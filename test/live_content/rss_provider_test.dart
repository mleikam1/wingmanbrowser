import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/models.dart';
import 'package:wingman_browser/live_content/eligibility.dart';
import 'package:wingman_browser/live_content/rss_parser.dart';
import 'package:wingman_browser/live_content/rss_provider.dart';
import 'package:wingman_browser/live_content/rss_transport_native.dart';

final now = DateTime.utc(2026, 9, 13, 12);
ApprovedLiveSource source({
  String id = 'news',
  List<String> terms = const [],
  bool author = false,
  String topic = 'science',
  String format = 'path-prefix',
  List<String> paths = const ['/news/'],
  String feedPath = '/feed/',
}) => ApprovedLiveSource.fromJson({
  'id': id,
  'name': 'Publisher',
  'homepageUrl': 'https://publisher.example/',
  'language': 'en',
  'topics': [topic],
  'allowedArticleHosts': ['publisher.example'],
  'articlePathPrefixes': paths,
  'articleUrlFormat': format,
  'eligibilityScope': 'science-reporting',
  'enabled': true,
  'feedUrl': 'https://publisher.example$feedPath',
  'feedRedirectHosts': ['publisher.example'],
  'requiresAttribution': author,
  'requiredTopicTerms': terms,
  'rights': {
    'titles': true,
    'excerpts': true,
    'images': false,
    'attribution': 'Publisher',
    'licenseUrl': 'https://publisher.example/rights',
  },
});
LiveContentEligibility gate(Iterable<ApprovedLiveSource> sources) =>
    LiveContentEligibility(
      registry: LiveSourceRegistry(sources),
      canOpenDestination: (u) => !u.path.contains('blocked'),
    );
Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
String rss({
  String title = 'Science reporting',
  String desc = 'Publisher summary',
  String author = 'Researcher',
  String date = 'Sun, 13 Sep 2026 10:00:00 GMT',
  String path = 'one',
  String guid = 'one',
}) =>
    '<rss xmlns:dc="http://purl.org/dc/elements/1.1/"><channel><item><title>$title</title><link>https://publisher.example/news/$path</link><guid>$guid</guid><description><![CDATA[$desc]]></description><dc:creator>$author</dc:creator><pubDate>$date</pubDate></item></channel></rss>';
RssParsedFeed parse(
  String text, {
  ApprovedLiveSource? approved,
  bool Function(String, String)? allows,
}) {
  final s = approved ?? source();
  return parseRssFeed(bytes(text), s, now, gate([s]), allows ?? (_, _) => true);
}

class FakeTransport implements RssFeedTransport {
  final List<Object> results;
  FakeTransport(this.results);
  final calls = <Map<String, String>>[];
  int cancellations = 0;
  @override
  Future<RssFetchResponse> fetch(
    ApprovedLiveSource source,
    Map<String, String> validators,
  ) async {
    calls.add(Map.of(validators));
    final result = results.removeAt(0);
    if (result is Completer<RssFetchResponse>) return result.future;
    if (result is RssFetchResponse) return result;
    throw result;
  }

  @override
  void cancel() {
    cancellations++;
  }
}

