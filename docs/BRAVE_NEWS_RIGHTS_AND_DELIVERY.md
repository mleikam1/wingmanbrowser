# Wingman News — shared delivery and rights

September 26, 2026. Shared Brave news is implemented and fixture-tested, with
its committed source disabled and shared caching/media rights unapproved. No
live shared-Brave ingestion, shared-media grant, production scheduler or
shared-news paid allowance has been verified. Explicit query-result acceptance
is recorded separately in [local live activation](BRAVE_LIVE_ACTIVATION.md).
Existing approved RSS, Currents and separately authorized NewsUSA content remain
available under their existing contracts.

## Two distinct entry points

Explicit News Search accepts an intentional submitted query through Wingman's
search gateway and returns a transient protected DTO. It does not store that
query, silently fetch another page or populate a shared feed. The owner has now
authorized [transient thumbnails for explicit normal News Search](BRAVE_NEWS_THUMBNAILS.md):
only returned Brave thumbnail URLs, fetched lazily through Wingman using an
opaque five-minute token and displayed from session memory. This media request
makes no second Search API call. Private/managed contexts remain text-only;
image-byte persistence and publisher-original fallback remain excluded. Live
thumbnail verification is recorded in that separate feature record.

`BraveNewsProvider` supplies the existing `NewsProvider`/`CompositeNewsProvider`
and Home/Discover snapshot path. It accepts reviewed source/prior-state/time,
never reader queries, identifiers, history or interests. Every reader of the
configured English/US shared source sees the same editorial supply; topic
ordering, follows and hides remain local. Private, handoff, inactive and
Updates-off states do not fetch and reject late callbacks. Student/managed
surfaces retain their existing restricted entry points.

## Fixed editorial mapping and schedule

| Existing canonical category | Reviewed public query |
| --- | --- |
| `general` | public interest news reporting |
| `sport` | sports results reporting |
| `arts_culture_entertainment` | arts culture museums reporting |
| `science_technology` | science technology research news |
| `economy_business_finance` | economy business reporting |
| `education` | education learning research news |
| `environment` | environment conservation research news |
| `health` | public health medical research news |

The adapter uses the actual protected Brave News endpoint with explicit strict
filtering, count=20, offset=0 and no web-only parameters. It does not invent a
headlines endpoint or a Brave category parameter. Existing canonical/derived
topic IDs and user selections are preserved.

At most one current editorial slot runs per 15-minute writer tick; each slot
has a two-hour minimum interval. Missed phases are skipped without a catch-up
burst. `reserve_scheduled()` commits the slot's next due time atomically with
the paid news reservation in the independent local/GCS budget ledger. Restart,
content-cache deletion and failed responses cannot reset that due time. The
two-request smoke allowance explicitly rejects scheduled use. Global, news
and web ceilings remain independent limits; news cannot consume the web cap.

Eight feeds every two hours would mean at most 96 calls/day or 2,880 per 30 days.
At the reviewed $5/1,000 list rate, successful calls at that cadence would cost
$14.40 before credits/account adjustments. This is scheduling arithmetic, not
approval to spend or a quote for storage/image/hosting rights. Datastore and
other delivery costs remain unknown until measured/reconciled.

The existing content store owns writer locking/fencing before refresh and
publication. The adapter composes that guard with current shared-rights checks
and the production runtime's live-search validation before every reservation.
The grant is checked again after the response before content can be retained.
The public reader has no provider or secret loader. A test performs real
ingestion with an injected provider transport, then 10,000 `SnapshotReader`
reads: exactly one provider fixture call occurs.

## Rights, provenance and expiry

Activation requires all of these independent records to agree:

- `backend/config/brave_rights.json`: approved `cached_news` gate/evidence,
  approved shared use/CDN fan-out and an explicit 3,600–86,400 second storage
  duration.
- The reviewed `brave-news` source: enabled title permission, separate excerpt
  permission, matching grant reference and a lifetime no longer than the grant.
- The build-pinned app registry: the same source/grant/retention agreement and
  configured common snapshot transport. A JSON provider flag alone grants no
  destination authority.

