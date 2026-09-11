import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/launchpad/launchpad.dart';
import 'package:wingman_browser/presentation/app_route_observer.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/launchpad/launchpad.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import '../support/protected_test_support.dart';

class LaunchpadTestStore extends MemorySignatureDocumentStore {
  bool fail = false;
  Completer<void>? pause;
  int writes = 0;
  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) async {
    writes++;
    if (fail) throw StateError('PRIVATE_STORAGE_DETAIL');
    await pause?.future;
    await super.writeDocument(key, value);
  }
}

class Harness {
  Harness(this.controller, this.policy, this.store, this.signal, this.allowed);
  final LaunchpadController controller;
  final PolicyRuntime policy;
  final LaunchpadTestStore store;
  final ValueNotifier<int> signal;
  final Set<String> allowed;
  final navigator = GlobalKey<NavigatorState>();
  final opened = <(LaunchpadTarget, bool)>[];
  final spacePins = <LaunchpadTarget>[];
  bool alive = true;
  late final actions = LaunchpadActions(
    canContinue: () => alive,
    changes: signal,
    catalog: LaunchpadCatalog(resources: policy.catalog),
    push: (page) async {
      await navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
    },
    onOpen: (target, {bool newTab = false}) async {
      opened.add((target, newTab));
    },
    bookmarks: () => policy.catalog
        .where((r) => allowed.contains(r.id))
        .take(1)
        .map(
          (r) => LaunchpadPinDraft(
            title: r.title,
            target: LaunchpadTarget.resource(r.id),
            fromBookmark: true,
          ),
        )
        .toList(),
    onAddToSpace: (target) async {
      spacePins.add(target);
    },
  );
  Future<void> show(WidgetTester tester, Widget page) async {
    unawaited(actions.push(page));
    await tester.pumpAndSettle();
  }

  void dispose() {
    controller.dispose();
    policy.dispose();
    signal.dispose();
  }
}

