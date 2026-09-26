import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/browser/protected_web_surface.dart';
import 'package:wingman_browser/main.dart' as app;
import 'package:wingman_browser/policy/policy_models.dart';
import 'package:wingman_browser/presentation/protection/policy_state_view.dart';

/// Exercises the ordinary entrypoint and production native asset resolver.
/// Benign loopback pages signal actual WK execution; no policy/engine injection.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('macOS ordinary app connects search, WebKit history and boundary', (
    tester,
  ) async {
    expect(Platform.isMacOS, isTrue);
    await binding.setSurfaceSize(const Size(1280, 850));
    addTearDown(() => binding.setSurfaceSize(null));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final signals = <String>{};
    server.listen((request) {
      request.response.headers.set('Cache-Control', 'no-store');
      if (request.uri.path == '/signal') {
        signals.add(request.uri.queryParameters['stage'] ?? '');
        request.response.statusCode = HttpStatus.noContent;
      } else if (request.uri.path == '/redirect') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          'Location',
          'http://gambling.protection.test/',
        );
      } else {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '''<!doctype html><title>Native app fixture</title>
          <h1>Wingman desktop fixture</h1>
          <input aria-label="Synthetic page input"><button>Native button</button>
          <script>
            window.addEventListener('load', () => {
              setTimeout(() => {
                history.pushState({}, '', '/history');
                fetch('/signal?stage=javascript-and-history');
              }, 0);
            });
            window.addEventListener('popstate', () => {
              fetch('/signal?stage=pop-' + location.pathname);
            });
          </script>''',
        );
      }
      unawaited(request.response.close());
    });
    addTearDown(() => server.close(force: true));
    final origin = 'http://127.0.0.1:${server.port}';

    Future<void> until(bool Function() ready, String stage) async {
      final timer = Stopwatch()..start();
      while (!ready() && timer.elapsed < const Duration(seconds: 90)) {
        // Let the desktop engine own frames while native AppKit content is
        // active. A forced test pump can wait indefinitely without a vsync.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!ready()) {
        debugPrint('MACOS_SIGNALS $signals');
        for (final view
            in tester.allRenderObjects.whereType<RenderAppKitView>()) {
          final state = await ProtectedWebBridge.channel
              .invokeMapMethod<String, Object?>('state', {
                'viewId': view.viewController.id,
              });
          final uri = Uri.tryParse(state?['url']?.toString() ?? '');
          if (uri?.host == '127.0.0.1') {
            debugPrint(
              'MACOS_NATIVE path=${uri?.path} back=${state?['canGoBack']} forward=${state?['canGoForward']} loading=${state?['isLoading']}',
            );
          }
        }
      }
      expect(ready(), isTrue, reason: stage);
      debugPrint('MACOS_STAGE $stage');
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder.hitTestable());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    await app.main();
    await until(
      () => find.byType(app.WingmanApp).evaluate().isNotEmpty,
      'startup',
    );
    if (find.text('Get started').evaluate().isNotEmpty) {
      await tap(find.text('Get started'));
    }
    final owner = tester.widget<app.WingmanApp>(find.byType(app.WingmanApp));
    await until(
      () => owner.signatures!.initialized && owner.policy.liveAvailable(),
      'real bundled mandatory protection prepared',
    );
    expect(
      (await ProtectedWebBridge.capabilities()).resourceCountersObservable,
      isFalse,
    );
    await until(
      () => find.byTooltip('New tab').hitTestable().evaluate().isNotEmpty,
      'expanded native chrome ready',
    );
    await tap(find.byTooltip('New tab').first);
    await until(
      () => find
          .byKey(const ValueKey('home-search-entry'))
          .hitTestable()
          .evaluate()
          .isNotEmpty,
      'new native normal tab',
    );

    Future<void> search(String url) async {
      await tap(find.byKey(const ValueKey('home-search-entry')));
      await until(
        () => find
            .byKey(const ValueKey('protected-search'))
            .hitTestable()
            .evaluate()
            .isNotEmpty,
        'search route',
      );
      await tester.enterText(
        find.byKey(const ValueKey('protected-search')),
        url,
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    await search('$origin/page');
    await until(
      () =>
          signals.contains('javascript-and-history') &&
          owner.session!.current.website?.path == '/history',
      'actual AppKitView WK page executed and history reached Flutter',
    );
    expect(find.byType(AppKitView), findsOneWidget);
    await until(
      () =>
          find
              .byTooltip('Reload protected page')
              .hitTestable()
              .evaluate()
              .isNotEmpty &&
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Back' &&
                    widget.onPressed != null,
              )
              .evaluate()
              .isNotEmpty,
      'committed document and enabled Back control',
    );
    await tap(find.byTooltip('Back').first);
    await until(
      () => owner.session!.current.website?.path == '/page',
      'native history back',
    );
    await tap(find.byTooltip('Forward').first);
    await until(
      () => owner.session!.current.website?.path == '/history',
      'native history forward',
    );
    await tap(find.text('Home').hitTestable().first);
    await until(
      () => find
          .byKey(const ValueKey('home-search-entry'))
          .hitTestable()
          .evaluate()
          .isNotEmpty,
      'return home',
    );
    await search('$origin/redirect');
    await until(
      () => find.byType(PolicyStateView).evaluate().isNotEmpty,
      'native redirect denial reaches branded boundary',
    );
    final boundary = tester.widget<PolicyStateView>(
      find.byType(PolicyStateView),
    );
    expect(boundary.decision.code, PolicyDecisionCode.blockMandatoryCategory);
    expect(boundary.decision.category, MandatoryCategory.gambling);
    expect(
      owner.session!.tabs
          .expand((t) => t.trail)
          .any((entry) => entry?.contains('gambling.protection.test') == true),
      isFalse,
    );
    debugPrint(
      'MACOS_APP actualMain=true bundledPolicy=true AppKitView=true '
      'nativeJavaScript=true historyBackForward=true redirectBoundary=true '
      'blockedAddressAbsent=true',
    );
    if (const bool.fromEnvironment('WINGMAN_MAC_QA_CAPTURE')) {
      await Future<void>.delayed(const Duration(seconds: 25));
    }
    await tap(find.text('Back to Home').hitTestable().first);
    await until(
      () => find
          .byKey(const ValueKey('home-search-entry'))
          .hitTestable()
          .evaluate()
          .isNotEmpty,
      'boundary returns to Home',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
