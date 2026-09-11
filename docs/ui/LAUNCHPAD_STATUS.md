# Launchpad implementation status

The local Launchpad milestone is implemented on `launchpad/implementation`, starting from clean `main` at `e93fc0e754bbc86ef205c26bf15d45480fa53689` in `/Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser`. This is the existing checkout. No repository/ancestor AGENTS.md was present. The earlier remote observation `a9b3765` predates the already merged consumer/UI work and was not checked out. The app is version **0.7.0+7**.

## Fresh baseline

Before edits, Flutter 3.44.4/Dart 3.12.2 and Xcode 26.3 (17C529) passed:

| Check | Result | Tool duration / command wall time |
|---|---|---|
| `flutter analyze --no-pub` | Clean | 2.0 / 3.21 s |
| `flutter test --no-pub` | 431 passed, 2 optional skips | 25 / 29.31 s |
| Android debug APK | Built | 10.6 / 13.15 s |
| iOS Simulator debug app | Built | 21.3 / 31.47 s |
| Web release with local resources | Built | 25.5 / 26.04 s |

Logs and exact commands: `../../work/launchpad-baseline-*.log` and `../../work/launchpad-baseline-results.json`, relative to the repository root. These builds do not imply new physical-device or native runtime acceptance.

## Audit and decisions

The active Home is `lib/presentation/home/home_screen.dart`; the old `screens/home_screen.dart`, omnibox and toolbar paths in the brief refer to earlier architecture. Current native dock and Web app navigation live in `components/browser_chrome.dart`. Home had four fixed tool tiles and up to six chosen signed resource IDs. The new Launchpad replaces that shortcut section and retains the current Shell/session ownership.

Separate versioned Launchpad records share the existing local signature-document store. Bookmarks, Spaces, catalog suggestions and optional chosen collections retain distinct ownership. No network request, image service, backend, analytics or live-renderer package was added for this local feature.

The authoritative policy and native bridge support only exact signed offline plaintext. Each requested website candidate received individual destination/scope research. ESPN NBA → Teams and Walmart Office Supplies → Notebooks & Pads rendered in external Chrome; they cannot navigate in Wingman. The current build has no live website renderer or positive eligibility for the full dynamic-content/dependency graph. A familiar company name, shortcut record or category cannot authorize a website. [Site compatibility](LAUNCHPAD_SITE_COMPATIBILITY.md) records exact addresses, native denial evidence and blockers.

## Execution ledger

| Work | Delivered |
|---|---|
| Data and migration | Strict bounded schema; atomic queued saves; once-only migration from the old Home choices; preserved edits, removals and unrelated documents; scoped undo and explicit Launchpad-only clearing. |
| Real Home | Editable local grid, empty-state actions, multi-select/skippable first use, compact/comfortable density, show/hide and expansion; one omnibox and existing browser dock. |
| Add and edit | Searchable starter catalog, bookmarks, tools and custom address entry; safe local normalization, title/icon/folder preview, current policy checks and explicit inactive consent. |
| Organization | Immediate-save non-drag reordering; visible Edit, context/long-press controls and stable Organize panel for consecutive keyboard moves; single-level folders with rename/move and both explicit deletion choices. |
| App integration | Current committed article and Library pins, explicit resource new app tab, selected-Space resource save, distinct bookmark/shortcut ownership, existing Finish Mode navigation and Home settings. |
| Catalog and content | 34 suggestions: 8 local tools, 18 original reviewed offline articles, 8 researched inactive websites. Optional finite Sports/Shopping/Learning sources with visibility, ordering, removal and chosen-source explanations. |
| Policy and privacy | Rechecked authoritative decisions, private/student memory storage and handoff isolation; local icons and text with no preview, favicon, typed-address or recommendation upload. Native denial remains intact. |
| Verification | Clean analyzer; 486 tests passed, 2 optional benchmark skips; 192 independently mounted layout states; actual release Web walkthrough, persistence, private Home and repeated keyboard moves; 12 planned native integration checks passed on dedicated Android/iOS targets. |
| Documentation | Specification, this status, candidate compatibility, full QA, UI QA, 12 widget captures and actual Web screenshots. |

Final commands, build results, native fixture timings, source inventory, screenshots and exact preview instructions are maintained in [Launchpad QA](LAUNCHPAD_QA.md). The working Web companion is [localhost:8791](http://127.0.0.1:8791/); actual test data used a separate temporary local origin.

## Remaining limits

Live ESPN, Walmart and the other candidate websites remain unavailable on every Wingman platform. Authentication, dynamic recommendations, advertisements, resource redirects and permitted live-content enforcement need a separate renderer/policy milestone. No fake feed, URL allowlist or landing-page substitute was introduced. The signed offline catalog remains development-reviewed and expires on March 10, 2027; production signing/distribution is not delivered.

This acceptance uses a dedicated Android emulator, iOS simulator, host widgets and an actual Web companion. Physical-phone testing, a complete human TalkBack/VoiceOver session, release signing, store review and whole-device network capture remain unperformed. Full-list Flutter Web row moves can lose DOM focus; the verified Organize panel keeps controls fixed for repeated keyboard moves.

## Delivery boundary

Source and tests are committed locally as **`563f7a1a8dde0be55604f54bec109ec0bde5d5f4`** on `launchpad/implementation`, followed by the documentation/evidence commit containing this report. Local `main` and `origin/main` remain at the starting commit. No push, remote merge, publication, purchase or production deployment was performed, following this milestone's explicit instruction. Use `git log --oneline main..HEAD` for the local source and evidence commits; the final delivery records the ending branch HEAD and clean working-tree check.
