import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/guard_pin/pin_derivation.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/signature/handoff/handoff_gate.dart';

import '../support/protected_test_support.dart';

class HandoffMemoryStore implements HandoffStore {
  @override
  bool supported = true;
  String? value;
  bool failRead = false, ignoreWrites = false;
  Completer<void>? beforeWrite;
  Completer<void>? beforeInactiveWrite;
  bool inactiveWriteEntered = false;
  int writes = 0;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('PRIVATE_STORAGE_ERROR');
    return value;
  }

  @override
  Future<void> write(String record) async {
    ++writes;
    await beforeWrite?.future;
    if (record == '{"schema":1,"active":false}' &&
        beforeInactiveWrite != null) {
      inactiveWriteEntered = true;
      await beforeInactiveWrite!.future;
    }
    if (!ignoreWrites) value = record;
  }
}

class HandoffFastDerivation implements PinDerivation {
  Completer<void>? waiting;
  bool entered = false;
  @override
  Future<List<int>> derive(String pin, List<int> salt) async {
    entered = true;
    await waiting?.future;
    return (await Sha256().hash([...salt, ...utf8.encode(pin)])).bytes;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PolicyRuntime policy;
  late HandoffMemoryStore store;
  late HandoffFastDerivation derivation;
  late HandoffController controller;
  var time = DateTime.utc(2026, 9, 11, 12);

  HandoffController make({
    Duration? timeout,
    Future<void> Function()? discard,
  }) {
    final value = HandoffController(
      store: store,
      discardIncoming: discard ?? () async {},
      derivation: derivation,
      clock: () => time,
      persistenceTimeout: timeout ?? const Duration(seconds: 10),
      capabilities: () async =>
          const HandoffCapabilities(staticSupported: true),
    );
    value.attachPolicy(policy);
    addTearDown(value.dispose);
    return value;
  }

  setUp(() async {
    time = DateTime.utc(2026, 9, 11, 12);
    policy = await loadTestPolicy(clock: () => time);
    store = HandoffMemoryStore();
    derivation = HandoffFastDerivation();
    controller = make();
    await controller.initialize();
  });
  tearDown(() => policy.dispose());

  Future<HandoffAttempt> activate({HandoffController? using}) async {
    final value = using ?? controller;
    return value.activate(
      preview: value.preview(['moon-phases'])!,
      code: '83197246',
      confirmation: '83197246',
    );
  }

  test(
    'Android secure gate disables destructive reset and uses an isolated namespace',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      Map<dynamic, dynamic>? options;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            options = (call.arguments as Map)['options'] as Map;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await PlatformHandoffStore.forTesting().read();
      expect(options?['resetOnError'], 'false');
      expect(options?['storageNamespace'], 'wingman.handoff.v1');
    },
  );

  test(
    'guest links are discarded on activation, restoration and authorized return',
    () async {
      var discarded = 0;
      final first = make(
        discard: () async {
          discarded++;
        },
      );
      await first.initialize();
      expect(
        discarded,
        0,
        reason: 'Fresh owner startup keeps ordinary rejection handling',
      );
      expect((await activate(using: first)).success, isTrue);
      expect(discarded, 1);
      final restored = make(
        discard: () async {
          discarded++;
        },
      );
      await restored.initialize();
      expect(discarded, 2);
      expect(restored.blocksOwner, isTrue);
      expect((await restored.unlock('99999999')).success, isFalse);
      expect(discarded, 2, reason: 'Wrong code cannot resume owner handling');
      expect((await restored.unlock('83197246')).success, isTrue);
      expect(discarded, 3);
    },
  );

  test(
    'failed native discard cannot activate or release a restored gate',
    () async {
      final failing = make(
        discard: () async {
          throw StateError('unavailable');
        },
      );
      await failing.initialize();
      expect(
        (await activate(using: failing)).result,
        HandoffResult.unavailable,
      );
      expect(failing.blocksOwner, isTrue);
      expect(failing.visibleResources, isEmpty);
      expect(
        store.value,
        isNull,
        reason: 'No guest was displayed or marker committed',
      );
      expect((await activate()).success, isTrue);
      final activeRecord = store.value;
      final restored = make(
        discard: () async {
          throw StateError('unavailable');
        },
      );
      await restored.initialize();
      expect(restored.blocksOwner, isTrue);
      expect(restored.visibleResources, isEmpty);
      expect((await restored.unlock('83197246')).success, isFalse);
      expect(store.value, activeRecord);
    },
  );