RssFetchResponse response(
  String body, {
  Map<String, String> headers = const {},
}) => RssFetchResponse(200, bytes(body), headers);
void main() {
  group('bounded RSS and Atom normalization', () {
    test('publisher title summary author and actual publication date', () {
      final item = parse(rss()).items.single;
      expect(item.title, 'Science reporting');
      expect(item.attribution, 'Researcher');
      expect(item.publishedAt, DateTime.utc(2026, 9, 13, 10));
      expect(item.imageUrl, isNull);
      expect(item.id, rssDigest('https://publisher.example/news/one'));
    });
    test('missing publication stays null; Atom updated is not publication', () {
      expect(parse(rss(date: '')).items.single.publishedAt, isNull);
      final x = parse(
        '<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Science</title><updated>2026-09-13T10:00:00Z</updated><link href="https://evil.example/a"/><link href="https://publisher.example/news/a"/><author><name>A Person</name></author></entry></feed>',
      );
      expect(x.items.single.publishedAt, isNull);
      expect(x.items.single.attribution, 'A Person');
    });
    test('EDT date converts; unknown and naive dates stay null', () {
      expect(
        rssDate('Fri, 11 Sep 2026 10:00:00 EDT', now),
        DateTime.utc(2026, 9, 11, 14),
      );
      expect(rssDate('2026-09-13T10:00:00', now), isNull);
      expect(rssDate('11 Sep 2026 10:00:00 XYZ', now), isNull);
    });
    test('ISO calendar or clock overflow never invents a publication date', () {
      for (final invalid in [
        '2026-02-31T10:00:00Z',
        '2026-13-01T10:00:00Z',
        '2026-09-13T24:00:00Z',
        '2026-09-13T12:60:00Z',
        '2026-09-13T12:30:60Z',
        '2026-09-13T12:30:00+25:00',
      ]) {
        expect(rssDate(invalid, now), isNull, reason: invalid);
      }
      expect(
        rssDate('2026-09-13T12:30:00.123-04:00', now),
        DateTime.utc(2026, 9, 13, 16, 30, 0, 123),
      );
    });
    test(
      'full text reviewed before excerpt truncation and never encoded content',
      () {
        var reviewed = '';
        final x = parse(
          rss(desc: '${'a' * 600} blocked promotion'),
          allows: (t, e) {
            reviewed = e;
            return !e.contains('blocked promotion');
          },
        );
        expect(x.items, isEmpty);
        expect(reviewed, contains('blocked promotion'));
        final y = parse(
          rss().replaceAll(
            '</item>',
            '<content:encoded xmlns:content="urn:content">SECRET FULL TEXT</content:encoded></item>',
          ),
        );
        expect(y.items.single.excerpt, isNot(contains('SECRET')));
      },
    );
    test('HTML embeds and scripts removed; no remote artwork', () {
      final item = parse(
        rss(
          desc:
              '<p>Plain</p><img src="https://evil.example/pixel"><script>secret</script><iframe>hidden</iframe>',
        ),
      ).items.single;
      expect(item.excerpt, 'Plain');
    });
    test('DTD entity declarations and malformed XML rejected', () {
      for (final value in [
        '<!DOCTYPE rss [<!ENTITY e SYSTEM "file:///etc/passwd">]><rss/>',
        '<!DOCTYPE rss><rss/>',
        '<rss><channel>',
      ]) {
        expect(() => parse(value), throwsA(anything));
      }
    });
    test('depth node entry and byte caps', () {
      expect(
        () => parse('<rss>${'<x>' * 65}${'</x>' * 65}</rss>'),
        throwsA(isA<RssFailure>()),
      );
      expect(
        () => parse('<rss><channel>${'<item/>' * 501}</channel></rss>'),
        throwsA(isA<RssFailure>()),
      );
      expect(
        () => parse('x' * (rssMaximumXmlBytes + 1)),
        throwsA(isA<RssFailure>()),
      );
    });
    test('rights hold, author requirements and positive topic evidence', () {
      expect(
        parse(rss(author: ''), approved: source(author: true)).items,
        isEmpty,
      );
      expect(
        parse(
          rss(title: 'Research'),
          approved: source(terms: ['fashion designer']),
        ).items,
        isEmpty,
      );
      expect(
        parse(
          rss(title: 'A fashion designer discusses craft'),
          approved: source(terms: ['fashion designer']),
        ).items,
        hasLength(1),
      );
      expect(parse(rss(desc: 'All rights reserved')).items, isEmpty);
    });
    test('exact host path scopes tracking and duplicate IDs', () {
      final s = source();
      expect(rssCanonical('https://publisher.example.evil/news/a', s), isNull);
      expect(rssCanonical('https://publisher.example/newspaper/a', s), isNull);
      expect(
        rssCanonical('https://publisher.example/news/%2e%2e/a', s),
        isNull,
      );
      expect(
        rssCanonical(
          'https://publisher.example/news/a?utm_source=x&amp;x=2#fragment',
          s,
        ).toString(),
        'https://publisher.example/news/a?x=2',
      );
    });
    test('old publication dropped and policy denied address excluded', () {
      expect(parse(rss(date: 'Sun, 02 Aug 2026 10:00:00 GMT')).items, isEmpty);
      expect(parse(rss(path: 'blocked')).items, isEmpty);
    });
    test(
      'dated-story pin is structural and section misses are not withdrawals',
      () {
        final s = source(format: 'dated-story', paths: ['/']);
        expect(
          rssCanonical('https://publisher.example/2026/09/13/story/', s),
          isNotNull,
        );
        for (final path in [
          '/2026/09/13/',
          '/news/a',
          '/2026/09/13/story/extra',
          '/2026/9/13/story',
        ]) {
          expect(rssCanonical('https://publisher.example$path', s), isNull);
        }
        final narrow = parse(
          rss(title: 'Sports report'),
          approved: source(terms: ['fashion designer']),
        );
        expect(narrow.items, isEmpty);
        expect(narrow.revokedIds, isEmpty);
        expect(narrow.guidToItem, isEmpty);
      },
    );
  });
  group('configured transport policy', () {
    test(
      'safety and rights withdrawals precede section omission; attribution holds',
      () {
        final narrow = source(terms: ['fashion designer'], author: true);
        for (final body in [
          rss(title: 'Sports report', desc: 'All rights reserved'),
          rss(title: 'Sports report', author: ''),
          rss(title: 'Sports report', desc: 'Sponsored partner'),
        ]) {
          final result = parse(
            body,
            approved: narrow,
            allows: (title, excerpt) => !excerpt.contains('Sponsored'),
          );
          expect(result.items, isEmpty);
          expect(
            result.revokedIds,
            body.contains('<dc:creator></dc:creator>')
                ? isEmpty
                : contains(rssDigest('https://publisher.example/news/one')),
          );
        }
      },
    );
    test('reject private reserved mapped and translation addresses', () {
      for (final ip in [
        '0.0.0.0',
        '10.1.2.3',
        '127.0.0.1',
        '100.64.0.1',
        '169.254.169.254',
        '172.31.1.1',
        '192.168.1.1',
        '192.0.2.1',
        '198.51.100.1',
        '203.0.113.1',
        '224.1.1.1',
        '::1',
        'fc00::1',
        'fe80::1',
        '::ffff:127.0.0.1',
        '64:ff9b::808:808',
        '2001:db8::1',
        '3fff::1',
      ]) {
        expect(isPublicRssAddress(InternetAddress(ip)), false, reason: ip);
      }
      for (final ip in [
        '8.8.8.8',
        '192.0.78.9',
        '2606:4700::1111',
        '::ffff:8.8.8.8',
      ]) {
        expect(isPublicRssAddress(InternetAddress(ip)), true, reason: ip);
      }
    });
    test('URL whitelist credentials downgrade and redirect destinations', () {
      for (final url in [
        'http://publisher.example/feed',
        'https://user@publisher.example/feed',
        'https://127.0.0.1/feed',
        'https://publisher.example.evil/feed',
        'https://publisher.example:8443/feed',
        'https://publisher.example/feed#x',
      ]) {
        expect(
          () => checkedRssUri(Uri.parse(url), source()),
          throwsA(isA<RssFailure>()),
        );
      }
      expect(
        checkedRssUri(
          Uri.parse('https://publisher.example/feed/?s=fashion'),
          source(),
        ).host,
        'publisher.example',
      );
    });
    test('mixed DNS rejected before any socket connection', () async {
      final t = NativeRssFeedTransport(
        resolver: (_) async => [
          InternetAddress('8.8.8.8'),
          InternetAddress('127.0.0.1'),
        ],
      );
      await expectLater(
        t.fetch(source(), {}),
        throwsA(
          isA<RssFailure>().having((e) => e.code, 'code', 'non-public-dns'),
        ),
      );
    });
    test('cancellation while DNS pending prevents later connection', () async {
      final pending = Completer<List<InternetAddress>>();
      final t = NativeRssFeedTransport(resolver: (_) => pending.future);
      final work = t.fetch(source(), {});
      t.cancel();
      pending.complete([InternetAddress('8.8.8.8')]);
      await expectLater(
        work,
        throwsA(isA<RssFailure>().having((e) => e.code, 'code', 'cancelled')),
      );
    });
  });
  group('durable refresh state and bounded snapshots', () {
    test(
      '30min pacing survives provider restore and disposable snapshot clear',
      () async {
        var time = now;
        final s = source(),
            t = FakeTransport([
              response(rss(), headers: {'etag': '"v1"'}),
            ]);
        final p = RssFeedProvider(
          registry: LiveSourceRegistry([s]),
          eligibility: gate([s]),
          allowsEditorialText: (_, _) => true,
          transport: t,
          clock: () => time,
        );
        final first = await p.fetch();
        expect(first.snapshot!.items, hasLength(1));
        p.restore(state: first.providerState, snapshot: null);
        time = time.add(const Duration(minutes: 1));
        final next = await p.fetch();
        expect(t.calls, hasLength(1));
        expect(next.snapshot!.sources.single.status, 'fresh');
        expect(next.warning, isNull);
      },
    );
    test('304 uses source validators and retains publication', () async {
      var time = now;
      final s = source(),
          t = FakeTransport([
            response(rss(), headers: {'etag': '"v1"'}),
            RssFetchResponse(304, Uint8List(0), {}),
          ]);
      final p = RssFeedProvider(
        registry: LiveSourceRegistry([s]),
        eligibility: gate([s]),
        allowsEditorialText: (_, _) => true,
        transport: t,
        clock: () => time,
      );
      final first = await p.fetch();
      p.restore(snapshot: first.snapshot, state: first.providerState);
      time = time.add(const Duration(minutes: 31));
      final next = await p.fetch();
      expect(t.calls.last, {'If-None-Match': '"v1"'});
      expect(
        next.snapshot!.items.single.publishedAt,
        first.snapshot!.items.single.publishedAt,
      );
      expect(next.snapshot!.items.single.fetchedAt, time);
    });
    test(
      'partial failure retains every source and shows usable content',
      () async {
        final a = source(id: 'a', feedPath: '/feed/a'),
            b = source(id: 'b', feedPath: '/feed/b');
        final t = FakeTransport([
          const RssFailure('http-429', headers: {'retry-after': '7200'}),
          response(rss()),
        ]);
        final p = RssFeedProvider(
          registry: LiveSourceRegistry([a, b]),
          eligibility: gate([a, b]),
          allowsEditorialText: (_, _) => true,
          transport: t,
          clock: () => now,
        );
        final r = await p.fetch();
        expect(r.snapshot!.sources, hasLength(2));
        expect(r.snapshot!.items, hasLength(1));
        expect(r.warning, isNull);
        expect(
          r.snapshot!.sources.first.nextRefreshAt,
          now.add(const Duration(hours: 2)),
        );
      },
    );
    test(
      'no-store removes prior cached text without legal revocation',
      () async {
        var time = now;
        final s = source(),
            t = FakeTransport([
              response(rss()),
              response(rss(), headers: {'cache-control': 'no-store'}),
            ]);
        final p = RssFeedProvider(
          registry: LiveSourceRegistry([s]),
          eligibility: gate([s]),
          allowsEditorialText: (_, _) => true,
          transport: t,
          clock: () => time,
        );
        final first = await p.fetch();
        p.restore(snapshot: first.snapshot, state: first.providerState);
        time = time.add(const Duration(minutes: 31));
        final r = await p.fetch();
        expect(r.snapshot!.items, isEmpty);
        expect(r.snapshot!.revokedItemIds, isEmpty);
      },
    );
    test('cancelled response cannot produce candidate state', () async {
      final pending = Completer<RssFetchResponse>(),
          s = source(),
          t = FakeTransport([]);
      t.results.add(pending);
      final p = RssFeedProvider(
        registry: LiveSourceRegistry([s]),
        eligibility: gate([s]),
        allowsEditorialText: (_, _) => true,
        transport: t,
        clock: () => now,
      );
      final work = p.fetch();
      p.cancel();
      pending.complete(response(rss()));
      await expectLater(work, throwsA(isA<RssFailure>()));
    });
    test(
      'narrow sections retain priority without globally revoking other topics',
      () async {
        final fashion = source(
          id: 'fashion',
          topic: 'fashion',
          terms: ['fashion designer'],
        );
        final sports = source(id: 'sports', topic: 'sports');
        final general = source(id: 'general');
        final transport = FakeTransport([
          response(rss(title: 'Sports report')),
          response(rss(title: 'Sports report')),
          response(rss(title: 'Sports report')),
        ]);
        final sources = [fashion, sports, general];
        final provider = RssFeedProvider(
          registry: LiveSourceRegistry(sources),
          eligibility: gate(sources),
          allowsEditorialText: (_, _) => true,
          transport: transport,
          clock: () => now,
        );
        final result = await provider.fetch();
        expect(result.snapshot!.items.single.sourceId, 'sports');
        expect(result.snapshot!.items.single.topics, {'sports'});
        expect(result.snapshot!.revokedItemIds, isEmpty);
      },
    );
    test(
      'Atom tombstone withdraws admitted GUID across restart and cache clearing',
      () async {
        var time = now;
        final s = source();
        final transport = FakeTransport([
          response(rss(guid: 'urn:story:one')),
          response(
            '<feed xmlns="http://www.w3.org/2005/Atom" xmlns:at="http://purl.org/atompub/tombstones/1.0"><at:deleted-entry ref="urn:story:one" when="2026-09-13T12:30:00Z"/></feed>',
          ),
          response(rss()),
        ]);
        RssFeedProvider provider() => RssFeedProvider(
          registry: LiveSourceRegistry([s]),
          eligibility: gate([s]),
          allowsEditorialText: (_, _) => true,
          transport: transport,
          clock: () => time,
        );
        final first = await provider().fetch();
        final secondProvider = provider()
          ..restore(snapshot: first.snapshot, state: first.providerState);
        time = time.add(const Duration(minutes: 31));
        final second = await secondProvider.fetch();
        expect(second.snapshot!.items, isEmpty);
        expect(
          second.snapshot!.revokedItemIds,
          contains(first.snapshot!.items.single.id),
        );
        final thirdProvider = provider()..restore(state: second.providerState);
        time = time.add(const Duration(minutes: 31));
        final third = await thirdProvider.fetch();
        expect(third.snapshot!.items, isEmpty);
        expect(
          third.snapshot!.revokedItemIds,
          contains(first.snapshot!.items.single.id),
        );
      },
    );
    test(
      'all-source timeout state preserves health and prevents restart hammering',
      () async {
        final s = source(),
            transport = FakeTransport([const RssFailure('timeout')]);
        RssFeedProvider provider() => RssFeedProvider(
          registry: LiveSourceRegistry([s]),
          eligibility: gate([s]),
          allowsEditorialText: (_, _) => true,
          transport: transport,
          clock: () => now,
        );
        final first = await provider().fetch();
        expect(first.snapshot!.items, isEmpty);
        expect(first.snapshot!.sources.single.status, 'unavailable');
        expect(first.warning, isNotNull);
        final restored = provider()..restore(state: first.providerState);
        final second = await restored.fetch();
        expect(
          second.snapshot!.sources.single.nextRefreshAt,
          now.add(const Duration(minutes: 30)),
        );
        expect(transport.calls, hasLength(1));
      },
    );
    test(
      'three lanes bound concurrency and stop launching requests on cancel',
      () async {
        final pending = List.generate(3, (_) => Completer<RssFetchResponse>());
        final transport = FakeTransport(List<Object>.of(pending));
        final sources = List.generate(
          10,
          (i) => source(id: 'source-$i', feedPath: '/feed/$i'),
        );
        final provider = RssFeedProvider(
          registry: LiveSourceRegistry(sources),
          eligibility: gate(sources),
          allowsEditorialText: (_, _) => true,
          transport: transport,
          clock: () => now,
        );
        final result = provider.fetch();
        expect(transport.calls, hasLength(3));
        provider.cancel();
        final expectation = expectLater(result, throwsA(isA<RssFailure>()));
        for (final waiter in pending) {
          waiter.complete(response(rss()));
        }
        await expectation;
        expect(transport.calls, hasLength(3));
      },
    );
    test('long publisher holds are never shortened', () {
      expect(
        rssRefreshDelay({'cache-control': 'max-age=172800'}, now, 1800),
        const Duration(days: 2),
      );
      expect(
        rssRefreshDelay({'retry-after': '9999999999999999999'}, now, 1800),
        isNull,
      );
    });
  });
}
