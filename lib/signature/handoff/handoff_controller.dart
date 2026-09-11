import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../guard_pin/pin_derivation.dart';
import '../../policy/policy_runtime.dart';
import 'handoff_store.dart';

export 'handoff_store.dart';

enum HandoffStatus { loading, owner, active, unavailable, unsupported }

enum HandoffResult {
  success,
  invalidCode,
  confirmationMismatch,
  incorrectCode,
  rateLimited,
  ineligible,
  canceled,
  unavailable,
}

class HandoffAttempt {
  const HandoffAttempt(this.result, {this.retryAfter = Duration.zero});
  final HandoffResult result;
  final Duration retryAfter;
  bool get success => result == HandoffResult.success;
}

class HandoffCapabilities {
  const HandoffCapabilities({
    this.staticSupported = false,
    this.deviceAuthenticationAvailable = false,
  });
  final bool staticSupported;
  final bool deviceAuthenticationAvailable;

  static Future<HandoffCapabilities> read() async {
    final data = await const MethodChannel(
      'wingman/browser',
    ).invokeMapMethod<String, Object?>('handoffCapabilities');
    return HandoffCapabilities(
      staticSupported:
          data?['staticOnly'] == true &&
          data?['contentViews'] == 0 &&
          data?['liveBrowsing'] == false,
      deviceAuthenticationAvailable:
          data?['deviceAuthenticationAvailable'] == true,
    );
  }
}

/// This object is minted by the authoritative policy, never from pasted text,
/// URLs, owner notes, findings, bookmarks or caller-created article bodies.
class HandoffPreview {
  HandoffPreview._(
    this._controller,
    List<ApprovedResource> resources,
    this._additional,
  ) : resources = List.unmodifiable(resources);
  final HandoffController _controller;
  final AdditionalRestrictions? _additional;
  final List<ApprovedResource> resources;
}

/// Static read-only sharing. The code authenticates only return to the owner;
/// it cannot change content policy or enable a native content capability.
/// Initialize before constructing/loading owner state, then attach the signed
/// policy runtime. All persistent mutations are serialized and read back.
class HandoffController extends ChangeNotifier {
  HandoffController({
    HandoffStore? store,
    PinDerivation? derivation,
    Future<HandoffCapabilities> Function()? capabilities,
    Future<void> Function()? discardIncoming,
    DateTime Function()? clock,
    Random? random,
    this.persistenceTimeout = storageTimeout,
    this.onStarted,
    this.onEnded,
  }) : _store = store ?? PlatformHandoffStore(),
       _derivation = derivation ?? const Pbkdf2PinDerivation(),
       _capabilitiesReader = capabilities ?? HandoffCapabilities.read,
       _discardIncoming = discardIncoming ?? _discardNativeIncoming,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final HandoffStore _store;
  final PinDerivation _derivation;
  final Future<HandoffCapabilities> Function() _capabilitiesReader;
  final Future<void> Function() _discardIncoming;
  final DateTime Function() _clock;
  final Random _random;
  final Duration persistenceTimeout;

  /// Root must route these payload-free events to a session-only handoff journal.
  final VoidCallback? onStarted, onEnded;
  Future<void> _queue = Future.value();
  Future<void>? _pendingPersistence;
  PolicyRuntime? _policy;
  _Session? _session;
  HandoffStatus _status = HandoffStatus.loading;
  HandoffCapabilities _capabilities = const HandoffCapabilities();
  bool _initialized = false, _disposed = false, _busy = false;
  bool _returnAuthorized = false;
  bool _returnUnconfirmed = false;
  int _revision = 0;
  static const maxResources = 8;
  static const maxBodyCharacters = 120000;
  static const storageTimeout = Duration(seconds: 10);

  HandoffStatus get status => _status;
  HandoffCapabilities get capabilities => _capabilities;
  bool get busy => _busy;
  bool get returnAuthorized => _returnAuthorized;
  bool get returnUnconfirmed => _returnUnconfirmed;
  bool get blocksOwner =>
      status != HandoffStatus.owner && status != HandoffStatus.unsupported;
  bool get canStart =>
      status == HandoffStatus.owner && _capabilities.staticSupported && !_busy;
  bool get canAuthenticate =>
      _session != null && !_busy && _pendingPersistence == null;
  int get lifecycleRevision => _revision;

