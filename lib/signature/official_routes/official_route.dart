import 'dart:convert';
import 'package:flutter/services.dart';
import '../../policy/policy_runtime.dart';

/// An identity review is evidence, never a grant of navigation permission.
enum RouteIdentityStatus { reviewed, expired, revoked, notYetReviewed }

Uri strictOfficialUri(String input) {
  if (input.length > 2048 ||
      RegExp(r'[^\x21-\x7e]|[\\%]').hasMatch(input) ||
      RegExp(r'(^|/)\.{1,2}(/|$)').hasMatch(input)) {
    throw const FormatException('Unsupported official destination.');
  }
  final uri = Uri.tryParse(input);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.host.isEmpty ||
      uri.hasFragment ||
      uri.hasPort ||
      RegExp(
        r'^https://[^/]*:',
        caseSensitive: false,
      ).hasMatch(input.split('?').first) ||
      uri.host.length > 253 ||
      !uri.host.contains('.') ||
      RegExp(r'^[0-9.]+$').hasMatch(uri.host) ||
      uri.host.endsWith('.') ||
      uri.host.split('.').any((s) => s.startsWith('xn--')) ||
      !RegExp(r'^[a-z0-9]+(?:[a-z0-9.-]*[a-z0-9])?$').hasMatch(uri.host) ||
      uri.host
          .split('.')
          .any(
            (s) =>
                s.isEmpty ||
                s.length > 63 ||
                s.startsWith('-') ||
                s.endsWith('-'),
          )) {
    throw const FormatException('Unsupported official destination.');
  }
  return uri.replace(host: uri.host.toLowerCase());
}

class OfficialRoute {
  OfficialRoute._({
    required this.id,
    required this.organization,
    required this.task,
    required this.destination,
    required this.region,
    required this.language,
    required this.reviewedAt,
    required this.expiresAt,
    required this.evidence,
    required this.revoked,
    required this.relatedGuideIds,
    required this.policyVersion,
    required this.policyCategoryIds,
  });
  final String id, organization, task, region, language;
  final Uri destination;
  final DateTime reviewedAt, expiresAt;
  final bool revoked;
  final int policyVersion;
  final List<RouteEvidence> evidence;
  final List<String> relatedGuideIds, policyCategoryIds;
  String get domain => destination.host;
  String get scope =>
      'Exact address only; no subpages, redirects, sign-in, files, or other destinations are approved by this record.';
  RouteIdentityStatus identityStatus(DateTime now) => revoked
      ? RouteIdentityStatus.revoked
      : now.isBefore(reviewedAt)
      ? RouteIdentityStatus.notYetReviewed
      : !now.isBefore(expiresAt)
      ? RouteIdentityStatus.expired
      : RouteIdentityStatus.reviewed;
  bool matchesDestination(String candidate) {
    try {
      return strictOfficialUri(candidate).toString() == destination.toString();
    } on FormatException {
      return false;
    }
  }

  RouteAssessment assess(
    PolicyRuntime policy, {
    required DateTime now,
    bool isPrivate = false,
    ContentContext context = ContentContext.general,
  }) {
    final identity = identityStatus(now);
    final decision = policy.policy.evaluate(
      PolicyRequest.navigation(
        destination,
        context: context,
        isPrivate: isPrivate,
      ),
    );
    return RouteAssessment(
      identity,
      decision,
      compatible: policyVersion == MandatorySafetyPolicy.version,
    );
  }

