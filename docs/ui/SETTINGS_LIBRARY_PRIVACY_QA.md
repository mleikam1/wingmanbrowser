# Settings, protection, library and privacy UI

These routes implement G01–G06, P01–P06, L01–L07, R01–R02 and X01–X03 against the existing signed offline-content boundary. No browser engine, arbitrary URL importer, website permission grant, ad SDK, report backend or automatic contact action was added.

## Actual behavior and boundaries

Settings uses dedicated routes for appearance, search, privacy, capabilities and About. Theme, article scale and local-suggestion preferences await durable state writes and preserve the previous preference after a failure. Version/build comes from `AppBuildInfo.current`. Home customization stays owned by the root preferences controller.

G04 confirms the selected categories before dispatch. It observes the root's retained deletion future after a timeout or reopening, without starting another native operation. Controls remain unavailable while that future is pending. Completion and failure are reported per category. Session clearing captures tab identities before any wait, preserves newer tabs and an unrelated active route, and keeps bookmarks/reading saves unless those categories were separately selected. Private routes do not show normal library counts or attach to a normal pending clear.

The library shows currently eligible reviewed IDs. Bookmarks support local search, add, delete and explicit reviewed-ID import/export; reading state supports Unread/All/Read. JSON imports are bounded to 512 KiB and 5,000 rows, count duplicates/rejections and require a merge confirmation. Eligibility is checked again at the durable commit. Export has an exact preview and explicit clipboard confirmation; other apps or OS clipboard services may access exported IDs. File pickers, arbitrary address imports, custom titles and folders remain unavailable.

**Unavailable-item cleanup:** safe-format saved IDs retain their existing 5,000-bookmark/500-reading-item bounds across restart, including when policy is unavailable. Content, routing and export still require current approval. Bookmarks and Reading list show only an aggregate unavailable count and offer a confirmed removal of that captured group; titles and IDs stay redacted. The deletion-only API subtracts those selected references from the latest saved state, preserving eligible/newly saved items, the other library group and legacy quarantine. Reading-list cleanup also removes the selected read marks. Private or closed-origin actions cannot clear normal saves. Individual redacted-row selection is not offered; G04 still supports an explicit whole-group clear.

History is a counts-only explanation of quarantined earlier records. Downloads explains the unavailable capability and preserves completed legacy files. The Reader displays exact reviewed installed text, source attribution and adjustable article scale, and hides body/title after policy invalidation. It is not website extraction on either mobile platform.

Protection separates immutable core policy, limited catalog coverage, additional restrictions and unavailable live controls. Optional restrictions never approve a previously denied destination. Each toggle updates its own field against the latest queued state, so another form cannot replace a choice saved while it awaited storage. Help Now implements an optional local one-minute pause and user-selected reviewed support resources; no calls, messages or service notification occur. TLS/threat error variants have no bypass and are **synthetic gallery states**, because there is no live transport to produce those failures in the current app.

Receipt detail expands typed purpose/destination/outcome categories. Configured behavior, observed events and unobservable behavior remain separate. Copying uses the reviewed snapshot; a changed snapshot requires re-review. Compatibility reports contain only the fixed coarse diagnostics and an optional explicitly reviewed domain. Report preparation/copying never submits anything. The actual correction registry supplies its sequence and active count; the production registry is empty, so no repair is advertised as active.

## Focused evidence

- `test/ui/settings_library_protection_test.dart`: 18 functional cases, including durable failure, import bounds, closed-scope export, private visibility, pending-clear reopening, reading filters and policy revocation.
- `test/ui/clear_data_navigation_test.dart`: five passing real root callback regressions with delayed workspace writes. A clear preserves newer tabs and normal newer routes, removes destroyed private Workspace/notes-dialog routes, and completes after shell teardown with a retained session. The captured-menu case denies old normal menu saves after clear selects a private tab.
- `test/ui/retired_library_cleanup_test.dart`: six passing cases cover restart/unrelated-save durability, redaction/cancel/selected deletion, queued-write preservation, read-mark cleanup, storage failure and private/closed/input boundaries.
- `test/ui/additional_boundary_races_test.dart`: three passing cases cover real two-form delayed toggles, failure preservation and private/support boundaries.
- `test/data/database_close_coordinator_test.dart`: two passing cases exercise both actual database owners with delayed native-close callbacks and verify nonoverlap, caller-visible failure and progress of the next close.
- `test/ui/privacy_compatibility_layout_test.dart`: four cases covering both themes at 320px/200% text, closed-scope clear cancellation, issue selection, reviewed copy and no diagnostic submission.
- `test/signature/privacy_export_widgets_test.dart`: six retained receipt/report privacy and asynchronous-export regressions. Lazy controls are revealed before interaction; safety assertions remain.
- `test/ui/settings_protection_visual_test.dart`: two cases exercising G01/P01/L02 across all eight handoff widths at 200% text, plus real Flutter captures at 390×812 in both themes.
- `test/ui/font_face_loading_test.dart`: all-family weights 400/500/700 render pixel-identically to separately aliased exact Regular/Medium/Bold faces. No dynamic font-loader override was found. Production font files were unchanged.

