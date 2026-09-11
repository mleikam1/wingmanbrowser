import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class FilterPackValidationException implements Exception {
  const FilterPackValidationException(this.code);
  final String code;
  @override
  String toString() =>
      'Filter pack rejected ($code). The current pack is unchanged.';
}

/// The signature covers exact payload bytes carried in the envelope, avoiding
/// cross-language JSON serialization/canonicalization ambiguities.
class SignedFilterManifest {
  const SignedFilterManifest({
    required this.version,
    required this.sequence,
    required this.createdAt,
    required this.minimumAppVersion,
    required this.filename,
    required this.sha256,
    required this.rulesSha256,
    required this.byteLength,
    required this.ruleCount,
    required this.license,
    required this.keyId,
  });
  final String version;
  final int sequence;
  final DateTime createdAt;
  final String minimumAppVersion;
  final String filename;
  final String sha256;
  final String rulesSha256;
  final int byteLength;
  final int ruleCount;
  final String license;
  final String keyId;
}

class FilterManifestVerifier {
  FilterManifestVerifier({
    required Map<String, List<int>> trustedKeys,
    this.appVersion = '0.4.0',
    DateTime Function()? clock,
  }) : trustedKeys = Map.unmodifiable(
         trustedKeys.map(
           (id, key) => MapEntry(id, List<int>.unmodifiable(key)),
         ),
       ),
       _clock = clock ?? DateTime.now;
  final Map<String, List<int>> trustedKeys;
  final String appVersion;
  final DateTime Function() _clock;
  static const maximumManifestBytes = 65536;
  static const maximumPackBytes = 64 * 1024 * 1024;
  static const maximumRules = 500000;

  Future<SignedFilterManifest> verify(Uint8List envelopeBytes) async {
    try {
      if (envelopeBytes.length > maximumManifestBytes) _reject('manifest-size');
      final envelope =
          jsonDecode(utf8.decode(envelopeBytes)) as Map<String, dynamic>;
      final keyId = envelope['keyId'] as String;
      final publicKey = trustedKeys[keyId];
      if (publicKey == null || publicKey.length != 32) _reject('unknown-key');
      final payload = base64Decode(envelope['payload'] as String);
      final signature = base64Decode(envelope['signature'] as String);
      if (signature.length != 64 || payload.length > maximumManifestBytes) {
        _reject('signature-format');
      }
      if (!await Ed25519().verify(
        payload,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      )) {
        _reject('signature');
      }
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      if (json['schema'] != 1) _reject('schema');
      final version = json['version'] as String;
      final sequence = json['sequence'] as int;
      final createdText = json['createdAt'] as String;
      final created = DateTime.parse(createdText);
      final minVersion = json['minimumAppVersion'] as String;
      if (!_versionPattern.hasMatch(version) ||
          sequence <= 0 ||
          sequence > 2147483647 ||
          !createdText.endsWith('Z') ||
          created.isAfter(_clock().toUtc().add(const Duration(days: 1))) ||
          _compareVersions(appVersion, minVersion) < 0) {
        _reject('compatibility');
      }
      final packs = json['packs'] as List;
      // One global artifact prevents revealing chosen categories through
      // category-specific download requests. Metadata supports future packs.
      if (packs.length != 1) _reject('pack-count');
      final pack = packs.single as Map<String, dynamic>;
      final filename = pack['filename'] as String;
      final checksum = pack['sha256'] as String;
      final rulesChecksum = pack['rulesSha256'] as String;
      final size = pack['bytes'] as int;
      final count = pack['rules'] as int;
      final license = pack['license'] as String;
      if (!RegExp(r'^[a-z0-9][a-z0-9_.-]{0,79}\.ndjson$').hasMatch(filename) ||
          filename.contains('..') ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(rulesChecksum) ||
          size <= 0 ||
          size > maximumPackBytes ||
          count <= 0 ||
          count > maximumRules ||
          license.isEmpty ||
          license.length > 120) {
        _reject('pack-metadata');
      }
      return SignedFilterManifest(
        version: version,
        sequence: sequence,
        createdAt: created,
        minimumAppVersion: minVersion,
        filename: filename,
        sha256: checksum,
        rulesSha256: rulesChecksum,
        byteLength: size,
        ruleCount: count,
        license: license,
        keyId: keyId,
      );
    } on FilterPackValidationException {
      rethrow;
    } catch (_) {
      _reject('manifest-format');
    }
  }

  Future<void> verifyPack(
    SignedFilterManifest manifest,
    Uint8List bytes,
  ) async {
    if (bytes.length != manifest.byteLength ||
        bytes.length > maximumPackBytes) {
      _reject('pack-size');
    }
    final digest = (await Sha256().hash(
      bytes,
    )).bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    if (digest != manifest.sha256) _reject('checksum');
  }

  static final _versionPattern = RegExp(
    r'^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$',
  );
  static int _compareVersions(String left, String right) {
    if (!_versionPattern.hasMatch(left) || !_versionPattern.hasMatch(right)) {
      _reject('version-format');
    }
    final a = left.split('.').map(int.parse).toList();
    final b = right.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return 0;
  }

  static Never _reject(String code) =>
      throw FilterPackValidationException(code);
}
