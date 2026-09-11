import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'live_manifest_hash.dart';
import 'policy_models.dart';

enum LiveResourceType { document, image, styleSheet, font }

/// A network scope, not a claim that its response has been classified.
class LiveResourceRecord {
  const LiveResourceRecord._({
    required this.url,
    required this.type,
    required this.mimeTypes,
    required this.maxBytes,
  });

  final String url;
  final LiveResourceType type;
  final Set<String> mimeTypes;

  /// Enforced by the Android mediated fetcher. WKWebView does not expose an
  /// equivalent pre-consumption HTTPS byte limit; it is not claimed on iOS.
  final int maxBytes;
}

class LiveSiteRecord {
  const LiveSiteRecord._({
    required this.id,
    required this.title,
    required this.description,
    required this.collection,
    required this.entryUrl,
    required this.enabled,
    required this.contexts,
    required this.reviewedAt,
    required this.expiresAt,
    required this.documents,
    required this.resources,
    required this.limitations,
  });

  final String id, title, description, collection, entryUrl;
  final bool enabled;
  final Set<ContentContext> contexts;
  final DateTime reviewedAt, expiresAt;
  final List<LiveResourceRecord> documents, resources;
  final List<String> limitations;

  bool isCurrent(DateTime now) =>
      !now.isBefore(reviewedAt) && now.isBefore(expiresAt);
}

/// Build-pinned, additive-to-nothing network permission. It cannot enable a
/// renderer, grant executable content or weaken the mandatory policy.
///
/// Native implementations independently verify the same bundled bytes and
/// enforce their request boundary. Dart approval is only a UI prerequisite.
class LiveBrowsingPolicy {
  const LiveBrowsingPolicy.unavailable([this.errorCode = 'not-loaded'])
    : sites = const [],
      reviewedAt = null,
      expiresAt = null,
      sequence = 0,
      privacyVersion = null,
      blockedThirdPartyDomains = const {};

  const LiveBrowsingPolicy._({
    required this.sites,
    required this.reviewedAt,
    required this.expiresAt,
    required this.sequence,
    required this.privacyVersion,
    required this.blockedThirdPartyDomains,
  }) : errorCode = null;

  static const assetPath = 'assets/policy/live_sites.json';
  static const maxManifestBytes = 512 * 1024;
  static bool _licensesRegistered = false;
  final List<LiveSiteRecord> sites;
  final DateTime? reviewedAt, expiresAt;
  final int sequence;
  final String? privacyVersion, errorCode;
  final Set<String> blockedThirdPartyDomains;

  static Future<LiveBrowsingPolicy> load({AssetBundle? bundle}) async {
    if (bundle == null && !_licensesRegistered) {
      _licensesRegistered = true;
      LicenseRegistry.addLicense(() async* {
        final license = await rootBundle.loadString(
          'assets/policy/live_privacy_license.txt',
        );
        yield LicenseEntryWithLineBreaks(
          const ['EasyPrivacy domain-rule adaptation'],
          'Adapted from EasyPrivacy by The EasyList authors '
          '(https://easylist.to/). Distributed under CC BY-SA 3.0. '
          'Wingman selected 2,501 exact third-party domain rules from commit '
          '7f83d42234e8a2737a924bbd4d3d0301da0f224e, converted them to JSON '
          'suffix rules, and excludes top-level navigation. This is a '
          'supported subset, not all of EasyPrivacy. No endorsement is claimed. '
          'Source: https://github.com/easylist/easylist/blob/'
          '7f83d42234e8a2737a924bbd4d3d0301da0f224e/easyprivacy/'
          'easyprivacy_trackingservers_thirdparty.txt\n\n$license',
        );
      });
    }
    try {
      final data = await (bundle ?? rootBundle).load(assetPath);
      if (data.lengthInBytes > maxManifestBytes) {
        return const LiveBrowsingPolicy.unavailable('manifest-size');
      }
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final digest = await Sha256().hash(bytes);
      final actual = digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      if (actual != liveManifestSha256) {
        return const LiveBrowsingPolicy.unavailable('manifest-integrity');
      }
      return _parse(jsonDecode(utf8.decode(bytes)));
    } catch (_) {
      return const LiveBrowsingPolicy.unavailable('manifest-unavailable');
    }
  }

