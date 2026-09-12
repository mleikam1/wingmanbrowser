import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/browser/protected_web_surface.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/components/browser_chrome.dart';
import 'package:wingman_browser/presentation/launchpad/launchpad.dart';
import 'package:wingman_browser/presentation/protection/policy_state_view.dart';
import 'package:wingman_browser/signature/launchpad/launchpad.dart';
import '../signature/integrated_workspaces_test.dart' as shared;
import '../support/protected_test_support.dart';

void main() {
  Future<void> enable(
    WidgetTester tester,
    shared.Harness h, {
    bool native = true,
  }) async {
    final live = (await tester.runAsync(
      () => LiveBrowsingPolicy.load(bundle: LocalCatalogBundle()),
    ))!;
    expect(live.errorCode, isNull);
    h.policy.configureLiveBrowsing(
      live,
      nativeAvailable: native,
      privateAvailable: native,
    );
    // A widget test checks the real Shell's routing without pretending to run a
    // native engine. Real HTML/image evidence lives in native integration tests.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ordinary addresses outside the reviewed catalog reach the consumer surface',
    (tester) async {
      final h = await shared.mount(tester);
      try {
        await enable(tester, h);
        await shared.tap(
          tester,
          find.byKey(const ValueKey('home-search-entry')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('protected-search')),
          'https://science.nasa.gov/moon/facts/',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(find.byType(ProtectedWebSurface), findsOneWidget);
        expect(h.session.current.website!.host, 'science.nasa.gov');
        final surface = tester.widget<ProtectedWebSurface>(
          find.byType(ProtectedWebSurface),
        );
        expect(surface.canOpen(Uri.parse('https://example.com/')), isTrue);
        surface.onNavigation(Uri.parse('https://example.com/'));
        await tester.pumpAndSettle();
        expect(find.byType(PolicyStateView), findsNothing);
        expect(h.session.current.website!.host, 'example.com');
        expect(h.services.launchpad.snapshot.shortcuts, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'additional restriction destroys the live surface and redacts its address',
    (tester) async {
      final h = await shared.mount(tester);
      try {
        await enable(tester, h);
        final actions = tester
            .widget<LaunchpadSection>(find.byType(LaunchpadSection))
            .actions;
        await actions.onOpen(
          const LaunchpadTarget.website('https://science.nasa.gov/moon/facts/'),
          newTab: true,
        );
        await tester.pumpAndSettle();
        expect(h.session.tabs, hasLength(2));
        expect(h.session.tabs.first.website, isNull);
        expect(find.byType(ProtectedWebSurface), findsOneWidget);
        await h.state.saveAdditionalRestrictions(
          AdditionalRestrictions(blockedResourceIds: ['nasa-moon']),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ProtectedWebSurface), findsNothing);
        expect(
          tester.widget<BrowserDock>(find.byType(BrowserDock)).resourceTitle,
          'Unavailable website',
        );
        await shared.tap(tester, find.byTooltip('Page information'));
        expect(find.text('Page information unavailable'), findsOneWidget);
        expect(find.textContaining('https://science.nasa.gov'), findsNothing);
      } finally {
        await h.close(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'a menu pin retains its committed snapshot across renderer resume',
    (tester) async {
      final h = await shared.mount(tester);
      try {
        await enable(tester, h);
        final actions = tester
            .widget<LaunchpadSection>(find.byType(LaunchpadSection))
            .actions;
        await actions.onOpen(
          const LaunchpadTarget.website('https://science.nasa.gov/moon/facts/'),
        );
        await tester.pumpAndSettle();
        final surface = tester.widget<ProtectedWebSurface>(
          find.byType(ProtectedWebSurface),
        );
        surface.onStatus(
          ProtectedWebStatus(
            url: surface.url,
            title: 'Moon facts',
            progress: 100,
          ),
        );
        await tester.pump();
        await shared.tap(tester, find.byTooltip('Menu'));
        // Closing a menu can resume a fresh native renderer before its action
        // runs. This must not discard the page already committed when opened.
        surface.onStatus(ProtectedWebStatus(url: surface.url, loading: true));
        await tester.pump();
        await shared.tap(tester, find.text('Add to Launchpad'));
        expect(find.byType(LaunchpadEditorScreen), findsOneWidget);
        expect(h.services.launchpad.snapshot.shortcuts, isEmpty);
      } finally {
        await h.close(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('absence of native capability keeps catalog addresses closed', (
    tester,
  ) async {
    final h = await shared.mount(tester);
    try {
      await enable(tester, h, native: false);
      final actions = tester
          .widget<LaunchpadSection>(find.byType(LaunchpadSection))
          .actions;
      await actions.onOpen(
        const LaunchpadTarget.website('https://science.nasa.gov/moon/facts/'),
        newTab: true,
      );
      await tester.pumpAndSettle();
      expect(h.session.tabs, hasLength(1));
      expect(h.session.current.website, isNull);
      expect(find.byType(ProtectedWebSurface), findsNothing);
      expect(find.byType(PolicyStateView), findsOneWidget);
    } finally {
      await h.close(tester);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
