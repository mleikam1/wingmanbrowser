import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/design_system/ui_preferences.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

class _Store extends MemorySignatureDocumentStore {
  int reads = 0, writes = 0;
  bool fail = false;

  @override
  Future<Map<String, Object?>?> readDocument(String key) {
    reads++;
    return super.readDocument(key);
  }

  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) {
    writes++;
    if (fail) return Future.error(StateError('Synthetic disk failure'));
    return super.writeDocument(key, value);
  }
}

void main() {
  test(
    'legacy and unknown artwork retain the independent saved layout',
    () async {
      final store = _Store();
      for (final name in [null, 'future-artwork']) {
        final row = UiPreferences(
          showOfficial: false,
          showSpaces: false,
          shortcutIds: const ['moon-phases'],
          moduleOrder: const ['spaces', 'task', 'official', 'shortcuts'],
        ).toJson()..remove('homeArtwork');
        if (name != null) row['homeArtwork'] = name;
        await store.writeDocument('ui', row);
        final writes = store.writes;
        final controller = UiPreferencesController(
          store: store,
          ephemeral: false,
        );
        await controller.initialize();
        expect(controller.storageError, isNull);
        expect(controller.snapshot.homeArtwork, HomeArtwork.none);
        expect(controller.snapshot.showOfficial, isFalse);
        expect(controller.snapshot.showSpaces, isFalse);
        expect(controller.snapshot.shortcutIds, ['moon-phases']);
        expect(controller.snapshot.moduleOrder.first, 'spaces');
        expect(store.writes, writes);
        expect(await store.readDocument('ui'), row);
        controller.dispose();
      }
    },
  );

  test(
    'artwork persists only after a successful local write and restores',
    () async {
      final store = _Store();
      final controller = UiPreferencesController(
        store: store,
        ephemeral: false,
      );
      await controller.initialize();
      for (final artwork in HomeArtwork.values) {
        await controller.update(
          (p) => p.copyWith(homeArtwork: artwork, showTask: false),
        );
        final reopened = UiPreferencesController(
          store: store,
          ephemeral: false,
        );
        await reopened.initialize();
        expect(reopened.snapshot.homeArtwork, artwork);
        expect(reopened.snapshot.showTask, isFalse);
        reopened.dispose();
      }
      store.fail = true;
      await expectLater(
        controller.update((p) => p.copyWith(homeArtwork: HomeArtwork.none)),
        throwsStateError,
      );
      expect(controller.snapshot.homeArtwork, HomeArtwork.creative);
      expect((await store.readDocument('ui'))!['homeArtwork'], 'creative');
      controller.dispose();
    },
  );

  test(
    'private artwork choices and reset never access owner documents',
    () async {
      final store = _Store();
      final owner = UiPreferences(homeArtwork: HomeArtwork.earthrise).toJson();
      await store.writeDocument('ui', owner);
      final reads = store.reads, writes = store.writes;
      final private = UiPreferencesController(store: store, ephemeral: true);
      await private.initialize();
      expect(private.snapshot.homeArtwork, HomeArtwork.none);
      await private.update((p) => p.copyWith(homeArtwork: HomeArtwork.forest));
      await private.reset();
      expect(private.snapshot.homeArtwork, HomeArtwork.none);
      expect(store.reads, reads);
      expect(store.writes, writes);
      expect(await store.readDocument('ui'), owner);
      private.dispose();
    },
  );

  test(
    'reset clears artwork alone with Home layout and preserves separate data',
    () async {
      final store = _Store();
      const saved = {'version': 1, 'kept': 'independent owner record'};
      for (final key in ['launchpad', 'workspace', 'privacy']) {
        await store.writeDocument(key, saved);
      }
      final controller = UiPreferencesController(
        store: store,
        ephemeral: false,
      );
      await controller.initialize();
      await controller.update(
        (p) => p.copyWith(homeArtwork: HomeArtwork.forest),
      );
      await controller.reset();
      expect(controller.snapshot.homeArtwork, HomeArtwork.none);
      for (final key in ['launchpad', 'workspace', 'privacy']) {
        expect(await store.readDocument(key), saved);
      }
      controller.dispose();
      for (final invalid in [
        42,
        ['forest'],
        'x' * 33,
      ]) {
        expect(
          () => UiPreferences.fromJson(
            UiPreferences().toJson()..['homeArtwork'] = invalid,
          ),
          throwsFormatException,
        );
      }
    },
  );
}
