# Protected visual browsing QA

Validation date: September 11, 2026. Version: **0.8.0+8**. This is a native visual-browsing pilot with a separately bounded web companion. Scope and remaining product limitations are in [Live browsing status](LIVE_BROWSING_STATUS.md).

## Scope under test

Three enabled sources contain six exact reviewed documents and 612 passive resource addresses. The bundled manifest is 289,663 bytes, expires October 11, 2026 at 00:00 UTC, and has matching Dart/Kotlin/Swift SHA-256 pins. The privacy subset contains 2,501 third-party domain rules. No whole domain, script engine, external application, login or checkout flow is granted by the manifest.

No Firebase/GCP deployment or new paid service was needed or created. Infrastructure inspection used read-only metadata operations; this report is not an audit of existing account spend.

## Host and companion evidence

The final complete host suite passed **528 tests with two optional skips**. This includes the expanded 17-test policy suite, native-event generation/ownership tests, runtime capability and expiry checks, actual Shell routing/revocation checks, local artwork persistence/private isolation and responsive UI tests. The menu-pin regression also passed.

The final `flutter analyze --no-pub` passed in 3.82 seconds. The full host run took 42.58 seconds. After correcting two stale private-tab/About sentences, the existing Shell visual, Settings/Library/Protection and live Shell suites passed all 24 tests in 7.07 seconds. The final `flutter build web --no-pub --no-web-resources-cdn` passed in 27.44 seconds. These are individual local observations, not performance guarantees. The rebuilt companion at port 8791 was inspected through its actual browser UI: the new local photo cards and credits appeared, the nature card opened its reviewed article, Home navigation returned correctly, and the browser console had no errors or warnings. The final refreshed build also showed its Home content without console errors or warnings. Saved customization was not changed for this inspection. Light/dark Home golden differences were visually reviewed and updated for the intentional discovery section. Discovery tests exercise 24 width/theme/text-size combinations.

## Native evidence and interpretation

Device targets are a dedicated Android 16 / API 36 emulator with WebView 153.0.8010.36 and a dedicated iPhone 17 Pro / iOS 26.3 simulator. These are development observations, not physical-device certification or production performance guarantees. Final fixtures use `--no-uninstall`; test-owned saved records are removed individually and unrelated saved fields are checked against the starting state of each actual-app fixture. An earlier bridge-only Android retry omitted that flag and uninstalled its test application from the dedicated emulator; preservation is not claimed for that installation. The separate user emulator was not targeted.

The independent bridge fixture opens NASA Moon facts, Wikipedia Chicago Bulls and Adafruit product 64 in both normal and private modes, plus NASA Moon overview. It requires page completion, disabled page JavaScript and image evidence, exercises 19 unsupported/forged operations with zero requests to a controlled forbidden endpoint, and checks suspend/handoff teardown. Original unrestricted channels remain denied.

Android's image evidence is bounded bitmap decoding of actual intercepted image responses. Its disabled page JavaScript also prevents DOM image inspection, so unavailable DOM counts are not reported as zero or as a rendering pass. iOS's fixed read-only native probe checks actual `document.images` completion/natural width without enabling page scripts. iOS does not report Android's subresource response/byte counters. Native capture protections remain enabled during visual inspection.

Final seven-page bridge runs passed on both platforms after tightening stale callback ownership, native input actions, iOS common rule preparation and Android profile purging:

- Android: the final fixture passed in approximately 18 seconds with `engineNetworkBlocked=true` on all seven pages. Normal NASA/Wikipedia/Adafruit/overview opens decoded 14/40/16/31 image responses; private NASA/Wikipedia/Adafruit decoded 14/39/16. Fetched response bodies stayed at or below 12 MiB and native network fetches at or below 80 per open. Final teardown reported zero renderers, zero pending purges, seven completed purges and no purge failure. Seven empty disposable profile names remain registered until the next process startup; completed data purging is not immediate profile-name removal. Evidence: `work/live-native-network-disabled-android-test.log` in the task workspace; the earlier explicit-purge run also passed in `work/live-native-profile-purge-android-test.log`.
- iOS: 29.4-second test build and approximately 73-second fixture, including 60 seconds reserved for attempted captures. Normal NASA/Wikipedia/Adafruit/overview pages reported 12/3/9/3 decoded DOM images and 7/2/3/7 external style sheets. Private NASA/Wikipedia/Adafruit reported 4/3/9 images and 7/2/3 style sheets. All had page JavaScript disabled, and both fixtures passed the 19 denials, zero controlled forbidden requests and immediate suspend/handoff teardown. Private visits did not increase iOS rule-compilation counts.

The fixed native user agent now produces the reviewed Wikipedia HTML and loads its two external style sheets. Fresh native screenshots could not be captured because the Mac was locked and automatic unlock was unavailable. Earlier screenshots of the unstyled response do not validate the current layout. Runtime image/style evidence is recorded above; fresh native visual review remains open.

The actual `app.main()` fixture **passed on Android and iOS**. It enters a reviewed NASA address through Home search, waits for native loading and completion, saves a committed-page Launchpad pin, verifies its exact target and `currentPage` source, opens the saved target in a new tab, and applies an additional restriction. Revocation removes the native surface and a forced reopen shows the policy denial. Finally it removes only its marked test pin, restores the test scope's previous restriction and compares unrelated saved Launchpad fields with the fixture's starting state. The final Android build/runtime were 16.1/18 seconds with renderer-owned network loads disabled; iOS's were 24.0/10 seconds. Evidence: `work/live-native-network-disabled-app-android-test.log` and `work/live-native-app-ios-test.log`. The earlier Android attempt failed before navigation because its helper entered text before the search route mounted; the fixture now waits for mounted, hit-testable fields. No production check was relaxed.

