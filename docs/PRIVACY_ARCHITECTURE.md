# Privacy architecture

## Bundled story images — 0.13.1+15

Home, Updates and eligible saved articles select actual story photographs from a
finite local catalog of four reviewed images. Each requires both the exact
article URL and its locally pinned source ID. Every other article remains
text-only; no topic or generic photo is substituted. These inputs are processed
on the device. The photo selector does not send the
article address, topic, source, save state or selection to a photographer, CDN,
image search, stock-photo API or classification service.

Native rendering uses `Image.asset`; no image download, remote-image cache,
cookie, referrer or background image-refresh service is added. A failed asset
decode renders a local unavailable placeholder rather than fetching a remote
substitute. The web companion obtains packaged images as ordinary same-origin
application assets; it does not contact the original image publishers. Original
download URLs in the rights records are provenance, not runtime endpoints.

The four new image files add 1,180,639 bytes before packaging. Existing
user-selected Home artwork remains separate and is not a story-image fallback.
No paid photo subscription, image API or dedicated image
hosting is configured. Normal application distribution and bandwidth remain
separate from this absence of an image-service bill.

Source-wide `images:false` and feed-image rejection remain enforced. An RSS
publisher cannot insert an arbitrary asset path or image URL into the local
catalog. On story surfaces, display still depends on current item eligibility
and owner context; a photo does not restore a hidden or withdrawn story. The
static Photo credits inventory describes packaged public assets, not photos the
owner viewed or saved. Private and handoff screens do not receive owner story
content. Credits identify the story image's date or its
archival date, without implying that an archive photograph depicts a new event.
Source and media rights are recorded in
[Story images](STORY_IMAGES.md) and [Content sources and rights](CONTENT_SOURCES_AND_RIGHTS.md).
This is a source-level data-flow description, not a packet capture or claim of
completed physical-device validation.

## Native publisher updates — 0.13

The normal consumer Home/Updates surface downloads the same 12 reviewed public
feeds on every device. Publishers receive the device IP, a generic Wingman reader
user agent, conditional cache validators and normal TLS/network metadata. The app
sends no cookies, referrer, browsing history, queries, selected topics, saves or
other account/device identifiers. Topic/source selection is entirely local and
never changes the upstream feed URL. Private, handoff and inactive owner contexts
cancel network work and suppress feed data. Turning Updates off persists locally.
There is no background feed refresh service, notification enrollment or image fetch.

Cache, saves, preferences and publisher refresh checkpoints use bounded local
feature documents. Clearing the disposable article cache does not reset publisher
Retry-After/backoff or erase saved links. Candidate refresh results may commit only
while their original owner context remains valid. Saving stores a publisher link
and permitted excerpt; it does not download full article HTML. Original articles
load only on the user's action in the existing consumer browser with its existing
privacy and mandatory protections. A configured snapshot service, when used by
an explicit build, receives the same common request instead of direct publisher
traffic. The web companion requires that service; it is not deployed.

The remaining sections retain earlier feature/milestone context; the live-feed
behavior above supersedes blanket claims that publisher URLs are never fetched.

> **Earlier milestone record (0.5–0.7).** Version 0.8 adds a separate protected native website pilot. This document's no-browsing-network, no-renderer, Android INTERNET and renderer-free cleanup assumptions do not describe that pilot. Use [Live browsing status](LIVE_BROWSING_STATUS.md), [Live browsing policy](LIVE_BROWSING_POLICY.md) and [Cloud cost plan](CLOUD_COST_PLAN.md) for current scope, platform differences and remaining validation. The historical observations below are preserved for their recorded builds; they are not v0.8 test results.

**We've got your back, not your data.** The 0.5 signature-feature milestone builds on the permanent-protection foundation. [The previous architecture](history/PRIVACY_ARCHITECTURE_PHASE3A.md) is historical and does not describe current runtime behavior. Final implementation/platform status is recorded in [Signature features](SIGNATURE_FEATURES_STATUS.md).

## Data boundaries

