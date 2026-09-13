import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'live_content_test.dart' as fixtures;

class CheckpointProvider extends fixtures.FakeProvider
    implements ResumableFeedProvider {
  LiveSnapshot? restoredSnapshot;
  Map<String, dynamic>? restoredState;
  final entered = Completer<void>();
  @override
  void restore({LiveSnapshot? snapshot, Map<String, dynamic>? state}) {
    restoredSnapshot = snapshot;
    restoredState = state;
  }

  @override
  Future<FeedResponse> fetch({String? etag, String? lastModified}) {
    if (!entered.isCompleted) entered.complete();
    return super.fetch(etag: etag, lastModified: lastModified);
  }
}

final checkpoint = <String, dynamic>{
  'schemaVersion': 1,
  'sources': {
    'science': {
      'nextRefreshAt': fixtures.now
          .add(const Duration(hours: 1))
          .toIso8601String(),
      'etag': '"publisher-version"',
    },
  },
};

FeedResponse success({String? warning}) => FeedResponse(
  snapshot: fixtures.snapshot(),
  providerState: checkpoint,
  warning: warning,
);

class CheckpointFailureStore extends MemorySignatureDocumentStore {
  bool fail = true;
  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) {
    if (fail && key == 'liveContentRefreshState') {
      throw StateError('storage failure');
    }
    return super.writeDocument(key, value);
  }
}

void main() {
  test(
    'publisher checkpoint survives restart and disposable cache deletion',
    () async {
      final store = MemorySignatureDocumentStore();
      final firstProvider = CheckpointProvider()..response = success();
      final first = fixtures.makeController(
        store: store,
        provider: firstProvider,
      );
      await first.refresh();
      expect(await store.readDocument('liveContentRefreshState'), checkpoint);
      expect(first.items, isNotEmpty);
      await first.clearCache();
      expect(first.items, isEmpty);
      first.dispose();

      final restartedProvider = CheckpointProvider()..response = success();
      final restarted = fixtures.makeController(
        store: store,
        provider: restartedProvider,
      );
      await restarted.refresh();
      expect(restartedProvider.restoredState, checkpoint);
      expect(restartedProvider.restoredSnapshot, isNull);
      restarted.dispose();
    },
  );

  for (final context in [
    LiveContentContext.private,
    LiveContentContext.handoff,
  ]) {
    test(
      'in-flight response cannot persist articles or checkpoint in $context',
      () async {
        final store = MemorySignatureDocumentStore();
        final provider = CheckpointProvider()
          ..pending = Completer<FeedResponse>();
        final controller = fixtures.makeController(
          store: store,
          provider: provider,
        );
        final refreshing = controller.refresh();
        await provider.entered.future;
        controller.setContext(context);
        provider.pending!.complete(success());
        await refreshing;
        expect(controller.items, isEmpty);
        expect(await store.readDocument('liveContentRefreshState'), isNull);
        expect(await store.readDocument('liveContentCache'), isNull);
        expect(await store.readDocument('liveContentSaved'), isNull);
        controller.dispose();
      },
    );
  }

  test(
    'turning updates off cancels an in-flight checkpoint and survives restart',
    () async {
      final store = MemorySignatureDocumentStore();
      final provider = CheckpointProvider()
        ..pending = Completer<FeedResponse>();
      final controller = fixtures.makeController(
        store: store,
        provider: provider,
      );
      final refreshing = controller.refresh();
      await provider.entered.future;
      await controller.setEnabled(false);
      provider.pending!.complete(success());
      await refreshing;
      expect(await store.readDocument('liveContentRefreshState'), isNull);
      controller.dispose();
      final restartedProvider = CheckpointProvider()..response = success();
      final restarted = fixtures.makeController(
        store: store,
        provider: restartedProvider,
      );
      await restarted.refresh();
      expect(restartedProvider.calls, 0);
      expect(restarted.preferences.enabled, isFalse);
      restarted.dispose();
    },
  );

  test(
    'failed checkpoint write blocks repeat requests even after cache clear',
    () async {
      var clock = fixtures.now;
      final store = CheckpointFailureStore();
      final provider = CheckpointProvider()..response = success();
      final controller = fixtures.makeController(
        store: store,
        provider: provider,
        clock: () => clock,
      );
      await controller.refresh();
      expect(controller.storageError, isNotNull);
      expect(provider.calls, 1);
      store.fail = false;
      clock = clock.add(const Duration(hours: 2));
      await controller.clearCache();
      await controller.refresh();
      expect(provider.calls, 1);
      controller.dispose();
    },
  );

  test(
    'withdrawn saved text stays hidden when a new checkpoint cannot be saved',
    () async {
      var clock = fixtures.now;
      final store = CheckpointFailureStore()..fail = false;
      final provider = CheckpointProvider()..response = success();
      final controller = fixtures.makeController(
        store: store,
        provider: provider,
        clock: () => clock,
      );
      await controller.refresh();
      await controller.save(controller.items.first);
      final savedId = controller.savedItems.single.id;
      provider.response = FeedResponse(
        snapshot: LiveSnapshot.fromJson(
          fixtures.snapshotJson(revokedItems: [savedId]),
        ),
        providerState: checkpoint,
      );
      store.fail = true;
      clock = clock.add(const Duration(minutes: 2));
      await controller.refresh();
      expect(controller.storageError, isNotNull);
      expect(controller.savedItems.single.item, isNull);
      expect(controller.items.any((item) => item.id == savedId), isFalse);
      controller.dispose();
    },
  );

  test(
    'unreadable checkpoint does not reset publisher backoff into new requests',
    () async {
      final store = MemorySignatureDocumentStore();
      await store.writeDocument('liveContentRefreshState', {
        'schemaVersion': 99,
      });
      final provider = CheckpointProvider()..response = success();
      final controller = fixtures.makeController(
        store: store,
        provider: provider,
      );
      await controller.refresh();
      expect(provider.calls, 0);
      expect(controller.storageError, contains('refresh settings'));
      expect(await store.readDocument('liveContentRefreshState'), {
        'schemaVersion': 99,
      });
      controller.dispose();
    },
  );

  test(
    'partial source warning keeps usable articles and durable publisher pacing',
    () async {
      final store = MemorySignatureDocumentStore();
      final provider = CheckpointProvider()
        ..response = success(warning: 'Some publishers are unavailable.');
      final controller = fixtures.makeController(
        store: store,
        provider: provider,
      );
      await controller.refresh();
      expect(controller.items, isNotEmpty);
      expect(controller.stale, isTrue);
      expect(controller.error, 'Some publishers are unavailable.');
      expect(await store.readDocument('liveContentRefreshState'), checkpoint);
      controller.dispose();
    },
  );
}
