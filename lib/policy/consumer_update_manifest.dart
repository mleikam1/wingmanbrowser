import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../config/app_version.dart';

class ConsumerUpdateException implements Exception {
  const ConsumerUpdateException(this.code);
  final String code;
  @override
  String toString() => 'Consumer update rejected ($code).';
}

/// An authenticated release descriptor. Only the verifier can construct it.
final class ConsumerUpdateManifest {
  ConsumerUpdateManifest._({
    required this.sequence,
    required this.version,
    required this.generatedAt,
    required this.filename,
    required this.sha256,
    required this.byteLength,
    required this.license,
    required Uint8List envelope,
  }) : envelope = Uint8List.fromList(envelope).asUnmodifiableView();
  final int sequence, byteLength;
  final String version, filename, sha256, license;
  final DateTime generatedAt;
  final Uint8List envelope;
}

/// Immutable authenticated bytes. A checksum supplied by a caller is never
/// sufficient authority to replace the mandatory baseline.
final class VerifiedConsumerUpdate {
  VerifiedConsumerUpdate._(this.manifest, Uint8List data)
    : data = Uint8List.fromList(data).asUnmodifiableView();
  final ConsumerUpdateManifest manifest;
  final Uint8List data;
}

class ConsumerUpdateVerifier {
  ConsumerUpdateVerifier({
    required Map<String, List<int>> trustedKeys,
    this.appVersion = AppVersion.name,
    DateTime Function()? clock,
  }) : trustedKeys = Map.unmodifiable({
         for (final entry in trustedKeys.entries)
           entry.key: List<int>.unmodifiable(entry.value),
       }),
       _clock = clock ?? DateTime.now;

  static const purpose = 'wingman-consumer-protection-v1';
  static const maximumManifestBytes = 65536;
  static const maximumDataBytes = 16 * 1024 * 1024;
  final Map<String, List<int>> trustedKeys;
  final String appVersion;
  final DateTime Function() _clock;
  bool get configured => trustedKeys.isNotEmpty;

  Future<ConsumerUpdateManifest> verifyManifest(Uint8List input) async {
    final envelopeBytes = Uint8List.fromList(input);
    try {
      if (envelopeBytes.isEmpty ||
          envelopeBytes.length > maximumManifestBytes) {
        _reject('manifest-size');
      }
      final envelope =
          jsonDecode(utf8.decode(envelopeBytes)) as Map<String, dynamic>;
      if (envelope.length != 3) _reject('envelope-schema');
      final key = trustedKeys[envelope['keyId'] as String];
      if (key == null || key.length != 32) _reject('unknown-key');
      final payload = base64Decode(envelope['payload'] as String);
      final signature = base64Decode(envelope['signature'] as String);
      if (signature.length != 64 || payload.length > maximumManifestBytes) {
        _reject('signature-format');
      }
      if (!await Ed25519().verify(
        payload,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
        ),
      )) {
        _reject('signature');
      }
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      if (json['purpose'] != purpose || json['schemaVersion'] != 1) {
        _reject('purpose');
      }
      final sequence = json['sequence'] as int;
      final version = json['version'] as String;
      final timeText = json['generatedAt'] as String;
      final time = DateTime.parse(timeText);
      final minimum = json['minimumAppVersion'] as String;
      final filename = json['filename'] as String;
      final digest = json['sha256'] as String;
      final size = json['bytes'] as int;
      final license = json['license'] as String;
      if (sequence < 2 ||
          sequence > 2147483647 ||
          !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._+-]{0,79}$').hasMatch(version) ||
          !timeText.endsWith('Z') ||
          time.isAfter(_clock().toUtc().add(const Duration(days: 1))) ||
          _compareVersions(appVersion, minimum) < 0 ||
          filename != 'consumer-$sequence.json' ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
          size < 1 ||
          size > maximumDataBytes ||
          license.isEmpty ||
          license.length > 4096) {
        _reject('metadata');
      }
      return ConsumerUpdateManifest._(
        sequence: sequence,
        version: version,
        generatedAt: time.toUtc(),
        filename: filename,
        sha256: digest,
        byteLength: size,
        license: license,
        envelope: envelopeBytes,
      );
    } on ConsumerUpdateException {
      rethrow;
    } catch (_) {
      _reject('manifest-format');
    }
  }

  Future<VerifiedConsumerUpdate> verifyData(
    ConsumerUpdateManifest manifest,
    Uint8List input,
  ) async {
    final data = Uint8List.fromList(input);
    if (data.length != manifest.byteLength || data.length > maximumDataBytes) {
      _reject('data-size');
    }
    final digest = (await Sha256().hash(
      data,
    )).bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    if (digest != manifest.sha256) _reject('data-integrity');
    return VerifiedConsumerUpdate._(manifest, data);
  }

  Future<VerifiedConsumerUpdate> verify(
    Uint8List envelope,
    Uint8List data,
  ) async => verifyData(await verifyManifest(envelope), data);

  static int _compareVersions(String a, String b) {
    final pattern = RegExp(
      r'^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$',
    );
    if (!pattern.hasMatch(a) || !pattern.hasMatch(b)) _reject('app-version');
    final left = a.split('.').map(int.parse).toList();
    final right = b.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (left[i] != right[i]) return left[i].compareTo(right[i]);
    }
    return 0;
  }

  static Never _reject(String code) => throw ConsumerUpdateException(code);
}
