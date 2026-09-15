import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'branding.dart';
import 'syndicated_article.dart';

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

/// Stable identity removes only recognized analytics parameters. The original
/// publisher link remains available separately for navigation and attribution.
Uri feedCanonicalIdentity(Uri uri) {
  final query = <String, dynamic>{};
  uri.queryParametersAll.forEach((key, values) {
    if (!key.toLowerCase().startsWith('utm_') &&
        !{'fbclid', 'gclid', 'mc_cid', 'mc_eid'}.contains(key.toLowerCase())) {
      query[key] = values;
    }
  });
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    queryParameters: query.isEmpty ? null : query,
  );
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

/// Only a bundled source rule can authorize this publisher's supplied image.
/// The initial rule deliberately covers exact RSS thumbnails, not article heroes.
class ApprovedImagePolicy {
  const ApprovedImagePolicy({
    required this.kind,
    required this.allowedHosts,
    required this.pathPrefixes,
    required this.licenseUrl,
    required this.licenseLabel,
    required this.credit,
    required this.maximumWidth,
    required this.maximumHeight,
    this.allowedQueryKeys = const {},
    this.reviewedArticles = const {},
  });
  factory ApprovedImagePolicy.fromJson(Map<String, dynamic> json) {
    final kind = feedId(json['kind']);
    if (!{
      'syndicated-feed-thumbnail',
      'syndicated-article-photo',
      'reviewed-article-image',
    }.contains(kind)) {
      throw const FormatException('Unknown publisher image policy.');
    }
    final hosts = feedIds(json['allowedHosts'], max: 10);
    final paths = json['pathPrefixes'];
    final width = json['maximumWidth'], height = json['maximumHeight'];
    if (hosts.isEmpty ||
        hosts.any(
          (h) => !RegExp(r'^[a-z0-9-]+(?:\.[a-z0-9-]+)+$').hasMatch(h),
        ) ||
        paths is! List ||
        paths.isEmpty ||
        paths.length > 10 ||
        paths.any(
          (p) =>
              p is! String ||
              !p.startsWith('/') ||
              p.length > 256 ||
              RegExp(r'[\x00-\x20%\\?#]').hasMatch(p) ||
              p.contains('..'),
        ) ||
        width is! int ||
        height is! int ||
        width < 1 ||
        height < 1 ||
        width > 2048 ||
        height > 2048) {
      throw const FormatException('Invalid publisher image policy.');
    }
    final reviewed = <String, LiveArticleImage>{};
    final mappings = json['reviewedArticles'] ?? <String, Object?>{};
    if (mappings is! Map || mappings.length > 100) {
      throw const FormatException('Invalid reviewed article images.');
    }
    for (final entry in mappings.entries) {
      final article = feedArticleUri(entry.key);
      final image = LiveArticleImage.fromJson(feedMap(entry.value));
      if (entry.key != article.toString() ||
          image.articleUrl != article ||
          image.basis != 'reviewed-article-image' ||
          image.articleId !=
              sha256
                  .convert(utf8.encode(article.toString()))
                  .toString()
                  .substring(0, 32)) {
        throw const FormatException(
          'Reviewed image must bind its exact article.',
        );
      }
      reviewed[entry.key as String] = image;
    }
    if ((kind == 'reviewed-article-image') != reviewed.isNotEmpty) {
      throw const FormatException(
        'Reviewed image policy requires exact mappings.',
      );
    }
    final policy = ApprovedImagePolicy(
      kind: kind,
      allowedHosts: hosts,
      pathPrefixes: Set.unmodifiable(paths.cast<String>()),
      licenseUrl: feedArticleUri(json['licenseUrl']),
      licenseLabel: feedText(json['licenseLabel'], max: 100),
      credit: feedText(json['credit'], max: 200),
      maximumWidth: width,
      maximumHeight: height,
      allowedQueryKeys: feedIds(json['allowedQueryKeys'] ?? [], max: 5),
      reviewedArticles: Map.unmodifiable(reviewed),
    );
    if (reviewed.values.any(
      (image) =>
          !policy.acceptsUri(image.url) ||
          image.width > width ||
          image.height > height,
    )) {
      throw const FormatException(
        'Reviewed image exceeds pinned source limits.',
      );
    }
    return policy;
  }
  final String kind, licenseLabel, credit;
  final Set<String> allowedHosts, pathPrefixes;
  final Set<String> allowedQueryKeys;
  final Uri licenseUrl;
  final int maximumWidth, maximumHeight;
  final Map<String, LiveArticleImage> reviewedArticles;
  bool acceptsUri(Uri uri) {
    try {
      if (feedArticleUri(uri.toString()) != uri ||
          uri.hasFragment ||
          !allowedHosts.contains(uri.host)) {
        return false;
      }
      final path = Uri.decodeComponent(uri.path);
      if (RegExp(r'[\x00-\x1f\\%]').hasMatch(path) ||
          path.split('/').any((p) => p == '.' || p == '..')) {
        return false;
      }
      if (kind == 'reviewed-article-image') {
        if (!reviewedArticles.values.any((image) => image.url == uri)) {
          return false;
        }
      } else if (uri.queryParametersAll.entries.any(
        (e) =>
            !allowedQueryKeys.contains(e.key) ||
            e.value.length != 1 ||
            !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(e.value.single),
      )) {
        return false;
      }
      return pathPrefixes.any(
        (p) => path == p || path.startsWith(p.endsWith('/') ? p : '$p/'),
      );
    } catch (_) {
      return false;
    }
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'allowedHosts': allowedHosts.toList()..sort(),
    'pathPrefixes': pathPrefixes.toList()..sort(),
    'licenseUrl': licenseUrl.toString(),
    'licenseLabel': licenseLabel,
    'credit': credit,
    'maximumWidth': maximumWidth,
    'maximumHeight': maximumHeight,
    'allowedQueryKeys': allowedQueryKeys.toList()..sort(),
    if (reviewedArticles.isNotEmpty)
      'reviewedArticles': {
        for (final entry in reviewedArticles.entries)
          entry.key: entry.value.toJson(),
      },
  };
}

