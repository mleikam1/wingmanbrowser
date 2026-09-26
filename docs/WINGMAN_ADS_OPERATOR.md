# Wingman direct ads: local operation and approval boundaries

The implementation can run a complete direct campaign workflow using isolated test money. The paid pilot remains **closed**: no verified inventory, paying customer, accepted contract, reconciled live funds or owner-approved production deployment was created in this work. A Brave Search credential supplies search data; it does not supply advertiser demand.

## Run the fixture workflow

From the repository, using the supported Python environment with `backend/requirements.txt` installed:

```sh
PYTHONPATH=backend work/brave-venv/bin/python -m wingman_ads init-fixture --store work/operator-demo.sqlite3
PYTHONPATH=backend work/brave-venv/bin/python -m wingman_ads set-password --store work/operator-demo.sqlite3
PYTHONPATH=backend work/brave-venv/bin/python -m wingman_ads serve --store work/operator-demo.sqlite3 --port 8896
```

Initialize only a new path. Initialization refuses an existing store or its identity marker; missing/corrupt files fail closed rather than resetting money. Password entry requires an interactive terminal and disables echoed fallback. The minimum length is 16 characters. There is no password argument, URL secret or credential in a browser bundle. `set-password` rotates the credential and invalidates existing sessions on their next request. Never use the public test-helper credential with a real store.

Visit `http://127.0.0.1:8896/` for the advertiser inquiry page and `/admin` for owner sign-in. The server binds only loopback. The fixture banner and commercial revenue zero remain visible. Gateway and operator processes may share **one exact SQLite file on one durable host**; transactions serialize through `BEGIN IMMEDIATE`. This is a bounded single-host pilot architecture, not an autoscaled or multi-host finance database. Do not put a separate SQLite finance file inside each Cloud Run/container instance.

The fixtures are a synthetic sponsor on `example.org`, a test $500 receipt and a fixed $0.50 CPC campaign. They are not a client, legal agreement, collection of cash or live impression. Root fixture gateway support can open the same fixture store with `open_fixture_service(path)`. `initialize_fixture_store(path)` creates a fresh isolated fixture explicitly. Both return an `AdsService`; call `close()` on server shutdown.

## Owner workflow

1. Review an inquiry, then separately validate advertiser identity, domain ownership and offer. Accepting an inquiry creates an unapproved advertiser; it does not accept an agreement.
2. Create a campaign draft with headline/body, exact approved HTTPS domain, reviewed broad contexts and negative contexts, dates in UTC, language/country, USD rate, total/daily limits, impression/click caps and external agreement reference. Default demand is direct. Images are optional: the raster sanitizer accepts PNG/JPEG, strips metadata and re-encodes first-party PNG. The shipping Flutter renderer currently displays text.
3. Record an invoice as a business record. Reconcile the external bank/payment receipt separately using a unique idempotency reference and evidence reference. The form records facts; it neither collects cards nor transfers money. Invoice records alone never fund delivery.
4. Preview, manually check the destination/offer/creative/contract/available inventory, then approve. Review expires after 24 hours. No automatic HTTP destination crawler runs: the scheduled expiry requires renewed human destination review, and policy/active state is checked again at decision and click. An unreviewed or changed destination never resolves from a click. Review is supplemental to native navigation protection, not a safety endorsement.
5. Monitor reserves, qualified views, deliberate clicks and earned charges. Pause/quarantine releases reservations and invalidates outstanding delivery versions. After investigating aggregate invalid traffic, enter an idempotent earned credit with the dispute evidence reference. Credit restores advertiser liability but does not reset the original spend cap.
6. Reconcile refunds, fees, partner shares and external chargebacks. Refunds cannot withdraw reserved/already-earned funds. A verified chargeback always pauses the campaign, releases reserves and records reversed cash; if the cash had already been earned, the report shows a disputed receivable, not spendable funds. Resolve it through collection or a reviewed credit. Do not hide an actual reversal because it exceeds unused balance.
7. Download the specific campaign’s aggregate report from its review page. Campaign/day/placement buckets below 20 renders are suppressed. The all-campaign download is for the owner. Business totals are separate from traffic buckets; never promise unique reach, individual conversions or attribution paths.

