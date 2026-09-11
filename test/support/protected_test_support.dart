import 'dart:io';
import 'package:flutter/services.dart';
import 'package:wingman_browser/data/browser_repository.dart';
import 'package:wingman_browser/domain/models.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';

class LocalCatalogBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

class MemoryTrust implements PolicyCheckpointStore {
  PolicyCheckpoint checkpoint = PolicyCheckpoint();
  @override
  Future<PolicyCheckpoint> load() async => checkpoint;
  @override
  Future<void> save(PolicyCheckpoint value) async {
    checkpoint = value;
  }

  @override
  Future<void> close() async {}
}

class MemoryBrowserRepository implements BrowserRepository {
  MemoryBrowserRepository({this.data = const BrowserData()});
  BrowserData data;
  BrowserSettings? saved;
  bool failSaves = false;
  @override
  Future<BrowserData> load() async => data;
  @override
  Future<void> saveSettings(BrowserSettings value) async {
    if (failSaves) throw StateError('PRIVATE_SQL_DETAIL');
    saved = value;
  }

  @override
  Future<void> saveSession(List<BrowserTab> tabs, String activeId) async {}
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<PolicyRuntime> loadTestPolicy({DateTime Function()? clock}) =>
    PolicyRuntime.initialize(
      repository: SignedPolicyRepository(
        bundle: LocalCatalogBundle(),
        clock: PolicyClock(
          wallClock: clock ?? () => DateTime.utc(2026, 9, 10, 12),
        ),
      ),
      checkpointStore: MemoryTrust(),
    );
