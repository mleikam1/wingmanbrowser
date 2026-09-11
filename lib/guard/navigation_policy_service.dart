import 'domain_normalizer.dart';
import 'filter_pack_repository.dart';
import 'guard_models.dart';

/// All routine navigation decisions use local rules. Threat, content and
/// support classifications are separate rule kinds, never URL keyword checks.
class NavigationPolicyService {
  NavigationPolicyService({
    required this.repository,
    DomainNormalizer? normalizer,
    DateTime Function()? clock,
  }) : normalizer = normalizer ?? DomainNormalizer();

  final FilterPackRepository repository;
  final DomainNormalizer normalizer;

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
    final List<GuardRuleMatch> rules;
    try {
      rules = await repository.lookupHost(host, useCache: !request.isPrivate);
    } catch (_) {
      return GuardDecision(
        action: GuardAction.blockPolicyUnavailable,
        host: host,
      );
    }
    for (final rule in rules) {
      final action = switch (rule.kind) {
        'malware' => GuardAction.blockMalware,
        'phishing' => GuardAction.blockPhishing,
        'harmful-download' => GuardAction.blockHarmfulDownload,
        'category' when rule.category?.isLifestyle == true =>
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
    // The retired domain pack is never positive eligibility. Support hosts,
    // old allowlists, PINs and optional settings cannot authorize live content.
    return GuardDecision(action: GuardAction.blockUnsupported, host: host);
  }
}
