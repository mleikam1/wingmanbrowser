# Wingman live content architecture

Current feed-candidate integration and shared-media rules: [FEED_CANDIDATE_INTEGRATION.md](FEED_CANDIDATE_INTEGRATION.md). Historical version notes below remain unchanged.

## Implemented boundary

Version 0.13.0+14 connects ordinary native consumer builds directly to 12 reviewed
public feeds: NASA, NOAA, USGS and nine Global Voices sections. Home presents a
three-story preview; Updates has fixed topic controls, one featured story, compact
following rows and explicit Load more. Coverage includes headlines, sports,
entertainment, technology, business, fashion, science, food, health and environment.
Sections have different publication frequencies; sparse coverage stays honest.

Topic selection, saved items, dismissed items, hidden sources, ranking and finite
pagination happen on the device. Every device requests the same configured feeds,
independent of interests. No browsing history, search query, selected topic, save
or dismissal is sent. Publishers can see the device IP and ordinary connection
metadata. Feed networking and content exposure stop in private/handoff contexts
or when Updates is off. Article taps use the unchanged consumer destination policy.

`RssFeedProvider` is the default on native platforms. A build explicitly configured
with `WINGMAN_FEED_URL` continues to use `SnapshotFeedProvider`. The web companion
requires that common HTTPS service because publishers do not offer suitable CORS.
There is no deployed Wingman content backend, paid key, arbitrary feed import,
remote image service or background scheduler. GeckoView is a rendering engine;
it does not supply editorial content. The browser engine was not changed.

### Native feed path

`rss_transport_native.dart` performs bounded HTTPS requests against the fixed
registry: public DNS only, numeric connection with original-host TLS verification,
no proxy environment, no cookies/referrer, three maximum redirects with validation,
four-second DNS timeout, eight-second connection bound and 25-second source deadline.
DNS futures retain a concurrency slot until they actually finish. Identity encoding
is requested; compressed responses are rejected. Bodies are capped at 1 MiB before
parsing. Three fetch lanes share a 45-second batch deadline; there are no immediate
retries. Failed sections retain only eligible unexpired cached rows.

`rss_parser.dart` accepts bounded RSS/Atom XML without DTD/entity processing and
converts only supplied title, description and author metadata to plain text. Rights,
scope, dates and current destination policy all apply before display. Fashion uses
one fixed publisher search and requires a specific clothing/design term in metadata;
an incidental word such as “fashion” cannot establish membership. Topic mismatch
omits only that section; actual rights/safety withdrawal still revokes the article.
Specialized sections precede the general feed during canonical-URL deduplication.
The Headlines tab displays all topics, without inventing personalized ranking.

Each source retains validators, last success, failures and next refresh. A minimum
30-minute interval, publisher cache directives and Retry-After/backoff survive
relaunch and cache deletion in `liveContentRefreshState`. The controller alone
persists the provider's candidate state, guarded by its owner-session generation.
An unreadable/unwritable checkpoint blocks further requests instead of silently
resetting publisher pacing. No provider writes directly to storage. Cache, saved
links and preferences retain their independent bounded local documents.

The following shared-service path remains available for an explicitly configured
backend/web deployment and has not been deployed by this change:

```text
Reviewed source configuration + mandatory destination policy
                       |
            scheduled ingestion job
                       |
     configured HTTPS feeds, conditional requests
                       |
     bounded XML parser -> rights/scope/eligibility -> dedup
                       |
          atomic private generation bundle
                       |
          GET /v1/snapshot.json (common)
                       |
      device cache -> local interests -> finite cards
                       |
      article tap -> ordinary protected Wingman browser
```

`backend/wingman_content/provider.py` defines the provider-neutral `NewsProvider`
boundary. `RssAtomProvider` is the first implementation. Future licensed providers
must produce the same normalized records and carry independently reviewed rights
and eligibility; their native response schemas do not reach Home.

The backend code is local and deployable. **No production feed endpoint or paid
cloud infrastructure was deployed.** Normal native builds work through direct
RSS without that service. Localhost remains only an optional integration endpoint.

## Configuration and rights

