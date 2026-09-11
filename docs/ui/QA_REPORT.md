# UI handoff QA and runnable review

**Status: UI milestone complete within the documented capability scope.431 host tests pass; native regression runs and all three final main builds pass.** This report records new application evidence; the reference package's QA JSON is not app-test evidence. The current production entrypoint is `lib/main.dart`, version **0.6.0+6**.

## Checkout and provenance

Repository: `/Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser`.

Started on `signature-features/consumer`, clean at `d5ca5ba7087e91f7f50b3b073960f7187a767e69`. Implementation branch: `ui-handoff/implementation`. Only the committed `Wingman_UI_Design_Handoff/` was retrieved from fetched `origin/main` at `a9b3765fc2d6f94d5d6185fedf8b66002da4ccfc`. Newer local 0.5 capabilities were preserved. No reset, second clone, dependency upgrade, remote merge, push, publication or production-service change occurred. Ending commit is recorded in the final response and repository history.

[CHANGED_FILES](CHANGED_FILES.md) lists every changed file from the starting commit. [Screenshot inventory](SCREENSHOT_MANIFEST.md) records each image’s actual dimensions and provenance.

The [51-row screen registry](SCREEN_REGISTRY.md) is the screen-by-screen implementation record. [UI_AUDIT](UI_AUDIT.md) preserves the starting capability audit; [DESIGN_SYSTEM](DESIGN_SYSTEM.md) documents the central components; [NAVIGATION](NAVIGATION.md) documents ownership and async behavior.

## Implemented product scope

| Feature | Actual supported behavior | Specific external/platform limit |
|---|---|---|
| Official Routes | Search/filter 18 reviewed identities, inspect exact evidence and scope, open separately eligible installed guides, prepare a reviewed local request draft | Identity is not a live-content grant; no submission endpoint |
| Before You Commit | Bounded local English analysis, six topics with exact excerpts/positions, explicit uncertainty, cancel/invalidate stale work, optional normal save/delete and reviewed export | No automatic upload, remote-page extraction, multilingual completeness or legal verdict |
| Your Spaces | Three chosen templates, durable notes/checklists/reviewed saves/topics, Home visibility/order, measurement utility and Sports source lookup | No inferred interests, network feeds or fabricated live scores |
| Finish Mode | Real task/checklist progress, current-tab ownership, pause/resume, explicit finish/save/close choices, unrelated tabs preserved and safe normal undo | Private closed tasks/tabs are never resurrected; no fabricated time saved |
| Hand It Over | Independent static shared view of 1–8 policy-pinned articles; fresh 8–12 digit return code; native secure marker and durable authenticated return | Unavailable on Web/private/unsupported secure storage; no device-wide kiosk, biometrics or live sites |
| Trust Receipt | Bounded coarse typed events, configured/observed/unobservable distinctions, detail, reviewed copy and clear | Not complete network instrumentation, browsing reconstruction or an automatic telemetry service |
| Compatibility Repair | Local issue selection, optional explicitly reviewed domain, minimal diagnostic preview/export, actual correction-registry status | No submission endpoint; current production correction registry is empty |

Home, focused search/results, five-position native dock, app-only Web navigation, grouped menu, tabs, Welcome, Library/Reader, Settings, Protection and privacy/data flows are connected to those same services. All themes use the central palette/local fonts. Home preferences are a bounded versioned document, saved before publication. No SQL schema bump is required.

## Protection and local-data review

The prior permanent-protection migration remains authoritative. No core allow-once, allowlist, private override, unrestricted URL importer, external-browser fallback or callable live-renderer bypass was introduced. Normal input, restored IDs, shortcuts, source guides, Reader, tasks and shared articles are re-evaluated by policy. Unknown/expired/revoked content stays closed. Earlier title/address metadata remains quarantined; only explicitly selected cleanup touches it.

The library is currently limited to **18 exact Ed25519-signed bundled original plaintext articles**. Their catalog version is 1.1.0, sequence2, with expiration March10,2027; runtime approval can become unavailable earlier. This is not comprehensive open-web protection. Connection security, organizational identity, content eligibility and compatibility remain different concepts. Live websites, unrestricted search, extracted website Reader, new downloads, per-site permissions and default-browser setup are unavailable. The UI makes these limits visible.

