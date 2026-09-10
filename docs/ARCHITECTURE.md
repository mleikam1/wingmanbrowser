# Architecture

Wingman shares Flutter product UI and browser metadata across targets. Mobile pages use platform engines. The web companion opens destinations in its host browser. There is no Chromium fork, browsing proxy, web-content backend or arbitrary iframe workaround.

| Area | Responsibility |
| --- | --- |
| `lib/main.dart` | Initialization, preferences, themes and shell |
| `lib/presentation/` | Home modules, omnibox, navigation controls, tabs, library, onboarding and settings |
| `lib/domain/` | Immutable models, direct search providers and URL parsing |
| `lib/state/browser_state.dart` | Metadata state and serialized persistence operations |
| `lib/data/` | Repository interface, transactional SQLite and native/web entry points |
| `lib/browser/browser_engine.dart` | Bounded controllers, navigation callbacks, permission mediation and app-only native channel |
| `android/app/src/main/` | Profiles, file selection, downloads, clearing, browser role and incoming intents |
| `ios/Runner/` | WK data-store configuration, download/navigation proxy and incoming URLs |
| `lib/config/`, `lib/monetization/` | Central configuration, placement policy, consent and owned Home ad slot |
| `lib/privacy/` | Enum-only analytics boundary and diagnostic categorization |
| `lib/guard/` | Domain normalization, local policy, signed manifests, indexed filter repository, SafeSearch |
| `lib/guard_ui/` | Local Guard controller, daily counts, time-limited grants, settings and owned blocked pages |
| `lib/guard_pin/` | Salted PIN derivation, native secure storage, persistent retry limits and session lock |
| `assets/guard/`, `assets/guard_tracking/` | Signed authored category starter pack and separately licensed tracker subset |

## Guard decisions and updates

`GuardRuntime` opens a local indexed SQLite filter database and verifies the active release. `NavigationPolicyService` separates known threat rules, user rules, temporary Focus and content categories. Explicit support/education classifications exempt category rules; they cannot bypass known threats or user blocks. Unknown domains remain usable and are not classified by words in their URLs. An unavailable pack has an explicit degraded status; normal browsing and native security can continue.

`GuardController` stores configuration separately from numeric daily statistics. Private decisions bypass the bounded host cache and saved counters. Allow Once is memory-only, bound to an exact host and tab, expires after five minutes, and is cleared when that navigation completes. Family lock removes those grants and propagates policy to live engines. Local suggestions consult only bookmarks/history and return before accessing either source in private mode.

Android and iOS read the same indexed active generation natively for callback paths, including redirects and response decisions. Normal subresources never invoke Dart classification; tracker blocking stays native. Android uses a synchronous third-party hostname check; iOS compiles a small WKContentRuleList. Updating policy rechecks cached tabs. The engine retains a blocked-navigation status even when no WebView was created, so a typed blocked address renders a Wingman-owned explanation rather than a spinner or website.

Signed manifests bind release metadata, pack bytes and the derived rule index. Activation and previous-generation state change transactionally. Verification failures retain the last valid version; downloads cannot import an unsigned arbitrary list. The default update source is absent. A future global, cacheable artifact transport can implement `FilterPackUpdateSource`, which accepts no browsing URL. No Google Cloud or Firebase resource is needed for local browsing. [Full privacy data flow](PRIVACY_ARCHITECTURE.md).

## State and memory

Flutter notifiers provide state without another state-management dependency. Widgets observe metadata and engine status. Serialized database writes keep navigation responsive and prevent a late save from resurrecting cleared history or a closed tab. Errors use generic messages; unreadable persistent data is not overwritten with memory defaults.

Persistent tabs store identity, URL, title, ordering and desktop preference. Live WebViews remain in `BrowserEnginePool`: at most **three** engines for **fifty** metadata records. Resident tabs retain engine state. Least-recently-used eviction destroys a controller; returning reloads its URL without restoring its old navigation stack, scroll state or forms. Private eviction clears the entire private site session. Pending creation/close generations prevent a closed engine from reappearing.

