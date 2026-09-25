# Wingman redesign implementation status

Updated 2026-09-25. The shared production redesign is implemented, with **1041 Flutter tests passed/6 existing opt-in skips**, clean analysis, Android/iOS/web local builds and runtime evidence. The separate macOS native workstream has **1055 Flutter tests passed/6 skips**, **14 native tests passed before the final history patch**, and a passing production-app integration journey after that patch. The Apple history timing defect is corrected on both Apple branches; the rebuilt iOS app passed native tests and an ordinary runtime smoke. Android ordinary visual QA and the final macOS XCTest launch have documented environment blockers. The packaged macOS release passed real foreground input, scrolling and toolbar history checks. This ledger is local acceptance evidence, not release certification.

## Protected starting state

Original checkout `2026-09-10/.../outputs/wingman_browser` remains clean at `18eef0c`; fetch showed0 local-only/19 remote-only commits. Original branch and working tree are unchanged. The isolated `outputs/wingman-browser` worktree uses `feat/wingman-wow-ui`, based on verified current `origin/main` (`254c907`). The remote coincidentally matched the historical design review; no rollback was performed. No AGENTS.md was found.

Production entrypoint is `lib/main.dart`. Android System WebView/iOS WKWebView use ProtectedWebBridge; the retired BrowserEnginePool is not browsing authority. Web is an external-navigation companion. No desktop target existed initially.

## Connected implementation

- Selected nine boards and three mobile references inspected; original logo retained. Semantic color/layout/motion roles and local blue/cyan ribbon art drive both themes.
- Responsive task-first Home, real resume progress/next step, chosen Launchpad/customization and compact Spaces. Existing saved module order/visibility is preserved. Updates remains optional/secondary.
- Capability-aware native expanded tabs/address/history controls; compact browser dock; captured-tab/task companion with real checklist, notes, explicit saves and local tools. Invalidated owners cannot retain sensitive content or redirect queued actions.
- Versioned schema2 Spaces/task saves and UI preferences, migrations and failed-write recovery. Normal permitted URL records remain distinct from offline resource IDs, bookmarks and transient native tab state. Private URLs do not persist into normal collections.
- Optional monotonic timer with paused background/restart checkpoints, reversible tab parking, scoped task completion and opt-in exact-site nudges after mandatory approval.
- Protection configuration/observation/limitations dashboard; actual Android interception counters with renderer lifetime, saturation and redacted typed boundary events. WK/web do not fabricate totals.
- Calm mandatory boundaries with safe task/Home recovery and preview-only review details. Local supplied-text terms analysis with excerpts/uncertainty, grouped Settings, tone/reduced motion and private preference separation.
- Native callbacks/async rule preparation are fenced to the captured renderer, request and lifetime on both Apple branches.
- Native Apple Back/Forward address publication follows loading/history settlement while retaining current-renderer, history-item and policy checks. iOS regressions cover first and interior history entries without reloading the document.
- Production feed/backend behavior unchanged. The only backend edit freezes a pre-existing time-sensitive test fixture. No account, cloud AI, telemetry, automatic page capture, new polling or paid service was added.

## Verified results and outputs

[VERIFICATION](VERIFICATION.md) records commands, exits and scope. Backend186 tests, Android23 JVM tests plus real integration journey, iOS13 current-consumer XCTest cases and shared1041 tests passed. Final analyzer is clean. The [platform matrix](PLATFORM_MATRIX.md) separates implemented/tested/blocked/unsupported states.

Ordinary iOS and web runtime exercised task/checklist/note persistence, timer state, companion reopening and safe private/host-navigation scope. Android ordinary APK installation/launch metadata is verified; its final screenshot shows a System UI ANR and is labeled as a blocker, not app acceptance.

Local builds are preserved under `artifacts/android/`, `artifacts/ios-simulator/` and `artifacts/web-companion/`, with hashes/source inventories in evidence. The [visual index](VISUAL_INDEX.md) maps all nine boards, mobile variants and additional loading/failure captures; widget-render, ordinary-runtime and OS setup/blocker evidence is clearly labeled. [Visual adaptations](VISUAL_DEVIATIONS.md) explain accessibility/capability-driven differences.

## Local commits and desktop lineage

- `3a6cd00`: completed shared UI checkpoint, state/behavior tests and initial evidence.
- `1a31bfd`: independently accessible task Continue and restored companion → selected-task detail; local run script.
- `efdd150`: ordinary Android artifact verification and explicit emulator/CUA blocker evidence.
- `50dab41`: iOS renderer/request/lifetime fences, expanded native regression and final1041-test/analyzer evidence.
- `9ee6d45`: final shared build/evidence records and production loading/failure captures.
- `edf5499`: iOS Back/Forward address synchronization, 13 passing native tests, 22 focused Dart tests and a replacement ordinary simulator artifact.
- The final documentation/capture commit is the branch tip after these changes; use `git log -1` for its exact hash.

`outputs/wingman-macos` / `feat/wingman-macos` starts from3a6cd00 and includes the shared runtime corrections, new AppKit WKWebView target and shared Apple policy code. Its [native ledger](../../../../wingman-macos/docs/ui/redesign/macos/README.md) owns desktop commits, artifact names, foreground checks, native fixture/integration results and gaps. Windows/Linux native targets remain absent.

## Final follow-up and manual verification gaps

The macOS production-app journey passed real AppKitView rendering, JavaScript, Back/Forward address updates, Home, a redirected mandatory boundary and safe recovery. The matching iOS history fix passed all 13 selected native tests; the latest ordinary `Wingman-20260925T211144Z.app` restored the task/checklist/notes and rendered example.com. See [history evidence](IOS_HISTORY_FOLLOWUP.md) and [installed-app smoke](evidence/ios-ownership-final-runtime.md).

Android's ordinary APK is installed and its MainActivity launch was verified, but System UI ANR obscured visual acceptance. The dedicated emulator was gracefully stopped with its data preserved. Relaunch that existing QA device in a healthy emulator UI to finish its ordinary visual check. The final packaged macOS release cleared the earlier foreground activation problem and passed actual address entry, page typing, button activation, scrolling and Back/Forward navigation. Hiding the app displayed its privacy cover. After bringing it back, the page could become visible while the window remained inactive and native typing did not resume; full return-to-active focus remains unaccepted. The desktop ledger records that bounded observation and native-panel scope. No security changes, data wipe, payment or production access is required.

The final macOS XCTest rerun stalled in dyld before application initialization or any test case, including one clean retry. The expanded first/interior history regressions compiled but were not executed by that run. Earlier 14-case native results, the final passing full-app integration, and the matching iOS native history tests are separate evidence; none is labeled a final 14-case macOS pass. The desktop ledger retains the startup samples and exact retry command.

## Boundaries

No push, merge, deployment, store submission, notarization purchase or paid service. Existing identifiers/signing and user installs are preserved; the new macOS target has its own local sandboxed identifier. Dedicated test devices/data are used. No invented metrics/tasks/page content or protection bypasses are present. An abrupt kill can restore only the timer's last durable checkpoint, paused. Physical-device certification, full assistive-technology coverage, performance/leak measurement and complete web-content classification are not claimed.
