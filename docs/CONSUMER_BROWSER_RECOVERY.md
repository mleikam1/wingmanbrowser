# Consumer browser recovery

## Checkout and reproduction

Audit started September 11, 2026. Repository: `/Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser`. Branch `main`, starting commit `d973e3612b2850b8d6e85de8a740d9df349108f7`. Initial working tree clean. No reset, checkout overwrite, push, publication or production change was performed.

Tooling: Flutter 3.44.4 stable (framework ad70ec4617), Dart 3.12.2, Xcode 26.3 (17C529). Available targets: Android emulators emulator-5554 and emulator-5556; booted iPhone 17 Pro / iOS 26.3, UDID C157677F-A33F-45B2-BFFB-F3DED552D4F4. The installed iOS app was `com.wingmanbrowser.wingmanBrowser`, 0.9.0 build9, ordinary `lib/main.dart`, consumer edition. Android emulator-5554 had no Wingman app installed at audit; this is not represented as an Android before-state reproduction.

Actual installed iOS reproduction, via Simulator UI: Home → Search or enter address → Web selected → `Chicago weather` → Search. DuckDuckGo results rendered, including Weather.com and AccuWeather. Clicking the first Weather.com result produced **Destination unavailable / This destination is not approved**. This was an application policy denial, not a failed provider search or lack of connectivity. The original screenshot and accessibility observations are in the task record.

The old input path was FocusedSearchScreen → SearchIntent(web:true) → BrowserShell._search → StrictSearchPolicy → six-document live policy → protected bridge → scriptless results. Result clicks were canceled by the native delegate and sent back to the same exact-document policy. The old BrowserEnginePool was a retired denial stub. Library mode separately searches installed article text and metadata without network access.

## Changed invariants

Consumer browsing is governed by a mandatory local category/threat baseline, optional additional restrictions and tracker controls. Absence from the reviewed catalog is no longer a denial. A permitted URL is **not verified safe**. Reviewed Home/feed eligibility, installed content integrity and school allowlisting remain separate concerns. School/unknown editions do not receive consumer renderer authority.

The consumer surface now uses native networking/rendering through Android System WebView and WKWebView. JavaScript, first-party cookies/storage, forms and normal redirects are enabled with native destination checks; no privileged JavaScript-to-native bridge is installed. Legacy exact-resource fetchers no longer own consumer transport. Native lifecycle suspension hides/pauses the retained renderer instead of destroying it.

The Flutter shell preserves its existing design, Launchpad, Spaces and tools. Browser controls use actual native history/reload/stop/find/share. User-requested windows open tabs. Four live native renderers are retained; inactive engines beyond this bound are released. Their last address can reopen on selection; native form state, scroll and back/forward stacks are not promised after eviction/process death. Normal-tab last addresses restore locally; private tabs and search-query addresses do not. Normal cookies remain in the normal platform store. Private data is isolated by native profile/data store.

Startup migration is now versioned. The old SQL migration no longer archives/reset legacy metadata on every load. New tab-restoration metadata uses a separate versioned local document and is revalidated before use. Hand It Over still replaces and removes owner renderers; it is not used as the normal browser configuration.

## Validation status

The original search-result denial is repaired: ordinary installed Wingman 0.10.0+10 now opens interactive websites from native search results without adding their document URLs to the pilot allowlist. This establishes a working browsing slice; it is not a claim that every requested browser function or category-protection case is complete.

| Evidence | Recorded result |
| --- | --- |
| Full Flutter host suite | **736 passed, 2 optional skips (7m13s)**, `work/consumer-recovery/full-tests-final.log` |
| Full project analysis | **No issues found (5.0 seconds)**, `work/consumer-recovery/analyze-final.log` |
| Final web release build | **Passed in 460.8 seconds**, `work/consumer-recovery/web-build-final.log` |
| Android native JVM suite | **8 passed**: five signed-update verifier tests and three strict-search tests |
| Android ordinary-app search | **12 queries, 10 ordinary result domains**, including provider refinement and More Results |
| iOS ordinary-app search | **11-query/10-domain matrix**, plus provider-field refinement and More Results; documentation navigation and Walmart image carousel worked |
| Web companion | A normal Home query performed top-level strict-provider navigation and rendered results; it did not embed or proxy websites |

