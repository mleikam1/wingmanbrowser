import 'dart:convert';
import 'dart:io';
import 'package:wingman_browser/live_content/rss_parser.dart';
import 'package:wingman_browser/live_content/eligibility.dart';
import 'package:wingman_browser/policy/consumer_protection_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/models.dart';
import 'package:wingman_browser/live_content/controller.dart';
import 'package:wingman_browser/live_content/rss_provider.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'rss_provider_test.dart' as fixture;

void main() {
  test(
    'actual NOAA photo caption does not withdraw independently approved text',
    () async {
      final registry = LiveSourceRegistry.fromJson(
        feedMap(
          jsonDecode(
            File('assets/live_content/sources.json').readAsStringSync(),
          ),
        ),
      );
      final source = registry.sources['noaa-news']!;
      final xml = File(
        'test/fixtures/live_content/noaa-photo-caption.xml',
      ).readAsStringSync();
      final policy = await ConsumerProtectionPolicy.verifyBytes(
        File(ConsumerProtectionPolicy.assetPath).readAsBytesSync(),
      );
      final gate = LiveContentEligibility(
        registry: registry,
        canOpenDestination: (uri) => policy.assessNavigation(uri).isAllowed,
      );
      final parsed = parseRssFeed(
        fixture.bytes(xml),
        source,
        DateTime.utc(2026, 9, 16),
        gate,
        gate.acceptsFeedText,
      );
      expect(source.source.rights.images, false);
      expect(
        parsed.items.single.title,
        'NOAA names Mississippi State University to host new Northern Gulf research institute',
      );
      expect(parsed.items.single.image, isNull);
      expect(
        parsed.items.single.publishedAt,
        DateTime.utc(2026, 9, 8, 15, 48, 55),
      );
      expect(parsed.revokedIds, isEmpty);
      expect(
        parsed.optionalFieldReasons,
        containsPair('unused-photo-caption-omitted', 1),
      );
      expect(
        parsed.items.single.excerpt,
        isNot(contains('Courtesy of Northern Gulf Institute')),
      );
    },
  );

  test('unused photo captions never hide article rights or policy withdrawals', () {
    const caption =
        '<figure><img src="https://publisher.example/photo.jpg">'
        '<figcaption>Image credit: Courtesy of Photographer</figcaption></figure>';
    final clean = fixture.rss(desc: '<p>Science reporting.</p>$caption');
    expect(fixture.parse(clean).items, hasLength(1));
    for (final rights in [
      '<rights>All rights reserved</rights>',
      '<copyright>Third-party copyright</copyright>',
      '<rights>Publisher article</rights><copyright>All rights reserved</copyright>',
    ]) {
      final parsed = fixture.parse(
        clean.replaceFirst('</item>', '$rights</item>'),
      );
      expect(parsed.items, isEmpty);
      expect(parsed.revokedIds, hasLength(1));
      expect(parsed.rejectionReasons, containsPair('rights-held', 1));
    }
    for (final rightsInText in [
      '<p>Article courtesy of Another Publisher</p>$caption',
      '<figure><figcaption>Courtesy of Another Publisher</figcaption></figure>',
      '<p>Image credit: Courtesy of Another Publisher</p>',
    ]) {
      final parsed = fixture.parse(fixture.rss(desc: rightsInText));
      expect(parsed.items, isEmpty);
      expect(parsed.revokedIds, hasLength(1));
    }
    final base = fixture.source();
    final unchanged = ApprovedLiveSource.fromJson({
      ...base.source.toJson(),
      'enabled': true,
      'allowedArticleHosts': ['publisher.example'],
      'articlePathPrefixes': ['/news/'],
      'feedUrl': base.feedUri.toString(),
      'feedRedirectHosts': ['publisher.example'],
      'eligibilityScope': base.eligibilityScope,
      'preserveFeedText': true,
    });
    expect(fixture.parse(clean, approved: unchanged).items, isEmpty);
    final policyHeld = fixture.parse(
      clean,
      allows: (_, excerpt) => !excerpt.contains('Photographer'),
    );
    expect(policyHeld.items, isEmpty);
    expect(policyHeld.rejectionReasons, containsPair('policy-held', 1));
    expect(policyHeld.revokedIds, hasLength(1));
  });

  test('publisher pacing survives a parser failure after HTTP 200', () async {
    final source = fixture.source();
    final transport = fixture.FakeTransport([
      fixture.response('<rss><channel>', headers: {'retry-after': '7200'}),
    ]);
    final provider = RssFeedProvider(
      registry: LiveSourceRegistry([source]),
      eligibility: fixture.gate([source]),
      allowsEditorialText: (_, _) => true,
      transport: transport,
      clock: () => fixture.now,
    );
    final result = await provider.fetch();
    final state = ((result.providerState!['sources'] as Map)['news'] as Map);
    expect(
      state['nextRefreshAt'],
      fixture.now.add(const Duration(hours: 2)).toIso8601String(),
    );
    final diagnostic = state['diagnostics'] as Map;
    expect(diagnostic['outcome'], 'parse-failure');
    expect(diagnostic['httpStatus'], 200);
    expect(diagnostic['fetched'], true);
  });

  test(
    'overlong optional byline is omitted; required attribution still holds',
    () {
      final xml = fixture.rss(author: 'Publisher author ' * 30);
      final optional = fixture.parse(xml);
      expect(optional.items.single.attribution, isNull);
      final required = fixture.parse(
        xml,
        approved: fixture.source(author: true),
      );
      expect(required.items, isEmpty);
      expect(required.revokedIds, isEmpty);
      expect(
        required.rejectionReasons,
        containsPair('required-attribution-missing', 1),
      );
    },
  );

  test('known future publication cannot be converted to an undated story', () {
    final parsed = fixture.parse(fixture.rss(date: '2026-10-13T10:00:00Z'));
    expect(parsed.items, isEmpty);
    expect(parsed.rejectionReasons, containsPair('future-publication', 1));
    expect(parsed.revokedIds, isEmpty);
  });

  testWidgets(
    'restored controller automatically gives deferred endpoints their fair turn',
    (tester) async {
      var time = fixture.now;
      final sources = List.generate(
        17,
        (index) =>
            fixture.source(id: 'publisher-$index', feedPath: '/feeds/$index'),
      );
      final transport = fixture.FakeTransport(
        List.generate(
          17,
          (index) => fixture.response(fixture.rss(path: 'story-$index')),
        ),
      );
      final store = MemorySignatureDocumentStore();
      LiveContentController create() => LiveContentController(
        store: store,
        eligibility: fixture.gate(sources),
        provider: RssFeedProvider(
          registry: LiveSourceRegistry(sources),
          eligibility: fixture.gate(sources),
          allowsEditorialText: (_, _) => true,
          transport: transport,
          clock: () => time,
        ),
        clock: () => time,
      )..setContext(LiveContentContext.owner);
      final first = create();
      await first.refresh();
      expect(transport.calls, hasLength(12));
      expect(first.error, isNull);
      first.dispose();
      final restored = create();
      try {
        await restored.initialize();
        time = time.add(const Duration(seconds: 29));
        await tester.pump(const Duration(seconds: 29));
        expect(transport.calls, hasLength(12));
        time = time.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(transport.calls, hasLength(17));
        expect(restored.error, isNull);
        final state = await store.readDocument('liveContentRefreshState');
        expect((state!['scheduler'] as Map)['attemptedEndpoints'], 5);
        expect((state['scheduler'] as Map)['deferredSources'], 0);
        restored.setContext(LiveContentContext.private);
        time = time.add(const Duration(minutes: 31));
        await tester.pump(const Duration(minutes: 31));
        expect(transport.calls, hasLength(17));
        expect(restored.items, isEmpty);
      } finally {
        restored.dispose();
      }
    },
  );

  test('navigation/footer promotion cannot reject actual ordinary story', () {
    final result = fixture.parse(
      fixture.rss(
        title: 'Sports match report',
        desc:
            '<p>The home team won the match.</p><footer>betting casino bonus</footer><nav>pornography</nav>',
      ),
      allows: (title, excerpt) =>
          !excerpt.contains('casino') && !excerpt.contains('pornography'),
    );
    expect(result.items.single.excerpt, 'The home team won the match.');
    expect(result.revokedIds, isEmpty);
    final blocked = fixture.parse(
      fixture.rss(desc: '<p>betting casino bonus</p>'),
      allows: (title, excerpt) => !excerpt.contains('casino'),
    );
    expect(blocked.items, isEmpty);
    expect(blocked.revokedIds, isNotEmpty);
  });

  test('successful empty feed stays healthy during a not-due turn', () async {
    final source = fixture.source();
    final transport = fixture.FakeTransport([
      fixture.response('<rss><channel/></rss>'),
    ]);
    final provider = RssFeedProvider(
      registry: LiveSourceRegistry([source]),
      eligibility: fixture.gate([source]),
      allowsEditorialText: (_, _) => true,
      transport: transport,
      clock: () => fixture.now,
    );
    final first = await provider.fetch();
    expect(first.snapshot!.sources.single.status, 'fresh');
    expect(first.warning, isNull);
    final sourceState = (first.providerState!['sources'] as Map)['news'] as Map;
    expect(sourceState['diagnostics'], containsPair('outcome', 'empty'));
    expect(sourceState['diagnostics'], containsPair('parsedEntries', 0));
    provider.restore(snapshot: first.snapshot, state: first.providerState);
    final second = await provider.fetch();
    expect(second.snapshot!.sources.single.status, 'fresh');
    expect(second.warning, isNull);
    expect(transport.calls, hasLength(1));
    final diagnostic =
        ((second.providerState!['sources'] as Map)['news']
                as Map)['diagnostics']
            as Map;
    expect(diagnostic['outcome'], 'not-due');
    expect(diagnostic['requested'], false);
    expect(diagnostic['lastAttemptOutcome'], 'empty');
  });

  test('optional unchanged excerpt over display bound retains title/link', () {
    final base = fixture.source();
    final approved = ApprovedLiveSource.fromJson({
      ...base.source.toJson(),
      'enabled': true,
      'allowedArticleHosts': ['publisher.example'],
      'articlePathPrefixes': ['/news/'],
      'feedUrl': base.feedUri.toString(),
      'feedRedirectHosts': ['publisher.example'],
      'eligibilityScope': base.eligibilityScope,
      'preserveFeedText': true,
    });
    final parsed = fixture.parse(
      fixture.rss(desc: 'word ' * 500),
      approved: approved,
    );
    expect(parsed.items, hasLength(1));
    expect(parsed.items.single.excerpt, isNull);
    expect(parsed.revokedIds, isEmpty);
  });

  test('RSS Atom self-link before unnamespaced article link keeps article', () {
    final text = fixture.rss().replaceFirst(
      '<link>',
      '<atom:link xmlns:atom="http://www.w3.org/2005/Atom" href="https://publisher.example/feed/" rel="self"/><link>',
    );
    expect(fixture.parse(text).items, hasLength(1));
  });

  test('malformed entry does not permanently withdraw valid siblings', () {
    final text = fixture.rss().replaceFirst(
      '<item>',
      '<item><link>https://publisher.example/news/broken</link></item><item>',
    );
    final parsed = fixture.parse(text);
    expect(parsed.items, hasLength(1));
    expect(parsed.rejected, 1);
    expect(parsed.revokedIds, isEmpty);
  });

  test(
    'one publisher failure cannot make healthy category globally fail',
    () async {
      final sources = [
        fixture.source(id: 'a', feedPath: '/a/'),
        fixture.source(id: 'b', feedPath: '/b/'),
      ];
      final transport = fixture.FakeTransport([
        const RssFailure('http-429'),
        fixture.response(fixture.rss()),
      ]);
      final result = await RssFeedProvider(
        registry: LiveSourceRegistry(sources),
        eligibility: fixture.gate(sources),
        allowsEditorialText: (_, _) => true,
        transport: transport,
        clock: () => fixture.now,
      ).fetch();
      expect(result.warning, isNull);
    },
  );

  test(
    'no-store response removes cache but allows later lawful representation',
    () async {
      var time = fixture.now;
      final source = fixture.source();
      final transport = fixture.FakeTransport([
        fixture.response(fixture.rss()),
        fixture.response(fixture.rss(), headers: {'cache-control': 'no-store'}),
        fixture.response(fixture.rss()),
      ]);
      final provider = RssFeedProvider(
        registry: LiveSourceRegistry([source]),
        eligibility: fixture.gate([source]),
        allowsEditorialText: (_, _) => true,
        transport: transport,
        clock: () => time,
      );
      final first = await provider.fetch();
      provider.restore(snapshot: first.snapshot, state: first.providerState);
      time = time.add(const Duration(minutes: 31));
      final second = await provider.fetch();
      expect(second.snapshot!.items, isEmpty);
      expect(second.snapshot!.revokedItemIds, isEmpty);
      expect(second.warning, isNull);
      final diagnostic =
          ((second.providerState!['sources'] as Map)['news']
                  as Map)['diagnostics']
              as Map;
      expect(diagnostic['outcome'], 'cache-prohibited');
      expect(diagnostic['transportError'], isNull);
      provider.restore(snapshot: second.snapshot, state: second.providerState);
      time = time.add(const Duration(hours: 1));
      final third = await provider.fetch();
      expect(third.snapshot!.items, hasLength(1));
      expect(
        utf8.encode(jsonEncode(third.providerState)).length,
        lessThan(450 * 1024),
      );
    },
  );
}
