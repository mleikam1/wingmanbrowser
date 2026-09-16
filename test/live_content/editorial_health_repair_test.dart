import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';

import 'editorial_delivery_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final outcome in ['cache-prohibited', 'not-due']) {
    test('native $outcome storage hold is not a publisher failure', () async {
      final source = fixtures.source('sports', images: false);
      final provider = fixtures.DeliveryProvider(
        FeedResponse(
          snapshot: fixtures.snapshot([source], []),
          providerState: {
            'schemaVersion': 1,
            'sources': {
              'sports': {
                'error': 'cache-prohibited',
                'diagnostics': {
                  'outcome': outcome,
                  'lastError': 'cache-prohibited',
                  // Older native checkpoints reported this successful HTTP
                  // response as a transport error during the storage hold.
                  if (outcome == 'cache-prohibited')
                    'transportError': 'cache-prohibited',
                  'httpStatus': 200,
                },
              },
            },
          },
        ),
      );
      final controller = await fixtures.controller(
        [source],
        [],
        provider: provider,
      );
      addTearDown(controller.dispose);
      await controller.selectTopics({'sports'});

      expect(controller.items, isEmpty);
      expect(controller.categoryHealth.reason, 'cache-prohibited');
      expect(controller.categoryHealth.hasFailure, isFalse);
      expect(
        controller.categoryHealth.title,
        'Publisher storage is restricted',
      );
      expect(provider.calls, 1);
    });
  }

  test('shared storage hold survives a later not-due snapshot', () async {
    final source = fixtures.source('sports', images: false);
    final snapshot = LiveSnapshot(
      snapshotId: 'shared-storage-hold',
      generatedAt: fixtures.now,
      expiresAt: fixtures.now.add(const Duration(hours: 1)),
      sources: [
        LiveSource.fromJson({
          ...source.source.toJson(),
          'diagnostics': {
            'outcome': 'not-due',
            'lastError': 'source-cache-prohibited',
            'httpStatus': 200,
          },
        }),
      ],
      items: const [],
    );
    final controller = await fixtures.controller(
      [source],
      [],
      provider: fixtures.DeliveryProvider(FeedResponse(snapshot: snapshot)),
    );
    addTearDown(controller.dispose);
    await controller.selectTopics({'sports'});

    expect(controller.categoryHealth.reason, 'cache-prohibited');
    expect(controller.categoryHealth.hasFailure, isFalse);
  });

  test(
    'a sponsored source cannot stand in for an editorial publisher',
    () async {
      final base = fixtures.source('travel', images: false);
      final sponsored = ApprovedLiveSource(
        source: base.source,
        allowedArticleHosts: base.allowedArticleHosts,
        articlePathPrefixes: base.articlePathPrefixes,
        eligibilityScope: 'sponsored-features',
        enabled: true,
        displayMode: 'sponsored-syndication',
      );
      final controller = await fixtures.controller(
        [sponsored],
        [],
        provider: fixtures.DeliveryProvider(
          FeedResponse(
            snapshot: fixtures.snapshot([sponsored], []),
            providerState: {
              'schemaVersion': 1,
              'sources': {
                'travel': {
                  'diagnostics': {'outcome': 'deferred'},
                },
              },
            },
          ),
        ),
      );
      addTearDown(controller.dispose);
      await controller.selectTopics({'travel'});

      expect(
        controller.categoryHealth.reason,
        'no-production-editorial-source',
      );
      expect(controller.categoryHealth.hasFailure, isFalse);
      expect(
        controller.categoryHealth.message,
        contains('sponsored features are labeled separately'),
      );
    },
  );
}
