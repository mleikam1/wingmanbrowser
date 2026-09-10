# Wingman privacy architecture

**We've got your back, not your data.**

Your browsing history is yours. Wingman doesn't sell your browsing history, build an advertising profile from the sites you visit, or inject Wingman ads into the websites you browse.

This document describes the implementation and remaining release work. It is not a substitute for a published privacy policy identifying the eventual operator, contact details, applicable rights, retention by service providers, and regional practices.

## Your data

Wingman has no application backend, account system, synchronization service, browsing proxy, or page-analysis service. Normal navigation goes to the website. A submitted search goes directly to the selected search provider. Wingman does not send the same query or page to a separate telemetry endpoint.

| Data | Current storage and behavior |
| --- | --- |
| Normal history | Local SQLite; most recent visit for each URL; retained up to 90 days and 5,000 URLs, pruned at startup and on writes |
| Bookmarks | Separate local SQLite table; only explicit user actions add bookmarks |
| Normal tab metadata | Local SQLite; separate from live browser controllers |
| Preferences | Local SQLite; includes theme, chosen search provider, Guard categories, custom site rules and Focus settings |
| Private history and tab metadata | Memory only; filtered before state persistence and again at the repository boundary |
| Private bookmarks | Disabled to avoid accidental persistent records |
| Page contents and forms | Handled by the platform browser engine and the website; not forwarded to Wingman servers |
| Product telemetry | No analytics upload; default analytics implementation is a no-op |

The web companion uses SQLite WASM in a worker with IndexedDB persistence under the companion's origin. A different development port is a different origin. Browser storage can be cleared or evicted and is not a backup. The upstream web SQLite adapter is experimental. No arbitrary third-party websites are embedded by the companion.

Local storage is not application-level encrypted. Device access controls protect app files, and another person with access to an unlocked device may see history. Android app backup is disabled. iOS places the structured database in backup-excluded Library/Application Support/Wingman, outside the Files-visible Documents directory. That exclusion does not establish backup treatment for every OS-managed normal website file or user download. SQLite secure deletion is enabled for deleted database records; this does not promise removal from previous operating-system backups, storage snapshots, or exported copies. Clear browsing data is an explicit user action, with categories explained before deletion.

## Private browsing

Private browsing changes storage behavior. Private pages do not enter Wingman's persistent history. Their tab metadata does not survive restart. On iOS, the private `WKWebsiteDataStore.nonPersistent()` is assigned before WKWebView creation and the native adapter verifies it is nonpersistent before loading a page. A minimal local patch exposes the configuration object to the app; changing a WebView's store after creation would not provide this guarantee.

Android requires WebView support for both multiple profiles and profile browsing-data deletion. Every private tab receives a separate profile with no normal-tab cookies. Cache mode disables normal caching. Closing or evicting that tab removes its profile cookies and browsing data and destroys the view. Android can temporarily write isolated profile data to disk while the tab is open; private mode is **not** a promise of memory-only website storage. A loaded profile cannot be removed from the profile registry in the same process. The next app launch removes abandoned private-profile directories before loading profiles, including remnants after an unclean exit. Android app backup is disabled.

At most three browser engines stay live. Evicting an inactive private engine ends its private site session; returning to it reloads the URL into fresh private storage. Private tabs do not share session cookies with one another in this foundation. Normal and private metadata remain separate from expensive controllers. See the README for device verification and platform limitations.

Private browsing is not a VPN or an anonymity network. Websites, searches, network providers, employers and schools can still observe traffic they handle. Downloads, explicit sharing, external apps and files saved by the user may remain outside Wingman's private session. Wingman's web companion cannot control or erase a separate browser's private mode, cookies or history.

## Wingman Guard

Routine Guard classification uses local normalized domains and a signature-verified indexed filter pack. It sends no navigation URL, page content, custom rule, PIN, or chosen sensitive category to Wingman infrastructure. The bundled starter has limited coverage; an unmatched site is not a finding that it is safe. No Web Risk API client, remote filter endpoint, cloud account sync, device-wide VPN, parental-management service or browser extension is active.

Private requests skip the shared domain-result cache and saved Guard statistics. The daily summary stores only a local date and three totals, with no per-site event log. Users can reset it. Local omnibox suggestions consult normal bookmarks/history only; private tabs do not consult them and no keystrokes are sent for suggestions. Temporary exceptions remain in memory. Explicitly creating an always-allow/custom site rule saves that preference locally, including when initiated from a private tab; automatic private browsing history and counters remain excluded.

The optional mobile Family PIN stores a random salt, derived verifier and retry state in platform secure storage. It does not store plaintext in SQLite, provide account recovery, or control other apps. Secure-store errors leave settings locked. See [PIN design and actual native checks](GUARD_PIN.md).

Native Android Safe Browsing and WebKit fraudulent-site warnings remain enabled where supported and can use platform-managed network services. Wingman returns Android threat hits to safety with optional reporting disabled, and opts out of Android WebView usage metrics. The usage setting does not disable all engine crash reports. These platform behaviors are distinct from Wingman's local classifier and no-op application telemetry. [Safe Browsing response reporting](https://developer.android.com/reference/android/webkit/SafeBrowsingResponse#backToSafety(boolean)), [WebView privacy](https://developer.android.com/develop/ui/views/layout/webapps/webview-privacy)

