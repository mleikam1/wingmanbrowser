# Wingman Browser — Complete UI/UX Implementation Prompt

## 01 / Assignment and source of truth

You are the principal product designer and Flutter UI engineer implementing Wingman's complete consumer interface in the existing `mleikam1/wingmanbrowser` repository. Implement the design, navigation, reusable components, real state bindings, and tests—not a strategy-only response or a collection of disconnected mockups.

Product: **Wingman Browser**. Mission: **“We've got your back, not your data.”** Positioning: a useful everyday browser with permanent protection, not a school-first application, antivirus dashboard, or engagement-maximizing feed. Monetization is deferred: no ads, sponsorship cards, subscriptions, affiliate integrations, revenue UI, or reserved advertising gaps in this milestone. Preserve unrelated commercial code without activating it.

Use the attached `wingman-logo-reference.png` as the identity source. Use `WINGMAN_UI_VISUAL_REFERENCE.html` as a visual composition reference, not production application logic or proof that illustrated capabilities exist. The HTML examples use synthetic design fixtures; do not copy their illustrative data into production as real user data. This written brief governs behavior when a static example cannot show every state.

Review the local checkout before coding. The source review behind this brief inspected `main` at commit `060839b8b656f89ea1a1998b2843f3322f7e33b3`. The user's local work may be newer; compare it and preserve it rather than checking out this old snapshot or overwriting completed features. Read repository instructions and actual capability reports. Record starting branch, commit, dirty files, tests, build results, and device capabilities. Make reversible, routine decisions without repeated clarification; stop only for genuinely missing authorization or an essential unresolved decision.

## 02 / Actual repository starting point

These files were inspected; use them as integration points, not assumptions about a different architecture:

- `lib/main.dart`: MaterialApp, app initialization, ListenableBuilder and onboarding/root selection.
- `lib/presentation/theme.dart`: current green/gold Material 3 theme; replace brand colors with the system below.
- `lib/presentation/widgets/brand.dart`: provisional geometric mark and wordmark; replace with supplied branding.
- `lib/presentation/browser_shell.dart`: engine lifecycle, app/page navigation, prompts, menus, Guard overlays and toolbar wiring. Decompose carefully without losing navigation-identity, lifecycle and stale-request protections.
- `lib/presentation/widgets/omnibox.dart`, `browser_toolbar.dart`, `browser_page_error.dart`, `clear_browsing_data_dialog.dart`.
- `lib/presentation/screens/home_screen.dart`, `onboarding_screen.dart`, `library_screen.dart`, `reader_screen.dart`, `settings_screen.dart`, `tab_switcher.dart`.
- `lib/guard_ui/guard_settings_screen.dart`, `guard_surfaces.dart`, `guard_controller.dart`.
- `lib/state/browser_state.dart`, `lib/browser/`, `lib/domain/`, `lib/data/`: inspect before changing their contracts.
- `pubspec.yaml`: existing local Roboto fonts, SQLite, WebView packages, and a local `webview_flutter_wkwebview` override. Preserve native privacy patches and local font behavior.
- `docs/PHASE_3_STATUS.md`, `docs/PLATFORM_CAPABILITY_MATRIX.md`, `docs/PRIVACY_ARCHITECTURE.md`: evidence and capability boundaries.

At the reviewed snapshot, the documented delivery was Phase 3A; later functionality was deferred. Home still contains sponsorship explanations, the toolbar has six controls and a long popup menu, and Guard includes opt-in controls and content overrides. Do not mistake prior feature prompts for implemented features. Audit all seven signature features individually before deciding whether to restyle, complete, or add them.

Retain the working Listenable/BrowserState approach unless a narrow, justified refactor is necessary. Do not introduce Riverpod, a new router, a new browser engine, or a major SDK migration merely to restyle the application.

## 03 / Non-negotiable product and safety constraints

Core protection is permanent. Maintain the user's established restrictions on adult/explicit entertainment, gambling, alcohol promotion/commerce, recreational-drug promotion/commerce, tobacco/vaping promotion, and known security threats, while preserving reviewed educational, health and recovery resources under the actual taxonomy. Optional restrictions may become stricter, never weaker than this baseline.

