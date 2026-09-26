# Search deployment proposal — no authorization or deployment

The separate WSGI gateway and `Dockerfile.search` are implemented. The existing
read-only content service remains separate from search and the operator plane.
The content image now includes the rights-gated Brave adapter's dependencies.
Neither image has been built/pushed or deployed in this implementation session.

## Required explicit owner configuration

Use `wingman_search.config.SearchConfig` with `profile=production` and
`environment=production`, an approved HTTPS `production_gateway_url`,
`shared_ledger_kind=gcs`, actual `shared_project`, `shared_bucket`,
`shared_object`, `provider_spend_approval_reference`, `production_cap_micros`,
`deployment_approval_reference`, an existing `secret_manager_reference`, and a
mounted `rights_register_path`. No project, billing account, domain, identity,
price, storage permission or advertiser demand is inferred from CLI defaults.
The key is accessed with no retry and CRC32C verification after the durable cap
is checked. Rights are re-read before each dispatch. Advertiser billing is an
independent gate; organic search does not require advertiser billing approval.

`GCSBudgetLedger.initialize_approved` is an explicit one-time installation API,
not a startup action. Owner approval must define the total micro-unit cap,
separate daily Web/News attempt caps and applicable unit cost. Preserve its
immutable `.initialized` marker and every accounting generation. No scheduled
job or release initializer may recreate an existing or missing allowance.
The bounded initial ledger holds at most 10,000 attempts; exhaustion requires
review and a designed migration, never deletion/reinitialization.

The deployment must mount owner-reviewed non-secret configuration and rights,
set `WINGMAN_SEARCH_CONFIG` to its absolute mounted path and use a runtime
identity limited to the necessary operations objects and secret. The content
reader has no Brave secret access. The operator service and finance store must
remain private and must not be copied into the public search image.

## Reviewable commands, only after separate approval

Supply real approved values; these placeholders intentionally cannot deploy.
Never execute the mutation steps as part of fixture testing.

```sh
WM_PROJECT='OWNER_APPROVED_DEDICATED_PROJECT'
WM_REGION='OWNER_APPROVED_REGION'
WM_SERVICE='OWNER_APPROVED_SEARCH_SERVICE'
WM_IMAGE='OWNER_APPROVED_REGISTRY_IMAGE_AT_SHA256_DIGEST'
WM_CONFIG='/absolute/path/to/approved-search-config.json'

# Local validation only. No secret loading, cloud client or provider request.
PYTHONPATH=backend work/brave-venv/bin/python -c \
  'import sys; from wingman_search.runtime import read_config; read_config(sys.argv[1]); print("configuration structurally valid; owner approval still required")' "$WM_CONFIG"

# Inspect an already-approved target. Does not infer current gcloud defaults.
gcloud run services describe "$WM_SERVICE" --region "$WM_REGION" --project "$WM_PROJECT" --format=export

# Build locally only when the existing Docker runtime is available.
# Review .dockerignore and inspect image layers for credentials before publishing.
docker build --file backend/Dockerfile.search --tag wingman-search:review .

# After owner review, use a separately prepared deployment manifest with the
# pinned image, explicit runtime identity, mounted config, and existing secret.
# Review its full diff before this mutation; do not create IAM/DNS/billing here.
gcloud run services replace work/search-release/approved-service.yaml --region "$WM_REGION" --project "$WM_PROJECT"
```

Prepare `approved-service.yaml` only after the target is identified. Use private
canary ingress initially, 0 minimum/1 maximum instance, 8 maximum concurrency,
a 30-second timeout and no platform request retries. These infrastructure
limits are not hard spend caps; the shared reserve-before-dispatch ledger is.
The image uses one worker with four threads. Explicit News thumbnail tokens
remain in that process for at most five minutes; keep this single-instance
canary topology or separately review routing affinity before scaling it.
Restarts or requests reaching another instance leave text results usable and
images absent; clients never repeat the paid search to recover a thumbnail.
Explicitly validate proxy TLS handling: WSGI requires HTTPS and the approved
Host. Forwarded headers must be accepted only from the actual trusted TLS
terminator; never trust arbitrary client-supplied headers. Reject duplicate
framing headers and cap request sizes/connections at ingress. No user POST body,
query, cookie, address, referrer or token may be logged in CDN/WAF/APM/proxy/error
paths. Gunicorn application access/error output is suppressed in the image;
operator health comes from bounded aggregate counters. Review platform-provided
request metadata separately, including retention and deletion.