The production-rule WebKit XCTest **passed** on the dedicated iOS simulator (test body 2.051 seconds; xcodebuild exit 0). Its request-counting loopback server observed one allowed HTML, stylesheet, PNG and initial redirect request. The allowed PNG decoded at four pixels; an exact percent-encoded query stylesheet loaded and applied its sans-serif rule. The forbidden redirect target, direct unknown image, stylesheet, CSS background, iframe and script each received zero requests. This is real WebKit behavior with the production rule builder, not a simulated Dart policy decision. The fixture enables no production localhost exception. An earlier test assumption about image scale was corrected to produce four physical pixels explicitly.

All eight existing native regression invocations passed: `protected_app`, `guard_engine`, `browser_engine` and `handoff_security` on each dedicated platform. The guard fixture rejected 140 raw methods; the retired browser fixture observed zero website requests and renderers; the full handoff fixture passed. The command for each was `flutter test --no-pub integration_test/<fixture>_test.dart -d <device> --no-uninstall`. Logs are `work/live-regression-<android|ios>-<fixture>.log` in the task workspace. These checks retain the retired API boundary while the new reviewed bridge is present.

## Network fallback and speculation limits

Android sets `blockNetworkLoads=true` in addition to returning a response for every interception. The permitted bytes come from Wingman's independently bounded native fetcher. Chromium's reviewed source applies cache-only flags to normal HTTP(S) network loads while still accepting supplied interception responses: [network flags](https://chromium.googlesource.com/chromium/src/+/8079a9879d3172afc081e3794c5c388650f89cdc/android_webview/browser/network_service/net_helpers.cc#86), [interception ordering](https://chromium.googlesource.com/chromium/src/+/8079a9879d3172afc081e3794c5c388650f89cdc/android_webview/browser/network_service/aw_proxying_url_loader_factory.cc#390). This is additional fallback protection, not proof that every speculative DNS/TLS operation is absent.

WebKit's reviewed upstream [preconnect path](https://github.com/WebKit/WebKit/blob/5ed89fc0abf85e2613cd16c9c16ac66c6d64e17d/Source/WebCore/loader/LinkLoader.cpp#L345) and [DNS-prefetch path](https://github.com/WebKit/WebKit/blob/5ed89fc0abf85e2613cd16c9c16ac66c6d64e17d/Source/WebCore/loader/FrameLoader.cpp#L5191) consult content rules as `Ping` requests; the pilot provides no Ping exception to its default block. These pinned upstream sources do not establish which exact revisions ship in the installed providers. Device fixture observations and a complete packet audit remain distinct; the latter has not been performed.

## Regression fixes made during validation

- Detached and closed replaced Flutter platform-view IDs; reject stale renderer events by generation.
- Prevented an older denied-open completion from overwriting a newer page state.
- Preserved the verified page snapshot for an explicit menu pin while route transitions destroy/recreate its renderer; new navigation or policy changes invalidate the action.
- Removed stale-view Android resource callbacks from the current page's request accounting and failure path.
- Kept unrelated method errors from releasing native data-cleanup barriers.
- Prepared every enabled iOS public rule list at startup, so a private first visit does not compile a site-specific persistent artifact.
- Restricted iOS live capability to 18.4+ for the public file-picker denial delegate and disabled external text-selection actions.
- Distinguished Android browsing-data purge completion from process-lifetime profile-name removal.
- Disabled Android renderer-owned network loading while retaining tested responses from the checked native fetcher.

## Ordinary local builds

Both ordinary main-entry builds passed and include the final source and copy:

```sh
flutter build apk --debug --no-pub --target lib/main.dart
flutter build ios --simulator --debug --no-pub --target lib/main.dart
```

Android built in 14.1 seconds; iOS in 21.9 seconds. The builds contain no integration-test entry point or visual-capture pause define. Version is **0.8.0+8**. The debug APK is `build/app/outputs/flutter-apk/app-debug.apk`, 188,730,912 bytes, SHA-256 `4f08dfabb29306bd988563799d9c74705536b3307e7c72dcd6b01e81f2778787`. The iOS simulator bundle is `build/ios/iphonesimulator/Runner.app`. These generated artifacts are local and ignored by Git.

The ordinary APK was installed as an upgrade and launched successfully only on dedicated emulator `emulator-5556`. The iOS app was installed and launched only on dedicated simulator `C157677F-A33F-45B2-BFFB-F3DED552D4F4`. Native capture protections were retained. Exact SDK install/launch commands and exit-zero receipts are in `work/live-native-delivery.json` in the task workspace. These are development builds; no store release or cloud deployment was performed.

## Release boundary

No automatic image/text classifier, general web search, interactive sites, signed remote live-policy publisher, production release signing, physical-device network audit or managed-school acceptance is established by these tests. ESPN/Walmart remain disabled candidates. User agents, response variants, markup and asset URLs can change; native visual inspection is required in addition to counters. Never relax the request boundary merely to improve a screenshot.
