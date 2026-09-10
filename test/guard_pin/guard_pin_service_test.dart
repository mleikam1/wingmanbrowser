import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/guard_pin/guard_pin_service.dart';
import 'package:wingman_browser/guard_pin/pin_derivation.dart';

class MemoryPinStore implements GuardPinStore {
  @override
  bool supported = true;
  String? value;
  bool failRead = false;
  bool ignoreWrites = false;
  int writes = 0;
  int reads = 0;
  @override
  Future<String?> read() async {
    reads++;
    if (failRead) throw StateError('Do not log storage error secrets');
    return value;
  }

  @override
  Future<void> write(String record) async {
    writes++;
    if (!ignoreWrites) value = record;
  }

  @override
  Future<void> delete() async => value = null;
}

/// Fast deterministic verifier for state-machine tests; production is covered
/// separately against an independently calculated PBKDF2 known answer.
class FastDerivation implements PinDerivation {
  Completer<void>? pending;
  bool entered = false;
  @override
  Future<List<int>> derive(String pin, List<int> salt) async {
    entered = true;
    await pending?.future;
    return (await Sha256().hash([...salt, ...utf8.encode(pin)])).bytes;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only six to twelve ASCII digits can configure a PIN', () async {
    final store = MemoryPinStore();
    final service = GuardPinService(store: store, derivation: FastDerivation());
    for (final pin in [
      '',
      '12345',
      '1234567890123',
      '12345a',
      '１２３４５６',
      '123456\n',
    ]) {
      expect((await service.setPin(pin)).reason, GuardPinReason.invalidPin);
    }
    expect(store.writes, 0);
    expect(service.status, GuardPinStatus.notConfigured);
  });

  test(
    'salted verifier is protected and restart never restores an unlock',
    () async {
      final store = MemoryPinStore();
      final service = GuardPinService(
        store: store,
        derivation: FastDerivation(),
      );
      expect((await service.setPin('319724')).success, isTrue);
      expect(service.hasPin, isTrue);
      expect(service.isLocked, isTrue);
      expect(store.value, isNot(contains('319724')));
      final record = jsonDecode(store.value!) as Map;
      expect(record['algorithm'], 'pbkdf2-hmac-sha256');
      expect(record['iterations'], 600000);
      expect(base64Decode(record['salt'] as String), hasLength(32));
      expect(base64Decode(record['verifier'] as String), hasLength(32));
      expect((await service.unlock('319724')).success, isTrue);
      expect(service.status, GuardPinStatus.unlocked);
      final restarted = GuardPinService(
        store: store,
        derivation: FastDerivation(),
      );
      await restarted.initialize();
      expect(restarted.status, GuardPinStatus.locked);
    },
  );

  test('same PIN produces different salts and verifiers', () async {
    final first = MemoryPinStore();
    final second = MemoryPinStore();
    await GuardPinService(
      store: first,
      derivation: FastDerivation(),
      random: Random(1),
    ).setPin('123456');
    await GuardPinService(
      store: second,
      derivation: FastDerivation(),
      random: Random(2),
    ).setPin('123456');
    final a = jsonDecode(first.value!) as Map;
    final b = jsonDecode(second.value!) as Map;
    expect(a['salt'], isNot(b['salt']));
    expect(a['verifier'], isNot(b['verifier']));
  });

  test(
    'unreadable or corrupt storage cannot silently remove PIN protection',
    () async {
      for (final store in [
        MemoryPinStore()..failRead = true,
        MemoryPinStore()..value = '{bad credential}',
      ]) {
        final service = GuardPinService(
          store: store,
          derivation: FastDerivation(),
        );
        await service.initialize();
        expect(service.status, GuardPinStatus.unavailable);
        expect(service.isLocked, isTrue);
        expect((await service.setPin('123456')).success, isFalse);
        expect(store.writes, 0);
      }
    },
  );

  test('non-persisting storage writes fail closed', () async {
    final store = MemoryPinStore()..ignoreWrites = true;
    final service = GuardPinService(store: store, derivation: FastDerivation());
    expect((await service.setPin('123456')).reason, GuardPinReason.unavailable);
    expect(service.isLocked, isTrue);
  });

  test(
    'attempt limit persists through restart and correct PIN cannot skip delay',
    () async {
      final store = MemoryPinStore();
      var time = DateTime.utc(2026, 9, 10);
      final service = GuardPinService(
        store: store,
        derivation: FastDerivation(),
        clock: () => time,
      );
      await service.setPin('123456');
      final guesses = await Future.wait(
        List.generate(5, (_) => service.unlock('999999')),
      );
      expect(guesses.every((value) => !value.success), isTrue);
      expect((jsonDecode(store.value!) as Map)['failures'], 5);
      final restarted = GuardPinService(
        store: store,
        derivation: FastDerivation(),
        clock: () => time,
      );
      expect(
        (await restarted.unlock('123456')).reason,
        GuardPinReason.rateLimited,
      );
      time = time.add(const Duration(seconds: 31));
      expect((await restarted.unlock('123456')).success, isTrue);
      expect((jsonDecode(store.value!) as Map)['failures'], 0);
    },
  );

  test('background lock cancels an in-flight unlock grant', () async {
    final store = MemoryPinStore();
    final derivation = FastDerivation();
    final service = GuardPinService(store: store, derivation: derivation);
    await service.setPin('123456');
    derivation.entered = false;
    derivation.pending = Completer<void>();
    final unlock = service.unlock('123456');
    await Future<void>.delayed(Duration.zero);
    expect(derivation.entered, isTrue);
    service.lock();
    derivation.pending!.complete();
    expect((await unlock).reason, GuardPinReason.cancelled);
    expect(service.isLocked, isTrue);
  });

  test(
    'replacing and removing PIN require its current value even after unlock',
    () async {
      final store = MemoryPinStore();
      final service = GuardPinService(
        store: store,
        derivation: FastDerivation(),
      );
      await service.setPin('123456');
      await service.unlock('123456');
      expect(
        (await service.setPin('654321', currentPin: '999999')).success,
        isFalse,
      );
      expect((await service.removePin('999999')).success, isFalse);
      expect(service.hasPin, isTrue);
      expect(
        (await service.setPin('654321', currentPin: '123456')).success,
        isTrue,
      );
      expect((await service.unlock('123456')).success, isFalse);
      expect((await service.removePin('654321')).success, isTrue);
      expect(store.value, isNull);
      expect(service.status, GuardPinStatus.notConfigured);
    },
  );

  test(
    'unsupported platforms never read or write a local-storage fallback',
    () async {
      final store = MemoryPinStore()..supported = false;
      final service = GuardPinService(
        store: store,
        derivation: FastDerivation(),
      );
      await service.initialize();
      expect(service.status, GuardPinStatus.unsupported);
      expect((await service.setPin('123456')).success, isFalse);
      expect(store.reads, 0);
      expect(store.writes, 0);
    },
  );

  test('production PBKDF2 matches independent Python hashlib answer', () async {
    final watch = Stopwatch()..start();
    final derived = await const Pbkdf2PinDerivation().derive(
      '123456',
      List.generate(32, (index) => index),
    );
    watch.stop();
    expect(
      base64Encode(derived),
      'Og2XL/MacyJKrVys5TAPo4kpZX/Go2ZCsW8wqejDqt0=',
    );
    // Test runner-only duration, never the PIN, salt or verifier.
    // ignore: avoid_print
    print('PIN_KDF_TEST_MS=${watch.elapsedMilliseconds}');
  });
}
