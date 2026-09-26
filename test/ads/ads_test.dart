import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/ads/session.dart';
import 'package:wingman_browser/presentation/ads/sponsored_placement.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/search/controller.dart';

Map<String, Object?> decision({
  String placement = 'search',
  bool fixture = true,
}) => {
  'schemaVersion': 1,
  'status': 'filled',
  'fixture': fixture,
  'noFillReason': null,
  'ad': {
    'id': '0123456789abcdef0123456789abcdef',
    'campaignId': 'fixture-campaign',
    'creativeId': 'fixture-creative',
    'placement': placement,
    'label': 'Sponsored',
    'advertiser': 'Synthetic Sponsor',
    'headline': 'Example productivity tools',
    'body': 'A synthetic first-party campaign. No real advertiser or revenue.',
    'displayDomain': 'example.org',
    'landingId': 'approved-landing',
    'deliveryToken': 'event-scoped-token-123456789',
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 10))
        .toIso8601String(),
    'whyThisAd': 'Selected for this current nonsensitive section.',
    'imagePath': null,
  },
};
SponsoredAd ad({String placement = 'search'}) =>
    SponsoredAd.fromDecision(decision(placement: placement), placement)!;

class FakeAdsClient implements WingmanAdsClient {
  final decisions = <Map<String, Object>>[], events = <Map<String, Object>>[];
  Future<SponsoredAd?> Function(Map<String, Object>)? onDecision;
  int cancellations = 0;
  @override
  Future<SponsoredAd?> decide(Map<String, Object> request) {
    decisions.add(request);
    return onDecision?.call(request) ??
        Future.value(ad(placement: request['placement'] as String));
  }

  @override
  Future<AdEventResult> event(Map<String, Object> request) async {
    events.add(request);
    return AdEventResult(
      accepted: true,
      landingUrl: request['kind'] == 'click'
          ? Uri.parse('https://example.org/product')
          : null,
    );
  }

  @override
  void cancel() {
    cancellations++;
  }
}

class _SearchClient implements WingmanSearchClient {
  _SearchClient({this.count = 1, this.secondSlotAllowed = false});
  final int count;
  final bool secondSlotAllowed;
  int calls = 0;
  @override
  Future<SearchResponse> search(SearchRequest request) async {
    calls++;
    return SearchResponse(
      kind: request.kind,
      status: 'ok',
      results: [
        for (var index = 0; index < count; index++)
          SearchResult(
            title: 'Organic result',
            url: Uri.parse('https://example.org/organic/$index'),
            description: 'Organic',
            source: 'example.org',
          ),
      ],
      moreAvailable: false,
      fixture: true,
      adContext: AdContextGrant(
        'context-grant-123456789',
        DateTime.now().toUtc().add(const Duration(minutes: 10)),
        secondSlotAllowed: secondSlotAllowed,
      ),
    );
  }

  @override
  void cancel() {}
}

