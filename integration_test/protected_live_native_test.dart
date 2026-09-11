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
  const moon = 'https://science.nasa.gov/moon/facts/';

  testWidgets('native visual browsing keeps its independent policy boundary', (
    tester,
  ) async {
    final events = <Map<Object?, Object?>>[];
    native.setMethodCallHandler((call) async {
      if (call.method == 'pageState' && call.arguments is Map) {
        events.add(Map<Object?, Object?>.from(call.arguments as Map));
      }
    });
    addTearDown(() => native.setMethodCallHandler(null));

    Future<int> mount(bool private, int key) async {
      final created = Completer<int>();
      final params = {'tabId': 'native-visual-$key', 'private': private};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Platform.isAndroid
                ? AndroidView(
                    key: ValueKey(key),
                    viewType: 'wingman/protected-web',
                    creationParams: params,
                    creationParamsCodec: const StandardMessageCodec(),
                    onPlatformViewCreated: created.complete,
                  )
                : UiKitView(
                    key: ValueKey(key),
                    viewType: 'wingman/protected-web',
                    creationParams: params,
                    creationParamsCodec: const StandardMessageCodec(),
                    onPlatformViewCreated: created.complete,
                  ),
          ),
        ),
      );
      final watch = Stopwatch()..start();
      while (!created.isCompleted &&
          watch.elapsed < const Duration(seconds: 15)) {
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

    Future<Map<String, Object?>> readyPage(int id) async {
      final watch = Stopwatch()..start();
      Map<String, Object?> latest = {};
      while (watch.elapsed < const Duration(seconds: 65)) {
        await tester.pump(const Duration(milliseconds: 250));
        latest = await state(id);
        if (latest['error'] != null) break;
        if (latest['isLoading'] == false &&
            latest['progress'] == 100 &&
            latest[Platform.isAndroid
                    ? 'decodedImageResponses'
                    : 'imagesComplete']
                is int &&
            (latest[Platform.isAndroid
                        ? 'decodedImageResponses'
                        : 'imagesComplete']
                    as int) >
                0) {
          if (Platform.isAndroid) {
            expect(latest['engineNetworkBlocked'], isTrue);
            expect(
              latest['bytesReceived'] as int,
              lessThanOrEqualTo(12 * 1024 * 1024),
            );
            expect(latest['networkRequests'] as int, lessThanOrEqualTo(80));
          } else {
            expect(
              latest['externalStyleSheets'] as int?,
              greaterThan(0),
              reason:
                  'The reviewed page must load an actual external stylesheet.',
            );
          }
          return latest;
        }
      }
      debugPrint('VISUAL pending state=$latest');
      fail(
        'The reviewed page did not render a decoded image within 65 seconds.',
      );
    }

    // The platform-view factory alone creates no live renderer.
    var viewId = await mount(false, 1);
    expect((await state(viewId))['hasRenderer'], isFalse);
    await expectLater(
      native.invokeMethod<void>('open', {
        'viewId': viewId,
        'url': moon,
        'requestId': 1,
      }),
      throwsA(isA<PlatformException>()),
    );
    expect((await state(viewId))['hasRenderer'], isFalse);

    await legacy.invokeMethod<void>('clearData', {'cookies': true});
    await expectLater(
      native.invokeMethod<void>('open', {
        'viewId': viewId,
        'url': moon,
        'requestId': 1,
      }),
      throwsA(isA<PlatformException>()),
    );
    await legacy.invokeMethod<void>('quarantineLegacyContent');
    final capabilities = await native.invokeMapMethod<String, Object?>(
      'capabilities',
    );
    expect(capabilities?['supported'], isTrue);
    expect(capabilities?['privateAvailable'], isTrue);
    final prepared = await native.invokeMapMethod<String, Object?>('state');
    if (Platform.isIOS) {
      expect(prepared?['preparedRuleSets'], 3);
      expect(prepared?['ruleCompilationCount'], 3);
    }

    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var probeRequests = 0;
    probe.listen((request) {
      probeRequests++;
      request.response.write('controlled positive control');
      unawaited(request.response.close());
    });
    addTearDown(() => probe.close(force: true));
    final address = Uri.parse('http://127.0.0.1:${probe.port}/forbidden');
    final client = HttpClient();
    await (await (await client.getUrl(address)).close()).drain<void>();
    client.close(force: true);
    expect(probeRequests, 1);
    probeRequests = 0;

    var denials = 0;
    for (final url in [
      address.toString(),
      'https://example.com/',
      'http://science.nasa.gov/moon/facts/',
      'https://science.nasa.gov/moon/facts/?arbitrary=1',
      'https://science.nasa.gov./moon/facts/',
      'https://science.nasa.gov:443/moon/facts/',
      'https://user@science.nasa.gov/moon/facts/',
      'https://science.nasa.gov/moon/../moon/facts/',
      'https://science.nasa.gov/moon/%66acts/',
      'https://www.espn.com/nba/team/_/name/chi/chicago-bulls',
      'https://www.walmart.com/browse/office-supplies/notebooks-pads/1229749_4796182',
      'javascript:alert(1)',
      'data:text/html,unreviewed',
      'file:///etc/hosts',
    ]) {
      await expectLater(
        native.invokeMethod<void>('open', {
          'viewId': viewId,
          'url': url,
          'requestId': 2,
          'approved': true,
          'policy': {'allow': true},
          'private': false,
        }),
        throwsA(isA<PlatformException>()),
      );
      denials++;
    }
    for (final method in [
      'loadHtml',
      'loadRequest',
      'evaluateJavaScript',
      'updatePolicy',
      'configure',
    ]) {
      await expectLater(
        native.invokeMethod<void>(method, {
          'viewId': viewId,
          'url': moon,
          'html': '<img src="$address">',
        }),
        throwsA(isA<PlatformException>()),
      );
      denials++;
    }
    expect((await state(viewId))['hasRenderer'], isFalse);
    expect(probeRequests, 0);

    await native.invokeMethod<void>('open', {
      'viewId': viewId,
      'url': moon,
      'requestId': 3,
    });
    final normal = await readyPage(viewId);
    expect(normal['url'], moon);
    expect(normal['javascript'], isFalse);
    expect(normal['hasRenderer'], isTrue);
    expect(normal['private'], isFalse);
    debugPrint('VISUAL normal=$normal');
    if (const bool.fromEnvironment('WINGMAN_VISUAL_CAPTURE')) {
      debugPrint('VISUAL captureReady=learning');
      await Future<void>.delayed(const Duration(seconds: 20));
    }
    if (Platform.isAndroid) {
      expect(normal['loadedImageResponses'] as int, greaterThan(0));
      expect(
        normal['bytesReceived'] as int,
        lessThanOrEqualTo(12 * 1024 * 1024),
      );
      expect(normal['blockedResources'] as int, greaterThan(0));
    }

    var revision = 3;
    final journeyImages = <String, Object?>{};
    for (final entry in {
      'sports': 'https://en.wikipedia.org/wiki/Chicago_Bulls',
      'shopping': 'https://www.adafruit.com/product/64',
      'moonOverview': 'https://science.nasa.gov/moon/',
    }.entries) {
      await native.invokeMethod<void>('open', {
        'viewId': viewId,
        'url': entry.value,
        'requestId': ++revision,
      });
      final journey = await readyPage(viewId);
      expect(journey['url'], entry.value);
      expect(journey['javascript'], isFalse);
      journeyImages[entry.key] =
          journey[Platform.isAndroid
              ? 'decodedImageResponses'
              : 'imagesComplete'];
      debugPrint('VISUAL journey=${entry.key} state=$journey');
      if (const bool.fromEnvironment('WINGMAN_VISUAL_CAPTURE') &&
          entry.key != 'moonOverview') {
        debugPrint('VISUAL captureReady=${entry.key}');
        await Future<void>.delayed(const Duration(seconds: 20));
      }
    }

    await native.invokeMethod<void>('setActive', {
      'viewId': viewId,
      'active': false,
    });
    expect((await state(viewId))['hasRenderer'], isFalse);
    await native.invokeMethod<void>('setActive', {
      'viewId': viewId,
      'active': true,
    });
    expect(
      (await state(viewId))['hasRenderer'],
      isFalse,
      reason: 'Activation alone cannot restore a previous page.',
    );
    await native.invokeMethod<void>('close', {'viewId': viewId});
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    viewId = await mount(true, 2);
    await native.invokeMethod<void>('open', {
      'viewId': viewId,
      'url': moon,
      'requestId': 1,
    });
    final private = await readyPage(viewId);
    expect(private['private'], isTrue);
    expect(private['javascript'], isFalse);
    debugPrint('VISUAL private=$private');

    var privateRevision = 1;
    for (final entry in {
      'sports': 'https://en.wikipedia.org/wiki/Chicago_Bulls',
      'shopping': 'https://www.adafruit.com/product/64',
    }.entries) {
      await native.invokeMethod<void>('open', {
        'viewId': viewId,
        'url': entry.value,
        'requestId': ++privateRevision,
      });
      final journey = await readyPage(viewId);
      expect(journey['private'], isTrue);
      expect(journey['javascript'], isFalse);
      journeyImages['private-${entry.key}'] =
          journey[Platform.isAndroid
              ? 'decodedImageResponses'
              : 'imagesComplete'];
      debugPrint('VISUAL privateJourney=${entry.key} state=$journey');
    }

    // Handoff is deny-only and destroys the real page before its acknowledgement.
    await legacy.invokeMethod<void>('discardHandoffIncoming');
    expect((await state(viewId))['hasRenderer'], isFalse);
    await expectLater(
      native.invokeMethod<void>('open', {
        'viewId': viewId,
        'url': moon,
        'requestId': ++privateRevision,
      }),
      throwsA(isA<PlatformException>()),
    );
    final finalState = await legacy.invokeMapMethod<String, Object?>(
      'capabilityState',
    );
    expect(finalState?['contentViews'], 0);
    if (Platform.isAndroid) expect(finalState?['secureWindow'], isTrue);
    await native.invokeMethod<void>('close', {'viewId': viewId});
    await legacy.invokeMethod<Object?>('initialize');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(probeRequests, 0);
    if (Platform.isAndroid) {
      // A loaded Android profile cannot be unregistered until process restart.
      // The actual browsing-data purge must nevertheless finish successfully.
      await legacy.invokeMethod<void>('clearData', {
        'storage': true,
        'cookies': true,
        'cache': true,
      });
    }
    final completed = await native.invokeMapMethod<String, Object?>('state');
    if (Platform.isIOS) {
      expect(
        completed?['ruleCompilationCount'],
        prepared?['ruleCompilationCount'],
        reason:
            'Private visits cannot create persistent site-specific rule entries.',
      );
    } else {
      expect(completed?['profilePurgesPending'], 0);
      expect(completed?['profilePurgeFailed'], isFalse);
      expect(completed?['profilePurgesCompleted'], greaterThanOrEqualTo(7));
      debugPrint('VISUAL Android profileCleanup=$completed');
    }
    debugPrint(
      'VISUAL result nativeDenials=$denials fixtureRequests=0 normalImages=${normal[Platform.isAndroid ? 'decodedImageResponses' : 'imagesComplete']} privateImages=${private[Platform.isAndroid ? 'decodedImageResponses' : 'imagesComplete']} journeyImages=$journeyImages suspendDestroyed=true handoffDestroyed=true legacyRawChannelClosed=true',
    );
  });
}