No account, school console, ads, sponsored/affiliate placement, analytics, replay, attribution, new SDK, cloud database or report endpoint was added. Normal notes/findings/settings remain local; private services are memory-only and never read owner documents. The native capture shields remain enabled. Explicit clipboard exports can be read by other software/OS services; they are never automatically sent. Existing conditional Flutter Unicode fallback can contact the font CDN, so no universal zero-network claim is made.

Final review found and corrected delayed preference overwrites, stale optional-boundary toggles, silent dropping of retired saved IDs, stale menu actions after an originating tab closes, and late clear-data route/disposal races. Retired IDs remain bounded opaque IDs and require explicit redacted cleanup. Clearing selected categories reports actual per-category results, preserves unrelated/new tabs, and continues observing a retained pending native operation rather than treating a timeout as success. Closing a private origin removes its feature stack and notes dialog before destroying its ephemeral service.

## Tooling and fresh baseline

Host macOS15.7.4 arm64; Flutter3.44.4/ad70ec4617, Dart3.12.2, engine a10d8ac38d. Android Studio JDK21.0.9 (app Java/Kotlin17); Android SDK/build tools36.1.0. Xcode26.3/17C529; CocoaPods1.16.2. Chrome152.0.7977.84. No toolchain changes.

Before application edits, the sequential baseline passed analyzer, **326 host tests with two optional skips**, Android debug, iOS Simulator debug and Web release. Baseline build times: Android11.3s, iOS13.2s, Web23.3s (compiler/build-tool times). Command wall times:13.78/21.25/23.88s. These baseline builds were not native execution, release-AOT or physical-device acceptance.

The first full updated run passed **402 tests, two optional skips**, analyzer clean2.4s. Later 17-case connected Shell/Home/reset/design run passed with real Flutter captures. **Final consolidated run:431 passed, two optional benchmark skips,26s; analyzer clean2.4s.** This includes new semantics, retired-save cleanup, five delayed clear/navigation cases, three concurrent-boundary cases and two cross-database close tests. The first final attempt exposed four test-fixture/old-expectation failures; they were corrected while preserving policy/render/export assertions, then the whole suite passed. The full host suite tested shared Dart implementation `ff8bbe6`; the subsequent Swift-only startup fix and native test instrumentation are committed as `124a263`. Final full analysis after those edits is clean2.4s; iOS guard and signature regressions were rerun successfully.

All raw logs live in `../../work/` relative to the repository, named `ui-baseline-*`, `ui-full-*`, `ui-root-final-layout.log`, `ui-home-gallery-final.log`, `ui-clear-navigation-final.log` and `ui-native-*`. Failed attempts are retained and distinguished from corrected reruns.

## Final normal builds

| Target / command | Baseline build time | Final build time | Actual result |
|---|---:|---:|---|
| `flutter build apk --debug --no-pub` |11.3s|14.5s|PASS; installed/launched on owned5556 emulator, version0.6.0+6, secure foreground window|
| `flutter build ios --simulator --debug --no-pub` |13.2s|19.8s|PASS; installed/launched on the named iPhone17Pro simulator, version0.6.0+6|
| `flutter build web --release --no-pub --no-web-resources-cdn --no-tree-shake-icons` |23.3s|25.5s|PASS; actual main preview and functional clipboard checks|

These are build-tool durations, not startup or runtime performance comparisons. Native integration artifacts were replaced by normal `lib/main.dart` builds. Web and Android production source is unchanged by the final iOS-only follow-up; the iOS main artifact includes it. Native artifact hashes/paths are recorded in `../../work/ui-native-final-artifacts.json`; build/run details are in [native_validation](native_validation.md).

## Native execution and limitations

Dedicated Android target: **emulator-5556**, Android16/API36; installed System WebView153.0.8010.36 is used only for legacy cleanup, never as an active content view. The unrelated5554 emulator was untouched. iOS target: **C157677F-A33F-45B2-BFFB-F3DED552D4F4**, iPhone17Pro simulator, runtime display26.3, actual26.3.1/23D8133.

