import 'dart:collection';

enum GuardCategory {
  adult('adult', 'Adult content'),
  alcohol('alcohol', 'Alcohol'),
  recreationalDrugs('recreational-drugs', 'Recreational drugs'),
  gambling('gambling', 'Gambling'),
  tobaccoVaping('tobacco-vaping', 'Tobacco / vaping'),
  malware('malware', 'Malicious websites'),
  phishing('phishing', 'Phishing / scams'),
  harmfulDownloads('harmful-downloads', 'Potentially harmful downloads'),
  socialMedia('social-media', 'Social media'),
  shopping('shopping', 'Shopping'),
  gaming('gaming', 'Gaming'),
  news('news', 'News');

  const GuardCategory(this.id, this.label);
  final String id;
  final String label;
  bool get isSecurity =>
      this == malware || this == phishing || this == harmfulDownloads;
  bool get isFocus => index >= socialMedia.index;
  bool get isLifestyle => !isSecurity && !isFocus;

  static GuardCategory? fromId(String id) =>
      values.where((value) => value.id == id).firstOrNull;
}

enum GuardAction {
  allow,
  blockCategory,
  blockMalware,
  blockPhishing,
  blockCustomRule,
  blockHarmfulDownload,
  requireAdditionalCheck,
  errorAllow,
}

/// A decision contains a hostname, never the full URL or page contents.
class GuardDecision {
  const GuardDecision({
    required this.action,
    required this.host,
    this.category,
    this.ruleId,
    this.packVersion,
    this.overrideAllowed = false,
  });

  final GuardAction action;
  final String host;
  final GuardCategory? category;
  final String? ruleId;
  final String? packVersion;
  final bool overrideAllowed;
  bool get isBlocked =>
      action != GuardAction.allow && action != GuardAction.errorAllow;
  bool get isSecurityBlock =>
      action == GuardAction.blockMalware ||
      action == GuardAction.blockPhishing ||
      action == GuardAction.blockHarmfulDownload;

  Map<String, Object?> toJson() => {
    'action': action.name,
    'host': host,
    'category': category?.id,
    'ruleId': ruleId,
    'packVersion': packVersion,
    'overrideAllowed': overrideAllowed,
  };

  factory GuardDecision.fromJson(Map<String, Object?> json) => GuardDecision(
    action: GuardAction.values.firstWhere(
      (action) => action.name == json['action'],
      orElse: () => GuardAction.requireAdditionalCheck,
    ),
    host: json['host'] as String? ?? '',
    category: GuardCategory.fromId(json['category'] as String? ?? ''),
    ruleId: json['ruleId'] as String?,
    packVersion: json['packVersion'] as String?,
    overrideAllowed: json['overrideAllowed'] == true,
  );
}

class GuardRequest {
  const GuardRequest({
    required this.uri,
    required this.tabId,
    this.navigationId,
    this.isPrivate = false,
    this.isDownload = false,
    this.suggestedFilename,
    this.mimeType,
    this.hasAllowOnceGrant = false,
  });

  final Uri uri;
  final String tabId;
  final String? navigationId;
  final bool isPrivate;
  final bool isDownload;
  final String? suggestedFilename;
  final String? mimeType;
  // The controller validates scope (tab + canonical host + download status).
  // This never bypasses a security rule or invalid URL handling.
  final bool hasAllowOnceGrant;
}

/// Local preferences. Focus adds temporary rules without changing lifestyle
/// selections. Mandatory threat/TLS protection has no disable switch here.
class GuardConfiguration {
  GuardConfiguration({
    this.guardEnabled = false,
    Set<GuardCategory> enabledCategories = const {},
    Set<String> customAllow = const {},
    Set<String> customBlock = const {},
    Set<GuardCategory> focusCategories = const {},
    Set<String> focusHosts = const {},
    this.focusExpiresAt,
    this.overridesAllowed = true,
    this.trackingProtection = true,
    this.dangerousDownloadProtection = true,
  }) : enabledCategories = UnmodifiableSetView(Set.of(enabledCategories)),
       customAllow = UnmodifiableSetView(Set.of(customAllow)),
       customBlock = UnmodifiableSetView(Set.of(customBlock)),
       focusCategories = UnmodifiableSetView(Set.of(focusCategories)),
       focusHosts = UnmodifiableSetView(Set.of(focusHosts));