  test(
    'interruption during preauthorization link disposal never commits owner return',
    () async {
      final waiting = Completer<void>();
      var calls = 0;
      final guarded = make(
        discard: () async {
          calls++;
          if (calls == 2) await waiting.future;
        },
      );
      await guarded.initialize();
      expect((await activate(using: guarded)).success, isTrue);
      final returning = guarded.unlock('83197246');
      while (calls < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      guarded.interrupt();
      waiting.complete();
      expect((await returning).result, HandoffResult.canceled);
      expect(guarded.returnAuthorized, isFalse);
      expect(guarded.blocksOwner, isTrue);
      expect(jsonDecode(store.value!)['active'], isTrue);
    },
  );

  test('fresh code is8–12ASCII digits and must be confirmed', () async {
    for (final code in [
      '',
      '1234567',
      '1234567890123',
      '１２３４５６７８',
      '12345678\n',
    ]) {
      final result = await controller.activate(
        preview: controller.preview(['moon-phases'])!,
        code: code,
        confirmation: code,
      );
      expect(result.result, HandoffResult.invalidCode);
    }
    expect(
      (await controller.activate(
        preview: controller.preview(['moon-phases'])!,
        code: '83197246',
        confirmation: '83197245',
      )).result,
      HandoffResult.confirmationMismatch,
    );
    expect(store.writes, 0);
    expect(controller.blocksOwner, isFalse);
  });

  test('only policy-minted bounded exact reviewed IDs can be shared', () async {
    expect(controller.preview(['https://example.test']), isNull);
    expect(controller.preview(['unknown']), isNull);
    expect(controller.preview([]), isNull);
    expect(controller.preview(List.filled(9, 'moon-phases')), isNull);
    expect(controller.preview(['moon-phases', 'moon-phases']), isNull);
    expect(
      controller.preview(
        ['moon-phases'],
        additional: AdditionalRestrictions(blockedResourceIds: ['moon-phases']),
      ),
      isNull,
    );
    final other = make();
    await other.initialize();
    expect(
      (await other.activate(
        preview: controller.preview(['moon-phases'])!,
        code: '83197246',
        confirmation: '83197246',
      )).result,
      HandoffResult.unavailable,
    );
    expect(
      policy.policy
          .evaluate(PolicyRequest.navigation(Uri.parse('https://example.test')))
          .isAllowed,
      isFalse,
    );
  });

  test(
    'active envelope pins exact hash and salted verifier without content/code',
    () async {
      expect((await activate()).success, isTrue);
      final record = jsonDecode(store.value!) as Map;
      expect(record['active'], true);
      expect(record['iterations'], 600000);
      expect(record['resources'], [
        {'id': 'moon-phases', 'sha256': policy.resource('moon-phases')!.sha256},
      ]);
      expect(base64Decode(record['salt'] as String), hasLength(32));
      expect(base64Decode(record['verifier'] as String), hasLength(32));
      expect(store.value, isNot(contains('83197246')));
      expect(
        store.value,
        isNot(contains(policy.resource('moon-phases')!.body)),
      );
      expect(controller.blocksOwner, isTrue);
      expect(controller.visibleResources.single.id, 'moon-phases');
    },
  );

  test(
    'process replacement stays gated until authenticated durable exit',
    () async {
      await activate();
      final restarted = make();
      expect(restarted.blocksOwner, isTrue);
      await restarted.initialize();
      expect(restarted.status, HandoffStatus.active);
      expect((await restarted.unlock('00000000')).success, isFalse);
      expect(restarted.blocksOwner, isTrue);
      expect((await restarted.unlock('83197246')).success, isTrue);
      expect(restarted.blocksOwner, isFalse);
      expect(jsonDecode(store.value!), {'schema': 1, 'active': false});
      expect(restarted.visibleResources, isEmpty);
      final again = make();
      await again.initialize();
      expect(again.status, HandoffStatus.owner);
    },
  );

  test(
    'corrupt oversized unknown and locked storage never unlock owner',
    () async {
      for (final value in [
        '{bad}',
        'x' * 8193,
        '{"schema":2,"active":false}',
        '{"schema":1,"active":false,"unexpected":true}',
        '{"schema":1,"active":true}',
      ]) {
        store.value = value;
        final valueController = make();
        await valueController.initialize();
        expect(valueController.status, HandoffStatus.unavailable);
        expect(valueController.blocksOwner, isTrue);
        expect(valueController.canStart, isFalse);
      }
      store.failRead = true;
      final locked = make();
      await locked.initialize();
      expect(locked.blocksOwner, isTrue);
      expect(locked.visibleResources, isEmpty);
    },
  );

  test(
    'unsupported secure storage cannot offer handoff or write state',
    () async {
      store.supported = false;
      final unsupported = make();
      await unsupported.initialize();
      expect(unsupported.status, HandoffStatus.unsupported);
      expect(unsupported.canStart, isFalse);
      expect(unsupported.preview(['moon-phases']), isNull);
      expect(store.writes, 0);
    },
  );

  test(
    'activation hides owner and guest until active write is acknowledged',
    () async {
      store.beforeWrite = Completer<void>();
      final action = activate();
      while (store.writes == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.blocksOwner, isTrue);
      expect(controller.visibleResources, isEmpty);
      store.beforeWrite!.complete();
      expect((await action).success, isTrue);
      expect(controller.visibleResources, hasLength(1));
    },
  );

  test('failed or ignored activation write remains gated', () async {
    store.ignoreWrites = true;
    expect((await activate()).result, HandoffResult.unavailable);
    expect(controller.blocksOwner, isTrue);
    expect(controller.visibleResources, isEmpty);
  });

  test(
    'failed inactive write cannot release owner or discard stored session',
    () async {
      await activate();
      store.ignoreWrites = true;
      expect(
        (await controller.unlock('83197246')).result,
        HandoffResult.unavailable,
      );
      expect(controller.blocksOwner, isTrue);
      expect((jsonDecode(store.value!) as Map)['active'], isTrue);
    },
  );

  test('pending timed-out write cannot race a subsequent write', () async {
    final fastTimeout = make(timeout: const Duration(milliseconds: 30));
    await fastTimeout.initialize();
    await activate(using: fastTimeout);
    store.beforeWrite = Completer<void>();
    expect(
      (await fastTimeout.unlock('83197246')).result,
      HandoffResult.unavailable,
    );
    final writes = store.writes;
    expect(
      (await fastTimeout.unlock('83197246')).result,
      HandoffResult.unavailable,
    );
    expect(store.writes, writes);
    expect(fastTimeout.canStart, isFalse);
    expect(fastTimeout.blocksOwner, isTrue);
    store.beforeWrite!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fastTimeout.blocksOwner, isTrue);
  });

