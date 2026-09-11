# UI handoff native validation

This is evidence for the 0.6 UI implementation on the dedicated development devices, not a release or physical-device certification. The application still renders only approved bundled plain text. No live WebView, external opener or policy override was added.

Observed 2026-09-11: Android 16/API36 on `emulator-5556`, System WebView 153.0.8010.36 used only for legacy cleanup, and iPhone 17 Pro simulator `C157677F-A33F-45B2-BFFB-F3DED552D4F4`, runtime 26.3.1 (23D8133). Xcode 26.3 (17C529). Every run uses the same installed app storage with `--no-uninstall`; Handoff start/resume use separate processes and only the dedicated smoke credential key. The unrelated Android emulator was not operated.

## Native runs

| Fixture | Platform / role | Result | Native build / suite | Parent-workspace log |
|---|---|---|---|---|
| Allocation-free browser boundary | Android consumer | PASS | 21.3 / 2 s | `work/ui-native-browser-android.log` |
| Raw native channel / plugin absence / cleanup | Android consumer | PASS | 15.2 / 3 s | `work/ui-native-guard-android.log` |
| Allocation-free browser boundary | iOS consumer | PASS | 26.9 / 1 s | `work/ui-native-browser-ios.log` |
| Raw native channel / plugin absence / cleanup | iOS consumer | PASS including fresh-process purge / completed receipt reuse | 21.4 / 2 s | `work/ui-native-guard-ios-quarantine.log` |
| Handoff start | Android consumer | PASS | 15.2 / 18 s | `work/ui-native-handoff-android-start.log` |
| Handoff separate-process resume | Android consumer | PASS | 18.0 / 30 s | `work/ui-native-handoff-android-resume.log` |
| Handoff start | iOS consumer | PASS | 22.2 / 6 s | `work/ui-native-handoff-ios-start.log` |
| Handoff separate-process resume | iOS consumer | PASS | 19.9 / 6 s | `work/ui-native-handoff-ios-resume.log` |
| Real main / search / saves / tabs / locked protection | Android Student | PASS | 18.1 / 22 s | `work/ui-native-protected-android.log` |
| Real main / search / saves / tabs / locked protection | iOS consumer | PASS | 23.8 / 16 s | `work/ui-native-protected-ios.log` |
| Signature features / real SQLite root reopen | Android consumer | PASS after serialized-close correction; initial failure retained below | 16.1 / 18 s | `work/ui-native-signature-android-coordinator.log` |
| Signature features / real SQLite root reopen | iOS consumer | PASS after ordered closes and completed-purge receipt | 20.2 / 13 s | `work/ui-native-signature-ios-quarantine-fixed.log` |

The denial fixtures assert zero content views/controlled-loopback requests, no legacy allow/prompt callback invocation, rejection of 140 raw native attempts, no former plugin constructor handler, and cleanup without a temporary renderer. Android also checks its secure-window flag and external PROCESS_TEXT rejection. A zero loopback counter is not device-wide packet inspection.

Handoff keeps the owner builder uncalled, provides an actual owner keyboard/UIKit responder positive control, then requires absent guest/return input and selection, wrong-code denial and durable authenticated return. Android's three targeted incoming VIEW windows passed without content requests or address replay after return. See [Handoff security](../HANDOFF_SECURITY.md) for the separate-process IDs, KDF timings and preserved limitations. iOS does not claim an unregistered universal-link delivery or exhaustive inactive-snapshot observation.

The protected main journeys exercise the actual 18-resource signed catalog, local search, article view, Bookmark/Read later changes, two independently opened reviewed articles, a real tab selection, URI rejection with dismissed editing, and a tap on a core protection row with no override. Student saves remain session-only. Their cleanup restores only reviewed IDs they changed.

## Single debug observations

| Observation | Android | iOS |
|---|---|---|
| Protected app.main → first settled UI | 5,101 ms (Student) | 1,444 ms (consumer) |
| Two-tab selection → settled article | 394.4 ms | 346.5 ms |
| Handoff activation / authenticated return | 2,241 / 2,467 ms | 1,938 / 1,696 ms |
| Signature app.main → Home/tools | 4,028 ms | 1,565 ms |
| 405-byte local analysis | 15 ms | 10 ms |
| Signature root reopen → restored tools | 952 ms | 462 ms |

