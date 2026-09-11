import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'policy_models.dart';

Future<String> policyDigest(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

/// Time never moves backwards within a process or below a persisted checkpoint.
class PolicyClock {
  PolicyClock({DateTime Function()? wallClock, DateTime? checkpoint})
    : _wall = wallClock ?? DateTime.now {
    final wall = _wall().toUtc();
    final buildFloor = DateTime.utc(2026, 9, 10);
    _base = [
      wall,
      buildFloor,
      if (checkpoint != null) checkpoint.toUtc(),
    ].reduce((a, b) => a.isAfter(b) ? a : b);
    _last = _base;
    _elapsed.start();
  }
  final DateTime Function() _wall;
  final Stopwatch _elapsed = Stopwatch();
  late final DateTime _base;
  late DateTime _last;
  DateTime now() {
    final wall = _wall().toUtc();
    final monotonic = _base.add(_elapsed.elapsed);
    for (final candidate in [wall, monotonic]) {
      if (candidate.isAfter(_last)) _last = candidate;
    }
    return _last;
  }

  void advanceFloor(DateTime? time) {
    if (time != null && time.isAfter(_last)) _last = time.toUtc();
  }
}

class PolicyCheckpoint {
  PolicyCheckpoint({
    this.minimumSequence = 1,
    this.seenAt,
    Iterable<String> revokedIds = const [],
  }) : revokedIds = Set.unmodifiable(revokedIds);
  final int minimumSequence;
  final DateTime? seenAt;
  final Set<String> revokedIds;
}

class VerifiedPolicyCatalog {
  VerifiedPolicyCatalog({
    required this.version,
    required this.sequence,
    required this.reviewedAt,
    required this.expiresAt,
    required Iterable<ApprovedResource> resources,
    required Iterable<String> revokedIds,
  }) : resources = List.unmodifiable(resources),
       revokedIds = Set.unmodifiable(revokedIds);
  final String version;
  final int sequence;
  final DateTime reviewedAt, expiresAt;
  final List<ApprovedResource> resources;
  final Set<String> revokedIds;
}

/// Verifies packaged data only. It has no HTTP client or arbitrary URL fetcher.
class SignedPolicyVerifier {
  SignedPolicyVerifier({required Map<String, List<int>> trustedKeys})
    : _keys = Map.unmodifiable(
        trustedKeys.map((k, v) => MapEntry(k, List<int>.unmodifiable(v))),
      );
  final Map<String, List<int>> _keys;
  static const maximumCatalogBytes = 256 * 1024;
  static const maximumArticleBytes = 32 * 1024;
  static const maximumTotalArticleBytes = 2 * 1024 * 1024;
  static const maximumResources = 100;

  Future<VerifiedPolicyCatalog> verify({
    required Uint8List manifestBytes,
    required Uint8List catalogBytes,
    required Future<Uint8List> Function(String) readAsset,
    required DateTime now,
    PolicyCheckpoint? checkpoint,
  }) async {
    Never reject(String code) => throw PolicyValidationException(code);
    try {
      if (manifestBytes.length > 65536 ||
          catalogBytes.length > maximumCatalogBytes) {
        reject('size');
      }
      final envelope = jsonDecode(utf8.decode(manifestBytes)) as Map;
      final key = _keys[envelope['keyId']];
      if (key == null || key.length != 32) reject('key');
      final payload = base64Decode(envelope['payload'] as String);
      final signature = base64Decode(envelope['signature'] as String);
      if (payload.length > 65536 ||
          signature.length != 64 ||
          !await Ed25519().verify(
            payload,
            signature: Signature(
              signature,
              publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
            ),
          )) {
        reject('signature');
      }
      final manifest = jsonDecode(utf8.decode(payload)) as Map;
      if (manifest['schema'] != 1 ||
          manifest['policyVersion'] != MandatorySafetyPolicy.version ||
          manifest['capability'] != 'bundledPlainText') {
        reject('policy-version');
      }
      if (manifest['catalogBytes'] != catalogBytes.length ||
          manifest['catalogSha256'] != await policyDigest(catalogBytes)) {
        reject('catalog-integrity');
      }
      final catalog = jsonDecode(utf8.decode(catalogBytes)) as Map;
      if (catalog['schema'] != 1 ||
          catalog['policyVersion'] != MandatorySafetyPolicy.version ||
          catalog['version'] != manifest['version'] ||
          catalog['sequence'] != manifest['sequence']) {
        reject('catalog-metadata');
      }
      final version = catalog['version'] as String;
      if (!RegExp(r'^\d{1,6}\.\d{1,6}\.\d{1,6}$').hasMatch(version)) {
        reject('version');
      }
      final sequence = catalog['sequence'] as int;
      if (sequence < MandatorySafetyPolicy.minimumCatalogSequence ||
          sequence < (checkpoint?.minimumSequence ?? 1) ||
          sequence > 2147483647) {
        reject('replay');
      }
      DateTime date(Object? value) {
        if (value is! String || !value.endsWith('Z')) reject('date');
        return DateTime.parse(value).toUtc();
      }

      final reviewed = date(catalog['reviewedAt']);
      final expires = date(catalog['expiresAt']);
      if (reviewed.isAfter(now) ||
          !expires.isAfter(now) ||
          !expires.isAfter(reviewed) ||
          expires.difference(reviewed) > const Duration(days: 366)) {
        reject('freshness');
      }
      String text(Object? value, int max) {
        if (value is! String ||
            value.trim().isEmpty ||
            value.length > max ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
          reject('text');
        }
        return value;
      }

      final reviewer = text(catalog['reviewer'], 200);
      final license = text(catalog['license'], 120);
      final revoked = <String>{...?checkpoint?.revokedIds};
      for (final id in (catalog['revokedIds'] as List? ?? const [])) {
        if (id is! String || !validResourceId(id)) reject('revocation');
        revoked.add(id);
      }
      final records = catalog['resources'] as List;
      if (records.isEmpty ||
          records.length > maximumResources ||
          manifest['resourceCount'] != records.length) {
        reject('record-count');
      }
      final resources = <ApprovedResource>[];
      final ids = <String>{};
      var totalBytes = 0;
      for (final record in records) {
        final row = record as Map;
        final id = row['id'] as String;
        final collection = row['collection'] as String;
        if (!validResourceId(id) ||
            !validResourceId(collection) ||
            !ids.add(id)) {
          reject('record-id');
        }
        if (row['capability'] != 'bundledPlainText' ||
            row.containsKey('url') ||
            row.containsKey('host') ||
            row.containsKey('dependencies')) {
          reject('unsupported-scope');
        }
        final path = row['assetPath'] as String;
        if (path != 'assets/policy/articles/$id.txt') reject('asset-path');
        final digest = row['sha256'] as String;
        final length = row['byteLength'] as int;
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
            length < 120 ||
            length > maximumArticleBytes ||
            (totalBytes += length) > maximumTotalArticleBytes) {
          reject('article-limit');
        }
        final bytes = await readAsset(path);
        if (bytes.length != length || await policyDigest(bytes) != digest) {
          reject('article-integrity');
        }
        final body = utf8.decode(bytes);
        if (RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(body)) {
          reject('article-text');
        }
        final contexts = <ContentContext>{};
        for (final context in row['contexts'] as List) {
          final parsed = ContentContext.values
              .where((c) => c.name == context)
              .firstOrNull;
          if (parsed == null) reject('context');
          contexts.add(parsed);
        }
        if (contexts.isEmpty) reject('context');
        final sources = <String>[];
        for (final source in row['sourceUrls'] as List) {
          final uri = Uri.tryParse(source as String);
          if (uri == null ||
              uri.scheme != 'https' ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty ||
              source.length > 2048) {
            reject('source');
          }
          sources.add(source);
        }
        if (sources.isEmpty || sources.length > 10) reject('source');
        final resourceReviewed = row['reviewedAt'] == null
            ? reviewed
            : date(row['reviewedAt']);
        final resourceExpires = row['expiresAt'] == null
            ? expires
            : date(row['expiresAt']);
        if (resourceReviewed.isAfter(now) ||
            resourceReviewed.isBefore(reviewed) ||
            !resourceExpires.isAfter(resourceReviewed) ||
            resourceExpires.isAfter(expires)) {
          reject('resource-freshness');
        }
        resources.add(
          ApprovedResource(
            id: id,
            title: text(row['title'], 160),
            summary: text(row['summary'], 500),
            collection: collection,
            body: body,
            assetPath: path,
            sha256: digest,
            reviewedAt: resourceReviewed,
            expiresAt: resourceExpires,
            policyVersion: MandatorySafetyPolicy.version,
            sourceUrls: sources,
            contexts: contexts,
            reviewer: reviewer,
            license: license,
          ),
        );
      }
      return VerifiedPolicyCatalog(
        version: version,
        sequence: sequence,
        reviewedAt: reviewed,
        expiresAt: expires,
        resources: resources,
        revokedIds: revoked,
      );
    } on PolicyValidationException {
      rethrow;
    } catch (_) {
      reject('format');
    }
  }
}

