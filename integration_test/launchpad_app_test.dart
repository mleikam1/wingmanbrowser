import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/main.dart' as app;
import 'package:wingman_browser/signature/launchpad/launchpad.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var stage = 'startup';

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    final watch = Stopwatch()..start();
    while (!ready() && watch.elapsed < const Duration(seconds: 20)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (!ready()) {
      final startup = find.byType(app.StartupSurface);
      debugPrint(
        'LAUNCHPAD_APP boundedWait stage=$stage '
        'ownerPresent=${find.byType(app.WingmanApp).evaluate().isNotEmpty} '
        'startupPresent=${startup.evaluate().isNotEmpty} '
        'startupFailed=${startup.evaluate().isEmpty ? null : tester.widget<app.StartupSurface>(startup).failed}',
      );
    }
    expect(ready(), isTrue, reason: 'Bounded Launchpad application-state wait');
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    // Native IME animations can move a form action after ensureVisible returns.
    // Finish text entry first, then scroll and require a real hit-test target.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    if (target.evaluate().isEmpty) {
      final scrollable = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(
        target,
        250,
        scrollable: scrollable,
        maxScrolls: 80,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    if (target.hitTestable().evaluate().isEmpty) {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target.hitTestable());
    await tester.pumpAndSettle();
  }

  Future<void> home(WidgetTester tester) async {
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    if (find.byTooltip('Home').evaluate().isNotEmpty) {
      await tap(tester, find.byTooltip('Home').last);
    }
  }

  Future<void> revealTiles(WidgetTester tester) async {
    final all = find.widgetWithText(TextButton, 'Show all');
    if (all.evaluate().isNotEmpty) {
      await tap(tester, all);
    }
    final containing = find.textContaining('Show all ');
    if (containing.evaluate().isNotEmpty) {
      await tap(tester, containing.first);
    }
  }

  testWidgets('actual main Launchpad add edit folder open and durable reopen', (
    tester,
  ) async {
    final start = Stopwatch()..start();
    await app.main();
    await until(
      tester,
      () => find.byType(app.WingmanApp).evaluate().isNotEmpty,
    );
    if (find.text('Get started').evaluate().isNotEmpty) {
      await tap(tester, find.text('Get started'));
    }
    var owner = tester.widget<app.WingmanApp>(find.byType(app.WingmanApp));
    await until(tester, () => owner.signatures!.initialized);
    var controller = owner.signatures!.launchpad;
    expect(
      controller.ephemeral,
      isFalse,
      reason: 'This durable fixture runs the consumer edition.',
    );
    expect(controller.storageError, isNull);
    final original = controller.snapshot;
    final originalFields = original.toJson()..remove('setup');
    final candidates = owner.policy.catalog.where(
      (resource) =>
          !original.shortcuts.any(
            (s) => s.target == LaunchpadTarget.resource(resource.id),
          ) &&
          controller.eligibility
              .assess(LaunchpadTarget.resource(resource.id))
              .canOpen,
    );
    expect(
      candidates.isNotEmpty,
      isTrue,
      reason: 'Fixture needs an eligible resource not already pinned.',
    );
    final article = candidates.first;
    final marker = 'Launchpad native ${DateTime.now().microsecondsSinceEpoch}';
    final articleName = '$marker article';
    final renamedArticle = '$marker renamed';
    final folderName = '$marker folder';
    final siteName = '$marker site';
    final siteUrl = 'https://www.espn.com/nba/?wingman-fixture=$marker'
        .replaceAll(' ', '-');
    final created = <String>{};
    String? folderId;
    void collectOwned() {
      created.addAll(
        controller.snapshot.shortcuts
            .where(
              (s) =>
                  s.title.startsWith(marker) &&
                  !original.shortcuts.any((old) => old.id == s.id),
            )
            .map((s) => s.id),
      );
      folderId ??= controller.snapshot.folders
          .where(
            (f) =>
                f.title == folderName &&
                !original.folders.any((old) => old.id == f.id),
          )
          .firstOrNull
          ?.id;
    }

    debugPrint(
      'LAUNCHPAD_APP mainToReadyMs=${start.elapsedMilliseconds} '
      'platform=${Platform.operatingSystem} mode=debug-integration NOT-cold-start',
    );

    try {
      // Follow the actual search → article → page menu → pin preview path.
      stage = 'pin-article';
      await tap(tester, find.byKey(const ValueKey('home-search-entry')));
      await tap(tester, find.widgetWithText(ChoiceChip, 'Library'));
      await tester.enterText(
        find.byKey(const ValueKey('protected-search')),
        article.title,
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tap(tester, find.text(article.title));
      expect(find.byKey(ValueKey('article-${article.id}')), findsOneWidget);
      await tap(tester, find.byTooltip('Menu').last);
      await tap(tester, find.text('Add to Launchpad'));
      await tester.enterText(
        find.byKey(const ValueKey('launchpad-name')),
        articleName,
      );
      await tap(tester, find.byKey(const ValueKey('launchpad-save')));
      await until(
        tester,
        () => controller.snapshot.shortcuts.any((s) => s.title == articleName),
      );
      collectOwned();
      final articleId = controller.snapshot.shortcuts
          .singleWhere((s) => s.title == articleName)
          .id;
      expect(
        controller.snapshot.shortcuts
            .singleWhere((s) => s.id == articleId)
            .source,
        LaunchpadSource.currentPage,
      );

      await home(tester);
      await revealTiles(tester);
      final tile = find.byKey(ValueKey('launchpad-tile-$articleId'));
      await tap(tester, tile);
      expect(find.byKey(ValueKey('article-${article.id}')), findsOneWidget);

      // Edit and open in another real catalog tab through the accessible actions.
      stage = 'edit-and-open';
      await home(tester);
      await revealTiles(tester);
      await tester.ensureVisible(tile);
      await tester.longPress(tile);
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(TextButton, 'Edit'));
      await tester.enterText(
        find.byKey(const ValueKey('launchpad-name')),
        renamedArticle,
      );
      await tap(tester, find.byKey(const ValueKey('launchpad-save')));
      await until(
        tester,
        () =>
            controller.snapshot.shortcuts.any((s) => s.title == renamedArticle),
      );
      final tabsBefore = owner.session!.tabs.length;
      final opening = Stopwatch()..start();
      await tap(tester, find.text('Open in new tab'));
      opening.stop();
      expect(find.byKey(ValueKey('article-${article.id}')), findsOneWidget);
      expect(owner.session!.tabs.length, tabsBefore + 1);
      debugPrint(
        'LAUNCHPAD_APP openNewCatalogTabMs=${opening.elapsedMilliseconds} '
        'single-observation NOT-performance-guarantee',
      );

      await home(tester);
      stage = 'create-folder';
      await tap(tester, find.byKey(const ValueKey('launchpad-edit')));
      await tap(tester, find.text('New folder'));
      final folderField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Folder name',
      );
      await tester.enterText(folderField, folderName);
      await tap(tester, find.text('Save folder'));
      await until(
        tester,
        () => controller.snapshot.folders.any((f) => f.title == folderName),
      );
      collectOwned();
      await home(tester);
      await revealTiles(tester);
      await tester.ensureVisible(tile);
      await tester.longPress(tile);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Move to folder'));
      await tap(tester, find.widgetWithText(SimpleDialogOption, folderName));
      await until(
        tester,
        () =>
            controller.snapshot.shortcuts
                .singleWhere((s) => s.id == articleId)
                .folderId ==
            folderId,
      );

      // Explicit website entry is a visible inactive record, never a live page.
      stage = 'save-inactive-address';
      await home(tester);
      await tap(tester, find.byKey(const ValueKey('launchpad-add')));
      await tap(tester, find.text('Enter an address'));
      await tester.enterText(
        find.byKey(const ValueKey('launchpad-name')),
        siteName,
      );
      await tester.enterText(
        find.byKey(const ValueKey('launchpad-address')),
        siteUrl,
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Save this address as inactive'));
      await tap(tester, find.byKey(const ValueKey('launchpad-save')));
      await until(
        tester,
        () => controller.snapshot.shortcuts.any((s) => s.title == siteName),
      );
      collectOwned();
      final siteId = controller.snapshot.shortcuts
          .singleWhere((s) => s.title == siteName)
          .id;
      await home(tester);
      await revealTiles(tester);
      await tap(tester, find.byKey(ValueKey('launchpad-tile-$siteId')));
      expect(find.text(siteUrl), findsOneWidget);
      final openSite = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Open'),
      );
      expect(openSite.onPressed, isNull);
      expect(find.text('Allow once'), findsNothing);
      expect(find.text('Always allow'), findsNothing);
      final oldOrder = controller.snapshot.shortcuts
          .singleWhere((s) => s.id == siteId)
          .order;
      expect(oldOrder, greaterThan(0));
      await tap(tester, find.text('Move up'));
      await until(
        tester,
        () =>
            controller.snapshot.shortcuts
                .singleWhere((s) => s.id == siteId)
                .order ==
            oldOrder - 1,
      );

      // Actual native app UI must create a separate private Launchpad, without
      // reading or presenting the owner's new shortcut/folder records.
      stage = 'private-isolation';
      await home(tester);
      await tap(tester, find.byTooltip('Tabs (${owner.session!.tabs.length})'));
      await tap(tester, find.text('New private tab'));
      await until(
        tester,
        () => owner.session!.privateServices?.initialized == true,
      );
      expect(owner.session!.current.isPrivate, isTrue);
      expect(find.text(renamedArticle), findsNothing);
      expect(find.text(siteName), findsNothing);
      expect(find.text(folderName), findsNothing);
      expect(
        owner.session!.privateServices!.launchpad.snapshot.shortcuts,
        isEmpty,
      );
      expect(
        owner.session!.privateServices!.launchpad.snapshot.folders,
        isEmpty,
      );
      final privateIndex = owner.session!.tabs.length;
      await tap(tester, find.byTooltip('Tabs ($privateIndex)'));
      await tap(tester, find.byTooltip('Close tab $privateIndex'));
      await home(tester);
      expect(owner.session!.tabs.any((tab) => tab.isPrivate), isFalse);

      final savedJson = jsonEncode(controller.snapshot.toJson());
      stage = 'owner-teardown';
      await owner.signatures!.flush();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final reopening = Stopwatch()..start();
      stage = 'owner-reopen';
      await app.main();
      await until(
        tester,
        () => find.byType(app.WingmanApp).evaluate().isNotEmpty,
      );
      owner = tester.widget<app.WingmanApp>(find.byType(app.WingmanApp));
      await until(tester, () => owner.signatures!.initialized);
      controller = owner.signatures!.launchpad;
      expect(
        jsonEncode(controller.snapshot.toJson()) == savedJson,
        isTrue,
        reason:
            'Exact saved Launchpad choices survive actual SQLite/root reopen.',
      );
      expect(controller.snapshot.folderItems(folderId!).single.id, articleId);
      expect(
        controller.eligibility
            .assess(
              controller.snapshot.shortcuts
                  .singleWhere((s) => s.id == siteId)
                  .target,
            )
            .canOpen,
        isFalse,
      );
      final native = await const MethodChannel(
        'wingman/browser',
      ).invokeMapMethod<String, Object?>('capabilityState');
      expect(native?['contentViews'], 0);
      expect(native?['liveBrowsing'], isFalse);
      debugPrint(
        'LAUNCHPAD_APP rootReopenMs=${reopening.elapsedMilliseconds} '
        'pagePin=true titleEdit=true localOpen=true newTab=true folderMove=true '
        'reorder=true inactiveAddress=true privateOwnerDataHidden=true '
        'durableReopen=true views=0 '
        'platform=${Platform.operatingSystem} NOT-process-death',
      );
    } finally {
      stage = 'exact-fixture-cleanup';
      if (find.byType(app.WingmanApp).evaluate().isNotEmpty) {
        owner = tester.widget<app.WingmanApp>(find.byType(app.WingmanApp));
        controller = owner.signatures!.launchpad;
        collectOwned();
        for (final id in created) {
          if (controller.snapshot.shortcuts.any((s) => s.id == id)) {
            await controller.removeShortcut(id);
          }
        }
        if (folderId != null &&
            controller.snapshot.folders.any((f) => f.id == folderId)) {
          await controller.removeFolder(folderId!, removeContents: false);
        }
        await owner.signatures!.flush();
        final remainingFields = controller.snapshot.toJson()..remove('setup');
        expect(
          jsonEncode(remainingFields) == jsonEncode(originalFields),
          isTrue,
          reason:
              'Only exact test-created records are removed; unrelated original fields survive.',
        );
        final setupChanged = controller.snapshot.setup != original.setup;
        if (setupChanged) {
          expect(original.setup, LaunchpadSetup.notStarted);
          expect(controller.snapshot.setup, LaunchpadSetup.completed);
        }
        debugPrint(
          'LAUNCHPAD_APP cleanupExactShortcuts=${created.length} '
          'cleanupExactFolder=${folderId == null ? 0 : 1} '
          'unrelatedOriginalFieldsPreserved=true setupCompletedByTest=$setupChanged',
        );
      } else {
        debugPrint(
          'LAUNCHPAD_APP cleanupPending testOwnedIds=${created.join(',')} '
          'testOwnedFolder=${folderId ?? 'none'}',
        );
      }
      await tester.pumpWidget(const SizedBox());
    }
  });
}
