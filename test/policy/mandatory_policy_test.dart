import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'policy_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PolicyFixture fixture;
  setUp(() async => fixture = await PolicyFixture.create());
  Future<PolicyRuntime> runtime(
    PolicyFixtureBundle bundle, {
    PolicyCheckpointStore? store,
    DateTime Function()? clock,
  }) async {
    final repo = SignedPolicyRepository(
      bundle: bundle,
      verifier: await fixture.verifier(),
      clock: PolicyClock(wallClock: clock ?? () => policyTestTime),
    );
    final value = await PolicyRuntime.initialize(
      repository: repo,
      checkpointStore: store ?? MemoryPolicyCheckpointStore(),
    );
    addTearDown(value.dispose);
    return value;
  }

  test(
    'shipped catalog is signed useful original content, with local search and contexts',
    () async {
      final app = await PolicyRuntime.initialize(
        checkpointStore: MemoryPolicyCheckpointStore(),
        clock: () => policyTestTime,
      );
      addTearDown(app.dispose);
      expect(app.status.usable, true, reason: app.status.errorCode);
      expect(app.catalog, hasLength(14));
      for (final record in app.catalog) {
        expect(record.body.length, greaterThan(120));
        expect(record.contexts, containsAll(ContentContext.values));
        expect(
          app.policy.evaluate(PolicyRequest.bundled(record.id)).isAllowed,
          true,
        );
        expect(
          app.policy
              .evaluate(
                PolicyRequest.bundled(
                  record.id,
                  context: ContentContext.student,
                  isPrivate: true,
                ),
              )
              .isAllowed,
          true,
        );
      }
      expect(app.search(''), hasLength(14));
      expect(app.search('https://unknown.test'), isEmpty);
      expect(MandatorySafetyPolicy.categories, hasLength(6));
    },
  );
  test(
    'all live/rendering operations and forged ID+URL combinations fail closed',
    () async {
      final app = await runtime(await fixture.bundle());
      for (final operation in PolicyOperation.values) {
        if (operation == PolicyOperation.renderBundled) continue;
        for (final private in [false, true]) {
          expect(
            app.policy
                .evaluate(
                  PolicyRequest(
                    operation: operation,
                    resourceId: 'seed-science',
                    uri: Uri.parse('https://approved-looking.test'),
                    isPrivate: private,
                  ),
                )
                .code,
            PolicyDecisionCode.blockUnsupportedCapability,
          );
        }
      }
      expect(
        app.policy
            .evaluate(
              PolicyRequest(
                operation: PolicyOperation.renderBundled,
                resourceId: 'seed-science',
                uri: Uri.parse('data:text/html,unsafe'),
              ),
            )
            .isAllowed,
        false,
      );
      expect(
        app.policy.evaluate(const PolicyRequest.bundled('unknown')).code,
        PolicyDecisionCode.blockUnreviewed,
      );
    },
  );
  test(
    'additional restrictions subtract only and removal never approves unknown content',
    () async {
      final app = await runtime(await fixture.bundle());
      final restrictions = AdditionalRestrictions(
        blockedCollections: ['science'],
      );
      expect(
        app.policy
            .evaluate(
              const PolicyRequest.bundled('seed-science'),
              additional: restrictions,
            )
            .code,
        PolicyDecisionCode.blockAdditionalRestriction,
      );
      expect(
        app.policy
            .evaluate(
              const PolicyRequest.bundled('unknown'),
              additional: AdditionalRestrictions(),
            )
            .code,
        PolicyDecisionCode.blockUnreviewed,
      );
      final imported = AdditionalRestrictions.fromJson({
        'guardEnabled': false,
        'customAllow': ['seed-science'],
        'adminOverride': true,
        'allowUnknown': true,
      });
      expect(
        app.policy
            .evaluate(
              const PolicyRequest.bundled('unknown'),
              additional: imported,
            )
            .isAllowed,
        false,
      );
    },
  );
  test(
    'expired catalog cannot be revived by backward clock and checkpoint survives restart',
    () async {
      var now = policyTestTime;
      final store = MemoryPolicyCheckpointStore();
      final app = await runtime(
        await fixture.bundle(),
        store: store,
        clock: () => now,
      );
      now = DateTime.utc(2027, 4);
      expect(
        app.policy.evaluate(const PolicyRequest.bundled('seed-science')).code,
        PolicyDecisionCode.blockPolicyUnavailable,
      );
      await app.flushCheckpoint();
      now = policyTestTime;
      expect(app.status.usable, false);
      final reopened = await runtime(
        await fixture.bundle(),
        store: store,
        clock: () => now,
      );
      expect(reopened.status.usable, false);
      expect(store.value.seenAt!.year, 2027);
    },
  );
  test(
    'corrupt archive/body, unsigned keys, unsupported scope and old policy are rejected',
    () async {
      final invalids = <PolicyFixtureBundle>[];
      // Same key identifier, independently generated untrusted signing key.
      invalids.add(await (await PolicyFixture.create()).bundle());
      final badSignature = await fixture.bundle();
      final envelope =
          jsonDecode(
                utf8.decode(badSignature.files['assets/policy/manifest.json']!),
              )
              as Map<String, dynamic>;
      envelope['signature'] = base64Encode(List<int>.filled(64, 0));
      badSignature.files['assets/policy/manifest.json'] = Uint8List.fromList(
        utf8.encode(jsonEncode(envelope)),
      );
      invalids.add(badSignature);
      final brokenBody = await fixture.bundle();
      brokenBody.files['assets/policy/articles/seed-science.txt'] =
          Uint8List.fromList([1, 2, 3]);
      invalids.add(brokenBody);
      final brokenCatalog = await fixture.bundle();
      brokenCatalog.files['assets/policy/catalog.json'] = Uint8List.fromList(
        utf8.encode('{}'),
      );
      invalids.add(brokenCatalog);
      invalids.add(
        await fixture.bundle(
          recordOverrides: {
            'capability': 'liveWeb',
            'url': 'https://education.example.test',
          },
        ),
      );
      invalids.add(
        await fixture.bundle(
          recordOverrides: {
            'assetPath': 'assets/policy/articles/../unreviewed.txt',
          },
        ),
      );
      invalids.add(
        await fixture.bundle(catalogOverrides: {'policyVersion': 0}),
      );
      for (final bundle in invalids) {
        final app = await runtime(bundle);
        expect(app.status.usable, false);
        expect(app.catalog, isEmpty);
        expect(
          app.policy
              .evaluate(const PolicyRequest.bundled('seed-science'))
              .isAllowed,
          false,
        );
      }
    },
  );
  test('sliced asset buffers verify exact selected bytes', () async {
    final bundle = await fixture.bundle()
      ..sliced = true;
    final app = await runtime(bundle);
    expect(app.status.usable, true, reason: app.status.errorCode);
  });
  test(
    'concurrent signed activations serialize and durable revocation cannot roll back',
    () async {
      final bundle = await fixture.bundle();
      final store = MemoryPolicyCheckpointStore();
      final app = await runtime(bundle, store: store);
      final second = await fixture.bundle(sequence: 2);
      final third = await fixture.bundle(
        sequence: 3,
        revoked: ['seed-science'],
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      bundle.beforeRead = (path) async {
        if (path.endsWith('.txt') && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final two = app.repository.activate(
        second.files['assets/policy/manifest.json']!,
        second.files['assets/policy/catalog.json']!,
      );
      await entered.future;
      var thirdDone = false;
      final three = app.repository
          .activate(
            third.files['assets/policy/manifest.json']!,
            third.files['assets/policy/catalog.json']!,
          )
          .then((_) => thirdDone = true);
      await Future<void>.delayed(Duration.zero);
      expect(thirdDone, false);
      release.complete();
      await two;
      await three;
      expect(app.status.sequence, 3);
      expect(store.value.minimumSequence, 3);
      expect(store.value.revokedIds, contains('seed-science'));
      expect(app.catalog, isEmpty);
      await expectLater(
        app.repository.activate(
          second.files['assets/policy/manifest.json']!,
          second.files['assets/policy/catalog.json']!,
        ),
        throwsA(isA<PolicyValidationException>()),
      );
      expect(app.status.sequence, 3);
      expect(app.catalog, isEmpty);
    },
  );
  testWidgets(
    'a pending earlier checkpoint cannot postpone later article expiry',
    (tester) async {
      var now = policyTestTime;
      final signer = await PolicyFixture.create();
      final bundle = await signer.bundle(
        recordOverrides: {
          'expiresAt': now.add(const Duration(minutes: 2)).toIso8601String(),
        },
      );
      final store = _DelayedCheckpoint();
      final app = await PolicyRuntime.initialize(
        repository: SignedPolicyRepository(
          bundle: bundle,
          verifier: await signer.verifier(),
          clock: PolicyClock(wallClock: () => now),
        ),
        checkpointStore: store,
      );
      var expiryObserved = false;
      app.addListener(() {
        if (app.resource('seed-science') == null) expiryObserved = true;
      });
      store.gate = Completer<void>();
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(expiryObserved, false);
      expect(store.gate!.isCompleted, false);
      now = now.add(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 2));
      expect(expiryObserved, true);
      expect(app.resource('seed-science'), isNull);
      expect(store.gate!.isCompleted, false);
      store.gate!.complete();
      await tester.pump();
      app.dispose();
    },
  );

  testWidgets(
    'individual approval expiry notifies before a delayed checkpoint save',
    (tester) async {
      var now = policyTestTime;
      final signer = await PolicyFixture.create();
      final bundle = await signer.bundle(
        recordOverrides: {
          'expiresAt': now.add(const Duration(seconds: 3)).toIso8601String(),
        },
      );
      final store = _DelayedCheckpoint();
      final repo = SignedPolicyRepository(
        bundle: bundle,
        verifier: await signer.verifier(),
        clock: PolicyClock(wallClock: () => now),
      );
      final app = await PolicyRuntime.initialize(
        repository: repo,
        checkpointStore: store,
      );
      var expiryObserved = false;
      app.addListener(() {
        if (app.resource('seed-science') == null) expiryObserved = true;
      });
      store.gate = Completer<void>();
      now = now.add(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 4));
      expect(expiryObserved, true);
      expect(app.resource('seed-science'), isNull);
      expect(store.gate!.isCompleted, false);
      store.gate!.complete();
      await tester.pump();
      app.dispose();
    },
  );

  test(
    'failure reading or writing checkpoint exposes no approved resources',
    () async {
      for (final failLoad in [true, false]) {
        final app = await runtime(
          await fixture.bundle(),
          store: _BrokenCheckpoint(failLoad),
        );
        expect(app.status.usable, false);
        expect(app.catalog, isEmpty);
      }
    },
  );
}

class _BrokenCheckpoint implements PolicyCheckpointStore {
  _BrokenCheckpoint(this.failLoad);
  final bool failLoad;
  @override
  Future<PolicyCheckpoint> load() async {
    if (failLoad) throw StateError('unreadable');
    return PolicyCheckpoint();
  }

  @override
  Future<void> save(PolicyCheckpoint checkpoint) async =>
      throw StateError('write failed');
  @override
  Future<void> close() async {}
}

class _DelayedCheckpoint extends MemoryPolicyCheckpointStore {
  Completer<void>? gate;
  @override
  Future<void> save(PolicyCheckpoint checkpoint) async {
    await gate?.future;
    await super.save(checkpoint);
  }
}