Remove the earlier opt-in model and core-category overrides from the underlying behavior as well as visible controls. No Allow Once, Always Allow, adult mode, private exception, PIN bypass, timed core unlock, paid unlock, or external-browser escape from a blocked destination. Sync, restoration and existing settings must not revive the old behavior. Keep optional distraction scheduling distinct from mandatory protection.

The UI must consume typed policy/capability state; it must not decide safety by changing a badge or hiding a switch. If mandatory enforcement is not implemented, treat that as a prerequisite and release blocker. A finished design gallery is not evidence of enforcement. Do not label the app protected while using experimental starter data as comprehensive coverage.

Keep approved-content eligibility and strict-search rules. Unknown, unsupported or unreviewed content must receive the correct policy state rather than a cosmetic “safe” label. Every route, shortcut, preview and signature-feature destination uses the same policy path. Official identity verification is not content approval, and HTTPS is not proof of trustworthiness.

Browsing history, selected interests, task notes and personal findings stay local by default. No automatic accounts, analytics, replay, attribution, cloud page analysis or uploaded browsing activity. No remote fonts or preview services merely for visual polish. Do not fetch favicons/thumbnails for unapproved destinations. Make no false anonymity, zero-data, clinical, compliance or foolproof-protection claims.

## 04 / Creative direction

Design language: **quiet surfaces, precise typography, electric-blue emphasis**.

The supplied winged W has energy, movement and depth. Carry its blue/navy/cyan identity into the UI; do not copy its metallic shading onto every control. Most of the screen should be calm and neutral. Use royal blue for actions, navy for structure, cyan for restrained highlights. Keep gradients in small decorative areas or brand artwork, never behind long text or security-origin information.

Avoid neon gaming styling, ornamental dashboard charts, glowing borders everywhere, giant daily hero banners, excessive pills, nested cards, neumorphism, mascot characters, purple replacement branding, and indiscriminate glassmorphism. Do not use blur above live WebViews as a requirement. Opaque surfaces are the reliable default.

The browser should feel fast before it feels animated. Web content is the protagonist while browsing. Home is a useful starting point, not a marketing landing page.

## 05 / Logo and assets

Preserve the original file unchanged. The supplied asset is a square RGB raster with a near-white background, not a transparent vector. Never rename it SVG, stretch it, trace a crude replacement, or remove all white pixels: the white highlights and negative space are part of the artwork.

Make a visually inspected, non-destructive crop derivative to remove surplus outer whitespace while preserving all swooshes. Until a properly approved transparent/vector asset exists, use the mark on a deliberate small white medallion that looks intentional in both themes. Do not show the entire white square as a giant tile on dark surfaces. The wordmark remains live text next to the mark, not a raster caption.

Suggested display bounds after crop: 28–32 logical pixels for compact identity, 40–48 for Home header, 72–96 for onboarding; use larger artwork only in the first-run experience. Keep clear space of at least one-quarter the displayed mark width. Use `BoxFit.contain` and explicit asset resolution variants. Cache decoded assets.

Create an asset wrapper with semantics and size variants. Mark purely decorative duplicates as excluded from semantics. Do not recolor the whole logo purple for private mode; identify privacy with a separate icon and text.

Update launcher/splash/favicon assets through verified platform rules. Do not invent an alternative monochrome logo or call this image trademark-cleared. Preserve the original in the repository under `assets/brand/source/`; register actual derivatives in `pubspec.yaml`.

## 06 / Design tokens

These are proposed UI tokens inspired by the logo, not a claim of exact source-pixel colors. Implement them centrally, with semantic light/dark roles and component themes rather than scattered hex values.

| Role | Light | Dark |
|---|---|---|
| App canvas | `#F5F8FF` | `#08111F` |
| Primary surface | `#FFFFFF` | `#101D31` |
| Raised/selected surface | `#EDF3FF` | `#162640` |
| Main text | `#10213D` | `#EDF4FF` |
| Secondary text | `#54647B` | `#A9B9D0` |
| Primary action fill | `#0062E8` | `#79AAFF` |
| On-primary label | `#FFFFFF` | `#071B4D` |
| Brand navy | `#071B4D` | `#071B4D` |
| Decorative cyan | `#20CFF2` | `#20CFF2` |
| Decorative divider | `#DFE7F3` | `#2A3B55` |
| Informational tint | `#EDF3FF` | `#162640` |

