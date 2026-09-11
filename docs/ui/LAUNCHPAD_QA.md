# Launchpad QA and preview

This report covers the actual Flutter application at `lib/main.dart`, extending the existing Home. It separates automated widget evidence, native runtime observations, external website research and the Web companion. It does not treat a saved website tile or a successful build as proof of live website support.

## Starting state and environment

Repository: `/Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser`. Clean `main` and `origin/main` started at `e93fc0e754bbc86ef205c26bf15d45480fa53689`; work continues locally on `launchpad/implementation`. Earlier UI handoff and permanent-protection changes were already merged before this milestone. No reset to the older remote observation occurred. No push, publication, deployment, purchase or external message is part of this milestone.

Toolchain: Flutter 3.44.4, Dart 3.12.2, Xcode 26.3 (17C529), macOS 15.7.4 arm64. Android uses the dedicated `emulator-5556` (API 36); iOS uses `C157677F-A33F-45B2-BFFB-F3DED552D4F4` (iPhone 17 Pro, iOS 26.3 simulator). `emulator-5554` was not touched. App version is 0.7.0+7. No Flutter, native-engine, SDK or package upgrade was made.

Before editing, analysis was clean, 431 tests passed with two optional benchmarks skipped, and Android debug, iOS Simulator debug and Web release builds passed. Exact baseline durations are in [LAUNCHPAD_STATUS.md](LAUNCHPAD_STATUS.md). Local command logs are under `../../work/launchpad-*.log` relative to the repository root, with `launchpad-baseline-results.json` recording command arrays, exit codes and wall times.

## Test evidence

The final host gate passed after the keyboard identity, delayed-write and stable Organize-panel corrections:

| Check | Result | Tool / wall time |
|---|---|---|
| `flutter analyze --no-pub` | Clean | 2.4 / 3.70 s |
| `flutter test --no-pub --dart-define=WINGMAN_CAPTURE_LAUNCHPAD=true` | **486 passed, 2 optional skips** | 39 / 42.63 s |
| `flutter build web --release --no-pub --no-web-resources-cdn --no-tree-shake-icons` | Built `build/web` | 30.9 / 31.54 s |
| `flutter build apk --debug --no-pub` | Built normal consumer `app-debug.apk` | 17.7 / 20.90 s |
| `flutter build ios --simulator --debug --no-pub` | Built normal consumer `Runner.app` | 24.6 / 34.39 s |

Logs: `../../work/launchpad-final5-{analyze,test,web}.log`; exact command arrays, exit codes and wall times: `../../work/launchpad-final-host-results.json`, relative to the repository root. The capture flag only regenerates local synthetic widget PNGs; it does not change app policy, enable networking or bypass native capture protection.

After all native fixtures, both platforms were rebuilt from the ordinary `lib/main.dart` entry point and installed over their existing installations. Android used `adb -s emulator-5556 install -r`; iOS used `xcrun simctl install` for the dedicated simulator. Both normal consumer apps then launched successfully. Build/install/launch command arrays and exit codes are recorded in `../../work/launchpad-main-{android,ios}.json` and matching logs. The final APK SHA-256 is `59d89c55c2ab6a714982f4ff365e066e9cf3b5600f8a83ff53986d8240401f22`. Native artifacts are local build output, excluded from Git.

Coverage within that combined suite:

| Area | Evidence |
|---|---|
| Models, persistence and current authority | 25 new Launchpad tests plus 8 existing SignatureServices tests. Strict data/schema bounds, once-only atomic migration, read/write failures, meaningful URL differences, duplicate handling, catalog provenance invalidation, canceled/stale writes, folders, non-drag ordering, undo/replay guards and real signed-policy revocation. The last three tests prove explicit local clearing, preservation on failure/cancel, no legacy reseeding or stale undo after clear, and unrelated/private document separation. |
| Real Shell navigation | Eight new cases: explicit current-page pin/bookmark separation, rejection of a stale committed page, actual new app tab/trail, forced website/additional-restriction denial, private Home separation, Library pin ownership, selected-Space save with policy revocation during its picker, and preview/cancel/clear of Launchpad alone. |
| Launchpad widgets | 20 functional cases and 2 independently mounted layout matrices (192 render states). Includes actual Tab/Enter, the stable Organize panel, delayed-write duplicate suppression and focused action identity in the Flutter widget tree, both nonempty-folder deletion choices, stale route/background cancellation, collections, revoked-source removal, restoration confirmation and local field handling. |
| Existing Home/session regressions | Layout/search semantics, preference reset, welcome and workspace navigation races passed. The deliberate compact heading change required updating an old forced-newline expectation in both the Shell and native protected fixtures; protection assertions remain intact. |

Two optional benchmark skips are expected without `GUARD_BENCHMARK` and `WINGMAN_CATALOG_BENCHMARK`. They are not functional test passes. No physical-device, store-review, release-signing, authenticated shopping or whole-device packet-audit acceptance is claimed.

## Native application runs

