# Wingman validation record — 2026-09-10

This record separates actual browser execution, host tests, source audits and
unverified capabilities. A fixture pass does not establish compatibility with
every public website, permission provider, device or store policy.

## Repository and environment

| Item | Recorded value |
| --- | --- |
| Repository | `/Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser` |
| Baseline | Newly created repository; branch `main`; commit `8c748adf1ecb271132bdba4ad25263e1a9e172d9` (`chore: establish Flutter 3.44 Wingman baseline`) |
| Implementation revision | Branch `main`; commit `bb25bd4c2b39a4b39dd602f49f7d78291b0bde20` contains implementation and test sources |
| Handoff revision | Implementation and evidence use separate local commits; inspect `git rev-parse HEAD` and `git status --short` for the final checkout and working-tree state |
| Flutter / Dart | Flutter 3.44.4 stable / Dart 3.12.2 |
| Apple toolchain | Xcode 26.3; iPhone 17 Pro simulator `C157677F-A33F-45B2-BFFB-F3DED552D4F4` |
| Android toolchain | JDK 21; Java/Kotlin bytecode target 17; installed Android 36.1 image |
| Dedicated Android emulator | `Wingman_API_36`, Google APIs/Play Store ARM64, 2 GB RAM; observed target `emulator-5556` |
| Web browser | Google Chrome 152, inspected using native UI automation and DevTools |
| Local web preview | Built production Home on `http://127.0.0.1:8787`; documented Flutter development command uses port 7357 |

Different web ports have different IndexedDB stores. No store submission,
production deployment, Git push or approval of a default-browser entitlement is
implied by these local results. Physical-device validation is still outstanding.

## Completed runs and current status

The parent workspace's local log directory is
`/Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/work`.
It is outside the repository and contains the native/full-suite evidence named
below. Repository `work/` holds the separate web/data artifacts. These logs are
development evidence; they are not shipped application logging.

| Check | Actual recorded result | Evidence / limit |
| --- | --- | --- |
| Full host unit/widget suite | **97 passed** in the final completed host run | Parent `work/unit-tests-handoff.log`, `00:05 +97: All tests passed!`. |
| Focused domain/data/state suite | **68 passed** after the additional persistence regression | Repository `work/domain-followup-tests.log`; real SQLite FFI tests, state and parser tests. |
| Final `flutter analyze` | **Passed, no issues found** | Parent `work/analyze-handoff.log`; full-repository analysis completed in 7.5 s. |
| Android real-engine expanded fixture | **1 passed** | Parent `work/android-integration-error-retry.log`, `00:19 +1: All tests passed!`; includes SPA refresh, iframe containment, HTTP error handling and connection-refused failed URL/retry preservation. This supersedes the earlier HTTP assertion failure. |
| Android renderer regression | **Passed: renderer terminated, failure contained and page reloaded** | Parent `work/android-integration-error-retry.log`, `STAGE renderer recovery passed`; actual native renderer termination, with the recovered page title verified. |
| iOS real-engine expanded fixture | **1 passed** | Parent `work/ios-integration-handoff.log`, `00:30 +1: All tests passed!`; native WKWebView and actual sqflite plugin, including SPA refresh, iframe containment and connection-refused failed URL/retry preservation. |
| iOS Google test-ad smoke | **1 passed; actual banner rendered** | Parent `work/ads-ios-final.log`, `00:21 +1: All tests passed!`; actual UMP readiness and Google-approved test inventory, with pending-request cancellation verified. |
| Main iOS simulator build | **Passed** | Parent `work/main-ios-build-handoff.log`: `Built build/ios/iphonesimulator/Runner.app`; final build completed in 20.3 s. |
| Latest iOS main-app manual acceptance | **Observed navigation, media, upload, dialogs, tabs, private-record exclusion, history clearing and lifecycle flows passed** | Actual simulator UI interactions and local server/SQLite/disk checks, detailed below. Download/Cancel preserved the original page without an error overlay; expired TLS URL and retry behavior also passed retest. |
| Main Android debug compilation | **Passed** | Parent `work/android-main-final-handoff.log`: `Built build/app/outputs/flutter-apk/app-debug.apk`; final main-app build completed in 22.0 s and was installed. This is a debug APK, not a production-signed release. |
| Latest Android main-app manual acceptance | **Observed cold/warm links, public navigation/search, tabs/eviction, playback, upload and download passed** | Emulator UI, local receiver and disk checks detailed below; the actual default-browser role prompt was canceled without changing the default. |
| Flutter web release | **Passed** | Parent `work/web-build-handoff.log`; `flutter build web --release --no-web-resources-cdn` completed in 47.1 s, with successful icon tree-shaking and WASM compatibility dry run. |
| Web SQLite/IndexedDB | **Passed in actual Chrome** | Dedicated browser probe verified real database close/reopen and full page reload. See [web validation](WEB_VALIDATION.md). |
| Web Home resource audit | **15 completed HTTP 200 requests, all to the app origin** | [Compact capture](WEB_RESOURCE_AUDIT.json); no off-origin request in this observed Home load. Conditional Unicode fallback remains documented. |
| Recorded web reload and interaction smoke | **Passed in actual Chrome** | The preceding production build reloaded at 20:15 UTC; Home rendered, Dark/Brave settings persisted, and the Go button opened loaded Brave results for `wingman` in a new Chrome tab. No page errors or additional app-tab request origins. This capture predates the final 47.1 s build. See [web validation](WEB_VALIDATION.md). |
| Distribution signing / stores | **Not validated or submitted** | Local simulator/debug compilation does not establish production signing, Apple entitlement approval, AdMob production configuration or store acceptance. |

