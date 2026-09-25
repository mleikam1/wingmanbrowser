# Native audit and desktop preparation

Audit date: 2026-09-25. Work branch: `feat/wingman-wow-ui`; initial checkout commit: `254c90717eb9e2837e5bbd1e757c02f3a7513d56`. The branch was created from the current repository checkout, not a historical rollback. This record distinguishes source inspection, new execution, and historical acceptance.

## Existing engines and boundaries

The production application is `lib/main.dart`, with `ProtectedWebController`/`ProtectedWebSurface` calling `wingman/protected-browser`. Android uses the custom System WebView adapter, AndroidX WebKit 1.17.0, native policy checks, platform TLS validation, first-party storage, feature-gated private profiles, and exposed resource/service-worker checks. iOS uses its custom WKWebView adapter with native navigation decisions, precompiled mandatory content rules, and `.default()`/`.nonPersistent()` website stores. Normal permitted consumer sites are supported independently of the reviewed content catalog. `BrowserEnginePool` and pilot-only integration fixtures are retired boundaries, not the active renderer.

Each live view belongs to a tab and normal/private scope. Requests carry an incrementing request ID; popup adoption has a short native lease tied to opener/document/profile/restrictions. Hidden surfaces pause media and the existing handoff boundary removes owner surfaces. Four native renderers are retained by the Flutter shell; eviction reopens an address rather than restoring native forms or history. No migration in this work changes identifiers, signing, policy data, production configuration, or existing installs.

`docs/CONSUMER_BROWSER_RECOVERY.md`, `BROWSER_ENGINE_CONTRACT.md`, `PROTECTION_COVERAGE.md`, and the actual source describe the current consumer architecture. `PLATFORM_CAPABILITIES.md` and `PLATFORM_CAPABILITY_MATRIX.md` include explicitly historical bundled-reader/Phase3 material; their retired “live engine disabled” statements are not the current implementation. Several existing `integration_test/protected_live_*`/`strict_search_native_test.dart` assertions still depend on pilot behavior and require deliberate migration before use as consumer acceptance.

## Detected local environment

| Component | Inspected value |
| --- | --- |
| Machine | macOS 15.7.4, arm64 |
| Flutter / Dart | 3.44.4 stable `ad70ec4617`; Dart 3.12.2 |
| Xcode | 26.3 / 17C529, `/Applications/Xcode.app/Contents/Developer` |
| Java / Gradle command | Temurin 17.0.18; Gradle 9.1.0 launcher/daemon uses that JDK (`evidence/android-gradle-environment.log`) |
| Existing project targets | Android, iOS, web; no macOS, Windows, or Linux directory at audit |
| New Android QA device | `Wingman_Redesign_QA_20260925`, emulator-5560; API36.1 image, Android16, Pixel7 profile, 2GiB/2cores |
| New Android QA engine | System WebView `134.0.6998.135`, queried from device |
| Android QA data | Task-local `work/android-avd/`; no personal app install, existing AVD, or default-browser setting changed |
| New Apple QA device | Dedicated `Wingman Redesign QA`, iPhone17, iOS26.3; created for this task and isolated from existing simulators |

A physical iPhone was detected by Flutter. It was not installed to, opened, modified, or used for acceptance. Existing emulators were identified read-only and left intact. No SDK or system image was globally upgraded.

## Counter correction and exact meaning

Android's prior `blockedResources` counter increased during policy evaluation, used unsynchronized snapshot reads, and survived renderer teardown. The new `ObservedRequestCounters` is synchronized and carries a renderer generation token. It records a denied request only on the native `shouldInterceptRequest` branch that actually returns a synthetic denial response for a policy rejection. Returning a permitted request to Chromium is an observed attempt, not a successful load. No request URL, title, header, or body is stored by this counter.

