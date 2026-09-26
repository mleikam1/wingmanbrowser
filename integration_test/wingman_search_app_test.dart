import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/main.dart' as app;
import 'package:wingman_browser/search/controller.dart';
import 'package:wingman_browser/presentation/ads/sponsored_placement.dart';
import 'package:wingman_browser/presentation/search/wingman_search_view.dart';

// Actual production main/shell against the separately started fixture gateway.
// Never point this test at a live search gateway. Use a dedicated simulator and
// --no-uninstall, preserving installed data and restoring only test-created tabs.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const fixtureEndpoint = String.fromEnvironment('WINGMAN_SEARCH_URL');
  Future<void> until(WidgetTester tester, bool Function() ready) async {
    final watch = Stopwatch()..start();
    while (!ready() && watch.elapsed < const Duration(seconds: 45)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), isTrue);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(finder.hitTestable().last);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'actual app Wingman fixture search, News and private isolation',
    (tester) async {
      await app.main();
      await until(
        tester,
        () => find.byType(app.WingmanApp).evaluate().isNotEmpty,
      );
      if (find.text('Get started').evaluate().isNotEmpty) {
        await tap(tester, find.text('Get started'));
      }
      final owner = tester.widget<app.WingmanApp>(find.byType(app.WingmanApp));
      final session = owner.session!;
      final originalIds = session.tabs.map((t) => t.id).toSet();
      final originalActive = session.current.id;
      try {
        await tap(tester, find.byTooltip('Tabs (${session.tabs.length})').last);
        await tap(tester, find.text('New tab').last);
        await tap(tester, find.byKey(const ValueKey('home-search-entry')));
        await tester.enterText(
          find.byKey(const ValueKey('protected-search')),
          'Python documentation',
        );
        expect(session.current.search, isNull);
        final watch = Stopwatch()..start();
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await until(tester, () => session.current.search?.loading == false);
        final search = session.current.search!;
        expect(search.failure?.code, isNull);
        expect(search.fixture, isTrue);
        expect(search.results, isNotEmpty);
        expect(find.byType(WingmanSearchView), findsOneWidget);
        final firstElapsed = watch.elapsedMilliseconds;
        await tap(tester, find.byKey(const ValueKey('search-news')));
        await until(tester, () => !search.loading);
        expect(search.kind, SearchKind.news);
        expect(search.fixture, isTrue);
        expect(search.failure?.code, isNull);
        await tap(tester, find.byTooltip('Tabs (${session.tabs.length})').last);
        await tap(tester, find.text('New private tab').last);
        expect(session.current.isPrivate, isTrue);
        expect(session.current.search, isNull);
        expect(find.text('Fixture results'), findsNothing);
        await tap(tester, find.byKey(const ValueKey('home-search-entry')));
        await tester.enterText(
          find.byKey(const ValueKey('protected-search')),
          'NASA Moon facts',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await until(tester, () => session.current.search?.loading == false);
        expect(session.current.search!.context, SearchContext.private);
        expect(session.current.search!.fixture, isTrue);
        expect(session.current.search!.failure?.code, isNull);
        debugPrint(
          'WINGMAN_SEARCH_APP actualMain=true web=fixture news=fixture privateIsolation=true typingRequest=false firstSearchMs=$firstElapsed paidCalls=0',
        );
      } finally {
        for (final tab
            in session.tabs
                .where((t) => !originalIds.contains(t.id))
                .toList()) {
          session.tabs.remove(tab);
          tab.dispose();
        }
        final index = session.tabs.indexWhere((t) => t.id == originalActive);
        session.active = index < 0 ? 0 : index;
        session.clearPrivateServicesIfUnused();
        await session.flush();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    skip: fixtureEndpoint != 'http://127.0.0.1:8895/v1/search',
  );

  testWidgets(
    'actual app fixture Sponsored disclosure and News/private isolation',
    (tester) async {
      await app.main();
      await until(
        tester,
        () => find.byType(app.WingmanApp).evaluate().isNotEmpty,
      );
      if (find.text('Get started').evaluate().isNotEmpty) {
        await tap(tester, find.text('Get started'));
      }
      final owner = tester.widget<app.WingmanApp>(find.byType(app.WingmanApp));
      final session = owner.session!;
      final originalIds = session.tabs.map((t) => t.id).toSet();
      final originalActive = session.current.id;
      try {
        await tap(tester, find.byTooltip('Tabs (${session.tabs.length})').last);
        await tap(tester, find.text('New tab').last);
        await tap(tester, find.byKey(const ValueKey('home-search-entry')));
        await tester.enterText(
          find.byKey(const ValueKey('protected-search')),
          'best office chairs',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await until(tester, () => session.current.search?.loading == false);
        final search = session.current.search!;
        expect(search.failure, isNull);
        expect(search.fixture, isTrue);
        expect(search.results, isNotEmpty);
        await until(tester, () => search.sponsored?.ad != null);
        expect(search.sponsored!.ad!.fixture, isTrue);
        expect(search.secondSponsored, isNull);
        expect(find.byType(SponsoredPlacement), findsOneWidget);
        expect(find.text('Fixture: useful everyday tools'), findsOneWidget);
        await tap(tester, find.text('Why this ad?'));
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.textContaining('Advertisers receive no individual query'),
          findsOneWidget,
        );
        await tap(tester, find.text('Close'));
        await tap(tester, find.byKey(const ValueKey('search-news')));
        await until(tester, () => !search.loading);
        expect(search.kind, SearchKind.news);
        expect(search.sponsored, isNull);
        expect(find.byType(SponsoredPlacement), findsNothing);
        await tap(tester, find.byTooltip('Tabs (${session.tabs.length})').last);
        await tap(tester, find.text('New private tab').last);
        expect(session.current.isPrivate, isTrue);
        expect(find.byType(SponsoredPlacement), findsNothing);
        expect(session.current.homeAds, isNull);
        await tap(tester, find.byKey(const ValueKey('home-search-entry')));
        await tester.enterText(
          find.byKey(const ValueKey('protected-search')),
          'best office chairs',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await until(tester, () => session.current.search?.loading == false);
        expect(session.current.search!.failure, isNull);
        expect(session.current.search!.context, SearchContext.private);
        expect(session.current.search!.sponsored, isNull);
        expect(find.byType(SponsoredPlacement), findsNothing);
        debugPrint(
          'WINGMAN_ADS_APP actualMain=true sponsored=fixture disclosure=true newsPrivateIsolation=true merchantRequests=0 realCharges=0',
        );
      } finally {
        for (final tab
            in session.tabs
                .where((t) => !originalIds.contains(t.id))
                .toList()) {
          session.tabs.remove(tab);
          tab.dispose();
        }
        final index = session.tabs.indexWhere((t) => t.id == originalActive);
        session.active = index < 0 ? 0 : index;
        session.clearPrivateServicesIfUnused();
        await session.flush();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    skip:
        fixtureEndpoint != 'http://127.0.0.1:8895/v1/search' ||
        !const bool.fromEnvironment('WINGMAN_ADS_ENABLED'),
  );
}