The iOS integration run exposed a genuine SQLite startup defect: sqflite's native
driver requires the row-returning `PRAGMA secure_delete = ON` to use `rawQuery`,
not `execute`. The repository now checks the returned enabled value. The passing
iOS fixture is after that fix. Its injected in-memory native SQLite database
verifies plugin behavior; host disk-reopen tests separately verify durable file
persistence. The main iOS app also restored normal metadata and onboarding after
termination and reinstallation over the existing app. These checks do not
establish every OS backup policy or uninstall/restore behavior.

## Scenario matrix

**Fixture** means a real OS WebView driven by the integration test against a
loopback HTTP server with synthetic pages. **Manual** means observed UI actions
in the running product. **Host** means Flutter unit/widget tests outside a mobile
engine. Android and iOS fixture passes below refer to the expanded acceptance
runs recorded above; public-site manual acceptance is recorded separately.

| Scenario | Completed evidence | Remaining limit or retest |
| --- | --- | --- |
| First-run message and Home | Host onboarding test; manual Chrome first launch and Home | Native full onboarding/manual acceptance should be recorded separately. |
| URL versus search | Host URL/parser suite, including explicit schemes, credentials, IPv4/IPv6, query encoding and selected providers | Does not establish every internationalized hostname or website behavior. |
| Public search provider | Manual Chrome Brave Search, normal iOS DuckDuckGo search and Android Google pages/search loaded actual results. [Android search](screenshots/android-google-search.png). | Other native provider/device combinations remain unverified. |
| Public `openai.com` on iOS | **Manual retest passed:** Research link, Back and Forward showed the correct URL/title and enabled control states. [Forward capture](screenshots/ios-openai-forward.png). | Supersedes the earlier stale title/Forward observation for this tested public-site flow; broader SPA compatibility is not established. |
| Normal page links, Back, Forward, Reload | Android and iOS real-engine fixtures passed, including SPA URL/title and Back/Forward refresh. Public OpenAI Research/Back/Forward passed manually on both platforms. [Android Forward](screenshots/android-openai-forward.png). | Broader website behavior retains the scope of its recorded fixture/manual checks. |
| `target=_blank` | Android fixture used a native pointer gesture; iOS automated fixture used DOM `.click()`. A separate actual iOS OS tap on the loopback fixture opened `/popup` in the current tab. | Synthetic Flutter pointer delivery into UIKit was unreliable, so automated iOS activation remains explicitly DOM-based. Public-site popup patterns need broader acceptance. |
| Page title, URL, progress, errors | Expanded Android/iOS fixtures passed title/URL/progress, HTTP 503, iframe containment and connection-refused failed URL/retry assertions. Download error overlay and iOS failed TLS URL/retry passed manual retest. The warning icon and “Page unavailable · host” caption were verified on both final native apps. | Earlier behavior failures are superseded by the passing retests. Broader failure/website combinations remain unverified. |
| Multiple tabs and closing repeatedly | Fixture cycled 12 tabs and checked at most three live engines; host model cycled 200 creations/closures. Manual iOS new-tab/switching passed. Android had six normal tabs with three native WebViews; returning to an evicted Wikipedia page reloaded successfully. | Point memory measurements are recorded below; no sustained memory profile or long-session soak is claimed. |
| History and bookmarks | Real-engine fixture stored both in native SQLite; host tests cover retention, deletion, settings and disk reopen. Manual iOS normal history was visible; Wikipedia bookmark saved, menu changed to “Remove bookmark”, and entry appeared in the bookmark list. | Broader public-site library flows remain unverified. |
| Normal metadata restoration | Manual iOS app termination and reinstallation over the existing app restored normal tab metadata and onboarding state; the expired-TLS destination remained blocked. | This preserves the existing app-data container; uninstall/data-loss and OS backup/restore are different, unverified scenarios. |
| Private history and tab exclusion | Host state and SQL-boundary tests; Android/iOS fixture verifies no private records. Manual iOS browsed `/private-ui-check`, closed the private tab, and SQL found zero matching history/tab records. | Private state is not a VPN or anonymity guarantee. |
| Private cookies/site storage | Android/iOS real-engine fixture verifies normal data absent privately, fresh private session empty after close, and normal data preserved | Crash/power-loss cleanup and full OS forensic deletion are not established by this test. |
| Clear history, cookies and local storage | Android/iOS fixture clears engines/data, reloads normal page and verifies cookies/localStorage/history empty; host durable-deletion tests. Manual iOS UI history clear was followed by SQL history count `0`. | The manual SQL check establishes history deletion; individual OS storage categories, service-worker edge cases and interrupted clear flows need further device acceptance. |
| Pending ad request when leaving Home | Actual iOS GMA/UMP smoke unmounted Home during a pending operation and verified no later ad/UI callback | Sentinel surface is a test harness, not an arbitrary third-party website. Source/policy checks cover advertising placement boundaries. |
| Actual test banner | iOS smoke reported `actualBannerRendered: true`, `outcome: bannerLoaded` and `canRequestAds: true` | No ad creative was clicked. Android ad rendering and alternate consent/geography paths remain separately unverified. |
| Wingman ads absent from external page content | Host ad-policy/privacy tests and source audit; no page-ad injection bridge is implemented | Does not replace production SDK/store-policy review or broad live browsing QA. |
| Web preferences and bookmarks persistence | Manual Chrome retained Dark/Brave/onboarding after reload; dedicated SQLite probe retained bookmark, history and normal tab and excluded private state | Browser eviction/clearing may remove IndexedDB. The upstream web SQLite adapter is experimental. |
| Web external navigation | Manual selected-provider search opened top-level Chrome tab; source has no arbitrary website iframe renderer | Host-browser extensions/network behavior is outside Wingman's control. |
| Layout and large text | Host widget tests at 320×640, 390×844, 844×390 and 1024×768 in light/dark, text scale 1.6; small-screen settings/private switcher tests. Manual iOS simulator video fullscreen, landscape rotation and exit passed. | Simulator rotation does not establish physical-device rotation behavior. Screen-reader acceptance and other rotation flows remain unverified. |
| Renderer crash and recovery | Expanded Android fixture terminated the actual renderer, observed the error state, reloaded and verified the recovered page title | iOS renderer termination and broader process/memory-pressure recovery remain unverified. |
| Login / form submission | Manual iOS and Android GitHub login pages/forms rendered; fixture also contains a form | No credentials were entered or submitted. Successful login, authenticated session and credential flow acceptance remain unverified. |
| File upload | iOS Photos picker uploaded a generated logo to loopback `/upload`; receiver confirmed/discarded 47,188 request-body bytes. Android system file picker uploaded the test logo; local receiver confirmed 47,190 bytes. [Android picker](screenshots/android-file-picker.png), [result](screenshots/android-upload-result.png). | Other file providers, multiple selection, camera capture and authenticated/public-service uploads remain unverified. No private user photo was used. |
| Downloads | iOS confirmed a 68-byte `wingman-test.txt`, verified on disk, and showed the completion toast. Retested Download and Cancel both preserved the original fixture URL/page and Reload without an error overlay. Android DownloadManager saved the 68-byte test binary with the main page preserved. | Authenticated downloads, detailed progress and background completion remain unverified. The earlier iOS overlay defect is superseded by the passing retest. |
| JavaScript dialogs | Manual iOS origin-labeled JavaScript alert appeared and Continue dismissed it successfully | Confirm/prompt variants and other origin/iframe cases remain unverified. |
| Camera / microphone / location | In-context permission paths reviewed; no automatic grants configured | Grant/deny/revocation and iframe/OS permission scenarios remain unverified on devices. |
| Video / fullscreen media / YouTube | Manual iOS YouTube “Me at the zoo” (19 s) played; native fullscreen, landscape rotation and exit passed. Android YouTube playback also passed. [Android watch page](screenshots/android-youtube-watch.png). | Other public players, protected media and background media behavior remain unverified. |
| Connection failure / offline / DNS / invalid TLS | Manual iOS `expired.badssl.com` was blocked with the failed URL preserved; Retry re-blocked the same address. Final native error states show the warning icon and hostname: [iOS](screenshots/ios-tls-blocked.png), [Android](screenshots/android-tls-blocked.png). No certificate bypass. Both native fixtures passed connection-refused failed URL/retry and HTTP 503 assertions. | Offline and DNS-specific failures remain unverified. The earlier failed URL/retry defect is superseded by these retests. |
| Android incoming HTTP link / default-browser role | Cold Wikipedia HTTP intent preserved Home with two tabs; warm OpenAI intent opened a third. The actual role prompt listed Wingman as eligible and was canceled without changing the default. [Role prompt](screenshots/android-default-browser-prompt.png). | User-granted default-role operation remains unverified; showing eligibility is not a role grant. |
| iOS incoming HTTP link / default browser | WKWebView and delivered-link handling implemented | Managed entitlement and approved signing are external requirements; no default-browser eligibility is claimed. |
| Background / foreground / rotation | Manual iOS app backgrounded through system Home and resumed with Settings state preserved; native video fullscreen/landscape/exit passed. | Broader lifecycle transitions, memory pressure and interrupted operations remain unverified. |