Home unmounts its ad widget when a browsing page is displayed. Engine notifications update toolbar title, address, progress and navigation availability. Navigation parsing is shared: safe HTTP/HTTPS goes to the site, searches go to the chosen HTTPS provider, and unsupported schemes or URL credentials are rejected. The app confirms allowlisted external links. Certificate failures are canceled without a bypass.

## Persistence and private sessions

SQLite schema v2 has distinct history, bookmark, normal-tab, settings and reading-list tables. Its migration preserves v1 records. Writes are transactional and parameterized. History stores the latest visit per URL, bounded by 90 days and 5,000 entries. Private records are filtered both by state and before repository SQL parameters; private history returns before database access. Bookmarking or saving a private page to the reading list is disabled.

Library mutations use a serialized durable queue and update visible state only after storage succeeds. Reading lists contain at most 500 title/address/read-state records, with no saved page body. Bookmark import accepts an explicitly selected Netscape HTML file, bounds actual bytes/markup/candidates, decodes inertly in a native worker, previews counts/text, then rechecks duplicates and the 5,000-bookmark cap before a confirmed commit. Web decoding remains bounded on the UI thread. Export is a separately disclosed OS share or browser download.

Native storage uses `wingman.db`. iOS stores it in backup-excluded Library/Application Support/Wingman. Web runs local SQLite WASM in a worker over origin-specific IndexedDB; storage can be evicted and is not a backup. SQLite secure deletion does not guarantee erasure of previous OS backups or snapshots. There is no server, account or synchronization component.

iOS private WKWebViews receive a nonpersistent store before construction. A minimal vendored patch exposes the official plugin's configuration identity to the app's native adapter; the adapter verifies isolation before navigation. Android private tabs require multiple-profile and complete-data-deletion support, receive separate profiles, and clear cookies/data on close before destruction. Android can temporarily write isolated profile data to disk; startup deletes abandoned profile directories. Unsupported providers fail closed. See [native notes](NATIVE_BROWSER.md).

## Security and permissions

The `wingman/browser` channel is application-only and is not exposed as a website-native capability bridge. Console output is discarded and native failures exclude URLs, credentials and filenames. Privileged operations have narrow native handlers. Android disables file URL access and mixed content and enables supported Safe Browsing functionality. The app does not alter page advertisements or install a content-upload bridge.

Camera/microphone requests require an active HTTPS page, explicit app approval and OS permission behavior. Async workflows recheck page/session identity before granting. HTTP authentication refuses cross-origin challenges. Files use platform pickers; downloads require explicit confirmation and may outlive private sessions. Android download requests do not copy authentication cookies into the OS database. Each website capability needs device acceptance independent of shared UI tests.

## Monetization and diagnostics

Ad interfaces take finite owned placements and route identities, not URLs. Consent wraps UMP behind a replaceable gateway; errors deny requests and changed choices require fresh evaluation. Only optional mobile debug test banners are available. SDK initialization happens after explicit opt-in and consent. The Android publisher-ID toggle runs after SDK initialization because that version requires it, but before any ad request. A startup invocation was removed after runtime testing exposed the SDK requirement.

`SponsorshipCatalog` has empty default inventory. The analytics implementation is a no-op with no arbitrary property bag or identifier. Optional in-memory counters have no timestamps or export. Diagnostic codes discard raw strings rather than attempting partial secret redaction. These application guarantees do not redefine third-party SDK behavior. See [privacy](PRIVACY.md) and [monetization](MONETIZATION.md).

## Future changes and tests

Tab groups and pinned/recently closed tabs can extend metadata without making every record a live engine. Sync requires a separate optional consent/encryption/key-management design. AI page exports must be user-triggered and scoped; no background collector exists. Commercial Home modules need explicit paid labeling and must not derive targeting from browser histories.

Tests cover parsing, real SQLite behavior, retention, private exclusion, state lifecycle, responsive UI, ad policy, consent changes and diagnostics. Native builds, mobile integration tests and actual browser navigation are separate evidence. Consult the validation report; a unit-test pass does not establish store or browser acceptance.