The new Android/iOS browser and native-channel denial suites passed. Android verifies FLAG_SECURE and PROCESS_TEXT denial. All four Handoff start/resume phases passed without uninstalling between paired processes. Android process IDs29465→29614; iOS33439→34118. Correct-code durable return, wrong-code rejection, owner-input positive control/guest-input negative control, no owner builder, no content view/request and no pending guest-link replay were exercised. Three actual Android ACTION_VIEW injection windows returned successfully without replay; iOS uses framework route/discard-channel checks, not an invented registered universal-link delivery.

Android Student and iOS consumer protected journeys passed. Both platforms also passed the consumer signature journey with actual SQLite close/reopen. The initial Android consumer run timed out at owner loading. Installed sqflite Android source revealed a worker-pool race when two final database closes overlap. A shared awaited close coordinator fixes that dispatch race; host tests exercise both real repository owners and failure progress. The corrected Android trace shows close #51 returning before #52 starts, no pending callbacks and a952ms root reopen. The20s bound was unchanged. The original failure log is retained, and only its exact generated test records were cleaned. An additional iOS run found a separate outer-startup failure despite completed SQL calls. Instrumentation then measured a redundant same-process WebKit purge at14,563ms, close to the unchanged15s startup timeout. The narrow fix reuses only a completed process-local quarantine receipt; the first process call still awaits actual WebKit deletion, and explicit Clear data always performs deletion. No live renderer or website-store writer exists that could repopulate that process. Fresh-process/count-zero, actual completion/count-one and reuse/count-one assertions passed. Final iOS guard and signature runs passed; actual first purge397ms, acknowledged reuse0ms, owner-root reopen462ms. No timeout was relaxed, and initial failures remain documented. See [native_validation](native_validation.md) for every invocation.

No physical Android/iPhone testing, store signing, release/AOT performance acceptance, complete TalkBack/VoiceOver audit, OS backup forensic-erasure verification or universal foldable/keyboard combination is claimed. Native protections were never disabled to obtain screenshots. A compiled app is distinct from an integration-tested app, and a simulator pass is distinct from a physical-device pass.

## Measured performance against the starting checkout

These are actual `flutter test` host microbenchmarks on the same Mac/Dart version, with unchanged sample counts. They run in a concurrent test suite and are noisy, not UI frame/FPS measurements or evidence of a speedup.

| Operation | Samples | Baseline median / p95 (µs) | Final median / p95 (µs) |
|---|---:|---:|---:|
| Search18 local Official identities |100|73 /461|36 /212|
| Restore3 Spaces/12 tasks from memory document |30|766 /1838|757 /2094|
| Local practice-terms analysis |30|634 /1428|654 /932|
| Switch12 memory tabs1000 times |30|546 /1175|493 /1286|

SQLite metadata reopen (20 warm repetitions,10 old tabs/5000 bookmarks/5000 history rows) was7.085/9.562ms median/p95 before and7.092/9.771ms after. Schema remained4; no private rows survived close. First opens were26.048ms/29.497ms. Host process RSS snapshots differ between test processes (baseline168.2→168.5MB; final193.2→196.3MB), so they do not establish app/WebView memory growth. The production-strength PIN KDF host check was1706ms before and1716ms after. No KDF weakening was used for native acceptance.

Single **debug integration** observations, measured after harness launch: Android Student main-to-settled5101ms/tab change394.4ms; iOS consumer1444ms/346.5ms. Handoff activation/return was2241/2467ms Android and1938/1696ms iOS. Corrected consumer root reopen was952ms Android and462ms iOS. These are not cold OS startup, installation, release, physical-device or sustained frame measurements. There was no fresh pre-UI native timing baseline, so prior-milestone device values are not reused as a before/after claim.

## Visual, accessibility and interaction evidence

The final main app was rebuilt for Web with local resources and opened at `http://127.0.0.1:8791/`. Actual Official Routes, Settings, Appearance and Protection navigation worked. The final Home semantic search action opened the field; `moon` produced two real matches, and a selected signed article opened. The grouped menu led to Compatibility: issue selection, domain-omitting preview and actual clipboard copy were verified. Before You Commit analyzed its invented practice example and copied exactly reviewed findings with positions and uncertainty. Both clipboard round trips passed, the prior clipboard was restored, and no new analysis was saved. Console warning/error inspection returned no entries. The running app preview is production `lib/main.dart`, not the HTML handoff. Its isolated review profile already contained explicitly named practice tasks/Spaces from earlier review; those records are not new production defaults.

