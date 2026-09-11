# Launchpad site compatibility and provenance

Research date: **2026-09-11**. This document separates destination research from the capabilities of the installed Wingman application. A saved shortcut, catalog entry, familiar brand, educational purpose, category label, or research-browser success never grants content eligibility.

## Current enforceable boundary

Wingman can render eligible, signed, bundled plain-text resources and its own local tools. It cannot open live websites on Android, iOS, or the Web companion. `ContentEligibilityService` rejects every navigation operation with `blockUnsupportedCapability`, before considering a host or bundled record. `BrowserEnginePool` cannot allocate a content view, even when an old callback returns `allow`. Both native bridges reject retired navigation, script, download, authentication, and external-launch commands. No Flutter WebView plugin is installed.

The eight researched website candidates can therefore be retained only as **inactive local review records**. Nothing is submitted to a reviewer or service. Their address remains visible and editable; changing it does not retain an approval. The user can instead choose existing eligible offline articles and local tools for working shortcuts. Those are separate destinations, never silent substitutes for a website.

Relevant implementation: `lib/policy/policy_runtime.dart`, `lib/signature/launchpad/launchpad_eligibility.dart`, `lib/browser/browser_engine.dart`, `android/app/src/main/kotlin/com/wingmanbrowser/wingman_browser/MainActivity.kt`, and `ios/Runner/AppDelegate.swift`. Android production removes the Internet permission; debug/profile retain it for Flutter tooling and controlled test fixtures. The iOS system WebKit link serves legacy data removal, not website rendering.

## Candidate records

Each canonical root was checked against a current official response. Review dates describe provenance freshness, not a signed content approval. The starter metadata uses a 30-day editorial review window, ending 2026-10-11. Icons are packaged Wingman symbols or local initials; no favicon, title, screenshot, score, price, or article fetch occurs when adding or displaying a shortcut.

