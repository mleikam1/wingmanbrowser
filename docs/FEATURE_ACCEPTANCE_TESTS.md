# Signature feature acceptance evidence

This document distinguishes implemented behavior, automated fixtures, and device observations. The signature milestone starts from commit `2171bce` on `signature-features/consumer`. The baseline recorded 190 passing host tests, two intentional benchmark skips, a clean analyzer, and Android debug / iOS Simulator / web release builds. Baseline logs are `work/signature-baseline-*.log` in the parent workspace. They are not evidence that later feature changes passed.

The mandatory boundary remains reviewed signed bundled plain text. The application has no live WebView renderer, authenticated website session, outbound search, or unrestricted external launch. Tests of historical live browser engines do not establish current live support.

## Feature scenarios and relevant tests

| Feature | Concrete implemented journey | Automated evidence | Acceptance boundary |
| --- | --- | --- | --- |
| Official Routes | Search a task/organization locally; choose region; inspect exact address, evidence and review dates; open a separately eligible Wingman guide | `test/signature/official_routes_test.dart`, `route_commit_screens_test.dart` | 18 real identity records reviewed against primary sources. Live opening remains **disabled pending review**. No active badge or launch exists for a policy-ineligible route. |
| Before You Commit | Paste selected visible English terms or choose the invented practice example; inspect six topics with exact excerpts/sections/time; explicitly save/delete a normal local snapshot | `commit_review_test.dart`, `route_commit_screens_test.dart`, integrated workspace receipt journey | Local bounded extraction only. No live DOM, merchant authentication, cloud AI, linked-term crawling or transaction. Private saved-list reads/writes are blocked. |
| Your Spaces | Create Home Projects, Learning and Sports; edit notes/checklists; reorder and disable; save eligible resources; use dimension conversion; reopen persisted state | `workspace_state_test.dart`, `workspace_restoration_test.dart`, `integrated_workspaces_test.dart` | Original signed local guides and explicit choices. No scores/feed/backend interest profile. Owner/private state and additional restrictions remain distinct. |
| Finish Mode | Create a goal; associate actual tabs; keep notes/results; pause, restore, finish; explicitly close only owned tabs; undo ordinary closure | `workspace_state_test.dart`, `integrated_workspaces_test.dart`, `workspace_navigation_races_test.dart` | Tab association is organization, not website-storage isolation. Private closure has no undo. Late writes may complete their original durable intent but cannot attach an unrelated current tab or steal a newer route. |
| Hand It Over | Preview approved public text, confirm owner return code, activate a static guest view, and authenticate return | `handoff_test.dart`; `integration_test/handoff_security_test.dart` start/resume phases | Static read-only sharing only. No website state/cookies/credentials are copied. Native interrupted-session marker and return behavior require actual platform tests; web is unavailable. Not a device kiosk. |
| Trust Receipt | Inspect actual typed event outcomes and configured policy/state; preview a sanitized optional local export | `privacy_journal_test.dart`, `privacy_export_widgets_test.dart`, integrated receipt journey | Bounded coarse events, no raw content/queries. Distinguishes observed/configured/unknown behavior. No complete network-observability or third-party no-collection claim. |
| Compatibility Repair | Preview a minimal local diagnostic; explicitly export; inspect/apply a narrow eligible bundled-reader correction fixture | `compatibility_test.dart`, `privacy_export_widgets_test.dart` | No diagnostic endpoint or live-site repair is configured. Declarative profile validation and a tested local reader fixture do not establish production website compatibility. |

All short test filenames in the table are under `test/signature/`. Additional baseline invariants remain in `test/policy/mandatory_policy_test.dart`, domain/data/state tests, and `integration_test/protected_app_test.dart`.

## Recorded validation

Final host and build totals are maintained in [implementation status](SIGNATURE_FEATURES_STATUS.md). Focused development runs cover 24 route/analysis cases, 26 privacy/compatibility cases, strict restoration, real SQLite v4 migrations, secure handoff, private-session teardown and delayed navigation. The final full suite supersedes those overlapping counts; they must not be added together.

The four new original guides were signed using the external development key. Existing fourteen signed record rows and the public key were preserved. `work/signature-catalog-sign.log` contains no seed. This is a development editorial/catalog check, not an independent certification or production review service.

## Cross-feature failure cases

The focused fixtures exercise exact destination matching and lookalike rejection; mandatory denial despite identity review; expired/revoked/malformed records; unsupported schemes, content and languages; corrupted/oversized local documents; explicit save errors; evidence limits; hostile text treated as data; private storage exclusion; cancellation after editing, route changes and backgrounding; current signed-body resolution; and policy rechecks before preview/navigation/save.

Workspace fixtures cover preserving unrelated tabs, rejecting claimed ownership from saved documents, revalidating undo, disposing private state, sequential durable writes, failure preservation, and nested restored-data bounds. The delayed-write screen fixtures exercise normal-to-private tab changes, a popped/reopened workspace, a newer route covering restoration, finishing after leaving its route, and dismissing the tab sheet during a durable detach. Saved references and live ownership must agree without a late operation closing a newer or unrelated tab.

Privacy export fixtures use injected clipboard/file ports to distinguish canceled dialogs, backgrounding, blocked continuation, persistence/export failure, and actual completion. They do not claim a real OS save dialog ran on every target. Handoff host fixtures exercise marker/read/write failures, expiry, policy changes, owner-tree removal, code checks, delayed writes and retry boundaries. Native tests must separately validate the platform secure marker across actual process restart.

## Manual review journeys

The following are review instructions, **not assertions that a manual pass occurred**. Record platform, build, date, actual result and screenshot when performed.

