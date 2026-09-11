> Historical Phase 1–3A document. Optional Guard, live browsing, external search, Reader and ad behavior described here is superseded by [permanent protection 0.4](RELEASE_READINESS.md). It is not a current capability or release claim.

# Wingman Browser — Phase 2 handoff report

**Status: Phase 2 implementation acceptance passed.** Android debug, iOS simulator and Web release builds passed, with native and full-app regression evidence below. Production signing, maintained filter coverage and physical-device performance remain release work; this is not a store-readiness claim.

**We've got your back, not your data.** Wingman Guard adds local, user-chosen browsing boundaries alongside native browser security. Ordinary destination classification does not send a navigation URL to Wingman infrastructure.

## Repository and baseline

| Field | Recorded state |
| --- | --- |
| Starting branch | `main`, tracking `origin/main` |
| Starting commit | `2bd9b098ebba09a72a79030b8bb6c9ebcd8435c1` |
| Starting working tree | Clean; remote fetched, README and architecture reviewed before implementation |
| Working branch | `phase2/wingman-guard` |
| Tested implementation commit | `375a649befadc73595306728816637f5b101b045`; policy/native acceptance ran at `fa266b0`, followed by the verified content-label wording and test synchronization/benchmark tooling changes. |
| Ending branch | `main` is the authorized integration destination. |
| Ending commit | Final code snapshot: `375a649befadc73595306728816637f5b101b045`. The accompanying delivery report records the subsequent documentation/merge commit and verified remote HEAD. |
| Remote integration | The user's repository-merge instruction authorizes integration into `https://github.com/mleikam1/wingmanbrowser`; the delivered summary records the actual push result. No production service or store deployment is included. |

Before Phase 2 source changes, all **97 host tests**, full `flutter analyze`, Android debug, iOS simulator debug, and web release builds passed. No critical baseline failure was found. The environment remains Flutter **3.44.4**, Dart **3.12.2**, Xcode **26.3**, JDK **21**, and Android **36.1** tooling; ordinary Android support starts at API 24. See [baseline evidence](phase2/BASELINE.md), [run commands](../README.md), and [Phase 1 validation](VALIDATION.md).

## Features and files added or changed

| Area | Concrete implementation and principal files |
| --- | --- |
| Guard policy | `lib/guard/`: typed requests/decisions/configuration, domain normalization, local policy precedence, SafeSearch, indexed filter repository and optional artifact transport |
| Guard UI | `lib/guard_ui/`: controller, Standard/Guard/Focus controls, custom rules, local totals, PIN entry, block/warning pages and explicit report composer |
| Home/onboarding | `lib/presentation/screens/` and `browser_shell.dart`: collapsed Guard status, optional setup with no preselected lifestyle categories, integrated navigation and private-state behavior |
| Omnibox | `lib/domain/local_suggestions.dart`, `widgets/omnibox.dart`: optional local bookmark/history suggestions, no private suggestions, keyboard-Go handling that preserves the edited destination |
| Family foundation | `lib/guard_pin/`: secure-store adapter, salted verifier, persistent retry budget, serialized authorization and lifecycle cancellation |
| Signed category data | `assets/guard/`, `tool/guard/`: 49 authored CC0 starter records, signed metadata/public verification key, external development-key authoring tool |
| Tracking data | `assets/guard_tracking/`: seven EasyPrivacy-derived third-party domain rules, pinned provenance, attribution and full CC BY-SA 3.0 license |
| Android | `NativeGuardPolicy.kt`, `NativeGuardSession.kt`, `GuardedWebViewClient.kt`, `MainActivity.kt`: indexed native checks and resource blocking while preserving browser callbacks/security |
| iOS | `NativeGuardPolicy.swift`, `AppDelegate.swift`, project configuration: indexed WK policy, compiled tracker rules and delegate integration |
| Persistence | Browser settings schema/repository fields for Guard configuration and aggregate totals; separate `guard.db` for public filter data |
| Verification | Guard/domain/controller/surface/PIN tests; native Guard, PIN, full-app UI and performance integration tests |
| Documentation | [Filter contract](GUARD_FILTER_PACKS.md), [privacy architecture](PRIVACY_ARCHITECTURE.md), [providers](PHASE2_PROVIDERS.md), [PIN](GUARD_PIN.md), [performance](GUARD_PERFORMANCE.md), [cloud design](CLOUD_CONTROL_PLANE.md), [future protection](FUTURE_PROTECTION.md) |

