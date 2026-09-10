import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wingman_browser/browser/browser_engine.dart';
import 'package:wingman_browser/guard/guard_models.dart';

const nativeChannel = MethodChannel('wingman/browser');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native Guard navigation, tracking, IDNA and private enforcement', (
    tester,
  ) async {
    final folder = Platform.isIOS
        ? await nativeChannel.invokeMethod<String>('localDataDirectory')
        : await getDatabasesPath();
    final dbPath = '$folder/guard-engine-smoke.db';
    await deleteDatabase(dbPath);
    final db = await openDatabase(dbPath);
    await db.execute(
      'CREATE TABLE guard_state(id INTEGER PRIMARY KEY, active_generation INTEGER, previous_generation INTEGER, active_version TEXT)',
    );
    await db.insert('guard_state', {
      'id': 1,
      'active_generation': 1,
      'active_version': 'fixture-1',
    });
    await db.execute(
      'CREATE TABLE guard_rules(generation INTEGER NOT NULL,host TEXT NOT NULL,kind TEXT NOT NULL,category TEXT NOT NULL,include_subdomains INTEGER NOT NULL,rule_id TEXT NOT NULL,PRIMARY KEY(generation,host,kind,category)) WITHOUT ROWID',
    );
    Future<void> rule(String host, String kind, String category) => db
        .insert('guard_rules', {
          'generation': 1,
          'host': host,
          'kind': kind,
          'category': category,
          'include_subdomains': 1,
          'rule_id': 'fixture-$kind',
        })
        .then((_) {});
    await rule('localhost', 'category', 'adult');
    await rule('scope.test', 'category', 'adult');
    await rule('threat.test', 'malware', 'malware');
    await rule('phishing.test', 'phishing', 'phishing');
    await rule('download.test', 'harmful-download', 'harmful-downloads');
    await rule('support.localhost', 'support', 'adult');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    final blockedBase = 'http://localhost:${server.port}';
    var blockedRequests = 0;
    var trackerRequests = 0;
    var raceRequests = 0;
    var replacementRequests = 0;
    var sameTargetRequests = 0;
    server.listen((request) async {
      if (request.uri.path == '/policy-race') raceRequests++;
      if (request.uri.path == '/replacement-a') replacementRequests++;
      if (request.uri.path == '/same-target') sameTargetRequests++;
      if (request.headers.host?.startsWith('localhost:') == true &&
          request.uri.path != '/tracker.js') {
        blockedRequests++;
      }
      if (request.uri.path == '/tracker.js') {
        trackerRequests++;
        request.response.headers.contentType = ContentType(
          'application',
          'javascript',
        );
        request.response.write('window.trackerLoaded = true;');
      } else if (request.uri.path == '/redirect' ||
          request.uri.path == '/redirect307') {
        request.response.statusCode = request.uri.path == '/redirect307'
            ? 307
            : 302;
        request.response.headers.set('Location', '$blockedBase/blocked-final');
      } else {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '''<!doctype html><html><head><meta name="viewport" content="width=device-width"><title>Guard fixture ${request.uri.path}</title></head><body>
<h1>Allowed Guard fixture</h1><a id="link" href="$blockedBase/link">Blocked link</a>
<a id="popup" href="$blockedBase/popup" target="_blank">Blocked popup</a>
<form id="post" action="$blockedBase/post" method="post"><input name="x" value="fixture"></form>
<form id="postRedirect" action="$base/redirect307" method="post"><input name="x" value="fixture"></form>
${request.uri.path == '/tracking' ? '<script src="$blockedBase/tracker.js"></script>' : ''}
</body></html>''',
        );
      }
      await request.response.close();
    });
    late BrowserEnginePool engine;
    Map<String, dynamic>? lastNativeBlock;
    final native = NativeBrowserService();
    await native.initialize(
      onIncomingUri: (_) {},
      onGuardBlocked: (event) {
        lastNativeBlock = Map<String, dynamic>.from(event);
        engine.guardBlocked(event);
      },
      onTrackersBlocked: (id, count) => engine.trackersBlocked(id, count),
      onRendererGone: (id) => engine.rendererGone(id),
      onNavigationSettled: (id, url) => engine.navigationSettled(id, url),
    );
    var dartPreflight = true;
    var forceDartBlock = false;
    final beforeLoadEntered = Completer<void>();
    final beforeLoadRelease = Completer<void>();
    final replacementEntered = Completer<void>();
    final replacementRelease = Completer<void>();
    final sameTargetEntered = Completer<void>();
    final sameTargetRelease = Completer<void>();
    var blocks = 0;
    var privateBlocks = 0;
    var trackers = 0;
    final notices = <String>[];
    engine = BrowserEnginePool(
      confirm: (_, _) async => false,
      prompt: (_, _, _) async => null,
      onPageChanged: (_, _, _, _) {},
      onMessage: notices.add,
      beforeLoadForTesting: (url) async {
        if (url.endsWith('/policy-race') && !beforeLoadEntered.isCompleted) {
          beforeLoadEntered.complete();
          await beforeLoadRelease.future;
        }
        if (url.endsWith('/replacement-a') && !replacementEntered.isCompleted) {
          replacementEntered.complete();
          await replacementRelease.future;
        }
        if (url.endsWith('/same-target') && !sameTargetEntered.isCompleted) {
          sameTargetEntered.complete();
          await sameTargetRelease.future;
        }
      },
      navigationPolicy: (request) async => GuardDecision(
        action: forceDartBlock
            ? GuardAction.blockCustomRule
            : dartPreflight && request.uri.host == 'localhost'
            ? GuardAction.blockCategory
            : GuardAction.allow,
        host: request.uri.host,
        category: GuardCategory.adult,
        overrideAllowed: true,
      ),
      onGuardBlock: (_, private) {
        blocks++;
        if (private) privateBlocks++;
      },
      onTrackersBlocked: (count, private) {
        if (!private) trackers += count;
      },
    );
    var active = 'normal';
    var config = <String, Object?>{
      'databasePath': dbPath,
      'guardEnabled': true,
      'enabledCategories': ['adult'],
      'customAllow': <String>[],
      'customBlock': <String>[],
      'focusHosts': <String>[],
      'focusCategories': <String>[],
      'overridesLocked': false,
      'allowOnce': <String, Object?>{},
      'blockHarmfulDownloads': true,
      'trackingEnabled': true,
      'trackingExceptions': <String>[],
      'trackerDomains': ['localhost'],
      'trackerVersion': 'fixture-1',
    };
    await engine.updateGuardPolicy(config);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: engine,
            builder: (_, _) {
              final ids = engine.liveTabIds;
              return ids.isEmpty
                  ? const SizedBox()
                  : IndexedStack(
                      index: ids.contains(active) ? ids.indexOf(active) : 0,
                      children: [
                        for (final id in ids)
                          KeyedSubtree(
                            key: ValueKey(id),
                            child: engine.view(id)!,
                          ),
                      ],
                    );
            },
          ),
        ),
      ),
    );
    Future<void> waitFor(bool Function() condition, String description) async {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (!condition() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(condition(), isTrue, reason: '$description; notices: $notices');
    }

    Future<void> openAllowed(
      String path, {
      String id = 'normal',
      bool private = false,
    }) async {
      active = id;
      await engine.open(tabId: id, url: '$base/$path', isPrivate: private);
      await tester.pump();
      await waitFor(
        () => !engine.status(id).isLoading && engine.status(id).progress == 100,
        'render $path',
      );
      expect(
        engine.status(id).guardDecision,
        isNull,
        reason:
            'Allowed fixture $path; status=${engine.status(id).url}; '
            'decision=${engine.status(id).guardDecision?.toJson()}; '
            'document=${await engine.evaluateForTesting(id, "location.href")}',
      );
      expect(engine.status(id).error, isNull);
    }

    Future<void> blocked(String label, {String id = 'normal'}) async {
      await waitFor(() => engine.status(id).guardDecision != null, label);
      expect(
        engine.status(id).guardDecision?.action,
        GuardAction.blockCategory,
      );
      expect(engine.status(id).error, isNull);
      expect(engine.status(id).isLoading, false);
      debugPrint('GUARD $label passed');
    }

    // No network: native standards conversion and signed-rule precedence.
    for (final pair in {
      'bücher.de': 'xn--bcher-kva.de',
      'faß.de': 'xn--fa-hia.de',
      'example。com': 'example.com',
      'ＡＢＣ.com': 'abc.com',
      '2001:0db8:0000:0000:0000:0000:0000:0001': '2001:db8::1',
      '[::1]': '::1',
      '::ffff:192.0.2.1': '::ffff:c000:201',
    }.entries) {
      expect(
        await nativeChannel.invokeMethod<String>('normalizeHost', {
          'host': pair.key,
        }),
        pair.value,
      );
    }
    for (final bad in [
      '.example.com',
      'bad..example',
      'user@example.com',
      'xn--.com',
      '127.1',
      '0x7f000001',
      'example.com..',
    ]) {
      expect(
        await nativeChannel.invokeMethod<String>('normalizeHost', {
          'host': bad,
        }),
        isNull,
        reason: bad,
      );
    }
    Future<Map?> nativeDecision(String url, {String? filename}) =>
        nativeChannel.invokeMethod<Map>('guardDecisionForTesting', {
          'url': url,
          'tabId': 'normal',
          'filename': filename,
        });
    expect(
      (await nativeDecision('https://threat.test'))?['action'],
      'blockMalware',
    );
    expect(
      (await nativeDecision('https://phishing.test'))?['action'],
      'blockPhishing',
    );
    expect(
      (await nativeDecision(
        'https://download.test',
        filename: 'notes.txt',
      ))?['action'],
      'blockHarmfulDownload',
    );
    expect(
      (await nativeDecision(
        'https://clean.test',
        filename: 'install.exe',
      ))?['action'],
      'requireAdditionalCheck',
    );
    expect(await nativeDecision('https://support.localhost'), isNull);
    expect(
      await nativeChannel.invokeMethod<String>('safeSearchForTesting', {
        'url': 'https://www.google.com/search?q=fixture&safe=off',
      }),
      contains('safe=active'),
    );
    final originalConfig = config;
    config = {
      ...config,
      'customBlock': ['scope.test', 'blocked.sub.scope.test', 'threat.test'],
      'customAllow': ['sub.scope.test', 'threat.test'],
    };
    await engine.updateGuardPolicy(config);
    expect(await nativeDecision('https://sub.scope.test'), isNull);
    expect(await nativeDecision('https://child.sub.scope.test'), isNull);
    expect(
      (await nativeDecision('https://sibling.scope.test'))?['action'],
      'blockCustomRule',
    );
    expect(
      (await nativeDecision('https://blocked.sub.scope.test'))?['action'],
      'blockCustomRule',
    );
    expect(
      (await nativeDecision('https://threat.test'))?['action'],
      'blockMalware',
    );
    config = {
      ...config,
      'customAllow': ['scope.test'],
    };
    await engine.updateGuardPolicy(config);
    expect(
      (await nativeDecision('https://scope.test'))?['action'],
      'blockCustomRule',
    );
    config = originalConfig;
    await engine.updateGuardPolicy(config);
    debugPrint('GUARD specific custom-rule scope and equal-host block passed');
    debugPrint('GUARD native policy and normalization passed');
    await engine.open(
      tabId: 'typed-block',
      url: '$blockedBase/typed',
      isPrivate: false,
    );
    await blocked('typed before view', id: 'typed-block');
    expect(engine.view('typed-block'), isNull);
    expect(blockedRequests, 0);
    await engine.close('typed-block');
    dartPreflight =
        false; // Remaining checks deliberately exercise native policy.
    await openAllowed('initial');
    await engine.evaluateForTesting(
      'normal',
      "document.getElementById('link').click(); true",
    );
    await blocked('link native');
    expect(engine.status('normal').canGoBack, true);
    await engine.back('normal');
    await waitFor(
      () =>
          engine.status('normal').guardDecision == null &&
          !engine.status('normal').isLoading,
      'blocked back',
    );
    await openAllowed('before-redirect');
    await engine.open(tabId: 'normal', url: '$base/redirect', isPrivate: false);
    await blocked('redirect native');
    await openAllowed('before-js');
    await engine.evaluateForTesting(
      'normal',
      "location.href='$blockedBase/javascript'; true",
    );
    await blocked('JavaScript native');
    await openAllowed('before-popup');
    if (Platform.isIOS) {
      await engine.evaluateForTesting(
        'normal',
        "document.getElementById('popup').click(); true",
      );
    } else {
      final y = await engine.evaluateForTesting(
        'normal',
        "document.getElementById('popup').getBoundingClientRect().top + 8",
      );
      final x = await engine.evaluateForTesting(
        'normal',
        "document.getElementById('popup').getBoundingClientRect().left + 8",
      );
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('engine-normal'))) +
            Offset((x as num).toDouble(), (y as num).toDouble()),
      );
    }
    await blocked('target blank native');
    await openAllowed('before-post');
    await engine.evaluateForTesting(
      'normal',
      "document.getElementById('post').submit(); true",
    );
    await blocked('POST native');
    final before307 = blockedRequests;
    await openAllowed('before-post-redirect');
    await engine.evaluateForTesting(
      'normal',
      "document.getElementById('postRedirect').submit(); true",
    );
    await blocked('POST redirect native');
    debugPrint(
      'GUARD POST redirect destination contacted: ${blockedRequests > before307}; final rendering blocked',
    );
    // Exact one-navigation host lease never bypasses threats or subdomains.
    config = {
      ...config,
      'allowOnce': {
        'normal': ['localhost', 'scope.test', 'threat.test'],
      },
      'allowOnceExpires': {
        'normal': {
          'localhost': DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'scope.test': DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'threat.test': DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
        },
      },
    };
    await engine.updateGuardPolicy(config);
    expect(await nativeDecision('$blockedBase/granted'), isNull);
    expect(
      (await nativeDecision('http://sub.scope.test'))?['action'],
      'blockCategory',
    );
    expect(
      (await nativeDecision('https://threat.test'))?['action'],
      'blockMalware',
    );
    await engine.retryGuard('normal');
    await waitFor(
      () =>
          engine.status('normal').guardDecision == null &&
          !engine.status('normal').isLoading,
      'allow once loads',
    );
    config = {...config, 'allowOnce': <String, Object?>{}};
    await engine.updateGuardPolicy(config);
    await engine.reload('normal');
    await blocked('expired grant');
    final staleNormalBlock = Map<String, dynamic>.from(lastNativeBlock!);
    await openAllowed('private-before-block', id: 'private', private: true);
    await engine.open(
      tabId: 'private',
      url: '$blockedBase/private',
      isPrivate: true,
    );
    await blocked('private native', id: 'private');
    expect(privateBlocks, greaterThan(0));
    await engine.close('private');
    final racingOpen = engine.open(
      tabId: 'race',
      url: '$base/policy-race',
      isPrivate: false,
    );
    await beforeLoadEntered.future;
    forceDartBlock = true;
    final beforeRaceConfig = config;
    config = {
      ...config,
      'customBlock': ['127.0.0.1'],
    };
    await engine.updateGuardPolicy(config);
    beforeLoadRelease.complete();
    await racingOpen;
    await waitFor(
      () =>
          engine.status('race').guardDecision?.action ==
          GuardAction.blockCustomRule,
      'policy changed during native creation',
    );
    expect(raceRequests, 0);
    forceDartBlock = false;
    config = beforeRaceConfig;
    await engine.updateGuardPolicy(config);
    await engine.close('race');
    debugPrint('GUARD stale native creation policy prevented network');
    active = 'replacement';
    final staleOpen = engine.open(
      tabId: active,
      url: '$base/replacement-a',
      isPrivate: false,
    );
    await replacementEntered.future;
    final newerOpen = engine.open(
      tabId: active,
      url: '$base/replacement-b',
      isPrivate: false,
    );
    await engine.updateGuardPolicy(config);
    replacementRelease.complete();
    await staleOpen;
    await newerOpen;
    await waitFor(
      () =>
          engine.status(active).url.endsWith('/replacement-b') &&
          !engine.status(active).isLoading,
      'newer destination wins policy retry',
    );
    await engine.open(
      tabId: active,
      url: '$base/replacement-b',
      isPrivate: false,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(engine.status(active).url, '$base/replacement-b');
    expect(replacementRequests, 0);
    final firstSame = engine.open(
      tabId: active,
      url: '$base/same-target',
      isPrivate: false,
    );
    await sameTargetEntered.future;
    final secondSame = engine.open(
      tabId: active,
      url: '$base/same-target',
      isPrivate: false,
    );
    sameTargetRelease.complete();
    await firstSame;
    await secondSame;
    await waitFor(
      () =>
          engine.status(active).url.endsWith('/same-target') &&
          !engine.status(active).isLoading,
      'same target superseded before load still loads',
    );
    expect(sameTargetRequests, 1);
    await engine.close(active);
    debugPrint('GUARD newer request and same-target activation preserved');

    // Category rules apply to navigation; tracker list independently blocks only third-party resources.
    await openAllowed('tracking');
    // Deliver an old native message after a newer request has committed. It
    // must not relabel the current allowed page or stop its resource loading.
    engine.guardBlocked(staleNormalBlock);
    expect(engine.status('normal').guardDecision, isNull);
    expect(engine.status('normal').url, '$base/tracking');
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      trackerRequests,
      0,
      reason: 'Tracker script must never reach fixture server',
    );
    if (Platform.isAndroid) expect(trackers, greaterThan(0));
    config = {
      ...config,
      'trackingExceptions': ['127.0.0.1'],
    };
    await engine.updateGuardPolicy(config);
    await engine.reload('normal');
    await waitFor(() => trackerRequests > 0, 'tracking site exception');
    expect(
      (await nativeDecision('$blockedBase/category-still-blocks'))?['action'],
      'blockCategory',
    );
    debugPrint(
      'GUARD tracker blocking and scoped exception passed; Android aggregate=$trackers',
    );
    config = {
      ...config,
      'customBlock': ['127.0.0.1'],
    };
    await engine.updateGuardPolicy(config);
    // Production Dart policy independently agrees with native, tested here by direct navigation.
    await engine.open(
      tabId: 'new-tab',
      url: '$base/new-tab-blocked',
      isPrivate: false,
    );
    await waitFor(
      () =>
          engine.status('new-tab').guardDecision?.action ==
          GuardAction.blockCustomRule,
      'new tab native guard',
    );
    expect(engine.liveEngineCount, lessThanOrEqualTo(3));
    expect(blocks, greaterThanOrEqualTo(9));
    await tester.pumpWidget(const SizedBox());
    for (final id in engine.liveTabIds) {
      await engine.close(id);
    }
    await engine.updateGuardPolicy({});
    engine.dispose();
    native.dispose();
    await db.close();
    await deleteDatabase(dbPath);
    await server.close(force: true);
    debugPrint('GUARD all native acceptance checks passed');
  });
}
