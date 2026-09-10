import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'guard_pin_store.dart';
import 'pin_derivation.dart';

export 'guard_pin_store.dart';

enum GuardPinStatus {
  loading,
  notConfigured,
  locked,
  unlocked,
  unavailable,
  unsupported,
}

enum GuardPinReason {
  success,
  invalidPin,
  incorrectPin,
  rateLimited,
  unavailable,
  notConfigured,
  cancelled,
}

class GuardPinAttempt {
  const GuardPinAttempt(this.reason, {this.retryAfter = Duration.zero});
  final GuardPinReason reason;
  final Duration retryAfter;
  bool get success => reason == GuardPinReason.success;
}

/// Local settings protection, not device management or a tamper-proof boundary.
/// Use one instance for the app. Call lock on background and on leaving the
/// protected settings session. Every app start begins locked if a PIN exists.
class GuardPinService extends ChangeNotifier {
  GuardPinService({
    GuardPinStore? store,
    this.derivation = const Pbkdf2PinDerivation(),
    DateTime Function()? clock,
    Random? random,
  }) : _store = store ?? PlatformGuardPinStore(),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final GuardPinStore _store;
  final PinDerivation derivation;
  final DateTime Function() _clock;
  final Random _random;
  Future<void> _queue = Future<void>.value();
  _PinRecord? _record;
  GuardPinStatus _status = GuardPinStatus.loading;
  bool _initialized = false;
  bool _disposed = false;
  int _lockRevision = 0;

  GuardPinStatus get status => _status;
  bool get hasPin => _record != null;
  bool get isSupported => _store.supported;
  bool get isLocked => switch (_status) {
    GuardPinStatus.loading ||
    GuardPinStatus.locked ||
    GuardPinStatus.unavailable => true,
    _ => false,
  };

  static bool isValidPin(String pin) => RegExp(r'^[0-9]{6,12}$').hasMatch(pin);

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> initialize() => _exclusive(_initialize);

  Future<void> _initialize() async {
    if (_initialized || _disposed) return;
    if (!_store.supported) {
      _initialized = true;
      _setStatus(GuardPinStatus.unsupported);
      return;
    }
    try {
      final value = await _store.read();
      _record = value == null ? null : _PinRecord.decode(value);
      _initialized = true;
      _setStatus(hasPin ? GuardPinStatus.locked : GuardPinStatus.notConfigured);
    } catch (_) {
      // An unreadable credential is never interpreted as no PIN.
      _setStatus(GuardPinStatus.unavailable);
    }
  }

  Future<GuardPinAttempt> _operation(
    Future<GuardPinAttempt> Function() action,
  ) => _exclusive(() async {
    await _initialize();
    if (_disposed ||
        !_store.supported ||
        !_initialized ||
        _status == GuardPinStatus.unavailable) {
      return const GuardPinAttempt(GuardPinReason.unavailable);
    }
    try {
      return await action();
    } catch (_) {
      _setStatus(GuardPinStatus.unavailable);
      return const GuardPinAttempt(GuardPinReason.unavailable);
    }
  });

  Future<GuardPinAttempt> unlock(String pin) {
    final revision = _lockRevision;
    return _operation(() async {
      final result = await _verify(pin);
      if (!result.success) return result;
      if (_disposed || revision != _lockRevision) {
        return const GuardPinAttempt(GuardPinReason.cancelled);
      }
      _setStatus(GuardPinStatus.unlocked);
      return result;
    });
  }

  Future<GuardPinAttempt> setPin(String newPin, {String? currentPin}) {
    final revision = _lockRevision;
    return _operation(() async {
      if (!isValidPin(newPin)) {
        return const GuardPinAttempt(GuardPinReason.invalidPin);
      }
      if (hasPin) {
        final authorized = await _verify(currentPin ?? '');
        if (!authorized.success) return authorized;
      }
      if (_disposed || revision != _lockRevision) {
        return const GuardPinAttempt(GuardPinReason.cancelled);
      }
      final salt = List<int>.generate(32, (_) => _random.nextInt(256));
      final verifier = await derivation.derive(newPin, salt);
      if (_disposed || revision != _lockRevision) {
        return const GuardPinAttempt(GuardPinReason.cancelled);
      }
      await _persist(_PinRecord(salt: salt, verifier: verifier));
      _setStatus(GuardPinStatus.locked);
      return const GuardPinAttempt(GuardPinReason.success);
    });
  }