  bool isUsable({DateTime? now}) {
    final time = now ?? DateTime.now().toUtc();
    return errorCode == null &&
        reviewedAt != null &&
        expiresAt != null &&
        !time.isBefore(reviewedAt!) &&
        time.isBefore(expiresAt!);
  }

  /// Includes disabled research candidates so their unavailable state can be
  /// explained. Callers must evaluate before every navigation or display.
  LiveSiteRecord? siteForUri(Uri uri) {
    final url = _canonicalHttps(uri);
    if (url == null) return null;
    for (final site in sites) {
      if (site.documents.any((document) => document.url == url)) return site;
    }
    return null;
  }

  PolicyDecision assessNavigation(
    Uri uri, {
    ContentContext context = ContentContext.general,
    AdditionalRestrictions? additional,
    DateTime? now,
  }) {
    final time = now ?? DateTime.now().toUtc();
    if (!isUsable(now: time)) {
      return const PolicyDecision(PolicyDecisionCode.blockPolicyUnavailable);
    }
    final site = siteForUri(uri);
    if (site == null) {
      return const PolicyDecision(PolicyDecisionCode.blockUnreviewed);
    }
    if (!site.enabled || !site.isCurrent(time)) {
      return const PolicyDecision(
        PolicyDecisionCode.blockUnsupportedCapability,
      );
    }
    if (!site.contexts.contains(context)) {
      return const PolicyDecision(PolicyDecisionCode.blockUnreviewed);
    }
    if (additional?.blockedResourceIds.contains(site.id) == true ||
        additional?.blockedCollections.contains(site.collection) == true) {
      return PolicyDecision(
        PolicyDecisionCode.blockAdditionalRestriction,
        resourceId: site.id,
        safeTitle: site.title,
      );
    }
    return PolicyDecision(
      PolicyDecisionCode.allowApproved,
      resourceId: site.id,
      safeTitle: site.title,
    );
  }

  /// Native policy parity oracle. It grants only listed passive resources of
  /// an already eligible top-level document. POST, nested HTML, scripts, APIs,
  /// unknown resource types and any unlisted redirect destination fail closed.
  PolicyDecision assessResource(
    Uri uri, {
    required Uri topDocument,
    required LiveResourceType type,
    String method = 'GET',
    ContentContext context = ContentContext.general,
    AdditionalRestrictions? additional,
    DateTime? now,
  }) {
    final parent = assessNavigation(
      topDocument,
      context: context,
      additional: additional,
      now: now,
    );
    if (!parent.isAllowed) return parent;
    if (method != 'GET' || type == LiveResourceType.document) {
      return const PolicyDecision(
        PolicyDecisionCode.blockUnsupportedCapability,
      );
    }
    final url = _canonicalHttps(uri);
    if (url == null || isKnownThirdPartyTracker(uri, topDocument)) {
      return const PolicyDecision(PolicyDecisionCode.blockUnreviewed);
    }
    final site = siteForUri(topDocument)!;
    if (!site.resources.any((r) => r.url == url && r.type == type)) {
      return const PolicyDecision(PolicyDecisionCode.blockUnreviewed);
    }
    return parent;
  }

  /// This deliberately matches the imported suffix-domain rules only. The
  /// positive resource scope supplies the stricter default-deny boundary.
  /// Same-host access is not called third party; no eTLD/PSL approximation is
  /// presented as an implementation of the entire EasyPrivacy language.
  bool isKnownThirdPartyTracker(Uri uri, Uri topDocument) {
    final host = uri.host.toLowerCase();
    if (host == topDocument.host.toLowerCase()) return false;
    var suffix = host;
    while (suffix.contains('.')) {
      if (blockedThirdPartyDomains.contains(suffix)) return true;
      suffix = suffix.substring(suffix.indexOf('.') + 1);
    }
    return false;
  }

