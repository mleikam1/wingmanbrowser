import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/browser/protected_web_surface.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import '../signature/integrated_workspaces_test.dart' as shared;
import '../support/protected_test_support.dart';

void main() {
  testWidgets(
    'system Back prioritizes native history once and preserves nested routes',
    (tester) async {
      final h = await shared.mount(tester, size: const Size(430, 932));
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      ProtectedWebController? engine;
      try {
        final live = (await tester.runAsync(
          () => LiveBrowsingPolicy.load(bundle: LocalCatalogBundle()),
        ))!;
        h.policy.configureLiveBrowsing(
          live,
          nativeAvailable: true,
          privateAvailable: true,
        );
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        await tester.pumpWidget(const SizedBox());
        final url = Uri.parse('https://www.nasa.gov/technology/');
        h.session.current.visitWebsite(url);
        await tester.pumpWidget(
          WingmanApp(
            state: h.state,
            policy: h.policy,
            signatures: h.services,
            session: h.session,
          ),
        );
        await tester.pumpAndSettle();
        var surface = tester.widget<ProtectedWebSurface>(
          find.byType(ProtectedWebSurface),
        );
        engine = ProtectedWebController(
          canOpen: (_) => true,
          onNavigation: (_) {},
        )..attach(401);
        surface.onController!(engine);
        surface.onStatus(
          ProtectedWebStatus(url: url, progress: 100, canGoBack: true),
        );
        await tester.pumpAndSettle();
        final position = h.session.current.position;
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(calls.where((call) => call.method == 'back'), hasLength(1));
        expect(h.session.current.position, position);
        await shared.tap(tester, find.byTooltip('Menu'));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(calls.where((call) => call.method == 'back'), hasLength(1));
        expect(h.session.current.position, position);
        surface = tester.widget<ProtectedWebSurface>(
          find.byType(ProtectedWebSurface),
        );
        surface.onStatus(ProtectedWebStatus(url: url, progress: 100));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(h.session.current.position, position - 1);
        expect(h.session.current.website, isNull);
        expect(calls.where((call) => call.method == 'back'), hasLength(1));
        expect(
          tester
              .widget<PopScope<Object?>>(find.byType(PopScope<Object?>))
              .canPop,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
        engine?.dispose();
        messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'native child token stays in memory and close returns to its opener only',
    (tester) async {
      final h = await shared.mount(tester, size: const Size(430, 932));
      try {
        final live = (await tester.runAsync(
          () => LiveBrowsingPolicy.load(bundle: LocalCatalogBundle()),
        ))!;
        h.policy.configureLiveBrowsing(
          live,
          nativeAvailable: true,
          privateAvailable: true,
        );
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        await tester.pumpWidget(const SizedBox());
        final url = Uri.parse('https://www.nasa.gov/technology/');
        h.session.current.visitWebsite(url);
        final opener = h.session.current;
        await tester.pumpWidget(
          WingmanApp(
            state: h.state,
            policy: h.policy,
            signatures: h.services,
            session: h.session,
          ),
        );
        await tester.pumpAndSettle();
        var surface = tester.widget<ProtectedWebSurface>(
          find.byType(ProtectedWebSurface),
        );
        surface.onCloseRequested!(); // An ordinary tab cannot be script-closed.
        expect(h.session.tabs, [opener]);
        surface.onNewWindowWithToken!(url, 'native-single-use-token');
        await tester.pumpAndSettle();
        expect(h.session.tabs.length, 2);
        final child = h.session.current;
        surface = tester.widget<ProtectedWebSurface>(
          find.byType(ProtectedWebSurface),
        );
        expect(surface.windowToken, 'native-single-use-token');
        expect(child.isPrivate, opener.isPrivate);
        surface.onCloseRequested!();
        await tester.pumpAndSettle();
        expect(h.session.tabs, [opener]);
        expect(h.session.current, opener);
        surface.onCloseRequested!(); // A stale child cannot close its opener.
        expect(h.session.tabs, [opener]);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
