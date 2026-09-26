import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'currents_shared_test.dart' as fixture;
import 'rss_provider_test.dart' as rss;

final now = fixture.fixtureNow;

Map<String, Object?> braveSource({bool approved = true}) => {
  ...fixture.currentsSource(),
  'id': 'brave-news',
  'name': 'Wingman News · Brave',
  'providerId': 'brave',
  'homepageUrl': 'https://brave.com/search/api/',
  'eligibilityScope': 'brave-preview',
  'feedUrl': 'https://api.search.brave.com/res/v1/news/search',
  'feedRedirectHosts': ['api.search.brave.com'],
  'minRefreshSeconds': 900,
  'enabled': approved,
  'sharedNewsGrant': {
    'status': approved ? 'approved' : 'unknown',
    'reference': approved ? 'fixture-grant' : null,
    'retentionSeconds': approved ? 86400 : null,
  },
  'rights': {
    'titles': approved,
    'excerpts': approved,
    'images': false,
    'attribution': 'Original publisher; results supplied by Brave Search API',
    'licenseUrl': 'https://api-dashboard.search.brave.com/terms-of-service',
  },
};

Map<String, Object?> braveStory() => {
  ...fixture.currentsStory('science'),
  'id': 'brave-fixture-one',
  'sourceId': 'brave-news',
  'providerId': 'brave',
  'publishedAt': null,
  'discoveredAt': now.toIso8601String(),
  'pageDate': now.subtract(const Duration(hours: 2)).toIso8601String(),
  'providerFetchedAt': now
      .subtract(const Duration(minutes: 5))
      .toIso8601String(),
  'sharedGrantReference': 'fixture-grant',
  'sharedGrantRetentionSeconds': 86400,
  'rights': braveSource()['rights'],
  'eligibility': {
    'state': 'eligible',
    'basis': 'provider-preview',
    'scope': 'brave-preview',
  },
};

Map<String, Object?> braveSnapshot({Map<String, Object?>? story}) => {
  ...fixture.currentsSnapshot(),
  'sources': [braveSource()],
  'items': [story ?? braveStory()],
};

LiveSourceRegistry registry({bool approved = true}) =>
    LiveSourceRegistry.fromJson({
      'schemaVersion': 1,
      'sources': [braveSource(approved: approved)],
    });

