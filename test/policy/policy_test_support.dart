import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';

final policyTestTime = DateTime.utc(2026, 9, 10, 12);

class PolicyFixtureBundle extends CachingAssetBundle {
  PolicyFixtureBundle(this.files);
  final Map<String, Uint8List> files;
  Future<void> Function(String)? beforeRead;
  bool sliced = false;
  @override
  Future<ByteData> load(String key) async {
    await beforeRead?.call(key);
    final bytes = files[key];
    if (bytes == null) throw StateError('Fixture asset absent');
    if (sliced) {
      final padded = Uint8List(bytes.length + 6)
        ..setRange(3, bytes.length + 3, bytes);
      return ByteData.view(padded.buffer, 3, bytes.length);
    }
    return ByteData.sublistView(bytes);
  }
}

class PolicyFixture {
  PolicyFixture._(this.key);
  final SimpleKeyPair key;
  static Future<PolicyFixture> create() async =>
      PolicyFixture._(await Ed25519().newKeyPair());
  Future<SignedPolicyVerifier> verifier() async => SignedPolicyVerifier(
    trustedKeys: {'fixture-only': (await key.extractPublicKey()).bytes},
  );
  Future<PolicyFixtureBundle> bundle({
    int sequence = 1,
    List<String> revoked = const [],
    Map<String, Object?> catalogOverrides = const {},
    Map<String, Object?> recordOverrides = const {},
  }) async {
    final body = Uint8List.fromList(
      utf8.encode(
        List.filled(
          8,
          'A reviewed lesson explains how a seed uses stored energy to grow toward light. Observation and careful notes help compare changes.',
        ).join('\n\n'),
      ),
    );
    final catalog = <String, Object?>{
      'schema': 1,
      'policyVersion': 1,
      'version': '1.0.$sequence',
      'sequence': sequence,
      'reviewedAt': DateTime.utc(2026, 9, 10).toIso8601String(),
      'expiresAt': DateTime.utc(2027, 3, 10).toIso8601String(),
      'reviewer': 'Independent synthetic test reviewer',
      'license': 'CC0-1.0',
      'revokedIds': revoked,
      'resources': [
        <String, Object?>{
          'id': 'seed-science',
          'title': 'Seed science',
          'summary': 'Observe germination without a remote page.',
          'collection': 'science',
          'capability': 'bundledPlainText',
          'assetPath': 'assets/policy/articles/seed-science.txt',
          'sha256': await policyDigest(body),
          'byteLength': body.length,
          'contexts': ['general', 'student'],
          'sourceUrls': ['https://science.example.test/review'],
          ...recordOverrides,
        },
      ],
      ...catalogOverrides,
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(catalog)));
    final payload = utf8.encode(
      jsonEncode({
        'schema': 1,
        'policyVersion': 1,
        'capability': 'bundledPlainText',
        'version': catalog['version'],
        'sequence': catalog['sequence'],
        'catalogBytes': bytes.length,
        'catalogSha256': await policyDigest(bytes),
        'resourceCount': 1,
      }),
    );
    final sig = await Ed25519().sign(payload, keyPair: key);
    return PolicyFixtureBundle({
      'assets/policy/catalog.json': bytes,
      'assets/policy/manifest.json': Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'keyId': 'fixture-only',
            'payload': base64Encode(payload),
            'signature': base64Encode(sig.bytes),
          }),
        ),
      ),
      'assets/policy/public_keys.json': Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'fixture-only': base64Encode((await key.extractPublicKey()).bytes),
          }),
        ),
      ),
      'assets/policy/articles/seed-science.txt': body,
    });
  }
}
