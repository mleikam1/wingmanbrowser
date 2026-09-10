import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/guard/guard_runtime.dart';
import 'guard_test_support.dart';

GuardRuleMatch rule(String host, String kind, GuardCategory? category) =>
    GuardRuleMatch(
      host: host,
      kind: kind,
      category: category,
      includeSubdomains: true,
      ruleId: 'test-rule',
    );
void main() {
  late MemoryRules repository;
  late NavigationPolicyService service;
  final enabled = GuardConfiguration(
    guardEnabled: true,
    enabledCategories: {GuardCategory.adult},
  );
  setUp(() {
    repository = MemoryRules([
      rule('adult.test', 'category', GuardCategory.adult),
      rule('social.test', 'category', GuardCategory.socialMedia),
      rule('malware.test', 'malware', GuardCategory.malware),
      rule('phishing.test', 'phishing', GuardCategory.phishing),
      rule('download.test', 'harmful-download', GuardCategory.harmfulDownloads),
      rule('support.adult.test', 'support', null),
    ]);
    service = NavigationPolicyService(
      repository: repository,
      clock: () => testTime,
    );
  });
  Future<GuardDecision> evaluate(
    String url, {
    GuardConfiguration? config,
    bool private = false,
    bool download = false,
    bool allowOnce = false,
    String? filename,
  }) => service.evaluate(
    GuardRequest(
      uri: Uri.parse(url),
      tabId: 'tab',
      isPrivate: private,
      isDownload: download,
      hasAllowOnceGrant: allowOnce,
      suggestedFilename: filename,
    ),
    config ?? enabled,
  );
  test('optional category toggles do not disable mandatory threats', () async {
    expect(
      (await evaluate(
        'https://adult.test',
        config: GuardConfiguration(),
      )).action,
      GuardAction.allow,
    );
    expect(
      (await evaluate('https://adult.test')).action,
      GuardAction.blockCategory,
    );
    for (final pair in [
      ('malware.test', GuardAction.blockMalware),
      ('phishing.test', GuardAction.blockPhishing),
    ]) {
      final decision = await evaluate(
        'https://${pair.$1}',
        config: GuardConfiguration(customAllow: {pair.$1}),
        allowOnce: true,
      );
      expect(decision.action, pair.$2);
      expect(decision.overrideAllowed, false);
    }
  });
  test('label boundaries and URL words do not cause keyword blocks', () async {
    expect(
      (await evaluate('https://notadult.test/porn/alcohol?q=gambling')).action,
      GuardAction.allow,
    );
    expect(
      (await evaluate('https://sub.adult.test')).action,
      GuardAction.blockCategory,
    );
  });
  test(
    'support exemptions are narrow and cannot weaken threat rules',
    () async {
      expect(
        (await evaluate('https://support.adult.test/recovery')).action,
        GuardAction.allow,
      );
      expect(
        (await evaluate('https://adult.test/support')).action,
        GuardAction.blockCategory,
      );
      expect(
        (await evaluate(
          'https://support.adult.test',
          config: enabled.copyWith(customBlock: {'support.adult.test'}),
        )).action,
        GuardAction.blockCustomRule,
      );
    },
  );
  test(
    'custom block wins over allow and custom allow exempts category only',
    () async {
      expect(
        (await evaluate(
          'https://adult.test',
          config: enabled.copyWith(customAllow: {'adult.test'}),
        )).action,
        GuardAction.allow,
      );
      expect(
        (await evaluate(
          'https://adult.test',
          config: enabled.copyWith(
            customAllow: {'adult.test'},
            customBlock: {'adult.test'},
          ),
        )).action,
        GuardAction.blockCustomRule,
      );
    },
  );
  test(
    'custom rules use specificity with block winning an equal-host tie',
    () async {
      final config = enabled.copyWith(
        customBlock: {'example.test', 'deep.allowed.example.test'},
        customAllow: {'allowed.example.test'},
      );
      expect(
        (await evaluate('https://allowed.example.test', config: config)).action,
        GuardAction.allow,
      );
      expect(
        (await evaluate(
          'https://child.allowed.example.test',
          config: config,
        )).action,
        GuardAction.allow,
      );
      expect(
        (await evaluate('https://sibling.example.test', config: config)).action,
        GuardAction.blockCustomRule,
      );
      expect(
        (await evaluate(
          'https://deep.allowed.example.test',
          config: config,
        )).action,
        GuardAction.blockCustomRule,
      );
      expect(
        (await evaluate(
          'https://allowed.example.test',
          config: config.copyWith(
            customBlock: {'example.test', 'allowed.example.test'},
          ),
        )).action,
        GuardAction.blockCustomRule,
      );
      expect(
        (await evaluate(
          'https://malware.test',
          config: config.copyWith(customAllow: {'malware.test'}),
        )).action,
        GuardAction.blockMalware,
      );
    },
  );

  test(
    'PIN lock gates overrides and cannot be persisted as an unlocked flag',
    () async {
      expect(
        (await evaluate('https://adult.test', allowOnce: true)).action,
        GuardAction.allow,
      );
      final locked = enabled.copyWith(overridesAllowed: false);
      final decision = await evaluate(
        'https://adult.test',
        allowOnce: true,
        config: locked,
      );
      expect(decision.action, GuardAction.blockCategory);
      expect(decision.overrideAllowed, false);
      expect(locked.toJson().containsKey('overridesAllowed'), false);
    },
  );
  test(
    'focus expiry and categories are independent of lifestyle selection',
    () async {
      final focus = enabled.copyWith(
        focusCategories: {GuardCategory.socialMedia},
        focusHosts: {'work-distraction.test'},
        focusExpiresAt: testTime.add(const Duration(minutes: 25)),
      );
      expect(
        (await evaluate('https://social.test', config: focus)).action,
        GuardAction.blockCategory,
      );
      expect(
        (await evaluate('https://adult.test', config: focus)).action,
        GuardAction.blockCategory,
      );
      expect(
        (await evaluate('https://work-distraction.test', config: focus)).ruleId,
        'focus-site',
      );
      final expired = focus.copyWith(focusExpiresAt: testTime);
      expect(
        (await evaluate('https://social.test', config: expired)).action,
        GuardAction.allow,
      );
      expect(
        (await evaluate('https://adult.test', config: expired)).action,
        GuardAction.blockCategory,
      );
    },
  );
  test(
    'private decisions are equal and request no classification cache',
    () async {
      final normal = await evaluate('https://adult.test');
      expect(repository.lastUseCache, true);
      final private = await evaluate('https://adult.test', private: true);
      expect(repository.lastUseCache, false);
      expect(private.toJson(), normal.toJson());
    },
  );
  test(
    'unavailable list allows ordinary browsing but keeps custom protection',
    () async {
      repository.fail = true;
      expect(
        (await evaluate('https://example.test')).action,
        GuardAction.errorAllow,
      );
      expect(
        (await evaluate(
          'https://custom.test',
          config: enabled.copyWith(customBlock: {'custom.test'}),
        )).action,
        GuardAction.blockCustomRule,
      );
    },
  );
  test('download reputation and executable caution are distinct', () async {
    expect(
      (await evaluate('https://download.test/readme')).action,
      GuardAction.allow,
    );
    final malicious = await evaluate(
      'https://download.test/readme',
      download: true,
      allowOnce: true,
    );
    expect(malicious.action, GuardAction.blockHarmfulDownload);
    expect(malicious.overrideAllowed, false);
    final caution = await evaluate(
      'https://example.test/download',
      download: true,
      filename: 'Invoice.EXE',
    );
    expect(caution.action, GuardAction.requireAdditionalCheck);
    expect(caution.isSecurityBlock, false);
    expect(caution.overrideAllowed, true);
    expect(
      (await evaluate(
        'https://example.test/download',
        download: true,
        filename: 'notes.txt',
      )).action,
      GuardAction.allow,
    );
    expect(
      (await evaluate(
        'https://example.test/file.apk',
        download: true,
        allowOnce: true,
      )).action,
      GuardAction.allow,
    );
  });
  test(
    'invalid and unsupported scheme decisions never expose secret URL',
    () async {
      final decision = await evaluate(
        'https://user:password@example.test?q=secret',
      );
      expect(decision.action, GuardAction.requireAdditionalCheck);
      expect(decision.host, isEmpty);
      expect(decision.toJson().toString(), isNot(contains('password')));
      expect(decision.toJson().toString(), isNot(contains('secret')));
    },
  );
}
