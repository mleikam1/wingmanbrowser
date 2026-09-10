import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:wingman_browser/guard/guard_runtime.dart';

final testTime = DateTime.utc(2026, 9, 10);

Map<String, Object?> testRule(
  String host, {
  String category = 'adult',
  String kind = 'category',
  String? id,
  bool includeSubdomains = true,
}) => {
  'host': host,
  'category': category,
  'kind': kind,
  'id': id ?? host.replaceAll('.', '-'),
  'includeSubdomains': includeSubdomains,
};

class TestSigner {
  TestSigner._(this.key, this.verifier);
  final SimpleKeyPair key;
  final FilterManifestVerifier verifier;
  static Future<TestSigner> create() async {
    final key = await Ed25519().newKeyPair();
    return TestSigner._(
      key,
      FilterManifestVerifier(
        trustedKeys: {'unit-test-only': (await key.extractPublicKey()).bytes},
        clock: () => testTime,
      ),
    );
  }

  Future<({Uint8List manifest, Uint8List pack})> sign(
    List<Map<String, Object?>> records, {
    int sequence = 1,
    Map<String, Object?> metadata = const {},
    Map<String, Object?> packMetadata = const {},
  }) async {
    final pack = Uint8List.fromList(
      utf8.encode('${records.map(jsonEncode).join('\n')}\n'),
    );
    final canonical =
        records
            .map(
              (r) => [
                r['host'],
                r['kind'],
                r['category'] ?? '',
                r['includeSubdomains'] == true ? 1 : 0,
                r['id'],
              ],
            )
            .toList()
          ..sort((a, b) {
            for (var i = 0; i < 3; i++) {
              final order = (a[i] as String).compareTo(b[i] as String);
              if (order != 0) return order;
            }
            return 0;
          });
    Future<String> digest(List<int> bytes) async => (await Sha256().hash(
      bytes,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final payload = utf8.encode(
      jsonEncode({
        'schema': 1,
        'version': '1.0.$sequence',
        'sequence': sequence,
        'createdAt': testTime.toIso8601String(),
        'minimumAppVersion': '0.1.0',
        'packs': [
          {
            'filename': 'test.ndjson',
            'sha256': await digest(pack),
            'rulesSha256': await digest(
              utf8.encode('${canonical.map(jsonEncode).join('\n')}\n'),
            ),
            'bytes': pack.length,
            'rules': records.length,
            'license': 'CC0-1.0',
            ...packMetadata,
          },
        ],
        ...metadata,
      }),
    );
    final signature = await Ed25519().sign(payload, keyPair: key);
    return (
      manifest: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'keyId': 'unit-test-only',
            'payload': base64Encode(payload),
            'signature': base64Encode(signature.bytes),
          }),
        ),
      ),
      pack: pack,
    );
  }
}

class MemoryRules implements FilterPackRepository {
  MemoryRules([this.rules = const []]);
  final List<GuardRuleMatch> rules;
  bool fail = false;
  bool? lastUseCache;
  @override
  FilterPackStatus get status =>
      const FilterPackStatus(version: 'test', integrityVerified: true);
  @override
  String? get activeDatabasePath => null;
  @override
  Future<void> init() async {}
  @override
  Future<List<GuardRuleMatch>> lookupHost(
    String host, {
    bool useCache = true,
  }) async {
    lastUseCache = useCache;
    if (fail) throw StateError('unavailable');
    return rules
        .where(
          (r) =>
              r.host == host ||
              r.includeSubdomains && DomainNormalizer.matches(host, r.host),
        )
        .toList();
  }

  @override
  void clearCache() {}
  @override
  Future<void> close() async {}
  @override
  Future<bool> rollback() async => false;
  @override
  Future<FilterUpdateResult> checkForUpdates({bool force = false}) async =>
      const FilterUpdateResult(FilterUpdateOutcome.notConfigured);
  @override
  Future<FilterPackStatus> importVerified(Uint8List m, Uint8List p) async =>
      status;
}