| Data | Current handling |
| --- | --- |
| Approved article bodies/metadata | Bundled, signed, loaded locally; source URLs never fetched |
| Queries, session tabs/back-forward trail | Memory only; reviewed IDs rather than arbitrary page metadata |
| Consumer bookmarks/reading state | Separate local reviewed-ID preferences, rechecked before display |
| Private sessions | No durable owner activity; separate memory-only feature state; other-session library hidden; fresh after restart |
| Student/unknown editions | Reviewed-session saves in memory; no account identity or consumer-save restoration |
| Consumer additional restrictions/theme/text size | Local preferences; restrictions never approve content |
| Student/unknown additional restrictions/theme/text size | Session memory only; no authenticated institutional configuration |
| Legacy tabs/bookmarks/history/reading list | SQLite v4 retains quarantine; counts only; no raw title/address/preview exposure |
| Policy checkpoint | Local sequence/time/revocation floor, no query or browsing events |
| Review requests | No service or upload; UI explains a minimal human-contact process |
| Ads/consent/analytics/crash services | No ad/consent SDK or configured telemetry pipeline |

No behavior is monetized or used to build inferred interests. There is no AI endpoint, VPN, proxy, cloud sync, remote content fetcher or account sign-in. The empty future commerce interface does not initiate work. Removing the SDK avoids initialization-time advertising traffic even when legacy debug flags are supplied.

Startup loads trust and verifies bundled policy, awaits native old-site-data cleanup, and migrates metadata before showing content. Android cancels only this application's unfinished DownloadManager requests. Completed downloads and external exports remain user-owned. A fixed failure screen does not disclose exception strings or legacy data.

Current additional controls are user-editable. Authenticated institutional restrictions, class provisioning and persistent managed-policy delivery are deferred. Session reset clears reviewed saves/current tabs/query state within the defined session, retaining additional restrictions and quarantine. It is not an erasure promise for OS backups, file-system snapshots, completed files or other applications. SQLite is not separately encrypted by Wingman. Native backup-exclusion settings reduce exposure but do not establish device-wide erasure.

## Database teardown and reopen

Browser and policy-checkpoint databases share one awaited close queue in `lib/data/database_close_coordinator.dart`. Their records and responsibilities remain separate. The queue serializes only close operations; it does not change schemas, content approval, retention, network behavior or encryption. Each caller receives its own completion/failure, and a failed close does not prevent the next queued close.

This addresses a source-supported Android lifecycle race in locked `sqflite_android` 2.4.4. Its `SqflitePlugin.onCloseDatabaseCall` removes a database from the native map before queuing its close; `closeDatabase` stops the shared worker pool when that map is empty. The pool uses `HandlerThread.quit`, which can drop a second queued final close. Concurrent owner and policy teardown can therefore leave a Dart path lock waiting for a native response during same-process reopen. No dependency or vendored plugin was modified. Two host tests exercise the actual browser/policy repository close call sites and failure recovery; they passed in the 431-test host run. An instrumented iOS same-process root reopen passed on the preceding source, returning both concurrent closes. The Android rerun passed with the serialized fix: the trace shows close #51 returning before close #52 starts, no pending database calls at teardown, and owner-root reopen to tools in 952ms. The fixture passed in 18s (`work/ui-native-signature-android-coordinator.log`, parent workspace), with the same 20-second bound. These are single debug integration observations, not cold-start or physical-device performance claims. The original failing Android run did not include per-close tracing, so the worker-pool mechanism is supported by dependency source and the corrected ordering/runtime result rather than a captured dropped callback. Test tracing records only fixed operation names and lifecycle phases, never SQL, paths, arguments or result data. A subsequent iOS run with the coordinator reached a distinct outer-startup failure despite both closes and all checkpoint calls returning (`work/ui-native-signature-ios-coordinator.log`). The transparent native-call trace then isolated repeated WebKit quarantine latency: the first actual purge took 434ms, while repeating it for a second Flutter root took 14,563ms, almost exhausting the unchanged 15-second prerequisite limit (`work/ui-native-signature-ios-quarantine-diagnostic.log`).

The iOS bridge now retains a private, process-only acknowledgement set exclusively by actual WebKit removal completion. Because this build has no website renderer or other website-store writer, another Flutter root in that same native process may reuse the completed startup purge. Every new native process still performs its first purge; pending/rejected requests cannot acknowledge success. There is no persistent receipt or setter. Explicit user-requested `clearData` always executes its own selected deletion and does not consult this acknowledgement. Restoring a renderer or store-writing SDK would require revisiting this invariant.