## Optional direct ads on an approved persistent host

The cloud search image is search-only. Never attach a local SQLite advertising
store to ephemeral Cloud Run instances or horizontally replicated copies. For
an independently authorized pilot on one durable host, install the backend
package including `wingman_ads`, mount its persistent financial store and use
the same WSGI factory with these additional explicit configuration fields:

```json
{
  "live_ads": true,
  "production_billing": true,
  "ads_runtime": "single-durable-host",
  "approved_ads_store_path": "/OWNER_APPROVED_PERSISTENT_VOLUME/ads.sqlite3"
}
```

This snippet is not a complete approved configuration. Both rights-register
gates and the independent owner-only live-finance evidence described in
`docs/WINGMAN_ADS_OPERATOR.md` are required. The existing store must already
have been explicitly initialized under that approval; startup never initializes
it or promotes fixture money. Run one host against one persistent database,
with tested backups, restore reconciliation and no auto-scaling. Keep the
operator server on loopback behind separately authorized private access; never
route its paths through the public search service. Its business-data backups
have a separate retention policy from consumer request state.

Advertising store or rights failure closes advertising without blocking an
otherwise authorized organic search. The constructed application exposes
`ads_unavailable` to the private host supervisor when startup cannot open the
approved ads service. Consumer responses contain no storage or approval details.
Every later ad operation rechecks the advertising rights and financial evidence.
Search dispatch independently rechecks `live_search`. Revocation cannot turn an
ad failure into a paid organic retry. Repairing a failed ads startup requires a
controlled restart after approval/storage repair, with the same intact ledger.

No automatic spending/replenishment, ongoing polling, DNS, IAM, cloud resources,
public invocation, domain setup or advertiser billing has been authorized.
GCS transaction and secret-access costs are **unknown**, not zero. Compute,
egress, storage, payment fees, support and fixed costs remain unpriced until an
approved target and measured workload exist. The reviewed Brave list-rate
estimate is $5/1,000 received successful requests before actual reconciliation;
reserved uncertain attempts consume the conservative allowance as well.

## Canary and rollback

1. Validate real target rights, secret metadata, non-resettable ledger/caps and
   approved logging configuration. Run datastore conflict/restore and privacy
   canaries only in that separately approved environment.
2. Start the approved private canary under its independent spending ceiling.
   Verify synthetic Web and News contracts, no extra endpoints, all rate windows,
   unknown-outcome accounting and end-to-end native navigation. Record actual
   invoice/provider charges separately from estimates. No automatic expansion.
3. On error, close `live_search`, `cached_news`, `live_ads`, `partner_demand` and
   `production_billing` gates as applicable; pause scheduled ingestion first.
   A rights-gated reader must immediately withhold revoked Brave items. Purge
   disallowed cached generations/backups using the approved retention procedure.
4. Restore the prior known-good app/image revision using the explicit project
   and service. Keep consumer app storage, bookmarks, Spaces, tabs, protection
   rules, provider accounting/initialization markers, financial records and
   audit records. Do not uninstall apps, wipe profiles, delete ledgers or reset
   request budgets. Do not reopen the old DDG search path as an error fallback.
5. Reconcile in-flight unknown provider attempts and outstanding advertiser
   reservations before reopening. Restore finance only from the latest complete
   reconciled state. Keep all gates closed if integrity cannot be established.
6. Obtain owner approval of canary evidence, real costs and remaining risks
   before increasing traffic. Code readiness is not release authorization.

Cloud persistence, mounted rights updates, TLS/logging behavior and the container
build remain unverified on real infrastructure. No production revenue is claimed.