  static bool isValidCode(String value) =>
      RegExp(r'^[0-9]{8,12}$').hasMatch(value) &&
      value.codeUnits.every((unit) => unit >= 48 && unit <= 57);

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  static Future<void> _discardNativeIncoming() => const MethodChannel(
    'wingman/browser',
  ).invokeMethod<void>('discardHandoffIncoming');

  Future<void> _discardGuestIncoming() =>
      _discardIncoming().timeout(persistenceTimeout);

  Future<void> initialize() => _exclusive(() async {
    if (_initialized || _disposed) return;
    if (!_store.supported) {
      _initialized = true;
      _setStatus(HandoffStatus.unsupported);
      return;
    }
    try {
      final value = await _store.read().timeout(persistenceTimeout);
      _session = value == null ? null : _Session.decode(value);
      if (_session != null) await _discardGuestIncoming();
      _initialized = true;
      try {
        _capabilities = await _capabilitiesReader().timeout(persistenceTimeout);
      } catch (_) {
        _capabilities = const HandoffCapabilities();
      }
      _setStatus(_session == null ? HandoffStatus.owner : HandoffStatus.active);
    } catch (_) {
      // Locked/unreadable/corrupt storage cannot be interpreted as inactive.
      // Best-effort address disposal cannot release this unavailable gate.
      try {
        await _discardGuestIncoming();
      } catch (_) {}
      _setStatus(HandoffStatus.unavailable);
    }
  });

  void attachPolicy(PolicyRuntime policy) {
    if (identical(policy, _policy)) return;
    _policy?.removeListener(_policyChanged);
    _policy = policy;
    _policy?.addListener(_policyChanged);
    _policyChanged();
  }

  void _policyChanged() {
    if (!_disposed) notifyListeners();
  }

  HandoffPreview? preview(
    Iterable<String> resourceIds, {
    AdditionalRestrictions? additional,
  }) {
    if (!canStart || _policy == null) return null;
    final ids = resourceIds.take(maxResources + 1).toList();
    if (ids.isEmpty ||
        ids.length > maxResources ||
        ids.toSet().length != ids.length) {
      return null;
    }
    final resources = <ApprovedResource>[];
    var bodyCharacters = 0;
    for (final id in ids) {
      final resource = _eligible(id, additional: additional);
      if (resource == null) return null;
      bodyCharacters += resource.body.length;
      if (bodyCharacters > maxBodyCharacters) return null;
      resources.add(resource);
    }
    return HandoffPreview._(this, resources, additional);
  }

  ApprovedResource? _eligible(String id, {AdditionalRestrictions? additional}) {
    final policy = _policy;
    if (policy == null ||
        !policy.policy
            .evaluate(PolicyRequest.bundled(id), additional: additional)
            .isAllowed) {
      return null;
    }
    return policy.resource(id);
  }

  /// Re-checks every frame/policy notification; a changed hash or revoked or
  /// expired approval hides the entire shared collection, never opens owner UI.
  List<ApprovedResource> get visibleResources {
    final session = _session;
    if (session == null ||
        status != HandoffStatus.active ||
        !_capabilities.staticSupported) {
      return const [];
    }
    final resources = <ApprovedResource>[];
    var bodyCharacters = 0;
    for (final item in session.resources) {
      final resource = _eligible(item.id);
      if (resource == null || resource.sha256 != item.sha256) return const [];
      bodyCharacters += resource.body.length;
      if (bodyCharacters > maxBodyCharacters) return const [];
      resources.add(resource);
    }
    return List.unmodifiable(resources);
  }

