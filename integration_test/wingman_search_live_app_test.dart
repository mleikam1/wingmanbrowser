import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/main.dart' as app;
import 'package:wingman_browser/presentation/search/wingman_search_view.dart';
import 'package:wingman_browser/search/controller.dart';

// Explicit, separately authorized local-live verification only. This is never
// part of ordinary host tests and never points the fixture harness at live mode.
// The gateway's durable allowance remains authoritative. Its selected request
// class must account this run within the automated verification ceiling.
class _TwoSearchConnections extends HttpOverrides {
  _TwoSearchConnections(this.endpoint);
  final Uri endpoint;
  int searchConnections = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (uri.scheme == endpoint.scheme &&
          uri.host == endpoint.host &&
          uri.port == endpoint.port &&
          uri.path == endpoint.path) {
        searchConnections++;
        // A third search cannot reach the gateway even if a regression adds
        // a retry or implicit request. Never inspect/log the query-bearing body.
        if (searchConnections > 2) {
          throw StateError('local_live_verification_connection_limit');
        }
      }
      return Socket.startConnect(proxyHost ?? uri.host, proxyPort ?? uri.port);
    };
    return client;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('WINGMAN_LOCAL_LIVE_VERIFY');
  final endpoint = GatewaySearchClient.endpointFrom(
    const String.fromEnvironment('WINGMAN_SEARCH_URL'),
    allowDevelopment:
        kDebugMode && const bool.fromEnvironment('WINGMAN_SEARCH_DEVELOPMENT'),
  );
  final permitted =
      enabled &&
      kDebugMode &&
      endpoint != null &&
      endpoint.scheme == 'http' &&
      {'127.0.0.1', 'localhost', '::1'}.contains(endpoint.host);

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    final watch = Stopwatch()..start();
    while (!ready() && watch.elapsed < const Duration(seconds: 45)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), isTrue);
  }

  bool interactive(Finder finder) {
    final matches = finder.hitTestable().evaluate();
    if (matches.isEmpty) return false;
    final route = ModalRoute.of(matches.last);
    return route == null ||
        (route.isCurrent &&
            (route.animation == null ||
                route.animation!.status == AnimationStatus.completed));
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await until(tester, () => finder.evaluate().isNotEmpty);
    await tester.ensureVisible(finder.last);
    await until(tester, () => interactive(finder));
    await tester.tap(finder.hitTestable().last);
    await tester.pump();
  }

  testWidgets(
    'opt-in actual app live Web and News: at most two search connections',
    (tester) async {
      final connections = _TwoSearchConnections(endpoint!);
      await HttpOverrides.runWithHttpOverrides(() async {
        await app.main();
        await until(
          tester,
          () => find.byType(app.WingmanApp).evaluate().isNotEmpty,
        );
        final owner = tester.widget<app.WingmanApp>(
          find.byType(app.WingmanApp),
        );
        final session = owner.session!;
        final originalIds = session.tabs.map((tab) => tab.id).toSet();
        final originalActive = session.current.id;
        final originalOnboarding = owner.state.settings.onboardingComplete;
        try {
          if (find.text('Get started').evaluate().isNotEmpty) {
            await tap(tester, find.text('Get started'));
          }
          expect(connections.searchConnections, 0);
          await tap(tester, find.byTooltip('Tabs (${session.tabs.length})'));
          await tap(
            tester,
            find.text(
              'Normal (${session.tabs.where((tab) => !tab.isPrivate).length})',
            ),
          );
          await tap(tester, find.text('New tab'));
          await tap(tester, find.byKey(const ValueKey('home-search-entry')));
          final field = find.byKey(const ValueKey('protected-search'));
          await until(
            tester,
            () => interactive(
              find.descendant(of: field, matching: find.byType(EditableText)),
            ),
          );
          await tester.enterText(field, 'NASA space science research');
          await tester.pump(const Duration(milliseconds: 500));
          expect(connections.searchConnections, 0);

          // Explicit submit 1. A failure stops the test; it is never retried.
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await until(tester, () => session.current.search?.loading == false);
          final search = session.current.search!;
          expect(search.failure?.code, isNull);
          expect(search.kind, SearchKind.web);
          expect(search.fixture, isFalse);
          expect(search.results.isNotEmpty, isTrue);
          expect(find.byType(WingmanSearchView), findsOneWidget);
          expect(find.text('Fixture results'), findsNothing);
          expect(find.text('Results provided by Brave Search'), findsOneWidget);
          expect(connections.searchConnections, 1);
          final webCount = search.results.length;

          // Pace independently of frame time; the gateway also enforces its
          // account/rate window. This delay never submits or retries a request.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2100)),
          );
          expect(connections.searchConnections, 1);
          // Explicit submit 2, same query, distinct News endpoint contract.
          await tap(tester, find.byKey(const ValueKey('search-news')));
          await until(
            tester,
            () => search.kind == SearchKind.news && !search.loading,
          );
          expect(search.failure?.code, isNull);
          expect(search.fixture, isFalse);
          expect(search.results.isNotEmpty, isTrue);
          expect(find.text('Fixture results'), findsNothing);
          expect(find.text('Results provided by Brave Search'), findsOneWidget);
          expect(connections.searchConnections, 2);
          await tester.pump(const Duration(seconds: 2));
          expect(connections.searchConnections, 2);
          debugPrint(
            'WINGMAN_LOCAL_LIVE_APP actualMain=true schemaVersion=1 fixture=false '
            'web=verified webResults=$webCount news=verified newsResults=${search.results.length} '
            'gatewaySearchConnections=2 submittedActions=2 noAutomaticSearch=true',
          );
        } finally {
          for (final tab
              in session.tabs
                  .where((tab) => !originalIds.contains(tab.id))
                  .toList()) {
            session.tabs.remove(tab);
            tab.dispose();
          }
          final index = session.tabs.indexWhere(
            (tab) => tab.id == originalActive,
          );
          session.active = index < 0 ? 0 : index;
          session.clearPrivateServicesIfUnused();
          await session.flush();
          if (owner.state.settings.onboardingComplete != originalOnboarding) {
            await owner.state.saveSettingsDurably(
              owner.state.settings.copyWith(
                onboardingComplete: originalOnboarding,
              ),
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }, connections);
    },
    skip: !permitted,
  );
}
