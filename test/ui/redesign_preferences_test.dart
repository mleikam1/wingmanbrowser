import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/design_system/ui_preferences.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

class _Store extends MemorySignatureDocumentStore {
  bool failWrites = false;
  int writes = 0;
  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) async {
    writes++;
    if (failWrites) throw StateError('private platform detail');
    await super.writeDocument(key, value);
  }
}

void main() {
  test(
    'version 1 layout migrates without losing choices and writes schema 2',
    () async {
      final store = _Store();
      final old = <String, Object?>{
        'version': 1,
        'showOfficial': false,
        'showTask': true,
        'showSpaces': false,
        'homeArtwork': 'forest',
        'shortcutIds': ['moon-phases'],
        'moduleOrder': ['spaces', 'task', 'official', 'shortcuts'],
      };
      await store.writeDocument('ui', old);
      final controller = UiPreferencesController(
        store: store,
        ephemeral: false,
      );
      await controller.initialize();
      expect(controller.snapshot.homeArtwork, HomeArtwork.forest);
      expect(controller.snapshot.shortcutIds, ['moon-phases']);
      expect(controller.snapshot.moduleOrder, [
        'spaces',
        'task',
        'official',
        'shortcuts',
      ]);
      expect(controller.snapshot.showOfficial, false);
      expect(controller.snapshot.showSpaces, false);
      expect(controller.snapshot.companionTone, CompanionTone.gary);
      expect(controller.snapshot.reduceMotion, false);
      expect((await store.readDocument('ui'))!['version'], 1);
      await controller.update(
        (value) => value.copyWith(
          companionTone: CompanionTone.betty,
          reduceMotion: true,
        ),
      );
      final saved = (await store.readDocument('ui'))!;
      expect(saved['version'], 2);
      expect(saved['companionTone'], 'betty');
      expect(saved['reduceMotion'], true);
      final restored = UiPreferencesController(store: store, ephemeral: false);
      await restored.initialize();
      expect(restored.snapshot.companionTone, CompanionTone.betty);
      expect(restored.snapshot.reduceMotion, true);
      expect(restored.snapshot.moduleOrder, old['moduleOrder']);
      controller.dispose();
      restored.dispose();
    },
  );

  test('all tone values round trip with motion and existing layout', () {
    for (final tone in CompanionTone.values) {
      final saved = UiPreferences(
        companionTone: tone,
        reduceMotion: true,
        homeArtwork: HomeArtwork.earthrise,
      );
      final restored = UiPreferences.fromJson(saved.toJson());
      expect(restored.companionTone, tone);
      expect(restored.reduceMotion, true);
      expect(restored.homeArtwork, HomeArtwork.earthrise);
    }
  });

  test(
    'future or malformed preferences remain preserved until explicit reset',
    () async {
      for (final patch in [
        <String, Object?>{'version': 999},
        <String, Object?>{'companionTone': 4},
        <String, Object?>{'reduceMotion': 'yes'},
      ]) {
        final store = _Store();
        final document = {...UiPreferences().toJson(), ...patch};
        await store.writeDocument('ui', document);
        final controller = UiPreferencesController(
          store: store,
          ephemeral: false,
        );
        await controller.initialize();
        expect(controller.storageError, isNotNull);
        await expectLater(
          controller.update((value) => value.copyWith(reduceMotion: true)),
          throwsStateError,
        );
        expect(await store.readDocument('ui'), document);
        expect(store.writes, 1);
        await controller.reset();
        expect(controller.storageError, isNull);
        expect(await store.readDocument('ui'), UiPreferences().toJson());
        controller.dispose();
      }
    },
  );

  test(
    'failed update keeps prior snapshot and retry persists the full change',
    () async {
      final store = _Store();
      final controller = UiPreferencesController(
        store: store,
        ephemeral: false,
      );
      await controller.initialize();
      await controller.update(
        (value) => value.copyWith(homeArtwork: HomeArtwork.creative),
      );
      final before = controller.snapshot.toJson();
      store.failWrites = true;
      await expectLater(
        controller.update(
          (value) => value.copyWith(
            companionTone: CompanionTone.wallace,
            reduceMotion: true,
          ),
        ),
        throwsStateError,
      );
      expect(controller.snapshot.toJson(), before);
      expect(await store.readDocument('ui'), before);
      expect(
        controller.storageError,
        isNot(contains('private platform detail')),
      );
      store.failWrites = false;
      await controller.update(
        (value) => value.copyWith(
          companionTone: CompanionTone.wallace,
          reduceMotion: true,
        ),
      );
      expect(controller.snapshot.companionTone, CompanionTone.wallace);
      expect(controller.snapshot.reduceMotion, true);
      expect(controller.snapshot.homeArtwork, HomeArtwork.creative);
      expect(controller.storageError, isNull);
      controller.dispose();
    },
  );

  test(
    'private preferences never read or write owner data and expire with session',
    () async {
      final store = _Store();
      await store.writeDocument(
        'ui',
        UiPreferences(
          companionTone: CompanionTone.betty,
          reduceMotion: true,
          shortcutIds: ['moon-phases'],
        ).toJson(),
      );
      final owner = await store.readDocument('ui');
      final first = UiPreferencesController(store: store, ephemeral: true);
      await first.initialize();
      expect(first.snapshot.companionTone, CompanionTone.gary);
      expect(first.snapshot.shortcutIds, isEmpty);
      await first.update(
        (value) => value.copyWith(
          companionTone: CompanionTone.wallace,
          reduceMotion: true,
        ),
      );
      expect(first.snapshot.companionTone, CompanionTone.wallace);
      expect(store.writes, 1);
      expect(await store.readDocument('ui'), owner);
      first.dispose();
      final second = UiPreferencesController(store: store, ephemeral: true);
      await second.initialize();
      expect(second.snapshot.companionTone, CompanionTone.gary);
      expect(second.snapshot.reduceMotion, false);
      expect(second.snapshot.shortcutIds, isEmpty);
      second.dispose();
    },
  );
}
