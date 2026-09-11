# Privacy architecture

**We've got your back, not your data.** This document describes 0.4 permanent-protection foundation. [The previous architecture](history/PRIVACY_ARCHITECTURE_PHASE3A.md) is historical and does not describe current runtime behavior.

## Data boundaries

| Data | Current handling |
| --- | --- |
| Approved article bodies/metadata | Bundled, signed, loaded locally; source URLs never fetched |
| Queries, session tabs/back-forward trail | Memory only; reviewed IDs rather than arbitrary page metadata |
| Consumer bookmarks/reading state | Separate local reviewed-ID preferences, rechecked before display |
| Private sessions | No new saved activity; other-session library hidden; fresh after restart |
| Student/unknown editions | Reviewed-session saves in memory; no account identity or consumer-save restoration |
| Additional restrictions/theme/text size | Local preferences; restrictions never approve content |
| Legacy tabs/bookmarks/history/reading list | SQLite v3 quarantine; counts only; no raw title/address/preview exposure |
| Policy checkpoint | Local sequence/time/revocation floor, no query or browsing events |
| Review requests | No service or upload; UI explains a minimal human-contact process |
| Ads/consent/analytics/crash services | No ad/consent SDK or configured telemetry pipeline |

No behavior is monetized or used to build inferred interests. There is no AI endpoint, VPN, proxy, cloud sync, remote content fetcher or account sign-in. The empty future commerce interface does not initiate work. Removing the SDK avoids initialization-time advertising traffic even when legacy debug flags are supplied.

Startup loads trust and verifies bundled policy, awaits native old-site-data cleanup, and migrates metadata before showing content. Android cancels only this application's unfinished DownloadManager requests. Completed downloads and external exports remain user-owned. A fixed failure screen does not disclose exception strings or legacy data.

Session reset clears reviewed saves/current tabs/query state within the defined session, retaining additional restrictions and quarantine. It is not an erasure promise for OS backups, file-system snapshots, completed files or other applications. SQLite is not separately encrypted by Wingman. Native backup-exclusion settings reduce exposure but do not establish device-wide erasure.

## Network inventory and evidence

The production catalog has no app-created browsing/search/classification/advertising requests. Android release manifest excludes INTERNET; debug/profile builds retain tooling networking. iOS has no content transport in the new adapter. Native integration loopback counters verify that attempted browsing/direct native calls make no request to the test server, not that every OS daemon is silent.

Web preview requests its same-origin Flutter application/font/catalog/SQLite assets. No remote font CDN is required by the documented build command. The host browser can still use its own services. Emulator/simulator framework traffic, Flutter tooling and host browser traffic must not be represented as Wingman collection or as evidence of universal silence. Final artifact and observed runtime findings are in MONETIZATION_POLICY.md and RELEASE_READINESS.md.

No full-packet production-device audit or third-party legal certification has been completed. Before a school pilot, review OS/keyboard/backup behavior, retention, shared-session cleanup, legal obligations and operator contracts using SCHOOL_DEPLOYMENT.md. Do not enroll real students or collect identifiers to test this milestone.
