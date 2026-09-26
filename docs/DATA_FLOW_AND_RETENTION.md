# Data flow and retention — implementation and launch dependencies

Reviewed September 26, 2026. Wingman does not build advertising profiles from
browsing history or sell search history. Submitted cloud searches necessarily
leave the device. A query can contain personal information even when forwarding
headers and stable identifiers are removed.

| Boundary | Data and purpose | Storage / launch state |
| --- | --- | --- |
| Local input | Current submitted query, locale and selected country | Ephemeral search state; no upload before explicit submit; local preferences do not become ad profiles |
| Wingman gateway | POST body needed for policy validation and provider request | No raw query/URL/referrer persistence, search analytics, request-body logs or query-bearing traces; query responses require no-store |
| Brave request | Necessary query/locale/country, server-fixed strict filter, count/offset; constant service identity | Server-to-server only; no consumer IP, cookie, Authorization, account identifier or complete browser headers forwarded |
| Brave provider | Processes the submitted query and server network metadata | Reviewed standard notice permits query retention up to 90 days; enterprise zero retention is unverified |
| Result display | Sanitized Wingman DTOs; publisher attribution and destination | Transient response; no shared Brave result cache, CDN fan-out or offline preview archive without documented rights |
| Explicit normal News thumbnail | Returned Brave thumbnail reference, opaque five-minute token, lazy POST to Wingman and one CDN fetch per token | Bounded transient token lookup; small PNG held only in originating normal-search memory until expiry/clear; no disk or server image-byte cache; private/managed contexts text-only |
| Budget ledger | Endpoint, local environment, UTC date/time, attempt outcome and integer money | Durable purpose-limited accounting; no query/result/consumer identifier fields; retained across rollback and credential rotation |
| Secret file | Replacement provider token | Ignored owner-only backend file for local development; never delivered to app; approved Secret Manager required for production |
| Direct ad decision | Current nonsensitive context only | No consumer history, retained interests, external segments, fingerprinting or raw query reports |
| Ad security | Event-scoped short-lived signed tokens and anti-replay state | Purpose-limited; expiry/deletion tested by ad subsystem; no stable user identity; pseudonymous processing must be disclosed |
| Advertiser finance | Approved campaign/contact/invoice/payment and aggregate delivery | Access-controlled business records, isolated from consumer activity; prepayment liability separate from earned revenue |

Private and student/managed surfaces have no ads or automatic news requests in
this release. No merchant/third-party creative or tracker is contacted merely
to render the strict first-party ad. A deliberate advertiser visit is an ordinary
external website visit, subject to that site's separate data practices and
Wingman's supported navigation protection.

## Collection controls to verify at deployment

The gateway must reject GET query endpoints/unsupported parameters, avoid URL
query strings, emit `Referrer-Policy: no-referrer` and `Cache-Control: no-store`,
and use an appropriate CSP. Search data must not enter service-worker storage,
browser persistence, crash reports, replay tools or exported reports. Expected
errors return short status classes only; raw HTTP exception objects often
contain query URLs and must never be logged or forwarded.

POST alone does not establish privacy. The eventual CDN, reverse proxy, load
balancer, WAF, framework, tracing, error-reporting and backup configurations must
be inspected for initial collection of request bodies, query strings, IPs,
headers and tokens. A later retention exclusion is not proof that collection
never occurred. No new deployment exists at this milestone, so those production
controls are unverified release dependencies. Required admin/security audit logs
must remain enabled with action/state identifiers only and no consumer query.

Do not describe hashed queries or IP addresses as anonymous, and do not claim
“nothing leaves your device” or “nobody stores your searches.” A no-provider-
retention product requirement blocks launch until the applicable agreement
actually supports it. The local proxy cannot erase personal information that a
person typed inside a query.

## Rights and deletion boundaries

An arbitrary short cache TTL is not storage permission. Brave shared-news cache,
shared image downloading/caching and full-text retention remain disabled under
`backend/config/brave_rights.json`. The owner's separate request authorizes
[transient thumbnails in explicit normal News Search](BRAVE_NEWS_THUMBNAILS.md):
only returned HTTPS `imgs.search.brave.com` references, a five-minute opaque
lookup, lazy first-party POST and a small re-encoded PNG. Image delivery makes
no additional Search API call. It forwards no consumer cookie/referrer or
subscription token and has no direct publisher/original-image fallback.

This narrow result-display path does not authorize shared feed storage, offline
images or shared or retained production media rights. Existing separately
approved content sources retain their own rights and independent pipeline. The source/publisher is
identified without presenting API permission as a publisher image license.
Live thumbnail verification is recorded in the linked feature record.

Deleting content caches must not delete cost/finance records or replenish a
provider allowance. A local key replacement changes credential material only.
Accounting snapshots expose aggregate operational fields and no credential-
derived fingerprint. Foundation fixture tests inspect the actual ledger schema
and bytes, metadata-only secret status, safe file rules and public source assets.
Final built-artifact and infrastructure scans remain part of release acceptance;
source scanning alone is not evidence for an uninspected production bundle.
