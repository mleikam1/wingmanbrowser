# Phase 3A local library and persistence evidence

Recorded 2026-09-10 for the everyday-browser milestone. These are source, host-test and synthetic SQLite measurements. Native picker, share-sheet, reader and main-app acceptance are reported separately; this document does not infer those results from host tests.

## Implemented boundaries

- Reading list stores explicit URL/title/created/read-state metadata, with a 500-page limit. It does not retain article bodies or provide offline copies. Save-from-page rejects private tabs and Home both in state and before repository database access. A separate explicit HTTP(S) address action works from normal Home, including the web companion, without search, navigation or a fetch; private tabs cannot use it. Read/unread and remove await durable storage.
- Bookmark import accepts user-selected UTF-8 Netscape HTML, up to 2 MiB and 5,000 candidate links. It retains HTTP(S) URLs without credentials, plain text titles of at most 512 Unicode code points, and bounded optional dates. It ignores executable/resource markup, rejects excessive markup complexity, never renders imported HTML, and has no networking or filesystem API. Folders flatten into a list. JSON and history import are unsupported in this milestone.
- Previewing does not write data. Confirmed import rechecks duplicates and capacity on the serialized write queue, merges atomically, and reports success only after SQL commit. Bookmark Add/Remove actions retain the intent shown when invoked, so a queued import cannot turn Add into removal. Failures return fixed, sanitized messages and keep prior visible library state.
- Export escapes all URL attributes and title text into Netscape HTML and rejects files beyond the same import bounds. It is an intentional plaintext export of bookmark URLs/titles, not an encrypted backup. The UI owns the user-selected output/share surface and temporary export-file lifecycle.
- New bookmarks are limited to 5,000. Oversized libraries created before this limit are preserved and may shrink; loading or migration does not silently truncate them. Such legacy data can exceed the new-library memory/iteration bounds.
- SQLite schema v2 adds `reading_list`; the transactional v1 migration preserves tabs, history, bookmarks and settings. `page_scale` defaults to 100% and clamps to 75–200% on copy/update, save and load. History remains separately limited to 90 days/5,000 unique URLs.

The metadata remains local. Android/iOS use the existing app SQLite location; web uses the existing SQLite worker/IndexedDB adapter. No sync, account, remote import, browsing telemetry or page-body collection was added.

## Automated evidence

The focused command is:

```sh
flutter test test/data test/state test/domain test/performance --reporter expanded
```

The focused suite passed **100 tests**. Scoped `flutter analyze` reported **no issues** for domain/data/state and their tests. Parent-workspace raw logs: `work/phase3-data-final-test.log` and `work/phase3-data-analyze.log`. The main handoff records the final whole-project checks separately.

| Scenario | Evidence |
| --- | --- |
| Actual v1 file upgrade and v2 close/reopen | [Library repository tests](../../test/data/library_repository_test.dart) seed the original schema and verify existing tabs/active ID/history/bookmarks/theme/provider/onboarding/Guard configuration/statistics/local suggestions, then reading state and page size across reopen. |
| Migration failure preserves evidence | A conflicting table forces a real SQLite upgrade failure. The database stays at v1 and retains its old records. |
| Atomic import/write failure | A SQLite trigger aborts an insertion partway through the batch. The old bookmark set remains intact. |
| Private source at the storage boundary | A direct private reading-list save returns before creating a database file; state tests also exercise tab changes while a normal save is queued. Existing history/session exclusion tests remain passing. |
| Capacity and prior data | SQL tests exercise the 500-page reading limit, duplicate URL prevention, 5,001 existing bookmarks preserved, rejected growth and allowed deletion. |
| Import safety/round trip | [Codec tests](../../test/domain/bookmark_transfer_test.dart) exercise scripts/resource tags, credentials and unsupported schemes, entities, Unicode, escaping, invalid dates, malformed UTF-8, excessive candidates, nesting and a megabyte of unterminated tag starts. |
| Concurrent actions and failure recovery | [State tests](../../test/state/browser_state_test.dart) cover duplicate imports, queued bookmark actions, commit-time capacity, invalid constructed previews, failure without false success, read/unread/remove failure, private exclusion and retry after a failed write. |
| Local suggestions | [Suggestion tests](../../test/domain/local_suggestions_test.dart) reject invalid/credential-bearing matching records and stop before consulting history when five bookmark results exist. Existing disabled/private early-return tests remain passing. |