LiveContentController controllerFor(
  fixture.SharedFixtureTransport transport, {
  MemorySignatureDocumentStore? store,
  DateTime Function()? clock,
}) => LiveContentController(
  store: store ?? MemorySignatureDocumentStore(),
  eligibility: LiveContentEligibility(
    registry: registry(),
    canOpenDestination: (_) => true,
  ),
  provider: SnapshotFeedProvider(
    endpoint: Uri.parse('https://wingman.example/v1/snapshot.json'),
    transport: transport,
  ),
  clock: clock ?? () => now,
)..setContext(LiveContentContext.owner);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Brave requires pinned grant and shared transport without changing publication date',
    () {
      final item = LiveContentItem.fromJson(braveStory());
      final gate = LiveContentEligibility(
        registry: registry(),
        canOpenDestination: (_) => true,
      );
      expect(gate.accepts(item, now: now), isFalse);
      gate.trustedProviderPreviews = true;
      expect(gate.accepts(item, now: now), isTrue);
      expect(item.publishedAt, isNull);
      expect(item.pageDate, now.subtract(const Duration(hours: 2)));
      expect(item.discoveredAt, now);
      expect(
        LiveContentItem.fromJson(item.toJson()).providerFetchedAt,
        item.providerFetchedAt,
      );
      expect(gate.imageFor(item), isNull);
      final unapproved = LiveContentEligibility(
        registry: registry(approved: false),
        canOpenDestination: (_) => true,
      )..trustedProviderPreviews = true;
      expect(unapproved.accepts(item, now: now), isFalse);
      for (final change in [
        {'sharedGrantReference': 'different-grant'},
        {'sharedGrantRetentionSeconds': 86401},
        {'discoveredAt': now.add(const Duration(seconds: 1)).toIso8601String()},
        {'pageDate': now.add(const Duration(seconds: 1)).toIso8601String()},
        {
          'providerFetchedAt': now
              .add(const Duration(seconds: 1))
              .toIso8601String(),
        },
      ]) {
        expect(
          gate.accepts(
            LiveContentItem.fromJson({...braveStory(), ...change}),
            now: now,
          ),
          isFalse,
        );
      }
    },
  );

  test(
    'native RSS never calls the Brave API or loads a shared preview',
    () async {
      final gate = LiveContentEligibility(
        registry: registry(),
        canOpenDestination: (_) => true,
      );
      final transport = rss.FakeTransport([]);
      final provider = RssFeedProvider(
        registry: registry(),
        eligibility: gate,
        allowsEditorialText: gate.acceptsFeedText,
        transport: transport,
        clock: () => now,
      );
      final result = await provider.fetch();
      expect(transport.calls, isEmpty);
      expect(result.snapshot!.items, isEmpty);
    },
  );

  test(
    'shared preview saves only original link and uses finite existing discovery',
    () async {
      final transport = fixture.SharedFixtureTransport()
        ..response = fixture.SharedFixtureTransport.jsonResponse(
          braveSnapshot(),
        );
      final store = MemorySignatureDocumentStore();
      final controller = controllerFor(transport, store: store);
      try {
        await controller.refresh();
        expect(controller.items, hasLength(1));
        expect(controller.hasMore, isFalse);
        final item = controller.items.single;
        await controller.save(item);
        expect(controller.savedItems.single.item, isNull);
        expect(controller.savedItems.single.linkUrl, item.openingUrl);
        final saved = jsonEncode(await store.readDocument('liveContentSaved'));
        expect(saved, isNot(contains(item.title)));
        expect(saved, isNot(contains(item.excerpt!)));
        expect(
          transport.requests.every(
            (uri) => uri.host == 'wingman.example' && !uri.hasQuery,
          ),
          isTrue,
        );
        expect(transport.calls, 1);
      } finally {
        controller.dispose();
      }
    },
  );

  testWidgets(
    'expiry removes Brave previews from durable cache without refetch',
    (tester) async {
      var clock = now;
      final transport = fixture.SharedFixtureTransport()
        ..response = fixture.SharedFixtureTransport.jsonResponse(
          braveSnapshot(
            story: {
              ...braveStory(),
              'expiresAt': now
                  .add(const Duration(seconds: 2))
                  .toIso8601String(),
            },
          ),
        );
      final store = MemorySignatureDocumentStore();
      final controller = controllerFor(
        transport,
        store: store,
        clock: () => clock,
      );
      try {
        await controller.refresh();
        expect(controller.items, hasLength(1));
        clock = now.add(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        await controller.flush();
        expect(controller.items, isEmpty);
        expect(
          jsonEncode(await store.readDocument('liveContentCache')),
          isNot(contains('brave-fixture-one')),
        );
        expect(transport.calls, 1);
      } finally {
        controller.dispose();
      }
    },
  );

  test(
    'private handoff inactive and updates off make no automatic request',
    () async {
      final transport = fixture.SharedFixtureTransport()
        ..response = fixture.SharedFixtureTransport.jsonResponse(
          braveSnapshot(),
        );
      final controller = controllerFor(transport);
      try {
        for (final context in [
          LiveContentContext.private,
          LiveContentContext.handoff,
          LiveContentContext.inactive,
        ]) {
          controller.setContext(context);
          await controller.refresh();
          expect(controller.items, isEmpty);
        }
        expect(transport.calls, 0);
        controller.setContext(LiveContentContext.owner);
        await controller.setEnabled(false);
        await controller.refresh();
        expect(transport.calls, 0);
      } finally {
        controller.dispose();
      }
    },
  );

  test('private transition discards late shared response', () async {
    final transport = fixture.SharedFixtureTransport()
      ..pending = Completer<FeedTransportResponse>();
    final controller = controllerFor(transport);
    try {
      final pending = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      controller.setContext(LiveContentContext.private);
      transport.pending!.complete(
        fixture.SharedFixtureTransport.jsonResponse(braveSnapshot()),
      );
      await pending;
      expect(controller.items, isEmpty);
      expect(transport.cancellations, greaterThan(0));
    } finally {
      controller.dispose();
    }
  });
}
