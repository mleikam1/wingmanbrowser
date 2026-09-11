import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('wingman/protected-browser');
  const legacy = MethodChannel('wingman/browser');
  const query = 'running shoes';
  const canonical = 'https://safe.duckduckgo.com/lite/?q=running%20shoes&kp=1';

  testWidgets('native provider Strict search preserves its separate boundary', (
    tester,
  ) async {
    Future<int> mount(bool private) async {
      final created = Completer<int>();
      final params = {'tabId': 'strict-search-$private', 'private': private};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Platform.isAndroid
                ? AndroidView(
                    key: ValueKey(private),
                    viewType: 'wingman/protected-web',
                    creationParams: params,
                    creationParamsCodec: const StandardMessageCodec(),
                    onPlatformViewCreated: created.complete,
                  )
                : UiKitView(
                    key: ValueKey(private),
                    viewType: 'wingman/protected-web',
                    creationParams: params,
                    creationParamsCodec: const StandardMessageCodec(),
                    onPlatformViewCreated: created.complete,
                  ),
          ),
        ),
      );
      final watch = Stopwatch()..start();
      while (!created.isCompleted && watch.elapsed.inSeconds < 15) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(created.isCompleted, isTrue);
      return created.future;
    }

    Future<Map<String, Object?>> state(int id) async =>
        await native.invokeMapMethod<String, Object?>('state', {
          'viewId': id,
        }) ??
        {};
    Future<void> denied(String method, Map<String, Object?> args) async {
      await expectLater(
        native.invokeMethod<void>(method, args),
        throwsA(isA<PlatformException>()),
      );
    }

    var id = await mount(false);
    expect((await state(id))['hasRenderer'], isFalse);
    expect(
      (await native.invokeMapMethod<String, Object?>(
        'capabilities',
      ))?["strictSearchAvailable"],
      isFalse,
    );
    await denied('openSearch', {'viewId': id, 'query': query, 'requestId': 1});
    await legacy.invokeMethod<void>('clearData', {'cookies': true});
    await denied('openSearch', {'viewId': id, 'query': query, 'requestId': 1});
    await legacy.invokeMethod<void>('quarantineLegacyContent');
    final caps = await native.invokeMapMethod<String, Object?>('capabilities');
    expect(caps?['strictSearchAvailable'], isTrue);
    expect(caps?['privateAvailable'], isTrue);
    final prepared = await native.invokeMapMethod<String, Object?>('state');

    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    probe.listen((request) {
      requests++;
      request.response.write('owned positive control');
      unawaited(request.response.close());
    });
    addTearDown(() => probe.close(force: true));
    final target = 'http://127.0.0.1:${probe.port}/forbidden';
    final client = HttpClient();
    await (await (await client.getUrl(
      Uri.parse(target),
    )).close()).drain<void>();
    client.close(force: true);
    expect(requests, 1);
    requests = 0;

    var denials = 0;
    for (final value in [
      canonical,
      canonical.replaceFirst('kp=1', 'kp=-2'),
      'https://safe.duckduckgo.com/settings',
      'https://safe.duckduckgo.com/l/?uddg=${Uri.encodeComponent(target)}',
      'https://safe.duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2F',
      'https://duckduckgo.com/?q=running%20shoes&kp=-2',
    ]) {
      for (final method in ['open', 'reload']) {
        await denied(method, {'viewId': id, 'url': value, 'requestId': 1});
        denials++;
      }
    }
    for (final value in [
      '',
      ' ',
      '!safeoff running shoes',
      'running shoes !g',
      '%21safeoff',
      '%2521safeoff',
      '\uFF01safeoff',
      '\uFE57safeoff',
      '\uFF05\uFF12\uFF11safeoff',
      'running\\shoes',
      'running\nshoes',
      '\u202Eshoes',
      '%FF',
      'a' * 513,
      '😀' * 257,
    ]) {
      await denied('openSearch', {
        'viewId': id,
        'query': value,
        'requestId': 1,
      });
      denials++;
    }
    await denied('openSearch', {
      'viewId': id,
      'url': canonical,
      'requestId': 1,
    });
    expect((await state(id))['hasRenderer'], isFalse);
    expect(requests, 0);

    for (final private in [false, true]) {
      if (private) id = await mount(true);
      await native.invokeMethod<void>('openSearch', {
        'viewId': id,
        'query': query,
        'requestId': 1,
        // This forged URL cannot become navigation authority.
        'url': 'https://duckduckgo.com/?q=ignored&kp=-2',
        'approved': true,
      });
      final watch = Stopwatch()..start();
      Map<String, Object?> page = {};
      while (watch.elapsed.inSeconds < 60) {
        await tester.pump(const Duration(milliseconds: 250));
        page = await state(id);
        if (page['error'] != null) {
          expect(page['hasRenderer'], isFalse);
          fail(
            'Provider search was unavailable and failed closed. '
            'This run does not establish positive search rendering.',
          );
        }
        final styles =
            page[Platform.isAndroid
                ? 'loadedStyleSheetResponses'
                : 'externalStyleSheets'];
        if (page['isLoading'] == false &&
            page['progress'] == 100 &&
            (page['searchResultLinks'] as int? ?? 0) > 0 &&
            (styles as int? ?? 0) > 0) {
          break;
        }
      }
      expect(page['url'], canonical);
      expect(page['strictSearch'], isTrue);
      expect(page['private'], private);
      expect(page['javascript'], isFalse);
      expect(page['hasRenderer'], isTrue);
      expect(page['isLoading'], isFalse);
      expect(page['searchResultLinks'] as int?, greaterThan(0));
      expect(
        page[Platform.isAndroid
                ? 'loadedStyleSheetResponses'
                : 'externalStyleSheets']
            as int?,
        greaterThan(0),
      );
      if (Platform.isAndroid) {
        expect(page['engineNetworkBlocked'], isTrue);
        expect(page['networkRequests'], 2);
        expect(page['bytesReceived'] as int, lessThanOrEqualTo(1088 * 1024));
      }
      // Neither a stale request nor the old URL loader can authorize search.
      await denied('openSearch', {
        'viewId': id,
        'query': query,
        'requestId': 1,
      });
      await denied('open', {'viewId': id, 'url': canonical, 'requestId': 2});
      expect((await state(id))['requestId'], 1);
      debugPrint(
        'STRICT_SEARCH private=$private links=${page['searchResultLinks']} '
        'styles=${page[Platform.isAndroid ? 'loadedStyleSheetResponses' : 'externalStyleSheets']} '
        'javascript=false independentScope=true',
      );
      await native.invokeMethod<void>('setActive', {
        'viewId': id,
        'active': false,
      });
      expect((await state(id))['hasRenderer'], isFalse);
      await native.invokeMethod<void>('setActive', {
        'viewId': id,
        'active': true,
      });
      expect((await state(id))['hasRenderer'], isFalse);
      await native.invokeMethod<void>('close', {'viewId': id});
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
    await legacy.invokeMethod<void>('clearData', {
      'storage': true,
      'cookies': true,
      'cache': true,
    });
    final finished = await native.invokeMapMethod<String, Object?>('state');
    expect(finished?['views'], 0);
    if (Platform.isIOS) {
      expect(finished?['searchRuleCompilationCount'], 1);
      expect(
        finished?['searchRuleCompilationCount'],
        prepared?['searchRuleCompilationCount'],
      );
    } else {
      expect(finished?['profilePurgesPending'], 0);
      expect(finished?['profilePurgeFailed'], isFalse);
    }
    expect(requests, 0);
    debugPrint('STRICT_SEARCH nativeDenials=$denials forbiddenProbeRequests=0');
  });
}
