import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/browser/protected_web_surface.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/components/wingman_task_panel.dart';
import 'package:wingman_browser/presentation/launchpad/launchpad.dart';
import 'package:wingman_browser/presentation/protection/policy_state_view.dart';
import 'package:wingman_browser/signature/launchpad/launchpad.dart';
import 'package:wingman_browser/signature/signature_services.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/signature/workspaces/discovery_session.dart';
import 'package:wingman_browser/signature/workspaces/workspace_controller.dart';
import 'package:wingman_browser/state/browser_state.dart';
import '../signature/integrated_workspaces_test.dart' as shared;
import '../support/protected_test_support.dart';

Future<shared.Harness> mountFocus(WidgetTester tester) async {
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
  await state.saveSettingsDurably(
    state.settings.copyWith(onboardingComplete: true),
  );
  final store = MemorySignatureDocumentStore();
  final services = SignatureServices(
    store: store,
    eligible: (id) =>
        policy.policy.evaluate(PolicyRequest.bundled(id)).isAllowed,
    websiteEligible: (uri) =>
        policy.policy.evaluate(PolicyRequest.navigation(uri)).isAllowed,
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
  final live = (await tester.runAsync(
    () => LiveBrowsingPolicy.load(bundle: LocalCatalogBundle()),
  ))!;
  policy.configureLiveBrowsing(
    live,
    nativeAvailable: true,
    privateAvailable: true,
  );
  // Real shell and policy routing; no native renderer or live network is claimed.
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  await tester.pumpAndSettle();
  return shared.Harness(policy, state, services, session, store);
}

void main() {
  testWidgets(
    'optional Continue dismisses only focus while mandatory denial stays non-overridable',
    (tester) async {
      final h = await mountFocus(tester);
      try {
        final task = await h.services.workspaces.createTask('Read a guide');
        await h.services.workspaces.setDistractionPreferences(
          enabled: true,
          sites: ['example.com', 'gambling.protection.test'],
        );
        final actions = tester
            .widget<LaunchpadSection>(find.byType(LaunchpadSection))
            .actions;
        await actions.onOpen(
          const LaunchpadTarget.website('https://example.com/'),
        );
        await tester.pumpAndSettle();
        expect(find.text('A moment for your goal'), findsOneWidget);
        expect(find.byType(ProtectedWebSurface), findsNothing);
        await shared.tap(tester, find.widgetWithText(TextButton, 'Continue'));
        expect(h.session.current.website?.host, 'example.com');
        expect(find.byType(ProtectedWebSurface), findsOneWidget);
        await actions.onOpen(
          const LaunchpadTarget.website('https://example.com/next'),
        );
        await tester.pumpAndSettle();
        expect(find.text('A moment for your goal'), findsNothing);
        await actions.onOpen(
          const LaunchpadTarget.website('https://gambling.protection.test/'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PolicyStateView), findsOneWidget);
        expect(find.text('Continue'), findsNothing);
        expect(find.text('A moment for your goal'), findsNothing);
        expect(
          h.session.current.website?.host,
          isNot('gambling.protection.test'),
        );
        await h.services.workspaces.updateTask(
          task,
          status: FinishStatus.paused,
        );
        await actions.onOpen(
          const LaunchpadTarget.website('https://gambling.protection.test/'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PolicyStateView), findsOneWidget);
        expect(find.text('Continue'), findsNothing);
        expect(
          (await h.store.readDocument('workspace')).toString(),
          isNot(contains('https://gambling.protection.test/')),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'nudge Save for later stores explicit allowed destination without navigating',
    (tester) async {
      final h = await mountFocus(tester);
      try {
        final task = await h.services.workspaces.createTask(
          'Stay with my plan',
        );
        await h.services.workspaces.setDistractionPreferences(
          enabled: true,
          sites: ['example.com'],
        );
        final actions = tester
            .widget<LaunchpadSection>(find.byType(LaunchpadSection))
            .actions;
        await actions.onOpen(
          const LaunchpadTarget.website('https://example.com/interesting'),
        );
        await tester.pumpAndSettle();
        await shared.tap(tester, find.text('Save for later'));
        expect(
          h.services.workspaces.task(task)!.savedPages.single.url,
          'https://example.com/interesting',
        );
        expect(h.session.current.website, isNull);
        expect(find.byType(ProtectedWebSurface), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'changing origin while a focus nudge is open cannot navigate or save into another session',
    (tester) async {
      final h = await mountFocus(tester);
      try {
        final task = await h.services.workspaces.createTask(
          'Captured normal goal',
        );
        await h.services.workspaces.setDistractionPreferences(
          enabled: true,
          sites: ['example.com'],
        );
        final actions = tester
            .widget<LaunchpadSection>(find.byType(LaunchpadSection))
            .actions;
        await actions.onOpen(
          const LaunchpadTarget.website('https://example.com/'),
        );
        await tester.pumpAndSettle();
        final staleContinue = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Continue'))
            .onPressed!;
        h.session.tabs.add(DiscoveryTab(isPrivate: true));
        h.session.active = h.session.tabs.length - 1;
        // Production tab selection emits its origin-change notification. The
        // harness directly owns the session, so notify the shell before testing
        // the already-captured callback; no old render object is tapped.
        await h.state.saveSettingsPatch(onboardingComplete: true);
        await tester.pumpAndSettle();
        expect(find.text('Captured normal goal'), findsNothing);
        expect(find.widgetWithText(TextButton, 'Continue'), findsNothing);
        expect(
          find.text('This tab has changed. The previous task is hidden.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        staleContinue();
        await tester.pumpAndSettle();
        expect(h.session.current.isPrivate, true);
        expect(h.session.current.website, isNull);
        expect(h.services.workspaces.task(task)!.savedPages, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'stale companion hides owner task text when the active session becomes private',
    (tester) async {
      final h = await shared.mount(tester, size: const Size(1440, 1000));
      try {
        final task = await h.services.workspaces.createTask(
          'OWNER_GOAL_SECRET',
        );
        await h.services.workspaces.updateTask(
          task,
          notes: 'OWNER_NOTES_SECRET',
        );
        h.session.current.taskId = task;
        await shared.tap(tester, find.byTooltip('Your Wingman'));
        expect(find.text('OWNER_GOAL_SECRET'), findsWidgets);
        final panel = tester.widget<WingmanTaskPanel>(
          find.byType(WingmanTaskPanel),
        );
        h.session.tabs.add(DiscoveryTab(isPrivate: true));
        h.session.active = h.session.tabs.length - 1;
        await h.state.saveSettingsPatch(onboardingComplete: true);
        await tester.pumpAndSettle();
        expect(panel.canContinue(), false);
        expect(find.text('OWNER_GOAL_SECRET'), findsNothing);
        expect(find.text('OWNER_NOTES_SECRET'), findsNothing);
        await expectLater(panel.onSave(task), throwsStateError);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );
  testWidgets(
    'shell lifecycle pauses focus timer and does not auto-resume after returning',
    (tester) async {
      final h = await shared.mount(tester);
      try {
        final task = await h.services.workspaces.createTask('A timed task');
        await h.services.workspaces.configureTimer(task, minutes: 25);
        await h.services.workspaces.setTimerRunning(task, true);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        await h.services.workspaces.flush();
        expect(h.services.workspaces.task(task)!.timer!.running, false);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(h.services.workspaces.task(task)!.timer!.running, false);
        expect(h.services.workspaces.task(task)!.status, FinishStatus.active);
        expect(tester.takeException(), isNull);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await h.close(tester);
      }
    },
  );
}
