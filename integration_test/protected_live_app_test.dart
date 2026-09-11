import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/browser/protected_web_surface.dart';
import 'package:wingman_browser/main.dart' as app;
import 'package:wingman_browser/policy/policy_models.dart';
import 'package:wingman_browser/presentation/launchpad/launchpad.dart';
import 'package:wingman_browser/presentation/protection/policy_state_view.dart';
import 'package:wingman_browser/signature/launchpad/launchpad.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> until(
    WidgetTester tester,
    bool Function() ready,
    String stage,
  ) async {
    final watch = Stopwatch()..start();
    while (!ready() && watch.elapsed < const Duration(seconds: 60)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), isTrue, reason: 'Live application stage: $stage');
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        250,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
        maxScrolls: 80,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target.hitTestable());
    await tester.pump();
  }

  testWidgets(
    'actual native app opens a reviewed website, pins it and revokes its scope',
    (tester) async {
      await app.main();
      await until(
        tester,
        () => find.byType(app.WingmanApp).evaluate().isNotEmpty,
        'startup',
      );
      if (find.text('Get started').evaluate().isNotEmpty) {
        await tap(tester, find.text('Get started'));
      }
      final owner = tester.widget<app.WingmanApp>(find.byType(app.WingmanApp));
      await until(
        tester,
        () => owner.signatures!.initialized,
        'local services',
      );
      expect(owner.policy.liveAvailable(), isTrue);
      final controller = owner.signatures!.launchpad;
      final original = controller.snapshot.toJson()..remove('setup');
      final nasa = owner.policy.liveSites.firstWhere(
        (site) => site.id == 'nasa-moon',
      );
      final target = nasa.documents
          .map((d) => LaunchpadTarget.website(d.url))
          .firstWhere(
            (target) =>
                !controller.snapshot.shortcuts.any((s) => s.target == target) &&
                controller.eligibility.assess(target).canOpen,
          );
      final marker =
          'Live page fixture ${DateTime.now().microsecondsSinceEpoch}';
      final hadRestriction = owner
          .state
          .protectedPreferences
          .additional
          .blockedResourceIds
          .contains(nasa.id);
      String? created;
      try {
        await tap(tester, find.byKey(const ValueKey('home-search-entry')));
        await until(
          tester,
          () => find
              .byKey(const ValueKey('protected-search'))
              .hitTestable()
              .evaluate()
              .isNotEmpty,
          'search route ready',
        );
        await tester.enterText(
          find.byKey(const ValueKey('protected-search')),
          target.value,
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await until(
          tester,
          () => find.byType(ProtectedWebSurface).evaluate().isNotEmpty,
          'native surface',
        );
        await until(
          tester,
          () => find.byType(LinearProgressIndicator).evaluate().isNotEmpty,
          'native document loading',
        );
        await until(
          tester,
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'document completion',
        );
        expect(find.textContaining('could not'), findsNothing);
        expect(owner.session!.current.website.toString(), target.value);
        await tap(tester, find.byTooltip('Menu').last);
        await tester.pumpAndSettle();
        await tap(tester, find.text('Add to Launchpad'));
        await until(
          tester,
          () =>
              find.byType(LaunchpadEditorScreen).evaluate().isNotEmpty &&
              find
                  .byKey(const ValueKey('launchpad-name'))
                  .hitTestable()
                  .evaluate()
                  .isNotEmpty,
          'committed page pin',
        );
        await tester.enterText(
          find.byKey(const ValueKey('launchpad-name')),
          marker,
        );
        await tap(tester, find.byKey(const ValueKey('launchpad-save')));
        await until(
          tester,
          () => controller.snapshot.shortcuts.any((s) => s.title == marker),
          'pin saved',
        );
        created = controller.snapshot.shortcuts
            .singleWhere((s) => s.title == marker)
            .id;
        final pin = controller.snapshot.shortcuts.singleWhere(
          (s) => s.id == created,
        );
        expect(pin.target, target);
        expect(pin.source, LaunchpadSource.currentPage);
        expect(controller.eligibility.assess(pin.target).canOpen, isTrue);

        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .popUntil((r) => r.isFirst);
        await tester.pumpAndSettle();
        await tap(tester, find.byTooltip('Home').last);
        await tester.pumpAndSettle();
        final actions = tester
            .widget<LaunchpadSection>(find.byType(LaunchpadSection))
            .actions;
        final before = owner.session!.tabs.length;
        await actions.onOpen(target, newTab: true);
        await until(
          tester,
          () => find.byType(ProtectedWebSurface).evaluate().isNotEmpty,
          'pinned new tab',
        );
        expect(owner.session!.tabs.length, before + 1);
        await until(
          tester,
          () => find.byType(LinearProgressIndicator).evaluate().isNotEmpty,
          'reopened document loading',
        );
        await until(
          tester,
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'reopened document',
        );
        await owner.state.setAdditionalBoundary(
          resourceId: nasa.id,
          hidden: true,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ProtectedWebSurface), findsNothing);
        expect(controller.eligibility.assess(target).canOpen, isFalse);
        final revoked = owner.policy.policy.evaluate(
          PolicyRequest.navigation(Uri.parse(target.value)),
          additional: owner.state.protectedPreferences.additional,
        );
        expect(revoked.code, PolicyDecisionCode.blockAdditionalRestriction);
        await tap(tester, find.byTooltip('Home').last);
        await tester.pumpAndSettle();
        final revokedActions = tester
            .widget<LaunchpadSection>(find.byType(LaunchpadSection))
            .actions;
        await revokedActions.onOpen(target);
        await tester.pumpAndSettle();
        expect(find.byType(PolicyStateView), findsOneWidget);
        expect(find.byType(ProtectedWebSurface), findsNothing);
        debugPrint(
          'LIVE_APP platform=${Platform.operatingSystem} actualMain=true nativeDocumentCompleted=true committedPin=true newTab=true scopeRevocation=true noClassificationClaim=true',
        );
      } finally {
        created ??= controller.snapshot.shortcuts
            .where((s) => s.title == marker)
            .firstOrNull
            ?.id;
        if (created != null) await controller.removeShortcut(created);
        await owner.state.setAdditionalBoundary(
          resourceId: nasa.id,
          hidden: hadRestriction,
        );
        await owner.signatures!.flush();
        final after = controller.snapshot.toJson()..remove('setup');
        expect(
          jsonEncode(after),
          jsonEncode(original),
          reason: 'Only exact fixture pin is removed',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
