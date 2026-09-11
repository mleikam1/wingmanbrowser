# Privacy architecture

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

## Network inventory and evidence

The production catalog has no app-created browsing/search/classification/advertising requests. The verified Android release merged manifest excludes INTERNET; a release APK/runtime is not available because the local AOT helper stalled. Debug/profile builds retain tooling networking. iOS has no content transport in the new adapter. Native integration loopback counters verify that attempted browsing/direct native calls make no request to the test server, not that every OS daemon is silent.

Web preview requests its same-origin Flutter application/font/catalog/SQLite assets. No remote font CDN is required by the documented build command. The host browser can still use its own services. Emulator/simulator framework traffic, Flutter tooling and host browser traffic must not be represented as Wingman collection or as evidence of universal silence. Final artifact and observed runtime findings are in MONETIZATION_POLICY.md and RELEASE_READINESS.md.

No full-packet production-device audit or third-party legal certification has been completed. Before a school pilot, review OS/keyboard/backup behavior, retention, shared-session cleanup, legal obligations and operator contracts using SCHOOL_DEPLOYMENT.md. Do not enroll real students or collect identifiers to test this milestone.

## Signature features: local state and explicit disclosure

Normal consumer feature documents use the existing local SQLite database and fixed `workspace`, `privacy`, and reserved `compatibility` namespaces. There is no separate backend or per-feature account. Each document is bounded to 512 KiB. Private and Student/unknown services wrap storage with a separate memory implementation, so a mistaken save request still cannot read or write the owner's backing store.

| Feature data | Boundary and retention |
|---|---|
| Official Routes | Common bundled identity/evidence catalog, searched locally. Identity review does not grant live navigation or imply the organization endorses Wingman |
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
