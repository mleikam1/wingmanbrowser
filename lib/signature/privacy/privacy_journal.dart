import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'privacy_models.dart';
import 'trust_receipt.dart';

export 'privacy_models.dart';
export 'trust_receipt.dart';

class PrivacyEventToken {
  PrivacyEventToken._(this._owner, this._event);
  final PrivacyJournal _owner;
  PrivacyEvent _event;
}

/// Optional feature instrumentation, never a complete browsing recorder.
/// The caller supplies a shared document-store namespace for normal sessions.
class PrivacyJournal extends ChangeNotifier {
  PrivacyJournal({
    required this.sessionKind,
    Map<String, Object?>? initialState,
    bool restorationFailed = false,
    bool awaitingRestoration = false,
    Future<void> Function(Map<String, Object?> state)? persist,
    DateTime Function()? clock,
  }) : _persist = sessionKind == PrivacySessionKind.normal ? persist : null,
       _hydrationPending = awaitingRestoration,
       _clock = clock ?? DateTime.now {
    if (awaitingRestoration) {
      _storageStatus = sessionKind == PrivacySessionKind.normal
          ? JournalStorageStatus.restoring
          : JournalStorageStatus.memoryOnly;
    } else if (sessionKind == PrivacySessionKind.normal && restorationFailed) {
      _restorationUnknown = true;
      _storageStatus = JournalStorageStatus.invalidState;
    } else if (sessionKind == PrivacySessionKind.normal &&
        initialState != null) {
      _restore(initialState);
    }
    if (!awaitingRestoration &&
        _storageStatus != JournalStorageStatus.invalidState) {
      _storageStatus = _persist == null
          ? JournalStorageStatus.memoryOnly
          : JournalStorageStatus.saved;
      if (_persist != null && initialState != null) _changed();
    }
    if (!awaitingRestoration) _hydrated.complete();
    _retentionTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (!_closed && _prune()) _changed();
    });
  }

  static const maximumEvents = 200;
  static const retention = Duration(days: 14);
  static const maximumStateBytes = 65536;
  final PrivacySessionKind sessionKind;
  Future<void> Function(Map<String, Object?> state)? _persist;
  final DateTime Function() _clock;
  final List<PrivacyEvent> _events = [];
  Future<void> _writes = Future.value();
  Map<String, Object?>? _pendingSnapshot;
  int _pendingRevision = 0;
  bool _writing = false;
  JournalStorageStatus _storageStatus = JournalStorageStatus.memoryOnly;
  bool _closed = false;
  int _revision = 0;
  bool _restorationUnknown = false;
  bool _hydrationPending;
  bool _clearBeforeHydration = false;
  final Completer<void> _hydrated = Completer<void>();
  Timer? _retentionTimer;

  JournalStorageStatus get storageStatus => _storageStatus;

  /// Completes the one startup read without replacing this journal or its
  /// in-flight event tokens. Current-session events remain current-session
  /// observations; only previously stored pending events become interrupted.
  void hydrate({
    Map<String, Object?>? initialState,
    bool restorationFailed = false,
    Future<void> Function(Map<String, Object?> state)? persist,
  }) {
    if (_closed || !_hydrationPending) return;
    final currentEvents = List<PrivacyEvent>.of(_events);
    _events.clear();
    _persist = sessionKind == PrivacySessionKind.normal ? persist : null;
    if (sessionKind == PrivacySessionKind.normal && !_clearBeforeHydration) {
      if (restorationFailed) {
        _restorationUnknown = true;
      } else if (initialState != null) {
        _restore(initialState);
      }
    }
    _events.addAll(currentEvents);
    _hydrationPending = false;
    _storageStatus = _restorationUnknown
        ? JournalStorageStatus.invalidState
        : _persist == null
        ? JournalStorageStatus.memoryOnly
        : JournalStorageStatus.saved;
    _hydrated.complete();
    _changed();
  }

  List<PrivacyEvent> get events {
    final now = _hour(_clock());
    return List.unmodifiable(
      _events.where(
        (event) =>
            !event.hour.isBefore(now.subtract(retention)) &&
            !event.hour.isAfter(now),
      ),
    );
  }

  PrivacyEventToken record(
    PrivacyActivity activity,
    PrivacyOutcome outcome, {
    PrivacyDestination destination = PrivacyDestination.local,
  }) {
    if (_closed) throw StateError('This journal session has closed.');
    if (!validPrivacyDestination(activity, destination)) {
      throw ArgumentError('Activity and processing destination disagree.');
    }
    if ((activity == PrivacyActivity.handoffStarted ||
            activity == PrivacyActivity.handoffEnded) &&
        sessionKind != PrivacySessionKind.handoff) {
      throw ArgumentError(
        'Handoff activity requires a separate handoff journal.',
      );
    }
    final event = PrivacyEvent(
      activity: activity,
      outcome: outcome,
      destination: destination,
      hour: _hour(_clock()),
    );
    _events.add(event);
    _changed();
    return PrivacyEventToken._(this, event);
  }

  PrivacyEventToken begin(
    PrivacyActivity activity, {
    PrivacyDestination destination = PrivacyDestination.local,
    bool queued = false,
  }) => record(
    activity,
    queued ? PrivacyOutcome.queued : PrivacyOutcome.started,
    destination: destination,
  );

  void finish(PrivacyEventToken token, PrivacyOutcome outcome) {
    if (_closed || !identical(token._owner, this)) return;
    if (token._event.outcome != PrivacyOutcome.queued &&
        token._event.outcome != PrivacyOutcome.started) {
      return;
    }
    if (outcome == PrivacyOutcome.queued) return;
    final index = _events.indexOf(token._event);
    if (index < 0) return;
    final next = token._event.withOutcome(outcome);
    _events[index] = next;
    token._event = next;
    _changed();
  }

  TrustReceipt receipt(PrivacyConfiguration configuration) => TrustReceipt(
    sessionKind: sessionKind,
    generatedAt: _hour(_clock()),
    configuration: configuration,
    events: events,
    storageStatus: storageStatus,
  );

  Future<void> clear() async {
    if (_closed) return;
    _events.clear();
    _restorationUnknown = false;
    if (_hydrationPending) _clearBeforeHydration = true;
    _storageStatus =
        _hydrationPending && sessionKind == PrivacySessionKind.normal
        ? JournalStorageStatus.restoring
        : _persist == null
        ? JournalStorageStatus.memoryOnly
        : JournalStorageStatus.pending;
    _changed();
    await _hydrated.future;
    await flush();
  }

  Future<void> flush() => _writes;

  void _changed() {
    _prune();
    final revision = ++_revision;
    final persist = _persist;
    if (persist != null && !_restorationUnknown && !_hydrationPending) {
      _storageStatus = JournalStorageStatus.pending;
      _pendingSnapshot = <String, Object?>{
        'schema': 1,
        'events': _events.map((e) => e.toJson()).toList(),
      };
      _pendingRevision = revision;
      if (!_writing) {
        _writing = true;
        _writes = _drainWrites(persist);
      }
    }
    if (!_closed) notifyListeners();
  }

  Future<void> _drainWrites(
    Future<void> Function(Map<String, Object?>) persist,
  ) async {
    // At most one write and one latest snapshot exist even if storage stalls.
    // A later clear is always the final snapshot, never reordered behind data.
    while (_pendingSnapshot != null) {
      final snapshot = _pendingSnapshot!;
      final revision = _pendingRevision;
      _pendingSnapshot = null;
      try {
        await persist(snapshot);
        if (revision == _revision) {
          _storageStatus = JournalStorageStatus.saved;
        }
      } catch (_) {
        if (revision == _revision) {
          _storageStatus = JournalStorageStatus.failed;
        }
      }
      if (!_closed) notifyListeners();
    }
    _writing = false;
  }

  bool _prune() {
    final before = _events.length;
    final now = _hour(_clock());
    _events.removeWhere(
      (event) =>
          event.hour.isBefore(now.subtract(retention)) ||
          event.hour.isAfter(now),
    );
    if (_events.length > maximumEvents) {
      _events.removeRange(0, _events.length - maximumEvents);
    }
    return _events.length != before;
  }

  void _restore(Map<String, Object?> state) {
    try {
      if (utf8.encode(jsonEncode(state)).length > maximumStateBytes ||
          state.length != 2 ||
          state['schema'] != 1 ||
          state['events'] is! List) {
        throw const FormatException();
      }
      final rows = state['events'] as List;
      if (rows.length > maximumEvents) throw const FormatException();
      for (final row in rows) {
        if (row is! Map || row.length != 4 || row['hour'] is! int) {
          throw const FormatException();
        }
        final activity = PrivacyActivity.values.byName(
          row['activity'] as String,
        );
        final destination = PrivacyDestination.values.byName(
          row['destination'] as String,
        );
        var outcome = PrivacyOutcome.values.byName(row['outcome'] as String);
        final hour = DateTime.fromMillisecondsSinceEpoch(
          row['hour'] as int,
          isUtc: true,
        );
        if (activity == PrivacyActivity.handoffStarted ||
            activity == PrivacyActivity.handoffEnded ||
            !validPrivacyDestination(activity, destination) ||
            hour != _hour(hour)) {
          throw const FormatException();
        }
        if (outcome == PrivacyOutcome.queued ||
            outcome == PrivacyOutcome.started) {
          outcome = PrivacyOutcome.interrupted;
        }
        _events.add(
          PrivacyEvent(
            activity: activity,
            outcome: outcome,
            destination: destination,
            hour: hour,
          ),
        );
      }
      _prune();
    } catch (_) {
      _events.clear();
      _restorationUnknown = true;
      _storageStatus = JournalStorageStatus.invalidState;
    }
  }

  static DateTime _hour(DateTime date) {
    final utc = date.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day, utc.hour);
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    if (!_hydrated.isCompleted) _hydrated.complete();
    _retentionTimer?.cancel();
    _events.clear();
    super.dispose();
  }
}