The two new integration fixtures run with `--no-uninstall`, preserving the installed app's data. The application fixture uses the real `main.dart`, actual signed policy, platform SQLite adapter, UI actions and a full root disposal/reopen. It creates uniquely named test records and removes only its two shortcuts and one folder, checking all unrelated original fields afterward. Successful first addition may legitimately move first-use setup from not-started to completed; the test records that transition instead of resetting the document.

| Fixture | Android emulator | iOS simulator |
|---|---|---|
| `launchpad_native_test.dart` | Passed; 48.83 s command wall time | Passed; 51.01 s command wall time |
| `launchpad_app_test.dart` | Passed; 76.17 s command wall time | Passed; 93.81 s command wall time |

Both app runs verified current-page pin, rename, actual in-app article/new-tab opening, folder creation/move, saved ordering, an explicitly inactive ESPN address, private owner-data exclusion and durable root reopen, with no live content view. One initial Android app-fixture tap missed a Save button after the IME moved the viewport. Its failed log is retained; the test helper now settles and hides test input before requiring a hittable control. No production keyboard gate or policy was weakened to make that test pass.

Single debug-integration observations, not cold-start or performance guarantees: Android main-to-ready 5,002 ms, new article tab 753 ms and root reopen 1,331 ms; iOS 1,974 / 701 / 489 ms respectively.

The existing security and connected-feature fixtures also passed:

| Existing fixture | Android command wall time | iOS command wall time |
|---|---|---|
| Static handoff start | 51.64 s | 43.55 s |
| Handoff separate-process resume | 55.36 s | 41.26 s |
| Actual protected app | 49.67 s, Student edition | 53.84 s, consumer edition |
| Actual Signature app and SQLite/root reopen | 49.56 s | 53.14 s |

All **12 planned native checks passed** across the two targets. The retained initial IME fixture failure makes 13 total invocations. The four handoff runs used distinct start/resume processes, excluded owner widgets/input/content views, rejected wrong return codes, accepted the correct code and left the dedicated test gates inactive. Targeted Android synthetic VIEW intents and the iOS Flutter deep-route/native pending-link checks did not replay guest links into owner state. Protected-app checks retained all 18 resources, search, saved articles, two-tab navigation and locked mandatory controls with zero content views/controlled requests. Signature checks exercised three Spaces, a task, local terms analysis and durable SQLite/root reopen, then cleaned up only their own fixtures. Both platforms completed their database close callbacks without pending native calls.

Exact commands, results and observations are retained in `../../work/launchpad-native-*.log` and adjacent JSON files. [Site compatibility](LAUNCHPAD_SITE_COMPATIBILITY.md) maps each native fixture to its log and platform. These checks retain the existing native capture and startup quarantine protections.

## Privacy and capability evidence

Launchpad models and widgets use the existing local document store, Flutter text and bundled Material symbols/initials. The new modules contain no HTTP client, remote image provider, DNS lookup, favicon service, preview fetch, preconnect, hidden WebView, analytics SDK, account service or upload path. The address editor normalizes locally, disables text suggestions/personalized IME hints and uses the existing safe text-selection menu. These findings describe app behavior; they do not certify an operating-system keyboard or host-browser extension.

The normal document contains preferences only. Policy decisions are never serialized as shortcut authority. Additional restrictions, catalog validity, current session and renderer capability are rechecked at the relevant save/open boundary. Private/student/unknown-edition controllers use memory storage before reading any owner document. Owner return from Hand It Over retains the existing quarantine and native capture coverage.

The candidate native fixture passed on both targets. It includes a positive loopback counter control and tests the retired engine/native bridge without allocating content views: eight candidates, 18 canonical/scoped addresses and 252 raw native denials on each platform. Both reported zero content views and zero subsequent fixture requests. Its zero-request claim is limited to that controlled fixture, not all traffic produced by an emulator, iOS, Flutter debug tooling, a host browser or external research.

## Website compatibility

The catalog has 34 suggestions with the current signed library: 8 local Wingman tools, 18 reviewed original offline articles and 8 individually researched website candidates. Eligible tools/articles open through the real Shell pipeline. The eight websites require explicit consent to save as inactive local records; nothing is submitted. ESPN NBA → Teams and Walmart Office Supplies → Notebooks & Pads rendered in the independent research browser. Neither has a supported live route in Wingman because there is no live renderer or enforceable positive eligibility for all dynamic content and dependencies. See [the detailed compatibility report](LAUNCHPAD_SITE_COMPATIBILITY.md) for exact paths, observed mixed content, scope and platform results.

No new live scores, prices, headlines, feed refresh, scraping, remote artwork or approved-host list was introduced. Sports, Shopping and Learning are optional finite source collections chosen by the user; they do not change a destination's content classification.

## Actual UI evidence

[Baseline Web Home](launchpad-screenshots/baseline-web-home-dark.png) records the old running UI before the Launchpad build. Actual release Web tests used a separate local origin, `http://127.0.0.1:58351/`, so synthetic selections did not change the existing preview's saved favorites. The existing preview on port 8791 was only reloaded to the new application. The temporary test origin used the same `build/web` files and did not publish anything externally. Its tab and task-owned server were closed after verification, and the viewport override was reset. The user's preview remains available on port 8791.

