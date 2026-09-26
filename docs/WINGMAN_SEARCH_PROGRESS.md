# Wingman Search, News and Ads implementation record

Started 2026-09-26 from clean `main` at `e8d4d89` in the existing primary
checkout. Working branch: `feat/wingman-brave-search-revenue`. Other worktrees
were inspected and preserved. No applicable AGENTS.md was found. The complete
v2 pack was found in Downloads and copied unmodified into the repository.

Baseline: Flutter 0.16.0+19 app, Android System WebView, Apple WKWebView, web
companion and Python shared-content backend. The merged redesign and macOS
implementation are preserved. Historical README claims are superseded by
current code and dated acceptance reports; whole-web semantic protection is
not established by the existing host/path baseline.

## Phase checkpoints

- 01 complete (`fabe93c`): hidden credential entry, durable spending controls,
  strict DTOs, fixed-host provider transport, mandatory query/result checks and
  privacy gates. No real provider allowance has been consumed.
- 02 complete (`e720a1b`): branded All/News search, transient tab state and
  protected activation; actual web/Android/iOS fixture flows exercised.
- 03 complete (`1685c82`): rights-gated scheduled news and GCS generation-CAS
  accounting; 10,000 shared readers cause one fake upstream attempt. Live
  cache/media/scheduling remain off pending rights and budget.
- 04 complete (`a8ea1aa`): direct prepaid campaigns, three finite placements,
  signed short-lived event tokens and transactional test-money settlement;
  no private/managed/sensitive ads or merchant precontact.
- 05 complete (`42ffe4e`): authenticated operator/intake, manual payment
  reconciliation, aggregate finance/scenarios and pilot documents. All 50
  ads/operator/finance tests pass; actual Safari operator workflow verified.
- 06 complete locally (`7780abe` plus final acceptance checkpoint): Python 332
  passed/0 failed/0 skipped; Flutter 1,099 passed/6 optional skips/0 failures;
  analyzer clean; Android JVM 23 passed. Actual web, Android and iOS fixture
  acceptance passes (one composite native test each). Real native testing
  exposed and fixed a cross-zone RSS cancellation race (37 focused tests).
  Android's 6,093 ms first fixture search misses the latency target; live p95
  remains unverified. See WINGMAN_SEARCH_RELEASE_REPORT.md for final outcomes,
  exact commands, preserved failure evidence and production dependencies.

## Baseline evidence

Initial `flutter analyze --no-pub` failed due to a stale generated dependency map
missing XML. Initial system-Python tests lacked Pillow/defusedxml. After restoring
locked dependencies: analyzer clean, Flutter 1,055 passed/6 skipped, Python 186
passed, Android JVM 23 passed. Lockfile unchanged.
Logs live in ignored `work/brave-evidence/`; the release report summarizes them.

## Authorization and live-call record

No Brave dispatches have been made by this implementation session. Credential
status is unconfigured (metadata-only check). The single launcher allowance is at most one web and one
news request, count=1, strict, synthetic, no retries, stop on first failure.
The persistent ledger, not this prose record, is authoritative after setup.
No ongoing spending, shared Brave redistribution/media rights, live ads,
partner demand, advertiser charges, deployment or production release is approved.
No actual earned revenue is claimed. Never reset operations or financial ledgers
to repeat tests or roll back software.

Review hardening: all received ambiguous rate metadata now halts spending; production approval domains require exact canonical list membership; reporting failure after a completed paid response preserves results and sets an operator-health flag. Shared GCS generation-CAS ledger, explicit Secret Manager factory and HTTPS WSGI adapter are implemented with fake-cloud tests; no cloud target or live traffic has been used.

Phase04 acceptance uses a new isolated `work/brave-evidence/ads-acceptance.sqlite3`; the earlier fixture database remains preserved. These are test-money stores, not the Brave provider budget. The provider allowance remains uninitialized and the replacement key remains unconfigured. No paid provider call, cloud resource, merchant connection, charge, contract or sales outreach has occurred. Existing approved native RSS traffic is separate from the controlled Search/Ads recorder.