Existing browser navigation, history/bookmarks, private storage, downloads/media, bounded engines and restrained Home monetization remain part of the application. Phase 2 adds no accounts, browsing proxy, page-analysis service, analytics backend or Firebase SDK.

## Guard architecture and behavior

`GuardController` owns local preferences, aggregate counters and short-lived grants; `GuardRuntime` composes the repository, normalizer, policy and SafeSearch. The browser engine consults Dart policy before application-initiated navigation, and native navigation layers check destinations independently. Decisions distinguish allow, category/custom block, malware, phishing, known harmful downloads, additional checks and unavailable-list allowance.

Standard mode leaves native security enabled and selects no lifestyle categories. Guard enables the user's chosen Adult content, Alcohol, Recreational drugs, Gambling and Tobacco/vaping categories. Focus adds temporary social-media, shopping, gaming, news or custom-site boundaries, with preset/end-of-day/custom durations. It does not change the user's lifestyle selections or add streaks/gamification.

Mandatory signed threat matches and invalid TLS cannot be overridden. Custom allow/block rules use the most-specific matching host; at an equal host, the block wins. A child allow keeps the ancestor block and its sibling coverage. Permitted Allow Once grants are bounded to a tab, exact canonical host, five-minute expiry and one completed navigation; lock state cancels grants. More-specific classifications and support/recovery exceptions have explicit policy treatment; host specificity/race regressions and the final native navigation-order retests passed. No page-word matching or AI page upload is used. A domain-level starter cannot classify every page or distinguish every support/journalism context.

Private tabs use the same Guard choices. Their automatic history, tab metadata, domain-result cache activity and saved block counts are excluded. Explicitly creating an always-allow/custom rule saves that local preference even if initiated privately; this is distinct from automatic browsing history. Reports default to no address, show the proposed text and export only through an explicit copy/share action. Full-address inclusion is a separate user choice. No reporting inbox is connected.

The optional mobile Family PIN uses PBKDF2-HMAC-SHA256 with 600,000 iterations and a random 32-byte salt, storing only a verifier/retry record in Android protected storage or non-synchronizing, device-bound iOS Keychain. Read failures remain locked. The fifth attempt starts a persisted delay; repeated failures increase it to at most an hour. Settings sessions lock on lifecycle/session exit and restart. This protects Wingman settings, not other browsers/apps or a device owner who can modify the app/data. There is no recovery account. [PIN details](GUARD_PIN.md)

## Filter-pack architecture

The shared SQLite index uses `(generation, host, kind, category)` keys and suffix queries. Routine navigation does not scan the entire pack or load every domain into Dart. A normal-session cache holds at most 512 hosts for ten minutes; private requests bypass it.

An Ed25519 envelope signs exact payload bytes, including version, monotonic sequence, UTC creation time, minimum app version, constrained filename, license, byte/rule limits, archive SHA-256 and canonical indexed-row SHA-256. Import is transactional. Startup/rollback verify archived bytes and indexed rows; a valid archive alone does not bless a corrupted index. The active and previous successful releases remain available; explicit rollback does not lower the update high-water mark.

Limits are 64 KiB per manifest, 64 MiB and 500,000 rules per artifact. A pack older than 30 days is identified as stale while remaining useful offline. Missing/corrupt storage reports unavailable coverage and withholds its native path, allowing the ordinary browser to start; category coverage is not claimed when no verified pack exists.