The latest iOS manual checks used the actual main app on the simulator, with OS
taps rather than the automated fixture's DOM activation. The upload used a
generated test logo and a loopback receiver that discarded the request body.
The private and clear-history checks inspected the app's local SQLite database;
the download check inspected the resulting local file. Selected visual evidence:
[iOS Home](screenshots/ios-home.png) and
[OpenAI Research after Forward](screenshots/ios-openai-forward.png). Screenshots
capture visible states; the action sequences and storage checks provide the
additional evidence described in the matrix.

## Android memory observations

These are two `dumpsys meminfo` snapshots of the same debug-app process on the
Android emulator, not a benchmark or a controlled tab-count comparison.

| Snapshot | Native WebViews | Total PSS (KB) | Total RSS (KB) | Total swap PSS (KB) | Evidence |
| --- | --- | --- | --- | --- | --- |
| Earlier idle observation | 1 | 320,446 | 426,920 | 15,049 | Parent `work/android-idle-memory.txt` |
| Later multitab observation | 3 | 315,170 | 330,176 | 90,805 | Parent `work/android-multitab-memory.txt` |

The emulator was under different swap pressure between observations. The lower
later PSS does not show that adding tabs reduces memory or establish a per-tab
cost. The useful bounded observation is that six normal tabs coexisted with
three native WebViews and an evicted Wikipedia page reloaded when selected.
Release-build, physical-device, isolated renderer-process and sustained-session
memory profiling remain unverified.

