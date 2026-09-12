import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

final now = DateTime.utc(2026, 9, 11, 12);
Map<String, Object?> sourceJson({
  bool excerpts = true,
  String status = 'fresh',
}) => {
  'id': 'science',
  'name': 'Public science publisher',
  'homepageUrl': 'https://science.example/news',
  'language': 'en',
  'topics': ['science', 'technology'],
  'status': status,
  'rights': {
    'titles': true,
    'excerpts': excerpts,
    'images': false,
    'attribution': 'Source: Science',
    'licenseUrl': 'https://science.example/rights',
  },
};
LiveSourceRegistry registry() => LiveSourceRegistry.fromJson({
  'schemaVersion': 1,
  'sources': [
    {
      ...sourceJson(),
      'allowedArticleHosts': ['science.example'],
      'articlePathPrefixes': ['/reports/'],
      'eligibilityScope': 'science-reporting',
      'enabled': true,
    },
  ],
});
Map<String, Object?> itemJson(
  int id, {
  String? title,
  String topic = 'science',
}) => {
  'id': 'item-$id',
  'sourceId': 'science',
  'title': title ?? 'Science report $id',
  'excerpt': 'A public science report.',
  'canonicalUrl': 'https://science.example/reports/$id',
  'publishedAt': now.subtract(Duration(minutes: id)).toIso8601String(),
  'fetchedAt': now.toIso8601String(),
  'expiresAt': now.add(const Duration(days: 7)).toIso8601String(),
  'language': 'en',
  'topics': [topic],
  'rights': {'title': true, 'excerpt': true, 'image': false},
  'eligibility': {
    'state': 'eligible',
    'basis': 'curated-source-scope',
    'scope': 'science-reporting',
  },
};
Map<String, Object?> snapshotJson({
  int count = 18,
  List<Object?>? items,
  List<Object?>? sources,
  List<String> revokedItems = const [],
  List<String> revokedSources = const [],
  String status = 'fresh',
}) => {
  'schemaVersion': 1,
  'snapshotId': 'snapshot-1',
  'generatedAt': now.toIso8601String(),
  'expiresAt': now.add(const Duration(minutes: 15)).toIso8601String(),
  'sources': sources ?? [sourceJson(status: status)],
  'items':
      items ??
      List.generate(
        count,
        (i) => itemJson(i, topic: i.isEven ? 'science' : 'technology'),
      ),
  'revokedItemIds': revokedItems,
  'revokedSourceIds': revokedSources,
};
LiveSnapshot snapshot({int count = 18}) =>
    LiveSnapshot.fromJson(snapshotJson(count: count));

class FakeProvider implements FeedProvider {
  FeedResponse? response = FeedResponse(snapshot: snapshot(), etag: '"one"');
  Object? failure;
  Completer<FeedResponse>? pending;
  int calls = 0, cancellations = 0;
  String? lastEtag, lastModified;
  @override
  Future<FeedResponse> fetch({String? etag, String? lastModified}) async {
    calls++;
    lastEtag = etag;
    this.lastModified = lastModified;
    if (failure != null) throw failure!;
    return pending?.future ?? response!;
  }

  @override
  void cancel() {
    cancellations++;
  }
}

class TestStore extends MemorySignatureDocumentStore {
  bool failWrites = false;
  int reads = 0, writes = 0;
  @override
  Future<Map<String, Object?>?> readDocument(String key) {
    reads++;
    return super.readDocument(key);
  }

  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) async {
    writes++;
    if (failWrites) throw StateError('disk unavailable private details');
    await super.writeDocument(key, value);
  }
}

class TestTransport implements FeedTransport {
  FeedTransportResponse response = FeedTransportResponse(
    200,
    Uint8List.fromList(utf8.encode(jsonEncode(snapshotJson()))),
    {'content-type': 'application/json', 'etag': '"one"'},
  );
  Uri? url;
  Map<String, String>? headers;
  @override
  Future<FeedTransportResponse> get(
    Uri endpoint,
    Map<String, String> headers,
  ) async {
    url = endpoint;
    this.headers = headers;
    return response;
  }

  @override
  void cancel() {}
}