These stopwatches start after the integration harness is running. They include the specified UI/storage operation and its settlement, but not installation or OS process launch; they are not cold-start, release, FPS, physical-device or performance guarantees. Native builds were serialized.

The Android signature run initially opened Home/tools in 4,153 ms and completed its 405-byte local analysis in 18 ms. The feature routes were reached, but after actual application-root disposal/reopen the 20-second bounded wait expired with `StartupSurface` present, `failed=false`, and Handoff status `owner`. The failure log is retained as `work/ui-native-signature-android.log` (16.1 s build / 38 s suite). Source review found a sqflite Android worker-pool close race when both database owners close concurrently. A shared app-level close coordinator now serializes the browser and policy-store closes, with two host tests covering non-overlap and progress after failure. The native retry at implementation commit `ff8bbe6` passed with the same 20-second bound; its sanitized trace shows the first close returned before the second started, no pending database call, and owner reopen in 952 ms. This is direct evidence of ordered teardown and a successful retry, not exhaustive timing proof of the original native failure. The earlier iOS pass predates the coordinator; both concurrent closes returned in that earlier trace.

The iOS signature run with ordered closes then hit a separate pre-owner startup failure (`work/ui-native-signature-ios-coordinator.log`, 23.6 s build / 48 s suite). Both closes and every observed SQLite operation completed. A later native-channel diagnostic measured its first quarantine at 434 ms and a redundant second same-process quarantine at 14,563 ms, close to the unchanged 15-second startup limit; that run narrowly passed (`work/ui-native-signature-ios-quarantine-diagnostic.log`, 20.5 s build / 28 s suite). The initial failed run did not include native-channel timing, so its precise native callback history is not claimed.

The iOS bridge now retains an in-memory acknowledgement only when WebKit actually completes the initial quarantine. The current capability boundary has no content WebView, ad view, authentication or website-store writer that could repopulate the store in that process. A subsequent root may reuse that completed acknowledgement; a fresh native process begins without it. Pending/error/timeout does not grant an acknowledgement, and an explicit owner Clear data request always performs its selected deletion. There is no preference, role, incoming payload or debug setter to forge completion. Native tests prove fresh false/count-zero state, actual completion/count-one, repeated quarantine still count-one, explicit deletion completion, and zero content views/requests. The final signature run measured an actual first purge of 397 ms and a completed acknowledgement on reopen in 0 ms; owner restoration was 462 ms. These checks verify the bounded invariant, not all future WebKit/provider behavior. First cleanup can still fail or time out; startup then remains unavailable.

Each initial failed Android/iOS run left exactly three generated Spaces, one task and one analysis. They were identified by synthetic fields plus IDs inside that failed run's timestamp window, then removed only from the workspace document while Wingman was stopped. Original database bytes were checked before replacement, all other tables/documents were compared unchanged, SQLite quick-check passed, and temporary snapshots were deleted. Receipts: `work/ui-failed-fixture-cleanup.json` and `work/ui-failed-ios-fixture-cleanup.json`. No generic app/database clear was performed. Successful runs use their own exact-ID cleanup.

## Build and manual scope

Android brand resources and iOS icon/launch storyboard assets compiled in these builds. Their actual launcher masks and startup appearance remain a separate visual check; see [native brand details](native_brand.md). The Android secure-window flag and iOS inactive-scene cover implementation are unchanged. Capturing protected Android content must not weaken those controls.

Integration runs replace standard APK/app build outputs. The final normal consumer artifacts were restored and installed: Android debug build 14.5 s, iOS simulator debug build 19.8 s. Both report version 0.6.0+6; both OS launch commands succeeded. Android's owned foreground window retains the SECURE flag; no protected-content screenshot was attempted. These are main builds/launches, not extra runtime test passes. Build/install/launch logs are `work/ui-native-main-{android,ios}*.log`; artifact hashes and paths are in `work/ui-native-final-artifacts.json`, with Android window evidence in `work/ui-native-main-android-window.json`.

The implementation base is commit `ff8bbe66819889512a2670446670efac5f72281d`. Android's final main artifact uses that source; iOS additionally includes the reviewed `AppDelegate.swift` completed-quarantine acknowledgement described above, committed as `124a263`. The final full analyzer after the native/test edits passed in 2.4 s (`work/ui-native-final-analyze.log`). The root's preceding full host gate passed 431 tests with two optional benchmark skips in 26 s (`work/ui-final-test-2.log`). No push, merge, deployment, enrollment or macOS security setting change was performed.