`HttpsFilterPackUpdateSource` supports a future fixed HTTPS global manifest and same-directory signed artifacts, bounded transfer sizes/time, no redirects and no web credentials/referrer. No instance or endpoint is configured at startup. A persisted 24-hour cadence supports restrained automatic checking when configured; the current build does not pretend to run a live background update service. No private signing key ships. The included verification key is a **development** key; production signing/distribution is outstanding. [Exact contract and provenance](GUARD_FILTER_PACKS.md)

## Platform implementation and provider boundaries

| Platform/system | Current implementation and limits |
| --- | --- |
| Android Guard | Dart preflight plus native main-frame override/interception and final-commit checks; provisional content stays hidden until accepted. Indexed native queries avoid per-resource Dart calls. Covered fixture paths include links, redirects, JavaScript, POST/307 and `target=_blank`. Callback coverage varies: a later redirect destination may be contacted before its rendering is blocked on some WebView providers. |
| Android security | System WebView Safe Browsing remains enabled where supported. Hits return to safety with optional reporting disabled. WebView usage metrics opt-out does not disable every engine crash report. Invalid TLS remains cancelled. |
| iOS Guard | WK navigation-action/response policy and commit checks use the local index; original plugin callbacks are forwarded. Compiled WKContentRuleLists handle tracker resources. Automated iOS page activations may use DOM actions because Flutter pointer delivery into UIKit is unreliable; manual OS gestures are a separate check. |
| iOS security | WebKit fraudulent-site warnings remain enabled. Apple's provider/region behavior is not equated with an Android threat callback or Google's Web Risk API. |
| Downloads | Known harmful-domain matches block; executable file types/MIME types produce a separate caution, not a fabricated malware verdict. Files are not scanned. Explicit saved files remain after private sessions close. |
| Web companion | Home/search/settings/local SQLite concepts work, with explicit limitation copy. It cannot filter arbitrary pages after opening another browser, control that browser's private mode or provide the mobile PIN boundary. No extension is implemented. |

[Native evidence and limitations](phase2/NATIVE_GUARD_VALIDATION.md), [web runtime observations](phase2/WEB_RUNTIME.md), [provider research with official sources](PHASE2_PROVIDERS.md)

Tracking Protection uses seven third-party analytics/session-replay domain rules: FullStory, Heap, Hotjar's two domains, Mixpanel, Mouseflow and ScorecardResearch. Android blocks resources natively and batches local counts; iOS uses compiled rules and honestly shows its count as unavailable. A temporary site exception affects tracking rules only. Wingman does not blanket-block ad servers, inject replacement ads, or process its owned Google ad view through this adapter.

SafeSearch recognizes specific GET search routes for DuckDuckGo, Google `.com`, Bing and Brave, with provider-specific strict parameters and safe hosts where applicable. Supported HTTP routes upgrade to HTTPS. Query text, unrelated duplicate parameters and fragments are preserved. Unsupported regional domains, POST bodies, provider changes and every search UI are not guaranteed; SafeSearch is not perfect content filtering.

## Cloud, Firebase, external providers and licensing

**Google Cloud resources created: none. Firebase resources created: none. Google Web Risk deployment/data/client credentials: none.** No production deployment or billing activation occurred. The minimum future control plane is common signed static artifacts, with optional GCS/CDN distribution and KMS signing, separate dev/staging/production authority, budgets and reviewed logging. No infrastructure or operational controls are claimed merely because the design describes them. [Cloud design](CLOUD_CONTROL_PLANE.md)

Actual external systems are the visited websites and their services; selected search providers; Android/WebKit platform security; explicitly chosen OS share/external apps; and the existing Google UMP/Mobile Ads integration. Google ads remain a **debug-only, explicit Home opt-in demo**, off by default and denied in release builds. Production ad units/revenue are not fabricated. Earlier actual iOS approved-test-banner evidence remains in [Phase 1 validation](VALIDATION.md); no new Phase 2 ad-rendering run is claimed.

