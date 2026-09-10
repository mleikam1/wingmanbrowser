import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wingman_browser/browser/browser_engine.dart';
import 'package:wingman_browser/data/sqlite_browser_repository.dart';
import 'package:wingman_browser/state/browser_state.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real engine navigation, bounded tabs, private isolation and cleanup', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      if (request.uri.path == '/failure') request.response.statusCode = 503;
      request.response.write(
        '''<!doctype html><html><head><meta name="viewport" content="width=device-width"><title>Wingman fixture ${request.uri.path}</title></head><body>
<h1>Wingman browser acceptance fixture</h1>
${request.uri.path == '/with-frame' ? '<iframe src="/failure" title="Failing embedded frame"></iframe>' : ''}
<a id="next" href="/second">Next page</a>
<a id="blank" href="/popup" target="_blank">Open new window</a>
<input id="file" type="file"><form><input name="username" autocomplete="username"><input type="password" name="password"></form>
<button onclick="alert('Fixture dialog')">Dialog</button>
<button id="spaOne" onclick="history.pushState({}, '', '/spa-one'); document.title='SPA one'">SPA one</button>
<button id="spaTwo" onclick="history.pushState({}, '', '/spa-two'); document.title='SPA two'">SPA two</button>
<script>window.onpopstate = () => { if(location.pathname.endsWith('spa-one')) document.title='SPA one'; else if(location.pathname.endsWith('spa-two')) document.title='SPA two'; };</script>
</body></html>''',
      );
      await request.response.close();
    });
    final repository = SqliteBrowserRepository(
      factory: databaseFactory,
      databasePath: inMemoryDatabasePath,
    );
    final data = BrowserState(repository: repository);
    await data.init();
    debugPrint('STAGE database ready');
    final native = NativeBrowserService();
    late final BrowserEnginePool engine;
    await native.initialize(
      onIncomingUri: (_) {},
      onRendererGone: (id) => engine.rendererGone(id),
      onNavigationSettled: (id, url) => engine.navigationSettled(id, url),
    );
    debugPrint('STAGE native ready');
    final notices = <String>[];
    engine = BrowserEnginePool(
      confirm: (_, _) async => false,
      prompt: (_, _, _) async => null,
      onPageChanged: (id, url, title, completed) => data.pageChanged(
        tabId: id,
        url: url,
        title: title,
        completed: completed,
      ),
      onMessage: notices.add,
    );
    String active = '';
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
      final end = DateTime.now().add(const Duration(seconds: 35));
      while (!condition() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(condition(), isTrue, reason: '$description. Notices: $notices');
    }

    Future<void> open(String id, String url, {bool private = false}) async {
      active = id;
      debugPrint('STAGE opening engine');
      await engine.open(tabId: id, url: url, isPrivate: private);
      debugPrint('STAGE engine open returned');
      await tester.pump();
      debugPrint('STAGE engine mounted');
      await waitFor(
        () => engine.status(id).progress == 100 && !engine.status(id).isLoading,
        'load $id',
      );
      expect(engine.status(id).error, isNull, reason: 'engine must render $id');
    }

    Future<void> tapPageElement(String tabId, String elementId) async {
      if (Platform.isIOS) {
        // Flutter test pointer events do not reliably reach embedded UIKit
        // views. Exercise the fixture's DOM action on iOS; OS-level taps are
        // covered separately by manual simulator validation.
        await engine.evaluateForTesting(
          tabId,
          "document.getElementById('$elementId').click(); true",
        );
        return;
      }
      final x = await engine.evaluateForTesting(
        tabId,
        "(() => { const r = document.getElementById('$elementId').getBoundingClientRect(); return r.left + r.width / 2; })()",
      );
      final y = await engine.evaluateForTesting(
        tabId,
        "(() => { const r = document.getElementById('$elementId').getBoundingClientRect(); return r.top + r.height / 2; })()",
      );
      final origin = tester.getTopLeft(find.byKey(ValueKey('engine-$tabId')));
      await tester.tapAt(
        origin + Offset((x as num).toDouble(), (y as num).toDouble()),
      );
    }

    debugPrint('STAGE harness ready');
    final normal = data.activeId;
    data.navigate('$base/first');
    await open(normal, '$base/first');
    debugPrint('STAGE first page ready');
    expect(engine.status(normal).title, contains('/first'));
    await engine.evaluateForTesting(
      normal,
      "document.getElementById('next').click(); true",
    );
    await waitFor(
      () =>
          engine.status(normal).url.endsWith('/second') &&
          engine.status(normal).canGoBack,
      'link navigation',
    );
    debugPrint('STAGE second page ready');
    await engine.back(normal);
    await waitFor(
      () =>
          engine.status(normal).url.endsWith('/first') &&
          engine.status(normal).canGoForward,
      'back',
    );
    debugPrint('STAGE back ready');
    await engine.forward(normal);
    await waitFor(
      () =>
          engine.status(normal).url.endsWith('/second') &&
          !engine.status(normal).isLoading,
      'forward',
    );
    debugPrint('STAGE forward ready');
    await engine.reload(normal);
    await waitFor(() => !engine.status(normal).isLoading, 'reload');
    // Real gestures preserve popup safety and Chromium's protection against
    // history entries inserted without user interaction.
    await tapPageElement(normal, 'blank');
    await waitFor(
      () =>
          engine.status(normal).url.endsWith('/popup') &&
          !engine.status(normal).isLoading,
      'target blank preserved in current tab',
    );
    await engine.evaluateForTesting(
      normal,
      "localStorage.setItem('wingman_test','normal'); document.cookie='wingman_test=normal; path=/'; true",
    );
    data.toggleBookmark();
    await data.flush();
    debugPrint('STAGE popup and bookmark ready');
    await tapPageElement(normal, 'spaOne');
    await waitFor(
      () =>
          engine.status(normal).url.endsWith('/spa-one') &&
          engine.status(normal).title == 'SPA one',
      'SPA first state',
    );
    await tapPageElement(normal, 'spaTwo');
    await waitFor(
      () =>
          engine.status(normal).url.endsWith('/spa-two') &&
          engine.status(normal).title == 'SPA two',
      'SPA second state',
    );
    await engine.back(normal);
    await waitFor(
      () =>
          engine.status(normal).url.endsWith('/spa-one') &&
          engine.status(normal).title == 'SPA one' &&
          engine.status(normal).canGoForward,
      'SPA back chrome refresh',
    );
    await engine.forward(normal);
    await waitFor(
      () =>
          engine.status(normal).url.endsWith('/spa-two') &&
          engine.status(normal).title == 'SPA two',
      'SPA forward chrome refresh',
    );
    debugPrint('STAGE SPA history refresh passed');
    expect((await repository.load()).history, isNotEmpty);
    expect((await repository.load()).bookmarks, isNotEmpty);
    expect(
      await native.privateBrowsingAvailable(),
      isTrue,
      reason: 'target must support isolated private data',
    );
    final private = data.newTab(isPrivate: true, url: '$base/private');
    await open(private.id, private.url, private: true);
    expect(
      (await engine.evaluateForTesting(
        private.id,
        "localStorage.getItem('wingman_test') || 'empty'",
      )).toString(),
      contains('empty'),
    );
    expect(
      (await engine.evaluateForTesting(
        private.id,
        "document.cookie || 'empty'",
      )).toString(),
      contains('empty'),
    );
    await engine.evaluateForTesting(
      private.id,
      "localStorage.setItem('wingman_test','private-secret'); document.cookie='wingman_private=secret; path=/'; true",
    );
    await engine.close(private.id);
    data.closeTab(private.id);
    await tester.pump();
    await data.flush();
    final stored = await repository.load();
    expect(stored.history.any((e) => e.url.contains('/private')), isFalse);
    expect(
      stored.tabs.any((e) => e.isPrivate || e.url.contains('/private')),
      isFalse,
    );
    final freshPrivate = data.newTab(
      isPrivate: true,
      url: '$base/private-fresh',
    );
    await open(freshPrivate.id, freshPrivate.url, private: true);
    expect(
      (await engine.evaluateForTesting(
        freshPrivate.id,
        "localStorage.getItem('wingman_test') || 'empty'",
      )).toString(),
      contains('empty'),
    );
    expect(
      (await engine.evaluateForTesting(
        freshPrivate.id,
        "document.cookie || 'empty'",
      )).toString(),
      contains('empty'),
    );
    await engine.close(freshPrivate.id);
    data.closeTab(freshPrivate.id);
    data.selectTab(normal);
    await open(normal, engine.status(normal).url);
    expect(
      (await engine.evaluateForTesting(
        normal,
        "localStorage.getItem('wingman_test')",
      )).toString(),
      contains('normal'),
    );
    for (var i = 0; i < 12; i++) {
      final tab = data.newTab(url: '$base/cycle-$i');
      await open(tab.id, tab.url);
      expect(engine.liveEngineCount, lessThanOrEqualTo(3));
      if (i.isEven) {
        await engine.close(tab.id);
        data.closeTab(tab.id);
        await tester.pump();
      }
    }
    await engine.clearData();
    await data.clearHistory();
    expect(engine.liveEngineCount, 0);
    expect((await repository.load()).history, isEmpty);
    data.selectTab(normal);
    data.navigate('$base/cleared');
    await open(normal, '$base/cleared');
    expect(
      (await engine.evaluateForTesting(
        normal,
        "localStorage.getItem('wingman_test') || 'empty'",
      )).toString(),
      contains('empty'),
    );
    expect(
      (await engine.evaluateForTesting(
        normal,
        "document.cookie || 'empty'",
      )).toString(),
      contains('empty'),
    );
    await open(normal, '$base/with-frame');
    expect(
      engine.status(normal).error,
      isNull,
      reason: 'An iframe HTTP failure must not replace the main page',
    );
    debugPrint('STAGE iframe error contained');
    await engine.open(tabId: normal, url: '$base/failure', isPrivate: false);
    await waitFor(
      () => engine.status(normal).error != null,
      'HTTP error state',
    );
    expect(engine.status(normal).url, '$base/failure');
    await open(normal, '$base/before-unreachable');
    final closedPort = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final unreachable = 'http://127.0.0.1:${closedPort.port}/unreachable';
    await closedPort.close();
    await engine.open(tabId: normal, url: unreachable, isPrivate: false);
    await waitFor(
      () => engine.status(normal).error != null,
      'unreachable page',
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      engine.status(normal).url,
      unreachable,
      reason: 'Failure chrome must preserve the attempted URL',
    );
    await engine.reload(normal);
    await waitFor(
      () => engine.status(normal).error != null,
      'retry failed URL',
    );
    expect(
      engine.status(normal).url,
      unreachable,
      reason: 'Retry must reload the failed URL, not the prior committed page',
    );
    debugPrint('STAGE failed URL and retry preserved');
    if (Platform.isAndroid) {
      await engine.open(
        tabId: normal,
        url: '$base/renderer-recovery',
        isPrivate: false,
      );
      await waitFor(
        () => !engine.status(normal).isLoading,
        'renderer fixture loaded',
      );
      expect(await engine.terminateRendererForTesting(normal), isTrue);
      await waitFor(
        () =>
            engine.status(normal).error?.contains('stopped responding') == true,
        'renderer failure contained',
      );
      await engine.reload(normal);
      await waitFor(
        () =>
            !engine.status(normal).isLoading &&
            engine.status(normal).error == null,
        'renderer recovered without app crash',
      );
      expect(
        (await engine.evaluateForTesting(normal, 'document.title')).toString(),
        contains('renderer-recovery'),
      );
      debugPrint('STAGE renderer recovery passed');
    }
    await tester.pumpWidget(const SizedBox());
    for (final id in engine.liveTabIds) {
      await engine.close(id);
    }
    engine.dispose();
    native.dispose();
    await data.flush();
    data.dispose();
    await server.close(force: true);
  });
}
