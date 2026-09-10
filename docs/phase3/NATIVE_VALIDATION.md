# Phase 3A native validation

Recorded 2026-09-10. The exact tool, OS and engine combination is listed in [the platform capability matrix](../PLATFORM_CAPABILITY_MATRIX.md). All measurements below use debug builds on an Android emulator or iOS simulator unless expressly stated otherwise. Logs are retained under the parent workspace's `work/` directory.

## Baseline failures and fixes

The Android Guard baseline failed once when an allowed tracking fixture retained an earlier block. An unchanged repeat passed. Review identified a stale native-report window: posted/IO callbacks had no navigation request identity. Native reports now carry the request token captured before evaluation, and Dart rejects a token from an older request. Android generation checks also guard report delivery; an undelivered block marker is cleared when a policy update invalidates it. Public navigation, allowed delegates, reload, back and forward bind the native request identity. Native-only POST/redirect callbacks keep the current identity. The Guard fixture now replays an old native block after a newer allowed page is loaded and verifies that it cannot replace the page.

The iOS browser baseline stalled at shared website-data deletion for over two minutes. It was interrupted and is **not** counted as a pass. A repeat with diagnostic timing passed, but that did not establish a fix. Subsequent 15-second bounded runs failed both with and without UI frame pumping. The fixed native stage was `clearing-default-store`.

Native logs explain the retention problem: default-store memory-cache deletion broadcast to six web processes despite a maximum of three Dart entries. Three completed immediately, while two others replied after approximately 56 and 65 seconds; one had no completion in the captured tail. Removed views still had native `pageCount=1`. Removing a WKWebView from its superview had left the plugin's Pigeon strong reference alive until Dart garbage collection.

The fix adds an explicit lifecycle method to the existing local WK controller extension. After native stop/detach and private-store clearing, it removes the three upstream self-KVO observations and calls Pigeon's existing documented manual-release method. The engine waits for the native weak lookup to return no view before shared deletion begins. No private OS API, generated Pigeon protocol change, cache omission or longer timeout is used. The native regression checks the actual weak WKWebView count through 12 close/evict cycles, as well as the Dart pool count.

The corrected iOS browser regression passed in **16 seconds**, plus teardown (`phase3-browser-ios-release-fix.log`): no more than three retained WK views during cycling, **zero** after clear, selected cookies/localStorage actually absent, history cleared, and navigation/back/forward/target-blank/SPA/error/failed-address retry checks preserved. This result follows the failed runs rather than erasing them. Native deletion can still fail on an unhealthy platform; success is never inferred from elapsed time.

The production clear operation returns an explicit timeout after 15 seconds if native completion is missing. New page loads stay paused until that operation finishes. A second request with different selected types is rejected while the first remains pending. The focused host test simulates cache-only deletion timing out and a cookies-only retry, verifies that the retry cannot report success, then verifies the pending state clears only on the original native completion (`phase3-clear-timeout-final.log`, pass).

## New capability checks

`reader_privacy_test.dart` exercises native page scaling and the privacy APIs using synthetic local documents. The iOS Reader is required to omit form/input/textarea/contenteditable/hidden/transparent/blurred/clipped/ARIA-hidden text and HTML; modal and large nonsemantic overlays make Reader unavailable. An isolated-world check overwrites page-world helpers and requires Reader to remain unaffected. Extraction is an explicit local action, and the fixture asserts no additional HTTP request. Inactive/stale views cannot produce a Reader result. Android explicitly reports Reader unsupported rather than using a page-controlled script world.

The Android test reads the actual activity secure flag in normal and private views and verifies that a Dart request cannot disable it; it also reads the native page zoom and default WebAuthn mode. The iOS test exercises the scene cover's debug state hook and native page zoom. **The debug cover hook is a state test, not an actual app-switcher screenshot test.** Real lifecycle/visual acceptance must be reported separately by the main-app checks. iOS active user screenshots remain possible.

The opt-in `http_auth_privacy_test.dart` uses only the explicitly synthetic public HTTPS fixture credentials `wingman-fixture` / `test-only`. It does not sign up for an account, access a password vault or install trust certificates. The test requires a normal authenticated response, a separate private challenge with denial preventing the authenticated body, a private-specific successful response, normal-session preservation after private close, and a fresh private challenge afterward. Provider/network failures are inconclusive, not privacy passes. See final runtime results below before treating this included fixture as executed evidence.

## Before-change performance

