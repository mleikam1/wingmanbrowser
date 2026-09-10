import '../config/ad_configuration.dart';

/// Route identity, not a hostname or a value supplied by a website.
enum AdHostSurface { home, newTab, ownedContent, ownedSearch, browserPage }

/// Explicitly owned placements. A browser-page placement cannot be constructed.
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
  surfaceMismatch,
  adsDisabled,
  consentUnavailable,
  notOptedIn,
}

/// Pure, testable boundary shared by every future provider. No API accepts a
/// URL, search query, page title, page content, audience or user identifier.
class AdPolicyService {
  const AdPolicyService();

  AdDecision evaluate({
    required AdPlacement placement,
    required AdHostSurface currentSurface,
    required bool isPrivate,
    required AdConfiguration configuration,
    required bool consentReady,
    required bool userOptedIn,
  }) {
    if (currentSurface == AdHostSurface.browserPage) {
      return AdDecision.externalPage;
    }
    if (isPrivate) return AdDecision.privateSession;
    if (placement.hostSurface != currentSurface) {
      return AdDecision.surfaceMismatch;
    }
    if (!configuration.canOfferTestAds) return AdDecision.adsDisabled;
    if (!userOptedIn) return AdDecision.notOptedIn;
    if (!consentReady) return AdDecision.consentUnavailable;
    return AdDecision.allowed;
  }
}
