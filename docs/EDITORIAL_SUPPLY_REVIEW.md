# Editorial supply review — September 15–16, 2026

The repair separates a permitted article from optional image availability. It does **not** establish new rights to commercial sports or entertainment feeds. This focused review promoted **zero new publishers**. The 17 existing source entries remain active; nine Global Voices entries represent one editorial publisher, now explicitly identified with `publisherId: global-voices`. The two NASA entries and three Science X brands likewise share their respective publisher IDs so diversity counts do not inflate independent ownership.

## Current rights decisions

These decisions concern Wingman's commercial consumer app and shared web cards, not whether a person may follow a bare hyperlink. “Permission required” means the proposed runtime use is outside an established grant; it does not mean the publisher will never license it.

| Publisher | Title/link and excerpt | Exact feed photo | Logo | Cache / redistribution | Full text | Runtime decision |
| --- | --- | --- | --- | --- | --- | --- |
| Global Voices | Commercial CC BY 3.0 text reuse, retaining author, source, original link, license and modification notice | Third-party images require separate clearance | No new logo approval; initials | Attributed text permitted; existing bounded retention remains | CC BY permits, but Wingman remains a link-out reader | Retain all existing sections; optional text cards restore supply |
| FanSided | Commercial reuse requires prior written consent | Not cleared | Not cleared | Commercial/automatic copying restricted without consent | Not cleared | Permission required; not activated |
| Yahoo Sports | RSS subsection allows unchanged feed display with attribution and original links; general commercial/aggregation restrictions still apply | No commercial app/redistribution grant established | Separate explicit written permission required | Commercial reuse and competing mobile/data aggregation restricted; no ads in the feed | Not cleared | Permission required; not activated |
| Deadline and Variety | PMC feed terms require unchanged text, attribution and direct article links; Sections 3–4 limit commercial use absent written permission | No commercial photo grant established | Feed-logo rule is conditional on an otherwise permitted use | Commercial redistribution requires permission | Not cleared | Both held under the same publisher-wide terms; no duplicate endpoint negotiations presumed |
| The Conversation US | Attributed extracts explicitly permitted with an original-article link; author/institution credit required | Each photo must be checked separately | Logos offered with permitted content | Online republishing requires an article-specific page-view counter; commercial non-journalism use needs clarification | CC BY-ND subject to guidelines | Hold for tracking-free app-use permission; not treated as an unreviewed unknown |
| NewsUSA | Unchanged supplied content with attribution; generic excerpt reuse remains off in Wingman | Only with accompanying complete article | No new approval | Existing transient no-store image handling remains | Existing sponsored reader preserves complete associated article and links | Retained, labeled Sponsored; excluded from editorial acceptance |
| Science X: Phys.org, Tech Xplore, Medical Xpress | Explicit no-charge personal/commercial RSS grant; headlines, links and credit unchanged | Existing exact `csz/news/tmb` thumbnails only, maximum 90×90 | No new approval | Only the existing feed presentation and bounded permitted cache; no bulk resale assumption | No full-article grant inferred | Retained, unchanged image scope |

Official evidence checked during this task:

