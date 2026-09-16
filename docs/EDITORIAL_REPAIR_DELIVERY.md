# Wingman editorial repair delivery — September 15–16, 2026

**A. Delivery defect:** repaired in the code and automated regressions. Final build **0.15.1 (18)** is compiled for Android, iOS simulator and web. Android and iOS simulator installations were updated in place without deleting data. The remaining acceptance step is actual on-screen verification of this new build: the Mac locked during the task and the UI-control tool could not unlock it. An unlock request is pending. No physical iPhone was connected.

**B. Editorial/photo targets:** **not met**. At the fixed live observation clock (September 15, 8:18 p.m. Central), Sports has **0/5** relevant stories within 72 hours, **0/2** publishers supplying recent stories and **0/3** approved photos. Entertainment has **1/5**, **1/2** and **0/3**. Each has one configured publisher, Global Voices. Their current reporting is international; this does not deliver the requested U.S.-based mix.

## Delivered code and build

- Branch: `codex/editorial-delivery-repair`, based on `712cfd5fdf94b6b7620fb6b3b7978f40310b8a78`.
- Exact compiled runtime: `0460434ec537d099e72bdff8192902a3da8c447a`. Subsequent commits contain tests and delivery evidence only. Embedded commit strings were checked inside the Android/iOS kernel artifacts and the web bundle.
- Version: **0.15.1 (18)**. Corrected the pre-existing UI display-version mismatch along with the build bump.
- Generated registry SHA-256: `c8c346c8ddf9357203fba7971f6ac008b815da9648b4eb3f577f1d7408f34806`.
- Native mode: existing direct RSS provider, no shared endpoint. Installed on Android `emulator-5554` and iPhone Air / iOS 26.3 simulator. Android used a 93 MiB ARM64-only package with ordinary versionCode 18 after its storage limit rejected the 187 MiB universal package; no data or caches were deleted. These are simulated devices, not hardware tests.
- Web mode: existing shared snapshot provider, debug-only localhost endpoint `http://127.0.0.1:8891/v1/snapshot.json`. It serves preserved common content and permitted media; reads do not fetch publishers. This is **not production deployment**. Release builds continue to reject local HTTP endpoints.
- No merge into main, TestFlight upload, paid service or new production hosting was performed for this scoped repair.

## Corrected causes

The installed simulator baseline was **0.14.0 (16)**, with the same original image-gated registry as the inspected checkout. Both Sports and Entertainment visibly showed “Refresh unavailable” and “No stories with available images.” This was observed through the simulator UI before the Mac locked; it was not inferred from source code or assumed to be TestFlight build17.

Ordinary permitted headlines now remain as compact text cards while an optional photo is absent, pending, rejected or returns 404. Independent excerpt permissions remove only the optional excerpt. Article IDs, pagination and scroll are stable while images load. Publisher identity uses the existing neutral initials when no approved logo is available.

NewsUSA retains its separate Sponsored label and complete associated article/photo contract. Its reader removes the body when required photo bytes expire, without a new network request. No-store image bytes stay transient. Science X retains its exact 90×90 approved thumbnail URLs. No substitute, stock or unauthorized photos were introduced.

Native/backend normalization now distinguishes a malformed entry from malformed XML, chooses the article link rather than atom:self, omits overlong optional descriptions/bylines, and checks bounded actual story metadata without unrelated navigation/footer content. Standard gzip/deflate decoding has independent wire/XML limits and preserves DNS/public-address checks, TLS verification and redirect validation. Validation failures retain publisher pacing headers.

The existing 12-endpoint/3-lane/45-second scheduler retains its persisted cursor and checkpoints. Deferred sources receive a later scheduled pass without repeated manual Refresh. Failed images have bounded attempts and delayed retries. Temporary cache restrictions no longer become permanent legal withdrawals. Explicit withdrawals still survive restarts and fresh reappearance.

Source/category diagnostics expose the bounded configured→enabled→due/deferred→requested→fetched→parsed→text-eligible→topic-matched→image-permitted→image-loaded→visible pipeline. Image cards and text fallbacks are separate. Common diagnostics exclude reader preferences, browsing history and reading-list activity. The preview redacts itself when the owning context becomes inactive. Messages distinguish source gaps, storage restrictions, scheduling, publisher/parser failures and local choices. Publisher success time is separate from the last delivery attempt and article publication dates.

