import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/signature/signature_services.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/signature/workspaces/discovery_session.dart';
import 'package:wingman_browser/signature/workspaces/workspace_controller.dart';
import 'package:wingman_browser/signature/workspaces/workspace_screen.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import 'package:wingman_browser/state/browser_state.dart';
import '../support/protected_test_support.dart';

class Harness {
  Harness(this.policy, this.state, this.services, this.session, this.store);
  final PolicyRuntime policy;
  final BrowserState state;
  final SignatureServices services;
  final DiscoverySession session;
  final MemorySignatureDocumentStore store;
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    services.dispose();
    state.dispose();
    policy.dispose();
  }
}

Future<Harness> mount(
  WidgetTester tester, {
  Size size = const Size(1024, 1000),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final policy = (await tester.runAsync(loadTestPolicy))!;
  final state = BrowserState(
    repository: MemoryBrowserRepository(),
    policyRuntime: policy,
  );
  await state.init();
  await state.saveSettingsDurably(
    state.settings.copyWith(onboardingComplete: true),
  );
  final store = MemorySignatureDocumentStore();
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
  return Harness(policy, state, services, session, store);
}

Future<void> tap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> workspaces(WidgetTester tester) async {
  await tap(tester, find.byTooltip('Menu'));
  await tap(tester, find.text('Spaces & Finish Mode'));
}

Future<void> home(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  navigator.popUntil((route) => route.isFirst);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'all three chosen Spaces, actual notes editing, reorder, disable and restart restoration',
    (tester) async {
      final h = await mount(tester);
      await workspaces(tester);
      for (final kind in SpaceKind.values) {
        await tap(tester, find.text(kind.label));
        expect(
          find.text('Shown because you chose ${kind.label}.'),
          findsOneWidget,
        );
        await tap(tester, find.text('Edit notes'));
        await tester.enterText(
          find.byType(TextField).last,
          '${kind.name} owner note',
        );
        await tap(tester, find.text('Save'));
        expect(find.text('${kind.name} owner note'), findsOneWidget);
        await tap(tester, find.byTooltip('Workspaces'));
      }
      expect(h.services.workspaces.snapshot.spaces.length, 3);
      expect(
        h.services.workspaces.snapshot.spaces.every(
          (s) => s.savedIds.isNotEmpty,
        ),
        isTrue,
      );
      await tap(tester, find.byTooltip('Move Sports up'));
      expect(h.services.workspaces.snapshot.spaces[1].kind, SpaceKind.sports);
      await tap(tester, find.text('Show Spaces on Home'));
      await home(tester);
      expect(find.text('Your Spaces'), findsNothing);
      final restored = WorkspaceController(
        store: h.store,
        eligible: (_) => true,
      );
      await restored.initialize();
      expect(restored.snapshot.spaces.length, 3);
      expect(
        restored.snapshot.spaces.map((e) => e.notes),
        contains('learning owner note'),
      );
      expect(restored.snapshot.spacesEnabled, isFalse);
      restored.dispose();
      expect(tester.takeException(), isNull);
      await h.close(tester);
    },
  );

  testWidgets(
    'Finish confirmation closes actual owned tab only and undo restores an unowned tab',
    (tester) async {
      final h = await mount(tester);
      final owned = h.session.current..visit('moon-phases');
      final unrelated = DiscoveryTab()..visit('read-a-rock');
      h.session.tabs.add(unrelated);
      await workspaces(tester);
      await tap(tester, find.text('Finish Mode'));
      await tap(tester, find.text('Start a task'));
      await tester.enterText(
        find.byType(TextField).last,
        'Read the Moon guide',
      );
      await tap(tester, find.text('Save'));
      await tap(tester, find.text('Associate current tab'));
      final task = h.services.workspaces.activeTask!;
      expect(owned.taskId, task.id);
      await tap(tester, find.text('Pause'));
      expect(h.services.workspaces.task(task.id)!.status, FinishStatus.paused);
      await tap(tester, find.text('Resume task tabs'));
      expect(h.session.current.id, owned.id);
      await workspaces(tester);
      await tap(tester, find.text('Finish Mode'));
      await tap(tester, find.text(task.goal));
      await tap(tester, find.text('Finish'));
      expect(
        h.session.tabs.length,
        2,
      ); // opening dialog is not a destructive choice
      await tap(tester, find.text('Close only this task’s associated tabs'));
      await tap(tester, find.text('Finish task'));
      expect(h.session.tabs.map((t) => t.id), [unrelated.id]);
      expect(
        h.services.workspaces.task(task.id)!.savedIds,
        contains('moon-phases'),
      );
      await tap(tester, find.text('Undo'));
      expect(h.session.tabs.length, 2);
      expect(h.session.tabs.every((t) => t.taskId == null), isTrue);
      expect(tester.takeException(), isNull);
      await h.close(tester);
    },
  );

  testWidgets('detached tab remains open when its previous task finishes', (
    tester,
  ) async {
    final h = await mount(tester);
    final task = await h.services.workspaces.createTask('Detach first');
    await workspaces(tester);
    await tap(tester, find.text('Finish Mode'));
    await tap(tester, find.text('Detach first'));
    await tap(tester, find.text('Associate current tab'));
    await tap(tester, find.byTooltip('Detach task tab'));
    expect(h.session.current.taskId, isNull);
    expect(h.services.workspaces.task(task)!.tabs, isEmpty);
    final tabId = h.session.current.id;
    await tap(tester, find.text('Finish'));
    await tap(tester, find.text('Close only this task’s associated tabs'));
    await tap(tester, find.text('Finish task'));
    expect(h.session.current.id, tabId);
    await h.close(tester);
  });

  testWidgets(
    'private workspace choices and findings never appear in normal store or new private session',
    (tester) async {
      final h = await mount(tester);
      await h.services.workspaces.createSpace(
        SpaceKind.learning,
        name: 'OWNER_SECRET',
      );
      await tap(tester, find.byTooltip('Tabs (1)'));
      await tap(tester, find.text('New private tab'));
      await workspaces(tester);
      expect(find.text('OWNER_SECRET'), findsNothing);
      await tap(tester, find.text('Sports'));
      await tap(tester, find.text('Edit notes'));
      await tester.enterText(find.byType(TextField).last, 'PRIVATE_NOTE');
      await tap(tester, find.text('Save'));
      expect(
        h.session.privateServices!.workspaces.snapshot.spaces.single.notes,
        'PRIVATE_NOTE',
      );
      expect(
        (await h.store.readDocument('workspace')).toString(),
        isNot(contains('PRIVATE_NOTE')),
      );
      await home(tester);
      await tap(tester, find.byTooltip('Tabs (2)'));
      await tap(tester, find.byTooltip('Close tab 2'));
      expect(h.session.privateServices, isNull);
      await tap(tester, find.text('New private tab'));
      await workspaces(tester);
      expect(find.text('PRIVATE_NOTE'), findsNothing);
      expect(h.session.privateServices!.workspaces.snapshot.spaces, isEmpty);
      await h.close(tester);
    },
  );

  testWidgets(
    'finishing the last private task tab destroys its tools and offers no undo',
    (tester) async {
      final h = await mount(tester);
      await tap(tester, find.byTooltip('Tabs (1)'));
      await tap(tester, find.text('New private tab'));
      final private = h.session.current;
      final model = h.session.privateServices!.workspaces;
      final taskId = await model.createTask('PRIVATE_FINISH_GOAL');
      await workspaces(tester);
      await tap(tester, find.text('Finish Mode'));
      await tap(tester, find.text('PRIVATE_FINISH_GOAL'));
      await tap(tester, find.text('Associate current tab'));
      expect(private.taskId, taskId);
      await tap(tester, find.text('Finish'));
      await tap(tester, find.text('Close only this task’s associated tabs'));
      await tap(tester, find.text('Finish task'));
      expect(h.session.tabs.any((t) => t.isPrivate), isFalse);
      expect(h.session.privateServices, isNull);
      expect(find.byType(WorkspaceScreen), findsNothing);
      expect(find.text('PRIVATE_FINISH_GOAL'), findsNothing);
      expect(find.text('Undo'), findsNothing);
      expect(
        (await h.store.readDocument('workspace')).toString(),
        isNot(contains('PRIVATE_FINISH_GOAL')),
      );
      expect(tester.takeException(), isNull);
      await h.close(tester);
    },
  );

  testWidgets(
    'contextual local analysis reaches an actual receipt; policy invalidation hides saved resource previews',
    (tester) async {
      final h = await mount(tester);
      await tap(tester, find.byTooltip('Menu'));
      await tap(tester, find.text('Before You Commit'));
      await tap(tester, find.text('Use a practice example'));
      await tester.ensureVisible(find.text('Check this selection'));
      await tester.tap(find.text('Check this selection'));
      // Analyzer runs off the UI isolate and completion needs real asynchronous time.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pumpAndSettle();
      expect(
        h.services.journal.events.any(
          (e) =>
              e.activity == PrivacyActivity.localAnalysis &&
              e.outcome == PrivacyOutcome.completed,
        ),
        isTrue,
      );
      await home(tester);
      await tap(tester, find.text('Protection overview'));
      await tap(tester, find.text('Trust Receipt'));
      await tester.scrollUntilVisible(
        find.textContaining('Wingman analyzed this selection on your device.'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.textContaining('Wingman analyzed this selection on your device.'),
        findsOneWidget,
      );
      await home(tester);
      final id = await h.services.workspaces.createSpace(
        SpaceKind.homeProjects,
      );
      await workspaces(tester);
      await tap(tester, find.text('Home Projects').first);
      h.policy.repository.restrict('integration-expired');
      await tester.pumpAndSettle();
      expect(find.text('Measure before you plan'), findsNothing);
      expect(h.services.workspaces.space(id)!.savedIds, isNotEmpty);
      await h.close(tester);
    },
  );

  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    testWidgets('new Home and workspace controls fit $size at1.6x text', (
      tester,
    ) async {
      final h = await mount(tester, size: size, scale: 1.6);
      expect(tester.takeException(), isNull);
      await workspaces(tester);
      expect(find.byType(WorkspaceScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Home Projects'));
      final problem = tester.takeException();
      if (problem != null) {
        debugPrint(problem.toString());
      }
      expect(problem, isNull);
      await h.close(tester);
    });
  }
}
