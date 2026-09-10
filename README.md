# Wingman Browser

**We've got your back, not your data.**

A Flutter browser using Android System WebView and iOS WKWebView, with a web Home/search companion. Wingman Guard adds optional local content boundaries, timed Focus, balanced tracker blocking and local Family settings. Normal history, bookmarks, preferences and tab metadata use local SQLite. Wingman has no browsing backend, account requirement, analytics upload or cloud sync.

**More of what matters to you. Less of what gets in your way.** Phase 3's first delivery is **3A**: everyday browsing and privacy verification, bookmark file import/export, a local reading list, website text/page size, and gated local Reader. Follow [Phase 3 status and evidence](docs/PHASE_3_STATUS.md); milestones 3B–3F remain Deferred.

Your browsing history is yours. Wingman doesn't sell your browsing history, build an advertising profile from the sites you visit, or inject Wingman ads into the websites you browse.

This is a development foundation, not a claim of completed store approval or production distribution readiness. Consult the [current Phase 3 report](docs/PHASE_3_STATUS.md), [historical validation report](docs/VALIDATION.md) and [release checklist](docs/RELEASE_CHECKLIST.md) for evidence and remaining work.

## Start here

Run commands from the repository:

```sh
cd /Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser
flutter pub get
flutter devices
```

The inspected machine has Flutter **3.44.4 stable**, Dart **3.12.2**, Xcode **26.3**, JDK **21**, and an Android **36.1** development target. Project Java/Kotlin bytecode targets Java 17. Android Studio manages SDKs, emulators and Logcat; Xcode manages simulators, signing and native iOS debugging. VS Code is optional. No broad tooling upgrade is required.

## Chrome preview

```sh
flutter run -d chrome --web-port 7357
```

The web target is Wingman's start/search/bookmark companion. It opens destinations in the host browser and does not embed arbitrary websites in iframes. Use a stable port to retain the same IndexedDB origin. `flutter build web` creates a local production bundle without publishing it.

## Android preview

Launch the dedicated Wingman emulator created for this project, wait for it to boot, then run:

```sh
flutter emulators --launch Wingman_API_36
flutter devices
flutter run -d emulator-5556
```

`Wingman_API_36` uses the installed Android 36.1 Google APIs/Play Store ARM64 image. Its observed device ID for this validation run was `emulator-5556`; use the actual ID from `flutter devices` if another emulator is already running or the assigned port changes. Android Studio → Device Manager provides the same controls. For a physical device, enable USB debugging, connect and authorize this computer, then run `flutter run -d <device-id>`.

Ordinary browsing supports Android API 24 and above. Private browsing additionally requires a System WebView provider with multiple-profile and browsing-data-deletion support. Update the provider if Wingman reports private browsing unavailable. There is no fallback to shared normal-tab storage.

## iPhone Simulator preview

The inspected machine's iPhone 17 Pro simulator ID is used below:

```sh
open -a Simulator
xcrun simctl boot C157677F-A33F-45B2-BFFB-F3DED552D4F4
flutter run -d C157677F-A33F-45B2-BFFB-F3DED552D4F4
```

Skip `simctl boot` if already booted. List alternatives with `xcrun simctl list devices available`. This project targets iOS 15 and above. Simulator development does not require distribution signing.

For native debugging, run `open ios/Runner.xcworkspace`, choose Runner and a simulator, then Run. For Flutter hot reload, leave `flutter run` attached and press `r`; press `R` for hot restart and `q` to stop. Xcode's Run alone does not provide Flutter CLI hot reload.

For a physical iPhone, enable Developer Mode, trust this Mac, and select an authorized signing team, unique bundle identifier and device in Xcode. Run `flutter run -d <device-id>` after signing is configured. Local development-team settings do not prove that the final product has approved provisioning or the browser entitlement.

## Implemented foundation

### Everyday browsing (Phase 3A)

- **Bookmarks → Import file** accepts a Netscape HTML export you choose. Preview the new, duplicate and rejected counts before confirming a merge. It does not open addresses, execute HTML or inspect other browsers' databases. Limits: 2 MiB per file and 5,000 bookmarks. **Export bookmarks** discloses full addresses before opening a save/share destination; external files/share caches may remain.
- **Save to reading list** keeps the current normal page's title/address locally. **Reading list → Add address** also saves an explicit web address without visiting it. Mark items read/unread or remove them. The 500-item list is metadata, not offline page downloads. Private pages cannot be saved. The v1→v2 SQLite migration preserves existing records and settings.
- **Settings → Website size** adjusts Android text or iOS page zoom. **Open reader** on iOS extracts bounded visible article text locally into a transient attributed text view with size controls. Forms, hidden content, recognized access overlays and active HTML are excluded. Android Reader is disabled pending a verified isolated-script implementation; the Web companion cannot extract external pages.
- Android capture protection covers the app window from startup, restricting screenshots and screen sharing. iOS shields inactive app previews; active-use screenshots remain possible. [Platform capability and authentication limits](docs/PLATFORM_CAPABILITY_MATRIX.md)
- Pending ads and Reader requests are invalidated when their context changes. Guard-block events carry navigation identity, and pending site-data deletion cannot falsely report clearing a different selection. [Privacy boundaries](docs/PRIVACY_ARCHITECTURE.md), [monetization policy](docs/MONETIZATION_POLICY.md)

