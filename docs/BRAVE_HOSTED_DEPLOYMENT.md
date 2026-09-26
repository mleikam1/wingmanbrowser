# Hosted Brave gateway — deployment record

September 26, 2026. The owner approved hosting Wingman Search in the existing
`wingman-interactive-live` Google Cloud project and a separate **$5 total Brave
request allowance**. The target app is **iOS internal TestFlight 0.17.0 (20)**,
bundle ID `com.wingmanbrowser.app`.

**The gateway is deployed. Hosted Web/News and News images passed verification
in the actual iOS simulator app. Apple accepted the internal TestFlight upload;
the build is Testing in the existing internal group. Delivery is recorded in [TESTFLIGHT_0_17_0.md](TESTFLIGHT_0_17_0.md).** Cloud
Build `7b73a128-527b-471e-9b12-06e1b4821e0f` completed successfully. Revision
`wingman-search-00001-mhh` is ready and receives 100% of traffic; public invocation
is enabled. Apple delivery is recorded separately after upload.

## Target and installed resources

The approved gateway is
`https://wingman-search-599739618634.us-central1.run.app/v1/search`.
This deterministic address passed the unpaid checks below. The release must embed it as
`WINGMAN_SEARCH_URL`; no local-development search URL belongs in TestFlight.
Native publisher RSS remains the feed default; shared Brave ingestion and
advertising are disabled.

| Resource | Recorded configuration |
| --- | --- |
| Project / region / service target | `wingman-interactive-live` / `us-central1` / `wingman-search` |
| Runtime identity | `wingman-search-runtime@wingman-interactive-live.iam.gserviceaccount.com` |
| Build identity | `wingman-search-build@wingman-interactive-live.iam.gserviceaccount.com` |
| Image build target | `us-central1-docker.pkg.dev/wingman-interactive-live/wingman-browser/search:0.17.0-20` |
| Build / serving revision | `7b73a128-527b-471e-9b12-06e1b4821e0f` — SUCCESS / `wingman-search-00001-mhh` — READY |
| Operations bucket | `wingman-brave-ops-599739618634`, versioning enabled, uniform access and public-access prevention |
| Build-source bucket | `wingman-browser-builds-599739618634`, uniform access and public-access prevention |
| Secret Manager | `wingman-brave-key`, `wingman-search-config`, `wingman-search-rights`, initial version 1, regional replication in `us-central1` |

The deployed image is pinned to
`sha256:f6b88bca4c02ff5b73fdb85c6b8ce97d16f47be806d4fd02c46114b91fdf17b4`.

The Brave credential stays on the server in Secret Manager. It is not an app
define, app asset, image layer, consumer response, or log field. The runtime
identity has secret access on these three named secrets. Its ledger write role
is conditioned on the exact budget object; a separate read binding covers the
initialization marker. The build identity has source-bucket read and repository
write access. No advertiser/operator financial store is included in this image.

## Fixed allowance and accounting

The one-time hosted approval is `wingman-brave-hosted-20260926-usd5`. Its durable
GCS ledger is `wingman-operations/brave-budget.json` in the operations bucket,
with the preserved, held `brave-budget.json.initialized` marker beside it.
The installation receipt records zero attempts and a held immutable marker.

- Total cap: **5,000,000 USD micros ($5)**, at **5,000 micros per reservation**;
  therefore at most **1,000 attempts** over the allowance's lifetime.
- Additional daily UTC caps: **100 Web and 100 News attempts**. A new day does
  not replenish the total allowance.
- Every attempt is reserved durably before dispatch. Failed or uncertain
  outcomes consume conservative capacity; invoice reconciliation remains
  distinct from estimated successful-request cost.
- Startup, redeployment and rollback must not initialize, delete, reset, refill
  or replace the allowance or its marker. Exhaustion needs a separate owner
  decision, not an automatic retry or new ledger.

The original local evaluation grant and its accounting remain unchanged. This
hosted authorization does not reopen or replenish it. The $5 limit bounds this
gateway's conservative Brave reservations; it is not a Google Cloud billing
cap or a claim about spending through other clients of the provider account.

## Deployed runtime and privacy boundary

The deployment uses **CPU always allocated, minimum zero and maximum
one instance**, one Gunicorn worker, four threads, and the explicit
`wingman_search.gunicorn_cloud_run` configuration. The service has one CPU,
512 MiB memory, concurrency eight and a 30-second request timeout. Always-allocated CPU lets
transient thumbnail expiry timers run while an instance exists. Minimum zero
permits scaling down; it does not make hosting free. Compute, storage, Secret
Manager, operations and network charges are separate and not yet reconciled.

The single worker owns the transient thumbnail-token registry: at most 128
entries, five-minute expiry, and one CDN fetch per consumed token. The server
does not cache image bytes. The originating normal-search client may briefly
retain its bounded image bytes for Back. A restart can remove optional images
without repeating a paid search. Scaling or routing changes require review.

