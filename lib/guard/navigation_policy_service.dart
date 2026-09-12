import '../policy/consumer_protection_policy.dart';
import '../policy/policy_models.dart';
import 'domain_normalizer.dart';
import 'filter_pack_repository.dart';
import 'guard_models.dart';

/// Local consumer blocking policy. A support annotation never grants an
/// exemption. Unknown classification and unavailable mandatory data differ.
class NavigationPolicyService {
  NavigationPolicyService({
    required this.repository,
    this.protection = const ConsumerProtectionPolicy.unavailable(),
    DomainNormalizer? normalizer,
    DateTime Function()? clock,
  }) : normalizer = normalizer ?? DomainNormalizer(),
       _clock = clock ?? DateTime.now;

  final FilterPackRepository repository;
  final ConsumerProtectionPolicy protection;
  final DomainNormalizer normalizer;
  final DateTime Function() _clock;

  Future<GuardDecision> evaluate(
    GuardRequest request,
    GuardConfiguration configuration,
  ) async {
    final String host;
    try {
      host = await normalizer.normalizeUri(request.uri);
    } catch (_) {
      return const GuardDecision(
        action: GuardAction.requireAdditionalCheck,
        host: '',
        ruleId: 'invalid-domain',
      );
    }
    final baseline = protection.assessNavigation(request.uri);
    if (baseline.category != null) {
      return GuardDecision(
        action: baseline.category == MandatoryCategory.securityThreat
            ? GuardAction.blockMalware
            : GuardAction.blockCategory,
        host: host,
        category: _category(baseline.category!),
        packVersion: protection.version,
      );
    }
    // The signed domain-pack repository remains an additive data source. It
    // cannot weaken the build-pinned consumer baseline or grant an allow once.
    List<GuardRuleMatch> rules = const [];
    try {
      rules = await repository.lookupHost(host, useCache: !request.isPrivate);
    } catch (_) {
      if (!protection.isUsable) {
        return GuardDecision(
          action: GuardAction.blockPolicyUnavailable,
          host: host,
        );
      }
    }
    for (final rule in rules) {
      final action = switch (rule.kind) {
        'malware' => GuardAction.blockMalware,
        'phishing' => GuardAction.blockPhishing,
        'harmful-download' => GuardAction.blockHarmfulDownload,
        'category' when rule.category?.isLifestyle == true =>
          GuardAction.blockCategory,
        'category'
            when configuration
                .activeCategories(_clock())
                .contains(rule.category) =>
          GuardAction.blockCategory,
        _ => null,
      };
      if (action != null) {
        return GuardDecision(
          action: action,
          host: host,
          category: rule.category,
          ruleId: rule.ruleId,
          packVersion: repository.status.version,
        );
      }
    }
    if (!baseline.isAllowed) {
      return GuardDecision(
        action: baseline.code == PolicyDecisionCode.blockPolicyUnavailable
            ? GuardAction.blockPolicyUnavailable
            : GuardAction.blockUnsupported,
        host: host,
      );
    }
    final custom = {
      ...configuration.customBlock,
      if (configuration.focusActive(_clock())) ...configuration.focusHosts,
    };
    if (custom.any((rule) => hostMatches(host, protectionHost(rule)))) {
      return GuardDecision(action: GuardAction.blockCustomRule, host: host);
    }
    return GuardDecision(
      action: GuardAction.allow,
      host: host,
      packVersion: protection.version,
    );
  }

  static GuardCategory _category(MandatoryCategory category) =>
      switch (category) {
        MandatoryCategory.sexualExplicit => GuardCategory.adult,
        MandatoryCategory.gambling => GuardCategory.gambling,
        MandatoryCategory.alcoholPromotion => GuardCategory.alcohol,
        MandatoryCategory.recreationalDrugPromotion =>
          GuardCategory.recreationalDrugs,
        MandatoryCategory.tobaccoNicotine => GuardCategory.tobaccoVaping,
        MandatoryCategory.securityThreat => GuardCategory.malware,
      };
}
