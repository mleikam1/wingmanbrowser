import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/presentation/settings/settings_screen.dart';
import 'package:wingman_browser/signature/signature_services.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/signature/workspaces/discovery_session.dart';
import 'package:wingman_browser/signature/workspaces/workspace_controller.dart';
import 'package:wingman_browser/signature/workspaces/workspace_screen.dart';
import '../signature/integrated_workspaces_test.dart' as shared;
import '../signature/workspace_navigation_races_test.dart'
    show PausedWorkspaceStore, mountRace;

// Private controllers deliberately replace all backing stores with memory.
// Pause the operation itself so this fixture retains that production boundary.
class _PausedPrivateWorkspace extends WorkspaceController {
  _PausedPrivateWorkspace()
    : super(
        store: MemorySignatureDocumentStore(),
        eligible: (_) => true,
        ephemeral: true,
      );

  Completer<void>? _gate;
  final entered = Completer<void>();

  Completer<void> pauseDetach() => _gate = Completer<void>();

  @override
  Future<void> detachTab(String taskId, String tabId) async {
    final gate = _gate;
    _gate = null;
    if (gate != null) {
      entered.complete();
      await gate.future;
    }
    await super.detachTab(taskId, tabId);
  }
}

class _PausedPrivateServices extends SignatureServices {
  _PausedPrivateServices()
    : super(
        store: MemorySignatureDocumentStore(),
        eligible: (_) => true,
        isPrivate: true,
      );

  late final _workspace = _PausedPrivateWorkspace();
  @override
  _PausedPrivateWorkspace get workspaces => _workspace;
  bool wasDisposed = false;

  @override
  void dispose() {
    wasDisposed = true;
    super.dispose();
  }
}

Future<void> _reviewSessionClear(WidgetTester tester) async {
  await shared.tap(tester, find.byTooltip('Settings'));
  await shared.tap(tester, find.text('Privacy & data'));
  await shared.tap(tester, find.text('This discovery session'));
  await shared.tap(tester, find.text('Review selected data'));
  expect(find.text('Clear selected data?'), findsOneWidget);
}