An exclusive campaign blocks overlapping approved inventory for its placement/country/language/date range, conservatively without overselling by context. Guaranteed impressions are supported for CPM packages only, cannot exceed the impression cap or budget, and require reconciled prepayment. This proves a numeric ceiling, not that real traffic exists; the owner must verify available supply before a quote.

## Delivery and financial semantics

All money is integer USD micros (`1 USD = 1,000,000 micros`); unsupported currencies are rejected. CPM rates must divide exactly into integer per-impression micros. Test stores return `chargedMicros: 0`, `billable: false` and a distinct `testChargedMicros`; fixtures contribute zero commercial revenue.

Search ad selection receives only a signed, short-lived grant for a reviewed broad intent after a successful nonempty initial normal search. Raw query, result contents, IP, account/device ID, history and stable interests never enter the ad store. New Tab uses untargeted inventory; news uses explicit nonsensitive current sections only. Private/student/managed and sensitive contexts do not receive ads.

One search unit is default; one New Tab sponsor; news cards follow six/twelve organic cards and share the maximum-two limit with NewsUSA. The second-search slot requires at least three initial organic results, a signed grant allowing it, a local frontend compile-time gate and separate owner evidence. It remains off by default. `experiment_approval` requires current demand, stable layout, relevance, incremental net contribution and quality/latency evidence references. The optional exploration share is capped at 10% and also off by default. No remote flag can raise the two-slot ceiling or weaken policy.

Candidate order is approved funded direct campaigns, a separately contracted privacy-compatible partner slot, expressly permitted merchant slot, then no-fill. No real external adapter, endpoint, auction, SDK, affiliate rewriting or partner account is connected. Default extension slots do not call anything. The tested extension interface can only choose among already reviewed/funded local campaign IDs and receives the finite current context; it cannot inject markup, URLs or tracking fields. Live bootstrap currently permits direct campaigns only, even if a test adapter is passed.

Policy, quality/relevance and contracted pacing precede estimated net yield. CPC click/fill and CPM qualifying-view/fill use the same delivered-opportunity denominator. Below 20 fills they are explicitly uncertain assumptions (1% click, 25% qualifying view); thereafter conservative smoothing applies. Estimates never settle money. No raw queries or provider result corpus train this calculation.

Deliveries reserve the price against cash, total and daily budgets under the same transaction as issuance. A signed 15-minute token binds delivery, campaign, creative, placement, price and version. The server reacquires current time, owner approval, token validity, active campaign and destination policy **after obtaining the transaction lock**. Duplicate event state cannot charge again.

Only POST events can settle. A CPC click requires a delivered token, foreground visibility and explicit user action; a genuine early click can bill before a one-second view. A CPM view requires at least 50% continuously visible for one second in a foreground view, plus at least a second since server issuance. Render/GET/HEAD/asset retrieval never bills. Successful click returns the approved clean merchant URL as JSON; there is no arbitrary redirect endpoint, query forwarding or per-user tracking suffix. Frontend navigation remains no-referrer and subject to native protection.

These are Wingman’s proposed contractual events, not independently certified human/viewability measurements. Tokens and client visibility claims do not prove a human. The service caps aggregate campaign issuance bursts and reserves a maximum liability; it does not fingerprint users. Disputed activity must be paused and reviewed rather than presented as solved fraud.

## Data retention and security

Delivery IDs, random page IDs, one-time event state and unfilled opportunity state expire within 15 minutes. Startup cleanup and a bounded 60-second sweeper release reservations and delete expired rows; with a healthy running service the maximum logical retention is 15 minutes plus 60 seconds. If offline, expired rows are purged before serving at startup. Storage failures fail serving closed. SQLite secure deletion is enabled for erased cells. Do not preserve consumer transient tables in long-term backups; recovery procedures must purge expired state before service resumes. Business invoices/receipts/adjustments, aggregate finance and owner audit are separate records, retained under the owner’s accounting policy.