## Actual advertising smoke result

The iOS result was produced by actual SDK callbacks, not a mocked consent grant:

```json
{
  "platform": "iOS",
  "testInventoryOnly": true,
  "actualBannerRendered": true,
  "outcome": "bannerLoaded",
  "pendingAtUnmount": true,
  "noAdAfterUnmount": true,
  "cancellationStages": ["consentStarted", "disposed"],
  "requestStages": ["consentStarted", "sdkInitializing", "bannerRequested", "bannerLoaded"]
}
```

The test did not force a geography, reset consent, use production ad inventory or
click an advertisement. UMP readiness in this environment does not establish
every required jurisdiction/consent path or final store disclosure.

## Privacy findings and practical boundaries

Source and host tests confirm that Wingman has no custom browsing-history/page
upload backend, analytics/attribution/crash SDK, page-ad injection mechanism or
privileged JavaScript bridge exposed to arbitrary websites. Private metadata and
history are rejected at state and SQLite boundaries. Private bookmarking is
disabled. Normal data uses separate local history/bookmark/tab/settings tables.
History is bounded to 90 days and 5,000 unique URLs. These are implementation and
test findings, not a claim that websites, operating systems or SDKs collect no
technical data.

The web Home resource audit verified local CanvasKit and interface fonts. Other
Unicode scripts/emoji may trigger Flutter's documented Google-hosted font fallback.
Chrome's remaining `Intl.v8BreakIterator` deprecation comes from the stable Flutter
engine; it was not suppressed. No page errors occurred in the final audited Home
load. After enabling Flutter semantics and using settings/search, DevTools also
reported generated form-field id/name advisories and verbose timing diagnostics;
its console error/warning categories and page-error count remained empty.
See [web details](WEB_VALIDATION.md), [privacy](PRIVACY.md),
[native limitations](NATIVE_BROWSER.md) and [release checklist](RELEASE_CHECKLIST.md).

## Commands to repeat the checks

From the repository, with the relevant emulator/simulator running:

```sh
flutter analyze
flutter test
flutter test integration_test/browser_engine_test.dart -d emulator-5556
flutter test integration_test/browser_engine_test.dart -d C157677F-A33F-45B2-BFFB-F3DED552D4F4
flutter test integration_test/ads_smoke_test.dart -d C157677F-A33F-45B2-BFFB-F3DED552D4F4 --dart-define=WINGMAN_TEST_ADS=true
flutter build web --release --no-web-resources-cdn
flutter build apk --debug
flutter build ios --simulator --debug
```

The browser-only storage probe has separate commands in [WEB_VALIDATION.md](WEB_VALIDATION.md).
The test-ad command may encounter a real UMP/user decision; do not substitute a
mocked grant, force consent, or automate ad-creative clicks to obtain a pass.

## Handoff

Implementation and validation evidence use separate local commits. Inspect
`git rev-parse HEAD` and `git status --short` for the checkout revision and
working-tree state without embedding a self-referencing documentation commit
hash. The local manual fixture server on
port 8810 was stopped after testing. The web preview on port 8787 remains active,
and both native main apps were left on Home.