The 49 category/support/test-threat records are an authored **CC0-1.0** starter. The seven tracker rules are an attributed **CC BY-SA 3.0** adaptation of a pinned EasyPrivacy source. ShareAlike/provenance apply to that data adaptation. Disconnect/DDG noncommercial lists were evaluated but not copied. No Google threat data is redistributed. Future Web Risk Update API use requires a suitable credential model, caching/freshness/attribution and licensing review; Lookup would send full URLs and is not selected. [Licensing/provider review](PHASE2_PROVIDERS.md)

Outstanding external setup includes production signing-key custody and a real signed distribution endpoint; maintained/licensed coverage; final operator identity/privacy policy and store disclosures; production AdMob consent/inventory/business configuration if ads are activated; Android upload signing; Apple developer enrollment, app identity, provisioning and any required default-browser/distribution entitlement. Future device-wide protection has separate eligibility/entitlement reviews. No fake VPN, restricted entitlement request, MDM service or cloud sync was added. [Release checklist](RELEASE_CHECKLIST.md), [future device-wide/extensions](FUTURE_PROTECTION.md)

## Network and privacy audit

| Wingman-created flow | Why data leaves / destination |
| --- | --- |
| Allowed website/resource/download request | Normal browsing to the selected website and its service providers |
| Submitted search | Direct to DuckDuckGo/safe.duckduckgo.com, Google Search, Bing, or Brave/safe.search.brave.com; no keystroke upload |
| Home shortcuts | Explicit navigation to Wikipedia, YouTube or OpenAI |
| Copy/share/external action | Explicit export to clipboard or the selected OS application; report address inclusion is chosen separately |
| Debug Home ad opt-in | Google UMP/GMA services, subject to consent/readiness and technical SDK processing |
| Platform safety | Engine-managed threat services; provider behavior/retention applies |
| Web companion loading | Its serving origin and framework resources; Phase 1 conditional font-fallback caveat remains documented |
| Wingman filter/report/config backend | **No active endpoint.** Optional artifact transport has no configured startup source. |

**Full navigation URLs are not sent to Wingman infrastructure by this implementation.** Website/search recipients necessarily receive requests the user makes; explicit full-URL report sharing sends it to the selected recipient. This is not a claim that OS/SDK services collect no technical data or that every encrypted third-party SDK request was inspected.

The audit covered app-owned Dart/native request paths, errors/logging, analytics, SDK declarations, private counters/cache, PIN storage and rule verification. Findings fixed during review include post-await lock checks, persisted-save failure disclosure, background-error containment, exact-host/expiry grants, optional Safe Browsing reporting, signed-index integrity, safe degraded startup and web transport referrer suppression. Final host race/specificity and native stale-navigation acceptance passed. Product analytics remains a fixed-enum no-op; no Firebase/attribution/standalone crash SDK was added. The full Mermaid flow, retention/recipient inventory, evidence and exclusions are in [Privacy architecture](PRIVACY_ARCHITECTURE.md) and [privacy disclosures](PRIVACY.md).

## Verified tests and build status

Evidence logs are in the parent workspace's `work/`, outside the repository; these are development logs, not application telemetry. The 197-test suite ran after the final engine changes. The subsequent wording-only change passed all six surface tests, final whole-checkout analysis, all three main builds and visual inspection; no native behavior changed afterward.

