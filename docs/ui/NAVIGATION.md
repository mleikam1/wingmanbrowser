# Navigation and session boundaries

The implemented application opens signed reviewed plaintext resources. It has no live WebView, unrestricted web search, external-browser launcher or live download action. Official identity evidence never grants content eligibility. The handoff's live page illustrations therefore map to a real offline article surface and explicit capability states. The route inventory and implemented/unavailable distinctions are in [SCREEN_REGISTRY](SCREEN_REGISTRY.md).

## Three different lifetimes

| Layer | Owns | Does not own |
|---|---|---|
| Flutter `Navigator` | Feature pages, search entry, dialogs, evidence, confirmation and ordinary Back dismissal | A website's browsing history or the host browser's tabs |
| `DiscoverySession` / `DiscoveryTab` | Memory-only app tabs, active tab, reviewed-resource trail, local search state and reading offsets | Persistent ordinary browsing history, cookies or live renderer instances |
| Policy, BrowserState and signature repositories | Signed eligibility/checkpoint; normal reviewed saves, settings, chosen Spaces/tasks/findings and coarse receipt documents | Permission to render unknown content, private owner-data persistence or automatic cloud sync |

`SignatureApplicationRoot` owns the durable controllers and the memory discovery session above the Hand It Over gate. Feature pages are pushed above the existing Shell. Closing a feature normally reveals the same originating tab and reading position; changing theme does not reconstruct a renderer. No renderer exists to keep alive for a thumbnail.

## Startup and first run

`main` reads the secure handoff marker before constructing owner data, then initializes signed policy and awaits native quarantine of earlier live content. `HandoffGate` decides whether the owner tree may be built. Owner loading opens BrowserState/repository; optional signature tools initialize separately so their restoration does not hold the ordinary Home load indefinitely.

`WingmanApp` chooses Welcome until `onboardingComplete` is saved. Get started performs a durable settings patch; a failed save leaves Welcome visible with an inline error and a retry. Success publishes the preference and opens Home. This is a local preference, not an account, subscription, terms submission or protection switch. An unreadable local repository can prevent durable first-run completion; the UI must not claim that its welcome preference was saved in that state.

The outer startup failure surface does not render an owner page or grant content. A restored guest marker continues to gate the entire owner navigator. Owner data, chosen theme and private tools are not loaded into the guest UI to make its styling match.

## Home, search and reviewed articles

Home shows one search entry and local shortcuts. The entry and article title control open `FocusedSearchScreen`; they do not create a second editable omnibox. Search uses the local signed library, with a separate explicit Official segment for the local identity catalog. Private mode excludes normal saved suggestions. Editing controls exclude OS lookup/process-text/external actions that could create an outbound escape.

The focused route returns a `SearchIntent` to its captured origin. The Shell checks that it remains mounted, foreground, on the same tab, and outside a handoff before applying that intent. URI-like input produces a typed policy/capability state; it is not converted into an outbound query or retained as a displayed blocked address. Reviewed result IDs and feature links are checked again immediately before opening.

Each tab begins with a Home entry. `visit` truncates its forward branch when a new reviewed page is visited and bounds the trail to 50 entries. Native Back and Forward move within that reviewed-resource trail; unavailable IDs are re-evaluated rather than trusted because they occur in history. Home uses the active tab and visits its start surface. New Tab is the explicit operation that creates another session.

A rejected destination does not append an unreviewed ID/URL to the trail or replace the originating reviewed article. The denial page uses the ordinary app stack; Back dismisses it, while its Home and Explore actions deliberately return to the Shell and choose those surfaces. A saved ID, catalog identity, shortcut or human-readable source URL is never itself an access grant.

## Native and web chrome

Native keeps **Back · Forward · Home · Tabs · Menu** in stable positions. Availability reflects the app's actual reviewed-page trail. Above it, an article has an information/title control and an installed-text indicator; there is no fake Reload/Stop state for a website that was never loaded. Feature forms have their own back header and do not duplicate the dock.

The web companion has **Home · Library · Your Spaces · App sessions · Menu** or an adaptive rail for the same app destinations. It does not impersonate host-browser Back/Forward, enumerate host tabs, or embed an arbitrary URL. All dimensions are based on the actual available window and text scale; the current rail rule is documented in [DESIGN_SYSTEM](DESIGN_SYSTEM.md).

Menu groups are Page actions, Wingman tools, Your library, and Protection/settings. The menu is a sheet on compact layouts and an adaptive dialog on expanded layouts. It dismisses before invoking its action. Every menu callback captures and rechecks the originating tab before invocation. Page information also revalidates the captured origin and resource eligibility when its content rebuilds; stale titles are replaced with an unavailable state. The reference's optional anchored desktop menu and native wide tab strip are not claimed as implemented.

## Tabs, reading positions and privacy

The app caps discovery tabs at 12. The switcher offers explicit Normal/Private groups and grid/list presentation. Entering the private group hides normal titles until the user explicitly selects Normal. Private cards do not display page titles or thumbnails. Selection and closure are distinct targets; close-all confirmation describes the captured group.

