# Content sources and rights

Current feed-candidate integration and shared-media rules: [FEED_CANDIDATE_INTEGRATION.md](FEED_CANDIDATE_INTEGRATION.md). Historical version notes below remain unchanged.

Reviewed **September 13, 2026**. The current registry has **12 feed entries from four separately operated publishers**: NASA, NOAA, USGS and Global Voices. Nine entries are sections of Global Voices, not nine independent newsrooms. The configured topics are Headlines, Sports, Entertainment, Technology, Business, Fashion, Science, Food, Health and Environment. All sources are English-language; this inventory does not promise local reporting for every region or a comprehensive daily newsroom for every topic.

This record supports attributed text cards and, in **0.13.1+15**, a separately reviewed catalog of bundled photographs. RSS availability alone does not establish reuse rights. Full article bodies, paid API keys and commercial syndication agreements are not included. Free feed access observed today is not a guarantee that every future destination will remain free or accessible.

## Current source registry and live evidence

`backend/sources.json` and `assets/live_content/sources.json` pin each source's identity, exact feed URL, redirect hosts, article hosts and path rules, topics, attribution requirements and rights scope. A snapshot-supplied publisher name cannot authorize another source. The three agency feeds retain their reviewed destination prefixes. Global Voices uses exact host `globalvoices.org` and a dated article path `/YYYY/MM/DD/<slug>/`; arbitrary feed imports, category pages and shop pages are outside this article scope.

One isolated local CLI ingestion on **September 13, 22:18:34–22:18:50 UTC** received **HTTP 200 from all 12 configured feeds**. It made one due attempt per feed and fetched no article bodies or images. The final public snapshot contains **79 unique articles, 86,036 JSON bytes**, with generated time **22:18:50 UTC**. It was derived offline from that single actual pass after fixing a topic-classification revocation bug: a Fashion search mismatch had incorrectly withdrawn one valid Sports article. Original feed states, dates, response receipts and the initial 78-item snapshot remain preserved; this correction was not a second network ingestion.