`backend/sources.json` is the reviewed ingestion configuration. It pins each feed
URL, exact redirect hosts, exact article hosts, allowed article path prefixes,
language, topic scope, rights, source review time, 1,800-second minimum refresh
interval and seven-day normalized-text retention cap. Those intervals are Wingman
engineering bounds; the publishers did not provide numeric contractual limits in
the reviewed guidance. See `CONTENT_SOURCES_AND_RIGHTS.md` for the source-specific
evidence and restrictions.

The generated `assets/live_content/sources.json` pins the same approved source
identity, feed/redirect hosts, pacing, article hosts and paths, topics, language,
rights and scope in the app.
A server response cannot grant itself an additional publisher, image right or
scope. Regenerate it after an approved configuration change:

```sh
PYTHONPATH=backend python -m wingman_content registry
```

NASA's mixed technology feed contains some earth science items. Each NASA item is
labelled science; technology is added only for the publisher's exact
`www.nasa.gov/technology/` section path. This uses publisher section evidence,
not headline keyword guesses. NOAA and USGS retain their reviewed science and
environment feed scopes.

Initial cards use publisher titles and bounded plain publisher descriptions.
RSS author/DC creator and Atom author names are retained as bounded plain item
attribution when supplied. Explicit item rights notices are also inspected and
retained when eligible. Source credit remains visible even without a byline.
Images are always `null`; no publisher logo, remote thumbnail, embedded player,
article body or full-text mirror is fetched or stored. Any local decorative topic
art is independent of the publisher. No generated text is presented as news.

## Transport and parser protections

The details in this subsection describe the optional Python ingestion transport;
native transport differences are documented above. Only ingestion code can select
a configured source. Neither the CLI nor GET
service accepts an arbitrary feed URL or article URL. A source fetch:

- Allows HTTPS on port 443, no credentials, fragments, control characters or
  backslashes, and only exact configured feed/redirect hosts.
- Resolves DNS in a terminable subprocess with a four-second bound; rejects the
  entire answer set if any address is private, loopback, reserved, multicast,
  unspecified, link-local, documentation, carrier-grade NAT, local translation or
  otherwise nonpublic. IPv4-mapped addresses are checked again as IPv4.
- Connects to a vetted numeric address while preserving the original hostname
  for TLS certificate verification and SNI. It does not honor proxy environment
  variables or perform a second unvalidated DNS lookup. TLS errors are failures.
- Revalidates host, scheme and public DNS after every redirect; at most three
  redirects are followed. A redirect to metadata/local addresses or HTTP fails.
- Has an eight-second socket bound and 25-second total fetch deadline, including
  redirect work, with connection interruption. A feed cannot cause unbounded
  resolver threads or repeated connection attempts.
- Accepts only XML/RSS/Atom MIME types, bounds response headers to 32 KiB, wire
  bytes to 1 MiB and inflated XML to 2 MiB. Incremental gzip decoding rejects
  oversized output, extra streams and truncation; other encodings are rejected.

The XML parser uses `defusedxml` with DTDs, entity declarations and external
entities explicitly forbidden. It accepts RSS 2 and Atom, at most 500 entries and
20,000 XML nodes. XInclude, XSLT and external schemas are never evaluated. HTML
descriptions are converted to plain text without executing or loading anything;
script/style/iframe/SVG content and image markup are dropped. Displayed titles
are capped at 200 characters and descriptions at 400. Eligibility inspects the
full bounded title and description before truncation.

Eligibility combines a reviewed named publisher/feed, publication scope, exact
destination host and path, permitted reuse, the same pinned six-category consumer
destination denylist, and conservative text/category checks for promotion or
third-party rights notices. A positive word match does not authorize an unknown
publisher or prove arbitrary content safe. Ambiguous restricted-product promotion
is held. Research/reporting context is distinct from promotion, within the
reviewed sources. This is a conservative curated-source implementation, not a
claim of perfect automated content classification. Held counts, reason counts
and at most ten examples per source remain in private administrative state and
CLI reports; they do not appear in the common client payload.

## Refresh, identity and removal

