# Protection providers and boundaries

Reviewed September 10, 2026. Wingman separates security threats, voluntary content categories, and tracking resources. A provider's coverage in one column does not establish coverage in another. Nothing here promises complete detection.

| Provider | Intended responsibility | Current integration boundary |
| --- | --- | --- |
| Android System WebView Safe Browsing | Known malicious, phishing and unwanted-software resources supported by the installed provider | Preserve engine protection and TLS validation. Availability/version varies; it does not classify alcohol, adult content or other chosen lifestyle categories. |
| WKWebView fraudulent-site warnings | WebKit warnings for suspected fraudulent content including malware/phishing | Enabled in native configuration. WebKit manages its service behavior; Wingman does not equate this with Google's Web Risk API or lifestyle classification. |
| Wingman local Guard data | Explicit domain rules, selected lifestyle/focus categories, support exceptions and test threat fixtures | Local navigation decision; no destination lookup at a Wingman server. A starter pack is not broad real-world threat intelligence. |
| EasyPrivacy-derived tracking starter | Seven third-party analytics/session-replay domain rules | Separate resource blocking on native browsing views. No blanket ad blocking, first-party site blocking, replacement ads or processing of Wingman's Google ad view. |
| Google Cloud Web Risk | Potential future additional malware/social-engineering/unwanted-software intelligence | **Not active.** No API key, service account, API client, downloaded Google threat database or per-navigation request is configured. |

Android recommends keeping Safe Browsing enabled. Its behavior is supplied by the installed WebView provider and can involve Google's service, independently of Wingman's own request code. On current WebView versions initialization is automatic; older targets require supported initialization/readiness handling. Android usage-metrics opt-out is separate from Safe Browsing and does not disable every crash report. [Android browser security behavior](https://developer.android.com/develop/ui/views/layout/webapps/managing-webview), [initialization API](https://developer.android.com/reference/android/webkit/WebView#startSafeBrowsing(android.content.Context,android.webkit.ValueCallback)), [WebView reporting privacy](https://developer.android.com/develop/ui/views/layout/webapps/webview-privacy)

Wingman handles supported Android threat callbacks with `backToSafety(false)`: the request is blocked without enabling the callback's optional reporting. This is separate from baseline platform safety checks. [Android response API](https://developer.android.com/reference/android/webkit/SafeBrowsingResponse#backToSafety(boolean))

Apple describes `isFraudulentWebsiteWarningEnabled` as warnings for suspected fraudulent content, including malware and phishing. The public property does not establish exact network endpoints, providers, retention, or complete threat coverage for every OS/region. Do not infer those guarantees from a Boolean setting. [Apple API](https://developer.apple.com/documentation/webkit/wkpreferences/isfraudulentwebsitewarningenabled)

## Tracker data and licensing

The bundled selection is [starter.json](../assets/guard_tracking/starter.json), adapted from EasyPrivacy at commit `c55f475954a28426e8884a6c8d92099d23366536`. It contains `fullstory.com`, `heapanalytics.com`, `hotjar.com`, `hotjar.io`, `mixpanel.com`, `mouseflow.com`, and `scorecardresearch.com`.

Each source rule is precisely `||domain^$third-party`; Wingman additionally excludes main-frame navigation. No upstream resource-type restriction was broadened. The data is a small starter, not a converted copy of all EasyPrivacy. It deliberately omits broad ad-server hosts and rules requiring syntax the native adapters do not implement. Temporary per-site tracking exceptions must remain independent of Guard categories, malware and TLS policy.

EasyList's authors offer GPL 3+ or CC BY-SA 3+. Wingman selects **CC BY-SA 3.0** for this separate data adaptation, includes the license and attribution, identifies the changes, and preserves ShareAlike obligations for adaptations of the data. This does not claim authors' endorsement. See [attribution and exact provenance](../assets/guard_tracking/ATTRIBUTION.md) and [author licensing statement](https://easylist.to/pages/licence.html).

Disconnect and DuckDuckGo's tracker blocklists were evaluated but not copied: both publish a noncommercial ShareAlike license and require a separate agreement for commercial use. No such agreement is claimed. [Disconnect repository](https://github.com/disconnectme/disconnect-tracking-protection), [DuckDuckGo repository](https://github.com/duckduckgo/tracker-blocklists)

WKContentRuleList compiles JSON rules into an efficient engine format. The native adapter should compile/cache per list version, use explicit third-party conditions and precise domain patterns, and attach only to browsing views. Do not create a JavaScript bridge exposing every resource just to count blocks. If a platform cannot provide trustworthy counts, show that limitation rather than invented totals. [Apple rule-list API](https://developer.apple.com/documentation/webkit/wkcontentrulelist), [WebKit domain-pattern guidance](https://webkit.org/blog/4062/targeting-domains-with-content-blockers/)

## Web Risk evaluation

The **Lookup API** sends the requested URL to Google for each uncached lookup. It is not selected for ordinary Wingman browsing. The Evaluate and Submission APIs also transmit URLs and may trigger processing/crawling or sharing described in Google's service terms; they are not a substitute for silent local classification. No report is submitted to these services by Phase 2. [Lookup API](https://docs.cloud.google.com/web-risk/docs/lookup-api), [Evaluate API](https://docs.cloud.google.com/web-risk/docs/evaluate-api), [service terms, Web Risk](https://cloud.google.com/terms/service-terms)

The **Update API** is the candidate for a future reviewed integration: periodically download compressed SHA-256 prefixes; canonicalize and hash URLs locally; check the indexed local database; on a prefix match, consult the positive/negative cache and request matching full hashes only when needed. A prefix confirmation exposes a hash prefix plus request/network metadata to Google, not the plaintext navigation URL. Hashing alone must not be marketed as anonymity. Maintain response checksums, version tokens, update backoff and Google's cache expirations. [Update API](https://docs.cloud.google.com/web-risk/docs/update-api), [cache requirements](https://docs.cloud.google.com/web-risk/docs/caching)

This design is not implemented merely because it is documented. Before activation, select a permitted mobile credential/authorization model with Google; an unrestricted billing key or service-account credential must never ship in the app. A Wingman prefix broker could conceal a client credential but would receive match timing/prefixes and require its own privacy, retention, abuse, cost and availability review. Avoid that additional service unless it provides a demonstrated benefit over native protections.

Google's current terms require appropriate attribution and a reliability caveat for warnings based on its lists, with freshness requirements tied to response expiration (or the stated fallback when no expiration is provided). A general offline promise for Wingman's own packs does not override Google's conditions. Verify the applicable contract and licensing before caching, proxying or redistributing Google data. No Google threat data is included in Wingman's distributable packs, and no redistribution right is assumed. [Web Risk service terms](https://cloud.google.com/terms/service-terms)

Cost scales with update cadence and confirmed prefix matches, not a new cloud call for every visited page. Future sizing must model actual list sizes, cache hit rates, match frequency and current pricing. No forecast revenue, billing activation or free-at-scale assumption is made. [Current Web Risk pricing](https://cloud.google.com/web-risk/pricing)

For the exact signed manifest/index contract and bundled category provenance, see [Guard filter packs](GUARD_FILTER_PACKS.md). Measured limits and benchmark scope are in [Guard performance](GUARD_PERFORMANCE.md).