  Future<HandoffAttempt> activate({
    required HandoffPreview preview,
    required String code,
    required String confirmation,
  }) {
    final revision = _revision;
    return _exclusive(() async {
      if (_disposed || !canStart || !identical(preview._controller, this)) {
        return const HandoffAttempt(HandoffResult.unavailable);
      }
      if (!isValidCode(code)) {
        return const HandoffAttempt(HandoffResult.invalidCode);
      }
      if (code != confirmation) {
        return const HandoffAttempt(HandoffResult.confirmationMismatch);
      }
      bool stillEligible() => preview.resources.every(
        (resource) =>
            _eligible(resource.id, additional: preview._additional)?.sha256 ==
            resource.sha256,
      );
      if (!stillEligible()) {
        return const HandoffAttempt(HandoffResult.ineligible);
      }
      _busy = true;
      notifyListeners();
      try {
        final salt = List<int>.generate(32, (_) => _random.nextInt(256));
        final verifier = await _derivation.derive(code, salt);
        if (_disposed || revision != _revision) {
          return const HandoffAttempt(HandoffResult.canceled);
        }
        if (!stillEligible()) {
          return const HandoffAttempt(HandoffResult.ineligible);
        }
        final session = _Session(
          resources: preview.resources
              .map((resource) => _Pinned(resource.id, resource.sha256))
              .toList(),
          salt: salt,
          verifier: verifier,
        );
        // Hide owner while writing, but do not show any guest body until durable.
        _setStatus(HandoffStatus.loading);
        await _discardGuestIncoming();
        if (_disposed || revision != _revision || !stillEligible()) {
          _setStatus(HandoffStatus.owner);
          return HandoffAttempt(
            revision != _revision
                ? HandoffResult.canceled
                : HandoffResult.ineligible,
          );
        }
        await _persist(session.encode());
        _session = session;
        _setStatus(HandoffStatus.active);
        _emit(onStarted);
        return const HandoffAttempt(HandoffResult.success);
      } catch (_) {
        _setStatus(HandoffStatus.unavailable);
        return const HandoffAttempt(HandoffResult.unavailable);
      } finally {
        _busy = false;
        if (!_disposed) notifyListeners();
      }
    });
  }

  Future<HandoffAttempt> unlock(String code) {
    final revision = _revision;
    return _exclusive(() async {
      final session = _session;
      if (_disposed || session == null || !_initialized || !canAuthenticate) {
        return const HandoffAttempt(HandoffResult.unavailable);
      }
      final now = _clock().millisecondsSinceEpoch;
      if (now < session.retryAt || now < session.lastAttemptAt) {
        return HandoffAttempt(
          HandoffResult.rateLimited,
          retryAfter: Duration(
            milliseconds: max(session.retryAt, session.lastAttemptAt) - now,
          ),
        );
      }
      _busy = true;
      notifyListeners();
      try {
        final failures = min(30, session.failures + 1);
        final seconds = failures < 5
            ? 0
            : min(3600, 30 * (1 << (failures - 5)));
        final attempted = session.withAttempt(
          failures,
          now + seconds * 1000,
          now,
        );
        // Persist a spent attempt before verification, including invalid codes.
        await _persist(attempted.encode());
        _session = attempted;
        if (!isValidCode(code)) {
          return const HandoffAttempt(HandoffResult.invalidCode);
        }
        final candidate = await _derivation.derive(code, session.salt);
        if (!_sameBytes(candidate, session.verifier)) {
          return HandoffAttempt(
            HandoffResult.incorrectCode,
            retryAfter: Duration(seconds: seconds),
          );
        }
        if (_disposed || revision != _revision) {
          return const HandoffAttempt(HandoffResult.canceled);
        }
        // Native dropping stays enabled until the authenticated owner shell
        // explicitly initializes. Clearing the queue cannot admit any content.
        await _discardGuestIncoming();
        if (_disposed || revision != _revision) {
          return const HandoffAttempt(HandoffResult.canceled);
        }
        // Authentication is complete. Only a confirmed durable inactive record
        // can release the owner gate; failure leaves owner content inaccessible.
        _returnAuthorized = true;
        if (!_disposed) notifyListeners();
        await _persist(_Session.inactive);
        _returnUnconfirmed = false;
        _session = null;
        _setStatus(HandoffStatus.owner);
        _emit(onEnded);
        return const HandoffAttempt(HandoffResult.success);
      } catch (_) {
        if (_returnAuthorized) _returnUnconfirmed = true;
        _setStatus(HandoffStatus.unavailable);
        return const HandoffAttempt(HandoffResult.unavailable);
      } finally {
        _returnAuthorized = false;
        _busy = false;
        if (!_disposed) notifyListeners();
      }
    });
  }

