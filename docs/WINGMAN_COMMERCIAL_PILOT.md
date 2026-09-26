# Wingman commercial pilot — owner review draft

Prepared 2026-09-26. The paid pilot is not open. This document is a planning and
review template, not legal advice, a binding agreement, a quote, an accepted
contract, or permission to deploy, contact advertisers, collect money, or spend
on acquisition. No actual paying advertiser, payment account, verified audience,
or earned revenue has been established by this implementation. Local examples
use synthetic campaigns and test money; their commercial revenue is zero.

## Local operational workflow

The advertiser inquiry page, operator console, campaign preview, business ledger,
and editable scenario calculator live in the separate `wingman_ads.operator`
application. They are not routes on the public search gateway. The default
fixture console binds only to loopback. Nothing has been published on an
owner-approved property.

From the repository root, these commands prepare a **fresh disposable fixture**:

```sh
PYTHONPATH=backend work/brave-venv/bin/python -m wingman_ads init-fixture --store backend/.local/ads-fixture.sqlite3
PYTHONPATH=backend work/brave-venv/bin/python -m wingman_ads set-password --store backend/.local/ads-fixture.sqlite3
PYTHONPATH=backend work/brave-venv/bin/python -m wingman_ads serve --store backend/.local/ads-fixture.sqlite3
```

Use the real terminal's hidden password prompt; never put a password in a URL,
command argument, web bundle, or conversation. Existing finance files must not be
deleted or reinitialized to replenish funds. Initialization is explicit and a
separate marker prevents resetting a missing ledger. Test and live stores are
separate; fixture campaigns cannot be activated as live campaigns.

The local preview is `http://127.0.0.1:8896/`. An inquiry saves business contact
details for owner review and takes no payment. `/admin` requires an authenticated
operator session; password changes revoke prior sessions. Sessions expire after
15 minutes; form mutations require same-origin CSRF validation. The console
requires exact Host/Origin values, escapes creative/contact text, and sends
no-store and same-origin referrer headers so Safari can preserve its same-origin
POST Origin; cross-origin referrers are withheld. Consumer search, ad and merchant
navigation retain no-referrer. Business contacts are isolated from consumer
requests. A secret URL is not authentication.

The operator reviews an inquiry, creates an advertiser, verifies its identity and
exact domain, then drafts a campaign. Saving changes invalidates outstanding
tokens and returns the creative to review. Approval requires a reviewed offer,
allowed destination, agreement reference, and reconciled funds; review expires
after 24 hours. Previewing a campaign records no billable delivery. Pause is
available even when delivery authorization has been revoked.

Production requires a separately approved durable single-host finance deployment,
explicit HTTPS origin, storage and finance authorizations, operator access,
backups, restore procedures, and an approved property. The ledger is not suitable
for independent per-instance SQLite copies in autoscaling cloud containers.
Search production configuration does not activate ads, advertiser billing, a
payment account, external demand, or the second-search-slot experiment.

## Pilot agreement worksheet

Complete these fields with the owner and appropriate reviewers before making an
offer. Keep agreement/business evidence in the restricted business records; use
reference IDs in the software, not consumer data or card details.

| Field | Owner-reviewed value |
|---|---|
| Advertiser legal identity and business contact | Pending |
| Verified domain and exact HTTPS landing destination | Pending |
| Offer, creative text and approved first-party raster | Pending |
| Agreement/review references and approval date | Pending |
| Countries and languages | Pending; explicit supported values only |
| Placements and nonsensitive contextual targets | Pending |
| Negative targets and excluded categories | Mandatory restrictions plus reviewed additions |
| Start/end, total/day budgets, impression/click caps | Pending; no unsupported delivery deadline |
| Currency and contracted billing basis | USD; fixed CPC or fixed CPM |
| Contract rate, deposit and verified available supply | Pending |
| Guaranteed quantity, if any | Pending; CPM only, within funded budget and hard cap |
| Exclusivity | Pending; overlapping exclusive inventory cannot be sold twice |
| Invoice, payment evidence and expected payment days | Pending |
| Underdelivery, cancellation and refund terms | Pending |
| Invalid-traffic review, dispute and credit process | Pending |
| Reporting period, bucket threshold and contacts | Pending |
| Merchant privacy and navigation responsibilities | Pending |

One search Sponsored unit is the default. A static New Tab sponsor occupies one
authorized placement. News inserts a Sponsored unit only after six organic cards
and caps combined sponsored density at two per deliberate feed session, counting
other sponsored content such as NewsUSA. Alternate raster sizes are not extra
inventory. Ads never alter organic ranking, browser protection, ordinary links,
or external publisher pages. Empty demand collapses the placement.