The complete query/domain ledger and failure attribution are in [SEARCH_ACCEPTANCE.md](SEARCH_ACCEPTANCE.md). Tests are separate from these actual application journeys. Earlier totals elsewhere in the repository are historical; native compilation/build/install details belong to the platform records.

On Android, the local fixture demonstrated JavaScript, GET forms, POST login with a 303 redirect, website storage, normal cookie/storage persistence after app replacement, private signed-out/empty storage, private-tab non-restoration, native back/forward, permitted and blocked redirects/windows, invalid-TLS rejection, and a harmless OS-picker download/upload round trip. The final release APK was installed; Find displayed yellow/orange matches and Next/Done worked without the earlier Flutter assertion. Normal cookie/storage survived the debug-to-release replacement. The latest release also passed generated-video fullscreen exit via system Back, the Find-to-next-page visibility regression, and HTTPS origin-named camera denial. Android’s system default-browser role was selected; an external-app link tap remains unverified. See [Android evidence](ANDROID_BROWSER_RECOVERY.md) for the full record and site-specific failures.

On iOS, actual fixtures demonstrated JavaScript, GET submission, back/forward, POST login, storage, normal persistence across replacement, private isolation/non-restoration, permitted/blocked redirects and windows, prohibited paths, and invalid-TLS rejection. A generated 53-byte file completed native save/select/upload, with 246 multipart request bytes received and discarded locally. Generated video played with native fullscreen entry/exit. An HTTPS camera prompt named its origin, and Deny returned NotAllowedError without granting sensor access. Provider-field refinement and More Results appended a second result set. Python's page position survived the menu. Find entry/Next/Done preserved the page and allowed the next navigation; visible iOS match highlighting remains unverified. Simulator drags did not reliably scroll native pages, while keyboard paging did. Detailed outcomes and limits are in [iOS UI acceptance](IOS_UI_ACCEPTANCE.md).

iOS `build-for-testing` passed, but XCTest execution could not launch its test host after approximately eight minutes (`CoreSimulator host_support_mig_launch_app`). Those tests were **not executed**, and the failure is classified as a tooling failure. Ordinary installed-app UI evidence and host Swift policy checks remain separate; they are not relabeled as XCTest passes.

Signed consumer update machinery is implemented: purpose-bound Ed25519 releases, bounded HTTPS transport, transactional active/previous/pending generations, replay protection, native preparation/activation/revert, cached restoration and failure recovery. Startup completes this work before allocating owner renderers. **No production update endpoint or signing key is configured**; the shipped key map is empty and the installed app uses its pinned baseline. Synthetic signed-update tests are not evidence of a running production feed. See [update protocol and configuration](CONSUMER_PROTECTION_UPDATES.md).

## Remaining acceptance and protection gaps

- Android's resource interceptor does not see later subresource redirect hops. Main-document checks do not close that limitation.
- Alcohol, recreational-drug commerce and tobacco/vaping remain small supplements rather than comprehensive maintained category feeds. Actual ESPN pages displayed betting promotion on both platforms: a confirmed false negative.
- iOS encoded/dynamic resource behavior and full signed-update lifecycle need platform-specific evidence. A functioning results page or passing policy unit test does not prove these boundaries.
- Grant-side origin permissions, physical-device behavior and iOS visual find highlighting/touch scrolling remain unverified; the current platform ledgers record executed media, denial, file and refinement checks. Blob downloads and complex POST new-window flows remain unsupported; some authentication/PWA capabilities remain incomplete or unverified.
- iOS default-browser selection requires Apple's managed entitlement, which this checkout does not possess. Native incoming-link handling alone does not confer default-browser eligibility.

The current product exposes installed protection data and staleness, distinguishes permitted from verified safe, and retains separate school/curation policies. [PROTECTION_COVERAGE.md](PROTECTION_COVERAGE.md) and [the requirements audit](RECOVERY_REQUIREMENTS_AUDIT.md) describe the remaining release gates. No production publication, service purchase or push was performed.
