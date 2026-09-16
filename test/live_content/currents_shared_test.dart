import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'rss_provider_test.dart' as rss;

final fixtureNow = DateTime.utc(2026, 9, 16, 12);
Map<String, Object?> currentsSource() => {
  'id': 'currents',
  'name': 'Currents News API',
  'homepageUrl': 'https://currentsapi.services/',
  'language': 'en',
  'topics': liveContentTopicOrder,
  'enabled': true,
  'providerId': 'currents',
  'articleHostPolicy': 'validated-public',
  'allowedArticleHosts': <String>[],
  'articlePathPrefixes': ['/'],
  'eligibilityScope': 'currents-preview',
  'retentionSeconds': 86400,
  'rights': {
    'titles': true,
    'excerpts': true,
    'images': false,
    'attribution': 'Powered by Currents News API',
    'licenseUrl': 'https://currentsapi.services/terms',
  },
  'lastSuccessAt': fixtureNow.toIso8601String(),
};
Map<String, Object?> currentsStory(String topic, {int id = 1}) => {
  'id': 'currents-$topic-$id',
  'sourceId': 'currents',
  'providerId': 'currents',
  'publisherId': 'publisher.example',
  'publisherName': 'Original Publisher',
  'providerCategories': ['general'],
  'title': 'Fixture $topic report $id',
  'excerpt': 'A supplied preview of the original publisher report.',
  'canonicalUrl': 'https://publisher.example/$topic/$id',
  'originalUrl': 'https://publisher.example/$topic/$id?utm_source=provider',
  'outboundUrl': 'https://publisher.example/$topic/$id?utm_source=provider',
  'publishedAt': fixtureNow
      .subtract(const Duration(hours: 2))
      .toIso8601String(),
  'fetchedAt': fixtureNow.toIso8601String(),
  'expiresAt': fixtureNow.add(const Duration(hours: 24)).toIso8601String(),
  'language': 'en',
  'region': 'US',
  'topics': [topic],
  'rights': (currentsSource()['rights']),
  'eligibility': {
    'state': 'eligible',
    'basis': 'provider-preview',
    'scope': 'currents-preview',
  },
};
Map<String, Object?> currentsSnapshot({List<Object?>? stories}) => {
  'schemaVersion': 1,
  'snapshotId': 'currents-fixture',
  'generatedAt': fixtureNow.toIso8601String(),
  'expiresAt': fixtureNow.add(const Duration(hours: 24)).toIso8601String(),
  'sources': [currentsSource()],
  'items':
      stories ??
      [for (final topic in liveContentTopicOrder) currentsStory(topic)],
};
LiveSourceRegistry currentsRegistry() => LiveSourceRegistry.fromJson({
  'schemaVersion': 1,
  'sources': [currentsSource()],
});

class SharedFixtureTransport implements FeedTransport {
  int calls = 0, cancellations = 0;
  final requests = <Uri>[];
  Map<String, String> lastHeaders = {};
  Completer<FeedTransportResponse>? pending;
  FeedTransportResponse response = jsonResponse(currentsSnapshot());
  static FeedTransportResponse jsonResponse(Map<String, Object?> value) =>
      FeedTransportResponse(
        200,
        Uint8List.fromList(utf8.encode(jsonEncode(value))),
        {'content-type': 'application/json', 'etag': '"fixture-one"'},
      );
  @override
  Future<FeedTransportResponse> get(
    Uri endpoint,
    Map<String, String> headers,
  ) async {
    calls++;
    requests.add(endpoint);
    lastHeaders = headers;
    return pending?.future ?? response;
  }

  @override
  void cancel() {
    cancellations++;
  }
}