Operator sessions are memory-only, random, expire after 15 minutes, rotate on login and revoke after password changes. CSRF tokens protect login and every mutation; the server checks exact Host and Origin and rejects duplicate fields, oversized bodies and transfer encoding. Cookies are HttpOnly/SameSite Strict and Secure on an approved HTTPS live origin. Authentication rate limits are global and bounded, without storing IP profiles. A maximum eight concurrent operator requests and five-second socket timeout bound resource use. HTML is escaped, CSP disallows scripts/external assets/frames, and HTTP access/body/header logging is disabled. The operator site uses `Referrer-Policy: same-origin` to preserve Safari’s same-origin POST Origin while withholding all cross-origin referrers; consumer ad/merchant navigation uses no-referrer.

Do not package `.sqlite3`, identity markers, approval JSON, signing keys, passwords, local invoice evidence or business contact exports with source releases. A real deployment needs protected durable storage and backups, monitored health/expiry, TLS on the approved owner property, a constrained reverse proxy/network boundary, operator credential management and owner-approved recovery procedures. Reverse-proxy forwarding headers do not establish application authorization. Public search exposes no operator routes.

## Explicit approved live bootstrap (not run)

`AdsStore.initialize_approved_live(path, authorization_path=...)` creates a **separate empty** live store. It never promotes/imports a fixture database. `open_approved_live_service(path)` opens that live store only on the declared single durable host and rereads its persisted owner evidence file for delivery and settlement. The gateway must separately enforce its live ads, billing, search-rights and deployment gates.

The owner-only approval JSON requires exact fields documented in `wingman_ads.common.live_approval`: schemaVersion 1; environment `single-durable-host`; exact absolute storePath; operatorHostId; approved HTTPS productionOrigin; expiry no later than 366 days; deployment/liveAds/finance/manualPayments evidence references; explicit approved flags plus durableStorage/singleHost true; partnerDemandEnabled false; secondSearchAdEnabled false by default. References record actual owner evidence; writing placeholder references is not approval. A live operator origin must match exactly. No live store was initialized for operation, no merchant account connected and no live charge authorized in this session. Synthetic tests exercise the gate without real financial actions.

## Finance inputs and missing evidence

The operator displays exact business totals and clearly marks missing search/cost figures. To combine externally verified, matching-period snapshots, pass `--finance-summary PATH` to `serve`. The file must be owner-only, at most 64 KiB and contain exactly `searchReport` and `costs`. It is reread per dashboard request and passed through `dashboard_finance`; it never changes the ledger or budgets. `searchReport` accepts the aggregate search metrics snapshot, aggregate provider ledger snapshot, period start/end and explicit completeness/alignment flags. Live ratios additionally require production durable counters. Do not put raw request logs or credentials into this file.

`finance.py` defines the finite cost fields and placement adjustment reconciliation. Missing costs, unreconciled provider outcomes, unverified periods and absent settled-cash evidence stay null. Search revenue per 1,000 uses **all submitted search-page requests**, including failures and noncommercial requests, with slot and page counters separate. The editable calculator uses explicit scenario assumptions; its $2.40/$9.00/$20.80 revenue cases and -$4.10/$2.50/$14.30 contribution cases are arithmetic, not forecasts.

## Evidence and rollback

Tests: `PYTHONPATH=backend work/brave-venv/bin/python -m unittest discover -s backend/tests -p 'test_ads*.py' -v`. The fixture-only matrix covers money concurrency, tokens, expiry/pause/revocation races, currency, demand chain, second-slot gates, finance arithmetic, chargebacks, operator authentication/CSRF/origin, intake and invoice workflows. See `work/brave-evidence/phase05-ads-tests.log` for the final count.

Actual local Safari verified advertiser copy, sign-in, authenticated operations and working scenario 9.00 revenue − 6.50 cost = 2.50 contribution. Review used only `work/brave-evidence/operator-fixtures.sqlite3` and loopback port 8896; no provider, payment, ad partner or merchant was contacted. Screenshots contain no credentials or delivery tokens.

Rollback by disabling frontend ads, stopping the ad service or revoking live evidence; pause campaigns to invalidate existing tokens and release reservations. Preserve the finance database and marker, retain audit/contract/reconciliation records, and resolve outstanding liabilities. Never delete/reinitialize the ledger as a rollback or spending reset.
