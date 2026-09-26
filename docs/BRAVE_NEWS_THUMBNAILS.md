# Transient thumbnails in explicit News Search

September 26, 2026. The owner requested images alongside explicit News search
results. This document records the implementation and live image verification.

## Scope and source

Only an eligible result from an explicitly submitted **normal-context News
search** may receive a thumbnail. Brave already returns an optional `thumbnail`
object, whose `src` is the served image URL and whose `original` is optional.
Wingman accepts only returned `src` URLs on exact HTTPS `imgs.search.brave.com`;
it does not guess URLs or use the publisher's original image. Missing, invalid,
expired or failed imagery leaves the attributed text result and protected link
usable. Private and managed contexts remain text-only, subject to their existing
search availability restrictions.

The [official News schema](https://api-dashboard.search.brave.com/api-reference/news/news_search/get)
defines these fields, and [Brave's official News example](https://raw.githubusercontent.com/brave/brave-search-skills/main/skills/news-search/SKILL.md)
uses that thumbnail host. News thumbnail dimensions and lifetime are not
promised by the schema. The 500-pixel description in Brave's separate Image
Search documentation is not a News-image size guarantee.

## Delivery and retention

1. The normal News response supplies the image reference. The backend retains
   its lookup only in transient memory, limited to 128 tokens per process, and
   gives the client an opaque 64-character hexadecimal token, expiring after
   five minutes. An idle timer physically removes expired entries; release or
   process shutdown also removes them. Fetching consumes the source URL before
   network I/O and retains only the consumed marker until expiry or release.
2. A visible client card lazily sends that token by POST to Wingman's gateway.
   At most one CDN fetch is permitted per token, including failed attempts.
   The gateway accepts a bounded static JPEG, PNG or WebP, strips metadata and
   emits a PNG of at most 256 × 144 pixels and 128 KiB. Aspect ratio is preserved;
   very narrow images receive padding so both dimensions are at least 16 pixels.
   Client and backend each permit at most two concurrent image fetches within
   their respective search-controller and gateway-process scopes. A malformed,
   unavailable or capacity-limited image does not fail the organic search.
3. Successful image bytes may remain in the originating normal-search session's
   memory for Back navigation, limited to 2 MiB per search controller, until the
   five-minute expiry or clearing. Both client and server also check monotonic
   elapsed-time deadlines, so moving the wall clock backward cannot extend
   retention. Bytes do not enter disk storage, saved items, offline previews or
   a service-worker cache. The server has no image-byte cache.
4. Expiry or clearing does not trigger another search, a token refresh, a
   publisher fallback or an automatic retry. Existing text results remain
   independent of image availability.

Tokens belong to one gateway process. The production image uses one worker with
four threads, and the reviewed canary configuration permits at most one instance.
Routing must be reviewed before increasing either process or instance count;
this implementation does not persist or replicate token mappings. A restart or
request routed to another process loses optional imagery while preserving text
results, and the client never repeats the paid search to recover an image. See
the [deployment boundary](../backend/deploy/SEARCH_RELEASE.md).

Thumbnail delivery makes a media request to Brave's image CDN. It makes **no
additional Web, News or Image Search API call** and does not reserve another
search attempt. CDN traffic and gateway processing are distinct from Search API
accounting; this is not a claim that all infrastructure bandwidth is free.

The browser/app contacts Wingman's gateway rather than the publisher image
host. Consumer cookies, authorization, referrers and the Brave subscription token
are not forwarded to the image CDN. The provider key stays at the existing
server-side search boundary. No direct publisher/original-image fallback, Open
Graph scraping, stock substitution or generated news artwork is introduced.
Token or image failure must not weaken destination policy, private-state
isolation or stale-callback rejection. Query, token and image URLs must not enter
request logs or durable consumer records.

## Rights boundary

[Brave's current terms](https://api-dashboard.search.brave.com/terms-of-service)
§3 permit use of Search Results with customer applications and distinguish
transient operational storage from broader retention. Our scoped interpretation
is that displaying a returned thumbnail transiently beside the requested News
result fits that ordinary result-display use. The owner's instruction authorizes
this feature; it is not a blanket publisher-image license or a legal guarantee.
Third-party rights remain relevant under §9.

This does not enable shared Home/Discover ingestion, stored image libraries,
CDN fan-out, offline image archives or shared or retained production media
rights. The `cached_news` and `remote_media` entries in `backend/config/brave_rights.json`
remain unchanged. Retaining or redistributing results beyond transient operation
needs the applicable rights; Brave's [API FAQ](https://brave.com/search/api/)
separately identifies storage-rights plans. Existing approved packaged story
photos retain their own provenance and permissions.

## Verification evidence

Offline verification on September 26, 2026 passed:

- Full backend suite: 413 tests in 45.531 seconds,
  `work/brave-live-evidence/thumbnail-backend-final.log`.
- Full Flutter suite: 1,117 passed, six existing optional skips, in 1 minute
  28 seconds, `work/brave-live-evidence/thumbnail-flutter-full.log`.
- Full Flutter analysis: no issues, 5.2 seconds,
  `work/brave-live-evidence/thumbnail-flutter-analyze.log`.

The fixture tests cover source validation, metadata stripping and raster limits,
single-use fetches, malformed/failed images, concurrency and capacity bounds,
private/managed suppression, viewport/lifecycle checks, Back reuse, clearing,
expiry despite clock rollback, and unchanged Search API attempt counts for image
fetch/release. They do not call the live provider or establish live image rights.

The Android arm64 debug APK and iOS Simulator app built successfully and were
installed over the ordinary apps on the dedicated Wingman verification devices,
preserving their data. Live image rendering was checked in the rebuilt web app
at `http://127.0.0.1:8898/`; native image rendering was not separately exercised.

Live verification used the existing grant and an automated gateway actor. One
explicit Web submission followed by one News selection increased the durable
Search attempt count from 9 to 11. The News response registered ten thumbnails;
only two visible cards initially fetched images, both delivered and visually
confirmed. Scrolling loaded two more images. Returning to the original cards
reused their pixels: the CDN attempt/delivery counts stayed at four and the
durable Search count stayed at eleven. No failed thumbnails or unknown Search
outcomes occurred in this live check. Missing/failed images, Back navigation,
private suppression, cancellation and expiry are covered by the fixture tests.

Local evidence is in `work/brave-live-evidence/thumbnail-live-before.json`,
`thumbnail-live-visible.json`, `thumbnail-live-scroll.json` and
`thumbnail-live-return.json`; screenshots are delivered with the task report,
not stored in the repository. These records contain aggregate counters only,
with no API key, query, thumbnail token or upstream image URL. The grant now has
89 total attempts and nine automated attempts remaining, with $0.055 reserved
and $0.445 remaining from its existing $0.50 ceiling. This is conservative
accounting, not a reconciled provider invoice. Its original expiry and ledger
are unchanged. The app is returned to manual-submission mode after verification.

Related: [data flow and retention](DATA_FLOW_AND_RETENTION.md),
[shared Brave News rights](BRAVE_NEWS_RIGHTS_AND_DELIVERY.md), and
[local live activation](BRAVE_LIVE_ACTIVATION.md).
