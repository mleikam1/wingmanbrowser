import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'consumer_manifest_hash.dart';
import 'consumer_update_manifest.dart';
import 'policy_models.dart';
import 'strict_search_policy.dart';

/// A validated local blocking baseline. Unknown destinations are permitted;
/// that decision is not a review, endorsement, or classification of page text.
/// Native adapters independently validate and enforce the same bundled data.
class ConsumerProtectionPolicy {
  const ConsumerProtectionPolicy.unavailable([this.errorCode = 'not-loaded'])
    : domains = const {},
      pathRules = const [],
      trackers = const {},
      sequence = 0,
      version = null,
      generatedAt = null;

  ConsumerProtectionPolicy._({
    required this.domains,
    required this.pathRules,
    required this.trackers,
    required this.sequence,
    required this.version,
    required this.generatedAt,
  }) : errorCode = null;

  static const assetPath = 'assets/policy/consumer_protection.json';
  static const maximumBytes = 16 * 1024 * 1024;
  static bool _registeredLicenses = false;
  static Future<ConsumerProtectionPolicy>? _bundled;
  final Map<MandatoryCategory, Set<String>> domains;
  final List<ConsumerPathRule> pathRules;
  final Set<String> trackers;
  final int sequence;
  final String? version, errorCode;
  final DateTime? generatedAt;
  bool get isUsable => errorCode == null && sequence >= 1;

  /// Staleness is visible coverage degradation. It never converts a validated
  /// blocking list into an empty list during an outage or catalog expiry.
  bool isStale(DateTime now) =>
      generatedAt == null || now.toUtc().difference(generatedAt!).inHours > 24;

  static Future<ConsumerProtectionPolicy> load({AssetBundle? bundle}) =>
      bundle == null ? (_bundled ??= _load()) : _load(bundle: bundle);

