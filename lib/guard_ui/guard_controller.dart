import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../guard/guard_runtime.dart';
import '../guard_pin/guard_pin_service.dart';
import '../state/browser_state.dart';

/// Owns local preferences and short-lived grants. No navigation URL is stored
/// here or sent to a service. Private activity never contributes to saved stats.
enum _GuardProblem { preferences, tracking, pack, sync, storage, operation }

class GuardController extends ChangeNotifier {
  GuardController({
    required this.state,
    required this.runtime,
    required this.pin,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final BrowserState state;
  final GuardRuntime runtime;
  final GuardPinService pin;
  final DateTime Function() _clock;
  GuardConfiguration _configuration = GuardConfiguration();
  GuardConfiguration get configuration => _configuration;
  final Map<_GuardProblem, String> _problems = {};
  String? get problem => _GuardProblem.values
      .map((kind) => _problems[kind])
      .whereType<String>()
      .firstOrNull;
  int _policyRevision = 0;
  static const _maximumDecisionAttempts = 3;

  void _setProblem(_GuardProblem kind, String? message) {
    if (_problems[kind] == message) return;
    if (message == null) {
      _problems.remove(kind);
    } else {
      _problems[kind] = message;
    }
    _notify();
  }

  void _refreshPackProblem() => _setProblem(
    _GuardProblem.pack,
    pack.integrityVerified
        ? null
        : 'No verified category pack is available. Native browser security still applies.',
  );
  bool _disposed = false;
  bool requestSetup = false;
  final Set<String> trackingExceptions = {};
  final Map<String, Map<String, DateTime>> _grants = {};
  List<String> _trackers = [];
  String _trackerVersion = '';
  String _day = '';
  int trackersToday = 0, riskyToday = 0, guardToday = 0;
  Timer? _timer;
  Future<void> _saveQueue = Future.value();
  Future<void> Function(Map<String, Object?> policy, bool recheck)? applyNative;

  bool get locked => pin.isLocked;
  bool get focusActive => configuration.focusActive(_clock());
  FilterPackStatus get pack => runtime.repository.status;
  GuardConfiguration get effective =>
      configuration.copyWith(overridesAllowed: !locked);

  Future<void> initialize() async {
    try {
      _configuration = GuardConfiguration.fromJson(
        Map<String, Object?>.from(jsonDecode(state.settings.guardJson) as Map),
      );
    } catch (_) {
      _setProblem(
        _GuardProblem.preferences,
        'Saved Guard preferences could not be read.',
      );
    }
    try {
      final saved = jsonDecode(state.settings.guardStatsJson) as Map;
      _day = saved['day'] as String? ?? '';
      int count(String key) =>
          (saved[key] is int ? saved[key] as int : 0).clamp(0, 1000000000);
      trackersToday = count('trackers');
      riskyToday = count('risky');
      guardToday = count('guard');
    } catch (_) {
      /* Statistics are disposable, never policy. */
    }
    _rollDay();
    try {
      final data =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/guard_tracking/starter.json',
                ),
              )
              as Map;
      _trackers = (data['domains'] as List).cast<String>();
      _trackerVersion = data['version'] as String;
    } catch (_) {
      _setProblem(
        _GuardProblem.tracking,
        'The tracking rules could not be loaded.',
      );
    }
    await pin.initialize();
    pin.addListener(_pinChanged);
    _policyRevision++;
    _refreshPackProblem();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      final expired = configuration.focusExpiresAt != null && !focusActive;
      if (expired) {
        _configuration = configuration.copyWith(clearFocus: true);
        _policyRevision++;
        _background(_persist());
        _background(sync(recheck: true));
      }
      if (_expireGrants()) _background(sync());
      if (_rollDay()) _background(_persistStats());
      _notify();
    });
    _background(_checkBackgroundUpdate());
  }

  Future<void> _checkBackgroundUpdate() async {
    final result = await runtime.repository.checkForUpdates();
    if (result.outcome == FilterUpdateOutcome.updated) {
      _policyRevision++;
      _refreshPackProblem();
      await sync(recheck: true);
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _background(Future<void> operation) {
    unawaited(
      operation.catchError((Object _) {
        if (problem == null) {
          _setProblem(
            _GuardProblem.operation,
            'A local Guard operation could not finish. Review protection status.',
          );
        }
        _notify();
      }),
    );
  }

  void _pinChanged() {
    _policyRevision++;
    if (locked) _grants.clear();
    _background(sync(recheck: true));
    _notify();
  }

  Future<void> update(GuardConfiguration next) async {
    if (locked) throw StateError('Unlock Family settings first.');
    if (next.customAllow.length > 200 ||
        next.customBlock.length > 200 ||
        next.focusHosts.length > 200) {
      throw StateError('Each site list supports up to 200 entries.');
    }
    _configuration = next;
    _policyRevision++;
    _grants.clear();
    await sync(recheck: true);
    await _persist();
    _notify();
  }

  Future<void> _persist() => _queue(() async {
    state.saveSettings(
      state.settings.copyWith(guardJson: jsonEncode(configuration.toJson())),
    );
    await state.flush();
    if (state.storageError != null) {
      _setProblem(
        _GuardProblem.storage,
        'Guard changed for this session, but local storage could not save it.',
      );
      _notify();
      throw StateError(
        'Guard changed for this session, but local storage could not save it.',
      );
    }
    _setProblem(_GuardProblem.storage, null);
    _setProblem(_GuardProblem.preferences, null);
  });

  Future<void> _queue(Future<void> Function() work) {
    final next = _saveQueue.then((_) => work());
    _saveQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> addRule(String input, {required bool allow}) async {
    if (locked) throw StateError('Unlock Family settings first.');
    final host = await runtime.normalizer.normalize(input);
    final hosts = Set<String>.of(
      allow ? configuration.customAllow : configuration.customBlock,
    );
    if (hosts.length >= 200 && !hosts.contains(host)) {
      throw StateError('Each list supports up to 200 sites.');
    }
    hosts.add(host);
    await update(
      allow
          ? configuration.copyWith(customAllow: hosts)
          : configuration.copyWith(customBlock: hosts),
    );
  }

  Future<GuardDecision> evaluate(GuardRequest request) async {
    String? host;
    for (var attempt = 0; attempt < _maximumDecisionAttempts; attempt++) {
      _expireGrants();
      final revision = _policyRevision;
      final selected = configuration;
      final wasLocked = locked;
      final focusWasActive = focusActive;
      final packSnapshot = (
        pack.generation,
        pack.version,
        pack.integrityVerified,
      );
      bool current() =>
          !_disposed &&
          revision == _policyRevision &&
          identical(selected, configuration) &&
          wasLocked == locked &&
          focusWasActive == focusActive &&
          packSnapshot ==
              (pack.generation, pack.version, pack.integrityVerified);
      try {
        host = await runtime.normalizer.normalizeUri(request.uri);
      } catch (_) {
        host = null; // The core policy supplies the invalid-domain decision.
      }
      _expireGrants();
      if (!current()) continue;
      final decision = await runtime.policy.evaluate(
        GuardRequest(
          uri: request.uri,
          tabId: request.tabId,
          navigationId: request.navigationId,
          isPrivate: request.isPrivate,
          isDownload: request.isDownload,
          suggestedFilename: request.suggestedFilename,
          mimeType: request.mimeType,
          hasAllowOnceGrant:
              !request.isDownload &&
              (_grants[request.tabId]?.containsKey(host) ?? false),
        ),
        selected.copyWith(overridesAllowed: !wasLocked),
      );
      // A lock, setting change, pack swap, completion or elapsed grant must
      // invalidate work that was already awaiting IDNA/SQLite/native callbacks.
      _expireGrants();
      if (current()) return decision;
    }
    return GuardDecision(
      action: GuardAction.requireAdditionalCheck,
      host: host ?? '',
      ruleId: 'policy-changed',
      overrideAllowed: false,
    );
  }

  Future<void> allowOnce(String tabId, GuardDecision decision) async {
    if (locked || !decision.overrideAllowed || decision.isSecurityBlock) {
      throw StateError('This block cannot be overridden.');
    }
    _policyRevision++;
    (_grants[tabId] ??= {})[decision.host] = _clock().add(
      const Duration(minutes: 5),
    );
    await sync();
  }

  Future<void> alwaysAllow(GuardDecision decision) async {
    if (locked || !decision.overrideAllowed || decision.isSecurityBlock) {
      throw StateError('This block cannot be overridden.');
    }
    // Remove an exact block only. A specific allow must preserve parent blocks
    // protecting sibling sites; the core/native policy resolves specificity.
    final blocked = configuration.customBlock
        .where((host) => decision.host != host)
        .toSet();
    await update(
      configuration.copyWith(
        customAllow: {...configuration.customAllow, decision.host},
        customBlock: blocked,
      ),
    );
  }

  void navigationCompleted(String tabId) {
    if (_grants.remove(tabId) != null) {
      _policyRevision++;
      _background(sync());
    }
  }

  void forgetTab(String tabId) => navigationCompleted(tabId);
  bool _expireGrants() {
    var changed = false;
    for (final grants in _grants.values) {
      grants.removeWhere((_, expiry) {
        final expired = !expiry.isAfter(_clock());
        changed = changed || expired;
        return expired;
      });
    }
    _grants.removeWhere((_, grants) => grants.isEmpty);
    if (changed) _policyRevision++;
    return changed;
  }

  Uri safeSearch(Uri uri) => runtime.safeSearch.apply(
    uri,
    adultFilteringEnabled: configuration.adultFilteringEnabled,
  );

  Future<void> pauseTracking(String input) async {
    if (locked) throw StateError('Unlock Family settings first.');
    final host = await runtime.normalizer.normalize(input);
    if (locked) throw StateError('Unlock Family settings first.');
    if (!trackingExceptions.remove(host)) trackingExceptions.add(host);
    _policyRevision++;
    await sync(recheck: false);
    _notify();
  }

  Map<String, Object?> get nativePolicy => {
    'databasePath': runtime.repository.activeDatabasePath,
    'guardEnabled': configuration.guardEnabled,
    'enabledCategories': configuration.enabledCategories
        .map((c) => c.id)
        .toList(),
    'customAllow': configuration.customAllow.toList(),
    'customBlock': configuration.customBlock.toList(),
    'focusHosts': configuration.focusHosts.toList(),
    'focusCategories': configuration.focusCategories.map((c) => c.id).toList(),
    'focusUntilEpochMs': configuration.focusExpiresAt?.millisecondsSinceEpoch,
    'overridesLocked': locked,
    'allowOnce': _grants.map(
      (tab, hosts) => MapEntry(tab, hosts.keys.toList()),
    ),
    'allowOnceExpires': _grants.map(
      (tab, hosts) => MapEntry(
        tab,
        hosts.map(
          (host, expiry) => MapEntry(host, expiry.millisecondsSinceEpoch),
        ),
      ),
    ),
    'blockHarmfulDownloads': configuration.dangerousDownloadProtection,
    'trackingEnabled': configuration.trackingProtection,
    'trackingExceptions': trackingExceptions.toList(),
    'trackerDomains': _trackers,
    'trackerVersion': _trackerVersion,
  };

  Future<void> sync({bool recheck = false}) async {
    _expireGrants();
    _refreshPackProblem();
    final apply = applyNative;
    if (apply == null) return;
    try {
      await apply(nativePolicy, recheck);
      _setProblem(_GuardProblem.sync, null);
    } catch (_) {
      _setProblem(
        _GuardProblem.sync,
        'Guard could not update a browser view. Close that tab and reopen it.',
      );
      _notify();
      rethrow;
    }
  }

  void recordBlock(GuardDecision decision, bool isPrivate) {
    if (isPrivate || !decision.isBlocked) return;
    _rollDay();
    if (decision.isSecurityBlock ||
        decision.category == GuardCategory.harmfulDownloads) {
      riskyToday++;
    } else {
      guardToday++;
    }
    _background(_persistStats());
    _notify();
  }

  void recordTrackers(int count, bool isPrivate) {
    if (isPrivate || count <= 0) return;
    _rollDay();
    trackersToday += count;
    _background(_persistStats());
    _notify();
  }

  bool _rollDay() {
    final now = _clock();
    final day = '${now.year}-${now.month}-${now.day}';
    if (_day == day) return false;
    _day = day;
    trackersToday = riskyToday = guardToday = 0;
    return true;
  }

  Future<void> _persistStats() => _queue(() async {
    state.saveSettings(
      state.settings.copyWith(
        guardStatsJson: jsonEncode({
          'day': _day,
          'trackers': trackersToday,
          'risky': riskyToday,
          'guard': guardToday,
        }),
      ),
    );
    await state.flush();
  });
  Future<void> resetStatistics() async {
    trackersToday = riskyToday = guardToday = 0;
    await _persistStats();
    _notify();
  }

  Future<FilterUpdateResult> checkUpdates() async {
    final result = await runtime.repository.checkForUpdates(force: true);
    if (result.outcome == FilterUpdateOutcome.updated) _policyRevision++;
    _refreshPackProblem();
    await sync(recheck: true);
    _notify();
    return result;
  }

  Future<bool> rollback() async {
    if (locked) throw StateError('Unlock Family settings first.');
    final changed = await runtime.repository.rollback();
    if (changed) _policyRevision++;
    _refreshPackProblem();
    await sync(recheck: true);
    _notify();
    return changed;
  }

  @override
  void dispose() {
    _disposed = true;
    _policyRevision++;
    _timer?.cancel();
    pin.removeListener(_pinChanged);
    applyNative = null;
    super.dispose();
  }
}
