import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'consumer_policy_installer.dart';
import 'consumer_protection_policy.dart';
import 'consumer_update_manifest.dart';
import 'consumer_update_source.dart';
import 'consumer_update_store.dart';

export 'consumer_policy_installer.dart';
export 'consumer_update_manifest.dart';
export 'consumer_update_source.dart';
export 'consumer_update_store.dart';

enum ConsumerUpdateOutcome {
  bundled,
  restored,
  updated,
  staged,
  current,
  notConfigured,
  throttled,
  rejected,
  recoveryRequired,
}

final class ConsumerUpdateStatus {
  const ConsumerUpdateStatus({
    required this.outcome,
    required this.activeSequence,
    required this.highestSequence,
    required this.stale,
    required this.sourceConfigured,
    required this.trustConfigured,
    this.pendingSequence,
    this.errorCode,
  });
  final ConsumerUpdateOutcome outcome;
  final int activeSequence, highestSequence;
  final int? pendingSequence;
  final bool stale, sourceConfigured, trustConfigured;
  final String? errorCode;
}

/// Consumer updates have their own signature purpose, sequence and durable
/// state. Optional Guard packs and curated catalog expiration are unrelated.
class ConsumerProtectionRepository extends ChangeNotifier {
  ConsumerProtectionRepository({
    ConsumerUpdateStore? store,
    ConsumerUpdateVerifier? verifier,
    this.source,
    ConsumerPolicyInstaller? installer,
    AssetBundle? bundle,
    ConsumerProtectionPolicy? bundled,
    DateTime Function()? clock,
  }) : store =
           store ??
           (kIsWeb ? MemoryConsumerUpdateStore() : SqliteConsumerUpdateStore()),
       // Keep trusted-key injection explicit for signed fixture tests.
       // ignore: prefer_initializing_formals
       _verifier = verifier,
       installer = installer ?? const NativeConsumerPolicyInstaller(),
       _bundle = bundle ?? rootBundle,
       // ignore: prefer_initializing_formals
       _bundled = bundled,
       _clock = clock ?? DateTime.now;

  static const trustedKeyAsset = 'assets/policy/consumer_update_keys.json';
  static const checkInterval = Duration(hours: 24);
  final ConsumerUpdateStore store;
  final ConsumerUpdateSource? source;
  final ConsumerPolicyInstaller installer;
  final AssetBundle _bundle;
  final ConsumerProtectionPolicy? _bundled;
  final DateTime Function() _clock;
  ConsumerUpdateVerifier? _verifier;
  ConsumerCacheState _cache = ConsumerCacheState();
  ConsumerProtectionPolicy _policy =
      const ConsumerProtectionPolicy.unavailable();
  ConsumerProtectionPolicy get policy => _policy;
  ConsumerUpdateOutcome _outcome = ConsumerUpdateOutcome.bundled;
  String? _error;
  bool _storageAvailable = true, _closed = false;
  Future<void>? _initialization;
  Future<void> _writes = Future.value();

  ConsumerUpdateStatus get status => ConsumerUpdateStatus(
    outcome: _outcome,
    activeSequence: _policy.sequence,
    highestSequence: _cache.highestSequence,
    pendingSequence: _cache.pendingSequence,
    stale: _policy.isStale(_clock()),
    sourceConfigured: source != null,
    trustConfigured: _verifier?.configured == true,
    errorCode: _error,
  );

