# Mandatory eligibility: first milestone security checks

This document describes the **bundled plain-text milestone**. It does not certify arbitrary live websites, documents, media, remote search, authentication or downloads as safe. Those capabilities are unavailable. Only the separate signed catalog evaluator can admit bundled content to the Flutter reader.

## Enforceable boundary

`lib/browser/browser_engine.dart` contains no WebView, URL launcher or network import. Its compatibility adapter rejects every navigation before a controller or native renderer can be allocated. Legacy policy callbacks, allow-once payloads, private flags, roles and test callbacks are never consulted for permission. The former annotation-only JavaScript test hook now throws unconditionally. The live Reader extraction script is removed.

`android/.../MainActivity.kt` and `ios/Runner/AppDelegate.swift` accept only a small set of local operations. Renderer configuration, private configuration, binding/preparation, policy mutation, scripts, file uploads, permission requests, downloads and external-opening methods are rejected by the default native channel branch. Default-browser requests return false. There is no content-engine enable switch in any build mode. The old native host evaluators, navigation clients, authentication delegates, download implementations and tracker-rule updater are removed; only IDNA normalization remains in the files named `NativeGuardPolicy`.

The Flutter WebView packages and generated plugin registration are removed as well. Rejecting the wrapper alone would have left the official plugin's raw Pigeon constructor channels available. AndroidX WebKit remains only for explicit legacy store cleanup; Apple WebKit remains for website-store removal and a read-only native hierarchy check. Neither path constructs a content WebView.

## Native test matrix

The two active native suites replace the previous browser-success suites. Their counters record only requests to the controlled loopback fixture, not all device/OS traffic.

| Check | Test / observable evidence | Android | iOS |
|---|---|---|---|
| Typed/reused/new/private address attempts | `browser_engine_test.dart`: HTTP/HTTPS unknown, redirect, POST, popup, download, auth and custom/data/blob/JavaScript/file/content/intent/about schemes produce `blockUnsupported`; zero live views | PASS | PASS |
| No preapproval load or legacy policy escape | Always-allow callback, permissive policy, role and allow-once values are supplied; policy/prompt/page/before-load callback counts remain zero | PASS | PASS |
| No Reader/script/back/forward/reload escape | Public legacy actions cannot allocate a renderer; Reader returns null; script hook throws even in debug | PASS | PASS |
| Native direct-call boundary | `guard_engine_test.dart`: 28 unsupported method names × five roles rejected, regardless of old IDs, request tokens, private, approved or debug payloads | PASS | PASS |
| Raw WebView plugin is absent | Former Pigeon constructor channel has no handler | PASS | PASS |
| No unreviewed page/resource fetch | Fixture would request frames, images, media, fetch, service-worker and WebSocket resources if rendered; no initial request occurs, so those features are unavailable rather than selectively filtered | PASS | PASS |
| Cleanup without a view | Native legacy quarantine and store deletion complete; native hierarchy reports zero content views | PASS | PASS |
| External text processing | Android embedding PROCESS_TEXT query returns no actions; direct action launch rejects | PASS | No analogous Android embedding channel |
| Native capture floor | Android activity secure flag cannot be weakened with a false Dart request; iOS retains its universal inactive-scene cover | PASS | Source retained; actual app-switcher recheck pending |
| Release dependency/permission boundary | Inspect merged APK manifest/DEX and iOS plugin/framework artifacts; no GMA/UMP or Flutter WebView bridge; production Android has no INTERNET permission | Pending artifact audit | Pending artifact audit |

Observed on the dedicated Android 16/API36 emulator (System WebView 134.0.6998.135) and iOS 26.3.1 iPhone 17 Pro simulator. The Android browser fixture passed (22.0-second build, 2-second suite); its final native fixture passed after the ProcessText change (17.1-second build, 3-second suite). The iOS browser fixture passed (24.8-second build, 2-second suite) and native fixture passed (18.0-second build, 2-second suite). Logs are in the parent workspace: `work/mandatory-browser-android.log`, `work/mandatory-native-android-final.log`, `work/mandatory-browser-ios-retry.log`, and `work/mandatory-native-ios.log`. The first iOS attempt failed during a generated Swift-package source race before app launch; it is preserved in `work/mandatory-browser-ios.log`, not counted as a pass. The separate delayed-native-deletion host regression passed (`work/mandatory-clear-timeout.log`).

A blocked initial request is the intended result for iframe, POST, redirect, script and service-worker fixtures. These tests **do not claim** that those mechanisms can be selectively admitted or intercepted safely. There is no live positive-eligibility adapter in this milestone.

## Real application startup and UI integration

`integration_test/protected_app_test.dart` calls production `app.main()` with the real bundled signature verification, policy checkpoint SQLite, native cleanup and application SQLite. It verifies the 14-resource catalog, a local Moon search, the article text, Bookmark/Read later state and UI, fixed rejection of an arbitrary loopback address, dismissed editing after rejection, an actual tap on a core-protection row with no override, and zero content views/fixture requests. Student saves remain session-only; the test restores only the reviewed-ID saves it adds.

