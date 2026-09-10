# Wingman Browser

**We've got your back, not your data.**

A Flutter browser foundation using Android System WebView and iOS WKWebView, with a web Home/search companion. Normal history, bookmarks, preferences and tab metadata use local SQLite. Wingman has no browsing backend, account requirement, analytics upload or cloud sync.

Your browsing history is yours. Wingman doesn't sell your browsing history, build an advertising profile from the sites you visit, or inject Wingman ads into the websites you browse.

This is a development foundation, not a claim of completed store approval or production distribution readiness. Consult the [validation report](docs/VALIDATION.md) for what was actually run and the [release checklist](docs/RELEASE_CHECKLIST.md) for remaining work.

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

On normal Home, tap **Load test advertisement**. Only Google-approved test inventory can load, after the UMP consent check. The flag alone does not start requests. No ad request receives browsing history, URLs, searches or page contents. Automated tests never click advertisements.

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

For mobile integration tests, start a target then run `flutter test integration_test -d <device-id>`. Compile results, host tests and actual browser scenarios are distinct evidence in the validation report.

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
- [Privacy and SDK disclosures](docs/PRIVACY.md)
- [Privacy/security source review](docs/PRIVACY_AUDIT.md)
- [Monetization configuration](docs/MONETIZATION.md)
- [Dependency decisions](docs/DEPENDENCIES.md)
- [Native capabilities and limitations](docs/NATIVE_BROWSER.md)
- [External actions and release checklist](docs/RELEASE_CHECKLIST.md)

The Wingman name, app identifiers, icon and wordmark are development placeholders, not proof of trademark or domain ownership. Final brand clearance, privacy/terms publication, store configuration, live ad/partnership setup, signing and device acceptance remain the operator's release work.