  Future<void> init() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    _policy = _bundled ?? await ConsumerProtectionPolicy.load(bundle: _bundle);
    try {
      if (_verifier == null) {
        final json =
            jsonDecode(await _bundle.loadString(trustedKeyAsset))
                as Map<String, dynamic>;
        if (json['schemaVersion'] != 1) {
          throw const ConsumerUpdateException('key-schema');
        }
        final keys = json['keys'] as Map<String, dynamic>;
        final decoded = {
          for (final entry in keys.entries)
            entry.key: base64Decode(entry.value as String),
        };
        if (decoded.values.any((key) => key.length != 32)) {
          throw const ConsumerUpdateException('key-format');
        }
        _verifier = ConsumerUpdateVerifier(trustedKeys: decoded, clock: _clock);
      }
      _cache = await store.load();
      _cache.validate();
    } catch (_) {
      _storageAvailable = false;
      _set(ConsumerUpdateOutcome.rejected, 'update-store-unavailable');
      return;
    }
    // A persisted signature is checked again on every process start. Only
    // native acknowledgement makes a cached generation a browsing policy.
    for (final sequence in [
      _cache.activeSequence,
      _cache.previousSequence,
    ].whereType<int>()) {
      try {
        final release = await _verifiedCached(sequence);
        final candidate = await _candidatePolicy(release);
        final prepared = await installer.prepare(release, restore: true);
        if (prepared == null) continue;
        if (!await _activateNative(prepared)) continue;
        if (sequence != _cache.activeSequence) {
          final recovered = ConsumerCacheState(
            highestSequence: _cache.highestSequence,
            activeSequence: sequence,
            pendingSequence: _cache.pendingSequence,
            lastCheck: _cache.lastCheck,
            releases: _cache.releases,
          );
          try {
            await store.write(recovered);
            _cache = recovered;
          } catch (_) {
            if (!await _recoverNative(prepared)) {
              _policy = const ConsumerProtectionPolicy.unavailable(
                'native-update-recovery',
              );
              _set(
                ConsumerUpdateOutcome.recoveryRequired,
                'native-update-recovery',
              );
            }
            rethrow;
          }
        }
        _policy = candidate;
        _set(ConsumerUpdateOutcome.restored);
        break;
      } catch (_) {
        _error = 'cached-release-rejected';
      }
    }
    if (_cache.pendingSequence != null) {
      try {
        await _accept(
          await _verifiedCached(_cache.pendingSequence!),
          restoringPending: true,
        );
      } catch (_) {
        _set(ConsumerUpdateOutcome.rejected, 'pending-release-rejected');
      }
    } else if (_policy.sequence == 1 && _cache.activeSequence != null) {
      _policy = const ConsumerProtectionPolicy.unavailable(
        'cached-native-recovery',
      );
      _set(
        ConsumerUpdateOutcome.recoveryRequired,
        'cached-release-unavailable',
      );
    } else if (!_policy.isUsable) {
      _set(
        ConsumerUpdateOutcome.recoveryRequired,
        'mandatory-baseline-unavailable',
      );
    }
  }

  Future<VerifiedConsumerUpdate> _verifiedCached(int sequence) async {
    final cached = _cache.releases[sequence];
    if (cached == null) {
      throw const ConsumerUpdateException('missing-cached-release');
    }
    final result = await _verifier!.verify(cached.envelope, cached.data);
    if (result.manifest.sequence != sequence) {
      throw const ConsumerUpdateException('cache-metadata');
    }
    return result;
  }

  Future<ConsumerProtectionPolicy> _candidatePolicy(
    VerifiedConsumerUpdate release,
  ) async {
    final value = await ConsumerProtectionPolicy.fromVerifiedUpdate(release);
    if (!value.isUsable) {
      throw ConsumerUpdateException(value.errorCode ?? 'baseline-format');
    }
    return value;
  }

  Future<ConsumerUpdateStatus> importUpdate(
    Uint8List envelope,
    Uint8List data,
  ) async {
    final envelopeCopy = Uint8List.fromList(envelope),
        dataCopy = Uint8List.fromList(data);
    await init();
    return _serialize(() async {
      try {
        if (!_storageAvailable) {
          throw const ConsumerUpdateException('update-store-unavailable');
        }
        await _accept(await _verifier!.verify(envelopeCopy, dataCopy));
      } catch (error) {
        _set(
          ConsumerUpdateOutcome.rejected,
          error is ConsumerUpdateException ? error.code : 'update-rejected',
        );
      }
      return status;
    });
  }

  Future<void> _accept(
    VerifiedConsumerUpdate release, {
    bool restoringPending = false,
  }) async {
    final sequence = release.manifest.sequence;
    final candidate = await _candidatePolicy(release);
    if (!restoringPending &&
        (sequence <= _cache.highestSequence ||
            sequence <= (_cache.pendingSequence ?? 1))) {
      throw const ConsumerUpdateException('replayed-sequence');
    }
    if (restoringPending && sequence != _cache.pendingSequence) {
      throw const ConsumerUpdateException('pending-sequence');
    }
    final retained = {
      _cache.activeSequence,
      _cache.previousSequence,
    }.whereType<int>().toSet();
    final pending = ConsumerCacheState(
      highestSequence: _cache.highestSequence,
      activeSequence: _cache.activeSequence,
      previousSequence: _cache.previousSequence,
      pendingSequence: sequence,
      lastCheck: _cache.lastCheck,
      releases: {
        for (final id in retained) id: _cache.releases[id]!,
        sequence: CachedConsumerRelease(
          release.manifest.envelope,
          release.data,
        ),
      },
    );
    await store.write(pending);
    _cache = pending;
    final prepared = await installer.prepare(
      release,
      restore: restoringPending,
    );
    if (prepared == null) {
      _set(ConsumerUpdateOutcome.staged, 'native-preparation-unavailable');
      return;
    }
    if (!await _activateNative(prepared)) {
      _set(ConsumerUpdateOutcome.staged, 'native-activation-rejected');
      return;
    }
    final previous = _cache.activeSequence;
    final committed = ConsumerCacheState(
      highestSequence: sequence > _cache.highestSequence
          ? sequence
          : _cache.highestSequence,
      activeSequence: sequence,
      previousSequence: previous,
      lastCheck: _cache.lastCheck,
      releases: {
        sequence: _cache.releases[sequence]!,
        if (previous != null && previous != sequence)
          previous: _cache.releases[previous]!,
      },
    );
    try {
      await store.write(committed);
    } catch (_) {
      if (!await _recoverNative(prepared)) {
        _policy = const ConsumerProtectionPolicy.unavailable(
          'native-update-recovery',
        );
        _set(ConsumerUpdateOutcome.recoveryRequired, 'native-update-recovery');
        return;
      }
      throw const ConsumerUpdateException('activation-commit-failed');
    }
    _cache = committed;
    _policy = candidate;
    _set(ConsumerUpdateOutcome.updated);
  }

  Future<bool> _activateNative(PreparedConsumerPolicy prepared) async {
    try {
      if (await installer.activate(prepared)) return true;
    } catch (_) {
      /* Lost activation acknowledgements require a native revert. */
    }
    final reverted = await _recoverNative(prepared);
    if (!reverted) {
      _policy = const ConsumerProtectionPolicy.unavailable(
        'native-update-recovery',
      );
      _set(ConsumerUpdateOutcome.recoveryRequired, 'native-update-recovery');
    }
    try {
      await installer.discard(prepared);
    } catch (_) {}
    return false;
  }

  Future<bool> _recoverNative(PreparedConsumerPolicy prepared) async {
    try {
      return await installer.revert(prepared);
    } catch (_) {
      return false;
    }
  }

  Future<ConsumerUpdateStatus> checkForUpdates({bool force = false}) async {
    await init();
    return _serialize(() async {
      if (source == null || _verifier?.configured != true) {
        _set(ConsumerUpdateOutcome.notConfigured);
        return status;
      }
      if (!_storageAvailable) {
        _set(ConsumerUpdateOutcome.rejected, 'update-store-unavailable');
        return status;
      }
      final now = _clock().toUtc();
      if (!force &&
          _cache.lastCheck != null &&
          now.difference(_cache.lastCheck!) < checkInterval) {
        _set(ConsumerUpdateOutcome.throttled);
        return status;
      }
      try {
        final checked = ConsumerCacheState(
          highestSequence: _cache.highestSequence,
          activeSequence: _cache.activeSequence,
          previousSequence: _cache.previousSequence,
          pendingSequence: _cache.pendingSequence,
          releases: _cache.releases,
          lastCheck: now,
        );
        await store.write(checked);
        _cache = checked;
        final manifest = await _verifier!.verifyManifest(
          await source!.fetchManifest().timeout(const Duration(seconds: 20)),
        );
        if (manifest.sequence == _cache.activeSequence) {
          final active = await _verifiedCached(manifest.sequence);
          if (manifest.sha256 != active.manifest.sha256) {
            throw const ConsumerUpdateException('sequence-equivocation');
          }
          _set(ConsumerUpdateOutcome.current);
          return status;
        }
        if (manifest.sequence == _cache.pendingSequence) {
          final pending = await _verifiedCached(manifest.sequence);
          if (manifest.sha256 != pending.manifest.sha256) {
            throw const ConsumerUpdateException('sequence-equivocation');
          }
          await _accept(pending, restoringPending: true);
          return status;
        }
        if (manifest.sequence <= _cache.highestSequence) {
          throw const ConsumerUpdateException('replayed-sequence');
        }
        final release = await _verifier!.verifyData(
          manifest,
          await source!
              .fetchData(manifest)
              .timeout(const Duration(seconds: 60)),
        );
        await _accept(release);
      } catch (error) {
        _set(
          ConsumerUpdateOutcome.rejected,
          error is ConsumerUpdateException ? error.code : 'update-unavailable',
        );
      }
      return status;
    });
  }

  void _set(ConsumerUpdateOutcome outcome, [String? error]) {
    // An uncertain native rollback cannot be downgraded to ordinary rejection.
    if (!_policy.isUsable) {
      outcome = ConsumerUpdateOutcome.recoveryRequired;
    }
    _outcome = outcome;
    _error = error ?? (_policy.isUsable ? null : _policy.errorCode);
    if (!_closed) notifyListeners();
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    if (_closed) {
      return Future.error(StateError('Consumer update repository is closed.'));
    }
    final result = _writes.then((_) => operation());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _writes;
    await store.close();
    super.dispose();
  }
}