Gunicorn access/error output goes to `/dev/null`. The installed `_Default`
logging-sink exclusion `wingman-search-consumer-privacy` is scoped to
`resource.type="cloud_run_revision"` and
`resource.labels.service_name="wingman-search"`. It is not a project-wide or
provider-wide no-logging guarantee: administrative audit records and build logs
are separate. Do not add request bodies, queries, tokens, upstream image URLs,
cookies, addresses or referrers to consumer logs. Verification should retain
aggregate counts, not provider bodies or request traces. A provider zero-retention
agreement and additional shared-content rights are not verified.

## Unpaid deployment checks

Six checks against the deterministic HTTPS host passed without a Brave attempt:

| Check | Response |
| --- | --- |
| `GET /` | 404, `not-found` |
| Approved-origin `OPTIONS /v1/search` | 200, `ok` |
| Invalid-query `POST /v1/search` | 400, `invalid-query` |
| Invalid-token `POST /v1/search/thumbnail` | 404, `thumbnail-unavailable` |
| Unapproved-origin `GET /` | 403, `origin-not-allowed` |
| `GET /` with alternate forwarded-host header | 404, `not-found` |

Each response had `Cache-Control: no-store, private`. Before and after snapshots
both show **zero Brave attempts, zero reserved micros and zero unknown outcomes**.
Durable search metrics correctly record one submitted/failed invalid query and
zero completions; that denominator entry is not a billed provider attempt.

Cloud Run's edge reserves `/healthz`, which returned Google's HTML 404 rather
than Wingman's handler. [Google's reserved-path guidance](https://docs.cloud.google.com/run/docs/known-issues#reserved_url_paths)
recommends avoiding paths ending in `z`. This build uses the platform's TCP
startup probe on port 8080 and the verified `OPTIONS /v1/search` response for
non-spending readiness. No extra health alias was added. These checks validate
the gateway boundary, not live Brave Web/News results or image retrieval.

## Native hosted acceptance

The ordinary `lib/main.dart` iOS app was built with the HTTPS gateway and installed
over the existing verification simulator app without clearing data. Launch,
opening a new tab, and typing a neutral NASA query left the hosted ledger at zero
attempts. Explicit All and News submissions returned genuine attributed results;
News displayed a thumbnail. Opening a permitted NASA article rendered its content.
Back restored the same News image and scroll position within the transient window.
The added verification tab was closed and the original tab restored.

Private ledger snapshots after News and after Back both recorded exactly **two
attempts: one Web and one News**, both HTTP/schema successes, zero unknowns and
**10,000 micros ($0.01)** conservatively reserved. Thus scrolling, thumbnail
rendering, article navigation and Back added no paid Search API call. Remaining
capacity at this check was **998 attempts / $4.99**. CDN fetch count was not exposed
or measured on the public service; fixture tests cover its one-use token behavior.
Provider responses and query histories were not saved to source control.

The release checks passed: 421 backend tests, including eight Cloud Run parser
checks; 32 focused app version/UI tests; and the iOS simulator build. The source
baseline already passed 1,117 Flutter tests (six existing optional skips), analysis,
and web/Android/iOS builds during the preceding thumbnail release.

## Owner rollback and revocation

The verified service specification pins `wingman-search-config` to version 1 and mounts
`wingman-search-rights:latest` at `/etc/wingman-rights/rights.json`. The key
reference is also pinned to version 1. Preserve the latest-version rights mount
on future revisions; pinning it to version 1 would prevent later revocation
versions from being observed automatically.

To close hosted search, preserve the existing rights document and add a new
version of `wingman-search-rights` with `gates.live_search.enabled=false`. Keep
the latest-version mount. The gateway rereads rights before each dispatch and
rejects subsequent search operations after it observes the update. Confirm
revocation with a non-spending check; already dispatched attempts remain in the
ledger and require normal accounting. Stop traffic if the update cannot be
confirmed, and keep the gate closed while restoring a known-good image.

Preserve all ledger generations, the held initialization marker, app data and
financial records. Do not roll accounting back with application code, delete
the bucket, reuse the local allowance, or turn on a search fallback. Restoring
service requires the owner's reviewed correction and intact remaining capacity.

Nonsecret deployment receipts are retained in ignored
`work/testflight-0.17.0/cloud/`: `resource-operations.json`,
`configuration-install.json`, `config.json`, `rights.json`, and
`build-submission.json`, plus `service-state.json` and `unpaid-probes.json`.
The submission receipt's original queued state is historical; the build has
since succeeded. Hosted live acceptance snapshots are `before-native-submit.json`,
`after-native-news.json` and `after-native-back.json`. Signed archive verification
and TestFlight processing status are recorded after those steps succeed. See [deployment controls](../backend/deploy/SEARCH_RELEASE.md)
and [thumbnail boundaries](BRAVE_NEWS_THUMBNAILS.md).
