import 'models.dart';
import 'syndicated_article.dart';

/// Publisher rights and a build-pinned editorial scope are the admission gate.
/// Text rules only subtract obvious promotion; they do not approve a source or
/// claim to classify every changing headline, image, or linked article.
class LiveContentEligibility {
  LiveContentEligibility({
    required this.registry,
    required this.canOpenDestination,
  });
  final LiveSourceRegistry registry;
  final bool Function(Uri) canOpenDestination;

  /// Image permission is independent of headline permission. This checks pinned
  /// origin/license/rendition and association consistency; provenance comes from
  /// the direct RSS provider, not from a self-asserted JSON image object.
  LiveArticleImage? imageFor(LiveContentItem item) {
    final approved = registry.sources[item.sourceId];
    final policy = approved?.imagePolicy, image = item.image;
    if (approved == null ||
        !approved.enabled ||
        policy == null ||
        image == null ||
        !approved.source.rights.images ||
        !item.rights.images ||
        image.sourceId != item.sourceId ||
        image.articleUrl != item.canonicalUrl ||
        image.basis != policy.kind ||
        image.credit != policy.credit ||
        image.licenseUrl != policy.licenseUrl ||
        image.licenseLabel != policy.licenseLabel ||
        image.width > policy.maximumWidth ||
        image.height > policy.maximumHeight ||
        (policy.kind == 'syndicated-feed-thumbnail' &&
            (image.width < 1 || image.height < 1)) ||
        (policy.kind == 'syndicated-article-photo' &&
            !acceptsSyndicatedArticle(item)) ||
        !policy.acceptsUri(image.url)) {
      return null;
    }
    try {
      return canOpenDestination(image.url) ? image : null;
    } catch (_) {
      return null;
    }
  }

  bool acceptsSyndicatedArticle(LiveContentItem item) {
    final source = registry.sources[item.sourceId],
        body = item.syndicatedArticle;
    if (source?.imagePolicy?.kind != 'syndicated-article-photo' ||
        body == null ||
        body.articleUrl != item.canonicalUrl ||
        body.publisher != source!.source.name ||
        body.licenseUrl != source.source.rights.licenseUrl ||
        !acceptsSyndicatedPromotion(item.title) ||
        !acceptsSyndicatedPromotion(body.plainText)) {
      return false;
    }
    try {
      return body.paragraphs
          .expand((p) => p.runs)
          .where((r) => r.link != null)
          .every((r) => canOpenDestination(r.link!));
    } catch (_) {
      return false;
    }
  }

  bool accepts(
    LiveContentItem item, {
    required DateTime now,
    bool saved = false,
  }) {
    final approved = registry.sources[item.sourceId];
    if (approved == null ||
        !approved.enabled ||
        !approved.source.rights.titles ||
        !item.rights.titles ||
        !approved.allowedArticleHosts.contains(item.canonicalUrl.host) ||
        !_approvedPath(item.canonicalUrl, approved.articlePathPrefixes) ||
        (approved.articleUrlFormat == 'dated-story' &&
            !RegExp(
              r'^/[0-9]{4}/[0-9]{2}/[0-9]{2}/[^/]+/?$',
            ).hasMatch(item.canonicalUrl.path)) ||
        (approved.requiresAttribution &&
            (item.attribution?.trim().isEmpty ?? true)) ||
        item.language != approved.source.language ||
        item.topics.isEmpty ||
        !item.topics.every(approved.source.topics.contains) ||
        item.eligibilityState != 'eligible' ||
        item.eligibilityBasis != 'curated-source-scope' ||
        item.eligibilityScope != approved.eligibilityScope ||
        item.fetchedAt.isAfter(now.add(const Duration(hours: 24))) ||
        (item.publishedAt?.isAfter(now.add(const Duration(hours: 24))) ??
            false) ||
        !item.expiresAt.isAfter(item.fetchedAt) ||
        (!saved && !now.isBefore(item.expiresAt)) ||
        item.expiresAt.difference(item.fetchedAt) > const Duration(days: 30)) {
      return false;
    }
    if (item.excerpt != null &&
        item.excerpt!.isNotEmpty &&
        (!approved.source.rights.excerpts || !item.rights.excerpts)) {
      return false;
    }
    if (item.rights.licenseUrl != null &&
        item.rights.licenseUrl != approved.source.rights.licenseUrl) {
      return false;
    }
    if ((item.syndicatedArticle != null
            ? !acceptsSyndicatedArticle(item)
            : !acceptsFeedText(item.title, item.excerpt ?? '')) ||
        !matchesTopicScope(
          item.title,
          item.excerpt ?? '',
          approved.requiredTopicTerms,
        )) {
      return false;
    }
    try {
      return canOpenDestination(item.canonicalUrl);
    } catch (_) {
      return false;
    }
  }