Final iOS native boundary and signature tests passed (`work/ui-native-guard-ios-quarantine.log`, 2s; `work/ui-native-signature-ios-quarantine-fixed.log`, 13s). They check fresh false/count 0 → actual completed/count 1 → reused/count 1, explicit clearing, zero content views and actual owner-root reopen. The final trace measured the first actual purge at 397ms, acknowledgement reuse at 0ms, and root reopen to tools at 462ms. The timeout was not raised. These remain single simulator debug observations, not physical-device or cold-start budgets; earlier failing and diagnostic runs are retained.

## Network inventory and evidence

The production catalog has no app-created browsing/search/classification/advertising requests. The verified Android release merged manifest excludes INTERNET; a release APK/runtime is not available because the local AOT helper stalled. Debug/profile builds retain tooling networking. iOS has no content transport in the new adapter. Native integration loopback counters verify that attempted browsing/direct native calls make no request to the test server, not that every OS daemon is silent.

Web preview requests its same-origin Flutter application/font/catalog/SQLite assets. No remote font CDN is required by the documented build command. The host browser can still use its own services. Emulator/simulator framework traffic, Flutter tooling and host browser traffic must not be represented as Wingman collection or as evidence of universal silence. Final artifact and observed runtime findings are in MONETIZATION_POLICY.md and RELEASE_READINESS.md.

No full-packet production-device audit or third-party legal certification has been completed. Before a school pilot, review OS/keyboard/backup behavior, retention, shared-session cleanup, legal obligations and operator contracts using SCHOOL_DEPLOYMENT.md. Do not enroll real students or collect identifiers to test this milestone.

## Signature features: local state and explicit disclosure

Normal consumer feature documents use the existing local SQLite database and fixed `workspace`, `privacy`, `ui`, `launchpad`, and reserved `compatibility` namespaces. There is no separate backend or per-feature account. Each document is bounded to 512 KiB. Private and Student/unknown services wrap storage with a separate memory implementation, so a mistaken save request still cannot read or write the owner's backing store.

| Feature data | Boundary and retention |
|---|---|
| Official Routes | Common bundled identity/evidence catalog, searched locally. Identity review does not grant live navigation or imply the organization endorses Wingman |
| Launchpad | Explicit local shortcut names, typed targets, saved website addresses, folder labels, display choices and independently selected collection sources. No browsing request, remote icon fetch or receipt payload is generated. Normal Privacy & data can clear this document without deleting bookmarks/Spaces or reimporting legacy shortcuts; private/Student choices use separate memory. Catalog provenance and saved preferences never grant live navigation |
| Spaces | Up to 8 user-chosen spaces; choices, notes, checklists and approved-resource IDs. Each has at most 12 choices, 50 saved IDs, 20 checklist entries and 4,000 note characters. Choices are not inferred from browsing or blocks |
| Finish Mode | Up to 12 workspaces, with explicit goal, notes, checklists, up to 12 tab references and 50 saved result IDs. These are organizational groups, not website-storage isolation |
| Before You Commit | User-invoked bounded local analysis. Findings are transient by default; up to 8 explicitly saved normal analyses. Excerpts and goals/notes can be sensitive and remain out of receipts. Private saving is unavailable |
| Trust Receipt | At most 200 typed feature events within a 14-day display/retention window; timestamps rounded to the UTC hour. No queries, page text, source/resource IDs, interests, domains, full addresses or form data |
| Compatibility report | Screen memory only; fixed diagnostic enums/versions. Optional bare domain requires explicit opt-in and preview. No screenshot or raw capture. Export goes only to the user-selected clipboard action |
| Hand It Over | Static approved public text only. The owner tree is unmounted behind the gate. A separate secure-store envelope persists selected public IDs/hashes, code verifier and retry state for restart protection; it is replaced with an inactive marker after authenticated return. The handoff journal itself is memory-only |

Workspace restoration is strict. Unsupported schemas, malformed nested data, duplicates and oversized saved records must produce a storage-error state, preserve the original document and disable replacement writes. They must not silently erase notes, drop extra records or deduplicate the user's saved material. A saved resource's syntax is not approval: current policy still decides whether it may render.

