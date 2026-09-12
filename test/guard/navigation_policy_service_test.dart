import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/guard/guard_runtime.dart';
import 'guard_test_support.dart';
import '../support/protected_test_support.dart';
import 'package:wingman_browser/policy/consumer_protection_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final categories = GuardCategory.values.where((c) => c.isLifestyle).toList();
  test(
    'legacy mandatory category decisions cannot be disabled by any configuration or grant',
    () async {
      for (final category in categories) {
        final host = '${category.id}.test';
        final repository = MemoryRules([
          GuardRuleMatch(
            host: host,
            kind: 'category',
            category: category,
            includeSubdomains: true,
            ruleId: 'mandatory',
          ),
        ]);
        final policy = NavigationPolicyService(repository: repository);
        for (final private in [false, true]) {
          final decision = await policy.evaluate(
            GuardRequest(
              uri: Uri.parse('https://$host'),
              tabId: 't',
              isPrivate: private,
              hasAllowOnceGrant: true,
            ),
            GuardConfiguration(
              guardEnabled: false,
              enabledCategories: {},
              customAllow: {host},
              overridesAllowed: true,
              dangerousDownloadProtection: false,
            ),
          );
          expect(decision.isBlocked, true);
          expect(decision.overrideAllowed, false);
          expect(decision.action, GuardAction.blockCategory);
        }
      }
    },
  );
  test(
    'missing mandatory baseline differs from unknown and support annotations',
    () async {
      final rules = MemoryRules([
        const GuardRuleMatch(
          host: 'support.test',
          kind: 'support',
          category: null,
          includeSubdomains: true,
          ruleId: 'old-support',
        ),
      ]);
      final policy = NavigationPolicyService(repository: rules);
      for (final host in ['unknown.test', 'support.test']) {
        final decision = await policy.evaluate(
          GuardRequest(uri: Uri.parse('https://$host'), tabId: 't'),
          GuardConfiguration(customAllow: {host}),
        );
        expect(decision.action, GuardAction.blockPolicyUnavailable);
        expect(decision.overrideAllowed, false);
      }
      rules.fail = true;
      expect(
        (await policy.evaluate(
          GuardRequest(uri: Uri.parse('https://unknown.test'), tabId: 't'),
          GuardConfiguration(),
        )).action,
        GuardAction.blockPolicyUnavailable,
      );
    },
  );
  test(
    'consumer baseline permits unknown domains and retains additive restrictions',
    () async {
      final baseline = await ConsumerProtectionPolicy.load(
        bundle: LocalCatalogBundle(),
      );
      final policy = NavigationPolicyService(
        repository: MemoryRules([]),
        protection: baseline,
      );
      final request = GuardRequest(
        uri: Uri.parse('https://unknown.test/interactive'),
        tabId: 't',
      );
      expect(
        (await policy.evaluate(request, GuardConfiguration())).action,
        GuardAction.allow,
      );
      expect(
        (await policy.evaluate(
          request,
          GuardConfiguration(customBlock: {'unknown.test'}),
        )).action,
        GuardAction.blockCustomRule,
      );
      expect(
        (await policy.evaluate(
          GuardRequest(
            uri: Uri.parse('https://gambling.protection.test/'),
            tabId: 't',
          ),
          GuardConfiguration(customAllow: {'gambling.protection.test'}),
        )).action,
        GuardAction.blockCategory,
      );
    },
  );
  test('host-wide support record cannot exempt a mandatory match', () async {
    final rules = MemoryRules([
      const GuardRuleMatch(
        host: 'mixed.test',
        kind: 'support',
        category: null,
        includeSubdomains: true,
        ruleId: 'support',
      ),
      const GuardRuleMatch(
        host: 'mixed.test',
        kind: 'category',
        category: GuardCategory.adult,
        includeSubdomains: true,
        ruleId: 'mandatory',
      ),
    ]);
    expect(
      (await NavigationPolicyService(repository: rules).evaluate(
        GuardRequest(
          uri: Uri.parse('https://mixed.test/education'),
          tabId: 't',
        ),
        GuardConfiguration(),
      )).isBlocked,
      true,
    );
  });
  test(
    'all threat kinds remain mandatory and private lookups skip the shared cache',
    () async {
      for (final pair in [
        ('malware', GuardCategory.malware),
        ('phishing', GuardCategory.phishing),
        ('harmful-download', GuardCategory.harmfulDownloads),
      ]) {
        final rules = MemoryRules([
          GuardRuleMatch(
            host: 'threat.test',
            kind: pair.$1,
            category: pair.$2,
            includeSubdomains: true,
            ruleId: 'threat',
          ),
        ]);
        final decision = await NavigationPolicyService(repository: rules)
            .evaluate(
              GuardRequest(
                uri: Uri.parse('https://threat.test'),
                tabId: 't',
                isPrivate: true,
                isDownload: true,
                hasAllowOnceGrant: true,
              ),
              GuardConfiguration(
                customAllow: {'threat.test'},
                overridesAllowed: true,
              ),
            );
        expect(decision.isSecurityBlock, true);
        expect(decision.overrideAllowed, false);
        expect(rules.lastUseCache, false);
      }
    },
  );
  test(
    'old JSON flags and manufactured decisions cannot restore override authority',
    () {
      final config = GuardConfiguration.fromJson({
        'guardEnabled': false,
        'enabledCategories': [],
        'customAllow': ['any.test'],
        'overridesAllowed': true,
        'dangerousDownloadProtection': false,
      });
      expect(config.guardEnabled, true);
      expect(config.customAllow, isEmpty);
      expect(config.overridesAllowed, false);
      expect(config.dangerousDownloadProtection, true);
      expect(config.activeCategories(testTime), containsAll(categories));
      expect(
        const GuardDecision(
          action: GuardAction.errorAllow,
          host: 'test',
          overrideAllowed: true,
        ).isBlocked,
        true,
      );
      expect(
        const GuardDecision(
          action: GuardAction.blockCategory,
          host: 'test',
          overrideAllowed: true,
        ).overrideAllowed,
        false,
      );
    },
  );
}