Each source independently stores ETag, Last-Modified, last successful validation,
next permitted refresh and consecutive failures. The job makes one attempt per
due source. A successful 304 reuses normalized text and publication dates and
updates only fetch/validation freshness. A persisted normalization version plus
configuration digest forces a full response on the first **due** fetch after
parser, rights or scope changes; it does not bypass the refresh interval.

Cache-Control max-age/s-maxage can increase the next refresh time. HTTP Retry-After
is honored without shortening a publisher's requested wait; values beyond a year
pause that source for operator review instead of fetching early. Failures back
off exponentially from 30 minutes to
six hours, with a bounded failure counter. There are no immediate retries and
Cloud Run/Scheduler templates also disable platform retries. Client pull-to-refresh in shared-service mode only reads the current snapshot.
Native direct mode checks each publisher’s persisted due time before requesting.
Successful 304 responses retain an earlier Cache-Control interval when the header
is omitted. An explicit `private` or `no-store` response prevents shared caching
and revokes previously stored source text rather than serving it through fallback.

Article IDs are a stable hash of a validated canonical HTTPS URL. Known tracking
parameters and fragments are removed. Equal canonical URLs deduplicate within or
across sources; equal titles at distinct URLs remain distinct. Internal RSS/Atom
IDs are hashed for revocation matching. The shared feed is limited to 300 items
and 512 KiB; the on-device implementation supplies finite pages.

`publishedAt` is the actual publisher publication timestamp or JSON `null` if
missing, invalid, timezone-less or implausibly future-dated. Atom `updated` is not
substituted for publication. `fetchedAt`, snapshot `generatedAt` and expiry are
separate fields. Known publication dates older than 30 days are omitted from the
current feed; undated items are explicitly undated, never labelled newly
published. Fetch failures preserve only unexpired normalized records and their
original dates. Even if the ingestion job stops, the GET service drops items whose
seven-day retention expiry has passed. Snapshot expiry still signals stale data.

An explicitly disabled or removed source emits `revokedSourceIds` and removes its
cards even without a publisher request. Configured item URL/ID revocations, Atom
tombstones and a previously eligible item that becomes ineligible emit persistent
`revokedItemIds`. Revoked records cannot reappear from cached fallback or a later
feed response. Ordinary rolling-feed omission removes the card from the next
finite snapshot and is **not** falsely labelled a publisher revocation. The app
keeps saved links separately but suppresses revoked cached text. A rehabilitated
source/item would require an explicit reviewed registry/protocol update; this
version does not silently undo revocations. The common envelope matches the
client's 5,000-item revocation limit. If that is exceeded, the service publishes a
source-wide halt and no items, preserving removal through `revokedSourceIds` and
requiring operator review rather than emitting an unparseable envelope or
silently forgetting removals.

## Atomic storage and read-only service

One private generation bundle contains normalized source state and the common
snapshot. Local writes use a same-directory temporary file, fsync and atomic
replacement under a process lock. A failed write leaves the previous generation
intact. The GCS adapter uses a single private object and generation-match
preconditions, so overlapping jobs cannot publish stale state over a newer write.
The public endpoint never exposes the state member or raw feed XML.

`GET /v1/snapshot.json` has no query parameters, preferences or user identifier.
It emits JSON, ETag, Last-Modified, bounded cache headers and nosniff. Conditional
GET can return 304. CORS supports only the fixed common endpoint and fixed GET /
OPTIONS methods and conditional request headers, without credentials or arbitrary
header reflection. Unknown paths/queries return 404; POST returns 405. `/healthz`
is a simple process health route, not evidence that sources are fresh.

The service does not log client IPs, referrers, user agents or access events. A
hosting provider may still process transport metadata; the deployment review must
set suitable operational log retention and must not claim network anonymity.
The local server caps concurrent handlers at 32, request headers at 32 KiB before
full parsing and request socket time at ten seconds. Storage polling is shared across requests and bounded to once per 15
seconds. On a storage read failure, an existing cached generation keeps its
original dates; a new service without a snapshot returns 503.

## Run and verify locally

From the repository root, create a virtual environment outside source and install
`backend/requirements.txt`, then run:

