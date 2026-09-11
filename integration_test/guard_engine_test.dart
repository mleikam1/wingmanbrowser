import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/browser/browser_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native raw channels cannot enable live content or old overrides', (
    tester,
  ) async {
    const channel = MethodChannel('wingman/browser');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      await request.response.close();
    });
    final address = 'http://127.0.0.1:${server.port}/unreviewed';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Native boundary fixture'))),
    );
    final methods = [
      'configure',
      'privateConfiguration',
      'prepareGuardNavigation',
      'updateGuardPolicy',
      'open',
      'loadUrl',
      'loadRequest',
      'navigate',
      'readArticle',
      'evaluateJavaScript',
      'runJavaScript',
      'evaluateForTesting',
      'chooseFiles',
      'requestPermissions',
      'download',
      'offerDownload',
      'openExternal',
      'launchUrl',
      'resume',
      'pageScale',
      'desktop',
      'find',
      'guardDecisionForTesting',
      'guardBenchmarkForTesting',
      'safeSearchForTesting',
      'terminateRendererForTesting',
      'privacyStateForTesting',
      'disablePublisherFirstPartyId',
    ];
    for (final role in ['consumer', 'family', 'student', 'guest', 'admin']) {
      for (final method in methods) {
        await expectLater(
          channel.invokeMethod<Object?>(method, {
            'id': 1,
            'url': address,
            'private': true,
            'tabId': 'legacy',
            'request': 2147483647,
            'method': 'POST',
            'role': role,
            'script': 'fetch("$address")',
            'filename': 'fixture.html',
            'types': ['camera', 'microphone', 'location'],
            'guardEnabled': false,
            'overridesLocked': false,
            'customAllow': ['127.0.0.1'],
            'allowOnce': {
              'legacy': ['127.0.0.1'],
            },
            'allowOnceExpires': {
              'legacy': {'127.0.0.1': 9999999999999},
            },
            'approved': true,
            'liveBrowsing': true,
            'debug': true,
          }),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'bundled_content_only',
            ),
          ),
        );
      }
    }
    expect(await channel.invokeMethod<bool>('privateAvailable'), isFalse);
    expect(await channel.invokeMethod<bool>('defaultBrowser'), isFalse);
    // The generated plugin's raw constructor channel must be absent as well.
    final constructor = Platform.isAndroid
        ? 'dev.flutter.pigeon.webview_flutter_android.WebView.pigeon_defaultConstructor'
        : 'dev.flutter.pigeon.webview_flutter_wkwebview.UIViewWKWebView.pigeon_defaultConstructor';
    expect(
      await BasicMessageChannel<Object?>(
        constructor,
        const StandardMessageCodec(),
      ).send([987654321, null]),
      isNull,
    );
    if (Platform.isAndroid) {
      const processText = MethodChannel('flutter/processtext');
      expect(
        await processText.invokeMapMethod<String, String>(
          'ProcessText.queryTextActions',
        ),
        isEmpty,
      );
      await expectLater(
        processText.invokeMethod<Object?>('ProcessText.processTextAction', [
          'unknown-processor',
          address,
          false,
        ]),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'bundled_content_only',
          ),
        ),
      );
    }
    await NativeBrowserService().quarantineLegacyContent();
    await channel.invokeMethod<void>('clearData', {
      'cookies': true,
      'cache': true,
      'storage': true,
    });
    final state = await channel.invokeMapMethod<String, Object?>(
      'capabilityState',
    );
    expect(state?['capability'], 'bundledPlainTextOnly');
    expect(state?['contentViews'], 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(requests, 0);
    debugPrint(
      'MANDATORY native methods=${methods.length * 5} rejected; plugin absent; cleanup complete; requests=0 views=0',
    );
    await server.close(force: true);
  });
}