No ads are eligible in private, student, managed, warning/block/settings, login or
payment contexts, or in sensitive help, health, personal distress or financial
distress contexts. Selection uses an immediate reviewed nonsensitive intent or
documented broad section/country, with no browsing history, retained query,
precise location, IP profile, advertising identifier, fingerprint, demographic
segment, or consumer account identifier.

Paid units say **Sponsored** before their headline and explain the immediate
context and ordinary merchant connection information shared after a click.
Advertisers cannot buy a safety endorsement, protection exception, consumer
query, individual conversion report, pixel, SDK, script, iframe, or user-level
attribution token. Landing IDs resolve only to a reviewed exact destination;
merchant navigation retains the browser's mandatory protection and no-referrer
boundary. Ordinary links are never silently rewritten as affiliate links.

## Measurement and dispute terms to review

Wingman's proposed qualifying-impression definition is at least 50% of the
creative visible for one continuous second while the view is foreground and
active. This is a contractual definition, not independent measurement
certification. An opportunity, server fill, render, qualified visible impression,
deliberate click and billable event are distinct counters.

A deliberate CPC click may qualify before the one-second visibility threshold;
it is not automatically invalid because it arrived early. CPM settlement requires
the qualified view. A GET/HEAD, link scan, prefetch, preview, hidden/background
view, replay, expired token or revoked campaign is not a billable event.

Delivery tokens are random, signed, scoped to a campaign/creative/placement/price
version, and expire within 15 minutes. They identify a delivery, not a consumer.
Minimal delivery/page anti-replay state expires with them; an active service
sweeps expired state every minute and checks expiration transactionally on use.
Local frequency counters remain on the device. Aggregate burst limits and risk
caps do not prove a person is human; disputed activity requires review.

Pause/quarantine contested campaigns before reviewing charges. Audited credits
reduce earned revenue; refunds return available prepaid cash. An observed
chargeback is recorded even if the money was already earned: it pauses and
invalidates deliveries, releases reservations, and exposes a disputed receivable
without granting negative spendable funds. Resolve that receivable explicitly
through reviewed business records; do not silently erase earned delivery or
pretend reversed cash is settled. Replaying the same operation key cannot create
another receipt, refund, credit or reversal.

Underdelivery and cancellation should release unused reservations and reconcile
the remaining advertiser liability. Commit no fixed delivery date without
verified available inventory. A guarantee must fit the campaign's funded CPM
quantity, hard impression cap and total budget; this arithmetic is necessary but
does not prove traffic exists. Maintain a separate supply plan before approving
guarantees; exclusive conflicts are blocked by the campaign store.

## Illustrative packages — not current offers or forecasts

| Illustration | Arithmetic | Commercial prerequisite |
|---|---|---|
| $500 sponsor package at $10 CPM | 50,000 qualifying impressions × $0.01 | Verify 50,000 available qualifying impressions and any exclusivity before quoting |
| $500 prepaid contextual search at $0.50 CPC | At most 1,000 valid clicks | Verify eligible inventory, rate, destination, funding and owner approval |

Reduce the package or wait when measured supply is smaller. Neither package
promises reach, conversions, retention, demographics, full geographic coverage,
or a completion date. No actual brand logos or clients are implied.

## Manual invoice and payment reconciliation

No payment processor, card collection, webhook, live charge or auto-renewal is
connected. The operator records an external invoice, then independently verified
bank/payment evidence using a unique idempotency key. Recording an invoice does
not increase funds. Recording a receipt establishes prepaid advertiser liability;
only valid delivery earns revenue. The software records facts and initiates no
transfer. Never use a receipt entry to represent promised or uncollected funds.

Retain business evidence for invoices, deposits, refunds, credits, fees, partner
shares and chargebacks under the owner's reviewed business retention policy.
Export only aggregate campaign/day/placement reports; advertiser exports suppress
buckets below 20 renders. These reports do not expose unique consumers, paths,
queries, IP addresses or referrer joins. The owner can inspect restricted finance
totals and audit records independently of advertiser exports.

Any future payment integration needs an expressly authorized merchant account,
signature verification, replay/idempotency controls, retry-safe handling, refunds
and chargebacks, and reconciliation against the provider's records. That is a
separate activation gate, not a benefit of possessing a Brave credential.

## Finance source definitions and missing data

`wingman_ads.finance.dashboard_finance` consumes the campaign store's aggregate
report plus optional operator-supplied search/provider summaries and cost inputs.
The default console has no imported search or cost summary, so those figures are unknown.
`serve --finance-summary PATH` accepts an owner-only JSON file of at most 64 KiB
with exactly `searchReport` and `costs`; both are reread and validated together on
each dashboard request. The import changes no ledger, allowance or payment.
`create_server(..., search_report=..., costs=...)` is the explicit adapter boundary;
it may receive a read-only aggregate callable. Never point it at consumer logs.