class LiveArticleImage {
  const LiveArticleImage({
    required this.url,
    required this.articleUrl,
    required this.sourceId,
    required this.credit,
    required this.caption,
    required this.licenseUrl,
    required this.licenseLabel,
    required this.basis,
    required this.width,
    required this.height,
    this.articleId,
  });
  factory LiveArticleImage.fromJson(Map<String, dynamic> json) {
    final width = json['width'], height = json['height'];
    if (json['schemaVersion'] != 1 ||
        width is! int ||
        height is! int ||
        width < 0 ||
        height < 0 ||
        ((width == 0 || height == 0) &&
            json['basis'] != 'syndicated-article-photo') ||
        width > 2048 ||
        height > 2048) {
      throw const FormatException('Invalid article image.');
    }
    return LiveArticleImage(
      url: feedArticleUri(json['url']),
      articleUrl: feedArticleUri(json['articleUrl']),
      sourceId: feedId(json['sourceId']),
      articleId: json['articleId'] == null ? null : feedId(json['articleId']),
      credit: feedText(json['credit'], max: 200),
      caption: feedText(json['caption'], max: 500),
      licenseUrl: feedArticleUri(json['licenseUrl']),
      licenseLabel: feedText(json['licenseLabel'], max: 100),
      basis: feedId(json['basis']),
      width: width,
      height: height,
    );
  }
  final Uri url, articleUrl, licenseUrl;
  final String sourceId, credit, caption, licenseLabel, basis;
  final String? articleId;
  final int width, height;
  bool get preserveAspectRatio => true;
  String get displayLabel => basis == 'reviewed-article-image'
      ? 'Reviewed story image'
      : basis == 'syndicated-article-photo'
      ? 'Supplied story photo'
      : 'Publisher thumbnail';
  String get cacheKey =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'url': url.toString(),
    'articleUrl': articleUrl.toString(),
    'sourceId': sourceId,
    if (articleId != null) 'articleId': articleId,
    'credit': credit,
    'caption': caption,
    'licenseUrl': licenseUrl.toString(),
    'licenseLabel': licenseLabel,
    'basis': basis,
    'width': width,
    'height': height,
  };
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
    this.imagePolicy,
    this.preserveFeedText = false,
    this.branding,
    this.feedCompatibility,
    String? displayMode,
  }) : displayMode =
           displayMode ??
           (imagePolicy?.kind == 'syndicated-article-photo'
               ? 'sponsored-syndication'
               : 'publisher-link');
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
    final compatibility = json['feedCompatibility'];
    if (compatibility != null &&
        (compatibility != 'nasa-photojournal-self-link-v1' ||
            json['id'] != 'nasa-photojournal' ||
            feed?.toString() !=
                'https://science.nasa.gov/feed/photojournal/latest-content/')) {
      throw const FormatException('Invalid source feed compatibility.');
    }
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
    final imagePolicy = json['imagePolicy'] == null
        ? null
        : ApprovedImagePolicy.fromJson(feedMap(json['imagePolicy']));
    final displayMode =
        json['displayMode'] ??
        (imagePolicy?.kind == 'syndicated-article-photo'
            ? 'sponsored-syndication'
            : 'publisher-link');
    if (!{'publisher-link', 'sponsored-syndication'}.contains(displayMode) ||
        (displayMode == 'sponsored-syndication') !=
            (imagePolicy?.kind == 'syndicated-article-photo') ||
        (imagePolicy?.reviewedArticles.values.any(
              (image) => image.sourceId != json['id'],
            ) ??
            false)) {
      throw const FormatException(
        'Invalid source display or image association.',
      );
    }
    return ApprovedLiveSource(
      source: LiveSource.fromJson(json),
      allowedArticleHosts: hosts,
      articlePathPrefixes: Set.unmodifiable(paths.cast<String>()),
      eligibilityScope: feedId(json['eligibilityScope']),
      enabled: json['enabled'] == true,
      requiredTopicTerms: Set.unmodifiable(topicTerms),
      requiresAttribution: json['requiresAttribution'] == true,
      imagePolicy: imagePolicy,
      branding: PublisherBranding.tryFromJson(json['branding']),
      displayMode: displayMode as String,
      feedCompatibility: compatibility as String?,
      preserveFeedText: json['preserveFeedText'] == true,
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
  final ApprovedImagePolicy? imagePolicy;
  final bool preserveFeedText;
  final PublisherBranding? branding;
  final String? feedCompatibility;
  final String displayMode;
  bool get isSponsoredSyndication => displayMode == 'sponsored-syndication';
}