| Registry entry | Exact configured feed | Accepted normalized entries before publication-age filtering and cross-feed deduplication |
| --- | --- | ---: |
| NASA Technology | [Technology RSS](https://www.nasa.gov/technology/feed/) | 10 |
| NOAA | [NOAA RSS](https://www.noaa.gov/rss.xml) | 8; two unreviewed destinations held |
| USGS | [USGS news RSS](https://www.usgs.gov/news/all/feed) | 30 |
| Global Voices · Sports | [Sport RSS](https://globalvoices.org/-/topics/sport/feed/) | 15 |
| Global Voices · Fashion | [Pinned Fashion query RSS](https://globalvoices.org/feed/?s=fashion) | 2; thirteen unrelated matches held |
| Global Voices · Food | [Food RSS](https://globalvoices.org/-/topics/food/feed/) | 15 |
| Global Voices · Health | [Health RSS](https://globalvoices.org/-/topics/health/feed/) | 15 |
| Global Voices · Science | [Science RSS](https://globalvoices.org/-/topics/science/feed/) | 15 |
| Global Voices · Technology | [Technology RSS](https://globalvoices.org/-/topics/technology/feed/) | 15 |
| Global Voices · Business | [Economics/business RSS](https://globalvoices.org/-/topics/economics-business/feed/) | 15 |
| Global Voices · Entertainment | [Arts/culture RSS](https://globalvoices.org/-/topics/arts-culture/feed/) | 15 |
| Global Voices · Headlines | [Main RSS](https://globalvoices.org/feed/) | 15 |

NASA identifies its feed through the [official RSS directory](https://www.nasa.gov/rss-feeds/); USGS offers [news subscriptions](https://www.usgs.gov/news/get-our-news). Global Voices publishes its section endpoints in its [RSS directory](https://globalvoices.org/feeds/). The Fashion query is a fixed reviewed endpoint, not arbitrary user input.

The final snapshot's counts below are **after** the 30-day publication window, canonical-URL deduplication and revocation checks. Topic totals overlap because agency articles can have more than one topic; they do not sum to 79. Cross-feed duplicates retain the first selected source's topics; the implementation does not union all section labels.

| Topic | Final article count | Newest publisher date | Oldest publisher date |
| --- | ---: | --- | --- |
| Headlines | 7 | September 13 | September 5 |
| Sports | 3 | September 5 | August 31 |
| Entertainment | 4 | September 13 | August 16 |
| Technology | 9 | September 10 | August 17 |
| Business | 4 | September 1 | August 28 |
| Fashion | 2 | September 4 | August 27 |
| Science | 49 | September 11 | August 19 |
| Food | 1 | August 21 | August 21 |
| Health | 3 | September 3 | August 22 |
| Environment | 38 | September 11 | August 19 |

Sports, Fashion and Food therefore survive the current cutoff, but their coverage is sparse and feature-oriented. Fashion includes a designer profile and garment-industry labor reporting, not a daily outfit or shopping wire. Food currently contains a feature on Indigenous crops and changing diets, not a recipe library. Business and Health are editorial coverage, not a market data terminal or personalized professional advice. Show the actual publication date; a fresh feed response must not relabel an August story as today's news.

Evidence: `work/content-discovery/ingestion-validation/cli-report.json`, `receipt-original.json`, `receipt-final.json`, the original `store/current.json`, and `public-snapshot-corrected.json`. The UI evidence input is `work/content-discovery/live-snapshot.json`; its SHA-256 is `2c3bd15c5e81cac78ae0bdc66e58de02bc3128c4359d080348713134f8211c14`. All 79 articles have publisher dates within the selected window; all Global Voices cards retain author credit; all remote image fields are null. Separate UI and browser acceptance is required—successful RSS ingestion is not proof of native article opening or unrestricted access to all publisher pages.

## Text reuse decisions

Each permitted card contains the publisher's title, a bounded plain-text publisher excerpt, source/author credit, publication date when supplied and a canonical article link. Strip executable HTML and label shortened text as an excerpt. Store provenance with the normalized record. Do not fetch full articles for redistribution.

| Publisher | Text and commercial reuse basis | Credit and exclusions | Images |
| --- | --- | --- | --- |
| NASA | NASA-created factual, informational/editorial text is suitable for attributed cards, including in a commercial app. Federal-work status and NASA's usage guidance are the basis. | Credit NASA and named author when supplied; exclude third-party protected material. Do not imply endorsement or turn NASA branding into Wingman branding. | Feed images disabled. One separately reviewed bundled photograph is permitted only for its exact story. Existing Home artwork has separate records and is not a story fallback. |
| NOAA | NOAA-created public information may be reused in products within its stated scope. Government hosting does not clear third-party contributions. | Credit NOAA, the program and named individual when supplied. Preserve notices; do not claim ownership or present altered text as an unmodified official statement. | Disabled, including photos embedded in descriptions. |
| USGS | USGS-authored or produced information is public domain in the U.S. Its guidance addresses reproduction and packaging for resale. | Credit U.S. Geological Survey and named author when supplied. Third-party works and the USGS identifier have separate restrictions. | Feed images disabled. Two separately reviewed bundled story images have explicit per-image public-domain records. |
| Global Voices | Publisher-created material is offered under CC BY 3.0, except where otherwise stated. The grant supports commercial sharing, adaptation, excerpt display and caching. | Require named author plus Global Voices credit near the card top, an original-article link and license link; indicate excerpting/format changes. Preserve exceptions and avoid endorsement claims. | Feed images disabled. One Solidarity Center photograph has separate CC BY 2.0 permission for its exact story; other third-party media is not cleared by the text license. |

Government primary authority: [U.S. Copyright Office, §§101 and 105](https://www.copyright.gov/title17/92chap1.html), [NASA usage guidance](https://www.nasa.gov/nasa-brand-center/images-and-media/), [NOAA product-use FAQ](https://www.noaa.gov/office-education/outreach-communication/faq), [NOAA Ocean Service reuse guidance](https://oceanservice.noaa.gov/about/faq.html), [USGS copyrights and credits](https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits), and [USGS commercial reproduction credit examples](https://www.usgs.gov/information-policies-and-instructions/acknowledging-or-crediting-usgs). Federal public-domain status is a U.S. legal basis, not a claim that every hosted contribution has a worldwide CC0 license.

The canonical NOAA product-use FAQ returned HTTP 403 during the earlier direct review. Guidance was verified in the search-indexed [official NOAA copy](https://prod-01-alb-www-noaa.woc.noaa.gov/office-education/outreach-communication/faq) and corroborated by accessible Ocean Service guidance. The live news feed succeeded; these are different access observations.

Global Voices' [current attribution policy](https://globalvoices.org/about/global-voices-attribution-policy/) and [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) govern its own licensed text. The policy requests republishing notice and invites recurring publishers to discuss partnership. No notice, agreement or contact was sent. Explicit per-work restrictions override the default. Consume RSS `description`, not full-body `content:encoded`; missing required authors or detected incompatible rights notices hold the item. The stored attribution includes the named author; the source record supplies the publisher and license. The adjustment notice must remain visible with the credit.

## Actual story photographs — 0.13.1+15

The user's selected rule is **actual story photos only**. Four reviewed images are bundled, and each requires both its exact locally approved article URL and source ID. Every other article remains text-only. There is no topic, stock or generic-image fallback. Existing user-selected DiscoveryPhotos remain separate Home artwork and are not assigned to stories. Photographer credits, source pages and licenses remain available in Photo credits; no paid image API or subscription is used.

The NASA Anak Krakatau satellite view is credited to NASA Earth Observatory / Michala Garrison and identifies its September 5, 2026 image date. The USGS zebra-mussel photograph credits Amy Benson and identifies its 1992 archive date; it depicts Lake Huron specimens, not a new Utah field sighting. The USGS Maunaiki photographs credit Thomas Jaggar / Hawaiian Volcano Observatory and identify 1919–1920. The Bangladesh garment-worker photograph credits Solidarity Center under CC BY 2.0, identifies its 2015 archive date and discloses the publisher crop. Its original [Flickr photo record](https://www.flickr.com/photos/62762640@N02/29010292884) independently confirms that license; Global Voices' CC BY 3.0 text license is not its basis. All four images occur on the linked publisher articles. These authorizations attach to the reviewed packaged bytes and article association, not the whole publisher or future feed images. See [Story images](STORY_IMAGES.md) and the linked individual media records for the exact scope.

The four new image files—three JPEGs and one WebP—total **1,180,639 bytes (1.181 MB)** before app packaging. Images load from the app bundle without publisher/CDN requests, an image API or a dedicated image-hosting service. Web distribution still serves its normal bundled application assets; this is not a claim that all app distribution or bandwidth is free. Source-wide `images:false` remains unchanged, and feed-supplied image URLs are still rejected. Credits and dates distinguish the satellite image from archive photographs; a photo used by an article is not automatically a photograph of a new event.

The source manifests record visual review of the saved assets and their checksums. They do not certify an automated safety classifier, every image on a publisher's website, or a completed device/build acceptance run. Photo additions do not change article eligibility, private/handoff visibility or destination protection.

## Cache, polling and withdrawal

**Thirty-minute polling, seven-day normalized-cache retention and the 30-day publication-age window are Wingman engineering limits, not license terms supplied by these publishers.** No numerical syndication polling mandate or maximum text-retention rule was found for the selected four publishers' approved text. Cache age and publication age are separate: successful revalidation refreshes fetched/cache time, never the original publication date.

Use ETag and Last-Modified validators when available, respect longer server freshness and Retry-After values, and back off on failures. The earlier agency responses included NASA `max-age=300, must-revalidate`, NOAA `max-age=900, public`, and USGS `max-age=600, public`. Global Voices responses supplied validators; a main-feed HEAD check with an Origin header supplied no `Access-Control-Allow-Origin`. Native HTTP availability does not imply that browser JavaScript can fetch the same RSS endpoint across origins. No early repeat requests were used to fabricate the September 13 ingestion result.

Parse publisher timezones, including EDT. Keep missing publication dates missing; Atom `updated` does not establish first publication. Normalize configured tracking parameters for canonical identity. Never execute feed HTML or request its embedded images, enclosures, favicons or trackers.

Rights, safety and explicit publisher/source withdrawals remove affected cards and cached excerpts when the update is received. A benign topic mismatch affects only that section and must not revoke an otherwise valid article from another feed. The backend regression covers both cases, including persistence across refreshes and rights checks taking precedence over topic matching. Saved links are user records; they do not extend withdrawn excerpt rights. Offline devices cannot learn new withdrawals before reconnecting, so finite display expiry remains necessary.

## Eligibility, privacy and source balance

Source approval combines reviewed publisher/feed scope, exact destination host/path, rights, attribution and item checks with current browser protection. Source origin does not certify every future item as suitable. Text checks can reject or hold an item; keywords alone do not grant rights or certify safety. Reporting and education may discuss a restricted subject without promoting it. Explicit sales, affiliate or prohibited-category promotion remains excluded.

Fashion is the one reviewed query feed. Its exact title/description scope terms exclude incidental expressions such as a football team winning “in dramatic fashion.” Both actual accepted Fashion articles were checked against the topic: the [August 27 designer profile](https://globalvoices.org/2026/08/27/how-buryat-fashion-designer-oksana-alkhunsaeva-stitched-her-life-back-together-in-russia/) and [September 4 garment-worker childcare report](https://globalvoices.org/2026/09/04/maternity-leave-is-expanding-in-bangladesh-but-garment-workers-still-struggle-for-childcare/). Topic matching remains a limited classifier and does not replace rights or suitability review.

Agency destination scopes remain: NASA `/` on exact hosts `www.nasa.gov` and `science.nasa.gov`, constrained to the selected feed; NOAA `/news/`, `/news-release/`, `/stories/`, `/education/`; USGS `/news/`, `/centers/`, `/programs/`, `/observatories/`, `/mission-areas/`, `/special-topics/`. Two NOAA entries remain held outside these paths. Do not widen a feed scope merely to increase counts.

Use only the exact reviewed story photographs described above; stories without a matching image remain text-only. Feed-supplied thumbnails and runtime remote media remain unapproved. No external moderation service, behavioral profile or browsing-history upload is needed for this feed selection. Direct publisher feed fetching exposes ordinary network metadata such as IP address and user agent; it is not accurate to claim that no data leaves the device. Private, handoff and feed-off states must suspend feed fetching and owner-content exposure.

## Candidates researched but not enabled

These decisions distinguish working transport from reuse permission and appropriate current content. Detailed HTTP metadata and policy notes are in `work/content-discovery/source-research.md` and its neighboring receipts.

| Candidate | Verified finding and decision |
| --- | --- |
| [The Conversation](https://theconversation.com/us/republishing-guidelines) | U.S. main/arts Atom feeds returned 200 with current articles. CC BY-ND/extract rules require author and institution credit; the policy also requires a page-view counter, limits systematic republication and may charge commercial non-journalism uses. No clear extract waiver for the counter was found. Hold for a compatible agreement/integration; do not silently add tracking. Photos are separate. |
| [Wikinews](https://en.wikinews.org/wiki/Main_Page) | Main page announces closure/read-only transition on May 4, 2026. Archival articles and a live template clock are not current news. Excluded from live coverage. |
| [Phys.org](https://phys.org/feeds/), [Tech Xplore](https://techxplore.com/feeds/), [Medical Xpress](https://medicalxpress.com/feeds/) | Five tested science/gadgets/business/health/nutrition RSS endpoints returned 200 with September articles. Their specific free commercial RSS permission requires unchanged feed content/headlines/links and attribution; the current excerpt truncation contract is different. Full articles and photos are not licensed by that grant. Sample HTML had a skippable donation/offerwall configuration; unrestricted native access to every article is unverified. Hold. |
| [VOA](https://www.voanews.com/p/5338.html) | Reuse applies to exclusively VOA-produced material, excluding AP/AFP/Reuters and other licensed works. RSS directory is accessible, but per-item/category authorship and current inventory were not fully cleared. No blanket feed approval. |
| [GOV.UK culture/media/sport](https://www.gov.uk/help/terms-conditions) | Official departmental Atom returned 200 with September updates. OGL reuse includes application/feed caching, with exceptions. Mixed policy, guidance and statistics do not establish a general match-report or entertainment feed. Not selected. |
| [FashionNetwork](https://us.fashionnetwork.com/texte/36.html) | Commercial/professional RSS redistribution requires prior agreement. None obtained. |
| [Hindustan Times RSS](https://www.hindustantimes.com/rss) | Personal/noncommercial restriction; not approved for this consumer-app integration. |
| [ScienceDaily](https://www.sciencedaily.com/terms.htm) | Free commercial RSS permission has unchanged-content, advertising, interstitial, retention and database restrictions. The current saved-excerpt/cache design does not establish compliance. Hold; NewsDaily has separate terms. |
| [NIH News in Health](https://newsinhealth.nih.gov/about-us) | Attributed article republication is encouraged; most photos are copyrighted. Tested `rss.xml` returned 403. No working current feed claimed. |
| Library of Congress Catbird Seat | RSS returned 200, but the newest entry was a 2023 farewell. Excluded as current culture news. |
| NOAA Ocean Service / Ocean Facts | Earlier checks found malformed news XML and an old facts feed. Not repaired or relabeled as current news. |
| NIH releases / NIEHS / Fogarty | Earlier checks found a 403, stale 2025 or June 2026 publication metadata, absent dates, or problematic destination paths. Fresh HTTP modification dates did not establish fresh reporting. Not enabled. |

The [Guardian commercial platform](https://open-platform.theguardian.com/access/) remains a possible separately negotiated expansion, not part of this free source plan. No paid provider, quote, contract or key was obtained. A paid data-access subscription would not by itself prove syndication rights.

## Historical agency-only receipts

The following records describe the **September 12 implementation before Global Voices was added**, not the current source/topic counts.

At **00:40:31 UTC**, the first run published **43 items: NASA 10, NOAA 3, USGS 30**. Seven NOAA entries were held because `/news-release/` was not yet reviewed in the configuration. The 00:47:20 invocation correctly recorded every source `not-due`; retained evidence supported adding the prefix without an early fetch.

The next due run at **01:10:50 UTC** published **48 items: NASA 10, NOAA 8, USGS 30**, snapshot `93470a9470abea5c1f3d39bc592edd8f`, with HTTP 200 from all three. Forty-four supplied a named author; four NASA entries did not. Science appeared on 48 cards, Environment on 38 and Technology on 3. The local GET measured **52,486 identity-encoded bytes**. An NOAA leadership biography and scholarship path remained held. These older files are under `work/live-content/`; the September 13 evidence and counts above supersede them for the expanded inventory.

Repository inspection at the start found no licensed news API integration or deployed content snapshot service. Older cloud control-plane documents describe browser protection, not content rights. Browser engines—GeckoView, Android WebView and WKWebView—render opened articles; they do not supply publisher licenses, news inventory or a deployed feed service. Source delivery and browser-engine selection remain separate responsibilities.
