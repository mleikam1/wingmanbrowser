# Consumer protection coverage — recovery milestone

Consumer Wingman permits a destination when the current mandatory blocking policy has no match. “Permitted” does **not** mean reviewed or verified safe. Home/feed review, managed school allowlisting, search-provider adult filtering, additional restrictions, tracker controls, and destination protection are separate systems. There is no unrestricted mode and no user override for a mandatory match.

## Implemented local baseline

The build-pinned `assets/policy/consumer_protection.json` contains 318,889 category/threat suffix-domain rules, 9 host/path rules, and 2,501 third-party tracker rules. Dart and the native engines independently validate the same SHA-256 before use. The baseline is 6,186,863 bytes; its SHA-256 is `f397d8f87a02fbb7754ce9c77931f740ba10271370e1e09f8402607bef59098f`.

| Layer | Packaged coverage | Specific limitation |
| --- | --- | --- |
| Explicit entertainment | Complete HaGeZi NSFW published list, with one category-only educational correction; 74,493 compiled domains including a synthetic fixture | Host classification misses explicit sections or media hosted by otherwise neutral services. Mixed hosts may be false positives. |
| Gambling | Complete HaGeZi Gambling Mini list, plus limited supplements; 67,364 domains | Mini is the upstream mobile-size subset, not its full gambling dataset. General sports sites need path/resource decisions. |
| Known threats | Complete HaGeZi Threat Intelligence Mini list, plus a synthetic fixture; 176,988 domains | Mini is the upstream subset. New threats, compromised neutral hosts and URL-specific threats can be missed. Platform threat protection supplements local rules where supported. |
| Alcohol promotion/commerce | 16 high-confidence first-party/fixture domains and two Walmart category paths | **Major production gap:** there is no maintained comprehensive alcohol-category feed. Product pages, delivery services and dynamic promotions are incompletely covered. |
| Recreational-drug promotion/commerce | 11 first-party/fixture domains | **Major production gap:** no maintained feed validated to separate recreational commerce from clinical treatment, pharmacy and recovery information. This supplement is limited and includes mixed commercial hosts. |
| Tobacco/nicotine/vaping promotion | 17 first-party/fixture domains | **Major production gap:** limited supplement, not comprehensive industry/domain coverage. |
| Additional restrictions | Persisted user-added blocked domains and existing collection/resource restrictions | Additive only. They cannot remove a mandatory rule. Hiding a reviewed website source blocks its listed document URLs; explicit user-added domains also cover subdomains. These are user restrictions, not category classifications. |
| Trackers | Existing licensed EasyPrivacy adaptation: 2,501 third-party suffix domains | A selected domain-rule subset, not the whole EasyPrivacy filter language. Normal functional third-party dependencies are permitted. Platform definitions of third party may differ. |

The small source supplements are labeled as gaps rather than presented as complete maintained datasets. Shipping broad production claims for all required categories requires a maintained appropriately licensed category feed, classification review and correction operations, and a stronger mixed-content integration. No paid service was purchased or configured for this milestone.

## Provenance, licensing and reproducibility

