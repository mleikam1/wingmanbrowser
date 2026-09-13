import 'dart:convert';
import 'package:flutter/services.dart';

String feedText(Object? value, {int max = 500, bool empty = false}) {
  if (value is! String ||
      value.length > max ||
      RegExp(
        r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u202a-\u202e\u2066-\u2069]',
      ).hasMatch(value)) {
    throw const FormatException('Invalid feed text.');
  }
  final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if ((!empty && clean.isEmpty) ||
      RegExp(r'<[/!a-zA-Z][^>]*>').hasMatch(clean)) {
    throw const FormatException('Feed text must be plain text.');
  }
  return clean;
}

String feedId(Object? value) {
  final id = feedText(value, max: 160);
  if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,159}$').hasMatch(id)) {
    throw const FormatException('Invalid feed identifier.');
  }
  return id;
}

DateTime feedDate(Object? value) {
  if (value is! String || value.length > 40) {
    throw const FormatException('Missing feed date.');
  }
  final date = DateTime.tryParse(value);
  if (date == null || !date.isUtc) {
    throw const FormatException('Feed dates need a timezone.');
  }
  return date.toUtc();
}

Uri feedArticleUri(Object? value) {
  if (value is! String ||
      value.length > 4096 ||
      RegExp(r'[\x00-\x20\\]').hasMatch(value)) {
    throw const FormatException('Invalid article address.');
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443) ||
      uri.host.endsWith('.') ||
      uri.host.contains('%')) {
    throw const FormatException('Articles require a public HTTPS address.');
  }
  return uri.removeFragment();
}

Set<String> feedIds(Object? value, {int max = 500}) {
  if (value is! List || value.length > max) {
    throw const FormatException('Invalid feed list.');
  }
  return Set.unmodifiable(value.map(feedId));
}

Map<String, dynamic> feedMap(Object? value) {
  if (value is! Map) throw const FormatException('Invalid feed object.');
  return Map<String, dynamic>.from(value);
}

class LiveContentRights {
  const LiveContentRights({
    required this.titles,
    required this.excerpts,
    required this.images,
    required this.attribution,
    required this.licenseUrl,
  });
  factory LiveContentRights.fromJson(Map<String, dynamic> json) =>
      LiveContentRights(
        titles: json['titles'] == true || json['title'] == true,
        excerpts: json['excerpts'] == true || json['excerpt'] == true,
        images: json['images'] == true || json['image'] == true,
        attribution: feedText(json['attribution'] ?? '', max: 500, empty: true),
        licenseUrl: json['licenseUrl'] == null
            ? null
            : feedArticleUri(json['licenseUrl']),
      );
  final bool titles, excerpts, images;
  final String attribution;
  final Uri? licenseUrl;
  Map<String, Object?> toJson() => {
    'titles': titles,
    'excerpts': excerpts,
    'images': images,
    'attribution': attribution,
    'licenseUrl': licenseUrl?.toString(),
  };
}

class LiveSource {
  const LiveSource({
    required this.id,
    required this.name,
    required this.homepageUrl,
    required this.language,
    required this.topics,
    required this.rights,
    this.status = 'fresh',
    this.fetchedAt,
    this.lastSuccessAt,
    this.nextRefreshAt,
  });
  factory LiveSource.fromJson(Map<String, dynamic> json) => LiveSource(
    id: feedId(json['id']),
    name: feedText(json['name'], max: 160),
    homepageUrl: feedArticleUri(json['homepageUrl']),
    language: feedId(json['language']),
    topics: feedIds(json['topics'], max: 20),
    rights: LiveContentRights.fromJson(feedMap(json['rights'])),
    status: feedText(json['status'] ?? 'fresh', max: 40),
    fetchedAt: json['fetchedAt'] == null ? null : feedDate(json['fetchedAt']),
    lastSuccessAt: json['lastSuccessAt'] == null
        ? null
        : feedDate(json['lastSuccessAt']),
    nextRefreshAt: json['nextRefreshAt'] == null
        ? null
        : feedDate(json['nextRefreshAt']),
  );
  final String id, name, language, status;
  final Uri homepageUrl;
  final Set<String> topics;
  final LiveContentRights rights;
  final DateTime? fetchedAt, lastSuccessAt, nextRefreshAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'homepageUrl': homepageUrl.toString(),
    'language': language,
    'topics': topics.toList(),
    'rights': rights.toJson(),
    'status': status,
    'fetchedAt': fetchedAt?.toIso8601String(),
    'lastSuccessAt': lastSuccessAt?.toIso8601String(),
    'nextRefreshAt': nextRefreshAt?.toIso8601String(),
  };
}

