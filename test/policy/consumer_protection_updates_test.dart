import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wingman_browser/policy/consumer_protection_policy.dart';
import 'package:wingman_browser/policy/consumer_protection_repository.dart';
import 'package:wingman_browser/policy/policy_models.dart';
import '../support/protected_test_support.dart';

final now = DateTime.utc(2026, 9, 11, 12);
typedef Release = ({Uint8List envelope, Uint8List data});

class Signer {
  Signer(this.keyPair, this.publicKey);
  final SimpleKeyPair keyPair;
  final SimplePublicKey publicKey;
  ConsumerUpdateVerifier get verifier => ConsumerUpdateVerifier(
    trustedKeys: {'fixture-only': publicKey.bytes},
    clock: () => now,
  );
  Future<Release> release(
    int sequence, {
    Map<String, Object?> payload = const {},
    Map<String, Object?> dataFields = const {},
  }) async {
    final version = 'fixture-$sequence';
    final data = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'sequence': sequence,
          'version': version,
          'generatedAt': now.toIso8601String(),
          'categories': {
            for (final category in MandatoryCategory.values)
              category.id: ['${category.id}.update-fixture.test'],
          },
          'pathRules': [
            {
              'host': 'mixed.update-fixture.test',
              'pathPrefix': '/promotion',
              'category': 'gambling',
            },
          ],
          'trackers': ['tracker.update-fixture.test'],
          ...dataFields,
        }),
      ),
    );
    final digest = (await Sha256().hash(
      data,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final bytes = utf8.encode(
      jsonEncode({
        'purpose': ConsumerUpdateVerifier.purpose,
        'schemaVersion': 1,
        'sequence': sequence,
        'version': version,
        'generatedAt': now.toIso8601String(),
        'minimumAppVersion': '0.10.0',
        'filename': 'consumer-$sequence.json',
        'sha256': digest,
        'bytes': data.length,
        'license': 'Synthetic test fixture; no production signing key.',
        ...payload,
      }),
    );
    final signature = await Ed25519().sign(bytes, keyPair: keyPair);
    return (
      envelope: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'keyId': 'fixture-only',
            'payload': base64Encode(bytes),
            'signature': base64Encode(signature.bytes),
          }),
        ),
      ),
      data: data,
    );
  }
}

class Installer implements ConsumerPolicyInstaller {
  bool ready = true, acknowledges = true, canRevert = true;
  int prepares = 0, activations = 0, reverts = 0;
  final restored = <int>[];
  @override
  Future<PreparedConsumerPolicy?> prepare(
    VerifiedConsumerUpdate update, {
    bool restore = false,
  }) async {
    prepares++;
    if (restore) restored.add(update.manifest.sequence);
    return ready
        ? PreparedConsumerPolicy(
            'candidate-${update.manifest.sequence}',
            update.manifest.sequence,
            update.manifest.sha256,
          )
        : null;
  }

  @override
  Future<bool> activate(PreparedConsumerPolicy prepared) async {
    activations++;
    return acknowledges;
  }

  @override
  Future<void> discard(PreparedConsumerPolicy prepared) async {}
  @override
  Future<bool> revert(PreparedConsumerPolicy prepared) async {
    reverts++;
    return canRevert;
  }
}

class Source implements ConsumerUpdateSource {
  Source(this.release);
  Release release;
  bool offline = false;
  int calls = 0;
  @override
  Future<Uint8List> fetchManifest() async {
    calls++;
    if (offline) throw const SocketException('offline');
    return release.envelope;
  }

  @override
  Future<Uint8List> fetchData(ConsumerUpdateManifest manifest) async =>
      release.data;
}

