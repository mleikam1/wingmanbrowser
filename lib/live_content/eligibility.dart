import 'models.dart';

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
    if (_prohibitedPromotion(item.title) ||
        _prohibitedPromotion(item.excerpt ?? '')) {
      return false;
    }
    try {
      return canOpenDestination(item.canonicalUrl);
    } catch (_) {
      return false;
    }
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
