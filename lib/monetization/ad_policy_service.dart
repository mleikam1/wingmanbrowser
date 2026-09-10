import '../config/ad_configuration.dart';

/// App route identity, never a hostname or a value supplied by a website.
enum AdHostSurface {
  unknown,
  home,
  newTab,
  ownedContent,
  ownedSearch,
  browserPage,
  guardBlock,
  securityWarning,
  helpNow,
  support,
  settings,
}

/// This coarse local decision never identifies a category or support activity.
/// Unknown and active stricter requirements both withhold unverified inventory.
enum AdProtectionRequirements { unknown, standard, strict }

class AdEligibilityContext {
  const AdEligibilityContext({
    this.currentSurface = AdHostSurface.unknown,
    this.isCurrentRoute = false,
    this.isForeground = false,
    this.protectionRequirements = AdProtectionRequirements.unknown,
  });

  final AdHostSurface currentSurface;
  final bool isCurrentRoute;
  final bool isForeground;
  final AdProtectionRequirements protectionRequirements;

  @override
  bool operator ==(Object other) =>
      other is AdEligibilityContext &&
      other.currentSurface == currentSurface &&
      other.isCurrentRoute == isCurrentRoute &&
      other.isForeground == isForeground &&
      other.protectionRequirements == protectionRequirements;

  @override
  int get hashCode => Object.hash(
    currentSurface,
    isCurrentRoute,
    isForeground,
    protectionRequirements,
  );
}

/// These declarations describe the reviewed development integration only.
/// They are local policy inputs, never claims returned by a creative or SDK.
/// There is no enabled live inventory or strict-compatible provider here.
enum AdProviderCapability { unknown, standardTestInventoryOnly }

enum AdContentSuitability { unknown, reviewedTestInventory }

/// Only explicit owned placements can be constructed.
enum AdPlacement {
  homeBanner(AdHostSurface.home),
  newTabBanner(AdHostSurface.newTab),
  ownedModule(AdHostSurface.ownedContent),
  ownedSearch(AdHostSurface.ownedSearch);

  const AdPlacement(this.hostSurface);
  final AdHostSurface hostSurface;
}

enum AdDecision {
  allowed,
  externalPage,
  privateSession,
  sensitiveSurface,
  surfaceMismatch,
  inactiveSurface,
  protectionUnknown,
  protectionIncompatible,
  providerUnverified,
  contentUnverified,
  adsDisabled,
  consentUnavailable,
  notOptedIn,
}

/// The eligibility preflight also gates UMP and SDK initialization. No API
/// accepts URLs, search text, Guard categories, interests or user identifiers.
class AdPolicyService {
  const AdPolicyService();

  AdDecision preflight({
    required AdPlacement placement,
    required AdEligibilityContext context,
    required bool isPrivate,
    required AdConfiguration configuration,
    AdProviderCapability providerCapability = AdProviderCapability.unknown,
    AdContentSuitability contentSuitability = AdContentSuitability.unknown,
  }) {
    if (context.currentSurface == AdHostSurface.browserPage) {
      return AdDecision.externalPage;
    }
    if (isPrivate) return AdDecision.privateSession;
    if (const {
      AdHostSurface.guardBlock,
      AdHostSurface.securityWarning,
      AdHostSurface.helpNow,
      AdHostSurface.support,
      AdHostSurface.settings,
    }.contains(context.currentSurface)) {
      return AdDecision.sensitiveSurface;
    }
    if (placement.hostSurface != context.currentSurface) {
      return AdDecision.surfaceMismatch;
    }
    if (!context.isCurrentRoute || !context.isForeground) {
      return AdDecision.inactiveSurface;
    }
    if (context.protectionRequirements == AdProtectionRequirements.unknown) {
      return AdDecision.protectionUnknown;
    }
    if (context.protectionRequirements == AdProtectionRequirements.strict) {
      return AdDecision.protectionIncompatible;
    }
    if (providerCapability != AdProviderCapability.standardTestInventoryOnly) {
      return AdDecision.providerUnverified;
    }
    if (contentSuitability != AdContentSuitability.reviewedTestInventory) {
      return AdDecision.contentUnverified;
    }
    if (!configuration.canOfferTestAds) return AdDecision.adsDisabled;
    return AdDecision.allowed;
  }

  AdDecision evaluate({
    required AdPlacement placement,
    required AdEligibilityContext context,
    required bool isPrivate,
    required AdConfiguration configuration,
    required bool consentReady,
    required bool userOptedIn,
    AdProviderCapability providerCapability = AdProviderCapability.unknown,
    AdContentSuitability contentSuitability = AdContentSuitability.unknown,
  }) {
    final eligibility = preflight(
      placement: placement,
      context: context,
      isPrivate: isPrivate,
      configuration: configuration,
      providerCapability: providerCapability,
      contentSuitability: contentSuitability,
    );
    if (eligibility != AdDecision.allowed) return eligibility;
    if (!userOptedIn) return AdDecision.notOptedIn;
    if (!consentReady) return AdDecision.consentUnavailable;
    return AdDecision.allowed;
  }
}
