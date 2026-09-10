# Release checklist and external actions

This is an engineering handoff, not evidence of store approval. Local builds cannot enroll the operator, approve entitlements, configure real advertising or secure distribution signing. The validation report records completed checks.

## Phase 3A claims and acceptance gate

Use [Phase 3 status](PHASE_3_STATUS.md) for observed results and [platform matrix](PLATFORM_CAPABILITY_MATRIX.md) for unsupported authentication and physical-device gaps. The following must be checked on the final code:

- Database v1→v2 preserves history, bookmarks, normal sessions and settings; reading-list mutations and confirmed bookmark imports report durable failures. Validate malformed/oversized imports, duplicate/cap handling, inert preview, cancellation and explicit export.
- Reader extracts bounded visible article text only after a user action; omit forms, hidden/access-restricted content and remote resources. Check changed/closed/private tabs and page-size behavior on actual native engines.
- Android capture protection is present before the first app frame. iOS inactive scene previews are shielded; do not claim foreground screenshots are prevented on iOS. Repeat private-cookie/storage/cleanup/restoration tests and separately record authentication-state limits.
- Delayed native Guard events cannot replace a newer navigation. Data-clear timeouts cannot report success or race new website storage writes.
- Owned ads fail closed for unknown/strict requirements and revalidate route/lifecycle changes across asynchronous consent/SDK work. Release ads remain disabled.
- Record runtime network-observation scope separately for owned services, websites, native security and optional providers. Source inspection alone is insufficient.
- Compare identified-device/mode performance against the fresh baseline; investigate regressions and preserve the distinction between synthetic debug fixtures and physical-device release behavior.

Milestones 3B–3F remain Deferred. No extension package, encrypted sync, Help Now, chosen-interest experience, remote assistance, publishing workflow or deployed backend is implied by 3A. A later release cannot enable unreviewed decryption, hidden tracking or production inventory through a remote flag. Known critical privacy defects remain release blockers.

## Guard release gates

Phase 2 supplies a limited local starter pack and browser-level controls. Before production distribution:

- Replace development signing trust with a managed production key and reviewed key-rotation procedure.
- License, validate and maintain broader category/tracker coverage; retain clear support/education exceptions and false-positive procedures.
- Configure a reviewed global update endpoint with budgets and operational ownership. No Google Web Risk feed, production update service or report inbox is active now.
- Complete release-mode startup, memory and navigation acceptance on older supported physical phones. Debug simulator/emulator timings are not production smoothness evidence.
- Preserve the browser-only scope disclosures for Web and Family controls; review Family PIN recovery expectations, SafeSearch gaps and native-provider disclosures.

## Identity and ownership

- Clear the Wingman brand for intended markets; replace the temporary icon/wordmark as needed. Local implementation establishes no trademark or domain ownership.
- Select final application/bundle IDs controlled by the operator. Update native configuration, SDK app records, store records and incoming-link tests together.
- Enroll in the required Apple/Google developer programs and configure authorized operator access, agreements, certificates and support contacts.
- Publish accurate privacy policy and terms with operator identity, contact details, rights handling and actual provider retention. Repository engineering notes are not final legal documents.

## Android distribution

- Replace current debug signing in the release build type with secured production/upload signing; keep private keys and passwords out of Git. Configure Play App Signing as appropriate.
- Inspect the final merged manifest, target/min SDK, permissions, backup behavior and ad-ID removal. Match each sensitive permission to its user-initiated feature.
- Test accepting and declining the browser-role request and incoming HTTP/HTTPS links during cold and warm launches. The browser remains usable without the role. [Android role API](https://developer.android.com/reference/android/app/role/RoleManager#ROLE_BROWSER)
- Exercise private profiles on supported/unsupported WebView providers, close/eviction, forced termination and next-launch cleanup. Unsupported isolation must refuse private browsing.
- Complete Google Play Data Safety and advertising declarations from the final SDKs and actual behavior, not solely from the lack of a Wingman backend.

## iOS entitlement and signing

- Configure an authorized Apple Developer team, final registered app ID, certificates and provisioning profiles. Existing development-team settings do not prove distribution authorization.
- Request the managed `com.apple.developer.web-browser` entitlement through [Apple's form](https://developer.apple.com/contact/request/default-browser-entitlement/). After approval, add it to the entitlement/signing configuration, regenerate provisioning and verify the signed archive contains it.
- Configure the required HTTP/HTTPS Info.plist registration, then verify default-browser selection and incoming links on a physical device. Preserve WKWebView and direct navigation; do not claim arbitrary Universal Links domains. Review Apple's functional requirements and prohibited permission keys. No entitlement is fabricated in the current app. [Apple browser requirements](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser), [entitlement reference](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser)
- Inspect the archive's privacy report, SDK manifests and required-reason APIs. Complete nutrition labels using actual partner behavior and reassess any tracking implications; the foundation does not request ATT or build cross-site profiles. [Apple privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- Verify the structured SQLite directory remains backup-excluded and outside Files-visible Documents. Inspect OS-managed normal website data and downloads separately before making broader backup claims.
- Test nonpersistent private stores, repeat creation/eviction/clearing/restart, and exercise uploads, permissions, media and downloads on physical hardware.

## Ads and commercial configuration

- Release ad requests currently fail closed. A reviewed production implementation needs a real AdMob account, app records, central unit IDs, native app-ID configuration and applicable app-ads.txt/ownership setup.
- Configure and test consent messaging, regional and age handling, and always-available required privacy choices. Denial, failure, withdrawal and no-fill must leave browsing usable.
- Audit actual SDK technical processing and identifiers with the exact Android/iOS versions. Non-personalized ads do not mean no collection. Follow [monetization notes](MONETIZATION.md) and [privacy documentation](PRIVACY.md).
- Keep test and live inventory separate; never automate live-ad clicks. Verify ad spacing, small screens, rotation, backgrounding and removal when leaving Home.
- Add sponsorships, affiliates and search referral parameters only for actual agreements with explicit disclosures and user-initiated destinations. Do not derive commercial targeting from hidden browser histories.

## Device acceptance and privacy audit

For each supported mobile target, test `openai.com`, followed links, back/forward, stop/reload, Home, tabs, bookmarks, history, provider selection and restoration. Confirm private visits never persist and normal/private site data remains separate. Repeatedly cross the three-engine limit and clear data after both browsing and a cold start.

Exercise offline/DNS/HTTP/SSL errors without accepting invalid certificates, file upload/download, permission refusal, external schemes and new-window links. Test large text, accessibility, themes, rotation and multiple screen sizes. Document unsupported or unverified secondary features.

Run analyze, automated tests, mobile integration tests and web/Android/iOS builds for the intended configuration. Distinguish compilation, simulator behavior, physical devices and store approval in the report. None implies the others.

Audit code and network behavior for history/page exports, URL/search telemetry, behavioral profiles, injected/replaced ads, unnecessary SDKs, private persistence, sensitive logging and privileged website bridges. Check ordinary cold start separately from optional test-ad opt-in. Do not commit raw diagnostic captures containing session secrets.

Completing this checklist does not authorize pushing, cloud deployment, merging externally or publishing a store release. Those actions require the user's explicit request; no production publishing automation is included.