Use separately tested success, caution and error colors with text/icons, not color alone. Caution is amber, danger red; do not turn every category block into a red emergency. Decorative dividers are not sufficient as the sole control boundary or keyboard-focus indicator. Cyan is not body text on white. Check real composed contrast, including opacity, hover, disabled, focused and pressed states.

Typography: retain the repository's bundled Roboto for this milestone. Use its real available weights deliberately; no runtime Google Fonts download. Brand text may use weight 700 with slightly tightened tracking. Body 16/24, supporting 14/20, metadata 12/16 sparingly, section heading 20/28, page heading 28/34, first-run display 36/42. Use 500 or 700 for emphasis, not ultra-light text. Let large text reflow; do not globally disable TextScaler or shrink substantive labels with FittedBox.

Spacing: 4, 8, 12, 16, 20, 24, 32, 40, 48. Default phone gutter 20, narrow phone 16, tablet 32, wide 40. Radii: 12 small controls, 16 buttons/inputs, 20 cards, 28 sheets. Use pills only for small state/filter chips. Standard CTA minimum height 52; icon hit area at least 48×48 logical pixels. Rows expand with content; 64 is a starting minimum, not a clipping height.

Motion: 100–140 ms press feedback, 180–220 ms sheet/menu changes, 220–280 ms meaningful route transitions. No idle shimmer or looping glow. Respect reduced motion; never animate sensitive previous-page content underneath a block or handoff. Use haptics sparingly and only when supported.

## 07 / Information architecture and navigation

Use one persistent browser shell on native mobile. Browser history and Wingman's app navigation are separate stacks.

On Home and live browsing, the bottom toolbar has exactly five stable controls: **Back · Forward · Home · Tabs · Menu**. Move reload/stop into the page omnibox so it does not require a sixth toolbar control. Back/forward availability reflects real page state. Home returns the active tab to its start surface without creating an extra tab; New Tab explicitly creates one. Do not move Home or Tabs between positions as the page changes.

For live pages, default to a compact bottom omnibox immediately above this toolbar. Keep safe-area insets, keyboard behavior and the visible origin correct. A validated top-address preference can be supported without rebuilding engines. Home has one prominent inline search/URL field; do not display a second editable omnibox below it. Both open the same focused address-entry route.

Keep browser chrome stable initially; do not introduce auto-hiding that causes viewport jumps or conceals the domain. A 2-pixel loading indicator can sit at the dock/content boundary. No decorative notch, shield, floating assistant bubble or extra toolbar obstructs websites.

Feature pages use ordinary app navigation: back header, meaningful title, optional contextual action. Close returns to the exact originating browser tab and scroll position. The browser toolbar is not duplicated beneath every form. Never recreate the WebView just because a sheet, theme, or feature page changes.

Menu groups: Page actions; Wingman tools; Your library; Protection and settings. On phones use an accessible sheet with familiar icons and labels. On wide screens use a compact anchored menu. No full-screen ungrouped list of thirty actions.

Wide native/tablet layouts may use a top address bar, tab strip, and an optional owned-page rail: Home, Spaces, Library, Tools, Protection, Settings. Do not cover external pages with a permanently expanded dashboard sidebar.

Flutter Web remains an owned Home/search/library/tools companion. Do not imitate control of host-browser tabs, show fake browser back/forward state, embed arbitrary sites, or claim mobile filtering after external top-level navigation. Give web its own capability-aware rail and a brief factual scope notice.

## 08 / Adaptive layout and components

Use available window width, not device names. Starting breakpoints: compact below 600; medium 600–1023; expanded 1024 and above logical pixels. Test live resizing, landscape, split screen, foldable insets, keyboard and pointer input. When text grows, simplify columns before compressing content.

Cap owned content at 1120–1200 wide, settings/forms at 720, reading at approximately 65–75 characters. Medium/wide layouts may use master/detail for Library, Spaces and Settings. Phone detail pages become push routes; contextual evidence becomes a sheet, and wide layouts can use a 380–440 side panel when sufficient room remains.

Build shared components: brand lockup, adaptive scaffold, page header, omnibox, suggestion row, browser dock, tab card, local resource row, Space card, quick link, primary/secondary/destructive buttons, settings row, status chip, protection explanation, evidence row, empty state, error state, adaptive sheet, menu group, confirmation, inline validation, snackbar and optional busy placeholder.