  factory OfficialRoute.fromJson(Map<String, Object?> json) {
    String text(String key, int limit) {
      final value = json[key];
      if (value is! String ||
          value.isEmpty ||
          value.length > limit ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
        throw const FormatException('Invalid official-route record.');
      }
      return value;
    }

    List<String> ids(String key, int limit) {
      final value = json[key];
      if (value is! List ||
          value.length > limit ||
          value.any((v) => v is! String || !validResourceId(v))) {
        throw const FormatException('Invalid official-route scope.');
      }
      return List.unmodifiable(value.cast<String>());
    }

    final id = text('id', 80);
    final destination = strictOfficialUri(text('destination', 2048));
    // Host and path are explicit reviewed identities, not suffix allowlists.
    if (!validResourceId(id) ||
        json['identityHost'] != destination.host ||
        json['navigationScope'] != 'exact' ||
        json['policyVersion'] != 1 ||
        json['status'] != 'reviewed' && json['status'] != 'revoked') {
      throw const FormatException('Invalid official-route identity.');
    }
    final reviewed = DateTime.tryParse(text('reviewedAt', 40));
    final expires = DateTime.tryParse(text('expiresAt', 40));
    if (reviewed == null ||
        expires == null ||
        !reviewed.isUtc ||
        !expires.isUtc ||
        !expires.isAfter(reviewed) ||
        expires.difference(reviewed) > const Duration(days: 180)) {
      throw const FormatException('Invalid official-route review window.');
    }
    final rawEvidence = json['evidence'];
    if (rawEvidence is! List || rawEvidence.isEmpty || rawEvidence.length > 5) {
      throw const FormatException('Official-route evidence is missing.');
    }
    final evidence = rawEvidence
        .map((e) => RouteEvidence.fromJson(Map<String, Object?>.from(e as Map)))
        .toList();
    final categories = ids('policyCategoryIds', 6);
    if (!categories.toSet().containsAll(
      MandatorySafetyPolicy.categories.map((c) => c.id),
    )) {
      throw const FormatException('Mandatory policy references are missing.');
    }
    return OfficialRoute._(
      id: id,
      organization: text('organization', 120),
      task: text('task', 160),
      destination: destination,
      region: text('region', 100),
      language: text('language', 50),
      reviewedAt: reviewed,
      expiresAt: expires,
      evidence: List.unmodifiable(evidence),
      revoked: json['status'] == 'revoked',
      relatedGuideIds: ids('relatedGuideIds', 5),
      policyVersion: 1,
      policyCategoryIds: categories,
    );
  }
}

class RouteEvidence {
  const RouteEvidence(this.source, this.explanation);
  final Uri source;
  final String explanation;
  factory RouteEvidence.fromJson(Map<String, Object?> json) {
    final source = json['source'];
    final explanation = json['explanation'];
    if (source is! String ||
        explanation is! String ||
        explanation.isEmpty ||
        explanation.length > 600 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(explanation)) {
      throw const FormatException('Invalid identity evidence.');
    }
    return RouteEvidence(strictOfficialUri(source), explanation);
  }
}

class RouteAssessment {
  const RouteAssessment(
    this.identity,
    this.policyDecision, {
    required this.compatible,
  });
  final RouteIdentityStatus identity;
  final PolicyDecision policyDecision;
  final bool compatible;
  bool get canOpen =>
      compatible &&
      identity == RouteIdentityStatus.reviewed &&
      policyDecision.isAllowed;
  bool get showsActiveVerificationBadge => canOpen;
}

class OfficialRouteCatalog {
  OfficialRouteCatalog._(this.version, this.routes);
  final int version;
  final List<OfficialRoute> routes;
  static const maximumBytes = 128 * 1024;
  static Future<OfficialRouteCatalog> loadBundle() async =>
      OfficialRouteCatalog.decode(
        await rootBundle.loadString('assets/signature/official_routes.json'),
      );
  factory OfficialRouteCatalog.decode(String source) {
    if (source.length > maximumBytes ||
        utf8.encode(source).length > maximumBytes) {
      throw const FormatException('Official catalog is too large.');
    }
    try {
      final json = jsonDecode(source) as Map;
      final rows = json['routes'] as List;
      if (json['schema'] != 1 ||
          json['version'] != 1 ||
          rows.isEmpty ||
          rows.length > 100) {
        throw const FormatException('Unsupported official catalog.');
      }
      final records = rows
          .map(
            (r) => OfficialRoute.fromJson(Map<String, Object?>.from(r as Map)),
          )
          .toList();
      if (records.map((r) => r.id).toSet().length != records.length) {
        throw const FormatException('Duplicate route identity.');
      }
      return OfficialRouteCatalog._(1, List.unmodifiable(records));
    } catch (_) {
      throw const FormatException('Official catalog is unavailable.');
    }
  }
  List<OfficialRoute> search(String query, {String? region}) {
    if (query.length > 200) return const [];
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(12);
    return routes
        .where(
          (r) =>
              (region == null || r.region == region) &&
              terms.every(
                '${r.organization} ${r.task} ${r.domain} ${r.region}'
                    .toLowerCase()
                    .contains,
              ),
        )
        .toList(growable: false);
  }
}