```sh
python3 -m venv work/live-content/venv
source work/live-content/venv/bin/activate
python -m pip install -r backend/requirements.txt
PYTHONPATH=backend python -m unittest discover -s backend/tests -v
PYTHONPATH=backend python -m wingman_content registry
PYTHONPATH=backend python -m wingman_content ingest --store work/live-content/store
PYTHONPATH=backend python -m wingman_content serve --store work/live-content/store --port 8891
```

Local integration uses the shared endpoint
`http://127.0.0.1:8891/v1/snapshot.json`. Native developer builds can opt into this
loopback endpoint. A shared-service release requires a reviewed HTTPS endpoint;
normal native direct-RSS releases need no define or service account.
Local operation does not require a cloud account. Do not alter persisted next
refresh times merely to demonstrate an additional network request.

Deterministic tests cover malformed XML, entities/DTD, quota/timeout/backoff,
conditional requests, gzip/wire limits, private/mixed DNS and rebinding,
unapproved/downgrade redirects, rights/promotion holds, pre-truncation review,
author preservation, missing publication dates, URL dedup, finite limits,
parser-upgrade revalidation, source removal, item/tombstone revocation, offline
expiry, atomic replacement failure, registry equivalence, baseline integrity and
CORS/common read-only service behavior. Actual ingestion runs and app acceptance
are recorded in `LIVE_CONTENT_ACCEPTANCE.md`; synthetic unit fixtures are never
presented as live source data.

### Historical September 12 backend acceptance

The earlier local backend suite passed 63 deterministic tests. Three actual CLI
passes were recorded: 00:40:31 UTC initial network ingestion (43 items), 00:47:20
UTC scheduling pass (all sources not due; no publisher requests), and 01:10:50
UTC final snapshot after the next permitted network ingestion (48 items, 52,486
bytes). These times are on 12 September 2026 UTC (11 September locally). Both
network passes received HTTP 200 from all three publishers; the final pass
intentionally omitted validators to reparse the updated normalizer. Conditional
304 ingestion behavior was exercised deterministically, and real GET service
conditional requests returned 304 without changing the stored generation.

The final snapshot contains NASA 10 / NOAA 8 / USGS 30 items, 44 supplied author
credits, and no missing publication dates in this particular live sample. Its
topics are science 48 / environment 38 / technology 3 (topics overlap). Two NOAA
records remain held for unreviewed paths: the leadership profile at
`/our-people/leadership/anita-vanek` and the Hollings scholarship item under
`/office-education/hollings-scholarship/news/`. Their presence in an official feed
did not automatically widen the reviewed article path scope. Detailed local run
reports are in `work/live-content/ingestion-run-1.json`,
`ingestion-run-2.json`, `ingestion-run-3-due.json` and
`ingestion-final-evidence.json`.

## Optional cloud operation

`backend/Dockerfile`, `backend/deploy/cloud-run-service.yaml`,
`cloud-run-job.yaml` and `scheduler.json` describe a small read service, a separate
authenticated ingestion job every 30 minutes and private storage. The reader
identity can read the object; the writer can replace it; Scheduler can invoke
only the job. No client can invoke ingestion or access the bucket. Cloud Storage
SDK calls disable automatic retries and have explicit per-operation timeouts.

`backend/deploy/README.md` contains reviewable operator commands and IAM/storage
choices. All project names remain placeholders for a **new dedicated project**.
Do not use the unrelated existing/default cloud projects. No deployment, project
creation, API enablement, public endpoint publication or billing attachment was
performed. Deployment and cloud IAM behavior remain unverified against real
infrastructure. The service/job have instance, concurrency and execution bounds;
budget alerts and instance caps are not hard spending caps. See
`CONTENT_OPERATING_COSTS.md` for the cost model and remaining approval boundary.

Implementation references: [Python HTTPSConnection](https://docs.python.org/3/library/http.client.html),
[defusedxml protections](https://pypi.org/project/defusedxml/),
[Google Cloud Storage Python SDK](https://pypi.org/project/google-cloud-storage/),
and [Cloud Run Jobs scheduling](https://docs.cloud.google.com/run/docs/execute/jobs-on-schedule).