Use at most one primary CTA per surface. Make every apparent interactive control functional or explicitly unavailable with a discoverable reason. No TODO callbacks, fake success messages, or production demo data. Prefer a usable list to forcing everything into cards.

Create a development-only component/screen gallery with deterministic synthetic fixtures. This is where all otherwise difficult states can be reviewed, not a hidden way to bypass production protection. Keep fixture injection and security test controls out of release builds.

## 09 / Complete screen and state inventory

Create a screen registry mapping each ID below to the actual route/widget, parent entry, data source, exit behavior, tests and platform capability. IDs are design identifiers, not required public URLs. Cover every additional route/dialog discovered in the audit; no green/gold or unfinished legacy surface may remain reachable.

### Foundation and browsing

**F01 — Bootstrap / launch.** Native splash with centered mark and theme-matched background, no arbitrary delay. Initialize protection before restoring pages. If initialization is slow, show honest progress wording; failed/stale policy receives a restricted recovery screen, not infinite loading or a false protected state. Preserve existing data on failure.

**F02 — Welcome.** At most two short first-run steps: brand/mission with Start Browsing, then optional Home/interest personalization that can be skipped. State permanent content boundaries plainly without shaming. No account, school enrollment, monetization explanation or permission carousel. Reopening never resets safety policy. Default-browser setup is contextual later and only supported when entitled.

**F03 — Home / New Tab.** Compact brand header and small truthful protection entry; headline “Where would you like to go?” with the mission beneath it. Prominent omnibox. Below: 4–6 user-selected eligible shortcuts; one Official Routes action; an optional current Finish Mode card; up to three selected Space cards. Provide Customize Home. Keep the search field and useful next action visible on a typical short phone. No giant wall of privacy promises, repeated slogan blocks, sponsorship card, feed or invented personal greeting.

**F04 — Focused address/search.** Native keyboard, clear cancel/back action, typed URL/search parsing, local suggestions grouped by type, and an explicit Official Routes mode. No background keystroke uploads. Do not prepopulate sensitive clipboard data automatically. Show provider/approved-search scope. Empty, no-match, unsupported address, blocked and no-approved-result states are distinct. Submission uses policy; do not invent a permissive search provider for the redesign.

**F05 — Eligible search results.** Search query/edit control, plain result titles, reviewed domain/scope information where real, readable snippets and no unrestricted image previews. Unknown/unavailable results show a factual explanation. If only external search currently works, implement the actual supported experience rather than impersonating a private search engine. Custom search templates cannot bypass the policy.

**F06 — Active browser.** Full usable page viewport; compact origin-first omnibox and stable five-control dock. Display the effective domain accurately; tapping exposes full URL and site info. Do not accept website-supplied colors/icons as native security indicators. Support loading/stop/reload, fullscreen media, native permission prompts and existing browser state. On refocus, scroll the address to reveal meaningful parts without hiding suspicious suffixes.

**F07 — Page menu / site information.** Page tools: save bookmark, reading list, find, reader, desktop site, copy/share where eligible. Contextual Wingman tools: Before You Commit, Finish Mode, Hand It Over, Trust Receipt, Report a Problem. Site-info sheet separates connection, permissions and Wingman eligibility. Unsupported controls have precise reasons; do not call a site safe merely because TLS succeeds.

**F08 — Tabs.** Clear Normal / Private segmentation with counts, native-feeling grid and optional accessible list view. Each card has title/domain, selected state and an independent close hit target. New Tab is prominent. Task association is a label/filter, not a third privacy mode. Use local metadata placeholders until safe screenshots exist; never store or expose private/handoff thumbnails. No fake website screenshots. Close-all confirms its scope; ordinary close can offer undo, private closure must not resurrect destroyed sessions. Respect actual tab/engine limits.

**F09 — Private start and unavailable state.** Same blue brand with a distinct privacy label/icon and an appropriately differentiated surface; dark appearance alone is not private mode. Explain what history/storage behavior actually exists and that mandatory protection stays on. Never expose normal suggestions, task goals or owner-library previews here. When native isolation is unsupported, present a clear availability explanation, not fake private browsing.

### Library and reading

**L01 — Library hub.** Bookmarks, Reading List, History and Downloads only when real platform tracking supports them. Search locally, show empty states and easy category navigation. Do not open on sensitive history by default. Tablet uses list/detail; phone pushes detail. Private-context access must not silently expose normal personal data.

