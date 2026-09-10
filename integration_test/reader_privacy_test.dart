import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/browser/browser_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'local reader excludes hidden and form content; native capture and page size',
    (tester) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requestedResources = 0;
      server.listen((request) async {
        requestedResources++;
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '''<!doctype html><html><head><meta name="viewport" content="width=device-width"><title>Reader fixture</title></head><body>
<main><h1>A readable local article</h1><p>This is visible article text, already delivered to the browser. Reader should keep this paragraph, with enough words to provide a useful accessible reading example.</p>
<p>Another visible paragraph contains a <b>bold phrase</b> and normal article text.</p>
<form>FORM_SECRET<input value="INPUT_SECRET"><textarea>TEXTAREA_SECRET</textarea></form>
<section contenteditable="true">EDITABLE_SECRET</section><p hidden>HIDDEN_SECRET</p>
<section style="display:none"><p>PAYWALL_SECRET</p></section><p style="opacity:0">TRANSPARENT_SECRET</p>
<p style="filter:blur(5px)">BLURRED_SECRET</p>
<div style="height:10px;overflow:hidden"><p style="position:relative;top:100px">CLIPPED_SECRET</p></div>
<p aria-hidden="true">ARIA_SECRET</p><a href="https://example.test">A plain link label</a>
</main></body></html>''',
        );
        await request.response.close();
      });
      final notices = <String>[];
      final engine = BrowserEnginePool(
        confirm: (_, _) async => false,
        prompt: (_, _, _) async => null,
        onPageChanged: (_, _, _, _) {},
        onMessage: notices.add,
      );
      var active = 'normal';
      await engine.setPageScale(125);
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
                        children: [for (final id in ids) engine.view(id)!],
                      );
              },
            ),
          ),
        ),
      );
      Future<void> open(String id, bool private) async {
        active = id;
        await engine.open(
          tabId: id,
          url: 'http://127.0.0.1:${server.port}/article',
          isPrivate: private,
        );
        final end = DateTime.now().add(const Duration(seconds: 20));
        while ((engine.status(id).isLoading ||
                engine.status(id).progress != 100) &&
            DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(engine.status(id).error, isNull, reason: notices.join('; '));
        expect(engine.status(id).isLoading, false);
      }

      await open('normal', false);
      final before = requestedResources;
      final article = await engine.readArticle(active);
      expect(engine.supportsReader, Platform.isIOS);
      if (Platform.isIOS) {
        expect(article, isNotNull);
        expect(article!.title, 'Reader fixture');
        expect(article.text, contains('visible article text'));
        expect(article.text, contains('bold phrase'));
        expect(article.text, isNot(contains('_SECRET')));
        expect(article.text, isNot(contains('<b>')));
      } else {
        expect(
          article,
          isNull,
          reason: 'No Android shared-world extraction fallback',
        );
      }
      expect(
        requestedResources,
        before,
        reason: 'Reader must not fetch resources',
      );
      expect((await engine.platformStateForTesting(active))['pageScale'], 125);
      await engine.setPageScale(75);
      expect((await engine.platformStateForTesting(active))['pageScale'], 75);
      if (Platform.isAndroid) {
        expect(
          (await engine.platformStateForTesting(active))['secureWindow'],
          true,
        );
        expect(
          (await engine.platformStateForTesting(
            active,
          ))['webAuthenticationSupport'],
          anyOf(0, null),
        );
        await NativeBrowserService().setSensitiveContent(false);
        expect(
          (await engine.platformStateForTesting(active))['secureWindow'],
          true,
        );
      } else {
        expect(
          (await engine.platformStateForTesting(
            active,
            shieldVisible: true,
          ))['shieldVisible'],
          true,
        );
        expect(
          (await engine.platformStateForTesting(
            active,
            shieldVisible: false,
          ))['shieldVisible'],
          false,
        );
      }
      await engine.evaluateForTesting(
        active,
        "const dialog=document.createElement('dialog');dialog.textContent='Sign in to continue';document.body.append(dialog);dialog.showModal();true",
      );
      expect(
        await engine.readArticle(active),
        isNull,
        reason: 'No text behind a visible modal',
      );
      await engine.evaluateForTesting(
        active,
        "document.querySelector('dialog').remove();true",
      );
      await engine.evaluateForTesting(
        active,
        "const overlay=document.createElement('div');overlay.id='cover';overlay.style='position:fixed;inset:0;background:white;z-index:999999';overlay.textContent='Access restricted';document.body.append(overlay);true",
      );
      expect(
        await engine.readArticle(active),
        isNull,
        reason: 'No article extraction behind a nonsemantic overlay',
      );
      await engine.evaluateForTesting(
        active,
        "document.querySelector('#cover').remove();true",
      );
      await engine.evaluateForTesting(
        active,
        "document.querySelector('main').hidden=true; true",
      );
      expect(await engine.readArticle(active), isNull);
      await open('private', true);
      if (Platform.isIOS) {
        expect(
          (await engine.readArticle(active))?.text,
          contains('visible article text'),
        );
        await engine.evaluateForTesting(
          active,
          "window.getComputedStyle=()=>({});JSON.stringify=()=>'{bad';true",
        );
        expect(
          (await engine.readArticle(active))?.text,
          contains('visible article text'),
          reason: 'Page-world overrides must not affect isolated extraction',
        );
      } else {
        expect(await engine.readArticle(active), isNull);
      }
      expect(
        await engine.readArticle('normal'),
        isNull,
        reason: 'No extraction from inactive tabs',
      );
      if (Platform.isAndroid) {
        expect(
          (await engine.platformStateForTesting(active))['secureWindow'],
          true,
        );
      }
      await tester.pumpWidget(const SizedBox());
      for (final id in engine.liveTabIds) {
        await engine.close(id);
      }
      engine.dispose();
      await server.close(force: true);
      debugPrint(
        Platform.isIOS
            ? 'READER isolated visible text, private-local, no fetch, page scale and native privacy state passed'
            : 'ANDROID Reader unavailable; normal/private capture flags, page scale and WebAuthn default passed',
      );
    },
  );
}