Current category filtering is **experimental**, with a small development starter. [Coverage and limitations](docs/GUARD_COVERAGE_AND_LIMITATIONS.md). Help Now, commitments, chosen interests, optional encrypted sync, extension beta and cloud assistance are not delivered in 3A. [Sync security gate](docs/SYNC_SECURITY_DESIGN.md)

### Wingman Guard (Phase 2)

Open **Wingman Guard** from Home or Settings. Turn on Guard and choose categories; none are preselected. Standard browsing keeps native security enabled. Focus adds temporary category/site boundaries. Private tabs follow the same Guard policy, while their activity stays out of saved history and statistics.

- Local indexed classification and a signed, versioned starter pack; SHA-256 and Ed25519 verification precede activation. Previous verified data supports rollback. There is no per-navigation cloud lookup.
- Native main-frame navigation defenses, separate security warnings, safe-search policy for DuckDuckGo, Google, Bing and Brave, custom block/allow rules, and limited tab-scoped Allow Once grants.
- Balanced tracking protection uses seven selected third-party EasyPrivacy domain rules under CC BY-SA 3.0. Android reports local blocked-resource counts; iOS does not expose a reliable count.
- Optional 6–12 digit Family PIN uses a salted PBKDF2 verifier in native secure storage with persistent retry limits. It protects Wingman settings, not other apps or devices.
- False-positive/missed-block reports let the user choose no address, a domain, or a full URL before copying/sharing. No report inbox or automatic upload is configured.

The **49-rule category pack is a limited starter dataset**. Threat entries in that pack are synthetic test fixtures; real general threat protection comes from the native engine. Google Web Risk and production filter hosting are **not active**. No category classifier is foolproof. See [provider coverage and licensing](docs/PHASE2_PROVIDERS.md), [Guard privacy architecture](docs/PRIVACY_ARCHITECTURE.md), and [Family PIN details](docs/GUARD_PIN.md).

Use `https://adult.guard.test`, `https://alcohol.guard.test` and `https://recreational-drugs.guard.test` to inspect the bundled category-block UI after enabling their matching categories. These reserved test domains do not host websites. Native integration tests also use a real loopback server to prove that blocked content never reaches the render step and that permitted content loads.

The Web companion saves configuration concepts and requests SafeSearch when launching supported searches. It cannot filter another browser's pages. The production update transport is deliberately unconfigured; verified bundled rules work offline. See [control-plane deployment prerequisites](docs/CLOUD_CONTROL_PLANE.md).

### Browser foundation

- Polished Home/New Tab, replaceable wordmark, light/dark/system themes, quick links, bookmarks and modular owned monetization space.
- Shared URL/search parsing and direct DuckDuckGo, Google, Bing and Brave Search providers.
- Mobile navigation, progress/security indicators, history/bookmarks, multiple and private tabs, local persistence, data clearing, share/copy, desktop-site mode and find-in-page.
- Three live browser engines for up to fifty tab records. Evicted tabs reload their last address; navigation stacks and unsaved forms are not restored after eviction/restart.
- Validated incoming links, constrained external schemes, explicit website permission handling, system file selection and supported downloads.
- Owned-placement ad policy, optional consent-gated Google test banners, and no-op analytics. No production ads or fabricated commercial revenue.

Secondary capability support depends on the OS engine. Android authenticated downloads may fail because session cookies are not copied into DownloadManager. Downloads explicitly saved from private tabs remain saved. Automatic script popups are blocked; user-activated new-window links use the current tab. Media, upload/download providers and site compatibility need physical-device acceptance. [Native implementation and limitations](docs/NATIVE_BROWSER.md).

## Privacy behavior

Normal history is retained locally for up to 90 days / 5,000 unique URLs. Private history and tab metadata never enter Wingman's database. iOS private views use a nonpersistent website store. Android uses isolated profiles that may temporarily write site data to disk; close/eviction clears them and next launch removes abandoned profiles. Private tabs have independent site sessions.

Android app backup is disabled. The iOS structured database is placed in a backup-excluded Application Support directory, separate from Files-visible downloads. This does not claim that every OS-managed normal website file, external download or previous backup is excluded or erased. Local data is not separately encrypted by Wingman. Private browsing is not a VPN.

