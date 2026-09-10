# Monetization foundation

Wingman limits monetization to eligible owned surfaces. Browser pages are never ad inventory for Wingman. The current implementation has an optional real Google test-banner demo and empty sponsorship inventory. There is no production ad traffic, partnership revenue, fabricated impression count or pretend affiliate integration.

The current Phase 3A request/lifetime rules are defined in [Monetization policy](MONETIZATION_POLICY.md). Interests, reviewed sponsorship catalogs and live inventory remain deferred or disabled.

## Run the mobile test demo

```sh
flutter run -d <android-or-ios-device-id> --dart-define=WINGMAN_TEST_ADS=true
```

On eligible normal Wingman Home with standard protection requirements, choose **Load test advertisement**. The explanation identifies Google's technical processing. The integration updates UMP consent information, presents a required consent form when applicable, checks `canRequestAds`, initializes the SDK, and requests a non-personalized adaptive banner. If consent, configuration, network or fill is unavailable, browsing remains available and no empty ad-sized rectangle is reserved. If UMP requires a privacy-options entry, the demo displays **Advertising privacy choices** and disposes an existing ad before presenting the form. Ads do not automatically reload after changing consent.

The demo is absent in private mode, under unknown/strict protection requirements, beneath another route, while backgrounded, on web/desktop, without the flag, and in profile/release builds. The flag alone does not start requests. Google Mobile Ads supports Android/iOS rather than the web companion. [Google Flutter setup](https://developers.google.com/admob/flutter/quick-start)

The central `lib/config/ad_configuration.dart` selects Google's banner sample units:

| Target | Sample app ID (native config) | Sample banner unit (Dart config) |
| --- | --- | --- |
| Android | `ca-app-pub-3940256099942544~3347511713` | `ca-app-pub-3940256099942544/6300978111` |
| iOS | `ca-app-pub-3940256099942544~1458002511` | `ca-app-pub-3940256099942544/2934735716` |

These are Google's test inventory, not the developer's ad account. Test requests and impressions do not generate account revenue. Never automate ad clicks; do not use live inventory for UI tests. [Google test ads](https://developers.google.com/admob/flutter/test-ads)

Android's application manifest requires `com.google.android.gms.ads.APPLICATION_ID`; iOS requires `GADApplicationIdentifier` in Info.plist. The sample app IDs allow local integration work without inventing credentials. Native measurement-delay settings are defense in depth; do not assume they disable every SDK component. The actual request path remains gated in Dart.

## Policy and extension points

`AdPlacement` identifies Home, New Tab, owned content and owned search. `AdPolicyService` checks placement, route/foreground lifetime, private mode, coarse protection requirements and the known test-provider/inventory declaration before any UMP/SDK contact; consent and opt-in are required before a request. It rejects a generic browser page even if another caller supplies an owned placement. Current UI uses only `HomeAdSlot`, with a conservative `AdEligibilityContext`; missing context, live local state inputs (`eligibilityChanges`, `readEligibility`, `readIsPrivate`) or `adRouteObserver` Navigator registration denies the demo. Live notifications invalidate attempts before the next frame and each asynchronous gate rereads the current state. The slot must be mounted inside the Home module list and removed before displaying a browsing view. Do not wrap the browser scaffold, omnibox or arbitrary WebView with an ad component.

All requests are constructed in the monetization layer with `AdRequest(nonPersonalizedAds: true)`. No keywords, content URL, publisher-provided identifier, browsing-derived segment or location is provided. Non-personalized ads still require appropriate consent and disclosures. [Google non-personalized ad explanation](https://support.google.com/admob/answer/7676680)

`SponsorshipCatalog` is an interface with an empty default implementation. A `SponsoredShortcut` requires the sponsor identity, a title and an HTTP(S) destination; its disclosure is generated as “Sponsored by …”. Future code must add reviewed pre-render content metadata/Guard eligibility, show that disclosure and wait for an explicit click before opening the commercial destination through normal Guard. URL validation alone is not a completed sponsorship policy. The interface receives a placement, not browser history.

Search-provider partnership parameters belong in centralized provider configuration. Adding a referral parameter requires an actual agreement and a visible disclosure. Do not quietly change organic destinations, select partners from browsing histories or expose raw search queries to telemetry.

## Consent behavior

`AdConsentManager` wraps a replaceable `ConsentGateway`. Concurrent calls share one refresh; a new session manager checks UMP again. A successful update precedes required forms and `canRequestAds`. Each slot attempt has its own immutable generation. Route cover/pop, protection/private changes and foreground loss cancel the previous attempt before subsequent work; returning Home does not revive it. Required forms load separately from presentation; the manager rechecks the Home lifetime before showing a loaded form and disposes it if Home has disappeared. Leaving or covering Home during earlier UMP operations also prevents continuation. SDK configuration checks cancellation between awaits, with mandatory post-initialization Android identity cleanup completing even after cancellation; a canceled attempt cannot request an ad. An already presented native form has no programmatic dismissal API here. Unknown/error states deny requests, deliberately stricter than using UMP's cached permission after an error. Existing privacy choices remain reachable after a form error. A demo button tap is not a substitute for legal consent. The consent manager never stores a homemade “consent granted” flag in Wingman's database. [Google UMP guidance](https://developers.google.com/admob/flutter/privacy)

Production must configure real messages in AdMob Privacy & messaging, test applicable regional flows and age treatment, and expose required privacy options throughout the supported product experience. Do not treat UMP's request permission alone as proof that every downstream configuration complies with Wingman's mission.

## Production is intentionally closed

`WINGMAN_ANDROID_BANNER_ID` and `WINGMAN_IOS_BANNER_ID` are reserved centralized environment inputs. They do **not** enable production ads. The configuration returns no ad unit in release builds. Enabling production requires a reviewed implementation change after these concrete external steps:

1. Create the actual AdMob app records and units, connect the true bundle/application IDs, and configure account readiness and any required app-ads.txt ownership verification.
2. Replace sample native app IDs through reviewed native build configuration. Supply production unit IDs through the centralized environment inputs, keeping them out of widgets.
3. Configure UMP messages, persistent privacy-options access, regional/age handling and tests for acceptance, refusal, unavailable networks and changed choices.
4. Confirm publisher first-party identifiers remain disabled. Android uses the native setting; the iOS Flutter method maps to the native publisher first-party setting. [Google Android setting](https://developers.google.com/admob/android/privacy/strategies), [Google iOS setting](https://developers.google.com/admob/ios/privacy/strategies)
5. Audit actual SDK traffic and identifiers, store privacy disclosures, native permissions and the archive's privacy manifests. This foundation does not request ATT or build cross-site ad profiles; any proposed tracking is a product-policy conflict requiring redesign. SKAdNetwork/AdAttributionKit configuration is not fabricated here.
6. Validate spacing, rotation, accessibility, backgrounding and disposal on devices, then have the store operator review the disclosures and distribution configuration.

No live accounts, store records, messages, production IDs or commercial agreements were created during local implementation. See [privacy architecture](PRIVACY.md) for actual data caveats.

## Historical native smoke verification

The recorded result below predates the Phase 3 eligibility/route changes. Updated host regressions pass separately; a fresh native rerun must be recorded before claiming the revised native path has been exercised.

### Run the native scenario

Run the optional native smoke scenario explicitly; ordinary integration runs skip it without the ad flag:

```sh
flutter test integration_test/ads_smoke_test.dart -d <android-or-ios-device-id> --dart-define=WINGMAN_TEST_ADS=true
```

It taps only Wingman's test-demo opt-in button, never the ad creative. It uses the real UMP/Google services without granting consent artificially, resetting consent, overriding geography or substituting a mocked SDK. Its fixed `WINGMAN_AD_SMOKE_RESULT` JSON distinguishes an actual rendered banner from consent/network/unavailable outcomes. A safe denied-request result can pass the boundary checks without proving banner delivery; inspect `actualBannerRendered` and `outcome`.

On September 10, 2026, the iOS 26.3 iPhone 17 Pro simulator rerun passed **after** the final required-form load/presentation cancellation change. It reported `actualBannerRendered: true`, `outcome: bannerLoaded`. The real sequence was consent check, SDK initialization, banner request and loaded native AdWidget; UMP reported ads requestable. It also began a native consent operation, removed Home while pending, and observed only `consentStarted` then `disposed`, with `pendingAtUnmount: true` and `noAdAfterUnmount: true`. There was no ad or later callback on the replacement surface. Xcode build took 49 seconds and test execution 21 seconds. This verifies the iOS sample-inventory path and pending-operation disposal on that simulator, not physical-device ad behavior, every form/consent region, or production account readiness. Focused tests separately cover cancellation while a required form is loading; no regional consent configuration was forced during this native run.

`HomeAdSlot.onStatusChanged` exposes only a finite lifecycle enum for this verification. It does not include an SDK response, device identifier, URL, search term or error text, and the normal app does not install a listener.
