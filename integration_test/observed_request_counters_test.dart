import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Local benign HTML and the installed reserved `.test` policy fixture only.
/// There is no production policy override, external page, or page/native bridge.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('wingman/protected-browser');
  const legacy = MethodChannel('wingman/browser');

  testWidgets(
    'observed request outcomes stay scoped to their native renderer',
    (tester) async {
      final boundaries = <Map<Object?, Object?>>[];
      native.setMethodCallHandler((call) async {
        if (call.method == 'navigationBlocked' && call.arguments is Map) {
          boundaries.add(Map<Object?, Object?>.from(call.arguments as Map));
        }
      });
      addTearDown(() => native.setMethodCallHandler(null));
      await legacy.invokeMethod<void>('initialize');
      await legacy.invokeMethod<void>('quarantineLegacyContent');
      final capabilities = await native.invokeMapMethod<String, Object?>(
        'capabilities',
      );
      expect(capabilities?['supported'], isTrue);
      expect(capabilities?['resourceCountersObservable'], isTrue);
      expect(capabilities?['resourceCounterScope'], 'rendererLifetime');

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        final path = request.uri.path;
        request.response.headers.contentType = ContentType.html;
        request.response.headers.set('Cache-Control', 'no-store');
        final fixture = switch (path) {
          '/normal' =>
            '''
          <script>document.cookie='qaNormal=present; path=/';
          localStorage.setItem('qaNormal','present');
          document.title='normal-ready';</script>
          <img src="http://gambling.protection.test/one.png">
          <img src="http://gambling.protection.test/two.png">
        ''',
          '/private' =>
            '''
          <script>document.title=!document.cookie.includes('qaNormal') &&
          !localStorage.getItem('qaNormal') && !localStorage.getItem('qaPrivate')
          ? 'private-empty' : 'private-leak';
          localStorage.setItem('qaPrivate','present');</script>
          <img src="http://gambling.protection.test/private.png">
        ''',
          '/additional' =>
            '''
          <script>document.title='additional-ready';</script>
          <img src="http://additional-counter.protection.test/resource.png">
        ''',
          _ =>
            '''
          <script>document.title=document.cookie.includes('qaNormal') &&
          localStorage.getItem('qaNormal')==='present' &&
          !localStorage.getItem('qaPrivate') ? 'normal-restored' : 'normal-lost';
          </script>
        ''',
        };
        request.response.write('<!doctype html><html>$fixture</html>');
        unawaited(request.response.close());
      });
      addTearDown(() => server.close(force: true));

      Future<Map<String, Object?>> state(int id) async =>
          await native.invokeMapMethod<String, Object?>('state', {
            'viewId': id,
          }) ??
          {};

      Future<int> mount(
        int key,
        bool private, {
        List<String> blockedDomains = const [],
      }) async {
        final created = Completer<int>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AndroidView(
                key: ValueKey(key),
                viewType: 'wingman/protected-web',
                creationParams: {
                  'tabId': 'counter-fixture-$key',
                  'edition': 'consumer',
                  'private': private,
                  'blockedDomains': blockedDomains,
                },
                creationParamsCodec: const StandardMessageCodec(),
                onPlatformViewCreated: created.complete,
              ),
            ),
          ),
        );
        final watch = Stopwatch()..start();
        while (!created.isCompleted && watch.elapsed.inSeconds < 20) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(created.isCompleted, isTrue);
        return created.future;
      }

      Future<Map<String, Object?>> open(
        int id,
        String path,
        String title,
      ) async {
        await native.invokeMethod<void>('open', {
          'viewId': id,
          'requestId': 1,
          'url': 'http://127.0.0.1:${server.port}$path',
        });
        final watch = Stopwatch()..start();
        var current = await state(id);
        while ((current['title'] != title || current['isLoading'] != false) &&
            watch.elapsed.inSeconds < 25) {
          await tester.pump(const Duration(milliseconds: 100));
          current = await state(id);
        }
        expect(current['error'], isNull);
        expect(current['title'], title);
        expect(current['isLoading'], isFalse);
        return current;
      }

      var id = await mount(1, false);
      expect((await state(id))['blockedResources'], isNull);
      final normal = await open(id, '/normal', 'normal-ready');
      expect(normal['blockedResources'], 2);
      expect(normal['resourceCounterScope'], 'rendererLifetime');
      expect(normal['resourceCounterSaturated'], isFalse);
      for (var replay = 0; replay < 3; replay++) {
        expect((await state(id))['blockedResources'], 2);
      }
      await expectLater(
        native.invokeMethod<void>('open', {
          'viewId': id,
          'requestId': 2,
          'url': 'http://gambling.protection.test/direct',
        }),
        throwsA(isA<PlatformException>()),
      );
      // Top-level pre-navigation denials never impersonate intercepted requests.
      expect((await state(id))['blockedResources'], 2);
      await tester.pump();
      expect(boundaries.last['reasonCode'], 'blockMandatoryCategory');
      expect(boundaries.last['category'], 'gambling');
      expect(boundaries.last.containsKey('url'), isFalse);
      expect(boundaries.last.containsKey('title'), isFalse);
      for (final fixture in [
        (
          'http://security-threat.protection.test/',
          'blockSecurityThreat',
          'security-threat',
        ),
        ('file:///unsupported-fixture', 'blockUnsupportedCapability', null),
      ].indexed) {
        await expectLater(
          native.invokeMethod<void>('open', {
            'viewId': id,
            'requestId': fixture.$1 + 3,
            'url': fixture.$2.$1,
          }),
          throwsA(isA<PlatformException>()),
        );
        await tester.pump();
        expect(boundaries.last['reasonCode'], fixture.$2.$2);
        expect(boundaries.last['category'], fixture.$2.$3);
        expect(boundaries.last.containsKey('url'), isFalse);
        expect(boundaries.last.containsKey('title'), isFalse);
      }
      await native.invokeMethod<void>('close', {'viewId': id});

      if (capabilities?['privateAvailable'] == true) {
        id = await mount(2, true);
        final private = await open(id, '/private', 'private-empty');
        expect(private['blockedResources'], 1);
        await native.invokeMethod<void>('close', {'viewId': id});
        id = await mount(3, true);
        final freshPrivate = await open(id, '/private', 'private-empty');
        expect(freshPrivate['blockedResources'], 1);
        await native.invokeMethod<void>('close', {'viewId': id});
      } else {
        debugPrint('COUNTER_QA private unavailable in installed WebView');
      }

      id = await mount(4, false);
      final restored = await open(id, '/restored', 'normal-restored');
      expect(restored['blockedResources'], 0);
      await native.invokeMethod<void>('close', {'viewId': id});

      id = await mount(
        5,
        false,
        blockedDomains: ['additional-counter.protection.test'],
      );
      final additional = await open(id, '/additional', 'additional-ready');
      expect(additional['blockedResources'], 1);
      await expectLater(
        native.invokeMethod<void>('open', {
          'viewId': id,
          'requestId': 2,
          'url': 'http://additional-counter.protection.test/direct',
        }),
        throwsA(isA<PlatformException>()),
      );
      await tester.pump();
      expect(boundaries.last['reasonCode'], 'blockAdditionalRestriction');
      expect(boundaries.last['category'], isNull);
      expect(boundaries.last.containsKey('url'), isFalse);
      expect(boundaries.last.containsKey('title'), isFalse);
      expect((await state(id))['blockedResources'], 1);
      await native.invokeMethod<void>('close', {'viewId': id});
      await tester.pumpWidget(const SizedBox.shrink());
      debugPrint(
        'COUNTER_QA real interception, replay, reset, typed redacted denial passed',
      );
    },
    skip: !Platform.isAndroid,
  );
}