  static LiveBrowsingPolicy _parse(Object? value) {
    final root = _object(value, const {
      'schemaVersion',
      'sequence',
      'policyVersion',
      'reviewedAt',
      'expiresAt',
      'sites',
      'privacy',
    });
    if (root['schemaVersion'] != 1 ||
        root['sequence'] != 1 ||
        root['policyVersion'] != MandatorySafetyPolicy.version) {
      throw const FormatException('Unsupported live policy');
    }
    final reviewed = _date(root['reviewedAt']);
    final expires = _date(root['expiresAt']);
    _window(reviewed, expires);
    final allDocumentUrls = <String>{};
    final ids = <String>{};
    final sites = <LiveSiteRecord>[];
    for (final value in _list(root['sites'], 32)) {
      final site = _object(value, const {
        'id',
        'title',
        'description',
        'collection',
        'entryUrl',
        'enabled',
        'contexts',
        'reviewedAt',
        'expiresAt',
        'documents',
        'resources',
        'limitations',
      });
      final id = _text(site['id'], 80);
      final collection = _text(site['collection'], 80);
      if (!validResourceId(id) ||
          !ids.add(id) ||
          !validResourceId(collection) ||
          site['enabled'] is! bool) {
        throw const FormatException('Invalid live site');
      }
      final siteReviewed = _date(site['reviewedAt']);
      final siteExpires = _date(site['expiresAt']);
      _window(siteReviewed, siteExpires);
      if (siteReviewed.isBefore(reviewed) || siteExpires.isAfter(expires)) {
        throw const FormatException('Site outside policy window');
      }
      final contexts = _list(site['contexts'], 2).map((value) {
        return ContentContext.values.byName(_text(value, 20));
      }).toSet();
      if (contexts.isEmpty) throw const FormatException('Missing context');
      final documents = _list(
        site['documents'],
        64,
      ).map((v) => _resource(v, document: true)).toList();
      if (documents.isEmpty ||
          documents.any((d) => !allDocumentUrls.add(d.url))) {
        throw const FormatException('Duplicate or missing document');
      }
      final entryUrl = _url(site['entryUrl']);
      if (!documents.any((d) => d.url == entryUrl)) {
        throw const FormatException('Entry outside document scope');
      }
      final resourceUrls = <String>{};
      final resources = _list(
        site['resources'],
        1024,
      ).map((v) => _resource(v, document: false)).toList();
      if (resources.any((r) => !resourceUrls.add(r.url))) {
        throw const FormatException('Duplicate resource');
      }
      sites.add(
        LiveSiteRecord._(
          id: id,
          title: _text(site['title'], 120),
          description: _text(site['description'], 500),
          collection: collection,
          entryUrl: entryUrl,
          enabled: site['enabled'] as bool,
          contexts: Set.unmodifiable(contexts),
          reviewedAt: siteReviewed,
          expiresAt: siteExpires,
          documents: List.unmodifiable(documents),
          resources: List.unmodifiable(resources),
          limitations: List.unmodifiable(
            _list(site['limitations'], 10).map((v) => _text(v, 1000)),
          ),
        ),
      );
    }
    final privacy = _object(root['privacy'], const {
      'version',
      'sourceUrl',
      'sourceCommit',
      'sourceSha256',
      'license',
      'scope',
      'domains',
    });
    if (privacy['license'] != 'CC-BY-SA-3.0' ||
        privacy['scope'] != 'third-party-subresources' ||
        !RegExp(
          r'^[a-f0-9]{40}$',
        ).hasMatch(_text(privacy['sourceCommit'], 40)) ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(_text(privacy['sourceSha256'], 64))) {
      throw const FormatException('Invalid privacy provenance');
    }
    _url(privacy['sourceUrl']);
    final domains = <String>{};
    for (final value in _list(privacy['domains'], 10000)) {
      final domain = _text(value, 253);
      if (!_validHost(domain) || !domains.add(domain)) {
        throw const FormatException('Invalid privacy domain');
      }
    }
    return LiveBrowsingPolicy._(
      sites: List.unmodifiable(sites),
      reviewedAt: reviewed,
      expiresAt: expires,
      sequence: root['sequence'] as int,
      privacyVersion: _text(privacy['version'], 80),
      blockedThirdPartyDomains: Set.unmodifiable(domains),
    );
  }

