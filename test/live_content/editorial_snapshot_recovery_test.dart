import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

import 'editorial_delivery_test.dart' as fixtures;

// These synthetic snapshots verify recovery and topic authorization. They do
// not measure publisher supply or relax explicit withdrawal protections.
class RecoveryHarness {
  RecoveryHarness(
    this.source,
    LiveContentItem initial, {
    MemorySignatureDocumentStore? store,
  }) : store = store ?? MemorySignatureDocumentStore(),
       provider = fixtures.DeliveryProvider(
         FeedResponse(snapshot: fixtures.snapshot([source], [initial])),
       );

  final ApprovedLiveSource source;
  final fixtures.DeliveryProvider provider;
  final MemorySignatureDocumentStore store;
  DateTime clock = fixtures.now;

  LiveContentController createController() => LiveContentController(
    store: store,
    provider: provider,
    eligibility: LiveContentEligibility(
      registry: LiveSourceRegistry([source], requireStoryImages: true),
      canOpenDestination: (_) => true,
    ),
    clock: () => clock,
  )..setContext(LiveContentContext.owner);

  Future<void> receive(
    LiveContentController controller,
    LiveContentItem item,
  ) => receiveResponse(
    controller,
    FeedResponse(snapshot: fixtures.snapshot([source], [item])),
  );

  Future<void> receiveResponse(
    LiveContentController controller,
    FeedResponse response,
  ) async {
    clock = clock.add(const Duration(minutes: 2));
    provider.response = response;
    final previousCalls = provider.calls;
    await controller.refresh();
    expect(provider.calls, previousCalls + 1);
  }
}

class CacheCheckpointFailureStore extends MemorySignatureDocumentStore {
  bool failCheckpoint = false;

  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) async {
    if (failCheckpoint && key == 'liveContentRefreshState') {
      throw StateError('Synthetic checkpoint write failure');
    }
    await super.writeDocument(key, value);
  }
}