The optional search summary contains `metrics` from the durable aggregate search
counter, `provider` from the provider ledger snapshot, `period:{start,end}` (UTC
dates), `periodAligned:true`, and `countsComplete:true`. The operator must verify
that business, search and provider totals cover exactly the same period/lifetime;
the calculator cannot establish that merely from two totals. Counters include all
submitted user search-page requests, including failed, private and noncommercial
requests. They are not unique audience, attributable users or paid inventory.
Incomplete, local-process, fixture or misaligned counters cannot produce a live
revenue-per-search claim.

| Measure | Definition |
|---|---|
| Submitted / completed / failed | All search-page request outcomes, with unresolved outcomes separately shown |
| Provider attempts by endpoint | Reservations persisted before dispatch, including failures, unknown outcomes and retries |
| Estimated success cost | List-rate estimate for confirmed HTTP successes; malformed HTTP200 responses still count |
| Unknown outcome reservation | Conservative held allowance, not a confirmed charge |
| Reconciled billed requests | Attempts with a positive reconciled charge; full billed-request count remains unknown until every attempt has a cost outcome |
| Actual provider cost | Complete cost reconciliation or explicit same-period cost evidence; partial reconciliation remains partial |
| Eligible rate / page fill | Eligible/filled search pages divided by all submitted requests, not per-slot counts |
| Fill among eligible | Filled slots / eligible slot opportunities; do not apply fill twice |
| Earned / collected / invoiced / settled | Separate business facts; collected deposits are not earned revenue and earned receivables are not settled cash |
| Search RPM | Net earned search USD × 1,000 / all submitted search requests |
| Variable contribution | Net earned delivery after credits, fees and shares, less actual provider/news/datastore/other variable costs |
| Fully loaded result | Variable contribution less fixed infrastructure, salaries/time, sales, licenses, taxes, support and acquisition |

Costs use integer USD micro-units and remain isolated from consumer traffic.
Supply `periodAligned:true` and a `costEvidenceReference` business reference.
Recognized cost categories are `providerWebMicros`, `providerNewsMicros`,
`otherSearchVariableMicros`, `otherNewtabVariableMicros`, `otherNewsVariableMicros`,
`datastoreMicros`, `fixedInfrastructureMicros`, `salariesTimeMicros`, `salesMicros`,
`licensesMicros`, `taxesMicros`, `supportMicros`, and `acquisitionMicros`. Missing
categories are null, not zero. Enter zero only when verified for the period.
Keep categories mutually exclusive to avoid double counting. Provider endpoint
costs must reconcile to the known total; cloud datastore operations are not free
merely because no cost has yet been supplied.

For a nonzero shared datastore bill, `searchDatastoreMicros` explicitly allocates
the search share, bounded by the total. Search contribution stays unknown without
that allocation; total variable contribution deducts the datastore bill only once.

When credits/fees/shares are nonzero, net yield by placement requires explicit
`placementAdjustments` for `search`, `newtab`, and `news`, each with
`creditsMicros`, `paymentFeesMicros`, and `partnerShareMicros`. Allocations must sum
exactly to recorded business totals; they are not automatically spread by clicks
or gross revenue. Without this allocation, net placement RPM stays unknown.
Optional `invoiceOutstandingMicros` and `cashSettledMicros` require verified
business evidence. `expectedPaymentDays` is an explicit planning assumption;
the dashboard does not invent time-to-cash from an invoice or an ad event.

## Editable sensitivity calculator

The authenticated `/calculator` form requires all assumptions. It records no
payment, campaign or forecast. Inputs are:

- `S`: optional total submitted searches for scaling a scenario.
- `f`: fraction of S receiving one billable-quality opportunity.
- `t`: valid click-through rate among those opportunities.
- `p`: net earned dollars per valid click after expected revenue deductions.
- `k`: all paid web provider attempts / S, including failures and retries.
- `c`: provider dollars per 1,000 calls.
- `v`: other variable search dollars per 1,000 S.

Revenue per 1,000 S = `1000 × f × t × p`.
Search delivery cost per 1,000 S = `k × c + v`.
Contribution = revenue − delivery cost.
Break-even coverage = cost / `(1000 × t × p)`.
Break-even net CPC = cost / `(1000 × f × t)`.
Zero denominators return unknown; coverage above 100% is marked infeasible.

With explicit sensitivity inputs `c=5`, `k=1.05`, `v=1.25`:

| Scenario | f | t | p | Revenue / 1,000 S | Cost / 1,000 S | Contribution / 1,000 S |
|---|---:|---:|---:|---:|---:|---:|
| Weak | 0.30 | 0.02 | $0.40 | $2.40 | $6.50 | −$4.10 |
| Working | 0.50 | 0.03 | $0.60 | $9.00 | $6.50 | $2.50 |
| Strong | 0.65 | 0.04 | $0.80 | $20.80 | $6.50 | $14.30 |

