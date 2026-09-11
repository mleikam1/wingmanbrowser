import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/design_system/ui_preferences.dart';
import 'package:wingman_browser/signature/launchpad/launchpad.dart';
import 'package:wingman_browser/signature/signature_services.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import '../support/protected_test_support.dart';

class LaunchpadTestStore extends MemorySignatureDocumentStore {
  final reads = <String>[];
  final writes = <String>[];
  String? failRead;
  bool failWrite = false;
  Completer<void>? gate, started;
  @override
  Future<Map<String, Object?>?> readDocument(String key) async {
    reads.add(key);
    if (key == failRead) throw StateError('SENSITIVE_STORAGE_DETAIL');
    return super.readDocument(key);
  }

  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) async {
    if (key == 'launchpad') {
      final pending = gate;
      gate = null;
      started?.complete();
      started = null;
      if (pending != null) await pending.future;
      if (failWrite) {
        failWrite = false;
        throw StateError('SENSITIVE_STORAGE_DETAIL');
      }
    }
    await super.writeDocument(key, value);
    writes.add(key);
  }

  Future<void> hold() {
    gate = Completer<void>();
    started = Completer<void>();
    return started!.future;
  }
}

Future<LaunchpadController> controller(
  LaunchpadTestStore store, {
  bool ephemeral = false,
  bool Function(String)? eligible,
  bool managed = true,
}) async {
  final c = LaunchpadController(
    store: store,
    ephemeral: ephemeral,
    eligibility: LaunchpadEligibilityService(
      resourceEligible: eligible ?? (_) => true,
    ),
    clock: () => DateTime.utc(2026, 9, 11),
  );
  if (managed) addTearDown(c.dispose);
  await c.initialize();
  return c;
}

LaunchpadDraft resource(String id, {String? folder, String? title}) =>
    LaunchpadDraft(
      title: title ?? id,
      target: LaunchpadTarget.resource(id),
      localIconKey: 'book',
      folderId: folder,
    );