  test(
    'verified return stays hidden until durable commit; later interruption is not an auth bypass',
    () async {
      await activate();
      store.beforeInactiveWrite = Completer<void>();
      final unlocking = controller.unlock('83197246');
      while (!store.inactiveWriteEntered) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.returnAuthorized, isTrue);
      expect(controller.blocksOwner, isTrue);
      expect((jsonDecode(store.value!) as Map)['active'], isTrue);
      // Correct code was already verified before committing the requested return.
      // Backgrounding here does not revoke that completed owner authorization.
      controller.interrupt();
      expect(controller.blocksOwner, isTrue);
      store.beforeInactiveWrite!.complete();
      expect((await unlocking).success, isTrue);
      expect(controller.blocksOwner, isFalse);
      expect(await store.read(), '{"schema":1,"active":false}');
    },
  );

  test(
    'late inactive write can complete only an already authenticated return after restart',
    () async {
      final fastTimeout = make(timeout: const Duration(milliseconds: 30));
      await fastTimeout.initialize();
      await activate(using: fastTimeout);
      store.beforeInactiveWrite = Completer<void>();
      expect(
        (await fastTimeout.unlock('83197246')).result,
        HandoffResult.unavailable,
      );
      expect(fastTimeout.returnUnconfirmed, isTrue);
      expect(fastTimeout.blocksOwner, isTrue);
      final beforeCompletion = make();
      await beforeCompletion.initialize();
      expect(beforeCompletion.blocksOwner, isTrue);
      final writes = store.writes;
      expect(
        (await fastTimeout.unlock('99999999')).result,
        HandoffResult.unavailable,
      );
      expect(store.writes, writes);
      store.beforeInactiveWrite!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        fastTimeout.blocksOwner,
        isTrue,
        reason:
            'The current process never silently converts timeout into UI success',
      );
      final afterCompletion = make();
      await afterCompletion.initialize();
      expect(
        afterCompletion.blocksOwner,
        isFalse,
        reason:
            'The correct code and explicit return were already authorized before the late write',
      );
    },
  );

  test(
    'five failed attempts persist backoff across process replacement',
    () async {
      await activate();
      for (var i = 0; i < 5; i++) {
        expect(
          (await controller.unlock('99999999')).result,
          HandoffResult.incorrectCode,
        );
      }
      final restarted = make();
      await restarted.initialize();
      expect(
        (await restarted.unlock('83197246')).result,
        HandoffResult.rateLimited,
      );
      time = time.add(const Duration(seconds: 31));
      expect((await restarted.unlock('83197246')).success, isTrue);
    },
  );

  test(
    'clock rollback cannot remove a spent attempt or bypass waiting',
    () async {
      await activate();
      await controller.unlock('00000000');
      time = time.subtract(const Duration(minutes: 2));
      expect(
        (await controller.unlock('83197246')).result,
        HandoffResult.rateLimited,
      );
      expect(controller.blocksOwner, isTrue);
    },
  );

  test(
    'background/back cancellation defeats in-flight code verification',
    () async {
      await activate();
      derivation.entered = false;
      derivation.waiting = Completer<void>();
      final unlocking = controller.unlock('83197246');
      while (!derivation.entered) {
        await Future<void>.delayed(Duration.zero);
      }
      controller.interrupt();
      derivation.waiting!.complete();
      expect((await unlocking).result, HandoffResult.canceled);
      expect(controller.blocksOwner, isTrue);
      expect((jsonDecode(store.value!) as Map)['active'], isTrue);
    },
  );

  test('policy revocation during derivation prevents activation', () async {
    derivation.entered = false;
    derivation.waiting = Completer<void>();
    final activating = activate();
    while (!derivation.entered) {
      await Future<void>.delayed(Duration.zero);
    }
    policy.repository.restrict('fixture-revoked');
    derivation.waiting!.complete();
    expect((await activating).result, HandoffResult.ineligible);
    expect(store.writes, 0);
  });

  test(
    'revocation or resource hash change hides body but keeps owner locked',
    () async {
      await activate();
      final record = jsonDecode(store.value!) as Map<String, dynamic>;
      (record['resources'] as List).first['sha256'] = '0' * 64;
      store.value = jsonEncode(record);
      final mismatched = make();
      await mismatched.initialize();
      expect(mismatched.visibleResources, isEmpty);
      expect(mismatched.blocksOwner, isTrue);
      policy.repository.restrict('fixture-revoked');
      expect(controller.visibleResources, isEmpty);
      expect(controller.blocksOwner, isTrue);
    },
  );

  test('expiry never returns owner or grants stale shared content', () async {
    await activate();
    time = DateTime.utc(2030);
    expect(controller.visibleResources, isEmpty);
    expect(controller.blocksOwner, isTrue);
  });

  testWidgets('guest has no owner subtree, input, selection or back escape', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await activate();
    });
    var ownerBuilds = 0;
    await tester.pumpWidget(
      HandoffGate(
        controller: controller,
        ownerBuilder: (_) {
          ++ownerBuilds;
          return const MaterialApp(home: Text('PRIVATE_OWNER_NOTES'));
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(ownerBuilds, 0);
    expect(find.text('PRIVATE_OWNER_NOTES'), findsNothing);
    expect(
      find.byKey(const ValueKey('handoff-body-moon-phases')),
      findsOneWidget,
    );
    expect(find.byType(EditableText), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(SelectionArea), findsNothing);
    await tester.binding.handlePushRoute('/owner-settings?private=1');
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE_OWNER_NOTES'), findsNothing);
    expect(ownerBuilds, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.blocksOwner, isTrue);
    expect(ownerBuilds, 0);
    await tester.tap(find.byKey(const ValueKey('handoff-return')));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byKey(const ValueKey('handoff-key-1')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(ownerBuilds, 0);
    expect(controller.blocksOwner, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
