import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/config/product_edition.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import '../support/protected_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ConsumerProtectionPolicy baseline;
  setUpAll(() async {
    baseline = await ConsumerProtectionPolicy.load(
      bundle: LocalCatalogBundle(),
    );
    expect(baseline.isUsable, true);
  });

  test(
    'complete published subsets exceed demonstration scale with all categories',
    () {
      expect(baseline.domains.length, MandatoryCategory.values.length);
      expect(
        baseline.domains[MandatoryCategory.sexualExplicit]!.length,
        greaterThan(70000),
      );
      expect(
        baseline.domains[MandatoryCategory.gambling]!.length,
        greaterThan(60000),
      );
      expect(
        baseline.domains[MandatoryCategory.securityThreat]!.length,
        greaterThan(170000),
      );
    },
  );

  test('ordinary and mixed-domain paths need no reviewed document record', () {
    for (final url in [
      'https://www.espn.com/nba/',
      'https://www.walmart.com/shop/deals',
      'https://www.nasa.gov/',
      'https://www.wikipedia.org/',
      'https://www.mozilla.org/',
      'https://www.apple.com/',
      'https://www.weather.gov/',
      'https://www.nps.gov/',
      'https://www.britannica.com/',
      'https://www.khanacademy.org/',
      'https://ordinary-unclassified.protection.test/interactive?form=1',
      'https://mixed.protection.test/education/alcohol-recovery',
      'https://www.cancer.gov/types/breast',
      'https://nida.nih.gov/',
      'https://en.academic.ru/',
    ]) {
      expect(
        baseline.assessNavigation(Uri.parse(url)).code,
        PolicyDecisionCode.allowPermitted,
        reason: url,
      );
    }
  });

  test(
    'category domain, suffix, decoded paths and boundaries stay mandatory',
    () {
      for (final entry in {
        'sexual-explicit': MandatoryCategory.sexualExplicit,
        'gambling': MandatoryCategory.gambling,
        'alcohol': MandatoryCategory.alcoholPromotion,
        'drugs': MandatoryCategory.recreationalDrugPromotion,
        'tobacco': MandatoryCategory.tobaccoNicotine,
        'security-threat': MandatoryCategory.securityThreat,
      }.entries) {
        for (final prefix in ['', 'sub.']) {
          final decision = baseline.assessNavigation(
            Uri.parse('https://$prefix${entry.key}.protection.test./'),
          );
          expect(decision.isAllowed, false);
          expect(decision.category, entry.value);
        }
      }
      for (final url in [
        'https://www.espn.com/espn/betting',
        'https://www.espn.com/ESPN/%62etting/',
        'https://www.espn.com/x/%2e%2e/espn/betting/',
        'https://www.walmart.com/cp/beer-wine-spirits/123',
        'https://mixed.protection.test/promotion/alcohol/',
      ]) {
        expect(
          baseline.assessNavigation(Uri.parse(url)).isAllowed,
          false,
          reason: url,
        );
      }
      for (final url in [
        'https://www.espn.com/espn/betting-education',
        'https://mixed.protection.test/promotion/alcohol-recovery',
        'https://gambling.protection.test.example.com/',
      ]) {
        expect(
          baseline.assessNavigation(Uri.parse(url)).isAllowed,
          true,
          reason: url,
        );
      }
    },
  );

  test(
    'missing or damaged baseline is a recovery state, not unknown classification',
    () async {
      final bytes = await File(
        ConsumerProtectionPolicy.assetPath,
      ).readAsBytes();
      final modified = Uint8List.fromList(bytes)..[bytes.length ~/ 2] ^= 1;
      final corrupt = await ConsumerProtectionPolicy.verifyBytes(modified);
      expect(corrupt.errorCode, 'baseline-integrity');
      expect(
        corrupt.assessNavigation(Uri.parse('https://www.nasa.gov/')).code,
        PolicyDecisionCode.blockPolicyUnavailable,
      );
      expect(
        baseline
            .assessNavigation(
              Uri.parse('https://new-unclassified.protection.test'),
            )
            .code,
        PolicyDecisionCode.allowPermitted,
      );
      expect(baseline.isStale(DateTime.utc(2030)), true);
      expect(baseline.isUsable, true);
    },
  );

  test(
    'additive domain restrictions persist and cannot disable the baseline',
    () {
      final restrictions = AdditionalRestrictions.fromJson({
        'blockedDomains': ['WALMART.COM.', 'https://ignored.example/', ''],
        'disabledCategories': MandatoryCategory.values
            .map((c) => c.id)
            .toList(),
      });
      expect(restrictions.blockedDomains, {'walmart.com'});
      expect(
        AdditionalRestrictions.fromJson(restrictions.toJson()).blockedDomains,
        {'walmart.com'},
      );
      expect(
        baseline
            .assessNavigation(
              Uri.parse('https://www.walmart.com/'),
              additional: restrictions,
            )
            .code,
        PolicyDecisionCode.blockAdditionalRestriction,
      );
      expect(
        baseline
            .assessNavigation(
              Uri.parse('https://gambling.protection.test/'),
              additional: restrictions,
            )
            .category,
        MandatoryCategory.gambling,
      );
    },
  );

  test(
    'tracker subset does not ban ordinary third party dependencies or navigation',
    () {
      final tracker = baseline.trackers.first;
      expect(
        baseline.isKnownThirdPartyTracker(
          Uri.parse('https://$tracker/pixel'),
          Uri.parse('https://ordinary.example'),
        ),
        true,
      );
      expect(
        baseline.isKnownThirdPartyTracker(
          Uri.parse('https://cdn.jsdelivr.net/npm/x.js'),
          Uri.parse('https://ordinary.example'),
        ),
        false,
      );
      expect(
        baseline.isKnownThirdPartyTracker(
          Uri.parse('https://$tracker/page'),
          Uri.parse('https://$tracker/'),
        ),
        false,
      );
    },
  );

  test(
    'saved reviewed-site restrictions subtract after catalog expiry',
    () async {
      final runtime = await loadTestPolicy();
      addTearDown(runtime.dispose);
      runtime.configureLiveBrowsing(
        await LiveBrowsingPolicy.load(bundle: LocalCatalogBundle()),
        nativeAvailable: true,
        privateAvailable: true,
      );
      runtime.repository.restrict('expired');
      final uri = Uri.parse('https://science.nasa.gov/moon/facts/');
      expect(
        runtime.policy.evaluate(PolicyRequest.navigation(uri)).isAllowed,
        true,
      );
      final id = runtime.policy.livePolicy!.siteForUri(uri)!.id;
      final restrictions = AdditionalRestrictions(
        blockedResourceIds: [id],
        blockedDomains: ['example.net'],
      );
      expect(
        runtime.nativeConsumerConfiguration(restrictions)['blockedDomains'],
        ['example.net'],
      );
      expect(
        runtime.nativeConsumerConfiguration(restrictions)['blockedUrls'],
        contains(uri.toString()),
      );
      expect(
        runtime.policy
            .evaluate(
              PolicyRequest.navigation(
                Uri.parse('https://science.nasa.gov/unlisted/path'),
              ),
              additional: restrictions,
            )
            .isAllowed,
        true,
      );
      expect(
        runtime.policy
            .evaluate(
              PolicyRequest.navigation(Uri.parse('https://www.nasa.gov/')),
              additional: restrictions,
            )
            .isAllowed,
        true,
      );

      expect(
        runtime.policy
            .evaluate(
              PolicyRequest.navigation(uri),
              additional: AdditionalRestrictions(blockedResourceIds: [id]),
            )
            .code,
        PolicyDecisionCode.blockAdditionalRestriction,
      );
    },
  );

  test(
    'school configuration cannot inherit the consumer permit-by-default rule',
    () async {
      final runtime = await loadTestPolicy();
      addTearDown(runtime.dispose);
      final service =
          ContentEligibilityService(
              runtime.repository,
              edition: ProductEdition.student,
            )
            ..nativeLiveAvailable = true
            ..nativeSearchAvailable = true
            ..consumerProtection = baseline
            ..livePolicy = await LiveBrowsingPolicy.load(
              bundle: LocalCatalogBundle(),
            );
      expect(
        service
            .evaluate(
              PolicyRequest.navigation(Uri.parse('https://www.walmart.com/')),
            )
            .code,
        PolicyDecisionCode.blockUnreviewed,
      );
      expect(
        service
            .evaluate(
              PolicyRequest.navigation(
                const StrictSearchPolicy().buildQuery('moon'),
              ),
            )
            .isAllowed,
        false,
      );
    },
  );
}
