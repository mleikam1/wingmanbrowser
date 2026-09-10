# Wingman monetization policy

**We've got your back, not your data.** Protection and support are never advertising opportunities. Ordinary browsing and core Guard do not require payment or an account.

## Current status

The Phase 3A local eligibility and cancellation boundary is implemented with automated regression tests. Production advertisements are **disabled pending approval/review**. The only provider path is an explicit mobile debug demo using Google's official test units; test impressions earn no revenue. Real sponsorship inventory is empty. There are no search agreements, affiliate commissions or fabricated earnings.

User-chosen interests and reviewed owned-content catalogs belong to **deferred milestone 3C**. This milestone does not introduce a feed, partnerships, audience segments, remote interest storage or new SDKs. No cloud resources, production ad settings or commercial search configuration are created or changed by this work.

## Eligibility before contact

`AdPolicyService.preflight` runs before UMP, SDK initialization, sizing, banner construction and loading. `evaluate` adds the consent and explicit opt-in checks. A request requires every applicable gate:

| Gate | Required behavior |
| --- | --- |
| Surface ownership | Placement matches an explicitly identified Wingman-owned surface. The current widget supports Home only; external browsing is rejected. |
| Sensitive surfaces | Guard blocks, security warnings, Help Now, support and settings are always ineligible. Unknown surface identity is ineligible. |
| Private mode | No Wingman ad/consent operation starts from a private slot. |
| Visible lifetime | Owned Home is the current route, app is resumed, and the registered route observer belongs to that Navigator. Hidden Home under a page, dialog or popup is not eligible. |
| Protection requirements | Unknown or strict requirements deny the current provider. Only explicitly known standard requirements may continue. The shell treats configured/locked PIN, active Focus, custom blocks and enabled Guard categories conservatively; unavailable protection state is unknown. |
| Provider/content review | A known development-provider capability and test-inventory declaration are required. No unknown creative source, live inventory or strict-compatible provider is declared. |
| Build configuration | Mobile debug build, explicit `WINGMAN_TEST_ADS=true`, and Google's sample unit. Release/profile/web/unsupported targets cannot resolve a unit. |
| User choice and consent | The user taps the demo control. A fresh UMP check and any required form precede `canRequestAds`; errors/unknown/refusal deny the SDK/request. |

The protection input is only the local enum `unknown`, `standard` or `strict`. It is never transmitted to a provider. No ad-layer API accepts Guard categories, block events, Help Now activity, recovery interests, page contents, URLs, search terms or browser-derived audiences. Do not encode these in ad-unit IDs, custom targeting, reporting labels or request metadata.

## Lifetime and failure behavior

`adRouteObserver` must be registered on the app Navigator. It synchronously invalidates an attempt when another route covers Home. The slot also checks actual `ModalRoute.isCurrent`, so an async completion cannot exploit the interval before a widget rebuild. A local `eligibilityChanges` subscription and live `readEligibility`/`readIsPrivate` callbacks are also required; absent or failing live inputs deny eligibility. Same-route Guard/private changes immediately invalidate the generation, clear opt-in and dispose the banner, before any frame. Each asynchronous gate reads the current local state again. Native lifecycle changes also invalidate attempts. Returning Home or rapidly changing protection away and back requires a fresh tap; it cannot revive an earlier operation.

Each consent attempt captures its own generation. A consent form that finishes loading after invalidation is disposed without presentation. Late banner callbacks cannot display an old ad or remove a newer one. Privacy-options actions first dispose the banner, are generation-checked, and do not automatically reload advertisements. A canceled/failed SDK initialization does not poison a later eligible attempt.

Calls already in progress cannot be recalled. An already presented UMP native form has no dismissal API in this adapter. Once Android SDK initialization has started, the required publisher first-party-ID disable call finishes even if the initiating route disappeared; that setting cannot safely precede initialization in the installed SDK. This is privacy cleanup, and no canceled ad request follows it. SDK disposal is not a shutdown guarantee or proof that all provider background processing has ended.