class SignedPolicyRepository extends ChangeNotifier {
  SignedPolicyRepository({
    AssetBundle? bundle,
    SignedPolicyVerifier? verifier,
    PolicyClock? clock,
    PolicyCheckpoint? checkpoint,
  }) : _bundle = bundle ?? rootBundle,
       // Keep this injectable named argument public without exposing mutation.
       // ignore: prefer_initializing_formals
       _verifier = verifier,
       clock = clock ?? PolicyClock(checkpoint: checkpoint?.seenAt),
       _checkpoint = checkpoint ?? PolicyCheckpoint();
  final AssetBundle _bundle;
  SignedPolicyVerifier? _verifier;
  final PolicyClock clock;
  PolicyCheckpoint _checkpoint;
  VerifiedPolicyCatalog? _catalog;
  String? _error;
  Future<void>? _initialization;
  Future<void> _activations = Future.value();
  Future<void> Function(PolicyCheckpoint)? beforeActivation;
  List<ApprovedResource> get resources => status.usable
      ? List.unmodifiable(
          _catalog!.resources.where(
            (r) =>
                !_catalog!.revokedIds.contains(r.id) &&
                r.expiresAt.isAfter(clock.now()),
          ),
        )
      : const [];
  PolicyStatus get status {
    final catalog = _catalog;
    final fresh = catalog != null && catalog.expiresAt.isAfter(clock.now());
    return PolicyStatus(
      usable: fresh,
      version: catalog?.version,
      sequence: catalog?.sequence,
      reviewedAt: catalog?.reviewedAt,
      expiresAt: catalog?.expiresAt,
      resourceCount: fresh ? resourcesCount : 0,
      errorCode: fresh
          ? _error
          : _error ?? (catalog == null ? 'unavailable' : 'expired'),
    );
  }

