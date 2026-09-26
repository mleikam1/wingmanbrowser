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

- 01 local checkpoint passed: secure local entry, durable spending controls,
  strict DTOs, fixed-host provider transport, mandatory query/result checks and
  privacy gates. 26 foundation tests and 10 provider-contract tests passed.
  Production shared datastore and infrastructure approval remain launch gates.
- 02 in progress: Flutter branded search, explicit News tab and protected activation.
- 03 queued: rights-gated provider-neutral shared news and scheduling.
- 04 queued: direct campaigns, ad rendering, valid-event settlement.
- 05 queued: operator/advertiser workflow, reconciled finance and scenarios.
- 06 queued: integration, security, platform and release evidence.

## Baseline evidence

Initial `flutter analyze --no-pub` failed due to a stale generated dependency map
missing XML. Initial system-Python tests lacked Pillow/defusedxml. After restoring
locked dependencies: analyzer clean, Flutter 1,055 passed/6 skipped, Python 186
passed, Android JVM 23 passed. Lockfile unchanged.
Logs live in ignored `work/brave-evidence/`; release report will summarize them.

## Authorization and live-call record

No Brave dispatches have been made by this implementation session. Credential
status is unconfigured (metadata-only check). The single launcher allowance is at most one web and one
news request, count=1, strict, synthetic, no retries, stop on first failure.
The persistent ledger, not this prose record, is authoritative after setup.
No ongoing spending, shared Brave redistribution/media rights, live ads,
partner demand, advertiser charges, deployment or production release is approved.
No actual earned revenue is claimed. Never reset operations or financial ledgers
to repeat tests or roll back software.
