# Content sources and rights

Reviewed September 11, 2026 (some live HTTP receipts are dated September 12 UTC). This record authorizes a narrow, attributed text-card implementation. It does not infer rights from RSS availability, declare every government-hosted work reusable, or license a publisher's photographs merely because their URLs occur in a feed.

## Existing integrations and decision

Repository inspection found no existing licensed news API integration, provider credential configuration, or live news backend. The earlier [cloud control-plane](CLOUD_CONTROL_PLANE.md) and [cost plan](CLOUD_COST_PLAN.md) concern browser protection distribution, not news rights. Existing reviewed article references and browser destinations are not syndication agreements. No account, paid developer key, or external connector was treated as a production content license.

Use three separately operated agency publishers: NASA, NOAA and USGS. They are distinct sources, but all are U.S. federal agencies; this is institutional science/public-information coverage, not a diverse general-news newsroom. The registry is `assets/live_content/sources.json`; the backend and client must pin its approved source identity, exact article domains, reviewed path prefixes, topics and rights scope. Snapshot-supplied source names cannot authorize another publisher.

## Enabled endpoint inventory

These are live HTTP observations, not fixture stories. Publisher content and counts can change after this review.

| Source | Configured feed | Observed response | Actual coverage / exact article hosts |
| --- | --- | --- | --- |
| NASA Technology | `https://www.nasa.gov/technology/feed/` | HTTP 200, valid RSS, 10 items, 284,013 bytes; newest item September 10, 2026 | Technology and science; `www.nasa.gov`, `science.nasa.gov` |
| NOAA | `https://www.noaa.gov/rss.xml` | HTTP 200, valid RSS, 10 items, 75,596 bytes; newest item September 8, 2026 | Environment and science, including weather/ocean/wildlife public information; `www.noaa.gov` |
| U.S. Geological Survey | `https://www.usgs.gov/news/all/feed` | HTTP 200, valid RSS, 30 items, 27,384 bytes; newest item September 11, 2026 | Earth science and environment; `www.usgs.gov` |