  int get resourcesCount =>
      _catalog?.resources
          .where(
            (r) =>
                !_catalog!.revokedIds.contains(r.id) &&
                r.expiresAt.isAfter(clock.now()),
          )
          .length ??
      0;
  DateTime? get nextExpiry {
    final catalog = _catalog;
    if (catalog == null) return null;
    var result = catalog.expiresAt;
    final now = clock.now();
    for (final resource in catalog.resources) {
      if (!_catalog!.revokedIds.contains(resource.id) &&
          resource.expiresAt.isAfter(now) &&
          resource.expiresAt.isBefore(result)) {
        result = resource.expiresAt;
      }
    }
    return result;
  }

  PolicyCheckpoint get checkpoint => PolicyCheckpoint(
    minimumSequence: _checkpoint.minimumSequence,
    seenAt: clock.now(),
    revokedIds: _checkpoint.revokedIds,
  );
  void restrict(String code) {
    _catalog = null;
    _error = code;
    notifyListeners();
  }

  Future<Uint8List> _read(String path) async {
    final data = await _bundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  void adoptCheckpoint(PolicyCheckpoint checkpoint) {
    clock.advanceFloor(checkpoint.seenAt);
    _checkpoint = PolicyCheckpoint(
      minimumSequence: checkpoint.minimumSequence > _checkpoint.minimumSequence
          ? checkpoint.minimumSequence
          : _checkpoint.minimumSequence,
      seenAt: clock.now(),
      revokedIds: {...checkpoint.revokedIds, ..._checkpoint.revokedIds},
    );
  }

  Future<void> init() => _initialization ??= _init();
  Future<void> _init() async {
    try {
      if (_verifier == null) {
        final json =
            jsonDecode(
                  utf8.decode(await _read('assets/policy/public_keys.json')),
                )
                as Map;
        _verifier = SignedPolicyVerifier(
          trustedKeys: {
            for (final e in json.entries)
              e.key as String: base64Decode(e.value as String),
          },
        );
      }
      await activate(
        await _read('assets/policy/manifest.json'),
        await _read('assets/policy/catalog.json'),
      );
    } catch (error) {
      _error = error is PolicyValidationException
          ? error.code
          : 'assets-unavailable';
    }
  }

  /// Signed replacement input is inert. There is no production update endpoint.
  /// Failure retains the previous verified snapshot; revocations never roll back.
  Future<void> activate(Uint8List manifest, Uint8List catalog) async {
    final envelope = Uint8List.fromList(manifest);
    final bytes = Uint8List.fromList(catalog);
    final result = _activations.then((_) => _activate(envelope, bytes));
    _activations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _activate(Uint8List manifest, Uint8List catalog) async {
    try {
      final verifier = _verifier;
      if (verifier == null) {
        throw const PolicyValidationException('uninitialized');
      }
      final verified = await verifier.verify(
        manifestBytes: Uint8List.fromList(manifest),
        catalogBytes: Uint8List.fromList(catalog),
        readAsset: _read,
        now: clock.now(),
        checkpoint: _checkpoint,
      );
      final checkpoint = PolicyCheckpoint(
        minimumSequence: verified.sequence,
        seenAt: clock.now(),
        revokedIds: verified.revokedIds,
      );
      // Runtime binds durable trust before the new records become visible.
      // A failed checkpoint cannot expose a generation whose revocations could
      // disappear after a restart.
      try {
        await beforeActivation?.call(checkpoint);
      } catch (_) {
        restrict('checkpoint-unavailable');
        throw const PolicyValidationException('checkpoint-unavailable');
      }
      _catalog = verified;
      _checkpoint = checkpoint;
      _error = null;
      notifyListeners();
    } catch (error) {
      _error = error is PolicyValidationException ? error.code : 'validation';
      rethrow;
    }
  }
}