  final bool guardEnabled;
  final Set<GuardCategory> enabledCategories;
  final Set<String> customAllow;
  final Set<String> customBlock;
  final Set<GuardCategory> focusCategories;
  final Set<String> focusHosts;
  final DateTime? focusExpiresAt;
  final bool overridesAllowed;
  final bool trackingProtection;
  final bool dangerousDownloadProtection;

  bool focusActive(DateTime now) => focusExpiresAt?.isAfter(now) ?? false;
  Set<GuardCategory> activeCategories(DateTime now) => {
    if (guardEnabled) ...enabledCategories.where((c) => !c.isSecurity),
    if (focusActive(now)) ...focusCategories.where((c) => c.isFocus),
  };
  bool get adultFilteringEnabled =>
      guardEnabled && enabledCategories.contains(GuardCategory.adult);

  GuardConfiguration copyWith({
    bool? guardEnabled,
    Set<GuardCategory>? enabledCategories,
    Set<String>? customAllow,
    Set<String>? customBlock,
    Set<GuardCategory>? focusCategories,
    Set<String>? focusHosts,
    DateTime? focusExpiresAt,
    bool clearFocus = false,
    bool? overridesAllowed,
    bool? trackingProtection,
    bool? dangerousDownloadProtection,
  }) => GuardConfiguration(
    guardEnabled: guardEnabled ?? this.guardEnabled,
    enabledCategories: enabledCategories ?? this.enabledCategories,
    customAllow: customAllow ?? this.customAllow,
    customBlock: customBlock ?? this.customBlock,
    focusCategories: clearFocus ? {} : focusCategories ?? this.focusCategories,
    focusHosts: clearFocus ? {} : focusHosts ?? this.focusHosts,
    focusExpiresAt: clearFocus ? null : focusExpiresAt ?? this.focusExpiresAt,
    overridesAllowed: overridesAllowed ?? this.overridesAllowed,
    trackingProtection: trackingProtection ?? this.trackingProtection,
    dangerousDownloadProtection:
        dangerousDownloadProtection ?? this.dangerousDownloadProtection,
  );

  Map<String, Object?> toJson() => {
    'guardEnabled': guardEnabled,
    'enabledCategories': enabledCategories.map((c) => c.id).toList()..sort(),
    'customAllow': customAllow.toList()..sort(),
    'customBlock': customBlock.toList()..sort(),
    'focusCategories': focusCategories.map((c) => c.id).toList()..sort(),
    'focusHosts': focusHosts.toList()..sort(),
    'focusExpiresAt': focusExpiresAt?.toUtc().toIso8601String(),
    // Lock state is derived from secure PIN/session state by the controller.
    'trackingProtection': trackingProtection,
    'dangerousDownloadProtection': dangerousDownloadProtection,
  };

  factory GuardConfiguration.fromJson(Map<String, Object?> json) {
    Set<String> strings(String key) =>
        (json[key] is List ? json[key] as List : const [])
            .whereType<String>()
            .take(200)
            .toSet();
    Set<GuardCategory> categories(String key) => strings(
      key,
    ).map(GuardCategory.fromId).whereType<GuardCategory>().toSet();
    return GuardConfiguration(
      guardEnabled: json['guardEnabled'] == true,
      enabledCategories: categories('enabledCategories'),
      customAllow: strings('customAllow'),
      customBlock: strings('customBlock'),
      focusCategories: categories('focusCategories'),
      focusHosts: strings('focusHosts'),
      focusExpiresAt: DateTime.tryParse(
        json['focusExpiresAt'] is String
            ? json['focusExpiresAt'] as String
            : '',
      ),
      trackingProtection: json['trackingProtection'] != false,
      dangerousDownloadProtection: json['dangerousDownloadProtection'] != false,
    );
  }
}

class GuardRuleMatch {
  const GuardRuleMatch({
    required this.host,
    required this.kind,
    required this.category,
    required this.includeSubdomains,
    required this.ruleId,
  });
  final String host;
  final String kind;
  final GuardCategory? category;
  final bool includeSubdomains;
  final String ruleId;
}

class FilterPackStatus {
  const FilterPackStatus({
    this.version,
    this.generation,
    this.createdAt,
    this.ruleCount = 0,
    this.hasPrevious = false,
    this.integrityVerified = false,
    this.errorCode,
  });
  final String? version;
  final int? generation;
  final DateTime? createdAt;
  final int ruleCount;
  final bool hasPrevious;
  final bool integrityVerified;
  final String? errorCode;
  bool isStale(DateTime now) =>
      createdAt == null || now.difference(createdAt!).inDays > 30;
}
