# Native Guard validation — 10 September 2026

Guard uses app-owned navigation callbacks, indexed local SQLite rules, and native tracker filtering. It does not install a JavaScript bridge, upload navigation URLs, collect page contents, or configure the advertising SDK's WebViews.

## Environment and build gate

The unchanged Phase 1 baseline passed Android debug (11.5 seconds), iOS simulator debug (17.6 seconds), 97 host tests, analyzer, and web build before Phase 2 edits. Initial Phase 2 native integration builds passed Android debug (28.5 seconds) and iOS simulator debug (36.5 seconds). Later native changes are compiled again by the integration runs below.

Android validation uses the dedicated API 36 emulator with Android System WebView and 1,971 MB guest-visible RAM. iOS validation uses the existing iPhone simulator. These are emulators, not physical low-end Android devices or older iPhones. No distribution signing, store entitlement, or production deployment is claimed.

## Automated native acceptance

`integration_test/guard_engine_test.dart` uses a local HTTP fixture and a separate temporary SQLite file. The test deliberately switches its Dart policy to allow for the native interception cases, so passing them requires the native layer to enforce the rule.

| Check | Android | iOS |
| --- | --- | --- |
| Typed blocked destination before creating a view | Pass | Pass |
| Main-frame clicked link, redirect, JavaScript navigation | Pass | Pass |
| `target=_blank` kept in current tab and blocked | Pass, actual test pointer gesture | Pass |
| Direct POST and 307 POST-preserving redirect | Pass | Pass |
| Exact-host, expiring one-time grant; signed malware remains mandatory | Pass | Pass |
| Private browser still applies Guard | Pass | Pass |
| Tracker script never reaches fixture server | Pass | Pass |
| Per-site tracker exception does not disable category rules | Pass | Pass |
| Native IDNA, IPv6, ambiguous numeric/invalid-host rejection | Pass | Pass |
| Separate malware, phishing, known harmful-download and executable-warning results | Pass | Pass |
| Policy changes while a created view waits to load: no network request | Pass | Pass |
| Older queued address cannot replace a newer address after policy retry | Pass | Pass |
| Same-target activation does not cancel a pending/issued load | Pass | Pass |

The final Guard suites, including custom-rule specificity and deterministic navigation races, passed on Android in nine seconds plus two seconds teardown and on iOS in eight seconds plus two seconds teardown. It recorded zero destination requests for the blocked routes before the explicit grant; the 307 redirect destination was not contacted in this tested provider. The tracker counter reported one blocked third-party script, and the server received the script only after the explicit tracking exception.

`integration_test/browser_engine_test.dart` also passed on final Android source (26 seconds plus one second teardown) and iOS (31 seconds plus two seconds teardown). The iOS rerun verified the repaired cache clear: all renderers close before one native-store deletion, avoiding repeated shared-cache removal while pages are live. These runs preserve normal/private cookie and local-storage isolation, cleanup, bounded live views, link navigation, SPA back/forward metadata, popup handling, iframe error containment, failed-address retry, and actual renderer termination/recovery.

Separate PIN tests exercised Android secure storage and iOS Keychain; their validation belongs to the PIN/UI report. Main application UI and incoming-intent acceptance are recorded separately from this engine fixture.

## Defense boundaries and limitations

