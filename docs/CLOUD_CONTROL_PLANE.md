> Historical Phase 1–3A document. Optional Guard, live browsing, external search, Reader and ad behavior described here is superseded by [permanent protection 0.4](RELEASE_READINESS.md). It is not a current capability or release claim.

# Wingman Cloud control-plane design

**Wingman Cloud powers the browser. It does not watch users browse.**

Phase 2 does not require a running backend. No Google Cloud or Firebase resources were created, no production deployment was made, and no Firebase SDK was added. Remote pack/config updates remain inactive until an actual signed distribution endpoint and release authority are configured. The app includes an optional `HttpsFilterPackUpdateSource` transport for a fixed HTTPS manifest and signed relative artifact filenames; shipped startup supplies no instance or endpoint. It refuses redirects and credentials, bounds response bytes, and verifies the downloaded data before activation. Normal browsing and the last valid local Guard data must work without that service.

## Small distribution design

Use a public, cacheable signed global manifest and immutable versioned artifacts. A Cloud Storage bucket with reviewed HTTP caching is sufficient initially; evaluate a CDN only when measured distribution demand warrants it. Cloud Run is optional for a concrete control-plane job, not a per-navigation classifier. Do not add accounts, databases, messaging, analytics, per-user remote configuration or a fleet of microservices to serve shared files.

Download the same global manifest/bundle across users where practical. Requests for separately named lifestyle packs can disclose preferences to a distributor even without a browsing URL. Bundle design should minimize that leak. Never add selected categories, active hosts, PIN state, history, search terms, precise user identifiers or private-session flags to headers/query parameters.

A future release pipeline should:

1. Validate provenance, license, domain normalization, schema, resource limits and support-resource exceptions in staging.
2. Generate deterministic manifest bytes containing the version, creation time, minimum app version, pack sizes/digests and public signing-key ID.
3. Sign those exact bytes with a dedicated asymmetric Cloud KMS key. Keep the private key out of clients, source, artifacts, environment dumps and logs.
4. Publish immutable artifacts, then atomically promote the signed manifest. Preserve the previous release and a reviewed rollback route.
5. Let clients verify signature, bounds, SHA-256 and compatibility before atomic activation; retain the last valid version if a fetch or validation fails.

Cloud KMS supports pure Ed25519 signing of raw input bytes. It must match the client's algorithm and byte encoding exactly; do not accidentally sign a prehash with a client expecting pure Ed25519. Grant the publisher only the signing permission on the specific key and required object-write permissions. Keep signing authority separate from public artifact access. [KMS algorithms](https://docs.cloud.google.com/kms/docs/algorithms), [asymmetric signing](https://docs.cloud.google.com/kms/docs/create-validate-signatures)

A compromised distribution bucket must not be able to invent signed rules. A compromised signing authority is a different threat: require release review, audit signer usage, allow public-key rotation through a separately reviewed trust policy, and avoid remote values that bypass immutable client protections. No signed feature flag may disable TLS validation, transmit navigation URLs, grant unrestricted native capabilities, replace publisher ads, or override user's Guard choices for a commercial partner.

## Environments, costs and logs

Keep dev, staging and production projects/buckets/keys distinct, with explicit environment variables in future infrastructure definitions. Test through dev/staging endpoints and non-production keys; never promote a fixture key as production trust. Set budgets/alerts before meaningful production spend, define object lifecycle policies, monitor aggregate serving health, and place rate limits/abuse controls on any future dynamic API. Budgets alert; they should not be described as a guaranteed hard spending cap. [Cloud budgets](https://docs.cloud.google.com/billing/docs/how-to/budgets)

A proposed starting update cadence is no more than daily with randomized scheduling, conditional requests and bounded retries; real rollout must measure list size, cache behavior and freshness needs. A thousand visited pages should not create a thousand Wingman API requests. Pack-signing operations scale with releases; shared downloads scale primarily with active clients and cadence. Compute and request budgets must be measured at realistic client counts before large rollout.

CDN/storage/Cloud Run infrastructure can observe IP addresses, request time, artifact paths and ordinary transport metadata. Configure access-log collection/retention deliberately; excluding fields in application code does not sanitize infrastructure logs automatically. Prefer coarse service-health metrics, short justified retention, no request bodies/query strings, no stable client identifier, and no page URLs in errors. Set actual retention before deployment rather than claiming a policy already exists. [Cloud Logging exclusions](https://docs.cloud.google.com/logging/docs/exclusions)

The only app-side optional network action in this design is fetching common signed data; normal navigation has no dependency on it. On update failure, keep the last valid local pack and explain staleness without disabling Guard silently. Provider-specific threat-data licenses and expiration requirements still apply; Wingman's own offline pack policy must not be used to redistribute or indefinitely reuse someone else's restricted threat feed.

## Other planes

The browsing plane remains on device: full URLs, history, bookmarks, tabs, private browsing, Guard decisions/settings and local counters. A future optional sync plane needs explicit enrollment, an encryption/key-recovery design and independent consent; it must remain separate from ads and analytics. A future aggregate-reporting plane must not reconstruct browsing histories from event sequences, domains, categories or stable identifiers. Neither plane is implemented by this design.

False-classification reporting is a separate user action, with an explicit preview of what would leave the device and optional domain/URL inclusion. No report endpoint or automatic original-URL submission is implied by a local report composer. The Web Risk Evaluate/Submission APIs are also not silently called on behalf of a user. See [provider boundaries](PHASE2_PROVIDERS.md).

Implement a future publisher against [the actual filter-pack contract](GUARD_FILTER_PACKS.md), including the signed canonical-index digest and monotonic sequence checks. [Performance evidence](GUARD_PERFORMANCE.md) concerns local evaluation and import; it is not a cloud capacity forecast.