| Tested build | Result | app.main to first settled UI | Build / suite | Log in parent workspace |
|---|---|---|---|---|
| Android debug, student edition | PASS | 3,076 ms | 15.3 s / 10 s | `work/mandatory-app-android-student-handoff.log` |
| iOS simulator debug, consumer edition | PASS | 1,385 ms | 19.3 s / 7 s | `work/mandatory-app-ios-consumer-final.log` |

These are single debug integration observations after the harness/process is already running. They exclude OS process launch and installation, use existing app storage, and are **not cold-start, release-performance or physical-device measurements**. Earlier test-only failures remain in `work/mandatory-app-android-student.log` (tap before scroll layout settled) and `work/mandatory-app-ios-consumer.log` (test scrolled the lazy sheet heading offscreen before checking it). The latter investigation also prompted explicit keyboard dismissal on URI rejection; the final tests assert that behavior.

## Legacy data and download migration

Startup must await `NativeBrowserService.quarantineLegacyContent()` before displaying the reviewed catalog. Failure or a 15-second timeout is an unavailable startup state, not permission to restore an old tab. The native channel rejects concurrent deletions rather than reporting a narrower pending request as if it fulfilled a later selection.

Android cancellation queries only this app's DownloadManager rows in pending/running/paused states; completed user files are preserved. It removes legacy default site data and deregisters old Wingman private profiles by name without loading them. Android explicitly forbids deleting profiles already loaded through `getProfile`; it may finish physical profile-file deletion asynchronously after successful deregistration. No renderer or profile restore path remains. [Android ProfileStore](https://developer.android.com/reference/androidx/webkit/ProfileStore) Complete cache/storage deletion on a provider without `DELETE_BROWSING_DATA` reports unsupported instead of creating a temporary WebView or claiming partial success. Android's complete store API also removes cookies/cache when storage or cache is selected. iOS removes the previous persistent WK store, including service-worker registrations and fetch caches; prior nonpersistent process-local stores are not restored. Neither migration previews old titles or content. Actual migration of a deliberately seeded outstanding OS download or a pre-upgrade orphan private profile has not been tested in this milestone; cancellation/deregistration scope is source-reviewed. The Android cleanup was corrected to avoid the documented getProfile/deleteProfile conflict and the final main-app run includes that correction.

## Why arbitrary live browsing remains unavailable

Android documents that the navigation callback omits app-initiated `loadUrl` and POST requests. Its resource callback omits `javascript:`/`blob:` resources and observes only the initial resource URL in a redirect chain. These are unsuitable as an exhaustive positive-eligibility boundary. The previous implementation also checked only main-frame content policy, leaving ordinary subresources outside it. [Android WebViewClient](https://developer.android.com/reference/android/webkit/WebViewClient)

Apple's custom scheme handler cannot replace a scheme already handled by WebKit. It is not a general HTTPS body interception API. [WKWebViewConfiguration scheme registration](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/seturlschemehandler(_:forurlscheme:))

WebKit content rules can block URL-pattern requests in advance, but request patterns alone do not establish that changing page bodies, feeds, generated content or media are reviewed. The old compiled list contained only optional tracker-domain rules. [Apple content-blocking rules](https://developer.apple.com/documentation/safariservices/creating-a-content-blocker)

The former WK downloader omitted its redirect decision method, for which Apple documents that redirects proceed by default. The downloader has now been removed entirely. [WKDownload redirect decisions](https://developer.apple.com/documentation/webkit/wkdownloaddelegate/download(_:willperformhttpredirection:newrequest:decisionhandler:))

Built-in phishing/malware warnings and SafeSearch parameters do not constitute positive eligibility for Wingman's mandatory taxonomy. No TLS interception, custom trust root, VPN, browser entitlement, managed-device enrollment or provider approval was introduced.

## Retired evidence and remaining limits

Previous native tests that successfully browsed arbitrary pages, authenticated to HTTPS Basic fixtures, extracted a live Reader article, measured three active WebViews or exercised optional Guard exceptions no longer describe the product. `browser_engine_test.dart` and `guard_engine_test.dart` are rewritten for denial; `reader_privacy_test.dart`, `http_auth_privacy_test.dart` and `guard_performance_test.dart` are removed. Their earlier logs remain historical evidence only, never passes for the new policy.

Pending or unavailable: real-device testing, release/profile runtime network observation, deliberately seeded outstanding legacy download cancellation, exhaustive iOS app-switcher timing, and any future live resource/auth/redirect approval adapter. Debug/profile Android harnesses retain INTERNET for Flutter tooling and the controlled request-counter test; the production permission check is separate. This application is not device-wide management: it does not claim control over other installed apps or previously saved user files outside its renderer.
