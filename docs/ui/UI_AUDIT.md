# UI implementation starting audit

Source-only audit, September 11, 2026. The full 313-line [master prompt](../../Wingman_UI_Design_Handoff/WINGMAN_UI_MASTER_PROMPT.md), [START_HERE](../../Wingman_UI_Design_Handoff/START_HERE.md), and [reference notes](../../Wingman_UI_Design_Handoff/DESIGN_REFERENCE_NOTES.md) were read. This audit records the starting point for implementation; it does not substitute for the requested Flutter redesign, builds or visual inspection.

## Baseline and evidence

- Branch: `ui-handoff/implementation`.
- Application HEAD: `d5ca5ba7087e91f7f50b3b073960f7187a767e69`, version `0.5.0+5`; prior implementation commit `9105b94`.
- Initial status: only untracked `Wingman_UI_Design_Handoff/`; application files were clean. The handoff was retrieved by the root task from upstream main `a9b3765`; that is design provenance, not an application reset target.
- The handoff reviewed old source `060839b8b656f89ea1a1998b2843f3322f7e33b3`. Mandatory protection and the seven local signature features were implemented later. Preserve the current architecture and behavior.
- This audit ran file/Git inspections only. **No Flutter, Gradle, browser or native commands were run for this source inventory.** Previous acceptance records are cited below, not relabeled as new UI test results.
- The HTML reference contains 26 synthetic compositions. Its screenshots, contrast arithmetic and `REFERENCE_QA.json` are reference evidence only, not app acceptance.

The [screen registry](SCREEN_REGISTRY.md) accounts for all 51 written flow IDs plus reachable overlays. Every initial row is design-pending even when baseline functionality exists.

## What is implemented and must survive

The app renders 18 signed, reviewed, original offline articles. Mandatory categories and positive eligibility are enforced independently of appearance. No live WebView, network search, sign-in, website permissions, website downloads or external-link launcher is available. A familiar official identity, signed article source URL, Space resource or restored task cannot authorize live content.

Startup checks the persisted handoff marker before owner state is constructed, initializes policy/checkpoint and quarantines legacy native content before loading normal SQLite state. Quarantined earlier titles/addresses are not shown. Reviewed bookmark/read-list IDs are distinct from raw legacy tables. Private signature tools use separate memory state and exclude normal saved analyses, workspaces and journal data. Theme/layout work must preserve these boundaries.

The current consumer features are real local implementations:

| Feature | Actual baseline behavior | Boundary to keep explicit |
|---|---|---|
| Official Routes | 18 reviewed identities, local search/region filter, exact evidence/expiry, related eligible Wingman guides | Identity evidence does not grant live eligibility; live opening remains disabled; no review endpoint |
| Before You Commit | Explicit bounded English text, six deterministic finding categories, excerpts/positions/time/conflicts, optional normal save/delete | No current webpage extraction, cloud analysis, merchant action, complete understanding or legal verdict; findings export not yet present |
| Spaces | Three explicit templates, local notes/checklists, chosen reviewed resources, reorder/delete, unit tool, Learning saved list | No inferred interests, live sports scores/schedules, paid course copies or hazardous project instructions |
| Finish Mode | Goal/checklist/notes, explicit task-tab ownership, pause/resume, finish/save/close choices and scoped undo | Saved task restoration is policy checked; ordinary tabs are transient; no private restore or late closure of unrelated tabs |
| Hand It Over | Supported native static reviewed text, root owner gate, fresh owner code, durable restart protection | Not interactive browsing, kiosk mode or OS-biometric authentication; unavailable on web; no private sharing |
| Trust Receipt | Coarse local typed observations separated from configured and unobservable behavior; explicit copy and clear | No raw URLs/query/text/interests; no zero-data-leaves or exhaustive network-observation claim |
| Compatibility | Minimal user-reviewed clipboard report; constrained exact-resource profile mechanism | No submission backend; no active production profiles; a test-only wrapping fixture is not a deployed repair |

## Old handoff paths versus the actual app

| Handoff-era area | Actual current source / change |
|---|---|
| Separate `omnibox.dart`, `browser_toolbar.dart`, `browser_page_error.dart` | Removed; `BrowserShell` owns inline local search, local article trails, notice cards and AppBar tools |
| Separate `library_screen.dart`, `reader_screen.dart`, `settings_screen.dart` | Removed; reviewed-ID saved destinations, article reader and Settings sheet are in `lib/presentation/browser_shell.dart` |
| Optional Guard settings/surfaces and PIN overrides | UI removed and legacy controllers neutralized; `lib/policy/` is authoritative; immutable rules are displayed in Shell |
| Native WebView page controller | `lib/browser/browser_engine.dart` is a fail-closed compatibility adapter; native bridges deny live content rather than allocate a renderer |
| Brand widget / shared blue design system | No baseline brand wrapper or shared component layer; `lib/presentation/theme.dart` supplies a small green/gold Material 3 theme |
| New seven feature interfaces | Already present under `lib/signature/`; redesign these actual screens and preserve their controllers/callback contracts |
| Root normal/private browser restoration | `SignatureApplicationRoot`, HandoffGate, `BrowserState`, `DiscoverySession` and scoped SignatureServices have distinct responsibilities; do not collapse them into a visual router |

Retained legacy codecs, database methods and earlier native test files are not proof of reachable old UI. New library transfer/clear behavior should act on validated reviewed IDs, not surface raw quarantined HTTP data.

## Source-confirmed design gaps

