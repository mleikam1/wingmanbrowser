import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/models.dart';
import 'package:wingman_browser/live_content/rss_provider.dart';

import 'rss_provider_test.dart' as fixture;

class ScheduledTransport implements RssFeedTransport {
  ScheduledTransport(this.result);
  final Future<RssFetchResponse> Function(ApprovedLiveSource) result;
  final urls = <String>[];
  final validators = <Map<String, String>>[];
  final hosts = <Set<String>>[];
  int cancellations = 0;
  @override
  Future<RssFetchResponse> fetch(
    ApprovedLiveSource source,
    Map<String, String> headers,
  ) {
    urls.add(source.feedUri.toString());
    validators.add(Map.of(headers));
    hosts.add(Set.of(source.feedRedirectHosts));
    return result(source);
  }

  @override
  void cancel() => cancellations++;
}

void main() {
  test(
    'duplicate prefers approved image record without mixing source rights',
    () async {
      final text = fixture.source(id: 'text-source', topic: 'science');
      final photo = ApprovedLiveSource.fromJson({
        ...text.source.toJson(),
        'id': 'photo-source',
        'topics': ['technology'],
        'enabled': true,
        'allowedArticleHosts': ['publisher.example'],
        'articlePathPrefixes': ['/news/'],
        'eligibilityScope': 'science-reporting',
        'feedUrl': 'https://publisher.example/photo-feed/',
        'feedRedirectHosts': ['publisher.example'],
        'rights': {'titles': true, 'excerpts': true, 'images': true},
        'imagePolicy': {
          'kind': 'syndicated-feed-thumbnail',
          'allowedHosts': ['images.publisher.example'],
          'pathPrefixes': ['/thumb/'],
          'licenseUrl': 'https://publisher.example/photo-rights',
          'licenseLabel': 'Photo feed terms',
          'credit': 'Photo publisher',
          'maximumWidth': 90,
          'maximumHeight': 90,
        },
      });
      final transport = ScheduledTransport(
        (source) async => fixture.response(
          fixture
              .rss(desc: source.source.id)
              .replaceFirst(
                '</item>',
                '<media:thumbnail xmlns:media="http://search.yahoo.com/mrss/" '
                    'url="https://images.publisher.example/thumb/one.jpg" width="90" height="90"/></item>',
              ),
        ),
      );
      Future<LiveContentItem> fetch(List<ApprovedLiveSource> sources) async =>
          (await RssFeedProvider(
            registry: LiveSourceRegistry(sources),
            eligibility: fixture.gate(sources),
            allowsEditorialText: (_, _) => true,
            transport: transport,
            clock: () => fixture.now,
          ).fetch()).snapshot!.items.single;
      for (final sources in [
        [text, photo],
        [photo, text],
      ]) {
        final item = await fetch(sources);
        expect(item.sourceId, 'photo-source');
        expect(item.excerpt, 'photo-source');
        expect(item.topics, {'technology'});
        expect(item.rights.images, isTrue);
        expect(item.image!.credit, 'Photo publisher');
        expect(fixture.gate(sources).imageFor(item), isNotNull);
      }
    },
  );

  test(
    'twelve unique endpoints per refresh resume fairly without fake failures',
    () async {
      final sources = List.generate(
        30,
        (i) => fixture.source(id: 'publisher-$i', feedPath: '/feeds/$i'),
      );
      final transport = ScheduledTransport(
        (_) async => fixture.response(fixture.rss()),
      );
      RssFeedProvider create() => RssFeedProvider(
        registry: LiveSourceRegistry(sources),
        eligibility: fixture.gate(sources),
        allowsEditorialText: (_, _) => true,
        transport: transport,
        clock: () => fixture.now,
      );
      final first = await create().fetch();
      expect(transport.urls, hasLength(12));
      expect(first.snapshot!.sources, hasLength(30));
      final states = first.providerState!['sources'] as Map;
      expect((states['publisher-20'] as Map)['nextRefreshAt'], isNull);
      expect((states['publisher-20'] as Map)['failures'], isNull);
      expect((states['publisher-20'] as Map)['error'], isNull);
      expect((first.providerState!['scheduler'] as Map)['deferredSources'], 18);
      expect(first.warning, isNull);
      expect(
        (first.providerState!['scheduler'] as Map)['nextRefreshAt'],
        fixture.now.add(const Duration(seconds: 30)).toIso8601String(),
      );
      expect(
        (states['publisher-20'] as Map)['diagnostics'],
        containsPair('outcome', 'deferred'),
      );
      final secondProvider = create()
        ..restore(snapshot: first.snapshot, state: first.providerState);
      final second = await secondProvider.fetch();
      expect(transport.urls, hasLength(24));
      final thirdProvider = create()
        ..restore(snapshot: second.snapshot, state: second.providerState);
      final third = await thirdProvider.fetch();
      expect(transport.urls, hasLength(30));
      expect(
        (third.providerState!['scheduler'] as Map)['nextRefreshAt'],
        fixture.now.add(const Duration(minutes: 30)).toIso8601String(),
      );
      expect(transport.urls.toSet(), hasLength(30));
      expect(
        (third.providerState!['scheduler'] as Map)['attemptedEndpoints'],
        6,
      );
      final fourth = create()
        ..restore(snapshot: third.snapshot, state: third.providerState);
      await fourth.fetch();
      expect(transport.urls, hasLength(30));
    },
  );

  test(
    'shared endpoint fetches once but retains separate source decisions and health',
    () async {
      var now = fixture.now;
      final sources = [
        fixture.source(id: 'brand-one'),
        fixture.source(id: 'brand-two'),
      ];
      final transport = ScheduledTransport(
        (_) async => fixture.response(fixture.rss(), headers: {'etag': '"v1"'}),
      );
      final provider = RssFeedProvider(
        registry: LiveSourceRegistry(sources),
        eligibility: fixture.gate(sources),
        allowsEditorialText: (_, _) => true,
        transport: transport,
        clock: () => now,
      );
      final first = await provider.fetch();
      expect(transport.urls, hasLength(1));
      expect(first.snapshot!.sources.map((s) => s.id), [
        'brand-one',
        'brand-two',
      ]);
      provider.restore(snapshot: first.snapshot, state: first.providerState);
      now = now.add(const Duration(minutes: 31));
      await provider.fetch();
      expect(transport.urls, hasLength(2));
      // URL dedup retained only one alias's item. The other needs the full body;
      // shared conditional requests must not strand it with unusable 304 data.
      expect(transport.validators.last, isEmpty);
    },
  );

  test('one alias cannot bypass another alias Retry-After hold', () async {
    final sources = [
      fixture.source(id: 'brand-one'),
      fixture.source(id: 'brand-two'),
    ];
    final transport = ScheduledTransport(
      (_) async => fixture.response(fixture.rss()),
    );
    final provider =
        RssFeedProvider(
          registry: LiveSourceRegistry(sources),
          eligibility: fixture.gate(sources),
          allowsEditorialText: (_, _) => true,
          transport: transport,
          clock: () => fixture.now,
        )..restore(
          state: {
            'schemaVersion': 1,
            'sources': {
              'brand-one': {
                'nextRefreshAt': fixture.now
                    .add(const Duration(hours: 2))
                    .toIso8601String(),
                'failures': 1,
                'error': 'http-429',
              },
            },
          },
        );
    final response = await provider.fetch();
    expect(transport.urls, isEmpty);
    expect(
      (response.providerState!['sources'] as Map)['brand-two']['nextRefreshAt'],
      isNull,
    );
    expect((response.providerState!['scheduler'] as Map)['deferredSources'], 1);
  });

  test(
    'deadline cursor advances only through started work and later sources resume',
    () async {
      final sources = List.generate(
        8,
        (i) => fixture.source(id: 'publisher-$i', feedPath: '/feeds/$i'),
      );
      final pending = Completer<RssFetchResponse>();
      final slow = ScheduledTransport((_) => pending.future);
      final firstProvider = RssFeedProvider(
        registry: LiveSourceRegistry(sources),
        eligibility: fixture.gate(sources),
        allowsEditorialText: (_, _) => true,
        transport: slow,
        clock: () => fixture.now,
      );
      // Compress only the provider's long deadline timers in this test zone;
      // the production constant remains 45 seconds and actual start order remains.
      final work = runZoned(
        firstProvider.fetch,
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) =>
              parent.createTimer(
                zone,
                duration >= const Duration(seconds: 40)
                    ? const Duration(milliseconds: 5)
                    : duration,
                callback,
              ),
        ),
      );
      expect(slow.urls, hasLength(3));
      final first = await work;
      expect(slow.urls, hasLength(3));
      expect(
        (first.providerState!['scheduler'] as Map)['cursorAfter'],
        'https://publisher.example/feeds/2',
      );
      expect(
        (first.providerState!['sources'] as Map)['publisher-3']['error'],
        isNull,
      );
      final fast = ScheduledTransport(
        (_) async => fixture.response(fixture.rss()),
      );
      final resumed = RssFeedProvider(
        registry: LiveSourceRegistry(sources),
        eligibility: fixture.gate(sources),
        allowsEditorialText: (_, _) => true,
        transport: fast,
        clock: () => fixture.now,
      )..restore(snapshot: first.snapshot, state: first.providerState);
      await resumed.fetch();
      expect(fast.urls, hasLength(5));
      expect(fast.urls.first, 'https://publisher.example/feeds/3');
      pending.complete(fixture.response(fixture.rss()));
    },
  );

  test('invalid persisted scheduling cursor is not silently reset', () {
    final sources = [fixture.source()];
    final provider = RssFeedProvider(
      registry: LiveSourceRegistry(sources),
      eligibility: fixture.gate(sources),
      allowsEditorialText: (_, _) => true,
    );
    expect(
      () => provider.restore(
        state: {
          'schemaVersion': 1,
          'sources': {},
          'scheduler': {'schemaVersion': 1, 'cursorAfter': 7},
        },
      ),
      throwsFormatException,
    );
  });
}