| Stable ID / name | Canonical URL and region | Narrow subject for a possible future review | Primary provenance |
| --- | --- | --- | --- |
| `espn` / ESPN | `https://www.espn.com/` · US English edition | Ordinary sports pages; no whole-host approval | [Official root](https://www.espn.com/), [NBA](https://www.espn.com/nba/), [Teams](https://www.espn.com/nba/teams) |
| `walmart` / Walmart | `https://www.walmart.com/` · US storefront; location/country choices may change the experience | A separately reviewed office-supplies journey | [Official root](https://www.walmart.com/), [Office Supplies](https://www.walmart.com/cp/office-supplies/1229749), [Notebooks & Pads](https://www.walmart.com/browse/office-supplies/notebooks-pads/1229749_4796182) |
| `target` / Target | `https://www.target.com/` · US storefront | Separately reviewed school/office supplies | [Official root](https://www.target.com/), [School & Office Supplies](https://www.target.com/c/school-office-supplies/-/N-5xsxr) |
| `best-buy` / Best Buy | `https://www.bestbuy.com/` · US storefront | Separately reviewed computer information or ordinary products | [Official root](https://www.bestbuy.com/), [Computers & Tablets](https://www.bestbuy.com/site/electronics/computers-pcs/abcat0500000.c?id=abcat0500000), [International orders](https://www.bestbuy.com/site/help-topics/international-orders/pcmcat204400050019.c?id=pcmcat204400050019&rdct=n) |
| `home-depot` / The Home Depot | `https://www.homedepot.com/` · US storefront; separate Canadian and Mexican sites | Separately reviewed project information or ordinary supplies | [Official root](https://www.homedepot.com/), [DIY Projects and Ideas](https://www.homedepot.com/c/diy_projects_and_ideas) |
| `wikipedia` / Wikipedia | `https://www.wikipedia.org/` · global language portal | An exact, separately reviewed encyclopedia revision | [Official language portal](https://www.wikipedia.org/), [Moon article](https://en.wikipedia.org/wiki/Moon) |
| `nasa` / NASA | `https://www.nasa.gov/` · US agency, public global information | An exact, separately reviewed science page | [Official root](https://www.nasa.gov/), [Earth's Moon](https://science.nasa.gov/moon/) |
| `khan-academy` / Khan Academy | `https://www.khanacademy.org/` · global; language/course availability varies | A separately reviewed lesson; interactive functionality needs independent work | [Official root](https://www.khanacademy.org/), [Arithmetic](https://www.khanacademy.org/math/arithmetic), [Official browser/device guidance](https://support.khanacademy.org/hc/en-us/articles/204795430-What-devices-and-browsers-work-best-for-Khan-Academy) |

These paths are research references, not a path allowlist, recommendation feed, capability configuration, or automatic source of app content.

## External research results

The following observations were made outside Wingman, using official website responses and, for the two required ordinary journeys, actual Chrome UI. No account was created or signed into, no permission or challenge was bypassed, and no purchase, cart change, advertising click, subscription, or notification action was performed. The two task-created Chrome tabs were closed afterward.

* **ESPN:** NBA → Teams rendered in Chrome; account, advertising, futures and ticket links coexist. The initial root text fetch encountered a JavaScript/robot-check page. [NBA source](https://www.espn.com/nba/)
* **Walmart:** Office Supplies → Notebooks & Pads rendered in Chrome without signing in. The category contains product grids, account controls and location-dependent presentation; its shared navigation includes alcohol. The notebooks view also exposed advertising/tracking destinations in product links. Neither category was approved or opened in Wingman. [Office Supplies](https://www.walmart.com/cp/office-supplies/1229749), [Notebooks & Pads](https://www.walmart.com/browse/office-supplies/notebooks-pads/1229749_4796182)
* **Target:** Official page responses include school/office supplies, product reviews and add-to-cart controls within broader retail navigation. The root also identifies sponsored material. This was a document-response review, not an interactive checkout or native compatibility test. [School & Office Supplies](https://www.target.com/c/school-office-supplies/-/N-5xsxr), [Official root](https://www.target.com/)
* **Best Buy:** Official responses include computer categories, dynamic offers, recommendations, accounts and memberships. Its international-order guidance describes delivery to US mailing addresses. No purchase or account journey was tested. [Computers & Tablets](https://www.bestbuy.com/site/electronics/computers-pcs/abcat0500000.c?id=abcat0500000), [International orders](https://www.bestbuy.com/site/help-topics/international-orders/pcmcat204400050019.c?id=pcmcat204400050019&rdct=n)
* **The Home Depot:** Public responses expose project guides alongside shopping, account and store-selection controls. The root warns that local prices and inventory can differ. No project page becomes approved merely because it sits beneath a DIY path. [DIY](https://www.homedepot.com/c/diy_projects_and_ideas), [Official root](https://www.homedepot.com/)
* **Wikipedia:** The language portal and English Moon article returned readable documents without an authentication step. The article contains linked topics, citations and media. Other topics, later revisions, external citations, account/edit operations and full-host content were not reviewed. [Portal](https://www.wikipedia.org/), [Moon](https://en.wikipedia.org/wiki/Moon)
* **NASA:** The official root and Moon page returned public information and links to imagery, interactive tools and other NASA services. Exact linked tools, media responses and external destinations were not validated. [Earth's Moon](https://science.nasa.gov/moon/)
* **Khan Academy:** Root and Arithmetic responses produced no extractable body in the research text tool. This does not prove an empty page in a full browser. Official guidance supports current Chrome, Firefox, Edge and Safari, including mobile browsing; that is not certification of an embedded Wingman renderer. Exercises, accounts and media were not exercised. [Supported browsers](https://support.khanacademy.org/hc/en-us/articles/204795660-Which-browsers-are-supported), [Device guidance](https://support.khanacademy.org/hc/en-us/articles/204795430-What-devices-and-browsers-work-best-for-Khan-Academy)

### Dependency evidence and unknowns

This is an inventory of **observed references**, not a complete network trace or an approved dependency set.

| Candidate | References observed in official responses / research UI | Not established |
| --- | --- | --- |
| ESPN | `a.espncdn.com`, `a1.espncdn.com`; third-party advertising frame/link in Chrome | Complete script/media/auth/advertising graph, per-response content, regional substitutions |
| Walmart | `i5.walmartimages.com`; same-host `/sp/track` product links in Chrome | Product/recommendation APIs, redirects, checkout/auth graph, country-specific changes |
| Target | `target.scene7.com`; account, cart and sponsored sections | Full API/identity/ad graph or every item/recommendation |
| Best Buy | `pisces.bbystatic.com`; account/membership controls | Full product, auth, checkout and recommendation graph |
| The Home Depot | `dam.thdstatic.com`, `assets.thdstatic.com`; store/cart controls | Full pricing, inventory, auth and checkout graph |
| Wikipedia | `upload.wikimedia.org`; language editions and external citations | Entire media corpus, later article revisions, user edits and every outbound target |
| NASA | `assets.science.nasa.gov`, `images-assets.nasa.gov`, linked `plus.nasa.gov` | Interactive-map/media behavior and complete third-party dependencies |
| Khan Academy | Official help identifies supported browsers; live lesson extraction was inconclusive | Full executable, media, exercise and identity dependencies |

The corresponding candidate links above are the sources for these observations. A dependency may be necessary for a page but still contain unreviewed content or tracking. It is not thereby an eligible top-level destination. No dependency host is granted access in this implementation.

## Why familiar hosts and path filters do not close the gap

The current implementation has no renderer and no mechanism to prove a live response, every nested resource, redirect, newly opened window, script-generated destination, form POST, service worker, download or external action eligible before consumption. A domain label or category URL does not add those mechanisms. Shared navigation, dynamic responses and third-party content require separate enforcement; removing a few links after display would be too late.

Official Android documentation explicitly excludes POST from `shouldOverrideUrlLoading`; `shouldInterceptRequest` does not receive JavaScript/blob URLs and observes only the initial URL in a resource redirect sequence. Consequently, reinstating one delegate and a list of trusted hosts would not establish the required boundary. [Android WebViewClient API](https://developer.android.com/reference/android/webkit/WebViewClient)

Apple exposes navigation decisions and compiled content-rule lists as separate WebKit APIs. Their existence is not evidence of a content-classification or provenance system in Wingman. No such live execution path is present or enabled here. [WKNavigationDelegate](https://developer.apple.com/documentation/webkit/wknavigationdelegate), [WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore)

For a future live-content milestone, prerequisites include exact content/resource approval semantics, an enforceable pre-consumption boundary for every request class, lifecycle/session identity, response/redirect changes, dependency isolation, threat controls, authentication and download boundaries, revocation/expiry, and adversarial native tests. Public-source research is only an input to that work. This Launchpad change does not authorize a new renderer, server proxy, host exemption, content fetcher, login flow or external-browser escape.

## Native verification

`integration_test/launchpad_native_test.dart` is the dedicated candidate test. It passed against the real signed bundled policy, current Launchpad eligibility, retired engine and actual native channel on both dedicated targets. It covered all eight canonical roots and ten neutral scoped journeys (18 addresses), including private mode, altered metadata, old allow payloads and direct native calls. Each platform rejected 252 raw native commands; the retired allow callback was never invoked and the Flutter WebView constructor channel was absent. A loopback positive control establishes the request counter; subsequent candidate/fixture actions must leave content-view and fixture-request counts at zero. That proves the tested boundary and the controlled counter, not a device-wide packet audit.

`integration_test/launchpad_app_test.dart` separately exercises actual `app.main`, native startup quarantine, the real signed policy and SQLite-backed owner state. Its UI journey pins and renames an eligible article, opens an explicit new catalog tab, creates/moves/reorders local records, retains a visibly inactive scoped website address, checks private Home isolation, then disposes and reopens the application root. This is a root/controller/SQLite restoration test, not a process-death claim. Cleanup removes only the exact synthetic records it created. If first use becomes completed, that monotonic setup transition is reported rather than resetting the owner's document.

Both run with `flutter test integration_test/<fixture>_test.dart --no-pub --no-uninstall -d <device>` in the consumer edition. The dedicated targets were checked again: Android `emulator-5556`, Android 16, System WebView 153.0.8010.36 (legacy-cleanup support only); iOS `C157677F-A33F-45B2-BFFB-F3DED552D4F4`, iPhone 17 Pro simulator on the installed iOS 26.3 runtime. These are emulator/simulator observations, not physical-device coverage.

| Platform / layer | Current Launchpad result | Evidence |
| --- | --- | --- |
| Official website research | Eight candidates reviewed; two ordinary journeys rendered externally | Primary links and Chrome observations above |
| Dart authoritative policy + Launchpad | PASS inside both actual native integrations; signed bundled positive control remains available, all live candidates denied | `integration_test/launchpad_native_test.dart` |
| Android emulator boundary | PASS: 18 addresses / 252 native denials / normal and private / views 0 / controlled requests 0; invocation 48.83 s | `work/launchpad-native-boundary-android.log` |
| iOS simulator boundary | PASS: same candidate and native assertions; invocation 51.01 s | `work/launchpad-native-boundary-ios.log` |
| Android actual main Launchpad | PASS: page pin, title edit, local open/new tab, folder/move/reorder, inactive address, private isolation, SQLite/root reopen, exact fixture cleanup | `work/launchpad-native-app-android-input-settled.log` |
| iOS actual main Launchpad | PASS: the same real app journey, durable choices, private isolation and exact fixture cleanup | `work/launchpad-native-app-ios.log` |
| Web companion | Live websites unsupported; editing and local tools tested separately | See Launchpad QA |
| Physical phones, authenticated sessions, purchases, full packet capture | Not tested | Explicitly outside these observations |

### Actual app observations

The Android real app run completed in 76.17 seconds, including build/install/test teardown; iOS completed in 93.81 seconds. Each used the existing installation and consumer edition. A single debug integration observation measured `app.main` to ready at 5,002 ms on Android and 1,974 ms on iOS; opening the explicit new catalog tab took 753 / 701 ms, and reopening the owner root took 1,331 / 489 ms. These are test-harness observations, not cold process startup, production performance guarantees or physical-device measurements.

Both actual app runs removed exactly two synthetic shortcuts and one synthetic folder. They verified that all unrelated original Launchpad fields survived. The first manual add legitimately changed first-use setup from not started to completed; the fixture did not reset that persisted state. The initial Android attempt is retained as `work/launchpad-native-app-android.log`: its Save action missed because native keyboard movement put the button outside the viewport. The fixture now dismisses input, settles layout and requires a hittable control before tapping; the retry passed. No production capability or timeout was relaxed.

### Preserved security regressions

The existing handoff fixture passed start and resume as four separate native invocations with preserved installations. Android used distinct process IDs 31798 → 31956; iOS used 67987 → 68824. In each platform's guest view, owner widgets, editable/selectable text, content views and controlled network requests remained absent. Wrong owner codes were rejected; the correct code returned to the owner and durably cleared only the dedicated smoke gate. Both test gates ended inactive. Android also received actual targeted synthetic VIEW intents during guest mode and before restored initialization; none replayed into owner state after authentication. iOS exercised the Flutter deep-route/back path and native pending-link state, not an OS universal-link enrollment.

| Existing regression | Android | iOS |
| --- | --- | --- |
| Static handoff start | PASS, 51.64 s · `work/launchpad-native-handoff-android-start.log` | PASS, 43.55 s · `work/launchpad-native-handoff-ios-start.log` |
| Static handoff separate-process resume | PASS, 55.36 s · `work/launchpad-native-handoff-android-resume.log` | PASS, 41.26 s · `work/launchpad-native-handoff-ios-resume.log` |
| Actual protected app | PASS, Student edition, 49.67 s · `work/launchpad-native-protected-android.log` | PASS, consumer edition, 53.84 s · `work/launchpad-native-protected-ios.log` |
| Actual Signature app and SQLite/root reopen | PASS, 49.56 s · `work/launchpad-native-signature-android.log` | PASS, 53.14 s · `work/launchpad-native-signature-ios.log` |

All durations in this table include build, preserved installation and test teardown. These fixtures do not establish physical-device behavior, OS authentication integration, interactive website handoff or unrestricted incoming-link capability.

The protected-app regression retained all 18 reviewed resources, local search, bookmark/read-later behavior, a real two-tab catalog switch and locked mandatory controls. Rejected arbitrary addresses left no raw address on the blocked surface, zero content views and zero controlled requests. Its separate debug observations were Android main-to-settled 4,400 ms / tab switch 424.0 ms and iOS 1,549 ms / 361.1 ms; these are single fixture observations with the same measurement limits above.

The Signature regressions verified local analysis, three synthetic Spaces, a paused Finish task, saved analysis and the actual SQLite/application-root reopen. Both native database close callbacks returned on both platforms, with no outstanding close or startup bridge call. The iOS run also verified the successful startup-quarantine receipt: one actual completed purge (421 ms), a 0 ms acknowledged reuse on owner-root reopening and no live content writers/views. This does not replace a future fresh-process purge. Signature timings were Android main-to-tools 4,447 ms / analysis 17 ms / root reopen 1,148 ms and iOS 1,829 / 9 / 479 ms, again single debug observations. Test-owned Spaces/task/analysis were removed by the fixture's exact-ID cleanup.

**Native acceptance:** all 12 planned checks passed across the dedicated Android emulator and iOS simulator. There were 13 invocations because the first new Android app fixture had the documented IME hit-test failure and was rerun with corrected test synchronization. No native production code, permission, content allow, request timeout or security boundary changed for these runs. The final existing Signature regressions compiled the last Organize UI refinement; its keyboard behavior also has dedicated host tests and separate Web QA.

### Final main artifacts

After all integration invocations, the standard paths were restored with normal **consumer `lib/main.dart`** debug builds, installed over the existing app and launched successfully on both dedicated devices. These restore/install commands are not additional integration-test passes.

| Final artifact | Build / install / launch evidence |
| --- | --- |
| Android `build/app/outputs/flutter-apk/app-debug.apk` | Gradle 17.7 s; build command wall 20.90 s; preserved install and `am start` returned success · `work/launchpad-main-android.log` |
| iOS `build/ios/iphonesimulator/Runner.app` | Xcode 24.6 s; build command wall 34.39 s; preserved install and launch returned success · `work/launchpad-main-ios.log` |

The Android APK SHA-256 is `59d89c55c2ab6a714982f4ff365e066e9cf3b5600f8a83ff53986d8240401f22`. Final restore commands and timings are also recorded in the corresponding `work/launchpad-main-*.json` files; version/hash metadata is in `work/launchpad-main-artifact-summary.json`. Android `am start` measures OS launch delivery, not rendered-app readiness. No release APK, signed iOS archive, store distribution, physical-device result or deployment is claimed.
