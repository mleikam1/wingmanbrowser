import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

import 'editorial_delivery_test.dart' as fixtures;

// These synthetic snapshots verify recovery and topic authorization. They do
// not measure publisher supply or relax explicit withdrawal protections.
class RecoveryHarness {
  RecoveryHarness(this.source, LiveContentItem initial)
    : provider = fixtures.DeliveryProvider(
        FeedResponse(snapshot: fixtures.snapshot([source], [initial])),
      );

  final ApprovedLiveSource source;
  final fixtures.DeliveryProvider provider;
  final MemorySignatureDocumentStore store = MemorySignatureDocumentStore();
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
  ) async {
    clock = clock.add(const Duration(minutes: 2));
    provider.response = FeedResponse(
      snapshot: fixtures.snapshot([source], [item]),
    );
    final previousCalls = provider.calls;
    await controller.refresh();
    expect(provider.calls, previousCalls + 1);
  }
}

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
}
