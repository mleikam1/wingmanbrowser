import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

import 'article_images_test.dart' as photos;

final now = photos.now;
ApprovedLiveSource source(
  String topic, {
  bool titles = true,
  bool images = true,
}) => ApprovedLiveSource.fromJson({
  ...photos.imageSource().source.toJson(),
  'id': topic,
  'name': '$topic editorial publisher',
  'topics': [topic],
  'rights': {'titles': titles, 'excerpts': true, 'images': images},
  'enabled': true,
  'allowedArticleHosts': ['science.example'],
  'articlePathPrefixes': ['/reports/'],
  'eligibilityScope': '$topic-reporting',
  if (images) 'imagePolicy': photos.imageSource().imagePolicy!.toJson(),
});

LiveContentItem story(
  String topic, {
  bool image = true,
  int id = 1,
}) => LiveContentItem.fromJson({
  ...photos.item(id, image: image).toJson(),
  'id': '$topic-$id',
  'sourceId': topic,
  'title': topic == 'sports' ? 'Home team wins the final' : 'A new film review',
  'publishedAt': now.subtract(const Duration(hours: 2)).toIso8601String(),
  'topics': [topic],
  'eligibility': {
    'state': 'eligible',
    'basis': 'curated-source-scope',
    'scope': '$topic-reporting',
  },
  if (image) 'image': {...photos.item(id).image!.toJson(), 'sourceId': topic},
});

class DeliveryProvider implements FeedProvider {
  DeliveryProvider(this.response);
  FeedResponse response;
  int calls = 0;
  @override
  Future<FeedResponse> fetch({String? etag, String? lastModified}) async {
    calls++;
    return response;
  }

  @override
  void cancel() {}
}

LiveSnapshot snapshot(
  List<ApprovedLiveSource> sources,
  List<LiveContentItem> rows,
) => LiveSnapshot(
  snapshotId: 'editorial-fixture',
  generatedAt: now,
  expiresAt: now.add(const Duration(hours: 1)),
  sources: sources.map((s) => s.source).toList(),
  items: rows,
);