  /// A narrowly scoped search feed must prove its topic from its plain metadata.
  /// This categorizes already reviewed sources; it does not authorize content.
  bool matchesTopicScope(String title, String excerpt, Set<String> terms) {
    if (terms.isEmpty) return true;
    final text = '$title $excerpt'.toLowerCase();
    return terms.any(
      (term) => RegExp(
        r'\b' + RegExp.escape(term.toLowerCase()) + r'\b',
      ).hasMatch(text),
    );
  }

  /// Applied to full bounded feed metadata before any display truncation, and
  /// again to each normalized snapshot item. Publisher scope and destination
  /// policy remain independent requirements.
  bool acceptsFeedText(String title, String excerpt) {
    final text = '$title $excerpt'.toLowerCase();
    if (text.contains('©') || RegExp(r'\bcopyright\s+\d{4}\b').hasMatch(text)) {
      return false;
    }
    if (RegExp(
      r'\b(?:sponsored(?:\s+content)?|paid\s+(?:post|partnership|advertisement)|'
      r'affiliate\s+links?|buy\s+now|shop\s+now|promo\s+code|'
      r'free\s+spins|deposit\s+bonus|place\s+(?:a\s+)?bets?|'
      r'adult\s+entertainment|sex\s+tapes?|pornographic|'
      r'cannabis\s+dispensary|all\s+rights\s+reserved)\b',
    ).hasMatch(text)) {
      return false;
    }
    if (_prohibitedPromotion(title) || _prohibitedPromotion(excerpt)) {
      return false;
    }
    final restricted = RegExp(
      r'\b(?:casino|sportsbook|sports betting|gambling|vaping|pornography|'
      r'cannabis|marijuana|tobacco|cigarettes?|vodka|whiskey|whisky|'
      r'beer|wine|liquor|nicotine)\b',
    ).hasMatch(text);
    final reporting = RegExp(
      r'\b(?:research|study|studies|scientists?|health|pollution|wildlife|'
      r'survey|geology|environment|hazard|reports?|evidence|regulation|'
      r'regulator|ban|warning|recovery|treatment|education|prevention|'
      r'risks?|addiction|policy|investigation)\b',
    ).hasMatch(text);
    return !restricted || reporting;
  }

  bool _approvedPath(Uri uri, Set<String> prefixes) {
    try {
      final path = Uri.decodeComponent(uri.path.isEmpty ? '/' : uri.path);
      if (path.contains('\\') ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
          path.split('/').any((part) => part == '.' || part == '..')) {
        return false;
      }
      return prefixes.any(
        (prefix) =>
            prefix == '/' ||
            path == prefix ||
            path.startsWith(prefix.endsWith('/') ? prefix : '$prefix/'),
      );
    } on FormatException {
      return false;
    }
  }

  bool _prohibitedPromotion(String text) {
    final value = text.toLowerCase();
    const products =
        r'(?:casino|gambling|sports betting|sportsbook|whiskey|vodka|liquor|alcohol|cannabis|marijuana|vapes?|tobacco|nicotine|cigarettes?|porn(?:ography)?)';
    if (RegExp(
          r'^(?:buy|shop|order|bet|wager|claim|play for cash)\b.{0,100}' +
              products,
        ).hasMatch(value) ||
        RegExp(
          products +
              r'.{0,60}\b(?:coupon|promo code|free spins|deposit bonus|buy now|shop now|bet now|order now)\b',
        ).hasMatch(value)) {
      return true;
    }
    final product = RegExp(r'\b' + products + r'\b').hasMatch(value);
    final promotion = RegExp(
      r'\b(?:sale|discount|deal|bonus|sign up|subscribe|exclusive offer|sponsored)\b',
    ).hasMatch(value);
    final reporting = RegExp(
      r'\b(?:research|study|studies|reports?|reporting|regulation|regulator|ban|warning|health|recovery|treatment|education|prevention|risks?|addiction|policy|investigation)\b',
    ).hasMatch(value);
    return product && promotion && !reporting;
  }
}