class ApprovedLiveSource {
  ApprovedLiveSource({
    required this.source,
    required this.allowedArticleHosts,
    required this.articlePathPrefixes,
    required this.eligibilityScope,
    required this.enabled,
    this.feedUri,
    this.feedRedirectHosts = const {},
    this.minRefreshSeconds = 1800,
    this.retentionSeconds = 604800,
    this.verifiedAt,
    this.articleUrlFormat = 'path-prefix',
    this.requiredTopicTerms = const {},
    this.requiresAttribution = false,
  });
  factory ApprovedLiveSource.fromJson(Map<String, dynamic> json) {
    final hosts = feedIds(json['allowedArticleHosts'], max: 20);
    if (hosts.any(
      (host) => !RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$').hasMatch(host),
    )) {
      throw const FormatException('Invalid approved source hosts.');
    }
    final paths = json['articlePathPrefixes'];
    if (paths is! List ||
        paths.isEmpty ||
        paths.length > 30 ||
        paths.any(
          (p) =>
              p is! String ||
              !p.startsWith('/') ||
              p.length > 256 ||
              p.contains('%') ||
              p.contains('..') ||
              p.contains('\\') ||
              p.contains('?') ||
              p.contains('#'),
        )) {
      throw const FormatException('Invalid approved source paths.');
    }
    final feed = json['feedUrl'] == null
        ? null
        : feedArticleUri(json['feedUrl']);
    final redirects = feedIds(json['feedRedirectHosts'] ?? [], max: 10);
    if (feed != null &&
            ((json['feedUrl'] as String).contains('#') ||
                !redirects.contains(feed.host)) ||
        redirects.any(
          (h) => !RegExp(r'^[a-z0-9-]+(?:\.[a-z0-9-]+)+$').hasMatch(h),
        )) {
      throw const FormatException('Invalid pinned feed origin.');
    }
    int bound(String key, int fallback, int low, int high) {
      final value = json[key] ?? fallback;
      if (value is! int || value < low || value > high) {
        throw const FormatException('Invalid feed schedule.');
      }
      return value;
    }

    final format = json['articleUrlFormat'] ?? 'path-prefix';
    if (format != 'path-prefix' && format != 'dated-story') {
      throw const FormatException('Invalid article format.');
    }
    final terms = json['requiredTopicTerms'] ?? [];
    if (terms is! List || terms.length > 30) {
      throw const FormatException('Invalid topic terms.');
    }
    final topicTerms = terms
        .map((v) => feedText(v, max: 80).toLowerCase())
        .toSet();
    return ApprovedLiveSource(
      source: LiveSource.fromJson(json),
      allowedArticleHosts: hosts,
      articlePathPrefixes: Set.unmodifiable(paths.cast<String>()),
      eligibilityScope: feedId(json['eligibilityScope']),
      enabled: json['enabled'] == true,
      requiredTopicTerms: Set.unmodifiable(topicTerms),
      requiresAttribution: json['requiresAttribution'] == true,
      articleUrlFormat: format as String,
      feedUri: feed,
      feedRedirectHosts: redirects,
      minRefreshSeconds: bound('minRefreshSeconds', 1800, 1800, 31622400),
      retentionSeconds: bound('retentionSeconds', 604800, 3600, 2592000),
      verifiedAt: json['verifiedAt'] == null
          ? null
          : feedDate(json['verifiedAt']),
    );
  }
  final LiveSource source;
  final Set<String> allowedArticleHosts, articlePathPrefixes;
  final String eligibilityScope;
  final bool enabled;
  final Uri? feedUri;
  final Set<String> feedRedirectHosts;
  final int minRefreshSeconds, retentionSeconds;
  final DateTime? verifiedAt;
  final String articleUrlFormat;
  final Set<String> requiredTopicTerms;
  final bool requiresAttribution;
}