The final host run passed **431 tests**, with two optional benchmark skips, in 26s (`work/ui-final-test-2.log`, parent workspace). Full analysis was clean in 2.4s (`work/ui-final-analyze-2.log`). This includes every case listed above. Earlier focused/capture logs remain `ui-owned-routes-tests.log`, `ui-clear-navigation-final.log`, `ui-owned-routes-analyze.log`, `ui-gpl-visual.log` and `ui-font-face-diagnostic.log`. The Android signature journey also passed its same-process owner-root reopen after serialized database closure (`ui-native-signature-android-coordinator.log`, 18s, debug emulator). A later iOS run exposed a distinct redundant WebKit startup-purge delay; its failure and diagnostic logs remain retained. After adding a success-only, process-local startup acknowledgement, final iOS boundary and signature tests passed (`ui-native-guard-ios-quarantine.log`, 2s; `ui-native-signature-ios-quarantine-fixed.log`, 13s). They verify the first actual purge, reuse only after completion, explicit user clearing, zero content views and real root reopen (462ms). No timeout was increased. Detailed close evidence and its limits are in [Privacy architecture](../PRIVACY_ARCHITECTURE.md). Broader native/Web acceptance is recorded by the root handoff report; these observations do not establish store or physical-device readiness.

## Visual comparison and remaining review

Source: `Wingman_UI_Design_Handoff/reference-previews/guard-dark.png` and `settings-dark.png`. Actual synthetic Flutter captures: [Protection dark](screenshots/gpl-p01-dark.png), [Protection light](screenshots/gpl-p01-light.png), [Settings dark](screenshots/gpl-g01-dark.png), [Settings light](screenshots/gpl-g01-light.png), [Bookmarks dark](screenshots/gpl-l02-dark.png), [Bookmarks light](screenshots/gpl-l02-light.png).

Reference and actual images were opened together at 390×812, density 1. The reference includes an illustrative status bar/device corner mask; the widget capture contains app-owned content only. Those infrastructure differences are excluded. Full-size controls were legible without a separate detail crop.

P01's first capture lacked the source's major hero and visible policy rows. The revised capture restores the navy/blue hero, white title, cyan standard shield, compact immutable category rows and separate coverage caution. Coverage copy intentionally describes 18 reviewed offline articles rather than the obsolete starter-filter/live-browser model. Colors use shared tokens; supplied artwork and native device infrastructure were not recreated. The final face raster test confirmed real font-weight selection.

G01's first comparison found oversized group headings, duplicate section spacing and missing raised icon tiles/dividers. The final Settings source uses 16px group labels, 14px secondary text, 40px raised icon tiles and dividers, and removes the duplicate spacing. The linked light/dark G/P/L captures were refreshed. Actual release Web G01/P01 rendering was inspected against the source in the combined [Settings comparison](screenshots/comparisons/settings-dark-runtime.png) and [Protection comparison](screenshots/comparisons/protection-dark-runtime.png), including the corrected G01 hierarchy. Capability-specific copy and resulting wrapping remain intentional; these checks do not claim pixel-identical rendering. The overall visual assessment is recorded in [Design QA](../../design-qa.md).

## Development gallery mapping

`tool/ui_gallery/settings_library_scenes.dart` exports `SettingsLibraryGalleryMenu` and `SettingsLibraryGallery`, connected only from `tool/ui_gallery.dart`. The menu is labeled synthetic; fixtures use memory state/checkpoints/journals, intercepted clipboard calls and a simulated deletion completion timer. No owner storage or native deletion is opened. Production `lib/main.dart` does not import the gallery.

| Scene | Handoff state |
|---|---|
| `settings` | G01–G06 real route navigation and in-memory preference writes |
| `privacy` / `pendingClear` / `failedClear` | G04 selection, confirmation, pending-to-complete, failed |
| `protection` | P01–P03 policy overview, details and additional switches |
| `unreviewed` / `unavailable` | P04 actual typed policy decisions |
| `tls` | P05 explicitly synthetic security error; no live capability |
| `help` | P06 local pause and reviewed support |
| `library` / `bookmarks` / `privateLibrary` | L01–L02 hub, saved items, private normal-library exclusion |
| `importBookmarks` / `exportBookmarks` | L03 strict reviewed-ID preview and intercepted export |
| `reading` / `history` / `downloads` | L04–L06 actual reading state and capability explanations |
| `reader` | L07 exact approved text |
| `receipt` | R01–R02 typed local observations and reviewed export |
| `report` | X01–X03 optional minimal report and actual empty registry |