These are arithmetic examples, not predicted Wingman results. The scenario's
fully loaded result stays unknown until shared news and all fixed/operating
costs are supplied separately. Do not confuse CPM per qualifying impression with
RPM per all searches. A Brave Search subscription buys data supply, not demand.

## Partner evaluation record — blank and disabled

Copy this table for each real candidate; fill it only from actual documentation
and reviewed agreements. No candidate or integration is implied by the template.

| Record | Evidence / decision |
|---|---|
| Company and business contact | Unknown |
| Publisher API and official documentation | Unknown |
| Permitted Wingman web/native placements | Unknown |
| Organic-provider compatibility / syndication terms | Unknown |
| Minimum traffic, fees and revenue share | Unknown |
| Payment terms, reserves and time to cash | Unknown |
| Invalid-traffic, credits and disputes | Unknown |
| Mandatory request fields and purposes | Unknown |
| Retention, processors and deletion | Unknown |
| SDK, cookie, pixel, IP and identifier behavior | Unknown |
| Restricted-category and sensitive-context controls | Unknown |
| Rendering, Sponsored labeling and attribution | Unknown |
| Merchant/affiliate action permission, if relevant | Unknown |
| Privacy/API review and agreement references | Unknown |
| Owner authorization, inventory approval and expiry | Not authorized |
| Enabled state | **Disabled** |

Brave's advertiser buying console is not a publisher monetization account.
“Non-personalized” does not establish identifier-free operation. A partner that
requires prohibited tracking stays disabled. The demand chain's offline adapter
interface can select only an already reviewed and funded local campaign ID:
direct demand first, separately authorized partner next, expressly permitted
merchant action next, otherwise no-fill. There is no bundled external service,
SDK, network fan-out or fictional endpoint.

## Commercial launch and growth gates

Before claiming revenue-live, the owner must establish all of the following:

- An approved property and durable deployment with authenticated operations,
  restricted business data, tested backups/restore, logging boundaries and funded
  service budgets.
- A genuine advertiser/partner agreement, verified identity/domain/destination,
  allowed creative, approved inventory and explicit live-ad authorization.
- Actual funding/payment terms and reconciled business evidence, separate from
  fixtures and from the provider API allowance.
- Real eligible delivery, qualified measurement, valid settlement, aggregate
  reports and provider/advertiser cost reconciliation for an explicit period.
- Rights for each enabled content/media/shared-feed capability; unapproved
  optional capabilities remain disabled independently.
- Credible invalid-traffic review and pause/refund/chargeback procedures; tokens
  and burst limits alone are not a fraud certification.
- Verified supply for any guarantee; no invented audience, conversion, retention
  or unique-reach claims.

Before substantial growth, review at least four weeks of repeatable earned
revenue and actual variable costs against a proposed contribution margin of at
least 25%, safe operation and a funded runway. This is a planning gate, not a
guarantee. Pause paid acquisition when cost/retention evidence is insufficient;
do not respond by weakening protection or adding more intrusive ads. Retention
cannot be claimed measured without a separate privacy-reviewed method.

The second-search-slot and yield-exploration experiments remain owner-disabled.
Activation needs specific demand, relevance, stable layout, quality/latency and
incremental net-contribution evidence. The hard ceiling is two search units,
with the second after at least three organic results; no flag can bypass baseline
privacy or content protections.

Current blockers: no approved production property/deployment, no actual paying
campaign, no payment account authorization, no verified commercial traffic, no
reconciled live provider/ad costs, no owner-approved live ad finance state, and
no contracted external demand. Brave shared-news/media rights also remain
disabled unless separately granted. Local code and fixture evidence do not
resolve those facts.

## Verification and rollback

`test_ads_core.py`, `test_ads_review.py`, `test_ads_finance.py` and operator HTTP
tests use synthetic business records and local fixtures. Independent regressions
cover transaction-lock expiry/revocation, caps, replay, early clicks, impossible
guarantees, currencies, post-spend chargebacks, demand gates, experiment bounds,
scenario arithmetic, all-search denominators, missing costs, and fixture/live
separation. Consult the final progress report for the complete latest counts.

Rollback by pausing delivery and disabling ads in the gateway, then revoke the
live gate or stop the operator service as appropriate. Keep the finance database
and initialization marker, preserve audit/evidence and reconcile outstanding
liabilities. Do not delete/recreate the ledger, discard chargebacks, or turn
prepaid cash into earned revenue during rollback. Organic search, native RSS,
link handling and core browser protections remain independent.
