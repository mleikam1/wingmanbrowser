# Wingman redesign implementation status

Updated2026-09-25. The shared production redesign is implemented, with **1041 Flutter tests passed/6 existing opt-in skips**, clean analysis, Android/iOS/web local builds and runtime evidence. The separate macOS native workstream has **1055 Flutter tests passed/6 skips** and **14 native tests passed**; its ordinary foreground/integration verification is finishing. Android's ordinary visual smoke has an explicit emulator OS/CUA blocker. This ledger is local acceptance evidence, not release certification.

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
- The final documentation/capture commit is the branch tip after these changes; use `git log -1` for its exact hash.

`outputs/wingman-macos` / `feat/wingman-macos` starts from3a6cd00 and includes the shared runtime corrections, new AppKit WKWebView target and shared Apple policy code. Its [native ledger](../../../../wingman-macos/docs/ui/redesign/macos/README.md) owns desktop commits, artifact names, foreground checks, native fixture/integration results and gaps. Windows/Linux native targets remain absent.

## Remaining verification at this checkpoint

1. Finish bounded macOS ordinary foreground and cross-layer integration checks, retain exact successes/blockers, and finalize its release artifact/commit.
2. Completed: final ownership-patched iOS artifact restored the task/checklist/notes and rendered example.com through native WKWebView; see `evidence/ios-ownership-final-runtime.md`.
3. Refresh aggregate documentation with those results and finalize scoped local evidence commits.

## Boundaries

No push, merge, deployment, store submission, notarization purchase or paid service. Existing identifiers/signing and user installs are preserved; the new macOS target has its own local sandboxed identifier. Dedicated test devices/data are used. No invented metrics/tasks/page content or protection bypasses are present. An abrupt kill can restore only the timer's last durable checkpoint, paused. Physical-device certification, full assistive-technology coverage, performance/leak measurement and complete web-content classification are not claimed.