FeedResponse cacheHoldResponse(
  ApprovedLiveSource source, {
  required bool providerStateError,
  bool notDue = false,
}) => FeedResponse(
  snapshot: LiveSnapshot.fromJson({
    ...fixtures.snapshot([source], []).toJson(),
    'sources': [
      {
        ...source.source.toJson(),
        'status': 'cached',
        'diagnostics': {
          'outcome': notDue ? 'not-due' : 'cache-prohibited',
          if (!providerStateError) 'lastError': 'source-cache-prohibited',
        },
      },
    ],
  }),
  providerState: providerStateError
      ? {
          'schemaVersion': 1,
          'sources': {
            source.source.id: {
              'error': 'cache-prohibited',
              'diagnostics': {
                'outcome': notDue ? 'not-due' : 'cache-prohibited',
              },
            },
          },
        }
      : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final malformedField in ['future publication', 'unsupported topic']) {
    test(
      '$malformedField is held without permanently revoking a saved title',
      () async {
        final source = fixtures.source('sports', images: false);
        final original = fixtures.story('sports', image: false);
        final harness = RecoveryHarness(source, original);
        var controller = harness.createController();
        try {
          await controller.refresh();
          await controller.save(controller.items.single);
          final malformed = LiveContentItem.fromJson({
            ...original.toJson(),
            'title': 'A replacement with invalid required metadata',
            if (malformedField == 'future publication')
              'publishedAt': fixtures.now
                  .add(const Duration(days: 3))
                  .toIso8601String(),
            if (malformedField == 'unsupported topic')
              'topics': ['entertainment'],
          });

          await harness.receive(controller, malformed);
          expect(controller.items, isEmpty);
          expect(controller.savedItems.single.available, isTrue);
          expect(controller.savedItems.single.item!.title, original.title);
          expect(
            controller.canOpen(controller.savedItems.single.item!),
            isTrue,
          );
          final saved = await harness.store.readDocument('liveContentSaved');
          expect(saved!['revokedItemIds'], isEmpty);

          // Persisted metadata must survive a new controller, not merely stay
          // usable in the session that originally saved the article.
          controller.dispose();
          controller = harness.createController();
          await controller.initialize();
          expect(controller.savedItems.single.available, isTrue);
          expect(controller.savedItems.single.item!.id, original.id);
          expect(controller.savedItems.single.item!.title, original.title);

          final repaired = LiveContentItem.fromJson({
            ...original.toJson(),
            'title': 'The publisher corrected the same article metadata',
          });
          await harness.receive(controller, repaired);
          expect(controller.items.single.id, original.id);
          expect(controller.items.single.title, repaired.title);
          expect(controller.items.single.canonicalUrl, original.canonicalUrl);
          expect(controller.canOpen(controller.items.single), isTrue);
          expect(controller.savedItems.single.available, isTrue);
          final recovered = await harness.store.readDocument(
            'liveContentSaved',
          );
          expect(recovered!['revokedItemIds'], isEmpty);
        } finally {
          controller.dispose();
        }
      },
    );
  }

  for (final aliasApproved in [false, true]) {
    test(
      'an extra topic appears only when the source approves it: $aliasApproved',
      () async {
        final base = fixtures.source('sports', images: false);
        final source = ApprovedLiveSource(
          source: LiveSource.fromJson({
            ...base.source.toJson(),
            'topics': ['sports', if (aliasApproved) 'entertainment'],
          }),
          allowedArticleHosts: base.allowedArticleHosts,
          articlePathPrefixes: base.articlePathPrefixes,
          eligibilityScope: base.eligibilityScope,
          enabled: true,
        );
        final item = LiveContentItem.fromJson({
          ...fixtures.story('sports', image: false).toJson(),
          'topics': ['sports', 'entertainment'],
        });
        final harness = RecoveryHarness(source, item);
        final controller = harness.createController();
        try {
          await controller.refresh();
          await controller.selectTopics({'sports'});
          expect(controller.items.map((i) => i.id), [item.id]);
          await controller.selectTopics({'entertainment'});
          expect(
            controller.items.map((i) => i.id),
            aliasApproved ? [item.id] : isEmpty,
          );
        } finally {
          controller.dispose();
        }
      },
    );
  }

  for (final providerStateError in [false, true]) {
    test(
      'temporary no-store holds then restores saved text; explicit withdrawal persists (provider state: $providerStateError)',
      () async {
        final source = fixtures.source('sports', images: false);
        final original = fixtures.story('sports', image: false);
        final harness = RecoveryHarness(source, original);
        var controller = harness.createController();
        try {
          await controller.refresh();
          await controller.save(controller.items.single);
          final originalSavedAt = controller.savedItems.single.savedAt;
          await harness.receiveResponse(
            controller,
            cacheHoldResponse(source, providerStateError: providerStateError),
          );
          expect(controller.items, isEmpty);
          expect(controller.savedItems.single.item, isNull);
          expect(controller.canOpen(original), isFalse);
          expect(
            controller.savedItems.single.unavailableReason,
            'This publisher temporarily restricts feed storage.',
          );
          final held = await harness.store.readDocument('liveContentSaved');
          expect(held!['revokedItemIds'], isEmpty);
          expect(jsonEncode(held), isNot(contains(original.title)));
          expect(
            jsonEncode(held),
            isNot(contains(original.canonicalUrl.toString())),
          );

          controller.dispose();
          controller = harness.createController();
          await controller.initialize();
          await harness.receiveResponse(
            controller,
            cacheHoldResponse(
              source,
              providerStateError: providerStateError,
              notDue: true,
            ),
          );
          expect(controller.savedItems.single.item, isNull);
          expect(controller.canOpen(original), isFalse);
          expect(controller.items, isEmpty);
          final stillHeld = await harness.store.readDocument(
            'liveContentSaved',
          );
          expect(stillHeld!['revokedItemIds'], isEmpty);
          expect(jsonEncode(stillHeld), isNot(contains(original.title)));

          // A fresh lawful source state explicitly clears its temporary cache
          // error and supplies the same article identity again.
          await harness.receiveResponse(
            controller,
            FeedResponse(
              snapshot: fixtures.snapshot([source], [original]),
              providerState: {
                'schemaVersion': 1,
                'sources': {
                  source.source.id: {
                    'error': null,
                    'diagnostics': {'outcome': 'success'},
                  },
                },
              },
            ),
          );
          expect(controller.items.single.id, original.id);
          expect(controller.savedItems.single.item!.id, original.id);
          expect(controller.savedItems.single.item!.title, original.title);
          expect(controller.savedItems.single.savedAt, originalSavedAt);
          expect(
            controller.canOpen(controller.savedItems.single.item!),
            isTrue,
          );

          await harness.receiveResponse(
            controller,
            FeedResponse(
              snapshot: LiveSnapshot.fromJson({
                ...fixtures.snapshot([source], []).toJson(),
                'revokedItemIds': [original.id],
              }),
            ),
          );
          await harness.receive(controller, original);
          expect(controller.items, isEmpty);
          expect(controller.savedItems.single.item, isNull);
          expect(controller.canOpen(original), isFalse);
          final withdrawn = await harness.store.readDocument(
            'liveContentSaved',
          );
          expect(withdrawn!['revokedItemIds'], contains(original.id));
          expect(jsonEncode(withdrawn), isNot(contains(original.title)));
        } finally {
          controller.dispose();
        }
      },
    );
  }

  test(
    'no-store stays hidden in memory when its checkpoint write fails',
    () async {
      final source = fixtures.source('sports', images: false);
      final original = fixtures.story('sports', image: false);
      final store = CacheCheckpointFailureStore();
      final harness = RecoveryHarness(source, original, store: store);
      final controller = harness.createController();
      try {
        await controller.refresh();
        await controller.save(controller.items.single);
        store.failCheckpoint = true;
        await harness.receiveResponse(
          controller,
          cacheHoldResponse(source, providerStateError: true),
        );
        expect(controller.storageError, isNotNull);
        expect(controller.savedItems.single.item, isNull);
        expect(controller.items, isEmpty);
        expect(controller.canOpen(original), isFalse);
        final persisted = await store.readDocument('liveContentSaved');
        expect(persisted!['revokedItemIds'], isEmpty);
        // The failed write cannot promise durable redaction. It must still stop
        // exposure now and prevent repeated requests with lost pacing state.
        store.failCheckpoint = false;
        harness.clock = harness.clock.add(const Duration(hours: 2));
        final calls = harness.provider.calls;
        await controller.refresh();
        expect(harness.provider.calls, calls);
        expect(controller.savedItems.single.item, isNull);
      } finally {
        controller.dispose();
      }
    },
  );
}