class FailingStore extends MemoryConsumerUpdateStore {
  int writes = 0;
  int? failWrite;
  @override
  Future<void> write(ConsumerCacheState state) async {
    if (++writes == failWrite) throw StateError('injected disk failure');
    await super.write(state);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Signer signer;
  late ConsumerProtectionPolicy bundled;
  setUpAll(() async {
    final pair = await Ed25519().newKeyPair();
    signer = Signer(pair, await pair.extractPublicKey());
    bundled = await ConsumerProtectionPolicy.load(bundle: LocalCatalogBundle());
    expect(bundled.isUsable, true);
  });
  ConsumerProtectionRepository repository({
    ConsumerUpdateStore? store,
    Installer? installer,
    Source? source,
    ConsumerUpdateVerifier? verifier,
    DateTime Function()? clock,
  }) {
    final repo = ConsumerProtectionRepository(
      store: store ?? MemoryConsumerUpdateStore(),
      installer: installer ?? Installer(),
      verifier: verifier ?? signer.verifier,
      bundled: bundled,
      source: source,
      clock: clock ?? () => now,
    );
    addTearDown(repo.close);
    return repo;
  }

  test(
    'authenticated candidate activates only after native acknowledgement and durable commit',
    () async {
      final store = MemoryConsumerUpdateStore(), native = Installer();
      final repo = repository(store: store, installer: native);
      final signed = await signer.release(2);
      final result = await repo.importUpdate(signed.envelope, signed.data);
      expect(result.outcome, ConsumerUpdateOutcome.updated);
      expect(repo.policy.sequence, 2);
      expect(store.state.activeSequence, 2);
      expect(store.state.highestSequence, 2);
      expect(store.state.pendingSequence, isNull);
      expect(native.activations, 1);
      expect(
        repo.policy
            .assessNavigation(Uri.parse('https://gambling.update-fixture.test'))
            .isAllowed,
        false,
      );
      expect(
        repo.policy
            .assessNavigation(Uri.parse('https://ordinary.example'))
            .isAllowed,
        true,
      );
    },
  );

  test(
    'unsupported native preparation stages bytes without replacing bundled policy',
    () async {
      final store = MemoryConsumerUpdateStore(),
          native = Installer()..ready = false;
      final repo = repository(store: store, installer: native);
      final signed = await signer.release(2);
      expect(
        (await repo.importUpdate(signed.envelope, signed.data)).outcome,
        ConsumerUpdateOutcome.staged,
      );
      expect(repo.policy, same(bundled));
      expect(store.state.activeSequence, isNull);
      expect(store.state.pendingSequence, 2);
      expect(native.activations, 0);
      await repo.close();
      final recovered = repository(store: store, installer: Installer());
      await recovered.init();
      expect(recovered.policy.sequence, 2);
      expect(recovered.status.pendingSequence, isNull);
    },
  );

  test(
    'bad signature and untrusted key cannot stage or activate data',
    () async {
      final signed = await signer.release(2);
      final json =
          jsonDecode(utf8.decode(signed.envelope)) as Map<String, dynamic>;
      json['signature'] = base64Encode(List.filled(64, 0));
      final native = Installer();
      final repo = repository(installer: native);
      expect(
        (await repo.importUpdate(
          Uint8List.fromList(utf8.encode(jsonEncode(json))),
          signed.data,
        )).errorCode,
        'signature',
      );
      final untrusted = repository(
        installer: native,
        verifier: ConsumerUpdateVerifier(trustedKeys: {}, clock: () => now),
      );
      expect(
        (await untrusted.importUpdate(signed.envelope, signed.data)).errorCode,
        'unknown-key',
      );
      expect(native.prepares, 0);
      expect(untrusted.policy, same(bundled));
    },
  );

  for (final entry in <String, Map<String, Object?>>{
    'wrong signature purpose': {'purpose': 'optional-guard-v1'},
    'replayed bundled sequence': {'sequence': 1},
    'future release': {'generatedAt': '2099-01-01T00:00:00Z'},
    'unsupported app': {'minimumAppVersion': '99.0.0'},
    'filename traversal': {'filename': '../consumer-2.json'},
    'oversize data': {'bytes': 20000000},
  }.entries) {
    test('rejects ${entry.key} before native preparation', () async {
      final native = Installer();
      final repo = repository(installer: native);
      final signed = await signer.release(2, payload: entry.value);
      expect(
        (await repo.importUpdate(signed.envelope, signed.data)).outcome,
        ConsumerUpdateOutcome.rejected,
      );
      expect(native.prepares, 0);
      expect(repo.policy, same(bundled));
    });
  }

  for (final entry in <String, Map<String, Object?>>{
    'category removal': {
      'categories': {
        'gambling': ['gambling.fixture.test'],
      },
    },
    'empty mandatory category': {
      'categories': {
        for (final category in MandatoryCategory.values)
          category.id: <String>[],
      },
    },
    'content sequence mismatch': {'sequence': 3},
    'content version mismatch': {'version': 'other'},
    'content timestamp mismatch': {'generatedAt': '2026-09-10T12:00:00Z'},
    'invalid category path': {
      'pathRules': [
        {
          'host': 'mixed.fixture.test',
          'pathPrefix': '/promotion',
          'category': 'not-mandatory',
        },
      ],
    },
  }.entries) {
    test('signed ${entry.key} cannot create a usable baseline', () async {
      final native = Installer();
      final repo = repository(installer: native);
      final signed = await signer.release(2, dataFields: entry.value);
      expect(
        (await repo.importUpdate(signed.envelope, signed.data)).outcome,
        ConsumerUpdateOutcome.rejected,
      );
      expect(native.prepares, 0);
      expect(repo.policy, same(bundled));
    });
  }

  test('modified or truncated release bytes fail authentication', () async {
    final repo = repository(), signed = await signer.release(2);
    final data = Uint8List.fromList(signed.data)..[0] ^= 1;
    expect(
      (await repo.importUpdate(signed.envelope, data)).errorCode,
      'data-integrity',
    );
    expect(
      (await repo.importUpdate(
        signed.envelope,
        Uint8List.sublistView(data, 1),
      )).errorCode,
      'data-size',
    );
    expect(repo.policy, same(bundled));
  });

  test('verified bytes and envelope are immutable', () async {
    final signed = await signer.release(2);
    final release = await signer.verifier.verify(signed.envelope, signed.data);
    expect(() => release.data[0] = 0, throwsUnsupportedError);
    expect(() => release.manifest.envelope[0] = 0, throwsUnsupportedError);
  });

  test('replay cannot replace an active update', () async {
    final repo = repository(), signed = await signer.release(2);
    await repo.importUpdate(signed.envelope, signed.data);
    expect(
      (await repo.importUpdate(signed.envelope, signed.data)).errorCode,
      'replayed-sequence',
    );
    expect(repo.policy.sequence, 2);
  });

  test(
    'offline check retains validated local generation and staleness is separate',
    () async {
      var time = now;
      final signed = await signer.release(2),
          source = Source(await signer.release(3))..offline = true;
      final repo = repository(source: source, clock: () => time);
      await repo.importUpdate(signed.envelope, signed.data);
      time = time.add(const Duration(days: 2));
      expect(
        (await repo.checkForUpdates()).outcome,
        ConsumerUpdateOutcome.rejected,
      );
      expect(repo.policy.sequence, 2);
      expect(repo.status.stale, true);
      expect(
        (await repo.checkForUpdates()).outcome,
        ConsumerUpdateOutcome.throttled,
      );
      expect(source.calls, 1);
    },
  );

  test(
    'missing production trust or endpoint performs no update request',
    () async {
      final source = Source(await signer.release(2));
      final repo = repository(
        source: source,
        verifier: ConsumerUpdateVerifier(trustedKeys: {}),
      );
      expect(
        (await repo.checkForUpdates()).outcome,
        ConsumerUpdateOutcome.notConfigured,
      );
      expect(source.calls, 0);
      expect(repo.policy, same(bundled));
      expect(
        (await repository().checkForUpdates()).outcome,
        ConsumerUpdateOutcome.notConfigured,
      );
      final keyJson = jsonDecode(
        await File(ConsumerProtectionRepository.trustedKeyAsset).readAsString(),
      );
      expect(keyJson['keys'], isEmpty);
    },
  );

  test(
    'failed native activation retains old generation; uncertain revert needs recovery',
    () async {
      final signed = await signer.release(2),
          native = Installer()..acknowledges = false;
      final repo = repository(installer: native);
      expect(
        (await repo.importUpdate(signed.envelope, signed.data)).outcome,
        ConsumerUpdateOutcome.staged,
      );
      expect(repo.policy, same(bundled));
      expect(native.reverts, 1);
      final uncertain = repository(
        installer: Installer()
          ..acknowledges = false
          ..canRevert = false,
      );
      expect(
        (await uncertain.importUpdate(signed.envelope, signed.data)).outcome,
        ConsumerUpdateOutcome.recoveryRequired,
      );
      expect(uncertain.policy.isUsable, false);
    },
  );

  test(
    'durable activation commit failure reverts native and can recover pending on restart',
    () async {
      final store = FailingStore()..failWrite = 2, native = Installer();
      final repo = repository(store: store, installer: native),
          signed = await signer.release(2);
      expect(
        (await repo.importUpdate(signed.envelope, signed.data)).errorCode,
        'activation-commit-failed',
      );
      expect(repo.policy, same(bundled));
      expect(native.reverts, 1);
      expect(store.state.activeSequence, isNull);
      expect(store.state.pendingSequence, 2);
      await repo.close();
      store.failWrite = null;
      final recovered = repository(store: store);
      await recovered.init();
      expect(recovered.policy.sequence, 2);
    },
  );

  test(
    'SQLite corruption recovers previous signed generation and preserves replay high-water mark',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wingman-consumer-update-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final location = '${directory.path}/updates.db';
      SqliteConsumerUpdateStore store() => SqliteConsumerUpdateStore(
        factory: databaseFactoryFfi,
        databasePath: location,
      );
      final repo = repository(store: store());
      for (final sequence in [2, 3]) {
        final signed = await signer.release(sequence);
        await repo.importUpdate(signed.envelope, signed.data);
      }
      await repo.close();
      final db = await databaseFactoryFfi.openDatabase(location);
      await db.update('consumer_releases', {
        'data': Uint8List.fromList([0]),
      }, where: 'sequence=3');
      await db.close();
      final native = Installer();
      final recovered = repository(store: store(), installer: native);
      await recovered.init();
      expect(recovered.policy.sequence, 2);
      expect(recovered.status.highestSequence, 3);
      final older = await signer.release(2);
      expect(
        (await recovered.importUpdate(older.envelope, older.data)).errorCode,
        'replayed-sequence',
      );
      final newer = await signer.release(4);
      expect(
        (await recovered.importUpdate(newer.envelope, newer.data)).outcome,
        ConsumerUpdateOutcome.updated,
      );
      expect(native.restored, contains(2));
      expect(native.activations, 2);
      await recovered.close();
    },
  );

