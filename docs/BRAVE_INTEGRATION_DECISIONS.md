# Brave integration decisions — local implementation, production gates closed

Reviewed September 26, 2026. Governing inputs are the supplied
`wingman_search_revenue_pack` v2 launcher, master, addendum, API contract, local
key instructions, sources, revenue playbook and Phase 01. Public provider
documentation establishes API capabilities; it does not establish this owner's
account balance, signed storage grant, paid demand or production permission.

## Baseline and scope

The primary checkout began clean on `main` at
`e8d4d8930f2a1352d7c4d0c868659abba2a501b6` (merged redesign and native macOS
browser). Work proceeds on `feat/wingman-brave-search-revenue`, preserving the
Flutter/Dart app, Android System WebView, iOS/macOS WKWebView, shared Swift
protection, web companion and Python content backend. No applicable AGENTS.md
was found in the repository or its ancestors. The other three local checkouts
are worktrees of this repository, not separate authoritative products.

The existing search path uses DuckDuckGo Strict, with separate library/official
local search; native navigation independently enforces the mandatory policy.
Brave development adds protected DTOs and a secret-bearing gateway boundary.
It does not change native browser engines or turn the public read-only news
snapshot service into an arbitrary upstream proxy. Production endpoint,
dedicated cloud project/domain, shared ledger, billing ceiling, merchant setup
and commercial demand remain owner-controlled dependencies. No cloud inventory
or unrelated project was modified.

Historical README material describes versions 0.9–0.14 and says native desktop
is unimplemented, while the current tree is 0.16.0+19 and includes macOS. The
historical exact-document restriction is not the current consumer destination
model. Existing protection documentation records real mixed-content and native
interception gaps; a strict provider request does not close those gaps.

## Rights and operational gates

The machine-readable register is `backend/config/brave_rights.json`. Separate
gates cover live search, cached news, remote media, live ads, partner demand and
production billing. They never affect the permanent protection baseline.
Unknown permissions stay disabled. An operator-set boolean is not evidence of
an agreement; enabled register entries require approval status and a nonsecret
reference to privately held authorization.

Ordinary human-facing API result display is documented by Brave; an enterprise
agreement is not assumed necessary for every request. Account acceptance and
production application scope still require verification. Transient result
processing is distinct from shared news snapshots, CDN fan-out, offline preview
retention, image/full-text rights and advertising-syndication terms. Those
expanded uses stay disabled until documented permission covers the actual use.
Provider identification remains truthful without suggesting Brave endorsement.

Brave's organic Search API is paid result supply. Its advertiser-facing Search
Ads/reporting APIs do not establish a Wingman publisher-demand entitlement.
Direct approved campaigns are a separate business path; fixtures and advertiser
prepayment are not earned delivery revenue. No contract, outreach, purchase,
advertiser charge or paid infrastructure change was made for this milestone.

## Decisions and evidence

- Default profile: fixtures, with ongoing development and production spend zero.
- Local smoke: the launcher grants at most one Web plus one News request,
  synthetic queries, count=1, server-side strict filtering, no retries and stop
  on the first failure. The durable allowance is never a daily replenishment.
- Credentials: hidden owner input into ignored owner-only `backend/.env.brave`;
  a replacement key is required after chat exposure. No real key was read or
  verified during foundation implementation.
- Accounting: integer USD micros, UTC buckets, reservations committed before
  dispatch; uncertain outcomes never create new attempt capacity.
- Local persistence: SQLite plus independent initialization marker, outside
  content caches. Production SQLite is rejected; an approved shared datastore
  with transaction/contended-worker tests is a release dependency.
- Configuration: unknown live rights, background news, media, ad demand and
  production billing remain disabled. Local fixture code is not release approval.

The foundation suite passed 26 fixture-only tests using
`PYTHONPATH=backend python3 -m unittest backend.tests.test_brave_foundation -v`.
These cover concurrency, restart, irreversible allowance exhaustion, partial
dispatch, corruption, rate windows, privacy schema, production refusal, secret
path safety and public-source secret scanning. Baseline suites and integrated
phase results are recorded centrally in `WINGMAN_SEARCH_PROGRESS.md`.

Official sources reviewed by the integration task:
[Web reference](https://api-dashboard.search.brave.com/api-reference/web/search/get),
[News reference](https://api-dashboard.search.brave.com/api-reference/news/news_search/get),
[plans](https://api-dashboard.search.brave.com/app/plans),
[rate limiting](https://api-dashboard.search.brave.com/documentation/guides/rate-limiting),
[terms](https://api-dashboard.search.brave.com/terms-of-service),
[privacy](https://api-dashboard.search.brave.com/privacy-policy) and
[API overview](https://brave.com/search/api/). Account-specific permissions have
not been verified by these public-document checks.