Scope is **one native renderer lifetime**, including its navigations/reloads. A new renderer begins at zero; close, eviction, and renderer replacement invalidate old callbacks and erase counts. Instances are per view, so normal/private counters cannot aggregate into each other. No values persist to disk. A count is not a unique tracker count, user score, full-network request count, or proof of no traffic. Main-frame pre-navigation, TLS, download, and service-worker denials are excluded. There is one observation point: replayed `pageState` snapshots do not increment it. Distinct intercepted attempts to the same URL count separately; URL-based deduplication would incorrectly hide real retries.

Counters cap at 100,000, with `resourceCounterSaturated` true if an observed dimension exceeded the cap. Capability fields are `resourceCountersObservable: true` and `resourceCounterScope: rendererLifetime`. A page state without a renderer reports null counts. WKWebView declares `resourceCountersObservable: false`, `resourceCounterScope: unobservable`, and null counts because installed content rules do not provide these enforcement callbacks. The UI must display “Not observable on this platform” in that case.

The existing Android redirect limitation remains: interception does not report later resource redirect hops, nor every scheme. This change measures the available callback, not an expanded enforcement boundary. See [Android WebViewClient request callback documentation](https://developer.android.com/reference/android/webkit/WebViewClient#shouldInterceptRequest(android.webkit.WebView,android.webkit.WebResourceRequest)).

## Native denied-navigation events

Android and iOS now carry a typed `reasonCode` and, only when the native policy returned one, a category on `navigationBlocked`. Codes distinguish mandatory category, security threat, additional restriction, unavailable policy, and unsupported capability. Generic failures never invent a category. These events carry the captured view/request identity and static explanatory copy, but omit the attempted URL and title. Dart validates these values before showing the branded recovery screen. Native navigation, redirect, popup, and same-document policy checks retain enforcement before the boundary is presented; resource denials remain resource outcomes rather than page-level recovery events.

The protocol change is implemented in native source. The final Android integration rerun passed the added typed-event assertions, including omitted URL/title and additional-restriction categories. The final iOS selection passed all 13 current consumer tests, including the typed denial/redaction assertions. Updated XCTest assertions retain the real server nonarrival/history checks while checking redaction and policy categories.

## New execution evidence

| Command / check | Result | Evidence |
| --- | --- | --- |
| Initial `cd android && ./gradlew testDebugUnitTest --console=plain` | Blocked: fresh checkout excludes generated wrapper. The preceding first attempt also used an absent log directory; both were setup failures, not test failures. | `evidence/android-native-baseline.log` |
| `flutter build apk --debug` | Passed; Gradle 53.9s, generated wrapper and built ordinary debug APK | `evidence/android-debug-build.log`; `build/app/outputs/flutter-apk/app-debug.apk` |
| `cd android && ./gradlew testDebugUnitTest --console=plain` | Passed; 23 app tests, 0 failures/errors/skips; includes 5 new counter tests | `evidence/android-native-tests.log`; generated XML under `build/app/test-results/testDebugUnitTest/` |
| New counter unit scenarios | Actual reported outcome, repeated snapshots, stale callback rejection, close/reset, independent normal/private instances, saturation, concurrent callback safety | `ObservedRequestCountersTest.kt` |
| `flutter test integration_test/observed_request_counters_test.dart -d emulator-5560 --reporter expanded` | Passed; 1 integration journey, including actual WebView blocks and normal/private cookies/localStorage separation. Device run 63s; build57.9s/install27.7s | `evidence/android-counter-integration.log` |
| Android native counter integration rerun | Passed; 1 journey, device run174s; build126.3s/install19.8s. The final marker predates the newly added typed-event assertions, so this is not their acceptance result. | `evidence/android-counter-boundary-integration.log` |
| `dart analyze integration_test/observed_request_counters_test.dart` | Passed; no issues | `evidence/android-counter-analysis.log` |
| Final Android integration | Passed;1 journey,2m44 total, build26.9s/install8.8s; actual blocked outcomes, replay/reset, private cookie/localStorage isolation and typed redaction | `evidence/android-native-final-integration.log` |
| Ordinary Android release APK | Passed,46.6s; normal Flutter package resolution corrected a stale test-plugin registrant left by an initial `--no-pub` attempt. Existing debug signing fallback preserved. | `evidence/android-build-manifest.json`; `artifacts/android/Wingman-0.16.0+19-local-release.apk` |
| `flutter build ios --simulator --debug` | Passed ordinary `lib/main.dart` simulator build in129.8s; before final typed-boundary edits | `evidence/ios-simulator-build.log` |
| Ordinary iOS native runtime | Dedicated simulator completed onboarding; example.com rendered, native link opened IANA, Back/Forward worked, companion created a real synthetic QA task/checklist/note and explicitly saved the permitted page | `screenshots/ios-native-example-page.png`, `ios-native-forward-iana.png`, `ios-wingman-populated.png`; `evidence/ios-app-runtime.log` |
| Final ordinary iOS UI runtime | Passed CUA smoke: immediate compact task Continue; 5 companion reopen cycles preserve saved state; restored-task Finish detail; real timer countdown then paused restart at13:30; private task/notes separation; reserved synthetic mandatory boundary and safe recovery. | `evidence/ios-ordinary-runtime-final.md`; `screenshots/ios-home-final-populated.png`, `ios-companion-final-restored.png`, `ios-finish-final-paused-restart.png`, `ios-private-boundary-final.png` |
| Current consumer iOS XCTest selection | Passed; 13 tests, 0 failures or unexpected failures, 21.347s test runtime / 144.79s complete command. Current consumer selection excludes the two explicitly historical pilot tests. Fresh result bundle retained. | `evidence/ios-native-final-20260925T201305Z.log`; `evidence/ios-final-summary-20260925T201305Z.json`; `work/redesign/ios-native-final-20260925T201305Z-56581.xcresult` |
| Final ordinary iOS simulator build | Passed; final stable-source incremental build 23.87s after Home semantics and restored-task callback fixes. Three affected UI files had identical before/after SHA256s. `lib/main.dart` app, bundle `com.wingmanbrowser.app`, version 0.16.0 build 19, no XCTest bundles. | `evidence/ios-simulator-stable-20260925T201929Z.log`; `evidence/ios-simulator-stable-summary-20260925T201929Z.json`; `artifacts/ios-simulator/Wingman-stable-20260925T201929Z.app` |

New integration fixture serves generated benign HTML on process loopback. It requests installed reserved `.test` policy destinations as image resources. It verifies observed denial counts, repeated snapshot stability, top-level denial exclusion, renderer reset, and normal/private store separation where private profiles are supported. It changes no production policy and uses no external website/feed quota.

Integration-test APKs in transient build output are not delivery artifacts. The ordinary `lib/main.dart` release APK is separately copied and hashed under `artifacts/android/`. All mobile builds/tests are serialized with the root UI agent to avoid concurrent `native_assets.json` writes.

## Historical macOS preparation and current workstream

At the initial audit macOS was **absent**. It is now implemented on the separate `feat/wingman-macos` branch; current build, runtime and test evidence is in [the desktop ledger](../../../../wingman-macos/docs/ui/redesign/macos/README.md). The following API audit records the original preparation, not current completion status. The web build remains a companion and cannot claim host browser protection. Per the master task, create the macOS branch only after the shared UI is completed and committed; do not delay the cross-platform UI for this work.

The lowest-dependency appropriate adapter is AppKit `WKWebView` inside Flutter `AppKitView`, retaining the existing protected method-channel contract. Official Flutter documentation describes an `NSView` factory through `FlutterMacOS`; the installed SDK confirms `create(withViewIdentifier:arguments:) -> NSView`, unlike iOS's `FlutterPlatformView` factory. It warns that macOS platform-view gesture support remains incomplete, which requires real mouse, keyboard, scrolling, overlays, and focus testing. See [Flutter macOS platform views](https://docs.flutter.dev/platform-integration/macos/platform-views) and [AppKitView](https://api.flutter.dev/flutter/widgets/AppKitView-class.html).

The official BSD-3-Clause `webview_flutter_wkwebview` 3.26.1 plugin is another available choice: macOS support exists since 3.15.0 and current minimums are Flutter 3.44 / Dart 3.12. It does not itself establish Wingman's mandatory rules, capability gating, private lifetime, or owned popup behavior. A direct custom adapter avoids depending on undocumented plugin internals and additional packages. This is an implementation recommendation, not a claim that its eventual adapter has passed QA. See the [official plugin](https://pub.dev/packages/webview_flutter_wkwebview), [changelog](https://pub.dev/packages/webview_flutter_wkwebview/changelog), and [supported platforms](https://pub.dev/documentation/webview_flutter/latest/).

Apple APIs and deployment availability checked in the installed Xcode macOS WebKit headers:

| Required feature | macOS API / minimum |
| --- | --- |
| Native renderer / navigation decisions | `WKWebView`, `WKNavigationDelegate` / 10.10 |
| Normal/private data stores | `WKWebsiteDataStore.default()`, `.nonPersistent()` / 10.11 |
| Mandatory compiled resource rules | `WKContentRuleListStore`, `WKUserContentController.add` / 10.13 |
| Modern navigation preferences / JS | `WKWebpagePreferences` / 10.15 |
| Native find / page zoom | `WKWebView.find`, `pageZoom` / 11.0 |
| Downloads / redirect delegate | `WKDownload`, navigation conversion / 11.3 |
| Pause media and end capture on hide | `setAllMediaPlaybackSuspended`, camera/microphone `.none`, `closeAllMediaPresentations` / 12.0 |
| Native upload chooser | `WKUIDelegate.runOpenPanel` / 10.12, using AppKit `NSOpenPanel` |

The implemented target uses macOS13+ (including AppKit sharing-picker lifecycle APIs) and can use these APIs on the detected 15.7.4 host. Official [content rule documentation](https://developer.apple.com/documentation/webkit/wkcontentruleliststore) requires rule compilation and addition to each configuration before loading. [Nonpersistent stores](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/nonpersistent()) separate ephemeral website state. A sandboxed target needs outgoing network capability ([Apple entitlement reference](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)); downloads/uploads require scoped user-selected file access rather than blanket filesystem access. No paid plugin, external rendering engine, VPN, signing entitlement request, notarization, or production identifier change is necessary for local development.

The separate branch followed this implementation sequence:

1. Generate only the new macOS target in the isolated desktop checkout. Preserve mobile IDs/signing. Set a local macOS identifier scoped to this new target and document it.
2. Extract/reuse the platform-independent Apple policy decoder, digest validation, strict-search canonicalization, compiled-rule generator, and signed-update semantics with parity tests. Keep UIKit-dependent sheets, lifecycle, factory signatures, and permissions out of the macOS adapter.
3. Implement both application/local-storage services and protected engine methods. Gate consumer capability until mandatory validation and all rule compilation succeed. Use `AppKitView` in the shared Flutter surface only for the macOS target.
4. Implement accepted URL/search loading, actual history/reload/stop/status/find, normal/private stores, captured tab ownership, lifecycle/media suspension, popup policy/revalidation, and cleanup. Keep unavailable permissions/file operations explicitly unavailable until their complete AppKit paths exist.
5. Exercise real neutral pages plus local redirects, new windows, POST forms, private cookies/storage, history, stale events, absent/corrupt policy, native hide/background, rule enforcement, and disposal. Leave live browsing gated on any missing mandatory capability.
6. Capture the running desktop shell and website; build local release output. Compile success alone is not native-browser acceptance.

Persistent coverage limits remain: WK request counts are unobservable, Android resource redirect coverage is limited, and the existing small alcohol/drug/tobacco data supplements are not comprehensive maintained feeds. Actual macOS acceptance is maintained in its separate ledger. Windows/Linux are absent and are not prerequisites for the macOS workstream.

## Apple ownership follow-up

The final native callback/request/lifecycle fencing mirrored from the macOS audit into iOS has a separate source-hash/test/build record in [IOS_OWNERSHIP_FOLLOWUP](IOS_OWNERSHIP_FOLLOWUP.md). It supersedes the earlier iOS build for delivery once its recorded command succeeds; earlier screenshots retain their stated provenance.