No empty banner rectangle remains during loading, no-fill, failures or ineligibility. No interstitial, rewarded override, protection paywall or ad view requirement is present.

## Google provider limits

The request is non-personalized and carries no browser context. Google explains that this mode can still use storage/identifiers for capping and reporting; consent and technical-data disclosures remain necessary. [Ad serving modes](https://developers.google.com/admob/flutter/privacy/ad-serving-modes), [UMP](https://developers.google.com/admob/flutter/privacy).

The adapter sets the global maximum content rating to `G` before initializing, disables same-app/publisher first-party identity settings where supported, disables iOS SDK crash reporting, and disables mediation initialization. It does not infer age or child-directed status from a PIN, Guard selection or interests. No mediation adapter is added. Google's rating API is a content control, not proof of individual Guard compatibility. [Request configuration](https://developers.google.com/admob/flutter/targeting).

Google states that automated sensitive-category blocking cannot guarantee every related ad is removed and has language/category limits. Consequently, provider category controls do not establish compatibility with stricter choices: this build withholds that inventory. Account-level prohibited categories must be reviewed consistently before any live integration; no category configuration is fabricated for Google's sample account. [Sensitive category blocking](https://support.google.com/admob/answer/3150176?hl=en).

Mediated bidding has additional filtering switches and source-specific support. Turning off those controls can also disable category blocks and maximum ratings. Do not add a source based on an assumption that another provider's settings automatically cover it. [Bidding-source controls](https://support.google.com/admob/answer/10931097?hl=en).

Do not inspect or modify a third-party creative with unsupported code. Do not exempt provider tracking because Wingman benefits commercially. The SDK's own data processing is disclosed separately; it is not made private by routing the ad through an owned screen. The current eligibility boundary grants no exception for browsing-derived profiling or sensitive-data collection.

## Future owned content and sponsorships

Before milestone 3C renders promotional text, previews, thumbnails or media, reviewed catalog metadata and a conservative local policy must establish eligibility. Unknown classification is not verified safe. Local interest choices must be explicit, editable/removable and independent of browsing history, with an explanation that the user selected the interest. Prefer a bounded common public catalog over topic-specific background requests or a backend profile.

Unsponsored ordering must remain separate from labeled commercial placement. A sponsored item requires a real agreement, sponsor disclosure and reviewed compatible content; all destination clicks use normal Guard/navigation handling. No silent redirects or monetization of a block/support moment. Help Now, support resources, sensitive settings and private browsing stay ad-free even if a future inventory source claims compatible content.

The existing `SponsorshipCatalog` returns no items. Its placeholder model is not yet a complete content-review/Guard-eligibility system; do not populate it merely because it validates an HTTP(S) URL.

## Evidence and remaining gates

`test/ad_policy_test.dart` covers surface/private/build/consent and provider/suitability/protection matrices. `test/ad_consent_test.dart` covers failure, required-form cancellation and privacy-options state. `test/home_ad_slot_test.dart` uses delayed fake consent/provider operations to test denial before contact, background/route changes, same-route private/Guard transitions and returns before a frame, live checks before notifications, listener replacement, loaded/late banner disposal and no automatic revival. `test/ad_provider_test.dart` exercises the installed SDK wire adapter with mocked native channels, including cancellation between configuration calls and Android privacy cleanup. These are local tests, not a claim of fresh native provider traffic capture.

The existing [native demo instructions](MONETIZATION.md) use actual Google/UMP services, without forced consent/geography or ad clicks. Any Phase 3 native rerun must be identified separately from historical Phase 1 evidence. Production stays closed until actual account/messages, persistent privacy-choice access, regional/age handling, provider traffic/data review, compatible inventory, disclosures and store/distribution approval are verified. See [privacy disclosures](PRIVACY.md) and [release checklist](RELEASE_CHECKLIST.md).
