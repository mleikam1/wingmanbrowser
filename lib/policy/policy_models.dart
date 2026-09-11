import 'dart:collection';

/// This baseline is application code, never a user, role, PIN or remote setting.
abstract final class MandatorySafetyPolicy {
  static const version = 1;
  static const minimumCatalogSequence = 1;
  // Native availability and current reviewed scope are checked at runtime.
  static const supportsReviewedLiveScopes = true;
  static const categories = MandatoryCategory.values;
}

enum MandatoryCategory {
  sexualExplicit('sexual-explicit', 'Sexually explicit entertainment'),
  gambling('gambling', 'Gambling and wagering'),
  alcoholPromotion('alcohol-promotion', 'Alcohol commerce and promotion'),
  recreationalDrugPromotion(
    'recreational-drug-promotion',
    'Recreational-drug commerce and promotion',
  ),
  tobaccoNicotine('tobacco-nicotine', 'Tobacco, nicotine and vaping promotion'),
  securityThreat('security-threat', 'Phishing, malware and confirmed scams');

  const MandatoryCategory(this.id, this.label);
  final String id, label;
}

enum ContentContext { general, student }

enum PolicyOperation {
  renderBundled,
  navigate,
  resource,
  authentication,
  download,
  externalDispatch,
  liveReader,
}

enum PolicyDecisionCode {
  allowApproved,
  blockMandatoryCategory,
  blockAdditionalRestriction,
  blockUnreviewed,
  blockSecurityThreat,
  blockUnsupportedCapability,
  blockPolicyUnavailable,
}

class PolicyRequest {
  const PolicyRequest({
    required this.operation,
    this.resourceId,
    this.uri,
    this.context = ContentContext.general,
    this.isPrivate = false,
  });
  const PolicyRequest.bundled(
    String id, {
    this.context = ContentContext.general,
    this.isPrivate = false,
  }) : resourceId = id,
       uri = null,
       operation = PolicyOperation.renderBundled;
  const PolicyRequest.navigation(
    Uri target, {
    this.context = ContentContext.general,
    this.isPrivate = false,
  }) : resourceId = null,
       uri = target,
       operation = PolicyOperation.navigate;
  final PolicyOperation operation;
  final String? resourceId;
  final Uri? uri;
  final ContentContext context;
  final bool isPrivate;
}

class PolicyDecision {
  const PolicyDecision(
    this.code, {
    this.resourceId,
    this.safeTitle,
    this.category,
  });
  final PolicyDecisionCode code;
  final String? resourceId, safeTitle;
  final MandatoryCategory? category;
  bool get isAllowed => code == PolicyDecisionCode.allowApproved;
}

bool validResourceId(String id) =>
    RegExp(r'^[a-z0-9][a-z0-9-]{0,79}$').hasMatch(id);
Set<String> _ids(Iterable<String> values, int maximum) =>
    UnmodifiableSetView(values.where(validResourceId).take(maximum).toSet());

/// Additional restrictions can only subtract from compiled/catalog eligibility.
class AdditionalRestrictions {
  AdditionalRestrictions({
    Iterable<String> blockedResourceIds = const [],
    Iterable<String> blockedCollections = const [],
  }) : blockedResourceIds = _ids(blockedResourceIds, 500),
       blockedCollections = _ids(blockedCollections, 50);
  final Set<String> blockedResourceIds, blockedCollections;
  Map<String, Object?> toJson() => {
    'blockedResourceIds': blockedResourceIds.toList()..sort(),
    'blockedCollections': blockedCollections.toList()..sort(),
  };
  factory AdditionalRestrictions.fromJson(Map<String, Object?> json) =>
      AdditionalRestrictions(
        blockedResourceIds:
            (json['blockedResourceIds'] is List
                    ? json['blockedResourceIds'] as List
                    : const [])
                .whereType<String>(),
        blockedCollections:
            (json['blockedCollections'] is List
                    ? json['blockedCollections'] as List
                    : const [])
                .whereType<String>(),
      );
}

class ProtectedPreferences {
  ProtectedPreferences({
    Iterable<String> bookmarkedIds = const [],
    Iterable<String> readingIds = const [],
    Iterable<String> readIds = const [],
    AdditionalRestrictions? additional,
  }) : bookmarkedIds = _ids(bookmarkedIds, 5000),
       readingIds = _ids(readingIds, 500),
       readIds = _ids(readIds, 500),
       additional = additional ?? AdditionalRestrictions();
  final Set<String> bookmarkedIds, readingIds, readIds;
  final AdditionalRestrictions additional;
  Set<String> get blockedResourceIds => additional.blockedResourceIds;
  Set<String> get blockedCollections => additional.blockedCollections;
  ProtectedPreferences copyWith({
    Iterable<String>? bookmarkedIds,
    Iterable<String>? readingIds,
    Iterable<String>? readIds,
    AdditionalRestrictions? additional,
  }) => ProtectedPreferences(
    bookmarkedIds: bookmarkedIds ?? this.bookmarkedIds,
    readingIds: readingIds ?? this.readingIds,
    readIds: readIds ?? this.readIds,
    additional: additional ?? this.additional,
  );
  Map<String, Object?> toJson() => {
    'schema': 1,
    'bookmarkedIds': bookmarkedIds.toList()..sort(),
    'readingIds': readingIds.toList()..sort(),
    'readIds': readIds.where(readingIds.contains).toList()..sort(),
    'additional': additional.toJson(),
  };
  factory ProtectedPreferences.fromJson(Map<String, Object?> json) {
    Iterable<String> values(String key) =>
        (json[key] is List ? json[key] as List : const []).whereType<String>();
    return ProtectedPreferences(
      bookmarkedIds: values('bookmarkedIds'),
      readingIds: values('readingIds'),
      readIds: values('readIds'),
      additional: AdditionalRestrictions.fromJson(
        json['additional'] is Map
            ? Map<String, Object?>.from(json['additional'] as Map)
            : const {},
      ),
    );
  }
}

class QuarantinedContentCounts {
  const QuarantinedContentCounts({
    this.archivedTabs = 0,
    this.bookmarks = 0,
    this.history = 0,
    this.readingList = 0,
  });
  final int archivedTabs, bookmarks, history, readingList;
  int get total => archivedTabs + bookmarks + history + readingList;
}

class ApprovedResource {
  ApprovedResource({
    required this.id,
    required this.title,
    required this.summary,
    required this.collection,
    required this.body,
    required this.assetPath,
    required this.sha256,
    required this.reviewedAt,
    required this.expiresAt,
    required this.policyVersion,
    required Iterable<String> sourceUrls,
    required Iterable<ContentContext> contexts,
    required this.reviewer,
    required this.license,
  }) : sourceUrls = List.unmodifiable(sourceUrls),
       contexts = Set.unmodifiable(contexts);
  final String id,
      title,
      summary,
      collection,
      body,
      assetPath,
      sha256,
      reviewer,
      license;
  final DateTime reviewedAt, expiresAt;
  final int policyVersion;
  final List<String> sourceUrls;
  final Set<ContentContext> contexts;
}

class PolicyStatus {
  const PolicyStatus({
    this.usable = false,
    this.version,
    this.sequence,
    this.reviewedAt,
    this.expiresAt,
    this.resourceCount = 0,
    this.errorCode,
  });
  final bool usable;
  final String? version, errorCode;
  final int? sequence;
  final int resourceCount;
  final DateTime? reviewedAt, expiresAt;
}

class PolicyValidationException implements Exception {
  const PolicyValidationException(this.code);
  final String code;
  @override
  String toString() => 'Reviewed content is unavailable ($code).';
}
