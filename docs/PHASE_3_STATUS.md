# Phase 3 — first 3A delivery

**We've got your back, not your data.**

**More of what matters to you. Less of what gets in your way.**

This report covers **3A: daily-browser reliability and privacy verification**, recorded 10 September 2026. The tested local features and fixes are delivered below, with passing final builds and runtime checks. This is not a completed Phase 3 or store-readiness claim.

## Repository and scope

Repository: `/Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser`. Starting `main` was clean at `e0ee0934346f1b1aa9a5a59f3fd72fdb01ff812b`, matching fetched remote HEAD. Implementation commit `baa0929` on `phase3/everyday-foundation` was merged into `main` by `1cb7338c2c7fa33de22f4e568fa576ebc35c95a4`, without conflicts. The subsequent documentation commit records this verification. The task handoff records the final pushed HEAD after remote verification.

Flutter UI, native Android System WebView/iOS WKWebView, local SQLite and indexed signed Guard packs are retained. Web remains a Home/search/library companion. Tooling: Flutter 3.44.4, Dart 3.12.2, effective Android JBR 21.0.9, Xcode 26.3. OS/engine combinations are in the [platform matrix](PLATFORM_CAPABILITY_MATRIX.md); exact local run commands are in [README](../README.md).

| Milestone | Status |
|---|---|
| 3A reliability/privacy | **Implemented and tested** for the slices below; remaining release acceptance is explicit |
| 3B commitments and Help Now | **Deferred** |
| 3C chosen interests and compatible monetization | **Deferred**; existing ad safety gates corrected in 3A |
| 3D encrypted continuity | **Deferred** |
| 3E extension and bounded assistance | **Deferred** |
| 3F distribution and operational hardening | **Deferred** |

## Implemented and tested

- **Local library:** reading-list URL/title/read-state metadata; explicit normal-session Add address without navigation/fetch; bookmark HTML import with inert preview, confirmed atomic merge and duplicate handling; bounded, escaped plaintext export. Actual reads stop beyond 2 MiB; limits are 5,000 candidate bookmarks and 500 reading entries. SQLite v1→v2 preserves existing data. Private saves are rejected before database access. The focused data suite passed **100 tests**; library/file/Reader UI coverage includes cancellation, background/route changes and failed writes. See [local data evidence](phase3/LOCAL_DATA_VALIDATION.md).
- **Web runtime:** actual release-browser import cancellation left the library unchanged. A fixture preview reported **2 new, 1 duplicate, 2 rejected**; confirmation saved two bookmarks that survived reload. Add address and marking a reading-list item read also survived reload. The final download created a **387-byte HTML file**, verified to contain the expected two URLs and escaped titles. A stale generated Web plugin registrant and browser cache were diagnosed during runtime verification. [Runtime details](phase3/WEB_RUNTIME_AND_NETWORK.md)
- **Browser/Guard reliability:** request identities reject old blocked-page callbacks; retry ordering and renderer recovery are retained. iOS clear-data diagnosis found retained WK views beyond the Dart pool. Explicit documented plugin disposal now releases them before shared deletion: fixtures measured at most three through 12 cycles and zero after clear. A pending/timeout clear cannot falsely satisfy a different selection.
- **Private sessions:** both native fixtures verify independent cookies/localStorage, clearing and fresh reopening while normal sessions survive. Synthetic HTTPS Basic-auth tests passed on **both OSes**, including private denial, separate authentication and normal-session preservation. Android profiles can temporarily write private data to disk; abandoned remnants are removed at startup. iOS uses a nonpersistent WK store. Private metadata is not restored; intentional downloads can remain. These tests do not establish every cache/provider/authentication scheme.
- **Reader/sizing:** iOS extracts ephemeral plain text in an isolated WK world, excludes form/editable/hidden content, refuses detected access overlays, makes no extra fixture HTTP request and rejects stale completion. The actual main-app Reader displayed the local article without either test exclusion marker, and its Larger text button visibly increased size. Detection is conservative and incomplete. Native website sizing supports 75–200%. Reading lists do not save article bodies.
- **Ad eligibility:** **52 policy/consent/provider/lifecycle tests plus one actual-shell wiring test** passed. Unknown/strict protection, private mode, covered routes and background state deny work before UMP/SDK requests. Live Guard/private notifications invalidate pending generations before another frame. Inventory remains explicitly opted-in approved debug test ads on eligible owned Home; no browsing context or Guard labels reach the provider. See [monetization policy](MONETIZATION_POLICY.md).

Native results use the Android 16/API 36 emulator with System WebView 134.0.6998.135 and iPhone 17 Pro/iOS 26.3.1 simulator, in debug mode:

| Fixture | Android | iOS |
|---|---:|---:|
| Browser/private/clear/navigation | Pass, 15 s | Pass, 16 s |
| Guard/request-identity | Pass, 9 s | Pass, 7 s |
| Reader availability/privacy/scaling | Pass, 4 s; Reader denied | Pass, 2 s |
| HTTPS Basic-auth separation | Pass, 5 s | Pass, 4 s |