Five additional [Reader lifecycle widget tests](../../test/reader_lifecycle_test.dart) passed with a controlled delayed extractor and the actual shell/Navigator: covering Settings, rapid route push/pop, inactive/resumed, a current successful completion and private transient use. They verify that stale results cannot open Reader and do not save history/bookmarks/reading-list metadata. They do not test native article extraction or establish Reader availability on a particular platform. Raw log: `work/phase3-reader-lifecycle-test.log`; scoped analysis: `work/phase3-reader-lifecycle-analyze.log`.

## Same-fixture metadata restoration comparison

The same [host restoration test](../../test/performance/metadata_restore_test.dart) ran against an isolated detached worktree of baseline `e0ee0934346f1b1aa9a5a59f3fd72fdb01ff812b` and the Phase 3A working code. Each independent process created a v1 file with **10 normal tabs, 5,000 bookmarks and 5,000 history rows**, then measured the first `BrowserState.init()` and 20 subsequent close/reopen operations. The Phase 3 run upgraded the file to v2; the baseline kept v1. Both preserved normal metadata and produced **zero private test URL/title rows** after a private session was closed.

| Host-only metric | Phase 2 baseline | Phase 3A |
| --- | ---: | ---: |
| First metadata open, including v2 migration where applicable | 88.77 ms | 73.71 ms |
| Repeated metadata reopen p50, 20 samples | 37.70 ms | 36.26 ms |
| Repeated metadata reopen p95 | 43.80 ms | 40.45 ms |

Raw logs: `work/phase3-metadata-restore-before.log` and `work/phase3-metadata-restore-after.log`. This is **not app startup, process-to-first-frame time, native WebView restoration or a physical-device benchmark**. Fixture creation already warmed SQLite, repeat runs used filesystem caches, and other host work/GC varied. The small difference is not a claimed speedup. The combined final suite also logs a separate run; its timing naturally differs from the sequential comparison.

## Maximum-library capacity sample

[Capacity fixture](../../test/performance/library_capacity_test.dart): 5,000 bookmarks plus 5,000 history rows, an 842,961-byte bookmark HTML file and 50 measured no-match suggestion requests after 10 warmups.

The sequential host samples measured roughly **195–208 ms** to decode the file and **90–96 ms** to commit all 5,000 bookmarks in SQLite. Import parsing runs separately from ordinary typing; native UI integration can use an isolate, while web parsing remains an explicit bounded operation on its thread. These measurements do not promise frame-time performance on a phone.

Moving URL parsing after the text match reduced the sampled worst-case no-match suggestion p50 from **4.74 ms to 2.74 ms**, and p95 from **4.91 ms to 3.00 ms**. Results remain capped at five, with no network requests and no suggestions in private mode. Raw logs: `work/phase3-library-capacity-before.log` and `work/phase3-library-capacity-after.log`.

The logs also record two process RSS snapshots. They include Flutter test runtime, SQLite, allocated fixtures and uncontrolled GC; they are neither peak application memory nor a valid before/after memory-improvement comparison. Native renderer memory, slow/older physical devices, OS interruption during a write, browser storage eviction and real user-file provider behavior require their own acceptance evidence.

## Provisional local budgets

For repeatable runs of these same synthetic host fixtures, investigate metadata-reopen p95 above **60 ms**, maximum-library suggestion p95 above **5 ms**, or 5k-file decode/commit above **300/150 ms**. These investigation thresholds allow headroom above the recorded baseline; they are not a physical-device service level or a reason to ignore visible input stalls. Native parsing remains off the UI thread regardless of the measured duration. Enforce the functional bounds of **2 MiB**, **5,000 bookmarks**, **500 reading entries** and **three resident views** independently of timing.

Actual browser-ready cold-start and total-browser-memory budgets require controlled device baselines before adoption. The native validation report records the unresolved idle-memory increase and mixed repeated timings rather than asserting they meet an unmeasured release budget.
