import 'dart:typed_data';

import 'guard_models.dart';

enum FilterUpdateOutcome {
  updated,
  current,
  throttled,
  notConfigured,
  rejected,
}

class FilterUpdateResult {
  const FilterUpdateResult(this.outcome, {this.status});
  final FilterUpdateOutcome outcome;
  final FilterPackStatus? status;
}

abstract interface class FilterPackRepository {
  Future<void> init();
  FilterPackStatus get status;
  String? get activeDatabasePath;
  Future<List<GuardRuleMatch>> lookupHost(
    String normalizedHost, {
    bool useCache = true,
  });
  void clearCache();
  Future<FilterPackStatus> importVerified(
    Uint8List manifestBytes,
    Uint8List packBytes,
  );
  Future<FilterUpdateResult> checkForUpdates({bool force = false});
  Future<bool> rollback();
  Future<void> close();
}

/// A control-plane transport only. Its methods never accept navigation URLs.
/// The signed manifest supplies a constrained filename and maximum byte count.
abstract interface class FilterPackUpdateSource {
  Future<Uint8List> fetchManifest();
  Future<Uint8List> fetchPack(String filename, int maximumBytes);
}