void main() {
  test(
    'ad parsing keeps text inert and rejects invalid tokens, URLs, expiry and fixture charges',
    () {
      final raw = decision();
      final creative = raw['ad'] as Map<String, Object?>;
      creative['headline'] = '<script>bad()</script><b>Example &amp; tools</b>';
      expect(
        SponsoredAd.fromDecision(raw, 'search')!.headline,
        'Example & tools',
      );
      for (final field in ['deliveryToken', 'id', 'landingId']) {
        final invalid = decision();
        (invalid['ad'] as Map<String, Object?>)[field] =
            'https://merchant.example/?q=secret';
        expect(
          () => SponsoredAd.fromDecision(invalid, 'search'),
          throwsA(isA<AdFailure>()),
        );
      }
      final expired = decision();
      (expired['ad'] as Map<String, Object?>)['expiresAt'] = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      expect(
        () => SponsoredAd.fromDecision(expired, 'search'),
        throwsA(isA<AdFailure>()),
      );
      expect(
        () => AdEventResult.parse({
          'schemaVersion': 1,
          'status': 'accepted',
          'fixture': true,
          'billable': true,
          'chargedMicros': 1,
          'testChargedMicros': 1,
          'landingUrl': null,
        }),
        throwsA(isA<AdFailure>()),
      );
    },
  );
  test(
    'no-fill makes one decision and never retries or emits events',
    () async {
      final client = FakeAdsClient()..onDecision = (_) => Future.value(null);
      final session = AdSession(
        client: client,
        request: {'placement': 'search'},
        allowed: () => true,
      );
      await session.load();
      await session.load();
      expect(session.ad, isNull);
      expect(client.decisions, hasLength(1));
      expect(client.events, isEmpty);
      session.dispose();
    },
  );
  test(
    'hidden contexts send nothing and stale decision cannot appear after privacy transition',
    () async {
      var allowed = false;
      final pending = Completer<SponsoredAd?>();
      final client = FakeAdsClient()..onDecision = (_) => pending.future;
      final session = AdSession(
        client: client,
        request: {'placement': 'search'},
        allowed: () => allowed,
      );
      await session.load();
      expect(client.decisions, isEmpty);
      allowed = true;
      final load = session.load();
      allowed = false;
      session.cancel();
      pending.complete(ad());
      await load;
      expect(session.ad, isNull);
      expect(client.events, isEmpty);
      session.dispose();
    },
  );
  test(
    'once-per-kind events and legitimate early click are separate from view',
    () async {
      final client = FakeAdsClient();
      final session = AdSession(
        client: client,
        request: {'placement': 'search'},
        allowed: () => true,
      );
      await session.load();
      expect(
        await session.send('view', visiblePermille: 499, visibleMs: 1000),
        isNull,
      );
      expect(client.events, isEmpty);
      final landing = await session.send(
        'click',
        visiblePermille: 200,
        visibleMs: 0,
        explicitAction: true,
      );
      expect(landing.toString(), 'https://example.org/product');
      expect(client.events.single['kind'], 'click');
      await session.send(
        'click',
        visiblePermille: 1000,
        visibleMs: 1000,
        explicitAction: true,
      );
      await session.send('render', visiblePermille: 1000, visibleMs: 0);
      await session.send('view', visiblePermille: 1000, visibleMs: 1000);
      await session.send('view', visiblePermille: 1000, visibleMs: 2000);
      expect(client.events.map((e) => e['kind']), ['click', 'render', 'view']);
      session.dispose();
    },
  );
  test(
    'live client rejects fixture delivery unless explicitly permitted for development',
    () async {
      final client = FakeAdsClient();
      final session = AdSession(
        client: client,
        request: {'placement': 'search'},
        allowed: () => true,
        allowFixtures: false,
      );
      await session.load();
      expect(session.ad, isNull);
      session.dispose();
    },
  );
  test(
    'NewsUSA gets finite sponsorship priority across category changes and load-more',
    () async {
      final client = FakeAdsClient();
      final page = AdsPageSession(placement: 'news', factory: () => client);
      final organic = [
        for (var i = 0; i < 12; i++) NewsInventoryItem('organic-$i', false),
      ];
      final allowed = page.prepareNews([
        ...organic,
        const NewsInventoryItem('newsusa-1', true),
        const NewsInventoryItem('newsusa-2', true),
        const NewsInventoryItem('newsusa-3', true),
      ]);
      expect(allowed, {'newsusa-1', 'newsusa-2'});
      expect(page.slot(0, section: 'science', allowed: () => true), isNull);
      expect(
        page.prepareNews([
          ...organic,
          const NewsInventoryItem('other-newsusa', true),
        ]),
        isEmpty,
      );
      expect(client.decisions, isEmpty);
      page.dispose();
    },
  );
  test(
    'one New Tab slot and two finite news slots; no sensitive section',
    () async {
      final client = FakeAdsClient();
      final home = AdsPageSession(placement: 'newtab', factory: () => client);
      final one = home.slot(0, section: 'untargeted', allowed: () => true)!;
      await one.load();
      expect(
        home.slot(0, section: 'untargeted', allowed: () => true),
        same(one),
      );
      expect(home.slot(1, section: 'untargeted', allowed: () => true), isNull);
      home.dispose();
      final page = AdsPageSession(placement: 'news', factory: () => client);
      page.prepareNews([
        for (var i = 0; i < 12; i++) NewsInventoryItem('o$i', false),
      ]);
      expect(page.slot(0, section: 'health', allowed: () => true), isNull);
      await page.slot(0, section: 'science', allowed: () => true)!.load();
      await page.slot(1, section: 'science', allowed: () => true)!.load();
      expect(page.slot(2, section: 'science', allowed: () => true), isNull);
      expect(client.decisions, hasLength(3));
      page.dispose();
      final disabled = AdsPageSession(
        placement: 'newtab',
        factory: () => client,
        enabled: false,
      );
      expect(
        disabled.slot(0, section: 'untargeted', allowed: () => true),
        isNull,
      );
      disabled.dispose();
    },
  );
  test(
    'organic search resolves without waiting for ads; private/news/default-off never allocate an ad path',
    () async {
      for (final context in SearchContext.values) {
        final search = _SearchClient();
        final ads = FakeAdsClient();
        final model = WingmanSearchController(
          client: search,
          context: context,
          permitted: () => true,
          resultAllowed: (_) => true,
          adsClientFactory: () => ads,
          adsEnabled: true,
        );
        await model.submit('productivity tools');
        if (context != SearchContext.managed) {
          expect(model.results, hasLength(1));
        }
        expect(ads.decisions, isEmpty);
        expect(model.sponsored != null, context == SearchContext.normal);
        await model.selectKind(SearchKind.news);
        expect(model.sponsored, isNull);
        model.dispose();
      }
      final model = WingmanSearchController(
        client: _SearchClient(),
        context: SearchContext.normal,
        permitted: () => true,
        resultAllowed: (_) => true,
        adsClientFactory: () => FakeAdsClient(),
      );
      await model.submit('productivity tools');
      expect(model.sponsored, isNull);
      model.dispose();
    },
  );
  test(
    'second search placement requires both gates and three initial organic results',
    () async {
      for (final localGate in [false, true]) {
        for (final grantGate in [false, true]) {
          for (final count in [2, 3]) {
            final ads = FakeAdsClient();
            final model = WingmanSearchController(
              client: _SearchClient(count: count, secondSlotAllowed: grantGate),
              context: SearchContext.normal,
              permitted: () => true,
              resultAllowed: (_) => true,
              adsClientFactory: () => ads,
              adsEnabled: true,
              secondSearchAdExperiment: localGate,
            );
            await model.submit('example office tools');
            expect(model.sponsored, isNotNull);
            expect(
              model.secondSponsored != null,
              localGate && grantGate && count >= 3,
            );
            await model.sponsored!.load();
            await model.secondSponsored?.load();
            expect(ads.decisions.length, model.secondSponsored == null ? 1 : 2);
            if (model.secondSponsored != null) {
              expect(ads.decisions.last['slotIndex'], 1);
              expect(ads.decisions.last.containsKey('query'), isFalse);
            }
            model.dispose();
          }
        }
      }
    },
  );
  test(
    'news slots respect density when selection shrinks and combines a supplied sponsor with an ad',
    () async {
      final client = FakeAdsClient();
      final page = AdsPageSession(placement: 'news', factory: () => client);
      final organic = [
        for (var i = 0; i < 12; i++) NewsInventoryItem('o$i', false),
      ];
      expect(
        page.prepareNews([
          ...organic,
          const NewsInventoryItem('newsusa', true),
        ]),
        {'newsusa'},
      );
      expect(page.newsSlot('newsusa'), 0);
      expect(page.slot(0, section: 'science', allowed: () => true), isNull);
      final second = page.slot(1, section: 'science', allowed: () => true)!;
      await second.load();
      expect(client.decisions.single['sponsoredCount'], 1);
      page.prepareNews(organic.take(6).toList());
      expect(page.slot(1, section: 'science', allowed: () => true), isNull);
      expect(second.eligible, isFalse);
      expect(
        page.prepareNews([...organic, const NewsInventoryItem('third', true)]),
        isEmpty,
      );
      page.dispose();
    },
  );
  Future<void> mount(
    WidgetTester tester,
    AdSession session, {
    ScrollController? scroll,
    double header = 0,
    ValueChanged<Uri>? open,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WingmanTheme.make(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              if (header > 0) SizedBox(height: header),
              Expanded(
                child: ListView(
                  controller: scroll,
                  children: [
                    SponsoredPlacement(
                      session: session,
                      scrollController: scroll,
                      canContinue: () => true,
                      onOpen: open ?? (_) {},
                    ),
                    const SizedBox(height: 900),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'actual visible foreground creative gets one impression and survives remount without duplicate events',
    (tester) async {
      final client = FakeAdsClient();
      final session = AdSession(
        client: client,
        request: {'placement': 'search'},
        allowed: () => true,
      );
      await mount(tester, session);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(client.events.where((e) => e['kind'] == 'view'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await mount(tester, session);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(client.decisions, hasLength(1));
      expect(client.events.where((e) => e['kind'] == 'render'), hasLength(1));
      expect(client.events.where((e) => e['kind'] == 'view'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets(
    'viewport header clipping prevents false view and scroll interruption resets continuous second',
    (tester) async {
      tester.view.physicalSize = const Size(400, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = FakeAdsClient();
      final session = AdSession(
        client: client,
        request: {'placement': 'search'},
        allowed: () => true,
      );
      final scroll = ScrollController();
      await mount(tester, session, scroll: scroll, header: 400);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(client.events.where((e) => e['kind'] == 'view'), isEmpty);
      await mount(tester, session, scroll: scroll);
      await tester.pump(const Duration(milliseconds: 500));
      scroll.jumpTo(500);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      expect(client.events.where((e) => e['kind'] == 'view'), isEmpty);
      scroll.jumpTo(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(client.events.where((e) => e['kind'] == 'view'), isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      expect(client.events.where((e) => e['kind'] == 'view'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      session.dispose();
    },
  );
  testWidgets(
    'background interruption yields no view and deliberate early activation resolves protected destination',
    (tester) async {
      final client = FakeAdsClient();
      final session = AdSession(
        client: client,
        request: {'placement': 'search'},
        allowed: () => true,
      );
      Uri? opened;
      await mount(tester, session, open: (uri) => opened = uri);
      await tester.pump(const Duration(milliseconds: 400));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(client.events.where((e) => e['kind'] == 'view'), isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.tap(find.text('Visit sponsor'));
      await tester.pump();
      expect(opened.toString(), 'https://example.org/product');
      expect(client.events.where((e) => e['kind'] == 'click'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
