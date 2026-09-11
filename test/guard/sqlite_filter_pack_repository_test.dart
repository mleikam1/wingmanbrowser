import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wingman_browser/guard/guard_runtime.dart';
import 'guard_test_support.dart';

class FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

class UpdateSource implements FilterPackUpdateSource {
  UpdateSource(this.manifest, this.pack);
  Uint8List manifest, pack;
  int calls = 0;
  bool fail = false;
  @override
  Future<Uint8List> fetchManifest() async {
    calls++;
    if (fail) throw const SocketException('offline');
    return manifest;
  }

  @override
  Future<Uint8List> fetchPack(String filename, int maximumBytes) async => pack;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late TestSigner signer;
  late SqliteFilterPackRepository repo;
  String getPath() => '${directory.path}/guard.db';
  SqliteFilterPackRepository create({
    FilterPackUpdateSource? source,
    DateTime Function()? clock,
  }) => SqliteFilterPackRepository(
    factory: databaseFactoryFfi,
    databasePath: getPath(),
    verifier: signer.verifier,
    installBundled: false,
    clock: clock ?? () => testTime,
    updateSource: source,
  );
  Future<void> install(int sequence, {String host = 'adult.test'}) async {
    final signed = await signer.sign([testRule(host)], sequence: sequence);
    await repo.importVerified(signed.manifest, signed.pack);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wingman-guard-test-');
    signer = await TestSigner.create();
    repo = create();
    await repo.init();
  });
  tearDown(() async {
    await repo.close();
    await directory.delete(recursive: true);
  });
  test(
    'bundled pack authenticates and installs offline with public key only',
    () async {
      await repo.close();
      repo = SqliteFilterPackRepository(
        factory: databaseFactoryFfi,
        databasePath: getPath(),
        bundle: FileBundle(),
        clock: () => testTime,
      );
      await repo.init();
      expect(repo.status.integrityVerified, true);
      expect(repo.status.ruleCount, 49);
      expect(
        (await repo.lookupHost('sub.adult.guard.test')).single.category,
        GuardCategory.adult,
      );
      expect(
        (await repo.checkForUpdates()).outcome,
        FilterUpdateOutcome.notConfigured,
      );
    },
  );
  test(
    'persistent suffix index preserves exact-only rules, reopen and version',
    () async {
      final signed = await signer.sign([
        testRule('adult.test'),
        testRule('exact.test', includeSubdomains: false),
      ]);
      await repo.importVerified(signed.manifest, signed.pack);
      expect(
        (await repo.lookupHost('sub.adult.test')).single.host,
        'adult.test',
      );
      expect(await repo.lookupHost('notadult.test'), isEmpty);
      expect(await repo.lookupHost('sub.exact.test'), isEmpty);
      expect(await repo.lookupHost('exact.test'), hasLength(1));
      await repo.close();
      repo = create();
      await repo.init();
      expect(repo.status.version, '1.0.1');
      expect(repo.status.integrityVerified, true);
      expect(repo.activeDatabasePath, getPath());
    },
  );
  test(
    'bounded normal LRU never stores private lookup or browsing URL',
    () async {
      await install(1);
      for (var i = 0; i < 550; i++) {
        await repo.lookupHost('host-$i.test');
      }
      expect(repo.cachedHostCount, 512);
      repo.clearCache();
      await repo.lookupHost('private.adult.test', useCache: false);
      expect(repo.cachedHostCount, 0);
      final db = await databaseFactoryFfi.openDatabase(getPath());
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      expect(
        tables.map((r) => r['name']),
        containsAll(['guard_state', 'guard_releases', 'guard_rules']),
      );
      expect(tables.any((r) => r['name'] == 'history'), false);
    },
  );
  test(
    'bad signature, checksum and incomplete records leave last good active',
    () async {
      await install(1);
      final signed = await signer.sign([testRule('new.test')], sequence: 2);
      final invalid = Uint8List.fromList(signed.pack)..[10] ^= 1;
      await expectLater(
        repo.importVerified(signed.manifest, invalid),
        throwsA(isA<FilterPackValidationException>()),
      );
      final envelope =
          jsonDecode(utf8.decode(signed.manifest)) as Map<String, dynamic>;
      final sig = base64Decode(envelope['signature'] as String)..[0] ^= 1;
      envelope['signature'] = base64Encode(sig);
      await expectLater(
        repo.importVerified(
          Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
          signed.pack,
        ),
        throwsA(isA<FilterPackValidationException>()),
      );
      final badCount = await signer.sign(
        [testRule('new.test')],
        sequence: 2,
        packMetadata: {'rules': 2},
      );
      await expectLater(
        repo.importVerified(badCount.manifest, badCount.pack),
        throwsA(isA<FilterPackValidationException>()),
      );
      expect(repo.status.generation, 1);
      expect(await repo.lookupHost('adult.test'), hasLength(1));
      final db = await databaseFactoryFfi.openDatabase(getPath());
      expect(
        (await db.rawQuery(
          'SELECT count(*) FROM guard_releases',
        )).single.values.single,
        1,
      );
    },
  );
  test(
    'strict row policy and signed index digest reject damaged imports',
    () async {
      await install(1);
      for (final records in [
        [testRule('example.test', kind: 'malware', category: 'adult')],
        [testRule('com')],
        [testRule('127.0.0.1')],
        [testRule('duplicate.test'), testRule('duplicate.test')],
      ]) {
        final signed = await signer.sign(records, sequence: 2);
        await expectLater(
          repo.importVerified(signed.manifest, signed.pack),
          throwsA(anything),
        );
        expect(repo.status.generation, 1);
      }
      final signed = await signer.sign(
        [testRule('valid.test')],
        sequence: 2,
        packMetadata: {'rulesSha256': '0' * 64},
      );
      await expectLater(
        repo.importVerified(signed.manifest, signed.pack),
        throwsA(isA<FilterPackValidationException>()),
      );
    },
  );
  test(
    'explicit rollback retains anti-replay high-water mark across reopen',
    () async {
      await install(1);
      await install(2, host: 'new.test');
      expect(await repo.rollback(), true);
      expect(repo.status.generation, 1);
      await expectLater(
        install(2),
        throwsA(isA<FilterPackValidationException>()),
      );
      await repo.close();
      repo = create();
      await repo.init();
      expect(repo.status.generation, 1);
      await expectLater(
        install(1),
        throwsA(isA<FilterPackValidationException>()),
      );
      await install(3, host: 'latest.test');
      expect(repo.status.generation, 3);
    },
  );
  test(
    'tampered indexed rules recover previous signed release without erasing evidence',
    () async {
      await install(1);
      await install(2, host: 'new.test');
      await repo.close();
      final db = await databaseFactoryFfi.openDatabase(getPath());
      await db.update('guard_rules', {
        'category': 'news',
      }, where: 'generation=2');
      await db.close();
      repo = create();
      await repo.init();
      expect(repo.status.generation, 1);
      expect(repo.status.integrityVerified, true);
      expect(await repo.lookupHost('new.test'), isEmpty);
      final inspect = await databaseFactoryFfi.openDatabase(getPath());
      expect(
        (await inspect.query(
          'guard_rules',
          where: 'generation=2',
        )).single['category'],
        'news',
      );
    },
  );
  test(
    'tampering without last good degrades without deleting evidence or stopping browser',
    () async {
      await install(1);
      await repo.close();
      final db = await databaseFactoryFfi.openDatabase(getPath());
      await db.delete('guard_rules');
      await db.close();
      repo = create();
      final runtime = await GuardRuntime.initialize(repository: repo);
      expect(runtime.repository.status.integrityVerified, false);
      expect(repo.status.errorCode, 'index-integrity');
      expect(repo.activeDatabasePath, isNull);
      expect(repo.lookupHost('adult.test'), throwsStateError);
      final decision = await runtime.policy.evaluate(
        GuardRequest(uri: Uri.parse('https://example.test'), tabId: 'one'),
        GuardConfiguration(),
      );
      expect(decision.action, GuardAction.blockPolicyUnavailable);
      final inspect = await databaseFactoryFfi.openDatabase(getPath());
      expect(await inspect.query('guard_releases'), hasLength(1));
    },
  );
  test(
    'corrupt SQLite file is preserved and app runtime still opens',
    () async {
      await repo.close();
      final file = File(getPath());
      await file.writeAsString('corrupt forensic evidence');
      repo = create();
      await GuardRuntime.initialize(repository: repo);
      expect(repo.status.integrityVerified, false);
      expect(repo.status.errorCode, 'storage-unavailable');
      expect(await file.readAsString(), 'corrupt forensic evidence');
    },
  );
  test(
    'global update cadence is persisted and network failure keeps offline rules',
    () async {
      await install(1);
      final next = await signer.sign([testRule('new.test')], sequence: 2);
      final source = UpdateSource(next.manifest, next.pack)..fail = true;
      await repo.close();
      repo = create(source: source);
      await repo.init();
      expect(
        (await repo.checkForUpdates()).outcome,
        FilterUpdateOutcome.rejected,
      );
      expect(repo.status.generation, 1);
      expect(
        (await repo.checkForUpdates()).outcome,
        FilterUpdateOutcome.throttled,
      );
      expect(source.calls, 1);
      source.fail = false;
      expect(
        (await repo.checkForUpdates(force: true)).outcome,
        FilterUpdateOutcome.updated,
      );
      expect(repo.status.generation, 2);
      await repo.close();
      repo = create(source: source);
      await repo.init();
      expect(
        (await repo.checkForUpdates()).outcome,
        FilterUpdateOutcome.throttled,
      );
      expect(
        (await repo.checkForUpdates(force: true)).outcome,
        FilterUpdateOutcome.current,
      );
    },
  );
}
