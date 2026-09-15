# Feed candidates and enriched cards

Implemented on `codex/feed-candidate-integration`, starting from
`af3e90d458b73bea7aaa502c951b6904175f6ecb`. This extends the existing Flutter
Home/Discover surfaces on Android, iOS and the web companion. Browser engines,
DuckDuckGo settings and mandatory destination protection remain unchanged.

Cards now show the original headline, a visible publisher-supplied excerpt
(up to three visual lines), publisher identity, category and publication time.
Exact 90×90 Science X thumbnails use the compact layout. Larger individually
reviewed images retain their aspect ratio. Source/Save/Share/Hide/About actions
remain available. Native article Back restores Discover’s selected category and
scroll position, using tab-owned memory that private/handoff transitions invalidate.
Web story links open a separate host-browser tab with no opener or referrer,
preserving the original card list. Ordinary stories open their original outbound URL. Canonical
URLs retain article/image identity. Unknown publication dates remain unknown.

The reusable branding component accepts only reviewed bundled raster assets.
No official publisher logos were approved during this change: publishers show a
neutral initials badge and their readable name. Initials are not official logos.
There are no remote favicon, logo-lookup, analytics or AI-summary calls.

## Candidate inventory and decisions

`backend/candidate_data/wingman_feed_candidates.csv` preserves the supplied input.
The importer uses Python's CSV parser, preserves every original field/record ID,
explicitly parses booleans, and stores publishers, endpoints and category
memberships separately. The source data contains **217 rows, 201 literal publisher
labels and 216 literal feed URLs**. Both supplied activation columns remain false.
Reviews are separate from imports and are not erased by re-importing.

`backend/candidate_data/reports/validation-report.json` and `.md` account for every
record. Availability, U.S. qualification, traffic, rights, policy, branding and
production state are independent fields. The first complete validation found
150 working/redirected endpoints, 24 stale and 42 requiring review or failing a
bounded access/format/network check. A 403 is access-restricted, not declared dead.
One insecure HTTP URL is rejected before a request. No login, CAPTCHA, paywall or
anti-bot restriction was bypassed.

25 candidate records received substantive rights reviews; 192 remain explicitly
unreviewed. A public RSS response or an image URL is not a commercial reuse grant.
There is **one new reviewed production source**, NASA Photojournal, with only two
individually approved image/article associations. The existing 16 sources are
preserved and reported separately, never counted as newly imported publishers.

NASA Photojournal currently emits two raw ampersands in one channel-level Atom
self-link. Its original and official alternate probe remain classified malformed.
The `nasa-photojournal-self-link-v1` compatibility adapter escapes only the exact
known self-link before the first item, for the pinned source ID and exact URL.
DTD/entity rejection and strict XML validation still apply; no article text or
other malformed feed is repaired. Promotion separately reproduces strict parsing
from retained raw bytes and checks original/normalized SHA-256 values. This is a
reviewed compatibility integration, not a claim that NASA's upstream XML is clean.

The two actual antenna photos were supplied as 1200-pixel variants on their exact
NASA pages, credited NASA/JPL-Caltech and independently checked for dimensions,
MIME and bytes. Their publisher dates are **25 August 2026**, not the later page
update date. They leave the live feed after its 30-day publication window. The
15 October rights review date is an operator re-review due date, not expiration
of NASA's underlying grant. New NASA images are held until individually reviewed.
NASA/JPL trademarks are not approved by those image terms.

## Source of truth and permitted display

`backend/sources.json` is the reviewed configuration. Generate the exact pinned
client registry with:

```sh
PYTHONPATH=backend python -m wingman_content registry
```

The generator now preserves image policies, original-text rules, display mode,
branding and compatibility metadata, and `requireStoryImages`. A parity test
prevents regeneration from dropping the four newer NewsUSA/Science X sources.
Source and preference limits support 256 reviewed entries; candidate import does
not automatically place any of the 217 rows in the runtime registry.

Display modes are explicit: `publisher-link` and `sponsored-syndication`.
NewsUSA remains a Sponsored feature with the complete supplied inert article,
byline/links, attribution and protected original link. Its excerpt permission is
false; it is not converted to a generic short-excerpt/full-photo card. Science X
uses only the exact permitted 90×90 feed thumbnails, never guessed larger CDN
variants or Open Graph scraping. The existing four bundled NASA/USGS/Global Voices
associations remain separate and intact.

Publisher XML is namespace-aware and bounded. Supplied descriptions/summaries
become inert plain text without requests. Full bounded supplied material is
reviewed before display truncation. Headlines over 500 characters are held rather
than rewritten. Preserve-text sources with over-limit summaries are held. No
summary is generated from a headline or copied from an ordinary article body.