LiveContentController makeController({
  SignatureDocumentStore? store,
  FeedProvider? provider,
  DateTime Function()? clock,
  bool Function(Uri)? canOpen,
}) => LiveContentController(
  store: store ?? MemorySignatureDocumentStore(),
  provider: provider,
  eligibility: LiveContentEligibility(
    registry: registry(),
    canOpenDestination: canOpen ?? (_) => true,
  ),
  clock: clock ?? () => now,
)..setContext(LiveContentContext.owner);
void main() {
  test(
    'canonical URL preserves exact unfragmented address and removes actual fragment',
    () {
      expect(
        feedArticleUri('https://science.example/news').toString(),
        'https://science.example/news',
      );
      expect(
        feedArticleUri('https://science.example/news#part').toString(),
        'https://science.example/news',
      );
    },
  );
  test(
    'snapshot preserves source, canonical URL, nullable publisher date and credits; removes remote images',
    () {
      final value = itemJson(1)
        ..['publishedAt'] = null
        ..['image'] = {'url': 'https://evil.example/track'}
        ..['attribution'] = 'Author: Example';
      final item = LiveContentItem.fromJson(value);
      expect(item.publishedAt, isNull);
      expect(item.fetchedAt, now);
      expect(item.canonicalUrl.toString(), 'https://science.example/reports/1');
      expect(item.attribution, 'Author: Example');
      expect(item.imageUrl, isNull);
      expect(item.toJson()['image'], isNull);
      expect(
        LiveContentItem.fromJson(item.toJson()).attribution,
        'Author: Example',
      );
    },
  );
  test(
    'malformed rows are skipped without hiding good rows; duplicate URLs deduplicate',
    () {
      final parsed = LiveSnapshot.fromJson(
        snapshotJson(
          items: [
            itemJson(1),
            {
              ...itemJson(2),
              'canonicalUrl': 'https://science.example/reports/1',
            },
            {...itemJson(3), 'title': '<img src=x>'},
            {...itemJson(4), 'canonicalUrl': 'javascript:alert(1)'},
          ],
        ),
      );
      expect(parsed.items.length, 1);
      expect(parsed.rejectedItems, 2);
    },
  );
  test(
    'unapproved source, host siblings, false scope and unlicensed excerpts cannot enter feed',
    () {
      final gate = LiveContentEligibility(
        registry: registry(),
        canOpenDestination: (_) => true,
      );
      for (final mutation in [
        {'sourceId': 'other'},
        {'canonicalUrl': 'https://other.science.example/a'},
        {'canonicalUrl': 'https://science.example/shop/promotion'},
        {'canonicalUrl': 'https://science.example/reports/%2e%2e/shop'},
        {
          'eligibility': {
            'state': 'eligible',
            'basis': 'keywords',
            'scope': 'science-reporting',
          },
        },
        {
          'rights': {'title': true, 'excerpt': false},
        },
        {
          'topics': ['gambling'],
        },
        {'language': 'es'},
      ]) {
        expect(
          gate.accepts(
            LiveContentItem.fromJson({...itemJson(1), ...mutation}),
            now: now,
          ),
          isFalse,
        );
      }
    },
  );
  test(
    'education and reporting allowed, obvious prohibited-product promotion excluded',
    () {
      final gate = LiveContentEligibility(
        registry: registry(),
        canOpenDestination: (_) => true,
      );
      for (final title in [
        'Research reports risks of nicotine addiction',
        'Study investigates alcohol advertising policy',
        'Scientists report gambling addiction prevention research',
      ]) {
        expect(
          gate.accepts(
            LiveContentItem.fromJson(itemJson(1, title: title)),
            now: now,
          ),
          isTrue,
          reason: title,
        );
      }
      for (final title in [
        'Buy nicotine vapes now',
        'Casino free spins and deposit bonus',
        'Exclusive alcohol discount deal',
      ]) {
        expect(
          gate.accepts(
            LiveContentItem.fromJson(itemJson(1, title: title)),
            now: now,
          ),
          isFalse,
          reason: title,
        );
      }
    },
  );
  test(
    'expiry removes feed but saved entry remains usable subject to current policy',
    () async {
      var clock = now;
      var allowed = true;
      final c = makeController(
        provider: FakeProvider(),
        clock: () => clock,
        canOpen: (_) => allowed,
      );
      await c.refresh();
      final item = c.items.first;
      await c.save(item);
      clock = now.add(const Duration(days: 8));
      expect(c.items, isEmpty);
      expect(c.savedItems.single.available, isTrue);
      expect(c.canOpen(item), isTrue);
      allowed = false;
      c.recheckEligibility();
      expect(c.savedItems.single.item, isNull);
      expect(c.canOpen(item), isFalse);
    },
  );
  test(
    'finite initial page, explicit more, local filters and dismissals never request provider',
    () async {
      final provider = FakeProvider();
      final c = makeController(provider: provider);
      await c.refresh();
      expect(c.items.length, 12);
      expect(c.hasMore, isTrue);
      c.loadMore();
      expect(c.items.length, 18);
      expect(c.hasMore, isFalse);
      await c.selectTopics({'technology'});
      expect(c.items.length, 9);
      await c.dismiss(c.items.first.id);
      expect(c.items.length, 8);
      await c.selectTopics({});
      expect(c.items.length, 12);
      await c.hideSource('science');
      expect(c.items, isEmpty);
      await c.followSource('science');
      expect(c.items, isNotEmpty);
      await c.showFewerTopic('science');
      expect(c.items.first.topics, {'technology'});
      await c.setLanguage('es');
      expect(c.items, isEmpty);
      await c.resetPreferences();
      expect(c.items.length, 12);
      expect(provider.calls, 1);
    },
  );
  test(
    'prefs, dismissals and saved article survive new controller without network',
    () async {
      final store = TestStore(), provider = FakeProvider();
      final c = makeController(store: store, provider: provider);
      await c.refresh();
      await c.save(c.items.first);
      await c.dismiss('item-1');
      await c.selectTopics({'science'});
      final other = makeController(store: store, provider: FakeProvider());
      await other.initialize();
      expect(other.savedItems.single.id, 'item-0');
      expect(other.preferences.selectedTopics, {'science'});
      expect(other.preferences.dismissedItemIds, {'item-1'});
      expect(other.items, isNotEmpty);
    },
  );
  test(
    'off is persistent, hides feed, keeps saved articles and makes no refresh requests',
    () async {
      final store = TestStore(), provider = FakeProvider();
      final c = makeController(store: store, provider: provider);
      await c.refresh();
      await c.save(c.items.first);
      await c.setEnabled(false);
      await c.refresh();
      expect(provider.calls, 1);
      expect(c.items, isEmpty);
      expect(c.savedItems.length, 1);
      final next = makeController(store: store, provider: provider);
      await next.refresh();
      expect(next.preferences.enabled, isFalse);
      expect(provider.calls, 1);
    },
  );
  test(
    'private, handoff and inactive hide owner content and deny all reads/writes/network',
    () async {
      for (final context in [
        LiveContentContext.private,
        LiveContentContext.handoff,
        LiveContentContext.inactive,
      ]) {
        final store = TestStore(), provider = FakeProvider();
        final c = makeController(store: store, provider: provider);
        await c.refresh();
        final item = c.items.first;
        await c.save(item);
        final writes = store.writes, reads = store.reads;
        c.setContext(context);
        await c.initialize();
        await c.refresh();
        await c.dismiss(item.id);
        await c.save(item);
        await expectLater(c.clearSaved(), throwsA(isA<FeedFailure>()));
        await c.resetPreferences();
        await c.clearCache();
        expect(c.items, isEmpty);
        expect(c.savedItems, isEmpty);
        expect(c.canOpen(item), isFalse);
        expect(c.fetchedAt, isNull);
        expect(store.writes, writes);
        expect(store.reads, reads);
        expect(provider.calls, 1);
      }
    },
  );
  test(
    'response arriving after private switch neither enters cache nor updates owner state',
    () async {
      final store = TestStore(),
          provider = FakeProvider()..pending = Completer();
      final c = makeController(store: store, provider: provider);
      final refresh = c.refresh();
      await Future<void>.delayed(Duration.zero);
      c.setContext(LiveContentContext.private);
      provider.pending!.complete(FeedResponse(snapshot: snapshot()));
      await refresh;
      expect(store.writes, 0);
      c.setContext(LiveContentContext.owner);
      expect(c.items, isEmpty);
      expect(c.refreshing, isFalse);
    },
  );
  test(
    'network error preserves cached feed and saved entries with honest stale state',
    () async {
      var clock = now;
      final provider = FakeProvider();
      final c = makeController(provider: provider, clock: () => clock);
      await c.refresh();
      await c.save(c.items.first);
      clock = now.add(const Duration(minutes: 2));
      provider.failure = const FeedFailure('Headlines could not be refreshed.');
      await c.refresh();
      expect(c.items.length, 12);
      expect(c.savedItems.length, 1);
      expect(c.stale, isTrue);
      expect(c.error, isNotNull);
    },
  );
  test(
    'conditional response does not invent publisher/fetched timestamps',
    () async {
      var clock = now;
      final provider = FakeProvider();
      final c = makeController(provider: provider, clock: () => clock);
      await c.refresh();
      clock = now.add(const Duration(minutes: 2));
      provider.response = const FeedResponse(notModified: true);
      await c.refresh();
      expect(provider.lastEtag, '"one"');
      expect(c.items.first.fetchedAt, now);
      expect(c.fetchedAt, now);
    },
  );
  test(
    'corrupt persisted opt-out refuses network until explicit reset',
    () async {
      final store = TestStore();
      await store.writeDocument('liveContentPreferences', {
        'schemaVersion': 99,
        'enabled': false,
      });
      final provider = FakeProvider(),
          c = makeController(store: store, provider: FakeProvider());
      final actual = makeController(store: store, provider: provider);
      await actual.refresh();
      expect(provider.calls, 0);
      expect(actual.storageError, isNotNull);
      await actual.setEnabled(true);
      await actual.refresh();
      expect(provider.calls, 0);
      await actual.resetPreferences();
      await actual.refresh();
      expect(provider.calls, 1);
      c.dispose();
    },
  );
  test(
    'corrupt saved/revocation document preserved and exposure remains closed',
    () async {
      final store = TestStore();
      await store.writeDocument('liveContentSaved', {
        'schemaVersion': 99,
        'items': [],
      });
      final provider = FakeProvider(),
          c = makeController(store: store, provider: FakeProvider());
      final actual = makeController(store: store, provider: provider);
      await actual.refresh();
      expect(provider.calls, 0);
      expect(
        (await store.readDocument('liveContentSaved'))!['schemaVersion'],
        99,
      );
      expect(actual.items, isEmpty);
      c.dispose();
    },
  );
  test(
    'explicit revocation tombstones saved item across refresh and cache clear',
    () async {
      var clock = now;
      final store = TestStore(), provider = FakeProvider();
      final c = makeController(
        store: store,
        provider: provider,
        clock: () => clock,
      );
      await c.refresh();
      final item = c.items.first;
      await c.save(item);
      clock = now.add(const Duration(minutes: 2));
      provider.response = FeedResponse(
        snapshot: LiveSnapshot.fromJson(snapshotJson(revokedItems: [item.id])),
      );
      await c.refresh();
      expect(c.savedItems.single.item, isNull);
      expect(c.items.any((i) => i.id == item.id), isFalse);
      expect(c.canOpen(item), isFalse);
      await c.clearCache();
      final next = makeController(store: store);
      await next.initialize();
      expect(next.savedItems.single.item, isNull);
      final saved = await store.readDocument('liveContentSaved');
      expect(jsonEncode(saved), isNot(contains(item.title)));
    },
  );
  test(
    'removed source revokes saved while unavailable status retains cached content',
    () async {
      var clock = now;
      final provider = FakeProvider();
      final c = makeController(provider: provider, clock: () => clock);
      await c.refresh();
      await c.save(c.items.first);
      clock = now.add(const Duration(minutes: 2));
      provider.response = FeedResponse(
        snapshot: LiveSnapshot.fromJson(snapshotJson(status: 'unavailable')),
      );
      await c.refresh();
      expect(c.items, isNotEmpty);
      expect(c.stale, isTrue);
      expect(c.savedItems.single.available, isTrue);
      clock = now.add(const Duration(minutes: 4));
      provider.response = FeedResponse(
        snapshot: LiveSnapshot.fromJson(snapshotJson(sources: [], items: [])),
      );
      await c.refresh();
      expect(c.savedItems.single.item, isNull);
      expect(c.items, isEmpty);
      expect(c.availableTopics, isEmpty);
      expect(c.availableLanguages, isEmpty);
    },
  );
  test(
    'excerpt withdrawal restricts cache and saved immediately even when disk fails',
    () async {
      var clock = now;
      final store = TestStore(), provider = FakeProvider();
      final c = makeController(
        store: store,
        provider: provider,
        clock: () => clock,
      );
      await c.refresh();
      final item = c.items.first;
      await c.save(item);
      clock = now.add(const Duration(minutes: 2));
      store.failWrites = true;
      provider.response = FeedResponse(
        snapshot: LiveSnapshot.fromJson(
          snapshotJson(sources: [sourceJson(excerpts: false)], items: []),
        ),
      );
      await c.refresh();
      expect(c.items, isEmpty);
      expect(c.savedItems.single.item, isNull);
      expect(c.canOpen(item), isFalse);
      expect(c.storageError, isNotNull);
      expect(c.storageError, isNot(contains('private details')));
    },
  );
  test(
    'successful excerpt withdrawal survives disposable cache clearing',
    () async {
      var clock = now;
      final store = TestStore(), provider = FakeProvider();
      final c = makeController(
        store: store,
        provider: provider,
        clock: () => clock,
      );
      await c.refresh();
      await c.save(c.items.first);
      clock = now.add(const Duration(minutes: 2));
      provider.response = FeedResponse(
        snapshot: LiveSnapshot.fromJson(
          snapshotJson(sources: [sourceJson(excerpts: false)], items: []),
        ),
      );
      await c.refresh();
      await c.clearCache();
      final next = makeController(store: store);
      await next.initialize();
      expect(next.savedItems.single.item, isNull);
    },
  );
  test(
    'clear cache does not delete saves or dismissals, and clear saved does not delete cache',
    () async {
      final c = makeController(provider: FakeProvider());
      await c.refresh();
      await c.save(c.items.first);
      await c.dismiss('item-2');
      await c.clearCache();
      expect(c.savedItems.length, 1);
      expect(c.preferences.dismissedItemIds, {'item-2'});
      await c.refresh();
      expect(c.items, isNotEmpty);
      await c.clearSaved();
      expect(c.savedItems, isEmpty);
      expect(c.items, isNotEmpty);
    },
  );
  test(
    'privacy clearSaved reports disk failure without claiming deletion',
    () async {
      final store = TestStore(),
          c = makeController(provider: FakeProvider(), store: TestStore());
      final actual = makeController(store: store, provider: FakeProvider());
      await actual.refresh();
      await actual.save(actual.items.first);
      store.failWrites = true;
      await expectLater(actual.clearSaved(), throwsA(isA<FeedFailure>()));
      expect(actual.savedItems.length, 1);
      expect(actual.storageError, isNotNull);
      c.dispose();
    },
  );
  test(
    'new metadata revocation redacts saved item even without separate revoked ID',
    () async {
      var clock = now;
      final provider = FakeProvider();
      final c = makeController(provider: provider, clock: () => clock);
      await c.refresh();
      await c.save(c.items.first);
      clock = now.add(const Duration(minutes: 2));
      final item = itemJson(0)
        ..['eligibility'] = {
          'state': 'ineligible',
          'basis': 'curated-source-scope',
          'scope': 'science-reporting',
        };
      provider.response = FeedResponse(
        snapshot: LiveSnapshot.fromJson(snapshotJson(items: [item])),
      );
      await c.refresh();
      expect(c.savedItems.single.item, isNull);
      expect(c.items, isEmpty);
    },
  );
  test(
    'configured snapshot transport uses common URL, validators, no user preference params',
    () async {
      final transport = TestTransport();
      final provider = SnapshotFeedProvider(
        endpoint: Uri.parse('https://feeds.example/v1/snapshot.json'),
        transport: transport,
      );
      final response = await provider.fetch(
        etag: '"cached"',
        lastModified: 'Fri, 11 Sep 2026 12:00:00 GMT',
      );
      expect(response.snapshot!.items.length, 18);
      expect(
        transport.url.toString(),
        'https://feeds.example/v1/snapshot.json',
      );
      expect(transport.headers, {
        'Accept': 'application/json',
        'If-None-Match': '"cached"',
        'If-Modified-Since': 'Fri, 11 Sep 2026 12:00:00 GMT',
      });
      transport.response = FeedTransportResponse(304, Uint8List(0), {});
      expect((await provider.fetch()).notModified, isTrue);
    },
  );
  test(
    'snapshot transport rejects redirects, HTML, oversized response and bounded retry',
    () async {
      final transport = TestTransport();
      final provider = SnapshotFeedProvider(
        endpoint: Uri.parse('https://feeds.example/v1/snapshot.json'),
        transport: transport,
      );
      for (final response in [
        FeedTransportResponse(302, Uint8List(0), {}),
        FeedTransportResponse(200, Uint8List(0), {'content-type': 'text/html'}),
        FeedTransportResponse(200, Uint8List(2 * 1024 * 1024 + 1), {
          'content-type': 'application/json',
        }),
      ]) {
        transport.response = response;
        await expectLater(provider.fetch(), throwsA(isA<FeedFailure>()));
      }
      transport.response = FeedTransportResponse(429, Uint8List(0), {
        'retry-after': '999999',
      });
      await expectLater(
        provider.fetch(),
        throwsA(
          isA<FeedFailure>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(days: 1),
          ),
        ),
      );
    },
  );
  test(
    'endpoint absent by default; insecure/query/credential/private endpoints rejected',
    () {
      expect(SnapshotFeedProvider.fromEnvironment(), isNull);
      for (final uri in [
        'http://feeds.example/v1/snapshot.json',
        'https://user:pass@feeds.example/v1/snapshot.json',
        'https://feeds.example/v1/snapshot.json?topic=science',
        'https://127.0.0.1/v1/snapshot.json',
        'http://localhost:8891/v1/snapshot.json',
        'https://192.168.0.1/v1/snapshot.json',
        'https://feeds.example/not-snapshot',
      ]) {
        expect(
          () => SnapshotFeedProvider.validateEndpoint(Uri.parse(uri)),
          throwsFormatException,
          reason: uri,
        );
      }
      expect(
        SnapshotFeedProvider.validateEndpoint(
          Uri.parse('http://127.0.0.1:8891/v1/snapshot.json'),
          allowLocal: true,
        ).port,
        8891,
      );
    },
  );
  test(
    'local real service smoke parses approved current sources and conditional GET',
    () async {
      final registry = LiveSourceRegistry.fromJson(
        feedMap(
          jsonDecode(
            await File('assets/live_content/sources.json').readAsString(),
          ),
        ),
      );
      final provider = SnapshotFeedProvider(
        endpoint: Uri.parse('http://127.0.0.1:8891/v1/snapshot.json'),
        allowLocal: true,
      );
      final response = await provider.fetch();
      final snapshot = response.snapshot!;
      final gate = LiveContentEligibility(
        registry: registry,
        canOpenDestination: (_) => true,
      );
      final accepted = snapshot.items
          .where((i) => gate.accepts(i, now: DateTime.now().toUtc()))
          .toList();
      expect(snapshot.sources.length, 3);
      expect(snapshot.items, isNotEmpty);
      expect(accepted.length, snapshot.items.length);
      expect(
        (await provider.fetch(
          etag: response.etag,
          lastModified: response.lastModified,
        )).notModified,
        isTrue,
      );
      // Counts only: no browsing history, URLs, or personalized identifiers logged.
      // ignore: avoid_print
      print(
        'Real common snapshot: ${snapshot.sources.length} sources, ${snapshot.items.length} items, ${accepted.length} eligible, conditional 304.',
      );
    },
    skip: Platform.environment['WINGMAN_LIVE_SMOKE'] != '1',
  );
}