  static Future<ConsumerProtectionPolicy> _load({AssetBundle? bundle}) async {
    if (bundle == null && !_registeredLicenses) {
      _registeredLicenses = true;
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks(
          const ['HaGeZi consumer protection data (adaptation)'],
          'HaGeZi DNS blocklists, revision '
          '23cdd6516160ae7903b81d762c22d557b808c1e0. '
          'NSFW, Gambling Mini and Threat Intelligence Mini lists. '
          'Modified into category suffix sets with a documented educational '
          'correction. Data is distributed under GPL-3.0; complete input '
          'sources are bundled in assets/policy/consumer_sources and the '
          'transformation is tool/compile_consumer_protection.py.\n\n'
          '${await rootBundle.loadString('assets/policy/consumer_sources/GPL-3.0.txt')}',
        );
      });
    }
    try {
      final data = await (bundle ?? rootBundle).load(assetPath);
      return verifyBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (_) {
      return const ConsumerProtectionPolicy.unavailable('baseline-unavailable');
    }
  }

  /// Only the compiled digest is authority. Callers cannot supply a replacement
  /// digest, disable category arrays, or derive trust from a stored preference.
  static Future<ConsumerProtectionPolicy> verifyBytes(Uint8List bytes) =>
      _decode(
        bytes,
        expectedDigest: consumerManifestSha256,
        expectedSequence: 1,
      );

  static Future<ConsumerProtectionPolicy> fromVerifiedUpdate(
    VerifiedConsumerUpdate release,
  ) => _decode(
    release.data,
    expectedDigest: release.manifest.sha256,
    expectedSequence: release.manifest.sequence,
    expectedVersion: release.manifest.version,
    expectedTime: release.manifest.generatedAt,
  );

  static Future<ConsumerProtectionPolicy> _decode(
    Uint8List bytes, {
    required String expectedDigest,
    required int expectedSequence,
    String? expectedVersion,
    DateTime? expectedTime,
  }) async {
    try {
      if (bytes.isEmpty || bytes.length > maximumBytes) {
        return const ConsumerProtectionPolicy.unavailable('baseline-size');
      }
      final digest = (await Sha256().hash(
        bytes,
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (digest != expectedDigest) {
        return const ConsumerProtectionPolicy.unavailable('baseline-integrity');
      }
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (json['schemaVersion'] != 1 ||
          json['sequence'] != expectedSequence ||
          (expectedVersion != null && json['version'] != expectedVersion) ||
          (expectedTime != null &&
              DateTime.parse(json['generatedAt'] as String).toUtc() !=
                  expectedTime)) {
        throw const FormatException('baseline-schema');
      }
      final categories = json['categories'] as Map<String, dynamic>;
      if (categories.length != MandatoryCategory.values.length) {
        throw const FormatException('baseline-categories');
      }
      final domains = <MandatoryCategory, Set<String>>{};
      for (final category in MandatoryCategory.values) {
        final list = (categories[category.id] as List).cast<String>();
        if (list.isEmpty ||
            list.length > 500000 ||
            list.any((host) => !validProtectionDomain(host))) {
          throw const FormatException('baseline-domains');
        }
        domains[category] = Set.unmodifiable(list);
      }
      final paths = (json['pathRules'] as List)
          .map((value) {
            final row = value as Map<String, dynamic>;
            final host = row['host'] as String;
            final prefix = row['pathPrefix'] as String;
            if (!validProtectionDomain(host) ||
                !prefix.startsWith('/') ||
                prefix.contains('%') ||
                prefix.contains('?') ||
                prefix != prefix.toLowerCase()) {
              throw const FormatException('baseline-path');
            }
            return ConsumerPathRule(
              host: host,
              pathPrefix: prefix,
              category: MandatoryCategory.values.singleWhere(
                (c) => c.id == row['category'],
              ),
            );
          })
          .toList(growable: false);
      final trackerList = (json['trackers'] as List).cast<String>();
      if (trackerList.any((host) => !validProtectionDomain(host))) {
        throw const FormatException('baseline-trackers');
      }
      return ConsumerProtectionPolicy._(
        domains: Map.unmodifiable(domains),
        pathRules: List.unmodifiable(paths),
        trackers: Set.unmodifiable(trackerList),
        sequence: json['sequence'] as int,
        version: json['version'] as String,
        generatedAt: DateTime.parse(json['generatedAt'] as String).toUtc(),
      );
    } catch (_) {
      return const ConsumerProtectionPolicy.unavailable('baseline-format');
    }
  }

  PolicyDecision assessNavigation(
    Uri uri, {
    AdditionalRestrictions? additional,
  }) {
    if (!isUsable) {
      return const PolicyDecision(PolicyDecisionCode.blockPolicyUnavailable);
    }
    if (!validConsumerUri(uri)) {
      return const PolicyDecision(
        PolicyDecisionCode.blockUnsupportedCapability,
      );
    }
    final host = protectionHost(uri.host);
    final category = categoryFor(uri);
    if (category != null) {
      return PolicyDecision(
        category == MandatoryCategory.securityThreat
            ? PolicyDecisionCode.blockSecurityThreat
            : PolicyDecisionCode.blockMandatoryCategory,
        category: category,
      );
    }
    if (additional?.blockedDomains.any((d) => hostMatches(host, d)) == true) {
      return const PolicyDecision(
        PolicyDecisionCode.blockAdditionalRestriction,
      );
    }
    try {
      final rewritten = const StrictSearchPolicy().rewriteProviderInput(
        uri.toString(),
      );
      if (rewritten != null &&
          !const StrictSearchPolicy().acceptsCanonical(uri)) {
        return const PolicyDecision(
          PolicyDecisionCode.blockUnsupportedCapability,
        );
      }
    } on FormatException {
      return const PolicyDecision(
        PolicyDecisionCode.blockUnsupportedCapability,
      );
    }
    final isSearch = const StrictSearchPolicy().acceptsCanonical(uri);
    if (isSearch &&
        (additional?.blockedCollections.contains('web-search') == true ||
            additional?.blockedResourceIds.contains('web-search') == true)) {
      return const PolicyDecision(
        PolicyDecisionCode.blockAdditionalRestriction,
      );
    }
    return PolicyDecision(
      PolicyDecisionCode.allowPermitted,
      resourceId: isSearch ? 'web-search' : null,
      safeTitle: isSearch ? 'DuckDuckGo search' : null,
    );
  }

  MandatoryCategory? categoryFor(Uri uri) {
    final host = protectionHost(uri.host);
    // Threat always wins over content annotations or support distinctions.
    for (final category in [
      MandatoryCategory.securityThreat,
      ...MandatoryCategory.values.where(
        (c) => c != MandatoryCategory.securityThreat,
      ),
    ]) {
      var suffix = host;
      while (suffix.isNotEmpty) {
        if (domains[category]?.contains(suffix) == true) return category;
        final dot = suffix.indexOf('.');
        if (dot < 0) break;
        suffix = suffix.substring(dot + 1);
      }
    }
    String path;
    try {
      path = normalizedProtectionPath(uri);
    } on FormatException {
      return null;
    }
    for (final rule in pathRules) {
      if (hostMatches(host, rule.host) &&
          (path == rule.pathPrefix || path.startsWith('${rule.pathPrefix}/'))) {
        return rule.category;
      }
    }
    return null;
  }

  bool isKnownThirdPartyTracker(Uri uri, Uri topDocument) {
    final host = protectionHost(uri.host);
    if (host == protectionHost(topDocument.host)) return false;
    var suffix = host;
    while (suffix.contains('.')) {
      if (trackers.contains(suffix)) return true;
      suffix = suffix.substring(suffix.indexOf('.') + 1);
    }
    return false;
  }
}

class ConsumerPathRule {
  const ConsumerPathRule({
    required this.host,
    required this.pathPrefix,
    required this.category,
  });
  final String host, pathPrefix;
  final MandatoryCategory category;
}

String protectionHost(String host) =>
    host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
bool hostMatches(String host, String rule) =>
    host == rule || host.endsWith('.$rule');
bool validProtectionDomain(String host) =>
    host.length <= 253 &&
    host.contains('.') &&
    host
        .split('.')
        .every(
          (label) =>
              RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(label),
        );

bool validConsumerUri(Uri uri) =>
    const {'http', 'https'}.contains(uri.scheme) &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    uri.port > 0 &&
    uri.port <= 65535 &&
    uri.toString().length <= 16384 &&
    !RegExp(r'[\x00-\x20\x7f\\]').hasMatch(uri.toString());

String normalizedProtectionPath(Uri uri) {
  final decoded = Uri.decodeComponent(uri.path).toLowerCase();
  final parts = <String>[];
  for (final part in decoded.split('/')) {
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (part.isNotEmpty && part != '.') {
      parts.add(part);
    }
  }
  return '/${parts.join('/')}';
}