Websites, search providers, operating systems and enabled ad services may process technical information. No separate analytics, attribution or crash-reporting platform is installed. Google Mobile Ads has its own documented SDK behavior. [Privacy architecture](docs/PRIVACY.md).

## Ads and search configuration

```sh
flutter run -d <android-or-ios-device-id> --dart-define=WINGMAN_TEST_ADS=true
```

On normal Home, with verified standard protection requirements, tap **Load test advertisement**. Unknown or stricter Guard requirements withhold this unverified provider before consent or SDK calls. Only Google-approved test inventory can load after the UMP consent check. The flag alone does not start requests. No ad request receives browsing history, URLs, searches or page contents. Automated tests never click advertisements.

Centralized `WINGMAN_ANDROID_BANNER_ID` / `WINGMAN_IOS_BANNER_ID` inputs are reserved for a reviewed production integration; supplying them cannot enable release ads. Native sample app IDs must also be replaced through reviewed configuration. [Ads, consent and sponsorship setup](docs/MONETIZATION.md).

Change the selected provider in Settings. Additional HTTPS endpoints, real partnership parameters and commercial disclosures belong in `SearchProvider` in `lib/domain/search.dart`. Searches go directly to the provider; Wingman has no search proxy or current commercial search agreement.

## Tests and local builds

```sh
flutter analyze
flutter test
flutter build web
flutter build apk --debug
flutter build ios --simulator --debug
flutter build ios --release --no-codesign
```

For mobile regression tests, start a target, then run each fixture separately:

```sh
flutter test integration_test/browser_engine_test.dart -d <device-id>
flutter test integration_test/guard_engine_test.dart -d <device-id>
flutter test integration_test/reader_privacy_test.dart -d <device-id>
```

The separate synthetic HTTPS authentication check uses public fixture values, not a real account or password vault:

```sh
flutter test integration_test/http_auth_privacy_test.dart -d <device-id>
```

Performance, test-ad and HTTPS authentication fixtures have separate setup and scopes described in [native validation](docs/phase3/NATIVE_VALIDATION.md) and [monetization notes](docs/MONETIZATION.md). Compile results, host tests and runtime scenarios are distinct evidence. The web build used for current runtime checks is `flutter build web --no-web-resources-cdn`.

After configuring signing, these commands create local release artifacts:

```sh
flutter build appbundle --release
flutter build ipa --release
```

**Android's release build currently uses the development debug signing key.** Replace it with secured production/upload signing before distribution. iOS archives require proper developer enrollment, certificates and provisioning. These local build commands do not push, deploy, submit to stores or publish a product.

## Default browser

Android declares HTTP/HTTPS VIEW/BROWSABLE intent filters and offers **Set Wingman as Default Browser** in Settings. Android 10+ uses the browser role request; earlier supported versions open default-app settings. The OS and user decide whether to grant it. [Android role API](https://developer.android.com/reference/android/app/role/RoleManager#ROLE_BROWSER)

iOS renders with WKWebView and handles delivered app links, but cannot claim default-browser eligibility before Apple's managed `com.apple.developer.web-browser` entitlement is approved. Request it through [Apple's form](https://developer.apple.com/contact/request/default-browser-entitlement/), then configure the approved app ID, entitlement/provisioning and required HTTP/HTTPS Info.plist registration. No entitlement or universal-link ownership is fabricated. [Apple requirements](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser)

## Repository and handoff

Created locally on branch `main`; initial baseline: `8c748adf1ecb271132bdba4ad25263e1a9e172d9`. No existing repository changes were overwritten. Run `git log -1 --oneline` for the current final revision; consult the validation report for the recorded handoff state.

- [Architecture](docs/ARCHITECTURE.md)
- [Current Phase 3 status](docs/PHASE_3_STATUS.md)
- [Privacy data flow and request inventory](docs/PRIVACY_ARCHITECTURE.md)
- [Protection providers and data licenses](docs/PHASE2_PROVIDERS.md)
- [Future device-wide protection and desktop extensions](docs/FUTURE_PROTECTION.md)
- [Privacy and SDK disclosures](docs/PRIVACY.md)
- [Privacy/security source review](docs/PRIVACY_AUDIT.md)
- [Monetization configuration](docs/MONETIZATION.md)
- [Dependency decisions](docs/DEPENDENCIES.md)
- [Native capabilities and limitations](docs/NATIVE_BROWSER.md)
- [External actions and release checklist](docs/RELEASE_CHECKLIST.md)

The Wingman name, app identifiers, icon and wordmark are development placeholders, not proof of trademark or domain ownership. Final brand clearance, privacy/terms publication, store configuration, live ad/partnership setup, signing and device acceptance remain the operator's release work.