Missing, failed, unapproved or unavailable photos exclude a story before feed
pagination. Saved text links remain supported. New decoded images append without
reshuffling visible cards. Cached eligible content can render before refreshes
finish. Travel has its own stable category; Environment and saved preferences
remain intact. Sparse categories are reported rather than filled with placeholders.

## Delivery and resource limits

Native RSS refreshes attempt at most 12 distinct due endpoints, on three lanes
within the existing 45-second batch window. A persisted cursor advances only past
actually started endpoints, so deferred sources remain eligible for later turns.
Duplicate exact endpoints share a response; unrelated publishers retain separate
normalization/rights/topic decisions. Every alias's pacing hold is honored. The
1800-second minimum cadence is not shortened. Scheduling does not receive the
user's interests, reading list, browsing history or current scroll position.

The optional Python backend serves one common nonpersonalized snapshot. Ingestion
is an operator command; HTTP reads never initiate publisher requests. Media is
addressed only as `/v1/media/<sha256-image-identity>`, never by an arbitrary URL
parameter. Approved media destinations use the existing public-DNS-pinned TLS
transport, validate every redirect, and decode JPEG/PNG/WebP with byte/pixel/frame
limits. Duplicate cache headers are combined conservatively and ambiguous
singleton headers rejected.

Flutter web cannot read encoded `ImageDescriptor` dimensions. A bounded
JPEG/PNG/WebP header parser checks dimensions before decoding, then every platform
checks the decoded frame dimensions and rejects animation. The web path is tested
with real raster decoding in Chrome, not only host widget fixtures.

Shared media ingestion admits at most 24 attempts per pass, using a persistent
cursor and a 1 MiB decoded-file-byte budget inside the existing 4 MiB atomic
private bundle. Each image is at most 1 MiB, at most 2048 pixels per dimension and
4 megapixels. Shared storage requires an explicit usable cache lifetime and
respects Age/no-store/private/no-cache. Service GETs serve only images referenced
by current, unrevoked, unexpired snapshot items. Private state, diagnostics and
media bytes are not embedded in public JSON.

Served media has a maximum 30-minute cache lifetime, further limited by the
remaining publisher response lifetime, article expiry and publication window.
Current snapshot revocations remove cards and previews on refresh; this does not
promise instantaneous remote withdrawal while an allowed cache remains valid.

NewsUSA photos are excluded from the durable shared-media path. Native clients
retain the existing fresh transient memory-only handling of no-store responses,
including buffer and decoded-image eviction on context changes/disposal. The web
companion consequently omits NewsUSA image cards when no permitted shared image
is available; it does not persist those photos to force parity.

Web clients fetch only the configured common service and permitted media path.
They do not request hundreds of publisher feeds or use a public CORS proxy. The
host browser controls its own network stack and any page opened after navigation;
Wingman does not claim it can enforce native browser protection there.

**Production web delivery remains blocked on an explicitly configured/deployed
shared endpoint.** This task creates no paid infrastructure, cloud service, IAM
change or production deployment. Local serving is supported and tested:

```sh
PYTHONPATH=backend python -m wingman_content ingest --store work/shared-content
PYTHONPATH=backend python -m wingman_content serve --store work/shared-content --port 8891
flutter build web --debug --dart-define=WINGMAN_FEED_ALLOW_LOCAL=true \
  --dart-define=WINGMAN_FEED_URL=http://127.0.0.1:8891/v1/snapshot.json
```

Local endpoints are only enabled in non-release builds with the explicit define.
For production use the existing approved HTTPS `/v1/snapshot.json` configuration.
No optional hostname in a runtime payload can grant new publisher/image rights.

## Operations, validation and rollback

See `backend/candidate_data/README.md` for import, bounded resumable validation,
report and reviewed-promotion commands. Reuse the validation checkpoint to preserve
Retry-After and source pacing; do not reset it to force repeated probes.

Deterministic tests use synthetic/permitted fixtures. Real network checks and
publisher-data UI captures are opt-in and reported separately. Exact commands,
results, native/web UI observations and coverage are recorded in the delivery
report; successful builds alone do not prove navigation or store delivery.

Rollback the scoped feature commit with `git revert`, regenerate the registry and
rebuild. Do not reset the user's checkout, remove app data, clear saves/preferences
or delete prior ingestion checkpoints. To withdraw a source, set its reviewed
`enabled` false (or use the existing explicit revocation fields), regenerate and
ship the registry, and ingest a new shared snapshot. Expired/revoked media is no
longer served; source removal does not delete the user's separately saved links.
No store upload is part of this feature branch.
