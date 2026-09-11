# Spaces and Finish Mode UI

The UI uses the existing `WorkspaceController`, persisted document schema, eligibility checks and root tab-ownership callbacks. This change does not add network content, inferred interests, website storage isolation, hidden timers or an automatic completion signal.

| Flow | Implemented surface |
| --- | --- |
| S01 | Your Spaces hub, chosen-space cards, explicit Home switch, calm empty state and keyboard-accessible move-up/move-down controls. |
| S02 | Three supported templates; a full local rename editor, chosen topics/sports, eligible-resource picker and confirmed deletion. Arbitrary custom collection types or editable icon libraries have no existing model and are not presented as working controls. |
| S03 | Home Projects detail with reviewed resources, local notes/checklist and the existing tested measurement converter. |
| S04 | Learning detail with explicit topic choices, resource provenance, eligible reading list and local notes. |
| S05 | Sports detail with chosen sports, owner-written team/competition notes and an official-source evidence action. No live score, schedule or betting feed is claimed. |
| T01 | Finish Mode list with real active/paused/finished status, local goal editor and a meaningful empty state. |
| T02 | Task detail with checked-item progress, associated tabs, existing pause/resume/associate/detach callbacks and local notes/checklist. |
| T03 | Explicit save-results and close-associated-tabs confirmation, actual tab/checklist counts and the existing private/normal undo distinction. |

Cards use two columns when enough room exists and the text scale permits them; otherwise they stack. A Create a Space action opens a real, bounded template picker near the top of the hub. Saved-item and reorder controls occupy their own row, so long titles do not compete for the same horizontal space. Details and forms have a 720-pixel maximum measure. The measurement tool opens explicitly, keeping reviewed resources in view by default. Its unit controls stack at narrow widths or large text. Busy labels reflect actual pending operations and have a static reduced-motion presentation.

The local text editors keep their existing input bounds, disabled personalized learning and copy/cut/paste/select-all-only context menu. No route callback or delayed tab-ownership decision was removed. Handoff still receives only currently eligible public resource IDs, limited to the existing eight-resource maximum.

`test/ui/workspace_layout_test.dart` exercises both themes at 320×640 and 1100×800 with 200% text. It uses real in-memory workspace controllers to create/rename/reorder templates, convert a value, edit notes, update selected choices, invoke an eligible handoff and finish a task with explicit close selection. `workspace_visual_test.dart` creates synthetic 390×844 captures for S01–S05/T01–T03. Capture flags exist only in tests. The first 10 focused tests passed in 4 s after correcting the progress control’s numeric accessibility value (`work/ui-workspaces-final.log`). A source-and-capture comparison then found oversized hub cards and an over-prominent converter; these were reduced and the create action moved near the top. The revised reflow tests, capture journeys and three tool-gallery initialization tests then passed in the full 402-test run (25 s, two optional benchmark skips), with clean full analysis (2.4 s): `work/ui-full-test-first.log` and `work/ui-full-analyze-first.log`. All 16 S/T light/dark captures were inspected after refresh.

These tests and renders are not native keyboard, screen-reader or physical-device acceptance evidence. The mandatory content boundary and existing task persistence/restart tests remain separate requirements.

`tool/ui_gallery/workspace_handoff_scenes.dart` supplies development-only synthetic scenes. It uses memory stores, verifies bundled policy into memory, intercepts outward actions and exposes an explicit demo-only Handoff store/derivation. Its banner is not production protection: the real app never imports the fixture, and web handoff remains unsupported.

The debug gallery entrypoint initializes `gallery_clipboard_binding.dart` before any ordinary Flutter binding. It intercepts Flutter `Clipboard.*` calls: reads return empty and writes never reach the host or retain supplied text. Other platform channels and incoming handlers are forwarded. A late initialization fails instead of silently leaving ordinary clipboard access active. This is a tool-only Flutter API boundary, not control over separate OS/browser actions. All three focused messenger tests passed in the coordinated 13-test follow-up, covering suppression, forwarding and malformed/late initialization (`work/ui-home-gallery-final.log`).
