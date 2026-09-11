# Signature features — implementation status

Development/review configuration 0.5.0. Updated 2026-09-11. Local work only; no publishing, remote merge, production services or monetization is authorized by this milestone.

## Starting audit

- Repository `mleikam1/wingmanbrowser`; clean branch `permanent-protection/foundation`, commit `2171bce29b283e04b52ca8a950ef88dd97a05b36`.
- New local branch `signature-features/consumer` retains that complete foundation. It is ahead of remote main; neither milestone has been merged remotely.
- Flutter 3.44.4, Dart 3.12.2, Xcode 26.3, JBR 21. Android emulator-5556 (API 36/Android 16, WebView 134.0.6998.135); iPhone 17 Pro iOS 26.3 simulator; Flutter web companion.
- Baseline: analyzer clean (1.9s); 190 tests passed, 2 optional skips (6s); Android debug build 17.0s; iOS simulator debug 13.5s; web JavaScript release/full fonts 24.5s. Logs are in the parent workspace `work/signature-baseline-*.log`.
- Existing Flutter plaintext reader, authoritative positive-eligibility policy, Ed25519 exact-body catalog, quarantined legacy browsing records, SQLite v3 and native fail-closed adapters. No live WebView exists in the shipping configuration. Ordinary reviewed-resource tabs/back/forward, local search, reviewed bookmarks/reading list, themes and private sessions remain in scope.
- No new dependencies or account services. SQLite v4 adds a separate bounded document table for explicit workspaces and minimal privacy events. Existing archived data is preserved.

## Feature status and verified scope

| Feature | Status | Working scope and boundary |
| --- | --- | --- |
| Official Routes | Partial | 18 reviewed organizational destinations with local search/evidence. Live opening remains denied by authoritative policy; identity is not content eligibility. |
| Before You Commit | Implemented and tested. | Bounded English pasted text/current signed articles, evidence and uncertainty, explicit local saves. Local analyzer and integrated receipt journey pass. No live DOM or cloud extraction. |
| Your Spaces | Implemented and tested. | Three user-chosen types, local resources/notes/checklists, reading-list integration and unit tool. Host UI, strict restoration, real SQLite migration and private-scope tests pass. Android/iOS actual-root SQLite reopen and web reload checks pass. |
| Finish Mode | Implemented and tested. | Explicit goals, notes, checklist, pause/resume, saved tab associations and selective finish. UI closure/undo/detach and six delayed-navigation tests pass; native persisted-task reopen and web pause/reload/resume pass. |
| Hand It Over | Implemented and tested. | Native static signed-text fallback with secure owner-return marker, custom keypad and whole-owner-tree replacement. Android/iOS preserved-install start and separate-process resume tests pass. Incoming-link disposal and authenticated owner initialization pass; Android received real OS VIEW intents. Web unavailable. |
| Trust Receipt | Implemented and tested. | Typed bounded event journal, stable startup hydration, distinct outcomes/destinations and previewed clipboard export. Unit, export-widget and integrated local-analysis journey pass. |
| Compatibility Repair | Partial | Sanitized local report/export and narrow tested declarative text-wrap profiles. Empty production registry, no endpoint or remote correction distribution. |

Final native main-app builds, web preview/network observations and complete-suite results are recorded below. A static handoff is not an interactive website session or a device-wide kiosk. A development-signed catalog is not an independent editorial certification. See feature documents for coverage and limitations.

## Final validation

All results are local observations on September 11, 2026. Logs referenced as `work/…` live in the parent workspace, outside the repository. The final source includes the incoming-link lifecycle guard, private teardown, stale Finish ownership and delayed tab-sheet detach fixes.

| Check | Final result | Baseline / qualification |
| --- | --- | --- |
| Flutter analyzer | **Clean, 2.5 s** | Baseline clean, 1.9 s |
| Full host unit/widget suite | **326 passed, 2 optional skips, 13 s** | Baseline 190 passed, 2 skips, 6 s; expanded coverage, not comparable workload |
| Android normal main debug APK | **PASS, 13.9 s** | Baseline 17.0 s |
| iOS normal main simulator debug app | **PASS, 22.3 s** | Baseline 13.5 s |
| Web JavaScript release/full local fonts | **PASS, 24.7 s** | Baseline 24.5 s; Wasm dry run passed, no Wasm runtime claim |
| Android protected main journey | **PASS**, 15.6 s build / 14 s test | Local search, 18 articles, saves, two tabs, core locks and URL denial; zero controlled-server requests/content views |
| iOS protected main journey | **PASS**, 24.5 s build / 10 s test | Same bounded ordinary-browsing scope |
| Android signature main journey | **PASS on diagnostic retry**, 16.2 s build / 18 s test | Real SQLite root reopen; first run timed out at reopen, cause unconfirmed |
| iOS signature main journey | **PASS**, 21.3 s build / 26 s test | Real SQLite root reopen; slow reopen recorded below |
| Native static handoff | **4 phases PASS** | Android + iOS start/separate-process resume, secure marker + real KDF/native input checks; exact evidence in HANDOFF_SECURITY.md |
| Web actual UI | **PASS for recorded journeys** | Official evidence, three Spaces, conversion, task reload/resume, local analysis/save, receipt, preview/copy report; actual screenshots available |

Host logs: `signature-analyze-handoff.log`, `signature-all-tests-handoff.log`. Main artifact logs: `signature-{android,ios,web}-main-handoff.log`. Native journey logs: `signature-protected-app-{android,ios}.log`, `signature-app-android-diagnostic.log`, `signature-app-ios.log`. The earlier Android timeout remains in `signature-app-android.log`. Earlier full-suite migration-version and dialog/fixture failures were fixed and are superseded by the complete 326-test pass, not counted as passing attempts.