  Future<void> _persist(String value) async {
    if (_pendingPersistence != null) throw const FormatException();
    final operation = () async {
      await _store.write(value);
      if (await _store.read() != value) {
        throw const FormatException('Handoff storage did not confirm the gate');
      }
    }();
    _pendingPersistence = operation;
    // A timed-out native write can still complete. Do not allow any subsequent
    // write to race it, especially an old inactive marker against a new session.
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(_pendingPersistence, operation)) {
            _pendingPersistence = null;
          }
          if (!_disposed) notifyListeners();
        },
        onError: (Object _) {
          if (identical(_pendingPersistence, operation)) {
            _pendingPersistence = null;
          }
          if (!_disposed) notifyListeners();
        },
      ),
    );
    await operation.timeout(persistenceTimeout);
  }

  /// Backgrounding/back cancellation invalidates code verification in flight.
  /// It never clears a persistent session or unlocks the owner.
  void interrupt() {
    ++_revision;
    if (!_disposed) notifyListeners();
  }

  void _setStatus(HandoffStatus value) {
    _status = value;
    if (!_disposed) notifyListeners();
  }

  void _emit(VoidCallback? callback) {
    try {
      callback?.call();
    } catch (_) {
      // A receipt callback cannot alter an already committed security state.
    }
  }

  @override
  void dispose() {
    ++_revision;
    _disposed = true;
    _policy?.removeListener(_policyChanged);
    super.dispose();
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  for (var i = 0; i < right.length; i++) {
    difference |= (i < left.length ? left[i] : 0) ^ right[i];
  }
  return difference == 0;
}

class _Pinned {
  _Pinned(this.id, this.sha256);
  final String id, sha256;
  Map<String, String> toJson() => {'id': id, 'sha256': sha256};
}

class _Session {
  _Session({
    required this.resources,
    required this.salt,
    required this.verifier,
    this.failures = 0,
    this.retryAt = 0,
    this.lastAttemptAt = 0,
  });
  final List<_Pinned> resources;
  final List<int> salt, verifier;
  final int failures, retryAt, lastAttemptAt;
  static const inactive = '{"schema":1,"active":false}';

  _Session withAttempt(int failures, int retryAt, int lastAttemptAt) =>
      _Session(
        resources: resources,
        salt: salt,
        verifier: verifier,
        failures: failures,
        retryAt: retryAt,
        lastAttemptAt: lastAttemptAt,
      );

  String encode() => jsonEncode({
    'schema': 1,
    'active': true,
    'resources': resources.map((item) => item.toJson()).toList(),
    'algorithm': 'pbkdf2-hmac-sha256',
    'iterations': Pbkdf2PinDerivation.iterations,
    'salt': base64Encode(salt),
    'verifier': base64Encode(verifier),
    'failures': failures,
    'retryAt': retryAt,
    'lastAttemptAt': lastAttemptAt,
  });

  static _Session? decode(String value) {
    if (value.length > 8192) throw const FormatException();
    final data = jsonDecode(value) as Map<String, dynamic>;
    if (data['schema'] != 1 || data['active'] is! bool) {
      throw const FormatException();
    }
    if (data['active'] == false) {
      if (data.length != 2) throw const FormatException();
      return null;
    }
    if (data['algorithm'] != 'pbkdf2-hmac-sha256' ||
        data['iterations'] != Pbkdf2PinDerivation.iterations) {
      throw const FormatException();
    }
    final list = data['resources'] as List;
    if (list.isEmpty || list.length > HandoffController.maxResources) {
      throw const FormatException();
    }
    final resources = <_Pinned>[];
    for (final raw in list) {
      final row = raw as Map<String, dynamic>;
      final id = row['id'] as String;
      final hash = row['sha256'] as String;
      if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,79}$').hasMatch(id) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
        throw const FormatException();
      }
      resources.add(_Pinned(id, hash));
    }
    if (resources.map((item) => item.id).toSet().length != resources.length) {
      throw const FormatException();
    }
    final salt = base64Decode(data['salt'] as String);
    final verifier = base64Decode(data['verifier'] as String);
    final failures = data['failures'] as int;
    final retryAt = data['retryAt'] as int;
    final lastAttemptAt = data['lastAttemptAt'] as int;
    if (salt.length != 32 ||
        verifier.length != 32 ||
        failures < 0 ||
        failures > 30 ||
        retryAt < 0 ||
        lastAttemptAt < 0) {
      throw const FormatException();
    }
    return _Session(
      resources: resources,
      salt: salt,
      verifier: verifier,
      failures: failures,
      retryAt: retryAt,
      lastAttemptAt: lastAttemptAt,
    );
  }
}