**L02 — Bookmarks.** Fast search, title/domain rows, add/edit/delete, and folders only if implemented with persistent models. Selection mode and overflow house import/export. Saved status remains correct after errors. Avoid re-fetching every favicon. An imported URL is not automatically eligible for navigation.

**L03 — Import / export.** Retain existing safe file limits and inert parsing. Show counts, duplicates/rejections, bounded preview, merge confirmation, cancel, progress and real outcome. No execution or automatic page visits. Export explains that addresses leave the app via the chosen file/share path. Do not lose background/route-change protections in the existing library code.

**L04 — Reading list.** Unread / All / Read filters, add-address flow, read state, remove and open reader when supported. State explicitly when saved entries contain only title/address rather than offline articles. No fictional cached content or reading percentages.

**L05 — History.** Search and date groups, local retention explanation, selection/delete and clear-data entry. Private entries are absent. Avoid sensitive page titles in overview cards, screen captures and receipts. Reflect actual persistence errors.

**L06 — Downloads.** Use actual download sources for progress, completed, failed, canceled, denied and unavailable. Distinguish removing a list record from deleting a file. Confirm consequential actions and respect platform file handling and content policy. Do not render or externally launch an unknown file as a UI convenience.

**L07 — Reader.** Quiet text-first layout, source attribution, responsive measure, text-size controls, copy/select where supported and return to original context. No WebView marketing chrome. Keep extracted text local/transient according to current privacy implementation. Android unsupported Reader must remain honest; do not enable it through an unreviewed JavaScript bridge to match iOS screenshots.

### Your Spaces and Finish Mode

**S01 — Spaces hub.** Title “Your Spaces,” one-sentence local-first explanation, create action, selected-space cards, reorder controls with non-drag alternatives and a meaningful empty state. No algorithmic interest inference or generic news feed.

**S02 — Create / customize Space.** Choose Home Projects, Learning, Sports or a custom eligible collection; name, local icon and optional template resources. Editable local choices, no age/profile quiz or silent interests upload. Review before destructive removal. Editing a template does not change mandatory restrictions.

**S03 — Home Projects detail.** Saved eligible resources, notes, materials/checklist and a tested unit/measurement utility. Use compact sections and Add actions. Do not generate unsafe construction advice or claim quantities have professional certification.

**S04 — Learning detail.** User-chosen topic, reviewed resources, reading list and local notes. Resource provenance is visible. No scraped paid courses or automatic third-party previews.

**S05 — Sports detail.** Explicit sport/team choices, reviewed links and saved items without betting promotion. Live scores/schedules appear only through a real licensed/approved integration; otherwise useful official resources—not invented match data.

**T01 — Finish Mode task list / create.** Optional goal, small checklist, choose associated tabs, Start. Goals stay local. Do not imply a task workspace isolates cookies. Empty and paused states should feel calm, not like a failed productivity streak.

**T02 — Active task.** Goal, progress based on actual checked items, associated tabs, notes, pause/resume and Finish. A compact resumable Home card replaces a permanent floating widget over pages. No mandatory timer, inferred completion, surveillance or punitive notifications.

**T03 — Finish / save result.** Summarize only real saved items; explicitly choose save/archive and which task tabs to close. Preserve unrelated tabs and offer safe undo where possible. No confetti required, no fabricated “time saved,” and no restored private data.

### Official Routes and Before You Commit

**O01 — Official Routes search.** “Find the official destination.” Local reviewed catalog, category/region filters and clear scope. Empty/no-match/expired-data states must be useful and honest. Do not show an endorsement badge for unreviewed entries.

**O02 — Route detail.** Organization/task, human-readable canonical domain, region, source evidence, review date and current eligibility. Main action “Open official site” only when permitted. Wording distinguishes reviewed identity from guaranteed safety. Region ambiguity receives a choice, not an inferred location. Missing coverage offers request review, not a guessed route.

**O03 — Request review.** Minimal field(s), user-reviewed destination and clear disclosure. Local export when no endpoint exists; “Request saved locally” is not “Submitted.” Never temporarily unlock the destination.

**C01 — Before You Commit setup.** Entry from page menu or explicit selection, labeled locally processed where true. Preview bounded text, explain supported scope, exclude credentials/payment fields and hidden content. Choose analysis without automatically sending it to a cloud provider.