## Validation

- Full Flutter suite: **985 passed, 6 opt-in tests skipped**. Targeted category-health suite: **4 passed**; storage/snapshot recovery suite: **7 passed**; image retry/expiry suite: **4 passed**.
- Flutter analysis: **no issues found**.
- Python backend: **126 passed**.
- Final Android debug APK, iOS simulator debug app and debug web build: **passed**; exact embedded runtime commit verified.
- Widget tests cover actual protected link callbacks, return scroll position, private/inactive cancellation, missing/pending/404 images, denied text, full-article contracts, partial/empty/deferred states, conditional responses, rate limits, malformed entries, and 200% text/semantics in both themes. Synthetic tests establish behavior, not publisher supply.
- Baseline simulator UI: both empty-category messages reproduced. Final simulator/emulator/browser UI: **pending Mac unlock**. No claim of post-repair hardware or on-screen acceptance is made.
- Real native host transport: **17/17 source endpoints returned HTTP 200**, in paced batches of 12 and 5 at 01:45–01:46 UTC. 16 responses used gzip and 1 were uncompressed; decoding, DNS validation and TLS verification succeeded. The persisted cursor scheduled the five deferred endpoints; the controller's automatic follow-up is separately covered by a regression test using the real provider and 17 endpoints. Both host passes had **no global warning**. Final native parsing produced **171 editorial + 15 sponsored** normalized records; this is not a visible-card count and no image request was made in that probe. Sports remained 3 text-eligible stories and Entertainment 1, with no permitted dynamic photos. These are macOS host transport results, **not iPhone execution**. Counts differ slightly from the earlier controlled 172-record sample because the live observations occurred at different times.

## Captured NOAA correction and historical limits

The final native parser also repairs an actual NOAA entry whose unused photo caption said “Courtesy of Northern Gulf Institute.” For sources that prohibit photos and allow excerpt normalization, a caption inside a figure containing an image no longer determines article-text rights. Full policy checks still inspect the original bounded story metadata; explicit article rights/copyright fields remain authoritative. The original feed entry is preserved as a regression fixture and its article becomes text-eligible without using the photo.

The earlier live host snapshot already recorded article ID `390bd35971fb6ddfbaf20c2e3addca58` as revoked. It remains held in that historical ledger: older tombstones lack enough per-item reason evidence for a safe general migration that preserves genuine withdrawals. Device ledgers have not been inspected, so no claim is made that this particular historical hold exists or was removed on the installed apps. No cache, checkpoint or user data was reset. The final 65-test native regression run validates this caption repair using the captured response; it does not change the previously observed 171-editorial host receipt.

## Before/after supply and remaining requirements

The [all-category before/after table](EDITORIAL_REPAIR_SUPPLY_EVIDENCE.md) uses identical preserved live inputs and previously decoded photos on both sides. Displayable common editorial cards increase **24→172**: Sports **0→3**, Entertainment **0→1**. The Sports entries are older than 72hours and are not counted toward acceptance. The table records every requested category plus Environment, publisher operators, raw/eligible counts, images, text fallbacks, actual newest dates and blockers. It also distinguishes a 14-day lifestyle freshness window from the 30-day retention ceiling.

**No new publisher was cleared or activated.** The 17 existing sources remain: 16 editorial endpoints across 5 independent operators, plus sponsored NewsUSA. The [focused rights review](EDITORIAL_SUPPLY_REVIEW.md) documents why FanSided, Yahoo Sports and PMC/Deadline/Variety still require commercial-use permission; it also records bounded alternatives. Public RSS and photograph URLs are not treated as permission. The missing broad U.S. mix requires a publisher grant or other genuinely eligible current source; changing browser engines cannot supply those rights.

For production web delivery, Wingman still needs an approved HTTPS host/storage deployment for the existing Python service, ingestion scheduling, and a configured `WINGMAN_FEED_URL`. No production endpoint was present. Providing that configuration/authorization is separate from the native repair; the localhost result does not satisfy production delivery.

The [verification metadata](evidence/editorial-repair.json) records build identity, test totals, actual native transport receipts and all-category measurements. Detailed build receipts, baseline evidence, comparison JSON and test logs are retained locally under `work/editorial-repair/` and in the task’s `outputs/editorial-repair/` folder. Publisher check/publication/media-expiry times have not been extended to make the evidence appear current.