LiveContentController currentsController(
  SharedFixtureTransport transport, {
  DateTime Function()? clock,
  MemorySignatureDocumentStore? store,
  bool Function(Uri)? canOpen,
}) => LiveContentController(
  store: store ?? MemorySignatureDocumentStore(),
  eligibility: LiveContentEligibility(
    registry: currentsRegistry(),
    canOpenDestination: canOpen ?? (_) => true,
  ),
  provider: SnapshotFeedProvider(
    endpoint: Uri.parse('https://wingman.example/v1/snapshot.json'),
    transport: transport,
  ),
  clock: clock ?? () => fixtureNow,
)..setContext(LiveContentContext.owner);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native RSS dispatch never calls the configured Currents API origin',
    () async {
      final registry = LiveSourceRegistry.fromJson({
        'schemaVersion': 1,
        'sources': [
          {
            ...currentsSource(),
            'feedUrl': 'https://api.currentsapi.services/v2/latest-news',
            'feedRedirectHosts': ['api.currentsapi.services'],
          },
        ],
      });
      final gate = LiveContentEligibility(
        registry: registry,
        canOpenDestination: (_) => true,
      );
      final transport = rss.FakeTransport([]);
      final provider = RssFeedProvider(
        registry: registry,
        eligibility: gate,
        allowsEditorialText: gate.acceptsFeedText,
        transport: transport,
        clock: () => fixtureNow,
      );
      final response = await provider.fetch();
      expect(transport.calls, isEmpty);
      expect(response.snapshot!.items, isEmpty);
    },
  );
  test(
    'explicit shared Currents source withdrawal also revokes saved links',
    () async {
      var now = fixtureNow;
      final transport = SharedFixtureTransport();
      final controller = currentsController(transport, clock: () => now);
      try {
        await controller.refresh();
        await controller.save(controller.items.first);
        now = now.add(const Duration(minutes: 15));
        transport.response = SharedFixtureTransport.jsonResponse({
          ...currentsSnapshot(),
          'sources': <Object?>[],
          'items': <Object?>[],
        });
        await controller.refresh();
        expect(controller.items, isEmpty);
        expect(
          controller.canOpenSavedLink(controller.savedItems.single),
          isFalse,
        );
        expect(controller.savedItems.single.available, isFalse);
      } finally {
        controller.dispose();
      }
    },
  );
  test(
    'legacy all-source preference migrates, explicit subset and hides survive',
    () async {
      final legacy = rss.source();
      final other = rss.source(id: 'other');
      final registry = LiveSourceRegistry([
        legacy,
        other,
        ApprovedLiveSource.fromJson(currentsSource()),
      ]);
      for (final selected in [
        <String>{'news', 'other'},
        <String>{'news'},
      ]) {
        final store = MemorySignatureDocumentStore();
        await store.writeDocument(
          'liveContentPreferences',
          LiveContentPreferences(
            selectedSourceIds: selected,
            hiddenSourceIds: {'other'},
            selectedTopics: {'technology'},
          ).toJson(),
        );
        final controller = LiveContentController(
          store: store,
          eligibility: LiveContentEligibility(
            registry: registry,
            canOpenDestination: (_) => true,
          ),
        )..setContext(LiveContentContext.owner);
        try {
          await controller.initialize();
          expect(
            controller.preferences.selectedSourceIds,
            selected.length == 2 ? {'news', 'other', 'currents'} : {'news'},
          );
          expect(controller.preferences.hiddenSourceIds, {'other'});
          expect(controller.preferences.selectedTopics, {'technology'});
        } finally {
          controller.dispose();
        }
      }
    },
  );
  test(
    'a legacy publisher hide also hides its Currents supplied articles',
    () async {
      final transport = SharedFixtureTransport();
      final registry = LiveSourceRegistry([
        rss.source(),
        ApprovedLiveSource.fromJson(currentsSource()),
      ]);
      final controller = LiveContentController(
        store: MemorySignatureDocumentStore(),
        provider: SnapshotFeedProvider(
          endpoint: Uri.parse('https://wingman.example/v1/snapshot.json'),
          transport: transport,
        ),
        eligibility: LiveContentEligibility(
          registry: registry,
          canOpenDestination: (_) => true,
        ),
        clock: () => fixtureNow,
      )..setContext(LiveContentContext.owner);
      try {
        await controller.refresh();
        expect(controller.items, isNotEmpty);
        await controller.hideSource('news');
        expect(controller.items, isEmpty);
        expect(controller.preferences.hiddenSourceIds, {'news'});
      } finally {
        controller.dispose();
      }
    },
  );
  test(
    'safe shared availability explains empty categories without hiding healthy cards',
    () async {
      for (final availability in [
        'configuration',
        'quota-paused',
        'policy-held',
      ]) {
        final transport = SharedFixtureTransport()
          ..response = SharedFixtureTransport.jsonResponse({
            ...currentsSnapshot(stories: [currentsStory('sports')]),
            'staleSourceIds': ['currents'],
            'sources': [
              {
                ...currentsSource(),
                'availability': availability,
                'status': 'unavailable',
              },
            ],
          });
        final controller = currentsController(transport);
        try {
          await controller.refresh();
          await controller.selectTopics({'entertainment'});
          expect(controller.categoryHealth.reason, availability);
          await controller.selectTopics({'sports'});
          expect(controller.items, hasLength(1));
          expect(controller.categoryHealth.reason, 'available');
          expect(controller.categoryHealth.hasFailure, isFalse);
        } finally {
          controller.dispose();
        }
      }
    },
  );
  testWidgets(
    'idle preview expiry removes durable cache without a network request',
    (tester) async {
      var now = fixtureNow;
      final store = MemorySignatureDocumentStore();
      final transport = SharedFixtureTransport()
        ..response = SharedFixtureTransport.jsonResponse(
          currentsSnapshot(
            stories: [
              {
                ...currentsStory('sports'),
                'expiresAt': fixtureNow
                    .add(const Duration(seconds: 2))
                    .toIso8601String(),
              },
            ],
          ),
        );
      final controller = currentsController(
        transport,
        store: store,
        clock: () => now,
      );
      try {
        await controller.refresh();
        expect(controller.items, hasLength(1));
        now = now.add(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        await controller.flush();
        expect(controller.items, isEmpty);
        expect(
          jsonEncode(await store.readDocument('liveContentCache')),
          isNot(contains('Fixture sports report')),
        );
        expect(transport.calls, 1);
      } finally {
        controller.dispose();
      }
    },
  );
  test(
    '16 canonical entries plus 5 retained derived topics are admitted via trusted common snapshot',
    () async {
      final transport = SharedFixtureTransport();
      final controller = currentsController(transport);
      try {
        await controller.refresh();
        expect(controller.availableTopics, containsAll(liveContentTopicOrder));
        for (final topic in liveContentTopicOrder) {
          await controller.selectTopics({topic});
          expect(controller.items.single.topics, {topic});
          expect(controller.items.single.publisherName, 'Original Publisher');
          expect(controller.excerptFor(controller.items.single), isNotNull);
        }
        expect(transport.calls, 1);
        expect(
          transport.requests.every(
            (uri) => uri.host == 'wingman.example' && !uri.hasQuery,
          ),
          isTrue,
        );
        expect(
          controller.items.single.openingUrl.queryParameters['utm_source'],
          'provider',
        );
      } finally {
        controller.dispose();
      }
    },
  );
  test(
    'public provider hosts need both configured provider approval and transport provenance',
    () {
      final item = LiveContentItem.fromJson(currentsStory('sports'));
      final withNotice = LiveContentItem.fromJson({
        ...currentsStory('sports'),
        'attribution': 'x' * 201,
      });
      expect(withNotice.attribution, hasLength(201));
      final gate = LiveContentEligibility(
        registry: currentsRegistry(),
        canOpenDestination: (_) => true,
      );
      expect(gate.accepts(item, now: fixtureNow), isFalse);
      gate.trustedProviderPreviews = true;
      expect(gate.accepts(item, now: fixtureNow), isTrue);
      for (final host in [
        '127.0.0.1',
        'localhost',
        'internal.local',
        'api.currentsapi.services',
        'other.currentsapi.services',
      ]) {
        final invalid = LiveContentItem.fromJson({
          ...currentsStory('sports'),
          'canonicalUrl': 'https://$host/story',
          'outboundUrl': null,
          'originalUrl': null,
        });
        expect(gate.accepts(invalid, now: fixtureNow), isFalse, reason: host);
      }
      final blocked = LiveContentEligibility(
        registry: currentsRegistry(),
        canOpenDestination: (_) => false,
      )..trustedProviderPreviews = true;
      expect(blocked.accepts(item, now: fixtureNow), isFalse);
    },
  );
  test(
    'hundreds of refreshes and category taps only use conditional shared cache after debounce',
    () async {
      var now = fixtureNow;
      final transport = SharedFixtureTransport();
      final controller = currentsController(transport, clock: () => now);
      try {
        await controller.refresh();
        for (var i = 0; i < 300; i++) {
          await controller.selectTopics({
            i.isEven ? 'sports' : 'entertainment',
          });
          controller.loadMore();
          await controller.refresh(force: true);
        }
        expect(transport.calls, 1);
        now = now.add(const Duration(minutes: 15));
        transport.response = FeedTransportResponse(304, Uint8List(0), {
          'etag': '"fixture-one"',
        });
        await controller.refresh();
        expect(transport.calls, 2);
        expect(transport.lastHeaders['If-None-Match'], '"fixture-one"');
        expect(transport.lastHeaders.containsKey('Authorization'), isFalse);
        expect(controller.lastSuccessAt, fixtureNow);
        expect(
          controller.items.single.publishedAt,
          fixtureNow.subtract(const Duration(hours: 2)),
        );
      } finally {
        controller.dispose();
      }
    },
  );
  test(
    'save stores only original link; cache republishing and 304 do not extend retention',
    () async {
      var now = fixtureNow;
      final store = MemorySignatureDocumentStore();
      final transport = SharedFixtureTransport();
      final controller = currentsController(
        transport,
        clock: () => now,
        store: store,
      );
      try {
        await controller.refresh();
        final item = controller.items.first;
        await controller.save(item);
        expect(controller.canOpen(item), isTrue);
        final saved = controller.savedItems.single;
        expect(saved.item, isNull);
        expect(saved.linkUrl, item.openingUrl);
        expect(
          jsonEncode(await store.readDocument('liveContentSaved')),
          isNot(contains(item.excerpt!)),
        );
        now = now.add(const Duration(hours: 25));
        transport.response = SharedFixtureTransport.jsonResponse({
          ...currentsSnapshot(),
          'generatedAt': now.toIso8601String(),
          'expiresAt': now.add(const Duration(hours: 24)).toIso8601String(),
        });
        await controller.refresh();
        expect(controller.items, isEmpty);
        expect(
          controller.canOpenSavedLink(controller.savedItems.single),
          isTrue,
        );
        expect(
          (await store.readDocument('liveContentCache'))!['snapshot'],
          isNotNull,
        );
        expect(
          jsonEncode(await store.readDocument('liveContentCache')),
          isNot(contains(item.excerpt!)),
        );
      } finally {
        controller.dispose();
      }
    },
  );
  test(
    'private and handoff invalidate delayed snapshot responses and keep source hides',
    () async {
      for (final context in [
        LiveContentContext.private,
        LiveContentContext.handoff,
      ]) {
        final transport = SharedFixtureTransport()
          ..pending = Completer<FeedTransportResponse>();
        final controller = currentsController(transport);
        try {
          final future = controller.refresh();
          while (transport.calls == 0) {
            await Future<void>.delayed(Duration.zero);
          }
          controller.setContext(context);
          transport.pending!.complete(
            SharedFixtureTransport.jsonResponse(currentsSnapshot()),
          );
          await future;
          expect(controller.items, isEmpty);
          expect(transport.cancellations, greaterThan(0));
          controller.setContext(LiveContentContext.owner);
          transport.pending = null;
          await controller.refresh();
          await controller.hidePublisher('publisher.example');
          expect(controller.items, isEmpty);
          expect(
            controller.preferences.hiddenSourceIds,
            contains('publisher:publisher.example'),
          );
        } finally {
          controller.dispose();
        }
      }
    },
  );
  test(
    'missing optional image remains a publisher text card and cached content is immediate on restart',
    () async {
      final store = MemorySignatureDocumentStore();
      final transport = SharedFixtureTransport()
        ..response = SharedFixtureTransport.jsonResponse(
          currentsSnapshot(
            stories: [
              {
                ...currentsStory('sports'),
                'image': {'url': 'null'},
                'excerpt': null,
              },
            ],
          ),
        );
      final controller = currentsController(transport, store: store);
      await controller.refresh();
      expect(controller.items.single.image, isNull);
      controller.dispose();
      final offline = SharedFixtureTransport()
        ..pending = Completer<FeedTransportResponse>();
      final restored = currentsController(offline, store: store);
      try {
        await restored.initialize();
        expect(restored.items.single.title, 'Fixture sports report 1');
        expect(offline.calls, 0);
      } finally {
        restored.dispose();
      }
    },
  );
}
