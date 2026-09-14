import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/live_content/rss_parser.dart';
import 'package:wingman_browser/live_content/ordering.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'live_content_test.dart' as fixtures;

final now = DateTime.utc(2026, 9, 14, 2);
ApprovedLiveSource imageSource() => ApprovedLiveSource.fromJson({
  ...fixtures.sourceJson(),
  'rights': {'titles': true, 'excerpts': true, 'images': true},
  'allowedArticleHosts': ['science.example'],
  'articlePathPrefixes': ['/reports/'],
  'eligibilityScope': 'science-reporting',
  'enabled': true,
  'preserveFeedText': true,
  'imagePolicy': {
    'kind': 'syndicated-feed-thumbnail',
    'allowedHosts': ['media.example'],
    'pathPrefixes': ['/thumb/'],
    'licenseUrl': 'https://science.example/feeds/',
    'licenseLabel': 'RSS terms',
    'credit': 'Science',
    'maximumWidth': 90,
    'maximumHeight': 90,
  },
});
LiveContentEligibility gate({
  bool requireImages = true,
  bool Function(Uri)? allowed,
}) => LiveContentEligibility(
  registry: LiveSourceRegistry([
    imageSource(),
  ], requireStoryImages: requireImages),
  canOpenDestination: allowed ?? (_) => true,
);
LiveContentItem item(int id, {bool image = true}) => LiveContentItem.fromJson({
  ...fixtures.itemJson(id),
  'fetchedAt': now.toIso8601String(),
  'expiresAt': now.add(const Duration(days: 7)).toIso8601String(),
  'rights': {'titles': true, 'excerpts': true, 'images': true},
  'image': image
      ? {
          'schemaVersion': 1,
          'url': 'https://media.example/thumb/$id.png',
          'articleUrl': 'https://science.example/reports/$id',
          'sourceId': 'science',
          'credit': 'Science',
          'caption': 'Publisher thumbnail',
          'licenseUrl': 'https://science.example/feeds/',
          'licenseLabel': 'RSS terms',
          'basis': 'syndicated-feed-thumbnail',
          'width': 1,
          'height': 1,
        }
      : null,
});
LiveSnapshot snapshot(
  List<LiveContentItem> items, {
  Set<String> revoked = const {},
}) => LiveSnapshot(
  snapshotId: 'images',
  generatedAt: now,
  expiresAt: now.add(const Duration(minutes: 30)),
  sources: [imageSource().source],
  items: items,
  revokedItemIds: revoked,
);
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwKFjwHwAEVAJA4zks+QAAAABJRU5ErkJggg==',
);

class Images implements ArticleImageTransport {
  final calls = <String>[];
  Completer<RssFetchResponse>? pending;
  RssFailure? failure;
  Map<String, String> responseHeaders = {'content-type': 'image/png'};
  int active = 0, maxActive = 0, cancels = 0;
  @override
  Future<RssFetchResponse> fetchImage(
    LiveArticleImage image,
    ApprovedLiveSource source, {
    required bool Function(Uri) canOpenDestination,
  }) async {
    calls.add(image.url.toString());
    active++;
    if (active > maxActive) maxActive = active;
    try {
      if (failure != null) throw failure!;
      await Future<void>.delayed(Duration.zero);
      return await (pending?.future ??
          Future.value(RssFetchResponse(200, png, responseHeaders)));
    } finally {
      active--;
    }
  }

  @override
  void cancel() {
    cancels++;
  }
}