1. On Home choose Official search, search “passport,” choose the region, and inspect evidence. Confirm live opening is disabled and that a related guide is labeled Wingman content. Try an absent organization and a deceptive URL; no invented approval or external action should appear.
2. Open Before You Commit from Page tools. Use the clearly labeled practice example; verify trial, price/interval, cancellation, refund and seller excerpts. Paste conflicting prices, remove cancellation text, select another language, and edit after a check. Save only after confirmation, then delete. Repeat in private: no normal saved findings or save control should appear.
3. Create all three Spaces, edit a note and checklist, reorder them, and try length conversion. Restart the normal app and verify explicit choices restore. A new private session must not inherit normal/private notes. Expired/restricted guide IDs must lose previews while the saved user record itself is preserved.
4. Start a Finish task with two associated tabs and keep an unrelated tab. Pause/resume, finish with the explicit close choice, and verify the unrelated tab survives. Undo a normal closure; private closure must offer no undo. A slow-write test must not select an old task after leaving its screen.
5. On a supported native device, preview Hand It Over, confirm the return code, and enter static sharing. Try back navigation, background/resume and process restart; owner tabs, notes, findings and settings must remain absent until authenticated return. Confirm normal owner data survives ending the session. Web must clearly report unavailable.
6. Open Trust Receipt after analysis and a failed/canceled optional export. Compare configured local behavior with the observed event outcomes. Preview its sanitized fields before export; no raw selection or goal should appear. Do not treat the receipt as a full website/OS packet log.
7. Open Something isn't working, choose an issue, review minimal fields, and cancel/export locally. Confirm there is no submitted-success claim without an endpoint. Apply the controlled bundled-reader compatibility fixture and confirm prohibited/unknown sibling content remains denied.

## Actual runtime review on September 11, 2026

The compiled web companion was operated in the Codex in-app browser at `http://127.0.0.1:8791/`. The following actions were actually performed:

- Searched “passport” locally, compared US/UK/Canada results, and inspected HM Passport Office canonical address, primary evidence and review dates. Live opening remained disabled.
- Created all three Spaces. Selected Science for Learning and Basketball for Sports. Converted 12 feet to 3.6576000 metres. Sports displayed local reviewed guides and its no-live-feed disclosure.
- Created and associated the review task “Review example: read two guides,” paused it, reloaded the browser, observed all three Spaces and the paused task restore, then resumed it. The original ordinary tab remained alongside the restored task tab.
- Ran the clearly invented practice terms through the actual local analyzer; inspected trial, monthly USD charge, cancellation, refund and seller excerpts; explicitly confirmed a local save and observed its saved entry.
- Inspected Trust Receipt and its actual completed analysis/save and workspace events, separate from configured disabled history/sync/cloud/live content.
- Previewed a layout-issue report without a domain, explicitly copied it, and observed the clipboard-completion disclosure: other apps/system clipboard services may access the copy; nothing was submitted.
- Reloaded the final rebuilt web output, observed the three saved Spaces and active task restore, opened a signed article, and confirmed the Hand It Over menu item is disabled and labeled “unavailable here.”

[Actual screenshots](SIGNATURE_SCREENSHOTS.md) document these states. Unperformed manual scenarios above remain review instructions; the automated negative fixtures provide separate evidence. No real transaction, external search, diagnostic submission, cloud request, score feed, or interactive website handoff occurred.

Native `protected_app_test` runs passed on both Android and iOS with actual main-entrypoint catalog search, article opening, bookmark/read-later actions, two tabs, locked core restrictions and unknown-URL denial. Native signature tests exercise the five tool screens, three explicitly synthetic Spaces with notes/checklists, a paused task, analysis saving, and real SQLite close/application-root reopen. Root reopen is **within one process** and is not labeled process death. Actual separate-process restart evidence belongs to the handoff start/resume tests. See [handoff security](HANDOFF_SECURITY.md) for exact native flags, real keyboard positive controls, secure marker/code behavior and the Android OS VIEW injection checks.

The first Android signature run timed out waiting for the second owner root after teardown; an instrumented retry passed without reproducing the timeout. Its cause is unconfirmed, and the failed log is retained. This is a release-hardening concern, not a claimed fixed defect. Final counts, platform timing and build outcomes are in [status](SIGNATURE_FEATURES_STATUS.md).

## Network and measurement limits

Source review used development research tools to open official references. That research traffic is not app traffic. The compiled web runtime's observed page-asset inventory contained 33 local-origin resources: 6 fonts, 3 scripts, 23 other resources and 1 local favicon. Observed origin: `http://127.0.0.1:8791`; browser console warning/error inspection returned none. The inventory covers observed resource entries, not every worker, non-asset request, OS service or browser/provider request. It is not a packet trace or proof that no data left the device. Raw observations are in parent-workspace `work/signature-web-assets-final.json` and `work/signature-web-export-ax.txt`.

Controlled native denial servers received zero requests, and native capability queries observed zero content WebViews during the protected and handoff journeys. Debug VM-service/build tooling is separate from Wingman feature traffic. There is no active embedded website renderer to audit; OS/engine cleanup or provider-security traffic is not fully instrumented by Trust Receipt. The source/dependency and final-artifact inspection are complementary evidence, not a replacement for runtime observations.

Performance observations distinguish host microbenchmarks, native debug integration intervals and actual process IDs. New-feature baselines are unavailable because the features did not exist. `main`-to-settled/tools measurements include asynchronous initialization and test pumps; they are not isolated raster/Home-render latency or physical cold-start percentiles. Full UI-thread profiling, low-end phones, physical-device accessibility and production packaging remain release work. See [status](SIGNATURE_FEATURES_STATUS.md) for the actual samples and baseline build comparison.