NASA lists its technology feed in the [official RSS directory](https://www.nasa.gov/rss-feeds/). USGS offers feeds through [Get Our News](https://www.usgs.gov/news/get-our-news). The [NOAA endpoint](https://www.noaa.gov/rss.xml) itself supplied the observed feed. Each fetch stays on the configured publisher host; article opening is a separate consumer-browser operation. All three are English-language sources. Locale selection must not imply that they supply local reporting for every region.

The initial actual ingestion published **43 items: NASA 10, NOAA 3 and USGS 30** at September 12, 00:40:31 UTC. Seven NOAA feed entries were conservatively held because their `/news-release/` destination prefix was absent from the first configuration. That publisher prefix is now reviewed and configured alongside `/news/`, `/stories/` and `/education/`; it was verified from retained feed evidence, without forcing an early refetch. The 00:47:20 UTC invocation correctly recorded all sources as `not-due`. These initial receipts are in `work/live-content/ingestion-run-1.json` and `ingestion-run-2.json`.

The next due network run produced snapshot `93470a9470abea5c1f3d39bc592edd8f` at **01:10:50 UTC, September 12: 48 items (NASA 10, NOAA 8, USGS 30)**, with HTTP 200 from all three publishers. Forty-four items supplied a named author; four NASA entries did not. Two NOAA entries remained held: an `/our-people/leadership/` biography and an `/office-education/` scholarship news path outside the reviewed prefixes. The narrower published total is intentional. Per-item topic assignment yielded science on 48, environment on 38 and technology on 3; a source's available topics no longer tag every item automatically. The final local GET measured 52,486 identity-encoded JSON bytes.

Current backend destination scopes: NASA allows `/` on its two exact hosts because its selected technology feed links to several site sections; it remains limited to entries supplied by that configured feed. NOAA permits the four prefixes above. USGS permits `/news/`, `/centers/`, `/programs/`, `/observatories/`, `/mission-areas/` and `/special-topics/`. A host/prefix match alone does not establish text rights or eligibility; feed provenance, source scope, rights exclusions and current browser policy all remain required.

## Rights decisions

For all three enabled sources, the implementation permits the publisher's own title and a bounded, plain-text publisher excerpt, with source attribution and a canonical article link. It does not retrieve full articles for redistribution. HTML removal and truncation must preserve meaning; label excerpts as excerpts. Store provenance with every normalized item.

| Source | Title / excerpt / commercial display / redistribution | Attribution and exclusions | Image decision |
| --- | --- | --- | --- |
| NASA | NASA's own factual, informational/editorial content is suitable for attributed cards in Wingman, including a commercial app. Federal-work status supplies the text basis; NASA's usage guidance separately permits factual use without implied endorsement. | Credit NASA and the named author when supplied. Third-party protected material is excluded. Do not claim partnership, use agency branding as Wingman branding, or imply approval. | Disabled. NASA's media terms contain third-party, logo and recognizable-person qualifications; a feed image is insufficient evidence. |
| NOAA | NOAA-created public information may be reused in products. Titles and publisher excerpts may be cached and redistributed within this scope; government hosting alone does not clear third-party material. | Credit NOAA, the NOAA program and named individual when supplied. Preserve notices. Do not imply endorsement, claim the material as Wingman's, or present edited material as an unmodified official statement. | Disabled, including third-party photos embedded in feed descriptions. |
| USGS | USGS-authored or produced information is public domain in the U.S. Its credit guidance expressly discusses reproduction and packaging for resale, supporting commercial text-card distribution. | Credit U.S. Geological Survey and named author when supplied. Exclude third-party protected text/media; the USGS identifier is separately controlled. | Disabled; third-party images and staff publicity rights require separate review. |

Primary authority: [U.S. Copyright Office, §§101 and 105](https://www.copyright.gov/title17/92chap1.html), [NASA usage guidance](https://www.nasa.gov/nasa-brand-center/images-and-media/), [NOAA product-use FAQ](https://www.noaa.gov/office-education/outreach-communication/faq), [NOAA Ocean Service reuse guidance](https://oceanservice.noaa.gov/about/faq.html), [USGS copyrights and credits](https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits), and [USGS commercial reproduction credit examples](https://www.usgs.gov/information-policies-and-instructions/acknowledging-or-crediting-usgs). Federal public-domain status is a U.S. legal basis, not a claim that every hosted contribution has a worldwide CC0 license. Retain the publisher's own permission and exceptions; do not assign invented Creative Commons licenses.

The canonical NOAA product-use FAQ returned HTTP 403 to the direct check. Its guidance was verified in the search-indexed [official NOAA copy](https://prod-01-alb-www-noaa.woc.noaa.gov/office-education/outreach-communication/faq), corroborated by the accessible Ocean Service guidance. This access limitation is not concealed as a successful direct fetch. The news feed itself returned 200.

## Cache, polling and withdrawal

No numeric syndication polling mandate or maximum text-retention term was found for these selected public-domain agency feeds. **Thirty-minute ingestion and seven-day normalized-cache retention are Wingman engineering limits, not publisher-issued license terms.** Public-domain text reuse supports keeping normalized excerpts; upstream HTTP response freshness remains separate.

Observed response headers: NASA `Cache-Control: max-age=300, must-revalidate`; NOAA `max-age=900, public`; USGS `max-age=600, public`. All three supplied ETag and Last-Modified validators. Use conditional requests after the configured interval, respect longer explicit server freshness or Retry-After values, and back off on failures. Do not repeatedly fetch merely to force an acceptance demonstration. A 304 updates successful validation time, not the publisher's publication date. Publication age and fetch freshness are different fields.

USGS dates include `EDT`; parse the stated zone rather than assuming UTC. Some USGS article links contain HTML-escaped query separators and `utm_*` tracking. Decode XML safely, normalize configured tracking parameters for canonical identity, and do not treat embedded HTML as executable content. Missing publication dates remain missing. Atom `updated` is not automatically `published`.

Rights or source revocation must remove affected items from new snapshots and cached display on the next successful revocation update; a normal timeout must retain still-usable cached items. Saved links remain user records, but do not grant continuing display rights to withdrawn excerpts. An offline client cannot know a new revocation until it reconnects, so enforce finite cached-display expiry and make this limitation explicit. No source description grants a permanent browser-policy exemption.

## Content eligibility and images

Approval is a source-scope decision plus item checks: the configured NASA technology reporting feed, NOAA public-information feed, and USGS science-reporting feed; exact publisher destination hosts; normalized metadata; local destination protection; and exclusion/review of promotional or ambiguous material. Publisher origin is evidence of the intended editorial scope, not proof that every future item is suitable.

Evaluate titles and excerpts before cards are emitted. Reporting, education and recovery may mention prohibited categories without promoting them. Conversely, a neutral headline must not make a promotional destination eligible. Keyword checks can flag items for exclusion/review but cannot establish approval by themselves. Government procurement notices, endorsements, promotions, unexplained third-party credits and out-of-scope destinations need rejection or explicit review.

All initial remote image references are null. Strip image tags and enclosure/media URLs before distributing cards; do not fetch thumbnails, logos or remote favicons during Home rendering. Use only existing reviewed local category art or a local icon. No automated image classifier, external moderation API, behavioral profile or browsing-history upload is enabled. Source scope and text rules remain limited controls, not a universal classifier.

## Additional sources tested but not enabled

| Candidate | Observed limitation | Rights / decision |
| --- | --- | --- |
| NOAA Ocean Service `https://oceanservice.noaa.gov/rss/nosnews.xml` | Malformed XML, mismatched closing tag | Reject the response; do not silently repair it into a live feed. |
| NOAA Ocean Facts `https://oceanservice.noaa.gov/rss/oceanfacts.xml` | Valid feed, 342 items; first item's date July 31, 2023, Last-Modified June 2024 | Educational/evergreen material, not counted as current news. |
| NIH releases `https://www.nih.gov/news-releases/feed.xml` | Official link verified; direct HTTP 403 | NIH's own public-domain text generally permits reuse; third-party exceptions apply. Not enabled without successful ingestion. |
| NIH/NIEHS Environmental Factor `https://www.niehs.nih.gov/news/factor/feeds/newsletter.xml` | Redirects to `/news/factor/rss_feed.xml`; 809 items, leading material from December 2025, missing `pubDate`, duplicated path segments in links | Text reprinting permitted, but stale/broken metadata cannot satisfy current-health acceptance. |
| NIH/NIEHS news `https://www.niehs.nih.gov/news/newsroom/rssfeed/rss_news.xml` | Leading item November 2025 despite fresh HTTP Last-Modified | Not current-health coverage; do not substitute server modification time. |
| NIH Fogarty `https://www.fic.nih.gov/Pages/rss-news.aspx` | Valid 25-item feed through a same-host SharePoint redirect; leading material June 23, 2026 | Not selected for the current-news set. |

NIH's [reuse FAQ](https://www.nih.gov/about-nih/frequently-asked-questions) excludes some licensed resources and images. [NIH News in Health](https://newsinhealth.nih.gov/about-us) encourages republication of its articles and illustrations, but warns that most photographs are copyrighted and requests attribution plus copies. [Environmental Factor](https://www.niehs.nih.gov/news/factor/subscribe-newsletter) permits text reprinting and asks for a copy. These policies do not authorize copying unrelated research papers, NIH-funded journals or photos. No publisher was contacted, and no copy was emailed.

## Coverage gap and paid option

The enabled set supports science, technology and environment. It does **not** supply broad general news, sports, entertainment or a full lifestyle/health feed. Outdoors information can occur within NOAA's environment coverage; that is not justification for a broad Lifestyle category promise.

The concrete publisher-authorized expansion candidate is **Guardian Open Platform Commercial**, using a negotiated content-distribution agreement. The publisher offers commercial API access and usage-dependent pricing; commercial approval is not included in its free developer key. [Commercial access](https://open-platform.theguardian.com/access/), [licensing options](https://licensing.theguardian.com/frequently-asked-questions).

The quote must explicitly cover Wingman's Android/iOS apps and web companion, title/excerpt display, common cached snapshots, local offline cache and reading-list metadata, attribution, territory/language, withdrawal deadlines, and any images. Third-party agency material may be excluded from the publisher's syndication rights. No quote, key, contract or purchase has been obtained. [Costs and remaining approval](CONTENT_OPERATING_COSTS.md) distinguish this viable licensing path from an API subscription that only sells access.