class LiveSourceRegistry {
  LiveSourceRegistry(Iterable<ApprovedLiveSource> sources)
    : sources = Map.unmodifiable({
        for (final source in sources) source.source.id: source,
      });
  factory LiveSourceRegistry.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 ||
        json['sources'] is! List ||
        (json['sources'] as List).length > 50) {
      throw const FormatException('Invalid approved source registry.');
    }
    final rows = (json['sources'] as List)
        .map((v) => ApprovedLiveSource.fromJson(feedMap(v)))
        .toList();
    if (rows.map((s) => s.source.id).toSet().length != rows.length) {
      throw const FormatException('Duplicate source.');
    }
    return LiveSourceRegistry(rows);
  }
  static Future<LiveSourceRegistry> loadBundled() async =>
      LiveSourceRegistry.fromJson(
        feedMap(
          jsonDecode(
            await rootBundle.loadString('assets/live_content/sources.json'),
          ),
        ),
      );
  final Map<String, ApprovedLiveSource> sources;
}

class LiveContentItem {
  const LiveContentItem({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.canonicalUrl,
    required this.publishedAt,
    required this.fetchedAt,
    required this.language,
    required this.topics,
    required this.rights,
    required this.eligibilityState,
    required this.eligibilityBasis,
    required this.eligibilityScope,
    required this.expiresAt,
    this.excerpt,
    this.attribution,
    this.region,
    this.reviewedAt,
  });
  factory LiveContentItem.fromJson(Map<String, dynamic> json) {
    final eligibility = feedMap(json['eligibility']);
    return LiveContentItem(
      id: feedId(json['id']),
      sourceId: feedId(json['sourceId']),
      title: feedText(json['title'], max: 500),
      excerpt: json['excerpt'] == null
          ? null
          : feedText(json['excerpt'], max: 1600, empty: true),
      attribution: json['attribution'] == null
          ? null
          : feedText(json['attribution'], max: 200, empty: true),
      canonicalUrl: feedArticleUri(json['canonicalUrl']),
      publishedAt: json['publishedAt'] == null
          ? null
          : feedDate(json['publishedAt']),
      fetchedAt: feedDate(json['fetchedAt']),
      language: feedId(json['language']),
      topics: feedIds(json['topics'], max: 20),
      rights: LiveContentRights.fromJson(feedMap(json['rights'])),
      eligibilityState: feedId(eligibility['state']),
      eligibilityBasis: feedId(eligibility['basis']),
      eligibilityScope: feedId(eligibility['scope']),
      reviewedAt: eligibility['reviewedAt'] == null
          ? null
          : feedDate(eligibility['reviewedAt']),
      expiresAt: feedDate(json['expiresAt']),
      region: json['region'] == null ? null : feedId(json['region']),
    );
  }
  final String id,
      sourceId,
      title,
      language,
      eligibilityState,
      eligibilityBasis,
      eligibilityScope;
  final String? excerpt, region, attribution;
  final Uri canonicalUrl;
  final DateTime? publishedAt, reviewedAt;
  final DateTime fetchedAt, expiresAt;
  final Set<String> topics;
  final LiveContentRights rights;