- Native policy decisions read the active SQLite generation and matching host suffixes in one indexed query. IP addresses match exactly; multi-label domains never inherit a bare top-level suffix. More-specific matching hosts are considered first. No native hostname cache is retained, including for private sessions.
- The app supplies a database path only after its signed pack and indexed-row integrity verification. Native paths must remain inside the app's data container. Explicitly clearing that path releases the old database handle. A runtime SQLite lookup error returns a visible additional-check decision without an override, while custom blocks remain effective. Custom rules use the most-specific matching host; equal-host block wins. A child allow rule never removes an ancestor block or permits siblings. A policy update publishes a revision immediately and uses its own ordered native update queue. Creation, delegate decisions and final loads recheck that revision; stale opens retry only after current policy is installed. A deterministic pre-load pause fixture verifies that a newly blocked request reaches no server. A failed native policy synchronization stops and hides existing views and prevents new browsing until synchronization succeeds.
- Android `shouldOverrideUrlLoading` does not cover every app-initiated or POST request. Dart checks app-initiated loads; native `shouldInterceptRequest` checks main-frame requests; provisional content remains hidden until the committed destination passes the native policy. Android's public resource callback does not report every later redirect hop. The tested redirects were stopped before reaching the blocked host, but **across provider versions a destination may be contacted before the final-commit guard prevents its display**. Wingman does not promise network-level blocking of every redirect.
- iOS checks main-frame navigation actions and responses and checks the committed destination again. It forwards the official WebView plugin's other delegate callbacks. iOS test DOM clicks are used because Flutter-generated pointer events do not reliably enter embedded UIKit views; actual OS-level popup gestures were validated in Phase 1 and require separate manual acceptance after native changes.
- Native SafeSearch applies only to recognized GET search routes and supported standard ports, upgrading recognized HTTP requests to HTTPS and setting provider-specific strict parameters. It handles supported trailing-dot hosts. **POST bodies, unsupported regional search domains, search-provider policy changes, and encrypted page-internal queries are not rewritten.** SafeSearch is not a complete content classifier.
- Tracker rules are the attributed small EasyPrivacy third-party domain subset. Android blocks resources natively and batches aggregate counts without URLs. WKWebView uses a compiled, content-addressed `WKContentRuleList`; public APIs expose no reliable block-count callback, so iOS does not invent a number. A tracking exception affects this tracker list only. Site rules, TLS, threat checks, and app ad views are independent.
- TLS failures still cancel; mixed content and file/provider access remain restricted. Android awaits one-time supported Safe Browsing initialization and reports unavailability without disabling local rules. Android Safe Browsing hits return to safety with optional hit reporting disabled (`backToSafety(false)`). WebView metrics opt-out covers usage metrics, not all engine crash reports. WK fraudulent-website warnings remain enabled; Apple controls those warnings and does not expose Android's threat-classification callback. Wingman's signed local threat matches cannot be overridden by allow lists or one-time grants.
- A known harmful-download rule blocks before the normal download action. Executable file types/MIME types produce a caution, not a claim of malware; an unlocked user can approve that single download request. Lock state and rules are checked again after the prompt. Native platform downloads do not scan file contents; Android DownloadManager performs the eventual transfer, with platform-controlled redirect behavior. Saved downloads remain on disk when a private tab closes, as disclosed in the download prompt.

## Performance evidence and qualification

A synthetic, unsigned **debug-only** SQLite fixture contains 100,000 indexed domains (7,176,192 bytes). It is installed into a separate test path, never accepted by the production signed-pack importer, and removed at test completion. `guardBenchmarkForTesting` measures 1,000 varied native evaluations with `System.nanoTime`, excluding MethodChannel transport. The helper is gated by Android's debuggable app flag; iOS diagnostic helpers compile only in the Debug configuration. None are exposed to website JavaScript.

Under concurrent native build/test activity and approximately 21 GB of host swap in use, native lookup median was **1.725 ms**, p95 **11.239 ms**. Android's main-process PSS was **331,477 KB** before browser views and **334,803 KB** with three views (3,326 KB increase). This excludes separate WebView renderer memory; the attempted global `dumpsys meminfo` timed out, so a complete app-plus-renderer memory total is unavailable.

That stressed debug run loaded three local pages in 18.942/6.784/4.897 seconds and measured Flutter test-pump switch times of 280 ms median and 1,140 ms p95. These include debug/emulation/test synchronization overhead and cannot be presented as production UI latency or evidence of smooth performance. The three-view bound held. With concurrent builds stopped, a lookup-only rerun measured **0.509 ms median / 4.981 ms p95** for the first 1,000 evaluations and **0.122 ms / 0.308 ms** for a repeated 1,000 evaluations with SQLite pages warm (still no hostname cache). It passed in three seconds plus two seconds teardown. Physical-device profiling remains unverified; results are also qualified in [Guard performance](../GUARD_PERFORMANCE.md).

Logs are retained in the parent workspace's `work/phase2-*.log` files. Reproducible test sources and this report are committed with the application; device logs are development evidence, not application telemetry.

## Reproduce the native benchmark

The heavy benchmark is opt-in, so normal integration runs do not require a synthetic database. Use a dedicated emulator with the debug application installed. `tool/guard/create_native_benchmark.py /tmp/wingman-native-benchmark.db` creates the test fixture; the production importer rejects it because it has no signed release. Copy it through `adb shell run-as com.wingmanbrowser.wingman_browser` into the application's `databases/guard-native-perf.db` path, then run:

```sh
flutter test integration_test/guard_performance_test.dart -d emulator-5556 --no-pub --dart-define=RUN_GUARD_NATIVE_BENCHMARK=true --dart-define=LOOKUP_ONLY=true
```

Omit `LOOKUP_ONLY` to include the three-view memory/test-pump scenario. The test removes its synthetic database when complete. The latest native acceptance logs are `phase2-guard-races-android.log`, `phase2-guard-races-ios.log`, `phase2-browser-regression-android-final.log`, and `phase2-browser-regression-ios-final.log`; the quieter measurement is `phase2-guard-lookup-android-quiet.log`.