LaunchpadDraft website(
  String input, {
  String title = 'A website',
  String? catalogId,
}) => LaunchpadDraft(
  title: title,
  target: LaunchpadTarget.website(input),
  source: catalogId == null ? LaunchpadSource.user : LaunchpadSource.catalog,
  catalogEntryId: catalogId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'ordinary hostname canonicalization retains meaningful path, query order and fragment',
    () {
      expect(normalizeLaunchpadWebsite('  ESPN.com  '), 'https://espn.com/');
      expect(
        normalizeLaunchpadWebsite('https://EXAMPLE.org./a/b?q=1&q=2#part'),
        'https://example.org/a/b?q=1&q=2#part',
      );
      expect(
        normalizeLaunchpadWebsite('https://example.org/?q=1&q=2'),
        isNot(normalizeLaunchpadWebsite('https://example.org/?q=2&q=1')),
      );
      expect(
        normalizeLaunchpadWebsite('https://example.org/a#one'),
        isNot(normalizeLaunchpadWebsite('https://example.org/a#two')),
      );
      expect(
        normalizeLaunchpadWebsite('https://xn--bcher-kva.de/'),
        'https://xn--bcher-kva.de/',
      );
    },
  );
  test(
    'dangerous and ambiguous addresses fail without lookup, fetch or search fallback',
    () {
      for (final input in [
        'javascript:alert(1)',
        'data:text/html,a',
        'file:///etc/passwd',
        'intent://example.org',
        'mailto:user@example.org',
        'https://user:pass@example.org/',
        'https://user%40name@example.org/',
        'https://example.org\\@evil.org/',
        'https://example.org:0/',
        'https://example.org:65536/',
        'https://bad%2fhost.example/',
        'https://example.org\n/path',
        'https://127.0.0.1/',
        'http://[::1]/',
        'http://localhost./',
        'http://printer.local./',
        'http://foo.localhost./',
        'http://example.123/',
        'http://single./',
        'https://bücher.de/',
        'just a search',
      ]) {
        expect(
          () => normalizeLaunchpadWebsite(input),
          throwsFormatException,
          reason: input,
        );
      }
    },
  );
  test(
    'forged caller allowance cannot add live rendering; mandatory block not retainable',
    () {
      final target = LaunchpadTarget.website(
        normalizeLaunchpadWebsite('espn.com'),
      );
      var calls = 0;
      final service = LaunchpadEligibilityService(
        resourceEligible: (_) => true,
        evaluateWebsite: (uri) {
          calls++;
          expect(uri.toString(), 'https://espn.com/');
          return const PolicyDecision(PolicyDecisionCode.allowApproved);
        },
      );
      expect(service.assess(target).canOpen, isFalse);
      expect(
        service.assess(target).policyCode,
        PolicyDecisionCode.blockUnsupportedCapability,
      );
      expect(calls, 2);
      final blocked = LaunchpadEligibilityService(
        resourceEligible: (_) => true,
        evaluateWebsite: (_) =>
            const PolicyDecision(PolicyDecisionCode.blockSecurityThreat),
      );
      expect(blocked.assess(target).canRetainInactive, isFalse);
      final broken = LaunchpadEligibilityService(
        resourceEligible: (_) => throw StateError('secret'),
      );
      expect(
        broken.assess(const LaunchpadTarget.resource('moon-phases')).canOpen,
        isFalse,
      );
    },
  );
  test(
    'new setup persists empty, dismissal and confirmed suggestions reset never repin removed entries',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store);
      expect(c.snapshot.shortcuts, isEmpty);
      expect(c.snapshot.setup, LaunchpadSetup.notStarted);
      await c.completeSetup(dismissed: true);
      final id = await c.addShortcut(resource('moon-phases'));
      await c.removeShortcut(id);
      await c.resetConfirmed();
      expect(c.snapshot.shortcuts, isEmpty);
      await c.completeSetup();
      final reopened = await controller(store);
      expect(reopened.snapshot.setup, LaunchpadSetup.completed);
      expect(reopened.snapshot.shortcuts, isEmpty);
    },
  );
  test(
    'legacy Home IDs migrate exactly once without changing unrelated documents or filtering away retired IDs',
    () async {
      final store = LaunchpadTestStore();
      final old = UiPreferences(
        shortcutIds: ['moon-phases', 'retired-resource'],
      ).toJson();
      await store.writeDocument('ui', old);
      await store.writeDocument('workspace', {'preserved': 'original'});
      final c = await controller(store, eligible: (id) => id == 'moon-phases');
      expect(c.snapshot.shortcuts.map((s) => s.target.value), [
        'moon-phases',
        'retired-resource',
      ]);
      expect(c.snapshot.setup, LaunchpadSetup.completed);
      expect(
        c.eligibility.presentedTitle(c.snapshot.shortcuts.last),
        'Unavailable resource',
      );
      expect(await store.readDocument('ui'), old);
      await c.removeShortcut(c.snapshot.shortcuts.first.id);
      final reopened = await controller(store);
      expect(reopened.snapshot.shortcuts.map((s) => s.target.value), [
        'retired-resource',
      ]);
      expect(await store.readDocument('workspace'), {'preserved': 'original'});
    },
  );
  test(
    'explicit clear is durable, clears only Launchpad and never reimports or undoes deleted data',
    () async {
      final store = LaunchpadTestStore();
      final oldUi = UiPreferences(shortcutIds: ['legacy-resource']).toJson();
      await store.writeDocument('ui', oldUi);
      await store.writeDocument('workspace', {
        'preserved': 'notes and findings',
      });
      await store.writeDocument('privacy', {'preserved': 'receipt'});
      final c = await controller(store);
      final token = await c.removeShortcut(c.snapshot.shortcuts.single.id);
      final folder = await c.createFolder('Personal folder');
      await c.addShortcut(resource('current', folder: folder));
      await c.setCollection(
        HomeCollectionPreference(
          kind: LaunchpadCollection.shopping,
          order: 0,
          sources: [
            const LaunchpadCollectionSource(
              title: 'A chosen website',
              target: LaunchpadTarget.website('https://example.org/'),
            ),
          ],
        ),
        retainInactiveWebsite: true,
      );
      await c.updatePreferences(
        showShortcuts: false,
        density: LaunchpadDensity.comfortable,
      );
      final before = c.snapshot.toJson();
      final started = store.hold(), gate = store.gate!;
      final clearing = c.clearSavedData();
      await started;
      expect(c.snapshot.toJson(), before);
      expect(await store.readDocument('launchpad'), before);
      final queuedUndo = expectLater(
        c.undo(token),
        throwsA(isA<LaunchpadException>()),
      );
      gate.complete();
      await clearing;
      await queuedUndo;
      final expected = LaunchpadSnapshot(
        setup: LaunchpadSetup.dismissed,
      ).toJson();
      expect(c.snapshot.toJson(), expected);
      expect(await store.readDocument('launchpad'), expected);
      expect(await store.readDocument('ui'), oldUi);
      expect(await store.readDocument('workspace'), {
        'preserved': 'notes and findings',
      });
      expect(await store.readDocument('privacy'), {'preserved': 'receipt'});
      final reopened = await controller(store);
      expect(reopened.snapshot.toJson(), expected);
      await expectLater(c.undo(token), throwsA(isA<LaunchpadException>()));
    },
  );
  test(
    'failed or canceled clear retains data and undo; private clear never touches owner storage',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store);
      final removed = await c.addShortcut(resource('removed'));
      final token = await c.removeShortcut(removed);
      await c.addShortcut(resource('kept'));
      final before = c.snapshot.toJson();
      store.failWrite = true;
      await expectLater(c.clearSavedData(), throwsA(isA<LaunchpadException>()));
      expect(c.snapshot.toJson(), before);
      expect(await store.readDocument('launchpad'), before);
      await expectLater(
        c.clearSavedData(canContinue: () => false),
        throwsA(isA<LaunchpadException>()),
      );
      await c.undo(token);
      expect(c.snapshot.shortcuts, hasLength(2));
      final owner = c.snapshot.toJson();
      store.reads.clear();
      store.writes.clear();
      final private = await controller(store, ephemeral: true);
      await private.addShortcut(resource('private'));
      await private.clearSavedData();
      expect(private.snapshot.shortcuts, isEmpty);
      expect(store.reads, isEmpty);
      expect(store.writes, isEmpty);
      expect(await store.readDocument('launchpad'), owner);
    },
  );
  test(
    'malformed legacy document preserved; migration makes no replacement and does not enable writes',
    () async {
      final store = LaunchpadTestStore();
      final original = {
        'version': 999,
        'private-looking-title': 'preserve bytes',
      };
      await store.writeDocument('ui', original);
      store.writes.clear();
      final c = await controller(store);
      expect(c.storageError, isNotNull);
      expect(store.writes, isEmpty);
      await expectLater(
        c.addShortcut(resource('moon-phases')),
        throwsA(isA<LaunchpadException>()),
      );
      expect(await store.readDocument('ui'), original);
      expect(await store.readDocument('launchpad'), isNull);
    },
  );
  test(
    'read error and failed first migration write retain old data; retry in a new session succeeds once',
    () async {
      final store = LaunchpadTestStore()..failRead = 'launchpad';
      final c = await controller(store);
      expect(c.storageError, isNotNull);
      expect(store.writes, isEmpty);
      store.failRead = null;
      await store.writeDocument(
        'ui',
        UiPreferences(shortcutIds: ['moon-phases']).toJson(),
      );
      store.failWrite = true;
      final failed = await controller(store);
      expect(failed.storageError, isNotNull);
      expect(await store.readDocument('launchpad'), isNull);
      final restored = await controller(store);
      expect(restored.snapshot.shortcuts.single.target.value, 'moon-phases');
      final again = await controller(store);
      expect(
        again.snapshot.shortcuts.single.id,
        restored.snapshot.shortcuts.single.id,
      );
    },
  );
  test(
    'malformed Launchpad and forged approval fields remain preserved and inaccessible',
    () async {
      final store = LaunchpadTestStore();
      final row = LaunchpadSnapshot().toJson()..['isApproved'] = true;
      await store.writeDocument('launchpad', row);
      store.writes.clear();
      final c = await controller(store);
      expect(c.storageError, isNotNull);
      await expectLater(c.resetConfirmed(), throwsA(isA<LaunchpadException>()));
      expect(await store.readDocument('launchpad'), row);
      expect(store.writes, isEmpty);
    },
  );
  test(
    'private service never reads or writes normal Launchpad, legacy preferences, sources or folder names',
    () async {
      final store = LaunchpadTestStore();
      await store.writeDocument('launchpad', {'owner': 'do not read'});
      store.reads.clear();
      store.writes.clear();
      final service = SignatureServices(
        store: store,
        eligible: (_) => true,
        isPrivate: true,
      );
      addTearDown(service.dispose);
      await service.initialize();
      await service.launchpad.createFolder('Private folder');
      await service.launchpad.addShortcut(resource('moon-phases'));
      await service.flush();
      expect(service.launchpad.snapshot.shortcuts, hasLength(1));
      expect(store.reads, isEmpty);
      expect(store.writes, isEmpty);
    },
  );
  test(
    'multi-select is atomic, skips identical destinations and rejects ineligible batch without partial success',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store, eligible: (id) => id != 'denied');
      final ids = await c.addSelected([
        resource('one'),
        resource('one'),
        resource('two'),
      ]);
      expect(ids, hasLength(2));
      final before = jsonEncode(c.snapshot.toJson());
      await expectLater(
        c.addSelected([resource('three'), resource('denied')]),
        throwsA(isA<LaunchpadException>()),
      );
      expect(jsonEncode(c.snapshot.toJson()), before);
      expect(await store.readDocument('launchpad'), c.snapshot.toJson());
    },
  );
  test(
    'website needs explicit inactive consent; names, categories and icons never confer approval',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store);
      await expectLater(
        c.addShortcut(website('espn.com')),
        throwsA(isA<LaunchpadException>()),
      );
      final id = await c.addShortcut(
        website('espn.com'),
        retainInactiveWebsite: true,
      );
      expect(c.snapshot.shortcuts.single.target.value, 'https://espn.com/');
      expect(
        c.eligibility.assess(c.snapshot.shortcuts.single.target).canOpen,
        isFalse,
      );
      await c.editShortcut(
        id,
        website('walmart.com', title: 'Approved Learning'),
        retainInactiveWebsite: true,
      );
      expect(
        c.eligibility.assess(c.snapshot.shortcuts.single.target).canOpen,
        isFalse,
      );
      expect(c.snapshot.toJson().containsKey('approval'), isFalse);
    },
  );
  test(
    'rename preserves provenance; normalized address change removes old catalog provenance',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store);
      final id = await c.addShortcut(
        website('espn.com', catalogId: 'espn'),
        retainInactiveWebsite: true,
      );
      await c.editShortcut(
        id,
        website('https://espn.com/', title: 'My sports'),
        retainInactiveWebsite: true,
      );
      expect(c.snapshot.shortcuts.single.catalogEntryId, 'espn');
      expect(c.snapshot.shortcuts.single.source, LaunchpadSource.catalog);
      await c.editShortcut(
        id,
        website('walmart.com'),
        retainInactiveWebsite: true,
      );
      expect(c.snapshot.shortcuts.single.catalogEntryId, isNull);
      expect(c.snapshot.shortcuts.single.source, LaunchpadSource.user);
    },
  );
  test(
    'duplicate detection respects meaningful URL path, query and fragment differences',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store);
      for (final url in [
        'example.org/a?q=1#one',
        'example.org/a?q=2#one',
        'example.org/a?q=1#two',
        'example.org/b?q=1#one',
      ]) {
        await c.addShortcut(website(url), retainInactiveWebsite: true);
      }
      expect(c.snapshot.shortcuts, hasLength(4));
      await expectLater(
        c.addShortcut(
          website('https://EXAMPLE.org./a?q=1#one'),
          retainInactiveWebsite: true,
        ),
        throwsA(isA<LaunchpadException>()),
      );
    },
  );
  test(
    'pending durable writes do not publish early; queued distinct prefs merge after failure recovery',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store);
      final started = store.hold();
      final gate = store.gate!;
      final first = c.updatePreferences(showShortcuts: false);
      await started;
      final second = c.updatePreferences(density: LaunchpadDensity.comfortable);
      expect(c.snapshot.showShortcuts, isTrue);
      expect(c.snapshot.density, LaunchpadDensity.compact);
      gate.complete();
      await Future.wait([first, second]);
      expect(c.snapshot.showShortcuts, isFalse);
      expect(c.snapshot.density, LaunchpadDensity.comfortable);
      store.failWrite = true;
      await expectLater(
        c.updatePreferences(showCollections: false),
        throwsA(isA<LaunchpadException>()),
      );
      expect(c.snapshot.showCollections, isTrue);
      expect(c.storageError, contains('previous layout'));
      await c.updatePreferences(showCollections: false);
      expect(c.storageError, isNull);
    },
  );
  test(
    'queued list inputs preserve the exact submitted selection and order',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store);
      final one = await c.addShortcut(resource('one'));
      final two = await c.addShortcut(resource('two'));
      final started = store.hold();
      final gate = store.gate!;
      final held = c.updatePreferences(showShortcuts: false);
      await started;
      final order = [two, one];
      final reorder = c.reorderRoot(order);
      order.clear();
      final drafts = [resource('three')];
      final add = c.addSelected(drafts);
      drafts.clear();
      gate.complete();
      await Future.wait([held, reorder, add]);
      expect(c.snapshot.rootItems.take(2).map((e) => e.id), [two, one]);
      expect(
        c.snapshot.shortcuts.any((e) => e.target.value == 'three'),
        isTrue,
      );
    },
  );
  test(
    'closed controller and changed origin invalidate queued mutations before storage',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store, managed: false);
      final started = store.hold();
      final gate = store.gate!;
      final first = c.addShortcut(resource('one'));
      await started;
      var current = true;
      final second = c.addShortcut(resource('two'), canContinue: () => current);
      final secondCheck = expectLater(
        second,
        throwsA(isA<LaunchpadException>()),
      );
      current = false;
      gate.complete();
      await first;
      await secondCheck;
      expect(c.snapshot.shortcuts, hasLength(1));
      final startedAgain = store.hold();
      final gateAgain = store.gate!;
      final pending = c.updatePreferences(showShortcuts: false);
      await startedAgain;
      final closed = c.createFolder('Must not save');
      final closedCheck = expectLater(
        closed,
        throwsA(isA<LaunchpadException>()),
      );
      c.dispose();
      gateAgain.complete();
      await pending;
      await closedCheck;
      expect((await store.readDocument('launchpad'))!['folders'], isEmpty);
    },
  );
  test(
    'folder move, reorder and nonempty delete are one valid durable snapshot across restart',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store);
      final one = await c.addShortcut(resource('one'));
      final two = await c.addShortcut(resource('two'));
      final folder = await c.createFolder('My folder');
      await c.renameFolder(folder, 'Renamed', localIconKey: 'initials:AB');
      await c.moveShortcut(one, folderId: folder, index: 0);
      await c.moveShortcut(two, folderId: folder, index: 0);
      await c.reorderFolder(folder, [one, two]);
      final reopened = await controller(store);
      expect(reopened.snapshot.folderItems(folder).map((e) => e.id), [
        one,
        two,
      ]);
      final token = await c.removeFolder(folder, removeContents: false);
      expect(c.snapshot.folders, isEmpty);
      expect(c.snapshot.rootItems.map((e) => e.id), [one, two]);
      await c.undo(token);
      expect(c.snapshot.folderItems(folder).map((e) => e.id), [one, two]);
      await c.removeFolder(folder, removeContents: true);
      expect(c.snapshot.shortcuts, isEmpty);
    },
  );
  test(
    'reordering exact siblings rejects stale lists, duplicate positions and orphaned persisted records',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store);
      final one = await c.addShortcut(resource('one'));
      final folder = await c.createFolder('Folder');
      final two = await c.addShortcut(resource('two'));
      await c.reorderRoot([two, folder, one]);
      final reopened = await controller(store);
      expect(reopened.snapshot.rootItems.map((e) => e.id), [two, folder, one]);
      await expectLater(
        c.reorderRoot([one, one, folder]),
        throwsA(isA<LaunchpadException>()),
      );
      final row =
          jsonDecode(jsonEncode(c.snapshot.toJson())) as Map<String, dynamic>;
      (row['shortcuts'] as List).first['folderId'] = 'missing-folder';
      expect(() => LaunchpadSnapshot.fromJson(row), throwsFormatException);
      final duplicate =
          jsonDecode(jsonEncode(c.snapshot.toJson())) as Map<String, dynamic>;
      (duplicate['shortcuts'] as List).first['order'] =
          (duplicate['shortcuts'] as List).last['order'];
      expect(
        () => LaunchpadSnapshot.fromJson(duplicate),
        throwsFormatException,
      );
    },
  );
  test(
    'undo preserves unrelated later writes, rechecks authority, cannot replay or cross sessions',
    () async {
      final store = LaunchpadTestStore();
      var allowed = true;
      final c = await controller(store, eligible: (_) => allowed);
      final id = await c.addShortcut(resource('one'));
      final token = await c.removeShortcut(id);
      await c.createFolder('Preserve this');
      allowed = false;
      await expectLater(c.undo(token), throwsA(isA<LaunchpadException>()));
      expect(c.snapshot.shortcuts, isEmpty);
      allowed = true;
      await c.undo(token);
      expect(c.snapshot.folders.single.title, 'Preserve this');
      await expectLater(c.undo(token), throwsA(isA<LaunchpadException>()));
      final another = await c.removeShortcut(id);
      final other = await controller(LaunchpadTestStore());
      await expectLater(
        other.undo(another),
        throwsA(isA<LaunchpadException>()),
      );
    },
  );
  test(
    'folder undo never overwrites edited children; concurrent token replay is rejected and failed undo is retryable',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store);
      final folder = await c.createFolder('Folder');
      final id = await c.addShortcut(resource('one', folder: folder));
      final token = await c.removeFolder(folder, removeContents: false);
      await c.editShortcut(id, resource('one', title: 'Edited'));
      await expectLater(c.undo(token), throwsA(isA<LaunchpadException>()));
      expect(c.snapshot.shortcuts.single.title, 'Edited');
      final deleted = await c.removeShortcut(id);
      store.failWrite = true;
      await expectLater(c.undo(deleted), throwsA(isA<LaunchpadException>()));
      final started = store.hold();
      final gate = store.gate!;
      final pending = c.undo(deleted);
      await started;
      await expectLater(c.undo(deleted), throwsA(isA<LaunchpadException>()));
      gate.complete();
      await pending;
      expect(c.snapshot.shortcuts.single.id, id);
    },
  );
  test(
    'collection sources are independent; queued source and visibility edits merge; reorder survives restoration',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store);
      final id = await c.addShortcut(resource('one'));
      await c.setCollection(
        HomeCollectionPreference(
          kind: LaunchpadCollection.learning,
          order: 0,
          sources: [
            const LaunchpadCollectionSource(
              title: 'One',
              target: LaunchpadTarget.resource('one'),
            ),
          ],
        ),
      );
      final started = store.hold();
      final gate = store.gate!;
      final hide = c.updateCollection(
        LaunchpadCollection.learning,
        (old) => HomeCollectionPreference(
          kind: old!.kind,
          order: old.order,
          visible: false,
          sources: old.sources,
        ),
      );
      await started;
      final add = c.updateCollection(
        LaunchpadCollection.learning,
        (old) => HomeCollectionPreference(
          kind: old!.kind,
          order: old.order,
          visible: old.visible,
          sources: [
            ...old.sources,
            const LaunchpadCollectionSource(
              title: 'Two',
              target: LaunchpadTarget.resource('two'),
            ),
          ],
        ),
      );
      gate.complete();
      await Future.wait([hide, add]);
      await c.removeShortcut(id);
      expect(c.snapshot.collections.single.sources, hasLength(2));
      expect(c.snapshot.collections.single.visible, isFalse);
      await c.setCollection(
        HomeCollectionPreference(kind: LaunchpadCollection.sports, order: 1),
      );
      await c.reorderCollections([
        LaunchpadCollection.sports,
        LaunchpadCollection.learning,
      ]);
      final reopened = await controller(store);
      expect(reopened.snapshot.collections.map((c) => c.kind), [
        LaunchpadCollection.sports,
        LaunchpadCollection.learning,
      ]);
    },
  );
  test(
    'limits include 64 shortcuts, 12 folders,24 sources and bounded icon/text schema',
    () async {
      final store = LaunchpadTestStore();
      final c = await controller(store);
      await c.addSelected(List.generate(64, (i) => resource('item-$i')));
      await expectLater(
        c.addShortcut(resource('overflow')),
        throwsA(isA<LaunchpadException>()),
      );
      for (var i = 0; i < 12; i++) {
        await c.createFolder('Folder $i');
      }
      await expectLater(
        c.createFolder('Overflow'),
        throwsA(isA<LaunchpadException>()),
      );
      await expectLater(
        c.setCollection(
          HomeCollectionPreference(
            kind: LaunchpadCollection.learning,
            order: 0,
            sources: List.generate(
              25,
              (i) => LaunchpadCollectionSource(
                title: 'Item',
                target: LaunchpadTarget.resource('item-$i'),
              ),
            ),
          ),
        ),
        throwsA(isA<LaunchpadException>()),
      );
      final smaller = await controller(LaunchpadTestStore());
      await expectLater(
        smaller.addShortcut(
          LaunchpadDraft(
            title: 'Bad',
            target: const LaunchpadTarget.resource('one'),
            localIconKey: 'https://favicon.example/',
          ),
        ),
        throwsFormatException,
      );
      await expectLater(
        smaller.addShortcut(resource('one', title: 'x' * 81)),
        throwsFormatException,
      );
      final maximumId = 'r' * 80;
      await smaller.addShortcut(
        LaunchpadDraft(
          title: 'Longest valid resource ID',
          target: LaunchpadTarget.resource(maximumId),
          source: LaunchpadSource.catalog,
          catalogEntryId: 'resource-$maximumId',
        ),
      );
      expect(
        smaller.snapshot.shortcuts.single.catalogEntryId,
        'resource-$maximumId',
      );
      expect(
        () => LaunchpadTarget.fromJson({
          'kind': 'tool',
          'value': 'explore',
          'isApproved': true,
        }),
        throwsFormatException,
      );
      expect(validLaunchpadIcon('initials:AB'), isTrue);
      expect(validLaunchpadIcon('initials:abc'), isFalse);
      LaunchpadSnapshot.fromJson(c.snapshot.toJson());
    },
  );
  test(
    'real signed policy, additional restrictions and invalidation change availability immediately without catalog grants',
    () async {
      final policy = await loadTestPolicy();
      addTearDown(policy.dispose);
      var additional = AdditionalRestrictions();
      final eligibility = LaunchpadEligibilityService(
        resourceEligible: (id) => policy.policy
            .evaluate(PolicyRequest.bundled(id), additional: additional)
            .isAllowed,
        resourceLookup: policy.resource,
        evaluateWebsite: (uri) => policy.policy.evaluate(
          PolicyRequest.navigation(uri),
          additional: additional,
        ),
      );
      final c = LaunchpadController(
        store: LaunchpadTestStore(),
        eligibility: eligibility,
      );
      addTearDown(c.dispose);
      await c.initialize();
      final id = await c.addShortcut(
        resource('moon-phases', title: 'Stored title'),
      );
      expect(
        eligibility.assess(c.snapshot.shortcuts.single.target).canOpen,
        isTrue,
      );
      additional = AdditionalRestrictions(blockedResourceIds: ['moon-phases']);
      expect(
        eligibility.presentedTitle(c.snapshot.shortcuts.single),
        'Unavailable resource',
      );
      final token = await c.removeShortcut(id);
      await expectLater(c.undo(token), throwsA(isA<LaunchpadException>()));
      for (final entry in LaunchpadCatalog.websites) {
        expect(
          eligibility.assess(entry.target).policyCode,
          PolicyDecisionCode.blockUnsupportedCapability,
        );
      }
      final catalog = LaunchpadCatalog(resources: policy.catalog);
      expect(
        catalog
            .search('sports')
            .any(
              (e) =>
                  e.target.kind == LaunchpadKind.resource &&
                  e.category == 'Sports',
            ),
        isTrue,
      );
      policy.repository.restrict('test-revoked');
      expect(
        eligibility
            .assess(const LaunchpadTarget.resource('moon-phases'))
            .canOpen,
        isFalse,
      );
      expect(LaunchpadCatalog.websites, hasLength(8));
      expect(LaunchpadCatalog.tools, hasLength(8));
    },
  );
}
