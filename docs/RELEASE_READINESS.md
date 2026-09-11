# Release readiness

Status: **not release-ready**. This is the first tested local foundation milestone, not the complete product-policy roadmap. Final test/build/native/artifact observations and ending commit are recorded in the handoff section below.

## Implemented scope

Mandatory compiled protection; exact signed offline eligibility; safe failure; legacy-data quarantine; local search; reviewed discovery and session navigation; additional restrictions; SDK-free consumer/student/unknown editions; native no-content allocation boundary. Core categories have no overrides. Fourteen original articles make the supported scope usable.

## Disabled pending review

Live websites, external search, resource loading, new windows, authentication, downloads/uploads, external dispatch, remote Reader, raw imported-title previews, arbitrary link opening, advertising inventory, account sign-in and cloud services. Compilation of a target does not enable these capabilities.

## Deferred and blocked

- Production content coverage: development editorial library only. A licensed, reviewed production catalog and coverage operations are required.
- Signed distribution/revocation: local verifier/checkpoint exists; production signing custody, key rotation, update service, emergency review/recovery and independent audit remain blocked on implementation and operator decisions.
- School managed pilot: deferred until core enforcement acceptance and approved test-device/MDM access. No enrollment, tenant backend, staff console, roster import or identity deployment has occurred.
- ChromeOS/desktop extension: not implemented. The Flutter web catalog is not a substitute.
- Everyday UX breadth: article find-in-page, dedicated browser keyboard shortcuts, production tablet/accessibility acceptance and verified reduced-motion behavior remain deferred/unverified. The current catalog reader supports scrolling and adjustable text; it does not deliver every former browser workflow.
- Learning/support breadth: the small general-support article is not a complete recovery, medication or sexual-health library. Expansion requires scoped editorial review.
- Real review submissions/appeals: no connected inbox or automatic sending. No temporary access while pending.
- Release packaging: Android AOT compiler launch stalled before execution; no release APK was produced. macOS security settings and SDK signatures/quarantine remain unchanged. The release merged manifest passed separately with INTERNET removed.
- Physical-device acceptance: VoiceOver/TalkBack, OS menus/keyboards, startup/capture timing, actual shared-device erase boundaries and store packaging remain unverified beyond explicitly recorded emulator/simulator checks.
- Privacy/legal: complete operator disclosures, student-data contracts, qualified legal review, store declarations and scoped network audit before release. No COPPA/FERPA/CIPA compliance certification is claimed.
- Performance: local measurements are development observations, not physical-device startup percentiles or a speed guarantee.

## Publication boundary

The user requested an audit and first tested milestone and explicitly prohibited push/publication/deployment/enrollment without approval. Changes are committed locally on `permanent-protection/foundation`. Prior Phase3A merge approval does not authorize publication of this new policy change. Nothing is pushed or deployed by this milestone.

## Verification handoff

The implementation is committed locally at `119f64e97f8bf67ccfa9f0e0d09f1fa9ff513c07`; subsequent verification refinements are recorded in the local Git log. The external workspace report `outputs/PERMANENT_PROTECTION_HANDOFF.md` records the exact ending commit without a self-referential commit hash.

| Verification | Observed result |
| --- | --- |
| Host unit/widget suite | **190 passed, 2 optional benchmark skips**, about 5 s; `work/permanent-all-tests-handoff.log` |
| Flutter analyzer | **Clean, 2.3 s**; `work/permanent-analyze-handoff.log` |
| Student and unknown data tests | **12 passed each**; `work/permanent-{student,unknown}-data-tests.log` |
| Commerce policy | **8 passed for each of consumer/student/unknown**, including retired ad defines; no inventory can render |
| Android main, clean Student debug build | **PASS, 22.5 s**; `work/permanent-android-main-clean.log` |
| iOS main, clean consumer simulator build | **PASS, 28.2 s**; `work/permanent-ios-main-clean.log` |
| Web JavaScript release build, full local icon fonts | **PASS, 24.0 s**; `work/permanent-web-main-full-icons.log` |
| Native fixtures and real main app | **PASS on Android and iOS**; two-tab extension, device details and final timings in SECURITY_TEST_MATRIX.md |
| Native artifact removal | **PASS** for audited clean Android debug/iOS simulator packages; no GMA/UMP or retired content/launch plugin implementation. Details and hashes in MONETIZATION_POLICY.md |
| Android release merged manifest | **PASS, 25 s**, no INTERNET; this is a build intermediate, not a release APK |
| Android release APK | **Blocked**, AOT helper stalled before compilation; no release runtime result |
| Local web UI | **PASS** for discovery, body search, article opening and sanitized unknown-URL denial; zero controlled denial-fixture requests in server log |
| Native manual visual/accessibility review | **Blocked by locked Mac**; automated native tests passed but do not replace physical/manual acceptance |

After the expanded integration tests, the actual main-entrypoint artifacts were rebuilt successfully (Android Student debug 14.1 s; iOS consumer simulator 22.8 s) so the standard build paths do not point to a test harness. This is an artifact restore, not another native UI test pass. Logs: `work/permanent-android-main-restored.log`, `work/permanent-ios-main-restored.log`.

The web preview was inspected in the Codex in-app browser through accessibility controls and rendered screenshots. HTTP logs show same-origin Flutter/font/catalog/SQLite assets and no request to the controlled denial path. This is not a browser-wide or device-wide packet audit. Details: `work/permanent-web-ui-observation.md`, `work/permanent-web-preview.log`.

Development measurements: 10 real signed catalog initializations and 1,000 searches on the host gave initialization p50/p95 **11.629/56.775 ms** and query p50/p95 **0.137/0.252 ms**. One separately launched Student debug APK on Android API 36 reported `am start -W` TotalTime **11,497 ms** (cold process, existing data; not reader-readiness timing). Ten seconds later, `dumpsys meminfo` reported **333,313 KB PSS**, **420,748 KB RSS**, **5,750 KB swap PSS**, and **zero WebViews**. Host memory pressure and emulator/debug overhead were substantial. These are observations, not release/physical-device performance targets. Logs: `work/permanent-catalog-benchmark-handoff.log` and `work/permanent-android-main-runtime.log`.

Failed attempts are preserved. Before the clean rebuild, iOS output retained retired frameworks and web generation referenced retired plugins; `flutter clean` plus `pub get` resolved those generated-output issues. A later web icon optimizer stalled before execution; the successful build uses supported `--no-tree-shake-icons` to bundle complete icons, without changing security controls. Android release `gen_snapshot` also stalled at process startup; the attempt was stopped. Sampling showed `_dyld_start` without compiler progress, but does not conclusively identify its cause. Logs: `work/permanent-android-release.log`, `work/permanent-aot-sample.txt`, `work/permanent-font-subset-sample.txt`, and the failed pre-clean build logs.

Baseline: 289 tests passed plus one optional skip; analyzer clean on retry (2.6 s); Android debug 14.9 s, iOS simulator 21.4 s, web 27.8 s. Earlier tests that required optional overrides/live browsing were explicitly retired. Their historical results are not counted as current passes. No production application code changed after the full 190-test/analyzer run; subsequent changes refine documentation and the separately rerun native integration test.