Normal feature documents survive ordinary owner UI replacement during handoff. Private services are destroyed when their private-session scope ends and never feed normal suggestions, task undo or saved findings. Task closure uses membership on actual live tabs; a restored document's claimed tab ID alone cannot close another tab. Undo is normal-session only and rechecks every resource against current policy.

The Android handoff secure-store adapter explicitly disables automatic reset on decryption/storage errors (`resetOnError: false`) and uses the dedicated `wingman.handoff.v1` namespace. An unreadable envelope must leave the gate unavailable rather than silently becoming an absent session on a later launch. This namespace isolates handoff security state from the legacy optional-control PIN store; it is not a separate OS user or device-wide sandbox.

## Privacy journal and receipt semantics

`PrivacyJournal` accepts only activity, outcome and destination enums. Destinations distinguish local processing, clipboard/file export and named search/provider categories. These categories are instrumentation, not request implementations: the current app has no external search, AI or diagnostic submission endpoint. Synthetic request-outcome tests verify that completed external activity cannot be labeled local; they do not establish an active provider integration.

A receipt separates **configured behavior**, **observed feature activity**, and **provider disclosures/unknowns**. Policy version and freshness come from current runtime state, including expired/unavailable states. A receipt remains inspectable when content policy expires. Absence of recorded events never becomes “no data left your device”; provider retention and OS/host-browser traffic are outside the journal's observations.

Queued, started, completed, failed, canceled, blocked and interrupted operations have different receipt wording. Restored queued/in-flight operations become interrupted, not successful. Failed/canceled external activity does not imply the destination received nothing. Clipboard success means the API completed, not that Wingman received a submission.

The normal journal prunes on restoration, activity and an hourly in-process timer. A closed app cannot run retention cleanup; OS backups and snapshots are outside this guarantee. Persistence holds at most one active write and one latest snapshot so slow storage cannot accumulate an unbounded queue. A clear operation is ordered after earlier writes. If restoration fails, new observations stay in memory with an explicit unknown-history disclosure; the original stored document is not overwritten until the user clears the journal. A failed save is disclosed as potentially lost on restart.

Startup hydrates the existing journal rather than replacing it. Actual early observations and their in-flight outcome tokens remain in the same session, while validated prior observations are merged within the same bounds. Writes wait for restoration; the receipt discloses that earlier observations are still loading. Explicit clear during loading waits for hydration and cannot restore the old records afterward. Disposal prevents a late read from recreating or persisting the closed journal.

Private/handoff journals ignore normal initial state and never call a persistence callback. Handoff lifecycle event categories are rejected by a normal journal. Completing a token from another or disposed journal cannot append an event to it. Root session routing remains essential for all feature producers.

## Export and endpoint inventory

Trust Receipt and compatibility screens are previews. Copy requires a separate user action, a live owner/session gate and current foreground route. Editing a report invalidates its previous preview. Raw error messages are not shown or exported. No guest handoff control opens these screens or invokes copy.

| Wingman-owned destination | Current implementation | Transmitted fields |
|---|---|---|
| Cloud AI, sync, external search, report submission | No configured endpoint or transport | None from these features |
| Remote official-route/correction updates | Disabled; bundled common data only | None |
| System clipboard | Explicit user-reviewed copy | Receipt's typed observations/configuration, or report's fixed diagnostics plus domain only if opted in |
| Web host | Same-origin app/catalog/font/SQLite worker assets | Ordinary asset-request metadata visible to the selected host/browser |

System clipboard data can be accessed by other apps and clipboard services, potentially including OS cross-device features. Exports are outside Wingman's private journal persistence boundary. Flutter's basic clipboard API does not provide an OS-local-only option; the UI discloses access rather than claiming isolation. There is no automatic upload, email, support inbox or diagnostic success response. [Flutter clipboard API](https://api.flutter.dev/flutter/services/Clipboard/setData.html), [Android clipboard framework](https://developer.android.com/develop/ui/views/touch-and-input/copy-paste), [Apple pasteboard local-only option](https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/localonly)

Compatibility corrections remain separate from content eligibility. The sole operation wraps long text lines for an exact approved body digest. Production profiles are empty; controlled fixture evidence and remote-distribution limitations are in [Compatibility policy](COMPATIBILITY_PROFILE_POLICY.md). Native OS clipboard, handoff and cross-feature integration acceptance must be read from the final test matrix, not inferred from these source boundaries.