The runtime config and content writer/reader must reference the same mounted
rights register. The content CLI rejects an alternate runtime rights path.
For the supplied Docker layout that common path is
`/app/backend/config/brave_rights.json`; locally it is
`backend/config/brave_rights.json`. Mount updates consistently across writer and
readers. Neither the CLI nor a successful token check creates permission.

Only original title, permitted short excerpt, publisher/domain identity,
canonical/original link, categories, attribution and bounded provenance enter
the shared snapshot. Distinct publisher assets/permissions are never merged.
Canonical URL deduplication merges membership only. Existing diversity logic
balances categories and publishers without bids or secret political ranking.

Brave `page_age` may mean publication **or modification**, so it is stored as
`pageDate`, not presented as a proven publication timestamp. `page_fetched` is
`providerFetchedAt`; Wingman's first observation is `discoveredAt`; its authorized
retrieval is `fetchedAt`. Unknown `publishedAt` remains null and the app displays
“Date unavailable.” Old/future metadata does not manufacture breaking news.
Repeated category discovery/republication keeps the original retrieval/expiry
of a retained representation. Reads and 304 responses never extend its grant.

This Brave shared release is text-only. Unlicensed thumbnail URLs are discarded
before content persistence; no image fetch, Open Graph scrape, guessed stock
art, generated news image or publisher logo partnership is introduced. Existing
individually approved sources retain their separate media controls. Broader
Brave image support in shared snapshots needs explicit article-associated rights
and another reviewed configuration change; a generic API token or remote-media
boolean is insufficient. The separately authorized transient search-thumbnail
path does not change these shared-source or production-media gates.

Rights revocation clears retained pools even before their next scheduled poll.
The reader rechecks current rights before returning an in-memory snapshot, and
Brave-bearing responses require revalidation. Client expiry timers remove
previews from durable local caches without a new request. Saved Brave items
contain only an explicit user's original link, not a permanent preview copy.
Contract approval must cover offline-cache expiry, object versions, soft deletion
and backups; the undeployed target's lifecycle policy remains an owner-controlled
release dependency. Operational budget records are never part of content cleanup.

## Cutover and rollback

The committed `brave-news` source is disabled. A future authorized source rollout
must update both backend configuration and generated app registry. The registry
can be generated locally without paid calls:

```sh
PYTHONPATH=backend work/brave-venv/bin/python -m wingman_content registry
```

The configuration's `primarySharedProvider` defaults to `currents`. Switching
that reviewed role to `brave` causes Currents to remain on standby with its
permitted cached records and preserved preferences; it is not polled in parallel
for the same role. A deployment must first satisfy the production runtime,
shared rights, secret-manager, independent spending and platform gates. The
writer accepts `--brave-runtime-config <approved-config-path>` and delays
constructing that provider until the common shared grant validates.

Rollback selects `currents`, closes the Brave cache gate and runs cleanup;
ordinary RSS/NewsUSA paths and user choices remain. Preserve cost ledgers,
initialization markers and user bookmarks. Never delete accounting, erase app
data or change protections to force a rollback. A revoked grant requires a
reviewed new authorization before restoring content.

## Verification

The backend news fixture suite covers missing key/rights, actual strict adapter
parameters, fixed public query selection, scheduled restart/cache loss/failure,
smoke isolation, runtime/writer guards, empty/malformed/old metadata, unknown
publication, image omission, original expiry/deduplication, excerpt/grant
revocation, revocation during a response, provider standby and 10,000 reader
calls without per-reader provider calls. Shared-ledger tests also verify atomic
scheduled slots across independently constructed workers.

Flutter tests cover pinned grant/shared-transport provenance, mismatched grants,
future date rejection, native RSS exclusion, link-only saves, finite feed,
preview expiry, no requests in excluded contexts and late private-transition
discard. Commands:

```sh
PYTHONPATH=backend work/brave-venv/bin/python -m unittest backend.tests.test_brave_news backend.tests.test_brave_shared_budget -v
flutter test test/live_content/brave_shared_test.dart test/live_content/currents_shared_test.dart
```

These are fixture and code-path results. They do not establish actual current
Brave content, an image license, deployed delivery, paid demand or earned revenue.