The three HaGeZi inputs are pinned to revision `23cdd6516160ae7903b81d762c22d557b808c1e0`; their headers record September 11, 2026, 08:49 UTC. The upstream publishes NSFW, Gambling Mini and Threat Intelligence Mini separately, describes Mini as a size-oriented subset, and documents false positives. This checkout includes the complete source input files, original headers, source digest metadata, upstream source attribution, and the full GPL-3.0 license in `assets/policy/consumer_sources/`. The category-data adaptation is distributed under that license. The existing EasyPrivacy subset retains its separate CC-BY-SA-3.0 attribution/license. See [HaGeZi repository](https://github.com/hagezi/dns-blocklists), its [pinned license](https://github.com/hagezi/dns-blocklists/blob/23cdd6516160ae7903b81d762c22d557b808c1e0/LICENSE), and [EasyPrivacy](https://easylist.to/).

Run `python3 tool/compile_consumer_protection.py` to reproduce the JSON and Dart trust anchor from the committed source files without network access. There is no arbitrary list-import setting. Updating a source, supplement or correction produces reviewable source/data/hash changes and requires a newly signed application build, with native hashes updated to the same generation.

Block List Project and UT1 were evaluated, but not imported. The former's broad drugs list contained medicine/pharmacy domains, which does not match the recreational-commerce-only policy. The latter describes its data as categorization rather than a universal blocking prescription. Bulk importing such categories would create avoidable educational/medical false positives. See [Block List Project](https://github.com/blocklistproject/Lists) and [UT1 categorization/licensing](https://dsi.ut-capitole.fr/blacklists/index_en.php).

## Integrity, freshness and update outages

These states are intentionally different:

1. **No classification match:** the valid consumer baseline permits ordinary navigation; it does not label the page safe.
2. **Stale but validated baseline:** continue enforcing its existing rules. Staleness is detectable after 24 hours and indicates degraded coverage. It does not erase the local data or shut down search because an unrelated catalog expired.
3. **Missing, corrupt, unsupported or uncompiled mandatory baseline:** enter an explicit protection recovery state and prevent protected native browsing. Never replace failed data with an empty list.
4. **Unusable optional/legacy filter pack:** the independent build-pinned baseline remains usable. Optional pack corruption cannot grant an exemption or redefine unknown as engine failure.

The initial baseline is a versioned, application-signed bundle. A separate consumer update repository now verifies purpose-bound Ed25519 manifests and JSON data, keeps active/previous/pending generations transactionally, rejects replay, and requires independent native preparation/activation before changing the browsing policy. It revalidates cached releases at startup and preserves usable local data during update outages. The existing signed optional-filter repository remains separate.

**No production consumer update endpoint or production signing key is configured.** The bundled update-key map is deliberately empty. Configured builds can check at startup with a 24-hour throttle; this milestone does not perform live-session timed hot updates. Synthetic signed-data/cache/native-failure tests cover the workflow, but production-feed operation and physical-device update/restart/rollback acceptance remain release gates. See [signed consumer update configuration and protocol](CONSUMER_PROTECTION_UPDATES.md). Failed native restoration or uncertain rollback enters recovery; missing or corrupt mandatory data cannot be silently bypassed.

Reviewed content expiration still removes expired reviewed content. School edition remains approved-sites-only. Neither expiration nor school mode is silently converted into the consumer blocking model.

## Search coverage and destination transitions

DuckDuckGo documents that searches on `safe.duckduckgo.com` always use strict adult filtering and that `kp=1` is its strict URL parameter. It also warns that inappropriate results can slip through. Wingman uses its ordinary user-facing page with JavaScript; it does not scrape results or upload queries to Wingman infrastructure. The provider necessarily receives submitted queries. There is no application keystroke-query upload or production full-search-URL logging. See [DuckDuckGo Safe Search](https://duckduckgo.com/duckduckgo-help-pages/features/safe-search) and [URL parameters](https://duckduckgo.com/duckduckgo-help-pages/settings/params).

Known provider entry points are normalized before navigation; known alternative search URLs are sent to the strict provider. Query refinements and pagination are retained. `kac=-1` requests disabled provider auto-suggest; native adapters also block the known DuckDuckGo autocomplete endpoint. Standalone bang/lucky shortcuts are rejected, while ordinary punctuation such as `Hello!` and `C++!` is accepted. Search result wrappers are decoded once locally into a destination URI, with no forwarding of wrapper state or credentials. That URI still requires the normal destination policy, as do redirects and user-created windows.

Adult SafeSearch is **not** a gambling, alcohol, drug, nicotine, or threat classifier. Search snippets, ads, recommendations, instant answers and thumbnails may contain those topics before a destination is opened. Unknown search services or website-internal search are not an exhaustive globally enforced SafeSearch namespace. URL checks cannot reliably inspect every result preview or client-side search request. These are coverage gaps, not reasons to claim provider filtering is comprehensive.

The web companion opens the configured strict provider using top-level navigation. After leaving the companion, the host browser owns cookies, content and navigation; native Wingman protection does not carry over. A Flutter web build is not a desktop browser binary.

## Native request coverage

Android WebView's `shouldInterceptRequest` observes only the initial URL of a resource redirect chain. This implementation returns permitted requests to Chromium's normal networking, so a permitted image, script or other subresource can redirect to a blocked domain without another local interception. Main-document navigation and the app's download redirect loop have separate checks, but those do not close this subresource gap. A supported lower-network enforcement layer is still needed before claiming every resource redirect is covered. See the [Android WebViewClient API contract](https://developer.android.com/reference/android/webkit/WebViewClient#shouldInterceptRequest(android.webkit.WebView,android.webkit.WebResourceRequest)).

iOS uses compiled WebKit content rules for resources and a separate decoded-path check for navigation. Passing Dart or native navigation tests does not prove that WebKit resource rules recognize every equivalent encoded path; that platform behavior needs its own fixture evidence. Native rule compilation and browser runtime evidence must be assessed independently from local policy-unit results.

## Mixed content, education and false positives

Neutral ESPN sports and Walmart shopping URLs are permitted without adding them to an exact-document allowlist. They are not globally exempt: ESPN's known betting paths, Walmart's selected alcohol category paths, and prohibited third-party domain matches remain blocked. No finite list of category path names covers every product, ad, recommendation, encoded variant, locale or JavaScript-only route on these services. A URL containing an ordinary topic word is not automatically blocked.

Actual neutral ESPN acceptance on both Android and iOS displayed betting promotion despite the current filters. This is an observed mandatory-category false negative, not merely an untested possibility. The current domain/path rules do not reliably remove promotion embedded in an otherwise ordinary sports page. The platform journey record is maintained in [SEARCH_ACCEPTANCE.md](SEARCH_ACCEPTANCE.md); ESPN remains subject to the same rules, without a brand-wide exemption.

Host/path rules match at hostname and path-segment boundaries, including one decoded/normalized path pass. They do not classify sentence meaning, image pixels or server-side double decoding. Domain suffix matches apply to subdomains, which can produce false positives on mixed services. The NSFW source's `en.academic.ru` dictionary entry is removed from that category during compilation; this does not exempt it from threat rules or grant any blanket brand override. Legitimate medical/educational and recovery sites are tested as ordinary permitted destinations. Corrections must be reviewed upstream/in the signed release; there is no override button for users.

## Verification boundary

The regression suite checks ten-plus ordinary domains, medical/educational destinations, all six synthetic mandatory categories, subdomain/trailing-dot matching, encoded paths, mixed-host path boundaries, additive restrictions, non-tracker dependencies, corrupted asset rejection, stale-but-usable behavior, independent catalog expiry, and separate school scope. Fixtures under `*.protection.test` are synthetic and cause no visits to real prohibited sites.

These are policy tests, not claims that each live website journey passed. Platform rendering, native request coverage, TLS, redirect/new-window behavior, cookie/private isolation, and search-to-site runtime evidence are recorded separately in `SEARCH_ACCEPTANCE.md` and `CONSUMER_BROWSER_RECOVERY.md`. No test count substitutes for those runtime results.
