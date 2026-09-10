import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/browser/reader_article.dart';
import 'package:wingman_browser/monetization/ad_route_observer.dart';
import 'package:wingman_browser/presentation/browser_shell.dart';
import 'package:wingman_browser/presentation/screens/reader_screen.dart';
import 'package:wingman_browser/presentation/screens/settings_screen.dart';
import 'package:wingman_browser/state/browser_state.dart';

import 'widget_test.dart' show MemoryRepository;

const _article = ReaderArticle(
  title: 'Explicit article fixture',
  text: 'Only the selected page text belongs in this transient reader.',
  sourceUrl: 'https://article.test/story',
);

class _ReaderFixture {
  _ReaderFixture(this.data, this.requests, this.requestedTabs);
  final BrowserState data;
  final List<Completer<ReaderArticle?>> requests;
  final List<String> requestedTabs;
}

Future<_ReaderFixture> _mount(WidgetTester tester) async {
  // Create/init inside the widget-test async zone. No real WebView or selected
  // website is needed to test route/lifecycle invalidation of an extraction.
  final data = BrowserState(repository: MemoryRepository());
  await data.init();
  final requests = <Completer<ReaderArticle?>>[];
  final requestedTabs = <String>[];
  const channel = MethodChannel('wingman/browser');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (_) async => null);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [adRouteObserver],
      home: BrowserShell(
        state: data,
        readerForTesting: (tabId) {
          requestedTabs.add(tabId);
          final request = Completer<ReaderArticle?>();
          requests.add(request);
          return request.future;
        },
      ),
    ),
  );
  // Let Home native initialization settle before navigating metadata. This
  // avoids accidentally requesting a platform WebView in a host-only test.
  await _pumpRoutes(tester);
  data.navigate(_article.sourceUrl);
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    data.dispose();
    await tester.pump();
    messenger.setMockMethodCallHandler(channel, null);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  return _ReaderFixture(data, requests, requestedTabs);
}

Future<void> _open(WidgetTester tester) =>
    (tester.state(find.byType(BrowserShell)) as dynamic).openReader()
        as Future<void>;

Future<void> _pumpRoutes(WidgetTester tester) async {
  // Metadata-only fixture has no native page and may show an indeterminate
  // progress indicator. Pump route transitions without waiting for that ticker.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  testWidgets(
    'reader result cannot replace the Settings route that covered it',
    (tester) async {
      final fixture = await _mount(tester);
      final opening = _open(tester);
      expect(fixture.requests.length, 1);
      (tester.state(find.byType(BrowserShell)) as dynamic).settings();
      await _pumpRoutes(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      fixture.requests.single.complete(_article);
      await _pumpRoutes(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(ReaderScreen), findsNothing);
      await opening;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid Settings push and pop still invalidates pending reader work',
    (tester) async {
      final fixture = await _mount(tester);
      final opening = _open(tester);
      (tester.state(find.byType(BrowserShell)) as dynamic).settings();
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await _pumpRoutes(tester);
      expect(find.byType(SettingsScreen), findsNothing);
      fixture.requests.single.complete(_article);
      await _pumpRoutes(tester);
      await opening;
      expect(find.byType(ReaderScreen), findsNothing);
      // A later explicit request is usable after the stale result was discarded.
      final retry = _open(tester);
      expect(fixture.requests.length, 2);
      fixture.requests.last.complete(_article);
      await _pumpRoutes(tester);
      expect(find.byType(ReaderScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
      await _pumpRoutes(tester);
      await retry;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inactive then resumed cannot revive an earlier reader result', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final opening = _open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    fixture.requests.single.complete(_article);
    await _pumpRoutes(tester);
    await opening;
    expect(find.byType(ReaderScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a current explicit completion opens Reader and returns normally',
    (tester) async {
      final fixture = await _mount(tester);
      final tabId = fixture.data.activeId;
      final opening = _open(tester);
      expect(fixture.requestedTabs, [tabId]);
      fixture.requests.single.complete(_article);
      await _pumpRoutes(tester);
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(find.text(_article.title), findsOneWidget);
      expect(find.text(_article.sourceUrl), findsOneWidget);
      Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
      await _pumpRoutes(tester);
      await opening;
      expect(fixture.data.activeId, tabId);
      expect(fixture.data.activeTab.url, _article.sourceUrl);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'private Reader stays transient and does not save library or history',
    (tester) async {
      final fixture = await _mount(tester);
      final private = fixture.data.newTab(
        isPrivate: true,
        url: _article.sourceUrl,
      );
      await tester.pump();
      final opening = _open(tester);
      expect(fixture.requestedTabs, [private.id]);
      fixture.requests.single.complete(_article);
      await _pumpRoutes(tester);
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(fixture.data.history, isEmpty);
      expect(fixture.data.bookmarks, isEmpty);
      expect(fixture.data.readingList, isEmpty);
      Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
      await _pumpRoutes(tester);
      await opening;
      expect(fixture.data.activeTab.isPrivate, true);
      expect(tester.takeException(), isNull);
    },
  );
}