Durations exclude teardown. [Native validation](phase3/NATIVE_VALIDATION.md) retains logs, failed baseline attempts, resolved clear/auth defects and exact assertions. Simulator/emulator results are not physical-device acceptance.

## Boundaries and deferred capabilities

**Implemented but unverified:** full-card app-switcher capture and timing across devices; real-vault autofill/private suggestions; arbitrary real-account authentication; physical-device startup/restoration and total renderer memory; broad OS file-provider/share compatibility. Android's foreground secure window produced a black screenshot. Actual iOS Files import and Save to Files export passed, including inspection of the saved 387-byte file. The visible portion of Wingman's overlapping private app-switcher card was neutral white; returning restored the page. iOS active screenshots remain possible.

**Blocked:** physical-device and approved credential-provider/default-browser acceptance need suitable hardware/configuration. The initial Mac lock was resolved during validation, enabling the iOS main-app checks above. After closing the manual private fixture, read-only database counts found zero private-marker rows and one normal article row in both history and tabs.

**Disabled pending approval/review:** Android Reader lacks a supported isolated execution-world implementation for the installed binding. Release ad inventory stays hard disabled pending provider/consent/compliance review. Arbitrary-site passkeys/browser credential-provider approval and Apple default-browser entitlement/signing remain external gates.

**Deferred:** Help Now, new schedules/commitment delays, selected interests, encrypted sync, extension targets and AI assistance. Existing local Focus/PIN are not the new 3B experience. There is no Help Now sending flow or interests profile. No two-client ciphertext or extension result is claimed. [Sync security design](SYNC_SECURITY_DESIGN.md) records requirements, not an implemented backend.

Guard remains **experimental**: 49 CC0 category/support/threat-fixture records and seven CC BY-SA 3.0 tracker domains. Threat entries are synthetic; no production Wingman threat feed/Web Risk endpoint exists. Domain rules cannot classify every post/image/advertisement; SafeSearch recognition is limited. Verified offline packs/rollback remain local. Licensing, update requirements and bypass boundaries: [Guard coverage](GUARD_COVERAGE_AND_LIMITATIONS.md).

## Network, cloud and performance

Authenticated cloud CLIs exist, but **no Wingman Browser backend, Firebase app, sync/AI endpoint or production resource was configured, reused or deployed**. No billed inference, subscription or revenue is claimed. Future services require provider approval, least privilege, reviewed logging and enforceable application limits; billing alerts alone are not spend caps.

No analytics/attribution/replay SDK or ordinary browsing upload was added. Websites/search providers receive requested traffic; engines and enabled test ads have separate provider flows. The observed release Web resource window contained **16 loopback-origin resources**, without console errors/warnings. This is not complete TLS, worker, OS or SDK capture. Native fixture counters separately verify blocked requests and Reader's no-fetch boundary. See [runtime network scope](phase3/WEB_RUNTIME_AND_NETWORK.md) and [privacy architecture](PRIVACY_ARCHITECTURE.md).

Android before→after→repeat lookup p50/p95 was **432.583/4,655.875→179.584/2,022.416→525.584/4,929.792 µs**. Idle main-process PSS was **309,280→340,690→350,026 KB**: an unresolved measured increase. Debug switch p95 was **112.790→137.253→100.645 ms**. Results vary; host swap was high and renderer memory excluded. No production speedup or unchanged-performance claim follows. Host metadata reopening p95 was **43.80→40.45 ms**; maximum-library suggestion p95 **4.91→3.00 ms**, neither a phone-startup measure. Detailed caveats/budgets: [native validation](phase3/NATIVE_VALIDATION.md), [local measurements](phase3/LOCAL_DATA_VALIDATION.md), [Guard budgets](GUARD_PERFORMANCE.md).

## Final handoff gates

The bounded outgoing scan found zero credential-pattern findings and no application database/package artifacts; it is not a security certification. Release gates include physical/provider validation, maintained production filter data/signing, platform entitlements, production consent/ad review and the [release checklist](RELEASE_CHECKLIST.md). Android release signing still uses the development debug key.

| Final check | Verified result / remaining scope |
|---|---|
| Whole-project tests | **289 passed**, one optional benchmark skipped, 16 s; `work/phase3-host-tests-handoff.log` |
| Full analysis | **Clean**, 4.9 s; `work/phase3-analyze-handoff.log` |
| Focused library/UI | **25 passed**, 3 s; analysis clean, including seven new route/background/picker-resume regressions |
| Android / iOS / Web application builds | **Passed:** Android debug 23.0 s, iOS simulator debug 44.2 s, Web release 49.1 s. Mobile apps installed and launched. Logs: `phase3-main-android.log`, `phase3-main-ios.log`, `phase3-web-build-delivery.log` |
| Web download/final runtime | **Passed:** actual download content verified; import cancellation/merge and reading-state persistence checked |
| Native performance / visual acceptance | Repeat recorded above; idle PSS unresolved. Main iOS import/export/Reader/private-close checks passed; snapshot observation is limited as stated |
| Ending Git state / authorized merge | Implementation merged to **main** at `1cb7338`; documentation follows this merge. Final pushed revision and clean-tree result are recorded in the task handoff |

Logs are development evidence in the parent workspace, not application telemetry.