Future<void> settle() async {
  for (var n = 0; n < 30; n++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'source diversity preserves source recency and defers explicit fewer topics',
    () {
      LiveContentItem row(int id, String source, String topic) =>
          LiveContentItem.fromJson({
            ...item(id).toJson(),
            'sourceId': source,
            'topics': [topic],
          });
      final rows = [
        row(1, 'tech-xplore', 'technology'),
        row(2, 'tech-xplore', 'technology'),
        row(3, 'phys-org', 'science'),
        row(4, 'medical-xpress', 'health'),
        row(20, 'newsusa-features', 'business'),
      ];
      expect(
        balancedLiveItems(rows, [
          'tech-xplore',
          'phys-org',
          'medical-xpress',
          'newsusa-features',
        ]).map((i) => i.sourceId),
        [
          'newsusa-features',
          'tech-xplore',
          'medical-xpress',
          'phys-org',
          'tech-xplore',
        ],
      );
      final fewer = balancedLiveItems(
        rows,
        ['tech-xplore', 'phys-org', 'medical-xpress', 'newsusa-features'],
        fewerTopics: {'technology'},
      );
      expect(
        fewer.take(3).any((i) => i.topics.contains('technology')),
        isFalse,
      );
      expect(fewer.last.id, 'item-2');
    },
  );
  test(
    'image metadata cannot authorize a new source, article, host, path, license, credit or rendition',
    () {
      final good = item(1);
      expect(gate().imageFor(good), isNotNull);
      for (final change in <Map<String, Object?>>[
        {'sourceId': 'other'},
        {'articleUrl': 'https://science.example/reports/other'},
        {'url': 'https://media.example.evil/thumb/1.png'},
        {'url': 'https://media.example/hero/1.png'},
        {'url': 'https://media.example/thumb/1.png?visitor=secret'},
        {'url': 'https://media.example/thumb/%252e%252e/1.png'},
        {'url': 'http://media.example/thumb/1.png'},
        {'licenseUrl': 'https://evil.example/license'},
        {'credit': 'Getty Images'},
        {'basis': 'unreviewed'},
        {'width': 900},
        {'width': 0},
      ]) {
        final altered = LiveContentItem.fromJson({
          ...good.toJson(),
          'image': {...good.image!.toJson(), ...change},
        });
        expect(gate().imageFor(altered), isNull, reason: change.toString());
      }
      expect(
        gate(allowed: (u) => u.host != 'media.example').imageFor(good),
        isNull,
      );
      expect(good.imageUrl, isNull);
      expect(
        LiveContentItem.fromJson(good.toJson()).image!.cacheKey,
        good.image!.cacheKey,
      );
    },
  );
  test(
    'RSS reads exact media namespace only and preserves the complete syndicated title and summary',
    () {
      final s = imageSource(), title = 'A' * 250, description = 'B' * 800;
      String xml(String thumb) =>
          '<rss xmlns:media="http://search.yahoo.com/mrss/"><channel><item><title>$title</title><description>$description</description><link>https://science.example/reports/one</link>$thumb</item></channel></rss>';
      for (final thumb in [
        '<media:thumbnail url="https://media.example/thumb/a.png" width="90" height="90"/>',
        '<thumbnail url="https://media.example/thumb/a.png" width="90" height="90"/>',
        '<media:thumbnail url="https://media.example/hero/a.png" width="90" height="90"/>',
      ]) {
        final parsed = parseRssFeed(
          Uint8List.fromList(utf8.encode(xml(thumb))),
          s,
          now,
          gate(),
          (_, _) => true,
        );
        expect(parsed.items.single.title, title);
        expect(parsed.items.single.excerpt, description);
        expect(
          gate().imageFor(parsed.items.single) != null,
          thumb.startsWith('<media:') && thumb.contains('/thumb/'),
        );
      }
    },
  );
  test(
    'image decoder rejects HTML, wrong MIME, dimension lies and corrupt images',
    () async {
      await validateArticleImage(png, item(1).image!, 'image/png');
      for (final (bytes, type) in [
        (Uint8List.fromList(utf8.encode('<svg/>')), 'image/svg+xml'),
        (png, 'image/jpeg'),
        (Uint8List.fromList([255, 216, 255, 1]), 'image/jpeg'),
      ]) {
        await expectLater(
          validateArticleImage(bytes, item(1).image!, type),
          throwsA(anything),
        );
      }
      final lie = LiveArticleImage.fromJson({
        ...item(1).image!.toJson(),
        'width': 90,
        'height': 90,
      });
      await expectLater(
        validateArticleImage(png, lie, 'image/png'),
        throwsA(isA<RssFailure>()),
      );
    },
  );
  test(
    'common batch is bounded, two lanes only; cached immutable bytes avoid repeated downloads',
    () async {
      final transport = Images(),
          loader = ArticleImageLoader(
            eligibility: gate(),
            transport: Images(),
            clock: () => now,
          );
      loader.cancel(clear: true);
      final tested = ArticleImageLoader(
        eligibility: gate(),
        transport: transport,
        clock: () => now,
        validator: (_, _, _) async {},
      );
      final rows = List.generate(110, (i) => item(i));
      await tested.load(rows, onChanged: () {});
      expect(transport.calls.length, ArticleImageLoader.maximumBatch);
      expect(transport.maxActive, lessThanOrEqualTo(2));
      expect(() => tested.bytesFor(rows.first)![0] = 0, throwsUnsupportedError);
      await tested.load(rows, onChanged: () {});
      expect(transport.calls.length, ArticleImageLoader.maximumBatch);
      tested.cancel(clear: true);
      expect(tested.bytesFor(rows.first), isNull);
    },
  );
  test(
    'cancelled image work never populates cache or calls owner callback; server retry delay is respected',
    () async {
      var clock = now, changes = 0;
      final transport = Images()..pending = Completer();
      final loader = ArticleImageLoader(
        eligibility: gate(),
        transport: transport,
        clock: () => clock,
        validator: (_, _, _) async {},
      );
      final work = loader.load([item(1)], onChanged: () => changes++);
      await settle();
      loader.cancel();
      transport.pending!.complete(
        RssFetchResponse(200, png, {'content-type': 'image/png'}),
      );
      await work;
      expect(changes, 0);
      expect(loader.bytesFor(item(1)), isNull);
      clock = clock.add(const Duration(minutes: 31));
      transport.pending = null;
      transport.failure = const RssFailure(
        'http-429',
        headers: {'retry-after': '7200'},
      );
      await loader.load([item(1)], onChanged: () => changes++);
      final count = transport.calls.length;
      clock = clock.add(const Duration(minutes: 90));
      await loader.load([item(1)], onChanged: () => changes++);
      expect(transport.calls.length, count);
      expect(changes, 0);
    },
  );
  test(
    'no-store responses are fresh transient display buffers, never reused across batches or owner changes',
    () async {
      final transport = Images()
        ..responseHeaders = {
          'content-type': 'image/png',
          'cache-control': 'no-cache, no-store, must-revalidate',
        };
      final loader = ArticleImageLoader(
        eligibility: gate(),
        transport: transport,
        clock: () => now,
        validator: (_, _, _) async {},
      );
      await loader.load([item(1)], onChanged: () {});
      expect(loader.bytesFor(item(1)), isNotNull);
      expect(loader.isTransientFor(item(1)), isTrue);
      await loader.load([item(1)], onChanged: () {});
      expect(transport.calls.length, 2);
      loader.cancel();
      expect(loader.bytesFor(item(1)), isNull);
      expect(loader.isTransientFor(item(1)), isFalse);
      await loader.load([item(1)], onChanged: () {});
      expect(transport.calls.length, 3);
      loader.cancel(clear: true);
    },
  );
  test(
    'unreadable preferences prevent image network even with a previously verified cached snapshot',
    () async {
      final store = MemorySignatureDocumentStore(),
          transport = Images(),
          eligibility = gate();
      await store.writeDocument('liveContentPreferences', {
        'schemaVersion': 999,
      });
      await store.writeDocument('liveContentCache', {
        'schemaVersion': 1,
        'snapshot': snapshot([item(1)]).toJson(),
        'publisherImagesVerified': true,
      });
      final controller = LiveContentController(
        store: store,
        eligibility: eligibility,
        imageLoader: ArticleImageLoader(
          eligibility: eligibility,
          transport: transport,
          clock: () => now,
        ),
        clock: () => now,
      )..setContext(LiveContentContext.owner);
      await controller.initialize();
      await settle();
      expect(controller.storageError, isNotNull);
      expect(transport.calls, isEmpty);
      expect(controller.imageFor(item(1)), isNull);
      controller.dispose();
    },
  );
  test(
    'ordinary snapshot JSON cannot grant publisher image provenance',
    () async {
      final eligibility = gate(),
          transport = Images(),
          provider = fixtures.FakeProvider()
            ..response = FeedResponse(snapshot: snapshot([item(1)]));
      final controller = LiveContentController(
        store: MemorySignatureDocumentStore(),
        eligibility: eligibility,
        provider: provider,
        imageLoader: ArticleImageLoader(
          eligibility: eligibility,
          transport: transport,
          clock: () => now,
        ),
        clock: () => now,
      )..setContext(LiveContentContext.owner);
      await controller.refresh();
      await settle();
      expect(controller.items, isEmpty);
      expect(controller.imageFor(item(1)), isNull);
      expect(transport.calls, isEmpty);
      controller.dispose();
    },
  );
  test(
    'image rights withdrawal suppresses display and further fetch even if durable writes fail',
    () async {
      var clock = now;
      final store = fixtures.TestStore(),
          eligibility = gate(),
          transport = Images(),
          provider = fixtures.FakeProvider()
            ..response = FeedResponse(
              snapshot: snapshot([item(1)]),
              publisherImagesVerified: true,
            );
      final controller = LiveContentController(
        store: store,
        eligibility: eligibility,
        provider: provider,
        imageLoader: ArticleImageLoader(
          eligibility: eligibility,
          transport: transport,
          clock: () => clock,
          validator: (_, _, _) async {},
        ),
        clock: () => clock,
      )..setContext(LiveContentContext.owner);
      await controller.refresh();
      await settle();
      expect(controller.imageBytesFor(item(1)), isNotNull);
      final revoked = snapshot([item(1)]).toJson();
      revoked['sources'] = [
        {
          ...imageSource().source.toJson(),
          'rights': {...imageSource().source.rights.toJson(), 'images': false},
        },
      ];
      provider.response = FeedResponse(
        snapshot: LiveSnapshot.fromJson(Map<String, dynamic>.from(revoked)),
        publisherImagesVerified: true,
      );
      store.failWrites = true;
      clock = clock.add(const Duration(minutes: 2));
      final requests = transport.calls.length;
      await controller.refresh();
      await settle();
      expect(controller.imageFor(item(1)), isNull);
      expect(controller.items, isEmpty);
      expect(transport.calls.length, requests);
      expect(controller.storageError, isNotNull);
      controller.dispose();
    },
  );
  test(
    'explicit per-article image removal hides the saved old image even on checkpoint failure',
    () async {
      var clock = now;
      final store = fixtures.TestStore(),
          eligibility = gate(),
          transport = Images(),
          provider = fixtures.FakeProvider()
            ..response = FeedResponse(
              snapshot: snapshot([item(1)]),
              publisherImagesVerified: true,
            );
      final controller = LiveContentController(
        store: store,
        eligibility: eligibility,
        provider: provider,
        imageLoader: ArticleImageLoader(
          eligibility: eligibility,
          transport: transport,
          clock: () => clock,
          validator: (_, _, _) async {},
        ),
        clock: () => clock,
      )..setContext(LiveContentContext.owner);
      final original = item(1);
      await controller.refresh();
      await settle();
      await controller.save(original);
      expect(controller.imageBytesFor(original), isNotNull);
      provider.response = FeedResponse(
        snapshot: snapshot([item(1, image: false)]),
        publisherImagesVerified: true,
      );
      store.failWrites = true;
      clock = clock.add(const Duration(minutes: 2));
      await controller.refresh();
      expect(controller.canOpen(original), isTrue);
      expect(controller.imageFor(original), isNull);
      expect(controller.imageBytesFor(original), isNull);
      controller.dispose();
    },
  );
  test(
    'photo-only pagination waits for decoded bytes and excludes rejected images',
    () async {
      final eligibility = gate(),
          transport = Images()..pending = Completer(),
          provider = fixtures.FakeProvider()
            ..response = FeedResponse(
              snapshot: snapshot([item(1), item(2), item(3, image: false)]),
              publisherImagesVerified: true,
            );
      final controller = LiveContentController(
        store: MemorySignatureDocumentStore(),
        eligibility: eligibility,
        provider: provider,
        imageLoader: ArticleImageLoader(
          eligibility: eligibility,
          transport: transport,
          clock: () => now,
          validator: (_, image, _) async {
            if (image.url.path.endsWith('/1.png')) {
              throw const RssFailure('body-too-large');
            }
          },
        ),
        clock: () => now,
        pageSize: 1,
      )..setContext(LiveContentContext.owner);
      addTearDown(controller.dispose);
      final loadingNotifications = <bool>[];
      controller.addListener(() {
        loadingNotifications.add(controller.imagesLoading);
      });
      await controller.refresh();
      await settle();
      expect(controller.imagesLoading, isTrue);
      expect(controller.items, isEmpty);
      expect(controller.hasMore, isFalse);
      expect(controller.imageFor(item(1)), isNotNull);
      await controller.save(item(3, image: false));
      expect(controller.savedItems.single.item!.id, 'item-3');

      transport.pending!.complete(
        RssFetchResponse(200, png, {'content-type': 'image/png'}),
      );
      await settle();
      expect(controller.imagesLoading, isFalse);
      expect(controller.items.single.id, 'item-2');
      expect(controller.hasMore, isFalse);
      expect(controller.imageBytesFor(item(1)), isNull);
      expect(controller.savedItems.single.item!.id, 'item-3');
      expect(loadingNotifications, contains(true));
      expect(loadingNotifications.last, isFalse);
    },
  );
  test(
    'retired image completion cannot clear a replacement owner batch loading state',
    () async {
      final eligibility = gate(),
          oldResponse = Completer<RssFetchResponse>(),
          newResponse = Completer<RssFetchResponse>(),
          transport = Images(),
          provider = fixtures.FakeProvider()
            ..response = FeedResponse(
              snapshot: snapshot([item(1)]),
              publisherImagesVerified: true,
            );
      transport.pending = oldResponse;
      final controller = LiveContentController(
        store: MemorySignatureDocumentStore(),
        eligibility: eligibility,
        provider: provider,
        imageLoader: ArticleImageLoader(
          eligibility: eligibility,
          transport: transport,
          clock: () => now,
          validator: (_, _, _) async {},
        ),
        clock: () => now,
      )..setContext(LiveContentContext.owner);
      addTearDown(controller.dispose);
      var changes = 0;
      controller.addListener(() => changes++);
      await controller.refresh();
      await settle();
      expect(controller.imagesLoading, isTrue);
      controller.setContext(LiveContentContext.private);
      expect(controller.imagesLoading, isFalse);
      transport.pending = newResponse;
      controller.setContext(LiveContentContext.owner);
      await settle();
      expect(controller.imagesLoading, isTrue);
      final beforeRetiredCompletion = changes;
      oldResponse.complete(
        RssFetchResponse(200, png, {'content-type': 'image/png'}),
      );
      await settle();
      expect(changes, beforeRetiredCompletion);
      expect(controller.imagesLoading, isTrue);
      expect(controller.items, isEmpty);
      newResponse.completeError(const RssFailure('offline'));
      await settle();
      expect(controller.imagesLoading, isFalse);
      expect(controller.items, isEmpty);
      expect(changes, greaterThan(beforeRetiredCompletion));
      expect(controller.fetchedAt, isNotNull);
    },
  );
  test(
    'image requirement precedes pagination; private and revoked items expose no metadata or bytes; saved text remains',
    () async {
      var clock = now;
      final eligibility = gate(),
          transport = Images(),
          provider = fixtures.FakeProvider();
      final rows = [
        ...List.generate(20, (i) => item(i, image: false)),
        item(25),
        item(26),
      ];
      provider.response = FeedResponse(
        snapshot: snapshot(rows),
        publisherImagesVerified: true,
      );
      final controller = LiveContentController(
        store: MemorySignatureDocumentStore(),
        eligibility: eligibility,
        provider: provider,
        imageLoader: ArticleImageLoader(
          eligibility: eligibility,
          transport: transport,
          clock: () => clock,
          validator: (_, _, _) async {},
        ),
        clock: () => clock,
        pageSize: 1,
      )..setContext(LiveContentContext.owner);
      await controller.refresh();
      await settle();
      expect(controller.items.single.id, 'item-25');
      expect(controller.hasMore, isTrue);
      await controller.save(rows.first);
      expect(controller.savedItems.single.item, rows.first);
      expect(controller.imageBytesFor(rows[20]), isNotNull);
      controller.setContext(LiveContentContext.private);
      expect(controller.items, isEmpty);
      expect(controller.imageFor(rows[20]), isNull);
      expect(controller.imageBytesFor(rows[20]), isNull);
      controller.setContext(LiveContentContext.owner);
      clock = clock.add(const Duration(minutes: 2));
      provider.response = FeedResponse(
        snapshot: snapshot(rows, revoked: {rows[20].id}),
        publisherImagesVerified: true,
      );
      await controller.refresh();
      expect(controller.imageBytesFor(rows[20]), isNull);
      expect(controller.items.single.id, 'item-26');
      controller.dispose();
    },
  );
}
