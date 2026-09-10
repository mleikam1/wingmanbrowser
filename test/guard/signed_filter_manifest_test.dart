import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/guard/guard_runtime.dart';
import 'guard_test_support.dart';

void main() {
  late TestSigner signer;
  setUp(() async {
    signer = await TestSigner.create();
  });
  test('exact signed bytes and app compatibility bind metadata', () async {
    final signed = await signer.sign([testRule('example.test')]);
    final manifest = await signer.verifier.verify(signed.manifest);
    expect(manifest.ruleCount, 1);
    expect(manifest.keyId, 'unit-test-only');
    await signer.verifier.verifyPack(manifest, signed.pack);
    final unknown = FilterManifestVerifier(trustedKeys: {});
    expect(
      unknown.verify(signed.manifest),
      throwsA(isA<FilterPackValidationException>()),
    );
    final envelope =
        jsonDecode(utf8.decode(signed.manifest)) as Map<String, dynamic>;
    final payload = base64Decode(envelope['payload'] as String)..[15] ^= 1;
    envelope['payload'] = base64Encode(payload);
    expect(
      signer.verifier.verify(
        Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
      ),
      throwsA(isA<FilterPackValidationException>()),
    );
  });
  for (final metadata in <Map<String, Object?>>[
    {'schema': 2},
    {'sequence': 0},
    {'sequence': 2147483648},
    {'version': '1.0'},
    {'minimumAppVersion': '0.4.0'},
    {'createdAt': '2026-09-13T00:00:00Z'},
    {'createdAt': '2026-09-10T00:00:00-05:00'},
  ]) {
    test('rejects incompatible signed metadata $metadata', () async {
      final signed = await signer.sign([
        testRule('example.test'),
      ], metadata: metadata);
      expect(
        signer.verifier.verify(signed.manifest),
        throwsA(isA<FilterPackValidationException>()),
      );
    });
  }
  for (final metadata in <Map<String, Object?>>[
    {'filename': '../other.ndjson'},
    {'filename': 'https://evil.test/x.ndjson'},
    {'bytes': 67108865},
    {'rules': 500001},
    {'license': ''},
    {'sha256': 'no'},
    {'rulesSha256': 'no'},
  ]) {
    test('rejects invalid signed pack limits $metadata', () async {
      final signed = await signer.sign([
        testRule('example.test'),
      ], packMetadata: metadata);
      expect(
        signer.verifier.verify(signed.manifest),
        throwsA(isA<FilterPackValidationException>()),
      );
    });
  }
  test(
    'transport rejects credentials, query and path traversal before requests',
    () async {
      for (final address in [
        'http://example.test/manifest.json',
        'https://user:secret@example.test/manifest.json',
        'https://example.test/manifest.json?q=secret',
        'https://example.test/manifest.json#fragment',
        'https://example.test/fake.json',
      ]) {
        expect(
          () => HttpsFilterPackUpdateSource(manifestUri: Uri.parse(address)),
          throwsArgumentError,
        );
      }
      final source = HttpsFilterPackUpdateSource(
        manifestUri: Uri.parse('https://example.test/packs/manifest.json'),
      );
      for (final file in [
        '../test.ndjson',
        '/test.ndjson',
        'https://other.test/test.ndjson',
        'test.json',
      ]) {
        expect(
          () => source.fetchPack(file, 100),
          throwsA(isA<FilterPackValidationException>()),
        );
      }
      expect(
        () => source.fetchPack('test.ndjson', 0),
        throwsA(isA<FilterPackValidationException>()),
      );
    },
  );
}