Future<LiveContentController> controller(
  List<ApprovedLiveSource> sources,
  List<LiveContentItem> rows, {
  photos.Images? images,
  DeliveryProvider? provider,
}) async {
  final gate = LiveContentEligibility(
    // Legacy installed caches/configuration must receive the repair too.
    registry: LiveSourceRegistry(sources, requireStoryImages: true),
    canOpenDestination: (_) => true,
  );
  final c = LiveContentController(
    store: MemorySignatureDocumentStore(),
    eligibility: gate,
    provider:
        provider ??
        DeliveryProvider(
          FeedResponse(
            snapshot: snapshot(sources, rows),
            publisherImagesVerified: true,
          ),
        ),
    imageLoader: ArticleImageLoader(
      eligibility: gate,
      transport: images ?? photos.Images(),
      clock: () => now,
    ),
    clock: () => now,
  )..setContext(LiveContentContext.owner);
  await c.refresh();
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final topic in ['sports', 'entertainment']) {
    test('$topic: permitted title survives a missing story photo', () async {
      final c = await controller(
        [source(topic, images: false)],
        [story(topic, image: false)],
      );
      addTearDown(c.dispose);
      await c.selectTopics({topic});
      expect(c.items.map((i) => i.id), ['$topic-1']);
      expect(c.imageBytesFor(c.items.single), isNull);
    });
    test('$topic: image loading cannot gate article pagination', () async {
      final images = photos.Images()..pending = Completer<RssFetchResponse>();
      final c = await controller(
        [source(topic)],
        [story(topic)],
        images: images,
      );
      addTearDown(c.dispose);
      expect(c.items.map((i) => i.id), ['$topic-1']);
      images.pending!.complete(RssFetchResponse(404, photos.png, const {}));
      await photos.settle();
      expect(c.items.map((i) => i.id), ['$topic-1']);
      expect(c.imageBytesFor(c.items.single), isNull);
    });
    test('$topic: title permission denied remains hidden', () async {
      final c = await controller(
        [source(topic, titles: false)],
        [story(topic, image: false)],
      );
      addTearDown(c.dispose);
      expect(c.items, isEmpty);
    });
  }
  test(
    'an unrelated failed publisher cannot mark Sports as a connection failure',
    () async {
      final sports = source('sports', images: false),
          entertainment = source('entertainment', images: false);
      final provider = DeliveryProvider(
        FeedResponse(
          snapshot: snapshot(
            [sports, entertainment],
            [story('sports', image: false)],
          ),
          warning: 'One publisher failed',
          providerState: {
            'schemaVersion': 1,
            'sources': {
              'sports': {
                'diagnostics': {
                  'outcome': 'not-due',
                  'lastSuccessAt': now.toIso8601String(),
                },
              },
              'entertainment': {
                'diagnostics': {
                  'outcome': 'transport-failure',
                  'httpStatus': 429,
                },
              },
            },
          },
        ),
      );
      final c = await controller(
        [sports, entertainment],
        [story('sports', image: false)],
        provider: provider,
      );
      addTearDown(c.dispose);
      await c.selectTopics({'sports'});
      expect(c.items, hasLength(1));
      expect(c.categoryHealth.hasFailure, isFalse);
      await c.selectTopics({'entertainment'});
      expect(c.categoryHealth.reason, 'fetch-failure');
    },
  );

  test(
    'empty, scheduled, no-source, hidden-choice and policy states are distinct',
    () async {
      final s = source('sports', images: false);
      final p = DeliveryProvider(
        FeedResponse(
          snapshot: snapshot([s], []),
          providerState: {
            'schemaVersion': 1,
            'sources': {
              'sports': {
                'diagnostics': {'outcome': 'empty', 'parsedEntries': 0},
              },
            },
          },
        ),
      );
      final c = await controller([s], [], provider: p);
      addTearDown(c.dispose);
      await c.selectTopics({'sports'});
      expect(c.categoryHealth.reason, 'no-recent-matches');
      await c.selectTopics({'travel'});
      expect(c.categoryHealth.reason, 'no-production-source');
      await c.selectTopics({'sports'});
      await c.hideSource('sports');
      expect(c.categoryHealth.reason, 'local-filters');
      for (final outcome in ['deferred', 'not-due', 'publisher-hold']) {
        final scheduled = await controller(
          [s],
          [],
          provider: DeliveryProvider(
            FeedResponse(
              snapshot: snapshot([s], []),
              providerState: {
                'schemaVersion': 1,
                'sources': {
                  'sports': {
                    'diagnostics': {'outcome': outcome},
                  },
                },
              },
            ),
          ),
        );
        expect(scheduled.categoryHealth.reason, 'scheduled');
        expect(scheduled.categoryHealth.hasFailure, isFalse);
        scheduled.dispose();
      }
    },
  );

  test(
    'diagnostics export describes common supply without interests or saved activity',
    () async {
      final c = await controller(
        [source('sports', images: false)],
        [story('sports', image: false)],
      );
      addTearDown(c.dispose);
      await c.selectTopics({'travel'});
      final before = c.diagnostics();
      final sports = (before['categories'] as List)
          .cast<Map<String, Object?>>()
          .singleWhere((r) => r['category'] == 'sports');
      expect(sports['textFallbacks'], 1);
      expect(sports['imageCards'], 0);
      expect(sports['editorialStoriesWithin72Hours'], 1);
      await c.selectTopics({'sports'});
      await c.save(c.items.single);
      expect(c.diagnostics(), before);
      c.setContext(LiveContentContext.private);
      expect(c.diagnostics(), {'schemaVersion': 1, 'status': 'inactive'});
    },
  );

  test(
    'optional excerpt permission or invalid optional metadata does not revoke title',
    () async {
      final row = LiveContentItem.fromJson({
        ...story('sports', image: false).toJson(),
        'excerpt': 'x' * 1800,
        'attribution': 'x' * 201,
        'excerptProvenance': {'field': 'unknown'},
      });
      expect(row.excerpt, isNull);
      expect(row.attribution, isNull);
      final c = await controller([source('sports', images: false)], [row]);
      addTearDown(c.dispose);
      expect(c.items, hasLength(1));
      expect(c.canOpen(row), isTrue);
    },
  );
}