`phase3-performance-android-before.log` passed using the same existing opt-in debug fixture and an unsigned synthetic 100,000-rule database. Production pack signature checks are not bypassed; this file is accepted only by the explicit debug benchmark path.

| Measurement | Before |
|---|---:|
| 1,000 native SQLite evaluations, no host cache: p50 / p95 | 432.583 / 4,655.875 µs |
| Main-process PSS, idle | 309,280 KB |
| Main-process PSS, three resident views | 351,018 KB |
| Main-process PSS difference | 41,738 KB |
| Android guest total memory | 1,971 MB |
| Available guest memory, idle / three views | 689 / 641 MB |
| Three loopback page loads | 1,215 / 156 / 339 ms |
| 30 debug tester-pump switches: p50 / p95 | 66.691 / 112.790 ms |

The native lookup timer is `System.nanoTime`, so it excludes Flutter method-channel transport. Debug tester-pump switching includes test-framework and debug overhead and is **not** a production frame-latency or smoothness metric. Three page-load samples do not establish a navigation percentile. Renderer-process PSS was not measured, so the memory figures are not total browser memory. Host swap was 18,250.62 MB used even without simultaneous heavy builds. Actual browser-ready cold startup, physical low-end phones, older physical iPhones, profile/release frame timing and total process-tree memory remain unmeasured.

## Final runtime results

| Final native fixture | Result | Log |
|---|---|---|
| iOS browser lifecycle / clear-data / native retention / existing navigation | Pass, 16 s plus 2 s teardown | `phase3-browser-ios-release-fix.log` |
| iOS Reader isolation, exclusions, overlay refusal, scaling, privacy state | Pass, 2 s plus 2 s teardown | `phase3-reader-ios-isolated.log` |
| iOS Guard, native request identity and existing policy/POST/redirect checks | Pass, 7 s plus 1 s teardown | `phase3-guard-ios-handoff.log` |
| Android Reader explicitly unavailable, normal/private secure flag, scaling, default WebAuthn mode | Pass, 4 s plus 1 s teardown | `phase3-reader-android-gated.log` |
| Android Guard, stale block replay, existing policy/POST/redirect and tracker checks | Pass, 9 s plus 1 s teardown | `phase3-guard-android-handoff.log` |
| Android browser, private storage, actual clear, SPA/error/retry and renderer recovery | Pass, 15 s plus 1 s teardown | `phase3-browser-android-handoff.log` |
| iOS synthetic HTTPS Basic authentication isolation / normal preservation | Pass, 4 s plus 2 s teardown | `phase3-auth-ios-final.log` |
| Android synthetic HTTPS Basic authentication isolation / normal preservation | Pass, 5 s plus 1 s teardown | `phase3-auth-android.log` |

The first iOS authentication run reached private cancellation after successful normal authentication, then failed because loading remained active (`phase3-auth-ios.log`). WebKit's cancellation result is also used for ordinary stop/supersede operations and was ignored by the general error path. The app now explicitly settles a user-cancelled current HTTP-auth prompt with a retryable message, guarded by address and request identity. The final successful runs cover cancellation as well as independent authentication. They use one synthetic Basic-auth HTTPS origin, and do not prove real-account, arbitrary authentication-scheme or password-provider behavior.

## Final main applications and Android capture

The actual `lib/main.dart` debug applications built successfully after source freeze: Android **23.0 seconds** (`phase3-main-android.log`) and iOS simulator **44.2 seconds** (`phase3-main-ios.log`). Builds use the current library, Reader, native lifecycle and ad-policy wiring. Installation replaces the app without uninstalling user data.

The final Android app was launched on the dedicated emulator. The window dump confirms Wingman's activity is visible, has a drawn surface, and carries `SECURE` (`phase3-android-window-state.txt`). An actual adb screenshot then showed a black app surface, matching Android's capture restriction; see [the captured result](../screenshots/android-phase3-secure.png). This verifies emulator screenshot enforcement in addition to the normal/private flag fixture. It does not establish physical/OEM behavior or protect against an external camera. The screenshot deliberately cannot serve as a visual review of Wingman's UI.

iOS main-app manual checks are now in progress through the Simulator UI. The actual system Files import picker opened Wingman Browser's Documents folder and selected the synthetic `Wingman-Phase3-Fixture.html`. The app preview showed **2 new, 1 duplicate, 2 rejected**; confirming Import 2 saved the two valid bookmarks. This is a **simulator pass** for the native picker, preview and confirmed import flow.