- [Global Voices republication policy](https://globalvoices.org/about/global-voices-attribution-policy/) (policy dated April 9, 2025). Third-party photography is explicitly separate from the text grant. The current Casablanca music article's photographs are credited to Le Backstage, L'Octave and individual performers as used with permission/courtesy; that is not a sublicense to Wingman. [Actual story](https://globalvoices.org/2026/09/13/as-casablancas-music-scene-grows-its-musicians-struggle/).
- [FanSided terms](https://fansided.com/terms), “Limitation on Use” (page labels last modification January 2023). Commercial use and automatic gathering require prior written consent. Its contributor-to-publisher grant is not a commercial grant to Wingman.
- [Yahoo U.S. terms](https://legal.yahoo.com/us/en/yahoo/terms/otos/index.html), current page dated August 4, 2026, sections “Use of Services”, “Ownership and Reuse”, “Member conduct” and “RSS Feeds”. A normal HTTPS request succeeded after the research browser failed to render the page. No access controls were bypassed. The RSS clause alone does not resolve the proposed commercial aggregation.
- [PMC terms](https://www.pmc.com/terms-of-use), dated August 21, 2026, sections 3, 4 and 19. The feed clause's linking requirements do not expressly override the commercial restriction; obtain a commercial feed/photo grant covering both brands where appropriate.
- [The Conversation U.S. guidelines](https://theconversation.com/us/republishing-guidelines). A normal HTTPS request succeeded. Extracts and advertising-supported publication are permitted subject to the listed conditions. The online counter transmits referring URL, browser user agent and an IP address used for city geocoding, even though the publisher says the IP is discarded. This review did not add that tracking to Wingman. A publisher exemption or explicit approval for the intended app use is needed.
- [NewsUSA terms](https://newsflow.newsusa.com/terms-of-syndication). Photographs are optional under the grant, but a displayed photograph cannot be separated from its article. Wingman's existing stricter complete-article/photo presentation is preserved for this repair.
- [Phys.org](https://phys.org/feeds/), [Tech Xplore](https://techxplore.com/feeds/) and [Medical Xpress](https://medicalxpress.com/feeds/) each explicitly permit commercial RSS use. This review does not enlarge thumbnails into full-resolution variants.

## Small alternative-source check

The focused alternatives did not produce a cleared, current replacement for the requested U.S. sports/entertainment mix:

- [Impakter's republication grant](https://impakter.com/about-impakter/republishing-content/) permits commercial unchanged attributed original articles under CC BY-ND. Its [Sports index](https://impakter.com/category/culture/sport/) showed no evidence of a current 72-hour sports inventory in the returned index (latest shown February 2, 2026). This is a content-supply gap, not a blanket denial of its text grant. No photographs or syndicated third-party material were inferred cleared.
- [Wikinews September 2026 archive](https://en.wikinews.org/wiki/Wikinews:2026/September) returned empty daily listings. A free license alone is not usable current inventory. No inactive category was added just to increase a publisher count.
- [Techdirt's publisher statement](https://www.techdirt.com/2009/01/29/why-is-it-so-difficult-to-opt-out-of-copyright/) supports reuse of its own writing, but its current About page returned HTTP 403. It is technology/copyright reporting and was not added as a substitute for match reporting or entertainment coverage.

## Actual bounded feed observations

A single due attempt for each of the **16 approved non-NewsUSA endpoints** ran September 16, 2026, **01:11:38–01:15:23 UTC** (September 15 evening U.S. Central). It reused the existing retained source states and validators. Sports and Entertainment returned **304**, confirming their retained representation; the other 14 returned **200**. No endpoint was retried. The next eligible attempts remain at or after **01:41:38–01:45:22 UTC**, subject to each response's cache directives.

Before the tightened Entertainment topic filter, Global Voices Sports had 15 parsed records, 3 permitted articles within 30 days, **0 within 72 hours**, newest September 5. Arts/Culture had 15 parsed records and 6 within 30 days, but only **one** was ordinary entertainment reporting (Casablanca music, September 13). The other retained records concerned folklore, sports, fashion or Indigenous identity. Those records are not counted as new entertainment inventory. The configuration now restricts that section to actual music, film, television, performance, dance and related reporting.

Both categories still have **one enabled editorial publisher**, **zero cleared recent story photographs**, and fewer than five relevant articles within 72 hours. Sports is short by five recent stories, one additional publisher and three images. Entertainment is short by four recent stories, one additional publisher and three images. A native text card is useful resilience, but does not satisfy these coverage targets or make the supplied international reporting U.S.-based.

Machine-readable response headers, next-due checkpoints, normalized states, current-source rights fetch receipts and the derived common-media coverage are retained under `work/editorial-repair/supply/`. The app registry includes a small `reviewStatusByTopic` summary for developer diagnostics; it is not a new candidate directory or permission grant. No paid service, credentials, tracking counter or production deployment was added.

## Common-delivery measurement (not native device evidence)

At 2026-09-16T01:18:24Z, the normal backend normalized the current responses/revalidated items and decoded 24 exact approved Science X thumbnails in one bounded media pass. No article-image request targeted NewsUSA. This table is before any later on-device policy/classifier decision; it excludes the four separate legacy bundled photographs and all sponsored inventory. The 30-day window is a retention ceiling, not a claim that lifestyle articles are fresh. Actual dates remain visible.

| Category | Enabled publisher operators | Raw fetched/revalidated records | Eligible ≤30d | Decoded image cards | Text fallbacks | Newest publication UTC | Relevant ≤72h |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| Headlines | 5 | 285 | 172 | 24 | 148 | 2026-09-16T00:40:01Z | 105 |
| Sports | 1 | 15 | 3 | 0 | 3 | 2026-09-05T05:00:38Z | 0 |
| Entertainment | 1 | 15 | 1 | 0 | 1 | 2026-09-13T12:00:57Z | 1 |
| Business | 2 | 45 | 5 | 0 | 5 | 2026-09-14T09:19:57Z | 1 |
| Technology | 3 | 65 | 45 | 8 | 37 | 2026-09-15T23:00:01Z | 30 |
| Science | 5 | 105 | 81 | 8 | 73 | 2026-09-16T00:13:24Z | 41 |
| Food | 1 | 15 | 1 | 0 | 1 | 2026-08-21T07:16:12Z | 0 |
| Health | 2 | 45 | 33 | 8 | 25 | 2026-09-16T00:40:01Z | 30 |
| Fashion | 1 | 15 | 2 | 0 | 2 | 2026-09-04T20:56:44Z | 0 |
| Travel | 0 | 0 | 0 | 0 | 0 | None | 0 |
| Environment | 2 | 40 | 37 | 0 | 37 | 2026-09-16T00:13:24Z | 11 |

Headline totals contain the finite cross-category mix; category rows can overlap and must not be summed. Counts collapse source sections/brands sharing an operator (Global Voices, NASA, Science X). Sports and Entertainment each remain at one actual publisher, so this accounting choice cannot satisfy their missing second-publisher requirement. Other remaining gaps: Food and Fashion are sparse older features; Travel has zero editorial sources; Business has few current items and zero images in this bounded pass. The rest of the image queue is deferred, not evidence of fetch failure.
