# Strict web search — v0.9.0+9

> Historical pilot record. Consumer 0.10 supersedes the exact-document, scriptless, first-page-only restrictions below. Current implementation and remaining release gaps: [Consumer recovery](CONSUMER_BROWSER_RECOVERY.md), [Search acceptance](SEARCH_ACCEPTANCE.md), [Protection coverage](PROTECTION_COVERAGE.md). School allowlisting remains a separate policy.

Implementation scope recorded September 11, 2026. This document supersedes earlier blanket statements that Wingman has no live web search. It does not broaden the existing reviewed destination list or establish a completed general-purpose browser.

## What is implemented

Supported Android and iOS 18.4+ native sessions can display the first, text-only DuckDuckGo results page. The user enters a query in Wingman's address/search field, chooses **Web**, and submits. Wingman constructs this one canonical URL locally:

```text
https://safe.duckduckgo.com/lite/?q=<UTF-8-percent-encoded-query>&kp=1
```

DuckDuckGo documents its safe hostname as always using Strict SafeSearch, `kp=1` as strict, and a public non-JavaScript Lite version. This implementation opens the ordinary provider page directly; it does not scrape results into a Wingman search index, call a private API, or use a paid search API. [SafeSearch documentation](https://duckduckgo.com/duckduckgo-help-pages/features/safe-search), [non-JavaScript versions](https://duckduckgo.com/duckduckgo-help-pages/features/non-javascript)

Search has no page scripts, image search, result images, pagination, provider form submissions, sign-in, uploads, downloads or interactive embeds. A new query must be submitted through Wingman's field. The permitted stylesheet can change upstream; an unsupported redirect or resource change can make the page fail or appear incomplete. Failure does not open a different provider, an unrestricted renderer or an external browser.

**Native desktop builds, live browsing and live search are not implemented.** The web companion runs in desktop browsers with local tools only. A maintained desktop engine, broader usable destination coverage, and further mobile browser compatibility remain required to meet the cross-platform browser goal. With only six permitted destination documents, many search results cannot open. This release is not a completed Firefox or DuckDuckGo Browser replacement.

## Fixed floor and optional restrictions

The publisher's build fixes DuckDuckGo adult filtering at **Strict**. There is no Moderate/Off choice, custom provider endpoint, API key setting, PIN bypass or private-mode exemption. Incoming supported DuckDuckGo search addresses are rebuilt under the canonical policy before loading; their setting parameters do not become authority. Bang shortcuts and direct-result shortcut syntax are rejected.

Changing the baseline requires a code change, security/content review and an app release. There is no Firebase admin setting, remotely editable allow flag or automatic filter updater that can lower it.

**Settings → Search** explains the filter and native capability. **Protection → Additional boundaries → Disable web search** persists the `web-search` collection restriction and removes live search while leaving local library search available. Private tabs inherit it read-only. Other saved boundaries can further restrict reviewed content. Removing an extra restriction restores only access already allowed by the publisher policy and current native capability.

Search availability requires the signed offline policy, current build-pinned live policy, native search capability, private capability when applicable, and no additional search restriction. The present live pack expires at **00:00 UTC on October 11, 2026**; expiry also closes search until a reviewed app update.

## Search filtering is not six-category classification

DuckDuckGo Strict targets adult results and explicitly acknowledges filtering misses. It is not a guarantee against gambling, alcohol, recreational-drug or nicotine promotion, malicious destinations, or every prohibited subject. A result snippet or advertisement may appear before its destination is evaluated. Wingman does not classify each search snippet or advertisement against all six of its content rules. Blocking a clicked destination cannot undo content already displayed in the results page. [Provider filtering scope and limitations](https://duckduckgo.com/duckduckgo-help-pages/features/safe-search)

The UI describes provider filtering and destination access separately. A search result, advertisement or provider redirect does not grant access. Result wrappers are decoded locally when supported, then the resulting address passes the normal destination policy. No network request is needed merely to decode a wrapper. These six exact destination documents are unchanged:

| Source | Permitted documents |
| --- | --- |
| NASA | `https://science.nasa.gov/moon/facts/`, `https://science.nasa.gov/moon/`, `https://science.nasa.gov/moon/exploration/`, `https://science.nasa.gov/earth/facts/` |
| Wikipedia | `https://en.wikipedia.org/wiki/Chicago_Bulls` |
| Adafruit | `https://www.adafruit.com/product/64` |

Their listed passive resources remain subject to the separate [live browsing policy](LIVE_BROWSING_POLICY.md). ESPN and Walmart remain disabled. No whole destination domain is approved, and reviewed addresses can serve changed content; there is no per-image or automatic six-category text classifier.

DuckDuckGo may display advertisements. Wingman does not add URL parameters that remove provider branding or advertising. The provider's integration guidance specifically asks applications and extensions not to disable these through parameters such as `k1`. This feature does not promise an ad-free search page. [URL-parameter integration guidance](https://duckduckgo.com/duckduckgo-help-pages/settings/params)

## Privacy and cost

Typing does not trigger remote suggestions or send partial queries. Submitting sends the full query and ordinary connection metadata, including the connecting IP address, directly to DuckDuckGo. The query is present in its HTTPS URL; encryption does not hide it from the provider. DuckDuckGo's policy says it does not store IP addresses alongside searches, but does retain anonymous search queries disconnected from identifying information. Its advertising and privacy practices still apply. [DuckDuckGo privacy policy](https://duckduckgo.com/privacy)

Wingman keeps submitted query URLs only in temporary session state. It does not persist web-query history or allow search pages to be saved as Launchpad pins; users can pin an independently eligible destination instead. Reloading, revisiting or resuming a transient search tab, including after a menu overlay, can send that already-submitted query to DuckDuckGo again. Local library search remains on device. No query is sent to a Wingman search server, Firebase, analytics service or cloud classifier. Private mode does not hide the query or IP from the provider.

Native storage boundaries still matter: Android disposable profiles can use temporary disk files and undergo explicit browsing-data and cookie cleanup; empty random profile names may remain until the next process start. iOS uses a nonpersistent website store. These controls are not a promise to erase OS backups, keyboard-provider data, external records or every possible network observation. Query text is not placed in WebKit's persistent rule-list definitions.

DuckDuckGo's ordinary search is free. No new paid search API, subscription, Firebase/GCP resource, deployment or per-query Wingman cloud billing was introduced. Existing cloud workloads were left unchanged; their spending was not audited. Store distribution, development, policy review, maintenance, updates and connectivity can still cost money. Future services and their cost design are outside this implementation. [Provider cost information](https://duckduckgo.com/duckduckgo-help-pages/get-duckduckgo/how-much-does-duckduckgo-cost), [Wingman cloud cost plan](CLOUD_COST_PLAN.md)

## Technical appendix

- **Independent native validation:** [Dart StrictSearchPolicy](../lib/policy/strict_search_policy.dart), [Kotlin serialization](../android/app/src/main/kotlin/com/wingmanbrowser/wingman_browser/StrictSearchPolicy.kt) and [Swift serialization](../ios/Runner/ProtectedWebBridge.swift) independently validate bounded Unicode queries and construct the fixed URL. Native `openSearch` receives the query, not a caller-provided endpoint or permission token. Encoded shortcuts, control characters and malformed input are rejected. The three implementations share adversarial fixture cases, not a shared trusted result.
- **Separate request scope:** each search permits its exact HTTPS document and one fixed HTTPS CSS address, `https://safe.duckduckgo.com/dist/lr.48ddfe4eadf6a534e93f.css`. Other resource requests are denied by default. Provider query parameters, cookies, page content and result links cannot add permission. The CSS filename is pinned; response content is not cryptographically pinned.
- **Android:** the native bridge mediates document/CSS requests, rejects redirects, checks response MIME types and byte limits, and returns intercepted data. `WebSettings.blockNetworkLoads` blocks WebView-owned network fallback. This is not a universal packet-silence claim. JavaScript, provider input controls and external dispatch remain disabled.
- **iOS:** a generic query-free search rule list is compiled at startup before search capability becomes available. Opening a query does not compile or persist a query-specific list. Default-deny rules permit only the canonical document pattern and fixed CSS; exact document ownership and native navigation checks remain separate. Cookie-blocking rules and a nonpersistent data store apply.
- **Platform limits:** WKWebView does not expose Android-equivalent inspection of every subresource response body, MIME type or streamed byte count. A rule-list match is not a content classification or response-integrity guarantee. Native request ownership, renderer teardown, lifecycle gates and cleanup remain required independently of URL validation.

The protected bridge and existing live policy, rather than an unrestricted engine, own this surface. The implementation does not inherit DuckDuckGo Browser's complete protections merely by using DuckDuckGo Search.

## Validation

Native bridge fixtures have passed normal and private search journeys on Android and iOS simulators. They provide evidence for the tested provider page and bridge behavior, not universal result filtering, physical-device security, desktop support or future provider compatibility.

The complete v0.9 host suite passed **686 tests with two optional skips**. The analyzer reported no issues, and all three native/Dart live-manifest pins matched. The actual app search flow passed on both platforms: startup, Web selected by default, submitted query rendered, search pin disabled, menu teardown and saved search-boundary revocation. Those fixtures verified that existing preferences, history and Launchpad data were preserved.

A controlled WKWebView XCTest also passed using the production rule builder and navigation predicate. Its synthetic loopback HTTP page and stylesheet each received one request; the iframe, redirect target, unknown resources and beacon received zero. The initial 302 response was requested, providing a positive redirect control. This is measured fixture behavior, not a guarantee about every HTTPS response or future OS release. Relevant executable coverage:

- [Shared adversarial query cases](../test/fixtures/strict_search_cases.json), [Dart URL-policy tests](../test/policy/strict_search_policy_test.dart) and [runtime gating tests](../test/policy/strict_search_runtime_test.dart).
- [Search settings, saved restrictions and private inheritance tests](../test/strict_search_settings_test.dart).
- [Shell search routing and privacy tests](../test/ui/strict_search_shell_test.dart).
- [Native search bridge fixture](../integration_test/strict_search_native_test.dart).
- [Actual app search fixture](../integration_test/strict_search_app_test.dart) and [controlled WebKit fixture](../ios/RunnerTests/RunnerTests.swift).

Validation used a dedicated Android 16/API 36 emulator and an iPhone 17 Pro/iOS 26.3 simulator, with `--no-uninstall` for native integration runs. Android's bridge fixture counted 14 result anchors in the fetched HTML and one loaded stylesheet per normal/private search; iOS counted 10 DOM result anchors and one external stylesheet per normal/private search. Both kept page JavaScript disabled. Android reported exactly two mediated requests per search, and iOS prepared its single query-free search rule list at startup without recompiling it for private visits. These counts describe the observed benign query and can change with provider results.

All six existing app regressions also passed: `protected_app_test.dart`, `launchpad_app_test.dart` and `protected_live_app_test.dart` on both platforms. They cover offline discovery, saved articles, tab switching, immutable controls, rejected URLs, Launchpad editing/restoration, live-page pinning and restriction revocation. The article-search fixtures explicitly choose Library now that supported native sessions default to Web. Test-owned changes were cleaned up without replacing unrelated saved preferences or records.

After the final scope-copy corrections, 93 focused host regressions passed and the analyzer remained clean. The release web build passed; its actual companion search screen was inspected with Web disabled, Library selected and the unsupported-platform explanation visible. The preview was returned to Home without changing saved customization. This does not establish native search rendering in a desktop browser.

Ordinary `lib/main.dart` **0.9.0+9** builds then passed and were upgraded/launched on the dedicated native targets with their installed data preserved. They contain no integration-test entry point or capture override. The Android debug APK is `build/app/outputs/flutter-apk/app-debug.apk`, 187,021,959 bytes, SHA-256 `ec2ea4825e0ede8f292acff6c086db73c201812242db8311cb60df64dd5e208d`. The iOS simulator bundle is `build/ios/iphonesimulator/Runner.app`, version 0.9.0/build 9. Generated binaries and local run receipts remain outside version control; no store upload or cloud deployment was performed.

Fresh native screenshot review and physical-device/release acceptance remain open. Existing capture protections were preserved. The app is a development build; simulator evidence is not store approval.

The [v0.8 visual-browsing QA report](PROTECTED_VISUAL_BROWSING_QA.md) remains evidence for that earlier destination pilot. Its old totals and blanket no-search statements are not v0.9 search acceptance evidence.