**C02 — Checking / unavailable.** Cancelable real progress; do not animate pretend stages. If extraction is unsupported or the page changes, state that and allow a safe recheck. No detached result from a different tab or earlier URL.

**C03 — Findings.** Sections for trial, recurring price/frequency, cancellation, returns and unknown/conflicting information. Each finding has a supporting excerpt and source; expand evidence in place or an adaptive panel. “The page states…” not “Safe to buy.” Clearly separate direct evidence from inference and unconfirmed terms. Missing evidence is not positive assurance. No arbitrary risk percentage or blanket green verdict.

**C04 — Save / share finding.** Optional local save, previewable sanitized export, delete. Private findings remain transient. No purchase, cancellation, form submission or autonomous account action.

### Hand It Over, protection and support

**H01 — Handoff setup.** Explain exactly what will be shared and hidden. User chooses an eligible public page/collection, confirms the scope, and sees whether real isolation is supported. No copying owner's login/session. Unsupported capability gets an honest alternative or unavailable explanation.

**H02 — Handoff session.** Minimal independent shell labeled “Shared view”; no owner tabs, library, suggestions, tasks or credentials. Navigation restricted to approved scope plus mandatory policy. No file pickers, external intents or native permissions that expose the owner. Returning to owner requires verified authentication, including after process death. Do not call this a device-wide kiosk.

**H03 — End / authenticate / cleanup.** Use OS authentication where appropriate; distinguish cancellation, failure and cleanup-in-progress. Do not reveal owner content underneath a transparent prompt. Do not claim immediate forensic erasure. A static read-only fallback, when safely implemented, must be labeled as such and strip active content.

**P01 — Protection overview.** A factual summary with drill-down, not a gamified score. Separate core policy state, filter-data status/coverage, tracking controls and optional restrictions. “Core rules active” and “Limited coverage” can both be true. Avoid exposing sensitive category names in Home summaries.

**P02 — Always-on protections.** Read-only list and plain explanations; use lock/info symbols, not disabled toggles implying future unlock. Policy and update/coverage details accessible. No success badge hardcoded from a setting.

**P03 — Additional boundaries.** Optional social media, entertainment/gaming/shopping/news or supported site restrictions; available schedules apply only to additional restrictions. Show inheritance/managed state honestly. Removing an optional rule cannot make prohibited/unreviewed content eligible.

**P04 — Blocked / unreviewed destination.** Neutral branded state with reason, Go Back, Home, Explore approved resources, Request Review and optional support. Distinguish category denial, unreviewed content, unsupported enforcement and unavailable policy. No threatening illustration, explicit image, unnecessary revealing title, bypass or external open. A review request never unlocks the current page.

**P05 — Security / connection error.** Distinct danger treatment for TLS/malware/phishing, versus ordinary offline/DNS/server failures. Retry only when appropriate; do not label every HTTP status as a threat. No Proceed Anyway for invalid TLS. Error UI must not hide continued prohibited loading behind a pretty overlay.

**P06 — Help Now.** Discreet optional route to offline-friendly break/reset actions, user-selected positive resources and verified support information. No diagnosis, clinical promise, ads or emotional gamification. A trusted-person action requires explicit user confirmation and cannot automatically disclose block events, categories or URLs. If not already functional, implement a minimal safe local flow; do not fake a crisis service.

### Trust, compatibility and settings

**R01 — Trust Receipt summary.** Readable list of what Wingman observed about this feature/session: local history state, requested search provider, local analysis, authorized external request, policy freshness. Separate observed, configured and unobservable behavior. No fabricated zero-data claim or reconstruction of browsing history.

**R02 — Receipt detail / export.** Expand an item for destination category, purpose, optionality and known limitations; bound local retention and keep private/handoff receipts ephemeral. Share only a user-previewed sanitized receipt. No automatic telemetry upload.

**X01 — Something isn't working.** Choose issue type, optional comment, minimal proposed diagnostics. Do not collect screenshots/page bodies, cookies, query strings or raw network logs by default. Explain that even a domain can be sensitive.

**X02 — Review / submit / export.** Preview fields, explicit consent and correct statuses: saved locally, exported, submitted, failed. No fake report number, support SLA or auto-fix promise. Without a backend, export remains genuinely useful.

