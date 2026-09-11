import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../guard/guard_runtime.dart';
import '../guard_pin/guard_pin_service.dart';
import '../policy/legacy_settings_migration.dart';
import '../state/browser_state.dart';

/// Retired API compatibility. It cannot grant access to any live destination.
/// The production shell uses the independent mandatory PolicyRuntime.
class GuardController extends ChangeNotifier {
  GuardController({
    required this.state,
    required this.runtime,
    required this.pin,
    DateTime Function()? clock,
  });
  final BrowserState state;
  final GuardRuntime runtime;
  final GuardPinService pin;
  GuardConfiguration _configuration = GuardConfiguration();
  GuardConfiguration get configuration => _configuration;
  GuardConfiguration get effective => configuration;
  bool get locked => pin.isLocked;
  bool get focusActive => false;
  FilterPackStatus get pack => runtime.repository.status;
  String? get problem => pack.integrityVerified
      ? null
      : 'Live content is unavailable under the mandatory policy.';
  bool requestSetup = false;
  int get trackersToday => 0;
  int get riskyToday => 0;
  int get guardToday => 0;
  Set<String> get trackingExceptions => const {};
  Future<void> Function(Map<String, Object?>, bool)? applyNative;
  Future<void> initialize() async {
    _configuration = GuardConfiguration.fromJson(
      Map<String, Object?>.from(
        jsonDecode(retireLegacyGuardSettings(state.settings.guardJson)) as Map,
      ),
    );
  }

  Future<void> update(GuardConfiguration next) async {
    if (locked) throw StateError('Additional settings are locked.');
    _configuration = GuardConfiguration(
      customBlock: next.customBlock,
      enabledCategories: next.enabledCategories.where((c) => c.isFocus).toSet(),
    );
    state.saveSettings(
      state.settings.copyWith(
        guardJson: retireLegacyGuardSettings(
          jsonEncode(_configuration.toJson()),
        ),
      ),
    );
    await state.flush();
    await sync(recheck: true);
    notifyListeners();
  }

  Future<GuardDecision> evaluate(GuardRequest request) =>
      runtime.policy.evaluate(request, configuration);
  Future<void> addRule(String input, {required bool allow}) async {
    if (allow) throw StateError('Mandatory protection has no allowlist.');
    final host = await runtime.normalizer.normalize(input);
    await update(
      configuration.copyWith(customBlock: {...configuration.customBlock, host}),
    );
  }

  Future<void> allowOnce(String tabId, GuardDecision decision) async =>
      throw StateError('Mandatory protection cannot be overridden.');
  Future<void> alwaysAllow(GuardDecision decision) async =>
      throw StateError('Mandatory protection cannot be overridden.');
  Future<void> pauseTracking(String input) async =>
      throw StateError('Live content is unavailable.');
  void navigationCompleted(String tabId) {}
  void forgetTab(String tabId) {}
  void recordBlock(GuardDecision decision, bool isPrivate) {}
  void recordTrackers(int count, bool isPrivate) {}
  Future<void> resetStatistics() async {}
  Uri safeSearch(Uri uri) => uri; // No external search path is authorized.
  Map<String, Object?> get nativePolicy => const {
    'mandatoryPolicyVersion': 1,
    'liveContentSupported': false,
    'overridesLocked': true,
  };
  Future<void> sync({bool recheck = false}) async =>
      applyNative?.call(nativePolicy, recheck);
  Future<FilterUpdateResult> checkUpdates() async =>
      const FilterUpdateResult(FilterUpdateOutcome.notConfigured);
  Future<bool> rollback() async => false;
}