Future<Harness> mountLaunchpad(
  WidgetTester tester, {
  bool private = false,
  LaunchpadTestStore? store,
  Size size = const Size(390, 812),
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final policy = (await tester.runAsync(loadTestPolicy))!;
  final allowed = policy.catalog.map((r) => r.id).toSet();
  final backing = store ?? LaunchpadTestStore();
  final controller = LaunchpadController(
    store: backing,
    ephemeral: private,
    eligibility: LaunchpadEligibilityService(
      resourceEligible: allowed.contains,
      resourceLookup: policy.resource,
    ),
    clock: () => DateTime.utc(2026, 9, 11, 12),
  );
  await controller.initialize();
  final h = Harness(controller, policy, backing, ValueNotifier(0), allowed);
  addTearDown(h.dispose);
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: h.navigator,
      navigatorObservers: [appRouteObserver],
      theme: WingmanTheme.make(dark ? Brightness.dark : Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LaunchpadSection(
              controller: controller,
              actions: h.actions,
              isPrivate: private,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'first-use multi-select saves chosen local tools and skip stays dismissed',
    (tester) async {
      final h = await mountLaunchpad(tester);
      await tap(tester, find.text('Browse suggested sites'));
      for (final id in ['tool-explore', 'tool-library']) {
        await tap(tester, find.byKey(ValueKey('launchpad-suggestion-$id')));
      }
      expect(find.text('2 selected'), findsOneWidget);
      await tap(tester, find.text('Add selected (2)'));
      expect(h.controller.snapshot.shortcuts, hasLength(2));
      expect(h.controller.snapshot.setup, LaunchpadSetup.completed);
      await h.controller.resetConfirmed();
      await h.show(
        tester,
        LaunchpadAddScreen(
          controller: h.controller,
          actions: h.actions,
          isPrivate: false,
          suggested: true,
          firstUse: true,
        ),
      );
      await tap(tester, find.text('Skip for now'));
      final reload = LaunchpadController(
        store: h.store,
        eligibility: h.controller.eligibility,
      );
      await reload.initialize();
      addTearDown(reload.dispose);
      expect(reload.snapshot.setup, LaunchpadSetup.dismissed);
      expect(reload.snapshot.shortcuts, hasLength(2));
    },
  );

  testWidgets(
    'custom address normalizes locally, requires inactive consent and rejects credentials',
    (tester) async {
      final h = await mountLaunchpad(tester);
      await tap(tester, find.byKey(const ValueKey('launchpad-add')));
      await tap(tester, find.text('Enter an address'));
      await tester.enterText(
        find.byKey(const ValueKey('launchpad-name')),
        'My sports',
      );
      await tester.enterText(
        find.byKey(const ValueKey('launchpad-address')),
        'espn.com/nba/?view=full#news',
      );
      await tester.pumpAndSettle();
      expect(find.text('https://espn.com/nba/?view=full#news'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('launchpad-save')));
      expect(h.controller.snapshot.shortcuts, isEmpty);
      expect(find.textContaining('Confirm that this address'), findsOneWidget);
      await tap(tester, find.text('Save this address as inactive'));
      await tap(tester, find.byKey(const ValueKey('launchpad-save')));
      expect(
        h.controller.snapshot.shortcuts.single.target.value,
        'https://espn.com/nba/?view=full#news',
      );
      expect(h.opened, isEmpty);
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await tap(
        tester,
        find.byKey(
          ValueKey(
            'launchpad-tile-${h.controller.snapshot.shortcuts.single.id}',
          ),
        ),
      );
      expect(find.text('Edit Launchpad'), findsOneWidget);
      expect(h.opened, isEmpty);
      await tap(tester, find.text('Edit'));
      await tester.enterText(
        find.byKey(const ValueKey('launchpad-address')),
        'https://name:secret@example.org',
      );
      await tap(tester, find.byKey(const ValueKey('launchpad-save')));
      expect(
        find.text('Enter an ordinary HTTPS website address.'),
        findsOneWidget,
      );
      expect(
        h.controller.snapshot.shortcuts.single.target.value,
        'https://espn.com/nba/?view=full#news',
      );
    },
  );

  testWidgets(
    'rename and initials preserve destination; changing to address invalidates resource availability',
    (tester) async {
      final h = await mountLaunchpad(tester);
      final entry = h.actions.catalog!.entries.firstWhere(
        (e) => e.target.kind == LaunchpadKind.resource,
      );
      final id = await h.controller.addShortcut(entry.draft());
      await h.show(
        tester,
        LaunchpadEditorScreen(
          controller: h.controller,
          actions: h.actions,
          isPrivate: false,
          shortcutId: id,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('launchpad-name')),
        'My chosen guide',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Or use initials'),
        'WM',
      );
      await tap(tester, find.byKey(const ValueKey('launchpad-save')));
      final renamed = h.controller.snapshot.shortcuts.single;
      expect(renamed.title, 'My chosen guide');
      expect(renamed.localIconKey, 'initials:WM');
      expect(renamed.target, entry.target);
      expect(renamed.catalogEntryId, entry.id);
      await h.show(
        tester,
        LaunchpadEditorScreen(
          controller: h.controller,
          actions: h.actions,
          isPrivate: false,
          shortcutId: id,
        ),
      );
      await tap(tester, find.text('Use a website address instead'));
      await tester.enterText(
        find.byKey(const ValueKey('launchpad-address')),
        'walmart.com',
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Save this address as inactive'));
      await tap(tester, find.byKey(const ValueKey('launchpad-save')));
      final changed = h.controller.snapshot.shortcuts.single;
      expect(changed.target.kind, LaunchpadKind.website);
      expect(changed.catalogEntryId, isNull);
      expect(h.controller.eligibility.assess(changed.target).canOpen, isFalse);
    },
  );

  testWidgets(
    'canceled and failed edits retain prior saved data and hide storage details',
    (tester) async {
      final h = await mountLaunchpad(tester);
      final id = await h.controller.addShortcut(
        LaunchpadDraft(
          title: 'Library',
          target: LaunchpadTarget.tool(LaunchpadTool.library),
        ),
      );
      await h.show(
        tester,
        LaunchpadEditorScreen(
          controller: h.controller,
          actions: h.actions,
          isPrivate: false,
          shortcutId: id,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('launchpad-name')),
        'Unsaved edit',
      );
      await tap(tester, find.text('Cancel'));
      expect(h.controller.snapshot.shortcuts.single.title, 'Library');
      await h.show(
        tester,
        LaunchpadEditorScreen(
          controller: h.controller,
          actions: h.actions,
          isPrivate: false,
          shortcutId: id,
        ),
      );
      h.store.fail = true;
      await tester.enterText(
        find.byKey(const ValueKey('launchpad-name')),
        'Failed edit',
      );
      await tap(tester, find.byKey(const ValueKey('launchpad-save')));
      expect(find.text('Change not saved'), findsOneWidget);
      expect(find.textContaining('PRIVATE_STORAGE_DETAIL'), findsNothing);
      expect(h.controller.snapshot.shortcuts.single.title, 'Library');
    },
  );

  testWidgets(
    'folder dialog keyboard teardown, move-out deletion and undo are coherent',
    (tester) async {
      final h = await mountLaunchpad(tester);
      final id = await h.controller.addShortcut(
        LaunchpadDraft(
          title: 'Local library',
          target: LaunchpadTarget.tool(LaunchpadTool.library),
        ),
      );
      await tap(tester, find.byKey(const ValueKey('launchpad-edit')));
      await tap(tester, find.text('New folder'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Folder name'),
        'Reading room',
      );
      await tap(tester, find.text('Save folder'));
      expect(tester.takeException(), isNull);
      final folder = h.controller.snapshot.folders.single;
      await tap(tester, find.text('Move to folder'));
      await tap(
        tester,
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('Reading room'),
        ),
      );
      expect(h.controller.snapshot.shortcuts.single.folderId, folder.id);
      final folderRow = find
          .ancestor(
            of: find.text('Reading room'),
            matching: find.byType(Padding),
          )
          .first;
      await tap(
        tester,
        find.descendant(of: folderRow, matching: find.text('Remove')),
      );
      await tap(tester, find.text('Move shortcuts to Launchpad'));
      expect(h.controller.snapshot.folders, isEmpty);
      expect(h.controller.snapshot.shortcuts.single.folderId, isNull);
      await tap(tester, find.text('Undo removal'));
      expect(h.controller.snapshot.folders.single.id, folder.id);
      expect(h.controller.snapshot.shortcuts.single.folderId, folder.id);
      expect(h.controller.snapshot.shortcuts.single.id, id);
    },
  );

  testWidgets(
    'visible non-drag reorder persists; remove and undo preserve other tiles',
    (tester) async {
      final h = await mountLaunchpad(tester);
      for (final tool in [LaunchpadTool.library, LaunchpadTool.explore]) {
        await h.controller.addShortcut(
          LaunchpadDraft(title: tool.label, target: LaunchpadTarget.tool(tool)),
        );
      }
      await tap(tester, find.byKey(const ValueKey('launchpad-edit')));
      await tap(tester, find.text('Move down').first);
      expect(h.controller.snapshot.rootItems.first.title, 'Learn');
      await tap(tester, find.text('Remove').first);
      expect(h.controller.snapshot.shortcuts.single.title, 'Library');
      await tap(tester, find.text('Undo removal'));
      final reload = LaunchpadController(
        store: h.store,
        eligibility: h.controller.eligibility,
      );
      await reload.initialize();
      addTearDown(reload.dispose);
      expect(reload.snapshot.rootItems.map((s) => s.title), [
        'Learn',
        'Library',
      ]);
    },
  );

  for (final inFolder in [false, true]) {
    testWidgets(
      'keyboard reorder retains the same item action in ${inFolder ? 'folder' : 'root'}',
      (tester) async {
        final h = await mountLaunchpad(tester);
        final folderId = inFolder
            ? await h.controller.createFolder('Reading')
            : null;
        for (final tool in [
          LaunchpadTool.explore,
          LaunchpadTool.library,
          LaunchpadTool.trustReceipt,
        ]) {
          await h.controller.addShortcut(
            LaunchpadDraft(
              title: tool.label,
              target: LaunchpadTarget.tool(tool),
              folderId: folderId,
            ),
          );
        }
        final movingId = inFolder
            ? await h.controller.addShortcut(
                LaunchpadDraft(
                  title: 'Check before choosing',
                  target: LaunchpadTarget.tool(LaunchpadTool.beforeYouCommit),
                  folderId: folderId,
                ),
              )
            : await h.controller.createFolder('My folder');
        await h.show(
          tester,
          LaunchpadManageScreen(
            controller: h.controller,
            actions: h.actions,
            isPrivate: false,
            folderId: folderId,
          ),
        );
        final actionKey = ValueKey('launchpad-move-up-$movingId');
        bool actionFocused() {
          var found = false;
          FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
            element,
          ) {
            if (element.widget.key == actionKey) {
              found = true;
            }
            return !found;
          });
          return found;
        }

        for (var i = 0; i < 80 && !actionFocused(); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(actionFocused(), isTrue);
        final originalFocus = FocusManager.instance.primaryFocus;
        List<String> itemIds() =>
            (folderId == null
                    ? h.controller.snapshot.rootItems
                    : h.controller.snapshot.folderItems(folderId))
                .map((item) => item.id)
                .toList();
        final original = itemIds();
        expect(original.last, movingId);
        // A real IndexedDB write can span frames; do not let the in-memory
        // adapter hide focus loss while the action is temporarily busy.
        final pendingWrite = inFolder ? null : Completer<void>();
        h.store.pause = pendingWrite;
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        if (pendingWrite != null) {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(itemIds(), original);
          expect(actionFocused(), isTrue);
          final writeCount = h.store.writes;
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(h.store.writes, writeCount);
          pendingWrite.complete();
          h.store.pause = null;
        }
        await tester.pumpAndSettle();
        expect(itemIds(), [original[0], original[1], movingId, original[2]]);
        expect(actionFocused(), isTrue);
        expect(FocusManager.instance.primaryFocus, same(originalFocus));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(itemIds(), [original[0], movingId, original[1], original[2]]);
        expect(actionFocused(), isTrue);
        expect(find.byType(LaunchpadEditorScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Organize keeps one stable panel for consecutive keyboard sibling moves',
    (tester) async {
      final h = await mountLaunchpad(tester);
      for (final tool in [
        LaunchpadTool.explore,
        LaunchpadTool.library,
        LaunchpadTool.trustReceipt,
      ]) {
        await h.controller.addShortcut(
          LaunchpadDraft(title: tool.label, target: LaunchpadTarget.tool(tool)),
        );
      }
      final movingId = await h.controller.createFolder('My reading folder');
      final original = h.controller.snapshot.rootItems
          .map((v) => v.id)
          .toList();
      await h.show(
        tester,
        LaunchpadManageScreen(
          controller: h.controller,
          actions: h.actions,
          isPrivate: false,
        ),
      );
      bool focused(Key key) {
        var found = false;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
          element,
        ) {
          if (element.widget.key == key) {
            found = true;
          }
          return !found;
        });
        return found;
      }

      Future<void> tabTo(Key key) async {
        for (var i = 0; i < 100 && !focused(key); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(focused(key), isTrue);
      }

      await tabTo(ValueKey('launchpad-organize-$movingId'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final panel = tester.widget<LaunchpadManageScreen>(
        find.byType(LaunchpadManageScreen),
      );
      expect(panel.itemId, movingId);
      expect(find.text('Organize'), findsNothing);
      for (final id in original.take(3)) {
        expect(find.byKey(ValueKey('launchpad-item-row-$id')), findsNothing);
      }
      final actionKey = ValueKey('launchpad-move-up-$movingId');
      await tabTo(actionKey);
      final originalFocus = FocusManager.instance.primaryFocus;
      for (final expectedIndex in [2, 1]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(h.controller.snapshot.rootItems[expectedIndex].id, movingId);
        expect(tester.widget(find.byType(LaunchpadManageScreen)), same(panel));
        expect(focused(actionKey), isTrue);
        expect(FocusManager.instance.primaryFocus, same(originalFocus));
        for (final id in original.take(3)) {
          expect(find.byKey(ValueKey('launchpad-item-row-$id')), findsNothing);
        }
      }
      expect(h.controller.snapshot.rootItems.map((v) => v.id), [
        original[0],
        movingId,
        original[1],
        original[2],
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'revocation immediately hides saved title and closes stale editor capability',
    (tester) async {
      final h = await mountLaunchpad(tester);
      final resource = h.policy.catalog.first;
      final id = await h.controller.addShortcut(
        LaunchpadDraft(
          title: 'Private custom resource title',
          target: LaunchpadTarget.resource(resource.id),
        ),
      );
      await h.show(
        tester,
        LaunchpadEditorScreen(
          controller: h.controller,
          actions: h.actions,
          isPrivate: false,
          shortcutId: id,
        ),
      );
      h.allowed.remove(resource.id);
      h.signal.value++;
      await tester.pumpAndSettle();
      expect(find.text('Resource eligibility changed'), findsOneWidget);
      expect(find.text('Private custom resource title'), findsNothing);
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Unavailable resource'), findsOneWidget);
      await tap(tester, find.byKey(ValueKey('launchpad-tile-$id')));
      expect(h.opened, isEmpty);
    },
  );

  testWidgets(
    'private editing never reads owner shortcuts or bookmark drafts',
    (tester) async {
      final store = LaunchpadTestStore();
      final owner = LaunchpadController(
        store: store,
        eligibility: LaunchpadEligibilityService(resourceEligible: (_) => true),
      );
      await owner.initialize();
      await owner.addShortcut(
        LaunchpadDraft(
          title: 'Owner-only title',
          target: LaunchpadTarget.tool(LaunchpadTool.library),
        ),
      );
      final writes = store.writes;
      owner.dispose();
      final h = await mountLaunchpad(tester, private: true, store: store);
      expect(find.text('Owner-only title'), findsNothing);
      await tap(tester, find.byKey(const ValueKey('launchpad-add')));
      await tap(tester, find.text('Choose from bookmarks'));
      expect(find.text('Owner bookmarks stay private'), findsOneWidget);
      expect(store.writes, writes);
      expect(h.controller.snapshot.shortcuts, isEmpty);
    },
  );

  testWidgets('closed origin cannot commit an address preview', (tester) async {
    final h = await mountLaunchpad(tester);
    await h.show(
      tester,
      LaunchpadEditorScreen(
        controller: h.controller,
        actions: h.actions,
        isPrivate: false,
        initialDraft: LaunchpadPinDraft(
          title: 'Local tool',
          target: LaunchpadTarget.tool(LaunchpadTool.library),
        ),
      ),
    );
    h.alive = false;
    await tap(tester, find.byKey(const ValueKey('launchpad-save')));
    expect(h.controller.snapshot.shortcuts, isEmpty);
  });

  testWidgets(
    'nonempty folder remove-contents choice and undo restore exact group',
    (tester) async {
      final h = await mountLaunchpad(tester);
      final folder = await h.controller.createFolder('Keep together');
      await h.controller.addShortcut(
        LaunchpadDraft(
          title: 'Library inside',
          target: LaunchpadTarget.tool(LaunchpadTool.library),
          folderId: folder,
        ),
      );
      await h.controller.addShortcut(
        LaunchpadDraft(
          title: 'Learn outside',
          target: LaunchpadTarget.tool(LaunchpadTool.explore),
        ),
      );
      await h.show(
        tester,
        LaunchpadManageScreen(
          controller: h.controller,
          actions: h.actions,
          isPrivate: false,
          itemId: folder,
        ),
      );
      await tap(tester, find.text('Remove'));
      await tap(tester, find.text('Remove folder and shortcuts'));
      expect(h.controller.snapshot.folders, isEmpty);
      expect(h.controller.snapshot.shortcuts.single.title, 'Learn outside');
      await tap(tester, find.text('Undo removal'));
      expect(h.controller.snapshot.folders.single.id, folder);
      expect(
        h.controller.snapshot.folderItems(folder).single.title,
        'Library inside',
      );
      expect(h.controller.snapshot.rootItems.map((i) => i.title), [
        'Keep together',
        'Learn outside',
      ]);
    },
  );

  testWidgets(
    'source choice is separate, reorder/hide persist, and Space pin calls explicit resource route',
    (tester) async {
      final h = await mountLaunchpad(tester);
      await h.show(
        tester,
        LaunchpadSourcesScreen(
          controller: h.controller,
          actions: h.actions,
          isPrivate: false,
          kind: LaunchpadCollection.learning,
        ),
      );
      final resourceEntries = h.actions.catalog!.entries
          .where((e) => e.target.kind == LaunchpadKind.resource)
          .take(2)
          .toList();
      for (final entry in resourceEntries) {
        await tap(
          tester,
          find.widgetWithText(CheckboxListTile, entry.displayName),
        );
      }
      expect(h.controller.snapshot.collections.single.sources, hasLength(2));
      expect(h.controller.snapshot.shortcuts, isEmpty);
      await tap(tester, find.byTooltip('Move source down').first);
      expect(
        h.controller.snapshot.collections.single.sources.first.target,
        resourceEntries.last.target,
      );
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await h.show(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: LaunchpadContentCollections(
              controller: h.controller,
              actions: h.actions,
              isPrivate: false,
            ),
          ),
        ),
      );
      await tap(tester, find.text('Add to a Space').first);
      expect(h.spacePins, [resourceEntries.last.target]);
      expect(h.opened, isEmpty);
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await h.show(
        tester,
        LaunchpadCollectionsScreen(
          controller: h.controller,
          actions: h.actions,
          isPrivate: false,
        ),
      );
      await tap(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('launchpad-collection-learning')),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(h.controller.snapshot.collections.single.visible, isFalse);
      final reload = LaunchpadController(
        store: h.store,
        eligibility: h.controller.eligibility,
      );
      await reload.initialize();
      addTearDown(reload.dispose);
      expect(reload.snapshot.collections.single.visible, isFalse);
      expect(reload.snapshot.collections.single.sources, hasLength(2));
    },
  );

  testWidgets(
    'restore suggestions asks first and never replaces current edits',
    (tester) async {
      final h = await mountLaunchpad(tester);
      await h.controller.addShortcut(
        LaunchpadDraft(
          title: 'My library name',
          target: LaunchpadTarget.tool(LaunchpadTool.library),
        ),
      );
      await h.controller.updatePreferences(
        density: LaunchpadDensity.comfortable,
        showCollections: false,
      );
      await h.show(
        tester,
        LaunchpadCustomizeScreen(
          controller: h.controller,
          actions: h.actions,
          isPrivate: false,
        ),
      );
      await tap(tester, find.text('Restore starter suggestions'));
      await tap(tester, find.text('Cancel'));
      expect(h.controller.snapshot.setup, LaunchpadSetup.completed);
      await tap(tester, find.text('Restore starter suggestions'));
      await tap(tester, find.text('Show suggestions'));
      expect(find.text('Choose your shortcuts'), findsOneWidget);
      expect(h.controller.snapshot.shortcuts.single.title, 'My library name');
      expect(h.controller.snapshot.density, LaunchpadDensity.comfortable);
      expect(h.controller.snapshot.showCollections, isFalse);
    },
  );

  testWidgets(
    'long press and keyboard-accessible visible edit reach the same actions',
    (tester) async {
      final h = await mountLaunchpad(tester);
      final id = await h.controller.addShortcut(
        LaunchpadDraft(
          title: 'My library',
          target: LaunchpadTarget.tool(LaunchpadTool.library),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(ValueKey('launchpad-tile-$id')));
      await tester.pumpAndSettle();
      expect(find.text('Edit Launchpad'), findsOneWidget);
      expect(find.text('Move to folder'), findsOneWidget);
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      bool focusedEdit() {
        var found = false;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
          element,
        ) {
          if (element.widget.key == const ValueKey('launchpad-edit')) {
            found = true;
          }
          return !found;
        });
        return found;
      }

      for (var i = 0; i < 20 && !focusedEdit(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focusedEdit(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Edit Launchpad'), findsOneWidget);
      for (final editable in tester.widgetList<EditableText>(
        find.byType(EditableText),
      )) {
        expect(editable.enableIMEPersonalizedLearning, isFalse);
      }
    },
  );

  testWidgets(
    'revoked selected source can be removed while another inactive source stays',
    (tester) async {
      final h = await mountLaunchpad(tester);
      final resource = h.policy.catalog.first;
      const website = LaunchpadTarget.website('https://www.espn.com/');
      await h.controller.setCollection(
        HomeCollectionPreference(
          kind: LaunchpadCollection.sports,
          order: 0,
          sources: [
            LaunchpadCollectionSource(
              title: 'Hidden revoked source',
              target: LaunchpadTarget.resource(resource.id),
            ),
            const LaunchpadCollectionSource(
              title: 'ESPN candidate',
              target: website,
            ),
          ],
        ),
        retainInactiveWebsite: true,
      );
      h.allowed.remove(resource.id);
      await h.show(
        tester,
        LaunchpadSourcesScreen(
          controller: h.controller,
          actions: h.actions,
          isPrivate: false,
          kind: LaunchpadCollection.sports,
        ),
      );
      expect(find.text('Hidden revoked source'), findsNothing);
      expect(find.text('Unavailable resource'), findsOneWidget);
      await tap(tester, find.byTooltip('Remove source').first);
      expect(
        h.controller.snapshot.collections.single.sources.single.target,
        website,
      );
      expect(find.text('Change not saved'), findsNothing);
    },
  );

  testWidgets('moving to current folder is a no-op without a storage error', (
    tester,
  ) async {
    final h = await mountLaunchpad(tester);
    await h.controller.addShortcut(
      LaunchpadDraft(
        title: 'Library',
        target: LaunchpadTarget.tool(LaunchpadTool.library),
      ),
    );
    await tap(tester, find.byKey(const ValueKey('launchpad-edit')));
    final writes = h.store.writes;
    await tap(tester, find.text('Move to folder'));
    await tap(
      tester,
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Your Launchpad'),
      ),
    );
    expect(h.store.writes, writes);
    expect(find.text('Change not saved'), findsNothing);
  });

  for (final interruption in ['route', 'background']) {
    testWidgets('queued edit does not revive after $interruption returns', (
      tester,
    ) async {
      final h = await mountLaunchpad(tester);
      h.store.pause = Completer<void>();
      final first = h.controller.updatePreferences(
        density: LaunchpadDensity.comfortable,
      );
      await tester.pump();
      await h.show(
        tester,
        LaunchpadEditorScreen(
          controller: h.controller,
          actions: h.actions,
          isPrivate: false,
          initialDraft: LaunchpadPinDraft(
            title: 'Canceled queued tool',
            target: LaunchpadTarget.tool(LaunchpadTool.library),
          ),
        ),
      );
      await tap(tester, find.byKey(const ValueKey('launchpad-save')));
      if (interruption == 'route') {
        await h.show(tester, const Scaffold(body: Text('Another route')));
        h.navigator.currentState!.pop();
        await tester.pumpAndSettle();
      } else {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
      }
      h.store.pause!.complete();
      await first;
      await h.controller.flush();
      await tester.pumpAndSettle();
      expect(h.controller.snapshot.shortcuts, isEmpty);
      expect(find.byKey(const ValueKey('launchpad-name')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