**X03 — Compatibility status.** Where an actual reviewed profile exists, show its version, narrowly stated purpose, activation and revocation status. Corrections never disable mandatory protection, TLS or privacy safeguards. Do not expose an “unblock everything” troubleshooting control. No remote executable code disguised as a theme/config update.

**G01 — Settings index.** Short grouped rows: Appearance; Home and Spaces; Search; Protection; Privacy and Data; Website Permissions; Accessibility; Default Browser when supported; Help and About. Replace the current wall of explanations with concise summaries and dedicated details. No forced account avatar, monetization pitch or school-administration shortcut.

**G02 — Appearance / Home.** Light/dark/system live preview, eligible address-bar position preference, Home module visibility/order and accessibility-related display options. Do not treat dark mode as private mode. Text size follows OS, with optional reader/site controls clearly distinguished.

**G03 — Search preferences.** Only verified compatible providers and their strict scope; simple disclosure of submitted-query recipients. No unrestricted custom endpoint or switch to disable core filtering. Local suggestions preference does not enable history suggestions in private/handoff sessions.

**G04 — Privacy and clear data.** Clearly show local categories, retention and actual SDK/service behavior. Destructive selection → explanation → confirm → real clearing state → result. Separate bookmarks, history, website storage, download files and session cleanup. Do not claim data cleared while asynchronous native deletion is pending or failed. Preserve the existing selection-generation protection.

**G05 — Permissions.** Per-site origin, current grant/deny state and reset action based on real platform support. Contextual OS requests remain native and are never silently granted. A webpage's dialog cannot impersonate a Wingman security confirmation; expose its origin and visually distinguish untrusted page messages.

**G06 — Help / About / legal / capabilities.** Actual version/build, privacy explanation, licenses, limitations, support/export and known platform capability status. Do not hardcode obsolete version text or fake audits. No mandatory sign-in or planned cloud-sync page that looks active. Retain school-managed labels only if a real managed configuration exists; no school dashboard is in scope.

## 10 / State and interaction contract

For every screen/component define applicable initial, loading, empty, populated, offline, storage-error, invalid-input, blocked, denied-permission, unsupported, pending, success and destructive-confirmation states. Mark not-applicable explicitly; do not invent network spinners for immediate local data.

Keep forms keyboard-safe with inline errors and preserved input. Buttons show actual busy state and prevent duplicate operations. Return focus appropriately after sheets and maintain reading order. Announce meaningful asynchronous results to assistive technology without reading sensitive content unnecessarily.

Show errors where they occur; do not use only a disappearing snackbar for a consequential failure. Use snackbars for reversible, low-risk feedback. Redact URLs/titles where they would expose sensitive browsing.

Keep sensitive routes opaque during transitions and background previews. Do not disable Android capture protection or private preview shielding for production screenshots. Use an approved debug-only gallery of synthetic data for design captures; clearly label evidence scope and preserve release protections.

## 11 / Implementation boundaries and completeness

Split the large shell by extracting presentational parts and small coordinators while retaining ownership of keyed WebViews and existing request-generation/lifecycle checks. Preserve native patches, private profile cleanup, restored-tab policy evaluation, download handling and import/export safeguards.

Suggested additive organization under the existing presentation layer: `design_system/`, `components/`, `navigation/` and feature directories for spaces, official routes, commitment review, tasks, handoff, receipts and compatibility. Reuse names already present. Use ThemeExtensions for semantic tokens when useful.

Use real local repositories/models for features that can operate locally. Do not postpone every missing feature behind a Coming Soon page. Where an external provider, reviewed data, entitlement or secure native capability is truly missing, implement and test the complete UI states in the development gallery, expose honest capability behavior, and report that integration as blocked—not finished.

Keep branded claims inactive if mandatory enforcement has not passed its prerequisite tests. Implement safety prerequisites in a separate tested milestone rather than hiding unfinished behavior beneath the new look. Do not launch billed infrastructure, add cloud AI or production content feeds simply to populate a mockup.

## 12 / Accessibility, performance and QA

Treat accessibility as release work. Target WCAG 2.2 AA principles for owned UI: at least 4.5:1 normal text, 3:1 large text, adequate non-text contrast and visible focus, plus this product's 48×48 logical-pixel touch targets. Test text scaling through 200% and the largest supported accessibility sizes; no ellipsis on essential instructions or action labels. Support TalkBack/VoiceOver, keyboard-only use, focus restoration, reduced motion and non-drag alternatives.