  test(
    'cached generation never silently falls back after failed native restore',
    () async {
      final store = MemoryConsumerUpdateStore();
      final initial = repository(store: store);
      final signed = await signer.release(2);
      await initial.importUpdate(signed.envelope, signed.data);
      await initial.close();
      final reopened = repository(
        store: store,
        installer: Installer()..ready = false,
      );
      await reopened.init();
      expect(reopened.policy.isUsable, false);
      expect(reopened.status.outcome, ConsumerUpdateOutcome.recoveryRequired);
    },
  );

  testWidgets(
    'native preparation timeout cannot activate an unacknowledged candidate',
    (tester) async {
      final signed = await signer.release(2);
      final release = await signer.verifier.verify(
        signed.envelope,
        signed.data,
      );
      const channel = MethodChannel('wingman/protected-browser');
      final pending = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) => pending.future);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final prepared = const NativeConsumerPolicyInstaller().prepare(release);
      await tester.pump(NativeConsumerPolicyInstaller.preparationTimeout);
      expect(await prepared, isNull);
      pending.complete(null);
      await tester.pump();
    },
  );

  testWidgets('native activation acknowledgement has a bounded timeout', (
    tester,
  ) async {
    const channel = MethodChannel('wingman/protected-browser');
    final pending = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => pending.future);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final activation = expectLater(
      const NativeConsumerPolicyInstaller().activate(
        const PreparedConsumerPolicy('token', 2, 'digest'),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(NativeConsumerPolicyInstaller.commandTimeout);
    await activation;
    pending.complete(null);
    await tester.pump();
  });

  test(
    'HTTPS update transport rejects credentials, query, fragment and non-HTTPS roots',
    () {
      for (final uri in [
        'http://updates.example/manifest.json',
        'https://user@updates.example/manifest.json',
        'https://updates.example/manifest.json?url=private',
        'https://updates.example/manifest.json#x',
        'https://updates.example/other',
      ]) {
        expect(
          () => HttpsConsumerUpdateSource(manifestUri: Uri.parse(uri)),
          throwsArgumentError,
        );
      }
      expect(
        HttpsConsumerUpdateSource(
          manifestUri: Uri.parse(
            'https://updates.example/releases/manifest.json',
          ),
        ).manifestUri.scheme,
        'https',
      );
    },
  );
}