A small licensed third-party tracker list applies only to browsing views. It does not process Wingman's owned ad view, replace publisher ads, or upload resource URLs. Android exposes batched local blocked-resource counts; iOS reports counts as unavailable because its compiled content rules do not provide a reliable equivalent.

The report composer defaults to no address, shows the proposed text, and copies or opens a selected share target only after an explicit action. Choosing a full address can disclose search terms or tokens, so it requires a separate selection and visible preview. No Wingman reporting inbox or automatic submission exists. [Complete data-flow and network inventory](PRIVACY_ARCHITECTURE.md), [providers and licensing](PHASE2_PROVIDERS.md)

## Monetization boundary

Wingman can earn money from labeled placements on its own Home, modules, search partnerships or explicitly initiated affiliate links. No contracts or live revenue are simulated in this build. There are no publisher-ad replacements, interstitial navigation gates or rewarded browsing gates.

`AdPlacement` has only explicit owned placements. `AdPolicyService` rejects browser-page routes, private sessions, route mismatches, missing consent and missing opt-in. The ad component receives no URL, page title, content, search terms, history, location or user identifier. Do not register a browsing WebView with `MobileAds.registerWebView`; do not enable ad SDK web-content integration.

Advertisements are off by default. The mobile debug demo requires the build flag, a Home button tap, and UMP authorization before an ad request. Release builds cannot request ads. The native SDK remains linked in the mobile app even with the demo off; Wingman does not claim that linking, platform registration or an initialized SDK implies zero processing. A loaded demo ad is disposed when its Home widget is removed. The SDK has no general shutdown API; leaving Home is not a promise that all SDK background activity has ended. See [monetization setup](MONETIZATION.md).

## SDK data is not browsing telemetry

Google's Android disclosure lists IP address, product interactions, diagnostics and device/account identifiers among SDK data. It describes purposes including advertising, analytics and fraud prevention. Removing advertising-ID access does not eliminate every other identifier or category. [Google Android data disclosure](https://developers.google.com/admob/android/privacy/play-data-disclosure)

Google's iOS disclosure describes possible IP-derived location, diagnostics/performance information, device identifiers, ad activity and interactions. Its SDK privacy manifest is evidence to inspect alongside actual configuration. It does not complete the app's disclosure for the developer. [Google iOS data disclosure](https://developers.google.com/admob/ios/privacy/data-disclosure)

The request explicitly selects non-personalized ads. This does not mean no cookies, no identifiers, no technical processing or no consent requirement. UMP and regional configuration remain necessary. [Google explanation of non-personalized ads](https://support.google.com/admob/answer/7676680)

Android removes the advertising-ID permission from the merged manifest and disables publisher first-party ID using the native SDK setting after initialization and before the first ad request. Before mobile ad initialization, Wingman disables iOS publisher first-party ID using the Flutter API that maps to Google's native setting, disables iOS SDK crash reporting, and disables mediation initialization. No mediation adapters, Firebase Analytics, Google Analytics, Meta, attribution SDKs, or standalone crash-reporting services are installed. These choices do not justify claiming that Google receives no diagnostic data on all platforms.

## Diagnostics and future analytics

`ProductAnalytics` accepts a fixed event enum and a private-session flag. It cannot accept arbitrary properties or URL payloads. The production implementation does nothing. Optional in-memory aggregate counters exclude private activity, contain no timestamps or identifiers, and have no network/export path.

`DiagnosticSanitizer` maps failures to fixed technical codes and URLs to transport categories. Even hostnames are omitted: a hostname can reveal a sensitive interest. It never calls `toString()` on a raw exception. Do not add direct logging of navigation callbacks, titles, headers, forms, tokens, search input or platform error descriptions. An eventual telemetry provider requires an explicit privacy design and approval; an interface is not authorization to install one.

Future sync and AI features must be separate, optional capabilities. Sync needs an explicit consent and encryption design. Any AI request involving a page must start with a user action and clearly identify the scoped content leaving the device. No background page analysis is present.

## Store release review

Apple requires app privacy answers to include integrated partners. Its open-web WebView guidance is distinct from data collected by the app's own SDKs. The published policy, App Store answers and final binary must agree. Inspect the archive's privacy report and required-reason APIs. Do not select a blanket “no data collected” answer based solely on Wingman's lack of a backend. [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)

Google Play Data Safety must reflect the final installed SDK versions, manifest, SDK settings and actual collection/sharing. Recheck Google's SDK disclosure before release and after a dependency change. No final store form has been submitted or fabricated.

## Verification

Automated ad/privacy tests cover forbidden surfaces, private exclusion, release denial, consent failures and changes, no raw URL diagnostics, and zero ad space with the demo disabled. Repository tests separately cover private data persistence and history retention. A store release additionally requires network inspection of cold start, ordinary browsing, private sessions, test-ad opt-in and consent withdrawal on real mobile targets. Automated policy tests do not prove that a third-party SDK sends no other traffic.

Sources reviewed September 10, 2026. Recheck sources against the exact release SDKs.