Use representative logical widths 320, 360, 390, 430, 600, 768, 1024 and 1440, including short heights, portrait/landscape, safe-area insets and keyboard display. Breakpoints are layout starting points, not device guarantees.

Build reusable widget/golden tests and meaningful integration journeys. Cover Home, address entry, actual browser navigation, tab switches, all three Space templates, Finish Mode, official-route evidence, findings with missing/conflicting information, handoff capability states, protection/blocked states, Trust Receipt, report export, Settings and clearing data in both themes.

Capture and visually inspect screenshots; do not consider golden-file generation itself visual review. Check wrapping, clipping, contrast, keyboard obstruction, selected/disabled states, reachable controls, unexpected white surfaces and large blank gaps. Preserve semantic tests and behavior assertions when updating old goldens.

Run existing tests as regressions. Add policy-routing tests for all new feature links; verify no privacy data enters normal history, screenshots, receipts or restored workspaces accidentally. No real prohibited sites, malware, passwords or live ads in test automation.

Measure startup, layout/raster frame timings, tab switching and memory on identified devices/build modes. The nominal frame budget is about 16.7 ms at 60 Hz and 8.3 ms at 120 Hz; profile real p95/p99 behavior rather than claiming guarantees from emulator screenshots. Do not keep extra WebViews alive for attractive tab previews. Lazy-build long lists and keep heavy extraction off the UI thread.

Run `flutter analyze`, automated tests, Android build, iOS simulator build and Flutter web build where tooling permits. A source review, successful compile, emulator run and physical-device acceptance are different evidence. Report exactly which occurred. Do not unnecessarily upgrade the entire dependency graph.

## 13 / Milestones, deliverables and completion

Milestone 1: audit, screen registry, protection prerequisites, tokens, assets and component gallery.
Milestone 2: actual Home, omnibox, browser chrome, tabs, onboarding and errors in both themes.
Milestone 3: Library, Reader, Settings, Protection and privacy flows.
Milestone 4: all seven signature-feature interfaces with real local functionality and explicit capability gates.
Milestone 5: adaptive layouts, accessibility, regression testing, performance and visual refinement.

Do not stop at Home. All reachable pages and overlays need coherent styling; every inventory item needs an implementation/status entry. Iterate on the actual app after inspection, not only on the reference HTML.

Produce:
- `docs/ui/UI_AUDIT.md` with inspected starting evidence and old/new mapping.
- `docs/ui/DESIGN_SYSTEM.md` with semantic tokens, components, assets and contrast results.
- `docs/ui/SCREEN_REGISTRY.md` including every route, sheet and error state.
- `docs/ui/NAVIGATION.md` with browser/app/session boundaries and back behavior.
- `docs/ui/IMPLEMENTATION_STATUS.md` separating functioning features from blocked capabilities.
- `docs/ui/QA_REPORT.md` and actual light/dark screenshots or contact sheets with device/build context.
- Updated launch documentation for CLI, Android emulator/device, iOS Simulator and web; VS Code remains optional. Native edits may require rebuilding rather than hot reload.

No destructive Git actions, broad unrelated rewrites, production changes, pushes, merges, store submissions, new billed services or device enrollment without approval. Preserve work you did not create. Commit tested milestones where appropriate and report the actual final Git state.

Completion report: changed files, before/after screen mapping, each feature's behavior/capability, permanent-protection prerequisite status, test/build results, screenshot locations, measured performance, privacy implications, remaining external gates and exact preview commands. No perfection or million-user engagement guarantee; provide evidence of a coherent, useful interface.

Start with the actual repository audit, then implement the design system and first tested screen milestone. Do not stop after restating this prompt.

---

## Reference sources for the implementer

Repository snapshot examined: https://github.com/mleikam1/wingmanbrowser/tree/060839b8b656f89ea1a1998b2843f3322f7e33b3

Current official documentation to verify during implementation:
- https://docs.flutter.dev/ui/adaptive-responsive
- https://docs.flutter.dev/ui/accessibility
- https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
- https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html

This brief defines proposed design decisions. It does not claim that the supplied reference UI is a working browser, that source-code review substitutes for runtime testing, or that all future capabilities exist in the reviewed repository.