  static LiveResourceRecord _resource(Object? value, {required bool document}) {
    final r = _object(value, {
      'url',
      'mimeTypes',
      'maxBytes',
      if (!document) 'type',
    });
    final type = document
        ? LiveResourceType.document
        : LiveResourceType.values.byName(_text(r['type'], 20));
    if (!document && type == LiveResourceType.document) {
      throw const FormatException('Nested document');
    }
    final mime = _list(r['mimeTypes'], 8).map((v) => _text(v, 80)).toSet();
    final allowedMime = switch (type) {
      LiveResourceType.document => const {'text/html'},
      LiveResourceType.image => const {
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/svg+xml',
      },
      LiveResourceType.styleSheet => const {'text/css'},
      LiveResourceType.font => const {
        'font/woff',
        'font/woff2',
        'application/font-woff',
        'application/octet-stream',
      },
    };
    if (mime.isEmpty ||
        !allowedMime.containsAll(mime) ||
        r['maxBytes'] is! int ||
        (r['maxBytes'] as int) <= 0 ||
        (r['maxBytes'] as int) > 8 * 1024 * 1024) {
      throw const FormatException('Invalid resource limits');
    }
    return LiveResourceRecord._(
      url: _url(r['url']),
      type: type,
      mimeTypes: Set.unmodifiable(mime),
      maxBytes: r['maxBytes'] as int,
    );
  }
}

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !keys.containsAll(value.keys)) {
    throw const FormatException('Unknown or missing live policy fields');
  }
  return value;
}

List<dynamic> _list(Object? value, int maximum) {
  if (value is! List || value.length > maximum) {
    throw const FormatException('Invalid live policy list');
  }
  return value;
}

String _text(Object? value, int maximum) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maximum ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException('Invalid live policy text');
  }
  return value;
}

DateTime _date(Object? value) {
  final text = _text(value, 20);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$').hasMatch(text)) {
    throw const FormatException('Invalid live policy date');
  }
  return DateTime.parse(text);
}

void _window(DateTime start, DateTime end) {
  if (!end.isAfter(start) || end.difference(start).inHours > 24 * 31) {
    throw const FormatException('Invalid live policy review window');
  }
}

String _url(Object? value) {
  final raw = _text(value, 4096);
  final uri = Uri.parse(raw);
  final normalized = _canonicalHttps(uri);
  if (normalized == null || uri.hasFragment || normalized != raw) {
    throw const FormatException('Noncanonical live policy URL');
  }
  return normalized;
}

String? _canonicalHttps(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      !_validHost(uri.host) ||
      uri.toString().length > 4096 ||
      RegExp(r'[^\x21-\x7e]').hasMatch(uri.toString()) ||
      RegExp(r'%(?:00|0a|0d|2f|5c)', caseSensitive: false).hasMatch(uri.path) ||
      uri.pathSegments.any((p) => p == '.' || p == '..' || p.contains('\\'))) {
    return null;
  }
  return uri.removeFragment().toString();
}

bool _validHost(String host) =>
    host.length <= 253 &&
    host.contains('.') &&
    !RegExp(r'^[0-9.]+$').hasMatch(host) &&
    !host.endsWith('.local') &&
    !host.endsWith('.localhost') &&
    !host.endsWith('.internal') &&
    !host.endsWith('.test') &&
    host
        .split('.')
        .every(
          (label) =>
              RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(label),
        );