class LiveSourceRegistry {
  LiveSourceRegistry(
    Iterable<ApprovedLiveSource> sources, {
    this.requireStoryImages = false,
  }) : sources = Map.unmodifiable({
         for (final source in sources) source.source.id: source,
       });
  factory LiveSourceRegistry.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 ||
        json['sources'] is! List ||
        (json['sources'] as List).length > 256) {
      throw const FormatException('Invalid approved source registry.');
    }
    final rows = (json['sources'] as List)
        .map((v) => ApprovedLiveSource.fromJson(feedMap(v)))
        .toList();
    if (rows.map((s) => s.source.id).toSet().length != rows.length) {
      throw const FormatException('Duplicate source.');
    }
    return LiveSourceRegistry(
      rows,
      requireStoryImages: json['requireStoryImages'] == true,
    );
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
  final bool requireStoryImages;
}

class LiveExcerptProvenance {
  const LiveExcerptProvenance({required this.field, this.shortened = false});
  factory LiveExcerptProvenance.fromJson(Map<String, dynamic> json) {
    if (!{'rss-description', 'atom-summary'}.contains(json['field']) ||
        json['format'] != 'plain-text' ||
        json['shortened'] is! bool) {
      throw const FormatException('Invalid publisher excerpt provenance.');
    }
    return LiveExcerptProvenance(
      field: json['field'] as String,
      shortened: json['shortened'] as bool,
    );
  }
  final String field;
  final bool shortened;
  Map<String, Object?> toJson() => {
    'field': field,
    'format': 'plain-text',
    'shortened': shortened,
  };
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
    this.image,
    this.syndicatedArticle,
    this.originalUrl,
    this.outboundUrl,
    this.updatedAt,
    this.excerptProvenance,
  });
  factory LiveContentItem.fromJson(Map<String, dynamic> json) {
    final eligibility = feedMap(json['eligibility']);
    LiveArticleImage? image;
    try {
      if (json['image'] != null) {
        image = LiveArticleImage.fromJson(feedMap(json['image']));
      }
    } catch (_) {
      /* An invalid image never removes a readable headline. */
    }
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
      originalUrl: json['originalUrl'] == null
          ? null
          : feedArticleUri(json['originalUrl']),
      outboundUrl: json['outboundUrl'] == null
          ? null
          : feedArticleUri(json['outboundUrl']),
      updatedAt: json['updatedAt'] == null ? null : feedDate(json['updatedAt']),
      excerptProvenance: json['excerptProvenance'] == null
          ? null
          : LiveExcerptProvenance.fromJson(feedMap(json['excerptProvenance'])),
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
      image: image,
      syndicatedArticle: json['syndicatedArticle'] == null
          ? null
          : SyndicatedArticle.fromJson(feedMap(json['syndicatedArticle'])),
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
  final Uri? originalUrl, outboundUrl;
  Uri get openingUrl => outboundUrl ?? canonicalUrl;
  final DateTime? publishedAt, reviewedAt, updatedAt;
  final LiveExcerptProvenance? excerptProvenance;
  final DateTime fetchedAt, expiresAt;
  final Set<String> topics;
  final LiveContentRights rights;
  final LiveArticleImage? image;
  final SyndicatedArticle? syndicatedArticle;

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
    if (originalUrl != null) 'originalUrl': originalUrl.toString(),
    if (outboundUrl != null) 'outboundUrl': outboundUrl.toString(),
    if (updatedAt != null) 'updatedAt': updatedAt?.toIso8601String(),
    if (excerptProvenance != null)
      'excerptProvenance': excerptProvenance!.toJson(),
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
    'image': image?.toJson(),
    'syndicatedArticle': syndicatedArticle?.toJson(),
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
        (json['sources'] as List).length > 256) {
      throw const FormatException('Invalid snapshot.');
    }
    final sources = (json['sources'] as List)
        .map((s) => LiveSource.fromJson(feedMap(s)))
        .toList();
    if (sources.map((s) => s.id).toSet().length != sources.length) {
      throw const FormatException('Duplicate source.');
    }
    final items = <LiveContentItem>[];
    final publishers = {
      for (final source in sources)
        source.id: '${source.homepageUrl.host}\u0000${source.name}',
    };
    var rejected = 0;
    final ids = <String>{}, urls = <String>{};
    for (final raw in json['items'] as List) {
      try {
        final item = LiveContentItem.fromJson(feedMap(raw));
        final publisherUrl =
            '${publishers[item.sourceId] ?? item.sourceId}\u0000${item.canonicalUrl}';
        if (ids.contains(item.id) || urls.contains(publisherUrl)) {
          continue;
        }
        ids.add(item.id);
        urls.add(publisherUrl);
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
      revokedSourceIds: feedIds(json['revokedSourceIds'] ?? [], max: 256),
      staleSourceIds: feedIds(json['staleSourceIds'] ?? [], max: 256),
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