The export confirmation opened the actual iOS share sheet with a **387-byte** HTML file. Save to Files saved `Documents/wingman-bookmarks.html` under Wingman Browser. A bounded read of only that exported file verified its size is exactly **387 bytes**, it contains exactly the two expected synthetic HTTP(S) links (including the preserved query string), and the script-shaped bookmark title is escaped as `&lt;script&gt;inert title&lt;/script&gt;` with **zero script elements**. This is a **simulator pass** for confirmed export, the native share sheet, Save to Files and the actual resulting file. No other user files were inspected.

The normal local article then opened through the actual menu's Open Reader action. Reader displayed the heading, all three visible paragraphs and the source address, with neither the textarea marker nor the hidden marker present. Two Larger text taps visibly increased Reader's font size. This is a **simulator pass** for the main-app Reader flow and Reader text controls; it is separate from the native website-page-size API fixture.

A new private tab loaded the same synthetic article with `?private-fixture=1`. Using Simulator Device → App Switcher performed a real OS transition. The visible portion of Wingman's overlapping card was opaque neutral white, with no page content visible in that portion. **Only the right portion of the card was visible because other cards overlapped it**, so this observation does not establish full-card coverage, snapshot timing, every transition or physical-device behavior. Returning restored the private page; closing that private tab left the normal page intact with one tab.

After the private close, a read-only query of the actual main-app SQLite database returned **zero** `private-fixture=1` rows in both `tabs` and `history`, and **one** normal synthetic article row in each table. Only these synthetic marker counts were output; no unrelated user data was inspected or exported. This verifies app-owned saved tab/history exclusion for that manual private session, not absence from every OS cache or third-party service.

The host-screen lock that initially prevented manual interaction was resolved before these checks. These simulator checks do not establish physical-device, complete snapshot-timing or every third-party Files-provider coverage.

## Matching after-change performance

The same debug fixture passed in 18 seconds plus 1 second teardown (`phase3-performance-android-after.log`), with no concurrent heavy build during the timed portion. No production optimization claim follows from one run on a loaded development Mac.

| Measurement | Before | After |
|---|---:|---:|
| Native SQLite evaluation p50 / p95 | 432.583 / 4,655.875 µs | 179.584 / 2,022.416 µs |
| Idle main-process PSS | 309,280 KB | 340,690 KB |
| Three-view main-process PSS | 351,018 KB | 363,392 KB |
| Three-view minus idle main-process PSS | 41,738 KB | 22,702 KB |
| Available guest memory, idle / three views | 689 / 641 MB | 679 / 621 MB |
| Three loopback page loads | 1,215 / 156 / 339 ms | 1,081 / 137 / 311 ms |
| Debug tester-pump switch p50 / p95 | 66.691 / 112.790 ms | 76.924 / 137.253 ms |

The after run used 19,155.69 MB of host swap. Native lookup time was lower in this sample, while absolute main-process memory and debug switching time were higher. The work does not claim a measured production speedup, production regression percentage or smoothness on a physical 2 GB phone. Both runs have the same debug, small-sample and missing renderer-memory limitations. The attempted adb process-tree snapshot occurred after the test had exited and returned no process, so it supplies no additional memory evidence.

A requested quiet repeat with unchanged functionality passed in 19 seconds plus 1 second teardown (`phase3-performance-android-repeat.log`). It measured native lookup p50/p95 **525.584 / 4,929.792 µs**, idle main-process PSS **350,026 KB**, three-view PSS **355,173 KB**, available guest memory **660 / 633 MB**, loopback loads **1,742 / 102 / 303 ms**, and debug switch p50/p95 **69.518 / 100.645 ms**. Host swap was 18,855.38 MB.

The repeat's switch p95 was lower than the baseline's 112.790 ms, so the first after run's approximately 22% increase was not repeatable. Native lookup times also varied substantially, preventing a one-run speedup claim. Idle PSS remained higher than the baseline in both after runs and is an **unresolved measured increase**; it is not dismissed as proven noise. Three-view PSS was closer to the baseline on repeat (355,173 versus 351,018 KB). The idle snapshots are not controlled for GC, shared-page PSS distribution or release-mode startup, and the workstation remained under substantial swap pressure. More controlled profile/release and physical-device measurements are required before attributing the idle increase or calling production performance unchanged. The deterministic native WK retention-count fix is separately verified and does not depend on these Android timing comparisons.