void main() {
  testWidgets(
    'pending selected session clear preserves newer normal/private tabs, active route and saved library',
    (tester) async {
      final store = PausedWorkspaceStore();
      final h = await mountRace(tester, store);
      try {
        await h.state.saveSettingsDurably(
          h.state.settings.copyWith(onboardingComplete: true),
        );
        await tester.pumpAndSettle();
        await h.state.setResourceBookmarked('moon-phases', true);
        await h.state.setResourceReading('moon-phases', true);
        final original = h.session.current;
        final task = await h.services.workspaces.createTask(
          'Captured session task',
        );
        await h.services.workspaces.associateTab(
          task,
          original.id,
          'moon-phases',
        );
        original.taskId = task;
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        final screen = tester.widget<SettingsScreen>(
          find.byType(SettingsScreen),
        );
        final gate = store.pauseNextWorkspaceWrite();
        final clear = screen.actions.onClearData({PrivacyDataCategory.session});
        await tester.pump();
        expect(store.entered!.isCompleted, isTrue);
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        navigator.popUntil((route) => route.isFirst);
        await tester.pumpAndSettle();
        final newer = DiscoveryTab(), private = DiscoveryTab(isPrivate: true);
        h.session.tabs.addAll([newer, private]);
        h.session.active = h.session.tabs.indexOf(private);
        h.session.query = 'Private draft remains';
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Newer private route')),
          ),
        );
        await tester.pumpAndSettle();
        gate.complete();
        final outcome = await clear;
        await tester.pumpAndSettle();
        expect(outcome.completed, {PrivacyDataCategory.session});
        expect(h.session.tabs, [newer, private]);
        expect(h.session.current, same(private));
        expect(h.session.query, 'Private draft remains');
        expect(h.services.workspaces.task(task)!.tabs, isEmpty);
        expect(h.state.protectedPreferences.bookmarkedIds, {'moon-phases'});
        expect(h.state.protectedPreferences.readingIds, {'moon-phases'});
        expect(find.text('Newer private route'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );
  testWidgets(
    'confirmed delayed clear never dismisses a newer route on the same originating tab',
    (tester) async {
      final store = PausedWorkspaceStore();
      final h = await mountRace(tester, store);
      try {
        await h.state.saveSettingsDurably(
          h.state.settings.copyWith(onboardingComplete: true),
        );
        await tester.pumpAndSettle();
        final original = h.session.current;
        final task = await h.services.workspaces.createTask('Same-tab clear');
        await h.services.workspaces.associateTab(
          task,
          original.id,
          'moon-phases',
        );
        original.taskId = task;
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Privacy & data'));
        await tester.tap(find.text('Privacy & data'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('This discovery session'));
        await tester.tap(find.text('This discovery session'));
        await tester.pump();
        await tester.ensureVisible(find.text('Review selected data'));
        await tester.tap(find.text('Review selected data'));
        await tester.pumpAndSettle();
        final gate = store.pauseNextWorkspaceWrite();
        await tester.tap(find.text('Clear selected'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(store.entered!.isCompleted, isTrue);
        final pending = h.session.pendingDataClear!;
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Newer same-tab route')),
          ),
        );
        await tester.pumpAndSettle();
        expect(h.session.current, same(original));
        gate.complete();
        final outcome = await pending;
        await tester.pumpAndSettle();
        expect(outcome.completed, {PrivacyDataCategory.session});
        expect(h.session.tabs.contains(original), isFalse);
        expect(find.text('Newer same-tab route'), findsOneWidget);
        expect(h.services.workspaces.task(task)!.tabs, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'private selected clear removes a newer same-tab Workspace and notes dialog before destroying its services',
    (tester) async {
      final h = await mountRace(tester, PausedWorkspaceStore());
      final privateServices = _PausedPrivateServices();
      await privateServices.initialize();
      h.session.privateServices = privateServices;
      try {
        await h.state.setResourceBookmarked('moon-phases', true);
        await shared.tap(tester, find.byTooltip('Tabs (1)'));
        await shared.tap(tester, find.text('New private tab'));
        final original = h.session.current;
        expect(original.isPrivate, isTrue);
        final model = privateServices.workspaces;
        final task = await model.createTask('PRIVATE_CLEAR_TASK');
        await model.updateTask(task, notes: 'PRIVATE_SAVED_NOTES');
        await model.associateTab(task, original.id, 'moon-phases');
        original.taskId = task;

        await _reviewSessionClear(tester);
        final gate = model.pauseDetach();
        await tester.tap(find.text('Clear selected'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(model.entered.isCompleted, isTrue);
        final pending = h.session.pendingDataClear!;

        await shared.home(tester);
        await shared.workspaces(tester);
        await shared.tap(tester, find.text('Finish Mode'));
        await shared.tap(tester, find.text('PRIVATE_CLEAR_TASK'));
        await shared.tap(tester, find.text('Edit notes'));
        expect(find.byType(WorkspaceScreen), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.enterText(
          find.byType(TextField).last,
          'PRIVATE_UNSAVED_DIALOG_NOTES',
        );
        expect(h.session.current, same(original));
        expect(privateServices.wasDisposed, isFalse);

        gate.complete();
        final outcome = await pending;
        await tester.pumpAndSettle();

        expect(outcome.completed, {PrivacyDataCategory.session});
        expect(outcome.failed, isEmpty);
        expect(h.session.tabs.any((tab) => tab.isPrivate), isFalse);
        expect(h.session.privateServices, isNull);
        expect(privateServices.wasDisposed, isTrue);
        expect(find.byType(WorkspaceScreen, skipOffstage: false), findsNothing);
        expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
        for (final text in [
          'PRIVATE_CLEAR_TASK',
          'PRIVATE_SAVED_NOTES',
          'PRIVATE_UNSAVED_DIALOG_NOTES',
        ]) {
          expect(find.text(text, skipOffstage: false), findsNothing);
          expect(
            (await h.store.readDocument('workspace')).toString(),
            isNot(contains(text)),
          );
        }
        expect(h.services.workspaces.snapshot.tasks, isEmpty);
        expect(h.state.protectedPreferences.bookmarkedIds, {'moon-phases'});
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'confirmed session clear completes after Shell teardown and retained session reopens coherently',
    (tester) async {
      final store = PausedWorkspaceStore();
      final h = await mountRace(tester, store);
      try {
        await h.state.setResourceBookmarked('moon-phases', true);
        final original = h.session.current;
        final task = await h.services.workspaces.createTask(
          'Clear after teardown',
        );
        await h.services.workspaces.associateTab(
          task,
          original.id,
          'moon-phases',
        );
        original.taskId = task;
        original.scrollOffsets['moon-phases'] = 200;

        await _reviewSessionClear(tester);
        h.session.query = 'Captured draft to clear';
        final gate = store.pauseNextWorkspaceWrite();
        await tester.tap(find.text('Clear selected'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(store.entered!.isCompleted, isTrue);
        final pending = h.session.pendingDataClear!;

        // Keep the owner session/services, as the root handoff gate does, while
        // disposing the entire shell, its Navigator and text controllers.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(h.session.pendingDataClear, same(pending));
        gate.complete();
        final outcome = await pending;
        await tester.pumpAndSettle();

        expect(outcome.completed, {PrivacyDataCategory.session});
        expect(outcome.failed, isEmpty);
        expect(h.session.pendingDataClear, isNull);
        expect(h.session.tabs, hasLength(1));
        expect(h.session.current, isNot(same(original)));
        expect(h.session.current.isPrivate, isFalse);
        expect(h.session.query, isEmpty);
        expect(original.scrollOffsets, isEmpty);
        expect(h.services.workspaces.task(task)!.tabs, isEmpty);
        expect(h.state.protectedPreferences.bookmarkedIds, {'moon-phases'});
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          WingmanApp(
            state: h.state,
            policy: h.policy,
            signatures: h.services,
            session: h.session,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Tabs (1)'), findsOneWidget);
        expect(find.text('Captured draft to clear'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'a captured normal page menu cannot save after delayed clear selects an existing private tab',
    (tester) async {
      final store = PausedWorkspaceStore();
      final h = await mountRace(tester, store);
      try {
        final original = h.session.current;
        await shared.tap(tester, find.byTooltip('Tabs (1)'));
        await shared.tap(tester, find.text('New private tab'));
        final private = h.session.current;
        final privateServices = h.session.privateServices;
        await shared.tap(tester, find.byTooltip('Tabs (2)'));
        await shared.tap(tester, find.text('Normal (1)'));
        await shared.tap(tester, find.text('Home'));
        expect(h.session.current, same(original));
        final task = await h.services.workspaces.createTask(
          'Captured menu task',
        );
        await h.services.workspaces.associateTab(
          task,
          original.id,
          'moon-phases',
        );
        original.taskId = task;
        await _reviewSessionClear(tester);
        final gate = store.pauseNextWorkspaceWrite();
        await tester.tap(find.text('Clear selected'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(store.entered!.isCompleted, isTrue);
        final pending = h.session.pendingDataClear!;
        original.visit('moon-phases');
        await shared.home(tester);
        await shared.tap(tester, find.byTooltip('Menu'));
        final menuBookmark = find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is Dialog || widget is BottomSheet,
          ),
          matching: find.text('Bookmark'),
        );
        expect(menuBookmark, findsOneWidget);
        gate.complete();
        expect((await pending).completed, {PrivacyDataCategory.session});
        await tester.pumpAndSettle();
        expect(h.session.current, same(private));
        expect(menuBookmark, findsOneWidget);
        await shared.tap(tester, menuBookmark);
        await h.state.flush();
        expect(h.state.protectedPreferences.bookmarkedIds, isEmpty);
        expect(h.state.protectedPreferences.readingIds, isEmpty);
        expect(h.session.privateServices, same(privateServices));
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );
}
