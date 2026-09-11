import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/browser/browser_engine.dart';
import 'package:wingman_browser/guard/guard_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'bundled-only boundary creates zero views and sends zero requests',
    (tester) async {
      const channel = MethodChannel('wingman/browser');
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests++;
        request.response.headers.contentType = ContentType.html;
        request.response.write('''<main>Unreviewed fixture</main>
<iframe src="/frame"></iframe><img src="/image"><video src="/media"></video>
<script>fetch('/fetch');new WebSocket('ws://127.0.0.1:${server.port}/socket');
navigator.serviceWorker.register('/worker');location='/redirect';</script>
<form action="/post" method="post"><button>Submit</button></form>
<a target="_blank" href="/popup">Popup</a>''');
        await request.response.close();
      });
      final origin = 'http://127.0.0.1:${server.port}';
      // Positive control proves this counter can observe real loopback traffic.
      final client = HttpClient();
      await (await (await client.getUrl(
        Uri.parse('$origin/probe'),
      )).close()).drain<void>();
      client.close(force: true);
      expect(requests, 1);
      requests = 0;
      var policyCalls = 0;
      var prompts = 0;
      var pageCallbacks = 0;
      var beforeLoads = 0;
      final engine = BrowserEnginePool(
        confirm: (_, _) async {
          prompts++;
          return true;
        },
        prompt: (_, _, _) async {
          prompts++;
          return 'synthetic';
        },
        onPageChanged: (_, _, _, _) {
          pageCallbacks++;
        },
        onMessage: (_) {},
        navigationPolicy: (request) async {
          policyCalls++;
          return GuardDecision(
            action: GuardAction.allow,
            host: request.uri.host,
          );
        },
        beforeLoadForTesting: (_) async {
          beforeLoads++;
        },
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Boundary fixture'))),
      );
      final values = [
        '$origin/unknown',
        '$origin/redirect',
        '$origin/post',
        '$origin/popup',
        '$origin/download.exe',
        '$origin/auth',
        'https://unknown.example/',
        'data:text/html,<script>location="$origin/data"</script>',
        'blob:$origin/generated',
        'javascript:fetch("$origin/script")',
        'file:///private/fixture.html',
        'content://fixture/page',
        'mailto:fixture@example.test',
        'tel:123',
        'sms:123',
        'intent://fixture/#Intent;scheme=https;end',
        'about:blank',
      ];
      for (final private in [false, true]) {
        for (var i = 0; i < values.length; i++) {
          final tab = 'fixture-$private-$i';
          await engine.updateGuardPolicy({
            'guardEnabled': false,
            'customAllow': ['127.0.0.1'],
            'allowOnce': {
              tab: ['127.0.0.1'],
            },
            'overridesLocked': false,
            'allowOnceExpires': {
              tab: {'127.0.0.1': 9999999999999},
            },
            'approved': true,
            'role': 'admin',
            'liveBrowsing': true,
          });
          await engine.open(tabId: tab, url: values[i], isPrivate: private);
          await engine.retryGuard(tab);
          await engine.reload(tab);
          await engine.back(tab);
          await engine.forward(tab);
          await engine.setDesktopMode(tab, true);
          await engine.find(tab, 'text');
          await engine.findNext(tab);
          await engine.setPageScale(200);
          engine.activate(tab);
          engine.guardBlocked({'id': 1, 'url': values[i], 'request': 9999});
          await engine.navigationSettled(1, values[i]);
          expect(
            engine.status(tab).guardDecision?.action,
            GuardAction.blockUnsupported,
          );
          expect(engine.status(tab).guardDecision?.overrideAllowed, isFalse);
          expect(engine.status(tab).url, isEmpty);
          expect(engine.status(tab).title, isEmpty);
          expect(await engine.readArticle(tab), isNull);
          expect(engine.view(tab), isNull);
          await expectLater(
            engine.evaluateForTesting(tab, 'fetch("$origin/debug")'),
            throwsUnsupportedError,
          );
          await engine.close(tab);
        }
      }
      expect(BrowserEnginePool.supportsLiveBrowsing, isFalse);
      expect(engine.liveEngineCount, 0);
      expect(engine.liveTabIds, isEmpty);
      expect([policyCalls, prompts, pageCallbacks, beforeLoads], [0, 0, 0, 0]);
      await NativeBrowserService().setSensitiveContent(false);
      final state = await channel.invokeMapMethod<String, Object?>(
        'capabilityState',
      );
      expect(state?['liveBrowsing'], isFalse);
      expect(state?['contentViews'], 0);
      if (Platform.isAndroid) expect(state?['secureWindow'], isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(requests, 0);
      debugPrint(
        'MANDATORY boundary requests=0 views=0 legacyPolicyCalls=0 prompts=0',
      );
      engine.dispose();
      await server.close(force: true);
    },
  );
}
