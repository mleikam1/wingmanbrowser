# Combined main merge acceptance

2026-09-25. The user authorized merging the completed shared redesign and native macOS implementation into local `main` and `origin/main`. This record covers source integration and publication; it does not authorize application deployment or store submission.

## Source lineage and resolutions

- Verified remote starting point: `254c90717eb9e2837e5bbd1e757c02f3a7513d56` (`origin/main`).
- Shared UI/mobile/web head: `908cbce` (`feat/wingman-wow-ui`).
- Native macOS head: `c4d2832` (`feat/wingman-macos`), based on the shared checkpoint `3a6cd00`.
- Integration checkout: `outputs/wingman-merged`; temporary branch `integrate/wingman-redesign`.
- Retained the complete desktop target, AppKit Flutter surface, native Apple storage routing and shared `darwin/ConsumerProtection.swift` compiled by both Apple Xcode targets. The iOS adapter keeps the latest renderer/request/lifecycle and settled-history fixes; helpers are defined once in shared Darwin source.
- Resolved overlapping privacy documentation to retain the current shared results and macOS private-store scope. The iOS test overlap was whitespace only. Documentation now uses same-repository links and records the prior artifacts as build provenance.
- The integration merge commit containing this ledger preserves both implementation heads as ancestors; identify it with `git log --merges --oneline`.
- Publication procedure: fast-forward local `main`, push normally to `origin/main`, then compare the local and remote object IDs. The final task response records the published commit after that verification; no force push is used.

## Combined tree validation

| Check | Result / evidence |
| --- | --- |
| Clean merge and conflict-marker review | Resolved the privacy prose and whitespace-only iOS test overlaps; `git diff --check` passed. |
| Production source parity with reviewed desktop head | Native production inputs, `lib/`, iOS Runner/project, shared Darwin, macOS, Android and pubspec inputs are byte-identical to reviewed `c4d2832`. |
| Flutter analysis | `flutter analyze --no-pub`: exit 0, no issues, 5.7s. |
| Full combined Flutter regression suite | Exit 0; **1,055 passed**, six existing opt-in skips, 1m42s. |
| Apple shared-source / project validation | Both iOS and macOS project plists pass lint; iOS shared helper extraction differs only in internal visibility and the required iOS/macOS configuration conditional. Native production sources match the reviewed desktop tree, so no redundant native rebuild is claimed. |
| Outgoing credential scan | 156 text files checked with high-confidence credential patterns; no findings. |
| Final Git working tree and remote commit verification | Required after commit/push; recorded in the task completion response. |

The earlier suites and artifacts retain their original source/test scope in [verification](VERIFICATION.md), [platform matrix](PLATFORM_MATRIX.md), and [macOS ledger](macos/README.md); they are not silently relabeled as new merged-tree executions.

## Local validation evidence

The following ignored logs were produced in the combined checkout. Their SHA256 digests preserve the exact verification output without committing generated build directories.

The [machine-readable merge verification](evidence/merge-verification.json) records exact commands, exits, source parity and log hashes.

| Log | SHA256 |
| --- | --- |
| `work/merge/pub-get.log` | `7354d3056ad7229d5400699bf2424c7a62dc92f1d7673b9d01ea120e804ddd1b` |
| `work/merge/analyze.log` | `98aafc5b5c557a897e59c5e9d27cdd236d306293e9a6cb347e5a4d1a9a308e0c` |
| `work/merge/flutter-tests.log` | `8db1b374baf4a3212d8dd48048c3950b201f8f4aa5a58c280bcf6a58d1496601` |

## Retained acceptance gaps

Android ordinary visual testing remains blocked by the dedicated emulator's System UI failure. The packaged macOS release passed foreground input, scrolling and toolbar history, but context-preserving native input after returning from inactivity remains unaccepted. The final macOS native history rerun compiled but its test host stalled in dyld before any test; the last 14-case native pass predates that observer change. The final production-app macOS integration and corresponding iOS native history tests passed afterward. Any new successful merged-tree checks above supplement that evidence without implying untested manual, physical-device, media/file-panel or distribution acceptance.