  /// No remote thumbnail is exposed by the client. Image approval needs its own
  /// pinned rights/moderation contract, not merely an image URL in a feed.
  Uri? get imageUrl => null;
  Map<String, Object?> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'title': title,
    'excerpt': excerpt,
    'attribution': attribution,
    'canonicalUrl': canonicalUrl.toString(),
    'publishedAt': publishedAt?.toIso8601String(),
    'fetchedAt': fetchedAt.toIso8601String(),
    'language': language,
    'topics': topics.toList(),
    'region': region,
    'rights': rights.toJson(),
    'eligibility': {
      'state': eligibilityState,
      'basis': eligibilityBasis,
      'scope': eligibilityScope,
      'reviewedAt': reviewedAt?.toIso8601String(),
    },
    'expiresAt': expiresAt.toIso8601String(),
    'image': null,
  };
}

class LiveSnapshot {
  const LiveSnapshot({
    required this.snapshotId,
    required this.generatedAt,
    required this.expiresAt,
    required this.sources,
    required this.items,
    this.revokedItemIds = const {},
    this.revokedSourceIds = const {},
    this.staleSourceIds = const {},
    this.rejectedItems = 0,
  });
  factory LiveSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 ||
        json['items'] is! List ||
        (json['items'] as List).length > 300 ||
        json['sources'] is! List ||
        (json['sources'] as List).length > 50) {
      throw const FormatException('Invalid snapshot.');
    }
    final sources = (json['sources'] as List)
        .map((s) => LiveSource.fromJson(feedMap(s)))
        .toList();
    if (sources.map((s) => s.id).toSet().length != sources.length) {
      throw const FormatException('Duplicate source.');
    }
    final items = <LiveContentItem>[];
    var rejected = 0;
    final ids = <String>{}, urls = <String>{};
    for (final raw in json['items'] as List) {
      try {
        final item = LiveContentItem.fromJson(feedMap(raw));
        if (ids.contains(item.id) ||
            urls.contains(item.canonicalUrl.toString())) {
          continue;
        }
        ids.add(item.id);
        urls.add(item.canonicalUrl.toString());
        items.add(item);
      } on FormatException {
        rejected++;
      }
    }
    final generated = feedDate(json['generatedAt']),
        expires = feedDate(json['expiresAt']);
    if (expires.isBefore(generated)) {
      throw const FormatException('Invalid snapshot lifetime.');
    }
    return LiveSnapshot(
      snapshotId: feedId(json['snapshotId']),
      generatedAt: generated,
      expiresAt: expires,
      sources: List.unmodifiable(sources),
      items: List.unmodifiable(items),
      rejectedItems: rejected,
      revokedItemIds: feedIds(json['revokedItemIds'] ?? [], max: 5000),
      revokedSourceIds: feedIds(json['revokedSourceIds'] ?? [], max: 50),
      staleSourceIds: feedIds(json['staleSourceIds'] ?? [], max: 50),
    );
  }
  final String snapshotId;
  final DateTime generatedAt, expiresAt;
  final List<LiveSource> sources;
  final List<LiveContentItem> items;
  final Set<String> revokedItemIds, revokedSourceIds, staleSourceIds;
  final int rejectedItems;
  LiveSnapshot withItems(List<LiveContentItem> value) => LiveSnapshot(
    snapshotId: snapshotId,
    generatedAt: generatedAt,
    expiresAt: expiresAt,
    sources: sources,
    items: value,
    revokedItemIds: revokedItemIds,
    revokedSourceIds: revokedSourceIds,
    staleSourceIds: staleSourceIds,
    rejectedItems: rejectedItems,
  );
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'snapshotId': snapshotId,
    'generatedAt': generatedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'sources': sources.map((s) => s.toJson()).toList(),
    'items': items.map((i) => i.toJson()).toList(),
    'revokedItemIds': revokedItemIds.toList(),
    'revokedSourceIds': revokedSourceIds.toList(),
    'staleSourceIds': staleSourceIds.toList(),
  };
}
