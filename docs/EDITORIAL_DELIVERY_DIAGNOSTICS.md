# Editorial delivery diagnostics

The app's developer diagnostics view reports local display counts separately
from provider supply. The Python service never receives source hides, selected
topics, reading-list activity, browsing history or reader identifiers. Requests
for an existing common snapshot or approved media never run ingestion.

Read a bounded JSON report without fetching a publisher:

```sh
PYTHONPATH=backend python -m wingman_content diagnostics \
  --store work/live-content/store --output work/live-content/diagnostics.json
```

Omit `--output` to print the report. The store and config are explicit inputs;
this command does not reset checkpoints, update snapshots, create credentials,
deploy a service or add scheduled jobs. Its `registryDigest` hashes the UTF-8
bytes of the generated app registry, including indentation and the final newline.

Each source's diagnostics report configured/enabled state; due, deferred,
requested and fetched flags; parsed entries, text eligibility, topic matches,
image permission, rejected entries and fixed reason counts. Native's existing
bounded scheduler can defer sources; Python's scheduled ingestion has no
per-reader queue and reports `deferred=false`.

`checkedAt` identifies the latest scheduler check. `attemptedAt` identifies the
last network attempt. `lastSuccessAt` identifies the last successful response,
including conditional revalidation. `countedAt` identifies the successful parse
behind the article counts and is unchanged by a 304. `nextDueAt` preserves the
publisher's cadence/Retry-After. `newestPublicationAt` is an actual supplied
publication date; fetching, revalidating or saving cannot make a story newer.
Some pre-repair stores have no exact parse diagnostics. The report marks those
as `not-configured` / `not-yet-checked` rather than inventing a network check;
their retained item counts remain visible as existing cached supply.

Outcomes distinguish `fresh`, `empty`, `content-held`, `not-modified`, `not-due`,
`deferred`, `publisher-hold`, `revoked`, `cache-prohibited`, `transport-failure`
and `parse-failure`. A parser failure can correctly have HTTP 200 and
`fetched=true`; it still has no new accepted parse. A not-due check does not
become a connection failure. `lastAttemptOutcome` and `lastError` retain the
previous attempt's result separately. Counts after a failure describe the last
good parse, not invented fresh results.

The local report aggregates configured endpoint counts for each category and
counts distinct editorial publisher IDs separately from feed URLs. Parse stages
sum the relevant source feeds; they are not disjoint article totals. The
`serverEligible` result counts current, deduplicated editorial items in that
category. `imageLoaded` / `imageCards` require currently retained, decoded media;
metadata containing an image URL is insufficient. `textFallbacks` counts
independent publisher-link stories without those bytes. NewsUSA is explicitly
excluded from editorial acceptance totals and has a separate
`completeArticlePendingImage` count: its full-article/photo contract is unchanged.
Bundled individually reviewed app photos are outside the shared media count.
The server reports visibility as `not-measured-on-server`; it does not infer
the effects of user preferences or private mode. The app adds actual visible
image/text counts locally.

`/healthz` reports process liveness with separate snapshot availability/date
fields. `/readyz` returns 200 only while an existing snapshot is fresh and 503
for missing or stale ingestion. Read-only delivery can still serve individually
unexpired cached articles with their original dates when readiness is stale.
Neither route performs an upstream request.

Optional article metadata does not grant or revoke the title. Missing optional
bylines/logos remain optional; `requiresAttribution=true` is still enforced.
An overlong optional summary from a source requiring unchanged text is omitted
and counted as `excerpt-omitted-size-limit`, without rewriting its words or
dropping its independently permitted title/link. Missing title/link entries are
reported individually; malformed XML documents still fail closed. Actual
rights/policy holds and explicit publisher tombstones retain revocation behavior.
Ordinary HTML navigation/footer elements are excluded from the displayed
article summary; safety checks still inspect the actual story and protected
destination. This is not a blanket approval of the publisher's whole website.

Transient no-store/private response instructions evict shared text and validators
without minting permanent article revocations. Refresh backoff and publisher
holds remain in place; a later permitted response can restore the same stable
article ID. Existing explicit policy/withdrawal revocations remain in force.
Shared media obeys its separate maximum age and permission rules. NewsUSA
photographs stay native/transient and never enter shared durable storage.

The backend remains a tested local service until an authorized production HTTPS
endpoint is configured/deployed using the existing deployment path. Localhost
evidence is not production web delivery. Successful transport or compact text
fallback does not establish broad publisher/photo licensing, image-classifier
coverage, or satisfaction of the Sports/Entertainment live inventory targets.