The walkthrough selected six resources/tools at once, created Weekend reading, moved its Moon shortcut into the folder, reordered the folder, removed and undid one shortcut, entered `espn.com/nba/`, chose a local icon and explicitly acknowledged its inactive state. The saved normalized address stayed visible and its Open control stayed disabled. Learning sources were chosen explicitly and remained distinct from shortcuts. Reload restored the selected tools, exact order, folder contents, inactive record, theme and two chosen sources. Opening the Moon article in a new app session rendered the actual signed article and changed the app-session count to two. A newly created private Home showed none of the owner shortcuts, folder name or selected content; closing that private session returned to the unchanged normal choices. Browser warning/error inspection returned no entries during this walkthrough.

Final release Web keyboard testing used Tab to reach the folder's **Organize** action and Enter to open its single-item panel. Tab then reached Move up. The first Enter moved Weekend reading from third to second among its siblings while retaining the same actual DOM button and accessibility focus; a second Enter moved it to first and correctly disabled further upward movement. These controls stay in place, so consecutive moves work without dragging. In the full-list Web manager, moving a whole row can cause the browser to drop DOM focus even when Flutter retains its FocusNode; the UI explicitly directs consecutive keyboard moves through Organize. No SDK patch, browser-focus script or direct DOM modification was introduced.

| Actual release Web capture | Size / scope |
|---|---|
| [Light phone Home](launchpad-screenshots/web-home-light-phone.png) | 390 × 844; four ordinary-phone columns, one omnibox and original Web companion dock |
| [Dark phone Home](launchpad-screenshots/web-home-dark-phone.png) | 390 × 844; same selected data and distinct inactive label |
| [Dark narrow Home](launchpad-screenshots/web-home-dark-narrow.png) | 320 × 700; two columns and wrapped Add/Edit controls |
| [Dark tablet Home](launchpad-screenshots/web-home-dark-tablet.png) | 768 × 1024; navigation rail and chosen finite source cards |
| [Light wide Home](launchpad-screenshots/web-home-light-wide.png) | 1280 × 800; constrained content width and navigation rail |
| [Dark wide Home](launchpad-screenshots/web-home-dark-wide.png) | 1280 × 720; same content at wide width |
| [Private Home](launchpad-screenshots/web-private-home-light.png) | 390 × 844; separate empty Launchpad, explicit private label |
| [Keyboard organization](launchpad-screenshots/web-organize-keyboard.png) | 1280 × 800; actual Move up focus retained after the first keyboard move |

The 12 independently mounted widget captures and 192 layout states are detailed in [LAUNCHPAD_UI_QA.md](LAUNCHPAD_UI_QA.md). They cover grid, editor, manager, suggestions, customization and collections in both themes at eight widths and 100%/200% text. An early harness retained its first Navigator route; exact-scene assertions and full unmounting fixed that harness, and all mislabeled captures were replaced. The final editor guidance wraps instead of truncating. Actual Web resizing was allowed to finish before saving each image; an initial transition-frame phone capture was replaced.

Accessibility evidence includes the real Web accessibility tree, explicit destination/state labels, keyboard Tab/Enter interaction, non-drag controls, four-column/minimum-target assertions and large-text widget reflow. Native screen-capture restrictions remain enabled; host-rendered synthetic captures are not screenshots from protected native windows. A full human TalkBack/VoiceOver session and physical-phone visual acceptance remain untested.

## Preview commands

From the repository above:

```sh
flutter pub get
flutter run -d emulator-5556
```

For the inspected iOS simulator:

```sh
flutter run -d C157677F-A33F-45B2-BFFB-F3DED552D4F4
```

For a standalone local Web build, stop any existing server on port 8791 before starting another:

```sh
flutter build web --release --no-web-resources-cdn --no-tree-shake-icons
python3 -m http.server 8791 --bind 127.0.0.1 --directory build/web
```

Open [the local Web companion](http://127.0.0.1:8791/). Its sessions are app sessions, not host-browser tabs; it does not filter the host browser. Source changes require rebuilding that static preview. For an attached hot-reload workflow, use `flutter run -d chrome --web-port=8792` with an installed supported Chrome target.

## Change inventory

The implementation adds `lib/signature/launchpad/` for typed records, local catalog, eligibility and queued persistence; `lib/presentation/launchpad/` for the real Home grid, catalog/editor, folder management, collections and customization; and focused core, widget and native fixtures. It integrates `SignatureServices`, the existing document namespace, app initialization, BrowserShell, Home, Library and the existing Spaces/Finish Mode page. It updates version metadata, README, two deliberate Home goldens and heading expectations, plus the four Launchpad documents and actual captures. The committed UI handoff, policy catalog signatures, native renderer denial, Android/iOS security settings and dependency versions are unchanged.
