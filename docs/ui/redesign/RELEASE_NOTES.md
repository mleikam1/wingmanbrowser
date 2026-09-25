# Local redesign candidate notes

2026-09-25 • existing application version 0.16.0+19 • `feat/wingman-wow-ui`

The production Flutter app now uses the supplied visual direction for Home, the Wingman companion, Spaces, Finish Mode, Protection, blocked recovery, Before You Commit and Settings. The original logo remains. Wide layouts use available space; compact layouts and larger text reflow. Light/dark/system previews, local Gary/Wallace/Betty wording and reduced motion are available in Settings.

The companion uses real captured task state and explicit page saving. Spaces add bounded permitted-page records with schema migration. Finish Mode adds an optional local timer, reversible tab parking and opt-in scoped site nudges; mandatory protection stays authoritative. Terms review keeps its local analyzer and shows evidence alongside supplied text. Protection separates configuration from measured Android interception outcomes and platform limitations; iOS/web do not display fabricated counts.

Production feeds and backend behavior are unchanged. No accounts, cloud assistant, page capture, feed polling or paid service was added. The About constant now matches the existing package version; this work does not imply a new store release.

Apple adapters also reject retired-renderer callbacks and stale async restoration, and now synchronize the address after native Back/Forward traversal settles. These corrections preserve mandatory policy checks and the same document/renderer. The final iOS simulator artifact includes both corrections and passed the native history tests and installed-app smoke.

## Verification and scope

Current test/build/device results belong to [IMPLEMENTATION_STATUS](IMPLEMENTATION_STATUS.md) and [PLATFORM_MATRIX](PLATFORM_MATRIX.md). Do not read earlier full-suite failures, earlier milestone totals or selected passing tests as final aggregate acceptance. The [visual index](VISUAL_INDEX.md) identifies widget renders versus ordinary running iOS simulator captures. A separate `feat/wingman-macos` worktree implements the native AppKit WKWebView browser; its runtime/test ledger records actual desktop coverage. Windows/Linux native engines are unsupported here. Physical-device accessibility/performance and store distribution are not claimed.

The original checkout is preserved. Changes are local; there has been no push, merge, deployment or store submission. Use [local run and rollback](LOCAL_RUN_AND_ROLLBACK.md) and the [privacy/capability note](PRIVACY_CAPABILITIES.md) when reviewing this candidate.