Evidence directory: [screenshots](screenshots/). `runtime-web-*` files come from the running release app in the isolated review browser profile (1280×720 Official wide,711×720 final Home/findings, or390×788 compact). `home-synthetic-*`, `shell-*`, `gpl-*`, `oc-*`, `workspace-*` and `handoff-*` come from real Flutter widgets/navigators with memory-only synthetic data, pixel ratio1. They do not bypass production native capture protection. Dimensions/state maps are documented beside each scoped QA report. Home/task names in those fixtures are test examples, never production defaults.

Host layout checks exercise light/dark,320/360/390/430/600/768/1024/1440 widths,200% text,320×480 short screens and844×390 landscape. Home also reaches320% text in landscape. Essential controls retain48px targets; primary controls52px. The actual Home search semantic node is tested as an enabled, independently labelled button with an assistive activation action; it does not merge surrounding content into a disabled field. Native integration uses real keyboards, while the guest keypad has no platform text input. These are targeted checks, not a claim of exhaustive accessibility conformance.

Visual corrections included Home headline/rhythm/quick links/task density, original-logo rendering, semantic tab-count treatment, Settings group spacing/icon tiles/dividers, Protection's hierarchy and truthful scope, Space card density and converter expansion, narrow forms/keypads, and removal of excessive Page information sheet height. The final comparison record is [design-qa.md](../../design-qa.md); scoped records are [Official/Commit](OFFICIAL_COMMIT_QA.md), [Spaces/Handoff](workspace_handoff_visual_qa.md), [Settings/Protection/Library](SETTINGS_LIBRARY_PRIVACY_QA.md) and [Shell](SHELL_VISUAL_QA.md).

The source includes an illustrative24px status strip; native-safe-area ownership is excluded when comparing widget captures. Larger body/supporting text and longer truthful capability explanations intentionally differ from small sample metadata. The wide Home uses a bounded720px composition; expanded evidence/menu uses a compact focused dialog rather than claiming a live-browser side panel. No fabricated status-bar artwork, remote thumbnails or synthetic production findings were added.

## Development gallery

`tool/ui_gallery.dart` is a separate debug-only entrypoint with shared components plus synthetic foundation, Official/Commit, Settings/Library and Workspace/Handoff scenarios. It is not imported by production main and cannot enable an unsafe destination. Fixtures use memory stores and controlled error/pending states. Flutter clipboard reads are empty and writes are discarded by the gallery binding; three tests prove interception and forwarding of unrelated platform messages. The binding is not a blanket claim about OS/browser actions outside Flutter.

Preview it only as labelled test evidence:

```sh
flutter run --no-pub -d chrome -t tool/ui_gallery.dart --web-port=8796
```

## Preview the updated application

Run from this exact checkout and branch; `build/web` and the device preview must be rebuilt from production `lib/main.dart` after integration tests because test harnesses overwrite normal output paths.

```sh
cd /Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser
git branch --show-current
# Expected: ui-handoff/implementation
flutter run --no-pub -d emulator-5556 -t lib/main.dart
```

In a separate terminal for the available iOS Simulator:

```sh
cd /Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser
flutter run --no-pub -d C157677F-A33F-45B2-BFFB-F3DED552D4F4 -t lib/main.dart
```

Chrome development preview:

```sh
cd /Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser
flutter run --no-pub -d chrome -t lib/main.dart --web-port=8795
```

Portable static release preview:

```sh
flutter build web --release --no-pub --no-web-resources-cdn --no-tree-shake-icons
python3 -m http.server 8791 --bind 127.0.0.1 --directory build/web
```

Use the existing local8791 server if it is already running. The current8791 server serves this checkout’s final `build/web`; the isolated in-app browser is left on Home. Both dedicated native targets have the final normal consumer main app installed and launched. Source is `124a263`; the ending documentation commit is recorded in the final response. No push or merge occurred.
