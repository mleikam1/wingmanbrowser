import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/config/ad_configuration.dart';
import 'package:wingman_browser/monetization/ad_policy_service.dart';
import 'package:wingman_browser/monetization/sponsorship_catalog.dart';

void main() {
  const policy = AdPolicyService();
  const testConfiguration = AdConfiguration(
    platform: AdPlatform.android,
    isDebug: true,
    testAdsEnabled: true,
  );

  AdDecision decide({
    AdPlacement placement = AdPlacement.homeBanner,
    AdHostSurface surface = AdHostSurface.home,
    bool isPrivate = false,
    bool isCurrentRoute = true,
    bool isForeground = true,
    AdProtectionRequirements requirements = AdProtectionRequirements.standard,
    AdProviderCapability provider =
        AdProviderCapability.standardTestInventoryOnly,
    AdContentSuitability suitability =
        AdContentSuitability.reviewedTestInventory,
    bool consent = true,
    bool optedIn = true,
    AdConfiguration configuration = testConfiguration,
  }) => policy.evaluate(
    placement: placement,
    context: AdEligibilityContext(
      currentSurface: surface,
      isCurrentRoute: isCurrentRoute,
      isForeground: isForeground,
      protectionRequirements: requirements,
    ),
    providerCapability: provider,
    contentSuitability: suitability,
    isPrivate: isPrivate,
    configuration: configuration,
    consentReady: consent,
    userOptedIn: optedIn,
  );

  test(
    'every placement rejects third-party browser content and private mode',
    () {
      for (final placement in AdPlacement.values) {
        expect(
          decide(placement: placement, surface: AdHostSurface.browserPage),
          AdDecision.externalPage,
        );
        expect(
          decide(
            placement: placement,
            surface: placement.hostSurface,
            isPrivate: true,
          ),
          AdDecision.privateSession,
        );
      }
    },
  );

  test('an owned placement must match its actual owned route', () {
    expect(
      decide(surface: AdHostSurface.ownedSearch),
      AdDecision.surfaceMismatch,
    );
    expect(decide(), AdDecision.allowed);
  });

  test('sensitive and unknown routes cannot become inventory', () {
    for (final surface in [
      AdHostSurface.guardBlock,
      AdHostSurface.securityWarning,
      AdHostSurface.helpNow,
      AdHostSurface.support,
      AdHostSurface.settings,
    ]) {
      for (final placement in AdPlacement.values) {
        expect(
          decide(placement: placement, surface: surface),
          AdDecision.sensitiveSurface,
        );
      }
    }
    expect(decide(surface: AdHostSurface.unknown), AdDecision.surfaceMismatch);
  });

  test(
    'foreground top route and verified protection are independent gates',
    () {
      expect(decide(isCurrentRoute: false), AdDecision.inactiveSurface);
      expect(decide(isForeground: false), AdDecision.inactiveSurface);
      expect(
        decide(requirements: AdProtectionRequirements.unknown),
        AdDecision.protectionUnknown,
      );
      expect(
        decide(requirements: AdProtectionRequirements.strict),
        AdDecision.protectionIncompatible,
      );
      expect(
        decide(provider: AdProviderCapability.unknown),
        AdDecision.providerUnverified,
      );
      expect(
        decide(suitability: AdContentSuitability.unknown),
        AdDecision.contentUnverified,
      );
    },
  );

  test('the default context denies even a fully configured debug demo', () {
    expect(
      policy.preflight(
        placement: AdPlacement.homeBanner,
        context: const AdEligibilityContext(),
        isPrivate: false,
        configuration: testConfiguration,
        providerCapability: AdProviderCapability.standardTestInventoryOnly,
        contentSuitability: AdContentSuitability.reviewedTestInventory,
      ),
      isNot(AdDecision.allowed),
    );
  });

  test('consent and explicit demo opt-in are independently required', () {
    expect(decide(consent: false), AdDecision.consentUnavailable);
    expect(decide(optedIn: false), AdDecision.notOptedIn);
  });

  test('release requests fail closed even with supplied production IDs', () {
    for (final platform in AdPlatform.values) {
      final configuration = AdConfiguration(
        platform: platform,
        isDebug: false,
        testAdsEnabled: true,
        androidProductionBannerId: 'ca-app-pub-1234567890123456/1234567890',
        iosProductionBannerId: 'ca-app-pub-1234567890123456/1234567890',
      );
      expect(decide(configuration: configuration), AdDecision.adsDisabled);
      expect(configuration.bannerUnitId, isNull);
    }
  });

  test('disabled and unsupported targets cannot resolve an ad unit', () {
    const configurations = [
      AdConfiguration(
        platform: AdPlatform.android,
        isDebug: true,
        testAdsEnabled: false,
      ),
      AdConfiguration(
        platform: AdPlatform.unsupported,
        isDebug: true,
        testAdsEnabled: true,
      ),
    ];
    for (final configuration in configurations) {
      expect(configuration.bannerUnitId, isNull);
      expect(decide(configuration: configuration), AdDecision.adsDisabled);
    }
  });

  test(
    'debug units are always Google samples despite production environment',
    () {
      expect(
        testConfiguration.bannerUnitId,
        'ca-app-pub-3940256099942544/6300978111',
      );
      const ios = AdConfiguration(
        platform: AdPlatform.ios,
        isDebug: true,
        testAdsEnabled: true,
        iosProductionBannerId: 'customer-inventory-must-not-be-used',
      );
      expect(ios.bannerUnitId, 'ca-app-pub-3940256099942544/2934735716');
    },
  );

  test(
    'sponsored shortcuts require disclosure and safe explicit destinations',
    () {
      final shortcut = SponsoredShortcut(
        title: 'An offer',
        sponsor: 'Example sponsor',
        destination: Uri.parse('https://example.com/offer'),
      );
      expect(shortcut.disclosure, 'Sponsored by Example sponsor');
      for (final destination in [
        'javascript:alert(1)',
        'file:///private/file',
        'https://',
        'https://user:secret@example.com/',
      ]) {
        expect(
          () => SponsoredShortcut(
            title: 'Offer',
            sponsor: 'Sponsor',
            destination: Uri.parse(destination),
          ),
          throwsArgumentError,
        );
      }
    },
  );
}