Per-tab scroll offsets are memory-only and bounded. Feature pushes and theme rebuilds preserve them. They survive the temporary replacement of the owner tree by Hand It Over because the owner `DiscoverySession` remains above that gate; an ordinary cold restart starts discovery tabs fresh. A saved Finish Mode task can restore currently eligible reviewed IDs through its own explicit resume flow.

Private tools use a separate ephemeral `SignatureServices` store. Normal saved library IDs, Spaces, analyses, Home preferences and receipt history are not loaded into that service. Closing the last private tab discards the transient service and positions; private tabs have no normal undo snapshot. Consumer normal records remain local and durable. Student/unknown editions retain their existing memory-only feature boundary; no managed-school enrollment or remote policy control was added.

## Asynchronous actions and durable results

An asynchronous operation distinguishes its captured data target from permission to change the current UI. A durable task detach/finish may need to reconcile its original task ownership after the user leaves. It must not switch a newer active tab, close an unrelated tab, pop a newer route, or reopen the old resource as a side effect of that delayed completion.

Workspace resume uses the captured service, origin tab and current originating route. Finish closure requires the still-current intent and matching normal/private scope. Normal task undo revalidates every restored resource; private closure does not create undo data. Tests in `workspace_navigation_races_test.dart` exercise delayed associate/resume/finish and sheet dismissal separately from basic navigation.

Privacy clearing captures the selected categories and existing matching-scope tabs before starting. A pending operation remains owned by the session, so reopening Privacy observes it instead of launching another deletion. Normal and private pending operations are not interchangeable. Outcomes list completed and failed categories; a 15-second wait result can remain pending while underlying work continues. A timeout is not a cancellation or a successful deletion.

Scoped clearing has a separate route/lifecycle reconciliation callback. Captured data can finish clearing without dismissing a newer route. If a preserved feature's own origin closes, its content must become unavailable; preserving a route does not authorize retaining a destroyed private view. Shell teardown must not turn a completed deletion into a disposed-controller error. All five clear/navigation regressions pass in the final431-test suite.

Normal reviewed bookmarks and reading state are independently clearable, including IDs whose approval expired; deletion does not require rendering their titles. Earlier history remains quarantined until an explicit clear and its visible count is updated on confirmed completion. Native legacy website data is one capability-specific category. Installed articles, completed download files, other categories, OS backups and already exported copies are not silently deleted.

Ordinary preference forms call `BrowserState.saveSettingsPatch`: theme, suggestions, article size and onboarding are merged against the latest state inside the serialized write queue and published only after storage succeeds. The explicit whole-snapshot method remains for deliberate snapshot operations and tests. Home layout has a separately bounded `ui` document; malformed data is preserved until confirmed reset, and failed reset never reports saved defaults. Private Home layout never accesses the owner document.

## Feature navigation and external boundaries

- Library/Reader opens only currently eligible reviewed IDs. Import/export transfers those IDs with an explicit preview; it does not restore legacy HTTP bookmarks or enable a network importer.
- Official Routes shows exact reviewed identity evidence and current unavailable live status. Its related Wingman guides are visibly separate local resources and rechecked before opening. Request review starts with a blank domain field; a local draft never unlocks the source.
- Before You Commit analyzes bounded user-chosen text or eligible article content locally. Route coverage, editing, backgrounding and source ineligibility invalidate pending results/exports. Normal saving and private transient use remain distinct.
- Trust Receipt, compatibility reports, review requests and findings export only after explicit preview/copy. They retain no automatic outbound submission endpoint. An already invoked clipboard operation cannot be revoked by canceling its future, so interrupted completion does not claim that the OS clipboard remained unchanged.
- Hand It Over replaces the entire owner navigator with a static reviewed shared view on supported native platforms. Returning to owner requires the existing fresh-code verifier and durable gate cleanup. App Back, deep routes, file pickers and external intents do not reveal the owner. Web and private unsupported states remain explicit; this is not a device-wide kiosk or live session sharing.

## Verification scope

`test/protected_shell_test.dart` passed ten updated host cases for new entrypoints, typed denial, private tab boundaries, storage failure and policy invalidation. `test/state/browser_state_test.dart` passed 14 cases including delayed independent preference patches and failed-save publication. The new `test/ui/preferences_reset_welcome_test.dart` adds reset cancellation/pending/failure/private/closed-session and first-run failed-save retry coverage; all five cases pass in the final431-test suite.

The native protected/signature integration files preserve zero-loopback-request, zero-WebView, saved-ID and private-persistence assertions while using Welcome, focused search, grouped Menu and tab cards. The final Android Student/iOS consumer protected journeys and both consumer signature journeys passed on the dedicated emulator/simulator; all four separate-process Handoff phases also passed. Consult the final [QA report](QA_REPORT.md), [O/C evidence](OFFICIAL_COMMIT_QA.md), and platform evidence for actual build/run results. The UI does not acquire live capability from a gallery, a screenshot, or a passing layout test.