| Check | Verified result | Final status / evidence |
| --- | --- | --- |
| Baseline suite/analyze/builds | 97 tests; analyze; Android/iOS/web all passed | Completed before source edits; `phase2-baseline-*.log` |
| Phase 2 full host suite | 197 passed, 1 optional benchmark skipped, 8 s | `phase2-host-handoff.log`; frozen engine and final host race/specificity cases |
| Focused Guard/core tests | 65 passed in recorded core run | Signed corruption/replay/rollback, normalization, precedence, cache, SafeSearch; final cases also included in the 197-test suite |
| Guard/controller race and specificity regression | 29 passed, 1 s | `phase2-guard-race-regression.log`; policy revisions, async lock changes and child/parent/equal-host rule behavior |
| PIN host suite | 10 passed | Salt/verifier, known-answer KDF, persisted retry limit, failures, concurrency/cancellation |
| Native PIN storage | Android and iOS passed | `phase2-pin-android.log`, `phase2-pin-ios.log`; isolated key, wrong PIN denied, locked service replacement and cleanup |
| Full-app Android Guard UI | All eight flags true, 50 s including teardown | `phase2-guard-ui-android-handoff-fixed.log`; keyboard Go, three categories, private exclusion, exceptions/network and settings reload on frozen production policy |
| Android native Guard fixture | Final pass, 11 s including teardown | `phase2-guard-races-android.log`; includes policy-change/preload and navigation-order regressions |
| iOS native Guard fixture | Final pass, 10 s including teardown | `phase2-guard-races-ios.log`; includes policy-change/preload and navigation-order regressions |
| Phase 1 native browser regression | Android final passed, 27 s; iOS passed, 33 s | `phase2-browser-regression-android-final.log`, `phase2-browser-regression-ios-final.log`; private isolation, cleanup, navigation/error handling and actual Android renderer recovery |
| Analysis | Final whole-checkout analysis passed, 3.6 s | `phase2-analyze-delivery.log`; includes final wording, test synchronization and benchmark tooling changes |
| Android build | Final main-entrypoint debug APK passed, 20.6 s; install succeeded and onboarding visibly rendered | `phase2-main-android-handoff-build-final.log`, `phase2-main-android-handoff-install.log`; debug signing only |
| iOS build | Final main-entrypoint simulator build passed, 41.9 s; installed, launched and manually exercised | `phase2-main-ios-copy-final.log`; distribution signing outside evidence |
| Web release/runtime | Final release and Wasm compile check passed, 50.1 s; final Home/reload observed | `phase2-web-copy-final.log`, [web runtime notes](phase2/WEB_RUNTIME.md) |
| Actual OS cold restart | Main iOS app terminated/relaunched; choices retained, private tab absent, saved private test rows zero | [Main-app acceptance](phase2/MAIN_APP_ACCEPTANCE.md), `phase2-ios-cold-restart.json`; production PIN was not set in this manual check |

The final UI rerun first exposed a test synchronization flaw: its off-screen progress bar was mistaken for idle settings. The fixture now waits for actual controls to be enabled and checks every category selection before continuing; the subsequent full run passed. No policy change was made to address that test failure.

The installed Android main app rendered onboarding and remained the top resumed activity. Its `am start -W` command reached the 15-second wait timeout before that confirmation; this is not a startup-performance pass. The [screenshot](screenshots/phase2-android-main.png) is included with the acceptance evidence.

Manual iOS acceptance covered onboarding, all three requested category blocks, normal Wikipedia browsing, private Guard, real cold restart, local aggregate/private-storage inspection, and disabling/re-enabling Alcohol around a listed public site. That site rendered its normal age gateway after the category was disabled; no personal information was entered. [Observed steps and screenshots](phase2/MAIN_APP_ACCEPTANCE.md)

The native fixture deliberately permits Dart policy for selected cases so native interception must enforce them. The full-app UI fixture uses real controllers/SQLite/native views with isolated stores, actual signed reserved `.test` records and a loopback HTTP server for allowed requests. It does not establish broad real-site category accuracy, successful external account login, physical-device behavior or a completed new store review.

## Performance measurements