  Future<GuardPinAttempt> removePin(String pin) {
    final revision = _lockRevision;
    return _operation(() async {
      final authorized = await _verify(pin);
      if (!authorized.success) return authorized;
      if (_disposed || revision != _lockRevision) {
        return const GuardPinAttempt(GuardPinReason.cancelled);
      }
      await _store.delete();
      if (await _store.read() != null) throw const FormatException();
      _record = null;
      _setStatus(GuardPinStatus.notConfigured);
      return const GuardPinAttempt(GuardPinReason.success);
    });
  }

  Future<GuardPinAttempt> _verify(String pin) async {
    final record = _record;
    if (record == null) {
      return const GuardPinAttempt(GuardPinReason.notConfigured);
    }
    final now = _clock().millisecondsSinceEpoch;
    if (now < record.retryAt) {
      return GuardPinAttempt(
        GuardPinReason.rateLimited,
        retryAfter: Duration(milliseconds: record.retryAt - now),
      );
    }
    final failures = min(record.failures + 1, 30);
    final delaySeconds = failures < 5
        ? 0
        : min(30 * (1 << (failures - 5)), 3600);
    // Count an attempt before deriving: killing the app mid-attempt does not
    // reset its retry budget. Successful verification resets this record.
    await _persist(record.withAttempts(failures, now + delaySeconds * 1000));
    if (!isValidPin(pin)) {
      _setStatus(GuardPinStatus.locked);
      return const GuardPinAttempt(GuardPinReason.invalidPin);
    }
    final candidate = await derivation.derive(pin, record.salt);
    if (!_sameBytes(candidate, record.verifier)) {
      _setStatus(GuardPinStatus.locked);
      return GuardPinAttempt(
        GuardPinReason.incorrectPin,
        retryAfter: Duration(seconds: delaySeconds),
      );
    }
    await _persist(record.withAttempts(0, 0));
    return const GuardPinAttempt(GuardPinReason.success);
  }

  Future<void> _persist(_PinRecord record) async {
    final encoded = record.encode();
    await _store.write(encoded);
    // Catch platform errors that otherwise look like successful writes.
    if (await _store.read() != encoded) throw const FormatException();
    _record = record;
  }

  void lock() {
    ++_lockRevision;
    if (hasPin && _status != GuardPinStatus.unavailable) {
      _setStatus(GuardPinStatus.locked);
    }
  }

  void _setStatus(GuardPinStatus value) {
    _status = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    lock();
    _disposed = true;
    super.dispose();
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  var difference = a.length ^ b.length;
  for (var i = 0; i < b.length; i++) {
    difference |= (i < a.length ? a[i] : 0) ^ b[i];
  }
  return difference == 0;
}

class _PinRecord {
  _PinRecord({
    required this.salt,
    required this.verifier,
    this.failures = 0,
    this.retryAt = 0,
  }) {
    if (salt.length != 32 ||
        verifier.length != 32 ||
        salt.any((b) => b < 0 || b > 255) ||
        verifier.any((b) => b < 0 || b > 255) ||
        failures < 0 ||
        failures > 30 ||
        retryAt < 0) {
      throw const FormatException();
    }
  }
  final List<int> salt;
  final List<int> verifier;
  final int failures;
  final int retryAt;

  _PinRecord withAttempts(int failures, int retryAt) => _PinRecord(
    salt: salt,
    verifier: verifier,
    failures: failures,
    retryAt: retryAt,
  );

  String encode() => jsonEncode({
    'version': 1,
    'algorithm': 'pbkdf2-hmac-sha256',
    'iterations': Pbkdf2PinDerivation.iterations,
    'salt': base64Encode(salt),
    'verifier': base64Encode(verifier),
    'failures': failures,
    'retryAt': retryAt,
  });

  static _PinRecord decode(String value) {
    if (value.length > 2048) throw const FormatException();
    final record = jsonDecode(value) as Map<String, dynamic>;
    if (record['version'] != 1 ||
        record['algorithm'] != 'pbkdf2-hmac-sha256' ||
        record['iterations'] != Pbkdf2PinDerivation.iterations) {
      throw const FormatException();
    }
    return _PinRecord(
      salt: base64Decode(record['salt'] as String),
      verifier: base64Decode(record['verifier'] as String),
      failures: record['failures'] as int,
      retryAt: record['retryAt'] as int,
    );
  }
}