1. **Brand and tokens:** the baseline theme is green/gold (`#135F51`, `#F6C969`), with hard-coded surface/card/input spacing. The requested navy/blue/cyan semantic system, logo wrapper, motion/focus/state tokens and shared components are not implemented. Roboto and Noto Sans Symbols are already bundled; preserve them and avoid new font requests.
2. **Home and navigation:** current Home begins with a large two-line headline and full catalog list. It lacks the requested logo, compact selected shortcuts, dedicated focused entry/cancel flow and Home customization. Main navigation is Discover/Bookmarks/Reading list. Local article Back/Forward controls work on a local trail; these must not be misrepresented as live web navigation.
3. **Chrome and hierarchy:** tools are spread across AppBar actions, page menu, article controls and sheets. Signature screens use independent Scaffolds; feature routes must retain a clear back-to-origin path without duplicated browser toolbars. Existing async route/tab ownership guards are required behavior.
4. **Library and Settings:** two saved destinations replace a unified Library. Settings is one long sheet with theme, article scale, collection restrictions, quarantine count and reset. Reset lacks a confirmation in the baseline. A selected-category clear flow needs dedicated state operations and durable completion. Existing bookmark removal requires current approval, so it is not sufficient for deleting an expired stored ID.
5. **Missing useful local slices:** consumer welcome, dedicated request-review preview/export, Help Now, full Help/About/licenses, approved-ID import/export and finding export are not complete reachable flows. These can be implemented locally without enabling live browsing or claiming a backend.
6. **Capability placeholders need deliberate treatment:** live search providers, site info/permissions, website downloads, TLS retry and browser media are unavailable. Show honest bounded capability states where navigable; do not add cosmetic enabled controls or inactive fake data to satisfy a mockup.
7. **Adaptive/accessibility work:** current Shell uses broad fixed padding and max widths 900 for discovery/760 for articles; sheets use viewport-height fractions. It has no complete handoff breakpoint/token system. Home active-task text is limited to two lines with ellipsis. Existing tests include selected 1.6× text/size checks, but do not establish the requested 200%/largest text, keyboard, screen reader, reduced-motion or full width matrix.
8. **Transient surfaces:** initial loading, inactive covers, storage failures, selection validation, private hidden lists, pending writes, all confirmation dialogs, task undo, guest keypads and clipboard outcomes must receive the same pass as major pages. The registry enumerates these separately.

These are source findings. This audit makes no new claim about visual clipping, pixel contrast, native touch behavior or rendered performance; those require actual screenshots and runtime checks during implementation.

## Protection prerequisites and implementation constraints

The existing foundation has tested mandatory-policy, migration, lifecycle and native hard-denial paths. The UI prerequisite is to preserve and re-run them, not restore optional Guard controls from the old handoff. Policy status must be read dynamically; expiry/revocation can invalidate a visible article, a saved analysis source, a picker item, or a restored task. A lock icon alone is not enforcement.

Use the actual current consumer context. Do not foreground school controls, monetization, subscriptions, ad SDKs or accounts. Additional restrictions subtract from eligibility and cannot alter the six core categories. A support article still requires a valid review; neither a Help button nor a review request creates an exception.

Keep explicit clipboard disclosure and local-only receipt/report semantics. Request/review UI must not automatically carry a blocked URL, query, private path or account data. Preserve restricted OS text-selection actions. Android secure capture and iOS privacy covers must remain enabled; visual fixture capture needs a separate debug-only gallery and must be labeled as synthetic.

## Evidence carried forward, and what remains to verify

The previous delivery's [feature acceptance](../FEATURE_ACCEPTANCE_TESTS.md), [status](../SIGNATURE_FEATURES_STATUS.md), [capability table](../PLATFORM_CAPABILITIES.md) and [actual web screenshots](../SIGNATURE_SCREENSHOTS.md) record 326 passing host tests plus two optional benchmark skips, a clean analyzer, Android debug/iOS simulator/web builds, native protected/signature journeys and four preserved-install native handoff phases. These are baseline evidence, not redesigned-UI acceptance. Recorded screenshots are from the compiled 0.5 web companion, unlike the handoff's HTML previews.

Previous evidence also records slow/unexplained owner-root reopening in an iOS run and an Android diagnostic retry. Android release AOT was not verified because an earlier local toolchain attempt stalled; debug artifacts are not release acceptance. No physical-device/store-signing, full accessibility or production-scale performance claim follows from the recorded emulator/simulator tests.

For this design milestone, run meaningful focused behavior tests plus the regression suite, analyzer and supported builds after coherent source changes. Inspect actual light/dark screens at 320, 360, 390, 430, 600, 768, 1024 and 1440 logical widths, short heights, keyboard/insets and large text. Test policy-invalid/private/storage-error states without prohibited sites or production data. Record real build mode/device/frame and memory context; reference HTML QA and golden generation alone do not satisfy visual review.

## Initial implementation sequence

1. Root establishes blue semantic tokens, preserved logo assets, shared page/section/status components and a debug-only gallery. Keep runtime policy state separate from visual fixtures.
2. Rebuild Home/focused local search, real local article chrome, tabs and welcome. Preserve session scope and origin-navigation behavior.
3. Build coherent reviewed Library, Reader, Settings, Protection, Help Now and safe local clear/transfer slices. State/API work precedes claims of durable success.
4. Restyle and complete all seven signature interfaces. Official review requests and analysis export are bounded local additions; native Handoff remains static and capability gated.
5. Update registry status from connected code and actual test evidence; complete adaptive, accessibility, performance and screenshot QA. Record remaining live/remote/physical-device gates explicitly.

This audit and registry are initial planning deliverables. Application implementation continues; neither document marks the UI handoff complete.
