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
  }) : normalizer = normalizer ?? DomainNormalizer(),
       _clock = clock ?? DateTime.now;

  final FilterPackRepository repository;
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
    List<GuardRuleMatch> rules;
    var lookupFailed = false;
    try {
      rules = await repository.lookupHost(host, useCache: !request.isPrivate);
    } catch (_) {
      rules = const [];
      lookupFailed = true;
    }

    GuardDecision decision(
      GuardAction action, {
      GuardCategory? category,
      String? ruleId,
      bool canOverride = false,
    }) => GuardDecision(
      action: action,
      host: host,
      category: category,
      ruleId: ruleId,
      packVersion: repository.status.version,
      overrideAllowed: canOverride && configuration.overridesAllowed,
    );

    for (final kind in ['malware', 'phishing', 'harmful-download']) {
      if (kind == 'harmful-download' && !request.isDownload) continue;
      final match = rules.where((rule) => rule.kind == kind).firstOrNull;
      if (match == null) continue;
      return decision(
        switch (kind) {
          'malware' => GuardAction.blockMalware,
          'phishing' => GuardAction.blockPhishing,
          _ => GuardAction.blockHarmfulDownload,
        },
        category: match.category,
        ruleId: match.ruleId,
      );
    }
    final allowOnce =
        configuration.overridesAllowed && request.hasAllowOnceGrant;
    bool matches(Set<String> rules) =>
        rules.any((rule) => DomainNormalizer.matches(host, rule));
    String? mostSpecific(Set<String> rules) => rules
        .where((rule) => DomainNormalizer.matches(host, rule))
        .fold<String?>(
          null,
          (best, rule) =>
              best == null || rule.length > best.length ? rule : best,
        );
    final customBlock = mostSpecific(configuration.customBlock);
    final customAllow = mostSpecific(configuration.customAllow);
    if (customBlock != null &&
        (customAllow == null || customBlock.length >= customAllow.length) &&
        !allowOnce) {
      return decision(
        GuardAction.blockCustomRule,
        ruleId: 'custom-block',
        canOverride: true,
      );
    }
    if (request.isDownload &&
        configuration.dangerousDownloadProtection &&
        !allowOnce &&
        _executable(request)) {
      // File type is a caution, not a claim the file contains malware.
      return decision(
        GuardAction.requireAdditionalCheck,
        category: GuardCategory.harmfulDownloads,
        ruleId: 'executable-download-type',
        canOverride: true,
      );
    }
    if (allowOnce || matches(configuration.customAllow)) {
      return decision(
        lookupFailed ? GuardAction.errorAllow : GuardAction.allow,
      );
    }
    if (configuration.focusActive(_clock()) &&
        matches(configuration.focusHosts)) {
      return decision(
        GuardAction.blockCustomRule,
        ruleId: 'focus-site',
        canOverride: true,
      );
    }
    // A specifically curated support/education destination only exempts
    // category rules. It cannot override threats, custom blocks or file checks.
    if (!rules.any((rule) => rule.kind == 'support')) {
      final active = configuration.activeCategories(_clock());
      final matches = rules.where(
        (rule) => rule.kind == 'category' && active.contains(rule.category),
      );
      if (matches.isNotEmpty) {
        final match = matches.first;
        return decision(
          GuardAction.blockCategory,
          category: match.category,
          ruleId: match.ruleId,
          canOverride: true,
        );
      }
    }
    return decision(lookupFailed ? GuardAction.errorAllow : GuardAction.allow);
  }

  bool _executable(GuardRequest request) {
    final mime = request.mimeType?.split(';').first.trim().toLowerCase();
    if (const {
      'application/vnd.android.package-archive',
      'application/x-msdownload',
      'application/x-msi',
      'application/x-executable',
      'application/x-sh',
    }.contains(mime)) {
      return true;
    }
    final filename =
        (request.suggestedFilename ?? request.uri.pathSegments.lastOrNull ?? '')
            .toLowerCase()
            .split(RegExp(r'[/\\]'))
            .last;
    final extension = filename.contains('.') ? filename.split('.').last : '';
    return const {
      'exe',
      'msi',
      'scr',
      'com',
      'bat',
      'cmd',
      'ps1',
      'vbs',
      'js',
      'jar',
      'apk',
      'aab',
      'dmg',
      'pkg',
      'app',
      'deb',
      'rpm',
    }.contains(extension);
  }
}
