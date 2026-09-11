import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/signature/signature_services.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/signature/workspaces/discovery_session.dart';
import 'package:wingman_browser/signature/workspaces/workspace_screen.dart';
import 'package:wingman_browser/state/browser_state.dart';
import '../support/protected_test_support.dart';
import 'integrated_workspaces_test.dart' as shared;

class PausedWorkspaceStore extends MemorySignatureDocumentStore {
  Completer<void>? _gate;
  Completer<void>? entered;
  Completer<void> pauseNextWorkspaceWrite() {
    entered = Completer<void>();
    return _gate = Completer<void>();
  }

  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) async {
    if (key == 'workspace' && _gate != null) {
      final gate = _gate!;
      _gate = null;
      entered!.complete();
      await gate.future;
    }
    await super.writeDocument(key, value);
  }
}

Future<shared.Harness> mountRace(
  WidgetTester tester,
  PausedWorkspaceStore store,
) async {
  tester.view.physicalSize = const Size(1024, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final policy = (await tester.runAsync(loadTestPolicy))!;
  final state = BrowserState(
    repository: MemoryBrowserRepository(),
    policyRuntime: policy,
  );
  await state.init();
  final services = SignatureServices(
    store: store,
    eligible: (id) => policy.policy
        .evaluate(
          PolicyRequest.bundled(id),
          additional: state.protectedPreferences.additional,
        )
        .isAllowed,
  );
  await services.initialize();
  final session = DiscoverySession();
  await tester.pumpWidget(
    WingmanApp(
      state: state,
      policy: policy,
      signatures: services,
      session: session,
    ),
  );
  await tester.pumpAndSettle();
  return shared.Harness(policy, state, services, session, store);
}

void main() {
  testWidgets(
    'dismissing tab sheet during detach clears ownership without closing tabs in a newer private scope',
    (tester) async {
      final store = PausedWorkspaceStore();
      final h = await mountRace(tester, store);
      try {
        final original = h.session.current..visit('moon-phases');
        final taskId = await h.services.workspaces.createTask(
          'Detach only the captured tab',
        );
        await shared.workspaces(tester);
        final page = tester.widget<WorkspaceScreen>(
          find.byType(WorkspaceScreen),
        );
        await page.onAssociateCurrentTab(taskId);
        expect(original.taskId, taskId);
        await shared.home(tester);
        await shared.tap(tester, find.byTooltip('Tabs (1)'));

        final gate = store.pauseNextWorkspaceWrite();
        await tester.tap(find.byTooltip('Close tab 1'));
        await tester.pump();
        expect(store.entered!.isCompleted, isTrue);
        await shared.tap(tester, find.text('New private tab'));
        final private = h.session.current;
        final privateServices = h.session.privateServices;
        expect(find.text('Session tabs'), findsNothing);

        gate.complete();
        await h.services.workspaces.flush();
        await tester.pumpAndSettle();

        expect(h.services.workspaces.task(taskId)!.tabs, isEmpty);
        expect(original.taskId, isNull);
        expect(h.session.tabs.map((tab) => tab.id), [original.id, private.id]);
        expect(h.session.current.id, private.id);
        expect(private.isPrivate, isTrue);
        expect(private.taskId, isNull);
        expect(h.session.privateServices, same(privateServices));
        expect(privateServices!.workspaces.snapshot.tasks, isEmpty);
        expect(h.session.canUndoTaskClosure, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'delayed association mutates its captured normal tab after user opens private tab',
    (tester) async {
      final store = PausedWorkspaceStore();
      final h = await mountRace(tester, store);
      try {
        final original = h.session.current..visit('moon-phases');
        final taskId = await h.services.workspaces.createTask(
          'Capture the originating tab',
        );
        await shared.workspaces(tester);
        final page = tester.widget<WorkspaceScreen>(
          find.byType(WorkspaceScreen),
        );
        final gate = store.pauseNextWorkspaceWrite();
        final pending = page.onAssociateCurrentTab(taskId);
        await tester.pump();
        expect(store.entered!.isCompleted, isTrue);
        await shared.home(tester);
        await shared.tap(tester, find.byTooltip('Tabs (1)'));
        await shared.tap(tester, find.text('New private tab'));
        final private = h.session.current;
        gate.complete();
        await pending;
        await tester.pumpAndSettle();
        expect(original.taskId, taskId);
        expect(private.isPrivate, isTrue);
        expect(private.taskId, isNull);
        expect(h.session.current.id, private.id);
        expect(
          h.services.workspaces.task(taskId)!.tabs.single.tabId,
          original.id,
        );
        expect(h.session.privateServices!.workspaces.snapshot.tasks, isEmpty);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'delayed task restoration cannot add or activate normal tabs after private navigation',
    (tester) async {
      final store = PausedWorkspaceStore();
      final h = await mountRace(tester, store);
      try {
        final taskId = await h.services.workspaces.createTask(
          'Restore only if still requested',
        );
        await h.services.workspaces.associateTab(
          taskId,
          'old-process-tab',
          'moon-phases',
        );
        await shared.workspaces(tester);
        final page = tester.widget<WorkspaceScreen>(
          find.byType(WorkspaceScreen),
        );
        final gate = store.pauseNextWorkspaceWrite();
        final pending = page.onResumeTask(h.services.workspaces.task(taskId)!);
        await tester.pump();
        expect(store.entered!.isCompleted, isTrue);
        await shared.home(tester);
        await shared.tap(tester, find.byTooltip('Tabs (1)'));
        await shared.tap(tester, find.text('New private tab'));
        final private = h.session.current;
        gate.complete();
        await pending;
        await tester.pumpAndSettle();
        expect(h.session.tabs, hasLength(2));
        expect(h.session.current.id, private.id);
        expect(h.session.current.isPrivate, isTrue);
        expect(h.session.tabs.every((t) => t.taskId == null), isTrue);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'popped and reopened workspace is not closed by an old delayed resume',
    (tester) async {
      final store = PausedWorkspaceStore();
      final h = await mountRace(tester, store);
      try {
        final taskId = await h.services.workspaces.createTask(
          'Do not steal a new route',
        );
        await h.services.workspaces.associateTab(
          taskId,
          'old-process-tab',
          'moon-phases',
        );
        await shared.workspaces(tester);
        final original = h.session.current.id;
        final page = tester.widget<WorkspaceScreen>(
          find.byType(WorkspaceScreen),
        );
        final gate = store.pauseNextWorkspaceWrite();
        final pending = page.onResumeTask(h.services.workspaces.task(taskId)!);
        await tester.pump();
        expect(store.entered!.isCompleted, isTrue);
        await shared.home(tester);
        await shared.workspaces(tester);
        gate.complete();
        await pending;
        await tester.pumpAndSettle();
        expect(find.byType(WorkspaceScreen), findsOneWidget);
        expect(h.session.current.id, original);
        expect(h.session.tabs, hasLength(1));
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'covering a workspace with a newer feature prevents delayed resume selection and pop',
    (tester) async {
      final store = PausedWorkspaceStore();
      final h = await mountRace(tester, store);
      try {
        final taskId = await h.services.workspaces.createTask(
          'Keep the newer feature open',
        );
        await h.services.workspaces.associateTab(
          taskId,
          'old-process-tab',
          'moon-phases',
        );
        await shared.workspaces(tester);
        final original = h.session.current.id;
        final page = tester.widget<WorkspaceScreen>(
          find.byType(WorkspaceScreen),
        );
        final gate = store.pauseNextWorkspaceWrite();
        final pending = page.onResumeTask(h.services.workspaces.task(taskId)!);
        await tester.pump();
        expect(store.entered!.isCompleted, isTrue);
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Newer feature route')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        gate.complete();
        await pending;
        await tester.pumpAndSettle();
        expect(find.text('Newer feature route'), findsOneWidget);
        expect(h.session.current.id, original);
        expect(h.session.tabs, hasLength(1));
      } finally {
        await h.close(tester);
      }
    },
  );
  testWidgets(
    'leaving during a durable finish clears captured ownership without late closure or route pop',
    (tester) async {
      final store = PausedWorkspaceStore();
      final h = await mountRace(tester, store);
      try {
        final owned = h.session.current..visit('moon-phases');
        final unrelated = DiscoveryTab()..visit('read-a-rock');
        h.session.tabs.add(unrelated);
        final taskId = await h.services.workspaces.createTask(
          'Finish without a late tab close',
        );
        await shared.workspaces(tester);
        await shared.tap(tester, find.text('Finish Mode'));
        await shared.tap(tester, find.text('Finish without a late tab close'));
        await shared.tap(tester, find.text('Associate current tab'));
        expect(owned.taskId, taskId);
        await shared.tap(tester, find.text('Finish'));
        await shared.tap(
          tester,
          find.text('Close only this task’s associated tabs'),
        );
        final gate = store.pauseNextWorkspaceWrite();
        await tester.tap(find.text('Finish task'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(store.entered!.isCompleted, isTrue);
        expect(
          h.services.workspaces.task(taskId)!.status.name,
          isNot('finished'),
        );

        // Leave the authorizing route while the original normal write is still
        // pending. A fresh private route must not be affected by its completion.
        await shared.home(tester);
        await shared.tap(tester, find.byTooltip('Tabs (2)'));
        await shared.tap(tester, find.text('New private tab'));
        final private = h.session.current;
        await shared.workspaces(tester);
        final privateServices = h.session.privateServices;
        gate.complete();
        await h.services.workspaces.flush();
        await tester.pumpAndSettle();

        expect(h.services.workspaces.task(taskId)!.status.name, 'finished');
        expect(
          h.services.workspaces.task(taskId)!.savedIds,
          contains('moon-phases'),
        );
        expect(owned.taskId, isNull);
        expect(h.session.tabs.map((t) => t.id), [
          owned.id,
          unrelated.id,
          private.id,
        ]);
        expect(h.session.current.id, private.id);
        expect(h.session.current.isPrivate, isTrue);
        expect(private.taskId, isNull);
        expect(find.byType(WorkspaceScreen), findsOneWidget);
        expect(h.session.privateServices, same(privateServices));
        expect(h.session.privateServices!.workspaces.snapshot.tasks, isEmpty);
        expect(find.text('Associated task tabs closed.'), findsNothing);
        expect(h.session.canUndoTaskClosure, isFalse);
      } finally {
        await h.close(tester);
      }
    },
  );
}
