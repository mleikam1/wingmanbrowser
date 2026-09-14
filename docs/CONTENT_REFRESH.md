# Content and presentation refresh

Version **0.14.0+16** replaces the four-photo-only feed experience with source-approved, article-associated images delivered with current publisher feeds. The browser engines and DuckDuckGo filtering settings are unchanged. The persistent Strict-search banner above results is removed; search privacy and protection details remain in settings and an expandable search explanation.

## Presentation

Home keeps the Wingman identity, mission, search and an accessible Protection action in a compact header. Live Discover cards appear before the offline library collections. Cards emphasize the unchanged headline, publisher, associated image and readable date. Save and article options remain available. Full timestamps, supplied excerpts and source terms are available through **About this story**.

The production registry requires a decoded, approved publisher image or an exact reviewed bundled photo before a story enters the visible feed, before pagination. These may be publisher photographs, illustrations or thumbnails; they are not represented as uniformly documentary photographs of current events. No stock/topic substitute is selected by Wingman. Stories whose images fail or exceed the limits are omitted from Discover. The initial image batch has an explicit loading state. After an offline restart, dynamic-image stories are unavailable until their photos can be requested again; legacy saved text links remain usable.

## Sources and commercial use

### Science X RSS

[Phys.org](https://phys.org/feeds/), [Tech Xplore](https://techxplore.com/feeds/) and [Medical Xpress](https://medicalxpress.com/feeds/) provide a specific free commercial RSS grant. Wingman preserves supplied headlines, links and publisher attribution. Only the exact small `media:thumbnail` supplied with that RSS item may be loaded. Larger article images, alternate CDN sizes, article bodies and Open Graph extraction are not authorized by this integration.

The published RSS permission refers to sites; treating native RSS cards as that same limited feed display is an interpretation, not a separately negotiated app license. Network-wide general terms otherwise reserve content rights. These feeds contain both U.S. and international reporting and sometimes illustrative imagery; do not advertise them as exclusively U.S. reporting or as current-event photography. The three sampled current feeds each supplied 30 items with 90×90 thumbnail metadata; three actual image responses were verified as 90×90 JPEGs.

### NewsUSA syndicated features

[NewsUSA's specific syndication terms](https://newsflow.newsusa.com/terms-of-syndication) grant free worldwide copying, distribution, publication and linking with attribution and no material changes. Supplied images must accompany their original complete articles. This is broader than access to an ordinary unlicensed RSS endpoint and has no noncommercial limitation in that grant.

Wingman treats this channel as **Sponsored feature** content. The original full article, byline, links, lists and footnotes are retained in an inert native reader, together with its supplied image and a protected link to the original publisher page. No paid API key or publisher account is used. Supplied pictures may be licensed stock used by the publisher; their permission is tied to that exact accompanying article, not a public-domain license or a license to reuse the photograph elsewhere.

Scripts, HTML execution and tracking-pixel requests are not part of the native reader. Promotional industries prohibited by Wingman's rules are excluded across the complete article, including when the copy calls itself research or health reporting. The sponsored source does not inherit the independent-reporting exception for restricted products. A source label and keyword checks are not a guarantee that every evolving article or photograph meets every content rule.

The existing NASA/USGS/Global Voices photographs retain their separate exact-article licenses and archive captions documented in [Story images](STORY_IMAGES.md). Additional sources must have their own approved feed and image contract.

## Delivery and privacy

Native Android and iOS use the existing public-DNS-pinned HTTPS transport. Approved media hosts and paths, MIME/signature checks, byte and decoded-pixel limits constrain image delivery. Image widgets receive checked bytes rather than arbitrary remote URLs. Image requests use a bounded common publisher batch, not the reader's selected topics, saves or browsing history. Image bytes are kept in memory; they are not a permanent offline-photo archive.

NewsUSA currently sends `no-cache, no-store, must-revalidate` for its photos. These responses are decoded for active display only and are not reusable cache entries or exported image fixtures. Refresh, context change and disposal clear those buffers; image widgets evict their decoded pixels when replaced or detached. A subsequent batch must request the image again. Cache-permitted Science X thumbnails have bounded memory reuse. Oversized or invalid image responses are rejected rather than replaced with unrelated artwork.

Publisher servers receive normal connection metadata, including IP addresses. Private browsing, inactive/handoff contexts, opt-out and source/article withdrawal must stop image work and prevent image access. Existing search and destination protection remain independent of feed permission.

No paid news API, image API, ad SDK or new cloud hosting service is introduced. Commercial content permission does not itself implement monetization, and mobile distribution, maintenance and connectivity can still have costs. Publisher availability, feed size and category coverage vary; the app does not claim an Opera-equivalent licensed publisher inventory or breaking-news coverage in every category.

## Verification

The actual September 14 UTC ingestion checked 16 fresh sources and retained 181 eligible text records. The image probe validated 84 Science X thumbnails. A separate image-only check over the accepted snapshot decoded 10 NewsUSA photos (717,700 bytes total); two responses exceeded the 1 MiB limit and were correctly rejected. No NewsUSA photo bytes were saved as reusable fixtures. These counts describe observed responses, not guaranteed daily supply or photo coverage in every category.

Network probes are opt-in and preserve publisher refresh checkpoints. Render captures use actual ingested content, checked reusable thumbnails and explicitly requested transient photos; they are UI evidence, separate from native browser navigation testing.

- Full host suite: **889 passed**, with five opt-in skips. Includes source permission, image validation, image-only pagination, cache withdrawal, sponsored-article parsing/reading, private-session isolation, protected search, large-text layout and existing browser behavior.
- Analyzer: **no issues found**.
- Real-content UI acceptance: **passed**. Five rendered screens cover Home, its preview, Discover and the complete sponsored reader. The final capture made one fresh NewsUSA photo request, saved no reusable transient photo bytes, and replayed only hash-verified Science X thumbnails. The images were visually reviewed.
- The focused real-data checks and receipts live under `work/content-refresh/`; publisher feed checkpoints remain under `work/rss-direct/`.

## Build delivery

- Android release APK: **73,174,213 bytes**. Installed successfully over the existing app on emulator-5554; package metadata confirms **0.14.0**, build **16**. This uses the existing development signing configuration for device/emulator testing.
- Signed iOS archive and App Store IPA: **31,379,640 bytes**. The archive identifies **com.wingmanbrowser.app**, version **0.14.0 (16)**. Deep/strict archive signature verification passed.
- Local build logs, artifact hashes and real-content capture receipts are under `work/content-refresh/`.

At the build checkpoint, TestFlight upload remains pending; the Mac locked before graphical Xcode distribution could start. Build 15 remains the previously verified internal testing release. Build success and screenshots do not establish TestFlight availability or installation on a physical device. A subsequent delivery entry records the upload/group result once verified.