| Measurement | Observed result / qualification |
| --- | --- |
| Host synthetic pack | 100,000 rules; 13.4 MB artifact; about 22.0 MB SQLite database |
| Host verified import / reopen | 3,019 / 554 ms |
| Host uncached lookup p50 / p95 | 199 / 327 µs over 1,000 samples |
| Host warm cache p50 / p95 | 9 / 14 µs; cache remained bounded at 512 hosts |
| Android native lookup p50 / p95, concurrent builds stopped | First 1,000: 0.509 / 4.981 ms; repeated 1,000: 0.122 / 0.308 ms with SQLite pages warm, no hostname cache; 1,971 MB API 36 emulator |
| Android cold Guard startup, bundled starter | 1,622 ms in the final passing full-app **debug** UI run; includes new DB/import/verification |
| Android memory points | Main-process PSS 331,477 KB idle / 334,803 KB with three views; excludes separate renderer processes |
| Stressed Android page/switch timing | Local pages 18.9 / 6.8 / 4.9 s; test-pump-inclusive switching p50 280 ms / p95 1,140 ms |
| Native PIN test operations | Android 10,810 ms / iOS 8,051 ms for several KDF/storage operations, not one unlock |

The memory/page/switch sample was under substantial swap/concurrent-build pressure; the later lookup-only sample stopped concurrent builds. These debug/emulated measurements do not prove smooth production performance. Low-memory physical Android devices, older physical iPhones, release cold startup, full renderer memory and large-update peak memory remain unverified. Query-plan/cap tests establish bounded indexed work; they are not a substitute for physical-device latency/animation testing. [Full measurement method and limits](GUARD_PERFORMANCE.md)

## Acceptance, risks and Phase 3

Completed implementation gates:

- [x] Host race/specificity regressions and complete suite: **197 passed, 1 optional benchmark skipped**; `phase2-host-handoff.log`.
- [x] Whole-checkout `flutter analyze`: **passed**; `phase2-analyze-handoff.log`.
- [x] Latest Android/iOS native Guard and affected Phase 1 regression retests: **passed**, as recorded in the validation table.
- [x] Final main Android and iOS build/install; Android full-app UI acceptance; iOS normal-site, category-off and private-mode manual acceptance.
- [x] Main iOS cold terminate/relaunch with saved Guard choices and private session absent. Secure PIN storage/relocking is covered by separate native tests; no additional manual OS-restart PIN claim.
- [x] Final Web release build and runtime reload confirmation.
- [x] Outgoing-file privacy/artifact scan: 414 tracked/untracked files; no detected credentials, browsing databases, app packages or publishing workflows. The known development signing key is outside the repository with mode 0600; only its metadata was inspected.
- [x] Final implementation committed as `375a649`; documentation and screenshot evidence accompany the authorized integration. Exact resulting remote merge commit is recorded in the delivery report.

Known limits remain: small category/tracker coverage; provider-dependent navigation callbacks; unsupported SafeSearch variants; no real update endpoint; untested production HTTPS distribution; unavailable iOS tracker counts; no file-content malware scan; ordinary local DBs not separately encrypted; Android private profiles can temporarily write isolated disk data; explicit downloads/exports/custom rules can persist; PIN is an app-level lock; no physical-device performance proof; and incomplete production signing/entitlement/SDK disclosure readiness.

Recommended Phase 3 priorities are maintained and legally reviewed category coverage with false-positive evaluation; release/physical-device startup, memory and compatibility work; a small signed static distribution service with protected production signing and reviewed update telemetry; operator/support/report handling with explicit privacy choices; broader native security/permission/download/redirect acceptance; and production store/monetization setup. Optional encrypted sync, device-wide controls and browser extensions should remain separately scoped projects with their own consent and operating-system eligibility review.

Reproduction commands are in [README](../README.md), [native validation](phase2/NATIVE_GUARD_VALIDATION.md), [PIN verification](GUARD_PIN.md) and [performance](GUARD_PERFORMANCE.md). Nothing in this report authorizes production cloud deployment or silently weakens Guard for a commercial relationship.
