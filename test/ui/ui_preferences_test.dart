import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/design_system/ui_preferences.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

class ControlledUiStore extends MemorySignatureDocumentStore {
  int reads = 0, writes = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<Map<String, Object?>?> readDocument(String key) {
    reads++;
    return super.readDocument(key);
  }

  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) async {
    writes++;
    await gate?.future;
    if (fail) throw StateError('Synthetic disk error');
    return super.writeDocument(key, value);
  }
}

void main() {
  test(
    'explicit Home choices restore, serialize, and preserve the last durable layout on failure',
    () async {
      final store = ControlledUiStore();
      final controller = UiPreferencesController(
        store: store,
        ephemeral: false,
      );
      await controller.initialize();
      store.gate = Completer<void>();
      final first = controller.update((p) => p.copyWith(showTask: false));
      final second = controller.update(
        (p) => p.copyWith(shortcutIds: ['moon-phases']),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot.showTask, isTrue);
      store.gate!.complete();
      await Future.wait([first, second]);
      expect(controller.snapshot.showTask, isFalse);
      expect(controller.snapshot.shortcutIds, ['moon-phases']);
      store.gate = null;
      store.fail = true;
      await expectLater(
        controller.update((p) => p.copyWith(showTask: true)),
        throwsStateError,
      );
      expect(controller.snapshot.showTask, isFalse);
      final restored = UiPreferencesController(store: store, ephemeral: false);
      await restored.initialize();
      expect(restored.snapshot.shortcutIds, ['moon-phases']);
      expect(restored.snapshot.showTask, isFalse);
      controller.dispose();
      restored.dispose();
    },
  );
  test('private Home never reads or writes the normal document', () async {
    final store = ControlledUiStore();
    final private = UiPreferencesController(store: store, ephemeral: true);
    await private.initialize();
    await private.update((p) => p.copyWith(shortcutIds: ['moon-phases']));
    expect(store.reads, 0);
    expect(store.writes, 0);
    private.dispose();
    final fresh = UiPreferencesController(store: store, ephemeral: true);
    await fresh.initialize();
    expect(fresh.snapshot.shortcutIds, isEmpty);
    fresh.dispose();
  });
  test(
    'malformed or oversized layout stays untouched, never silently truncates',
    () async {
      final store = ControlledUiStore();
      final bad = UiPreferences().toJson()
        ..['shortcutIds'] = List.filled(7, 'moon-phases');
      await store.writeDocument('ui', bad);
      final controller = UiPreferencesController(
        store: store,
        ephemeral: false,
      );
      await controller.initialize();
      expect(controller.storageError, isNotNull);
      await expectLater(
        controller.update((p) => p.copyWith(showTask: false)),
        throwsStateError,
      );
      expect(await store.readDocument('ui'), bad);
      expect(
        () => UiPreferences.fromJson(
          UiPreferences().toJson()..['unexpected'] = true,
        ),
        throwsFormatException,
      );
      expect(
        () => UiPreferences.fromJson(
          UiPreferences().toJson()..['moduleOrder'] = ['spaces'],
        ),
        throwsFormatException,
      );
      controller.dispose();
    },
  );
}
