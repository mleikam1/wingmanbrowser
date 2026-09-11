# Permanent-protection migration

Status: first foundation milestone implemented; final verification is recorded in RELEASE_READINESS.md. Audit date: September 10, 2026. Starting commit: `060839b8b656f89ea1a1998b2843f3322f7e33b3`, clean `main`, already merged Phase 3A. Work proceeds locally on `permanent-protection/foundation`; no push, production deployment, purchase, enrollment, or publication is authorized by this milestone.

## Audited environment and integrations

Repository: `/Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser`; remote `https://github.com/mleikam1/wingmanbrowser.git`. Installed tooling: Flutter 3.44.4, Dart 3.12.2, Xcode 26.3 and Android Studio JBR 21. Baseline architecture used Flutter UI, SQLite metadata, platform WebViews, optional native Guard, external search/Reader/download/launch paths and GMA/UMP. No Browser Firebase app, policy endpoint, school tenant service, cloud sync or AI integration is configured. This repository inventory does not claim an account-wide cloud audit; no cloud resources were created.

## Baseline preserved

Fresh baseline: 289 host tests passed plus one optional benchmark skipped; analyzer clean on retry (2.6 s). Android debug build passed (14.9 s), iOS simulator debug (21.4 s), web (27.8 s). The first analyzer invocation hit Flutter's generated ephemeral package deletion race during concurrent commands; the independent no-pub retry passed. Compilation is not device testing. The earlier committed source remains in Git and historical docs.

## Audit findings and decisions

| Earlier path | Finding | First milestone |
| --- | --- | --- |
| Guard defaults/settings | Off by default, empty category set, overrides configurable | Mandatory compiled baseline; core controls removed |
| Allow once/always, custom allow, PIN/Focus | Could bypass category decisions | No grants or role-based exceptions; legacy inputs cannot enable content |
| Unknown/evaluation failure | Could resolve to allow/errorAllow | Only exact signed bundled approval permits rendering |
| Support allowlist | Broad host exemptions could cover unrelated content | Exact article bodies only; source hosts grant no capability |
| Search | Four external providers and parameter-based SafeSearch | Local approved-record search only |
| Restored state/library/import | Raw saved titles/addresses could appear before review | SQLite v3 quarantine before UI; counts only; imported HTML UI removed |
| Native browsing | Main-frame callbacks did not cover all subresources/redirects/workers | No content WebView allocation; raw plugin bridges removed |
| Secondary paths | Reader, downloads, external browser, share, file picker and selection menus | Disabled or removed; controlled local text editing only |
| Ads | GMA/UMP SDK and initialization providers remained packaged | SDK/dependencies/registrants removed in every edition |
| School mode | No real managed configuration or tenant implementation | Ad-free student packaging; managed pilot explicitly deferred |

## Startup order and preservation

Flutter binding initializes without a restored-content widget. Signed policy and its separate durable trust checkpoint load first. Native legacy site data is cleared without constructing a content view; Android cancels Wingman-owned unfinished DownloadManager requests. Completed external files are preserved. Browser metadata then migrates before the production shell is created. Native cleanup failure produces a fixed restricted startup message; no exception text, old title, or raw address is shown.

Version 3 copies retired tab metadata into an archive table and retains legacy history, bookmark, and reading-list rows in their original tables while quarantining them from presentation. BrowserState returns no legacy title/URL library or history values to production presentation. Counts identify preserved items without previewing them. Old settings and imports cannot authorize content. New reviewed saves use separate ID-only preferences; invalid/stale IDs cannot render because every listing and open rechecks current eligibility.

Private tabs start fresh. Student/unknown editions do not restore consumer reviewed saves. The session-reset action preserves quarantine and additional restrictions. This is not secure deletion of OS backups, completed downloads, other applications, or all historical device files.

## Scope of replacement

The policy change makes the old browser UI unsafe by construction. Its override, live navigation, Reader, remote-library import/export, and external-launch screens were retired, together with tests that asserted their old successful behavior. Corresponding prior versions remain at the starting commit. Inert bookmark parsing, storage migration, normalizers, cryptographic verification and privacy tests remain where relevant. The unused patched WebView vendor dependency is removed rather than kept as an active raw bridge.

The new shell preserves useful navigation concepts for reviewed content: local discovery, bounded back/forward trails, up to 12 session tabs, bookmarks, reading status, themes, and text size. It does not imply restoration of live browsing or school management.