Normal main-entrypoint artifacts were rebuilt **after** integration tests, so standard build paths contain the application, not an integration harness. Android debug is approximately 183.6 MB; debug permissions include INTERNET for development/VM-service support. Current artifact inspection found none of the checked retired GMA/UMP, live-WebView, URL-launcher or attribution implementation packages. iOS bundled frameworks were App, Flutter, objective_c and sqlite3. The generated plugin list has no retired ad/live-content/launcher plugins. Exact hashes, names and sizes are in `work/signature-artifact-audit.json`. This package inspection complements runtime evidence and is not an exhaustive security audit.

## Performance observations

Host: macOS arm64, Dart 3.12.2, Flutter test debug host. These are bounded operation timings without UI rasterization, persistent-disk I/O or device startup. No new-feature baseline exists.

| Operation | Samples | Median | p95 |
| --- | ---: | ---: | ---: |
| Local Official Routes search, 18 records | 100 | 32 µs | 152 µs |
| Restore memory document, 3 Spaces / 12 tasks | 30 | 675 µs | 1,248 µs |
| Analyze the 405-byte invented practice terms locally | 30 | 615 µs | 1,309 µs |
| 1,000 in-memory selections among 12 tabs, per batch | 30 batches | 555 µs | 1,106 µs |

Native debug integration observations, **one sample each**:

| Measured interval | Android 16/API 36 emulator | iOS 26.3 simulator |
| --- | ---: | ---: |
| Protected main call → first settled Home | 3,688 ms | 2,354 ms |
| One actual debug UI tab switch | 371.8 ms | 344.3 ms |
| Signature main call → Home and tools ready | 3,666 ms | 1,650 ms |
| Local 405-byte analysis including native isolate dispatch | 16 ms | 11 ms |
| Close/reopen application root → persisted tools ready, same process | 1,147 ms | 12,682 ms |
| Handoff initialize, start / separate-process resume | 28 / 205 ms | 46 / 57 ms |
| Handoff activate / authenticated return | 2,521 / 1,958 ms | 1,763 / 1,652 ms |

The handoff figures include real 600,000-iteration PBKDF2. Android's installed WebView 134.0.6998.135 is capability metadata, not an active reader engine. No standalone Home-raster timing, physical low-end device, release-mode native percentile, or directly comparable new-feature baseline was obtained. Build durations depend on warm caches and host load; they do not establish a speed improvement. Optional feature initialization is separate from the ordinary Home gate; native analysis uses an isolate, while web analysis is bounded to 24 KiB on its single thread.

The first Android owner-root reopen exceeded the 20-second test bound; a later instrumented run passed without reproducing it. iOS's passing reopen was still slow. **The cause is unconfirmed and startup/reopen latency remains a release-hardening issue.** Do not turn the retry into a claim that an identified production defect was fixed.

## Privacy, coverage and release boundaries

- Reviewed coverage: **18 real official identities** (global and explicitly labeled US/UK/Canada English starting points), reviewed September 11 and due December 10, 2026. The separate approved reader catalog has **18 original signed guides**, with expiry March 10, 2027. Neither catalog is comprehensive. Identity does not grant live eligibility.
- No Wingman-owned endpoint, remote analysis, advertising, analytics, paid ranking, submission service, account or billed resource was added. Exports are explicit local clipboard actions with a cross-app clipboard disclosure. Normal receipt retention is at most 200 coarse events / 14 days; private/handoff activity stays in memory.
- The actual web observed asset inventory had 33 resources, all at the local preview origin, and no observed browser console errors/warnings. Native denial fixtures saw zero requests and zero content views. These are bounded observations, **not a complete OS/browser/engine traffic trace**. Development research requests are separate. See FEATURE_ACCEPTANCE_TESTS.md and PRIVACY_ARCHITECTURE.md.
- Compatibility profiles validate exact resource/hash/policy scope, fixed text-wrap action, evidence, expiry, revocation and monotonic update rules. The controlled eligible fixture changes from clipped to wrapped while unknown/prohibited siblings remain blocked. The production registry is empty. No arbitrary remote pack distribution, production-site correction or diagnostic endpoint is claimed.
- Live sites, auth, downloads/uploads, media and external search remain disabled from the existing permanent-protection foundation. Web cannot inspect host tabs or provide Hand It Over. Native Hand It Over is static approved text, not a website session, OS biometric transaction, or device-wide kiosk.
- Android release AOT remains **unverified/blocked by the previously observed local tool launch stall**; no 0.5 release APK was produced. The AOT failure was not retested in this milestone. macOS security controls were not weakened. iOS physical/store signing, production catalogs/key custody/distribution, full accessibility/reduced-motion/tablet acceptance and physical-device security/performance remain release work.
- No backend, provider or license is required for the implemented local tools. Expanding live coverage, feeds, production repair packs or cloud features requires reviewed capabilities/content/provider terms and any applicable external access. No cloud service was activated.

## Local delivery

Implementation commit **`9105b94`** is local on **`signature-features/consumer`**, followed by a documentation/evidence commit. Nothing was pushed, merged, published, enrolled or purchased. The exact ending commit and clean-tree result are in the external workspace report `outputs/SIGNATURE_FEATURES_HANDOFF.md`, avoiding a self-referential commit hash in this document. Prior merge requests do not override this milestone's explicit publication boundary.

[README](../README.md) contains exact Android/iOS/web launch commands and hot-reload instructions. [Actual screenshots](SIGNATURE_SCREENSHOTS.md) show review-created states. The local web preview is `http://127.0.0.1:8791/`; it is not a public deployment. This is a runnable development milestone with the disclosed partial scopes, **not a production-ready general web browser**.
