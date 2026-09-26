# Wingman Search and Ads traffic evidence

This is controlled client-boundary evidence, not a packet capture of every process on a phone. `test/ads/client_traffic_test.dart` uses the production native Search, Ads and shared-snapshot clients, their controllers, and an actual loopback HTTP recorder. Its socket factory rejects nonlocal destinations before DNS. The fixture gateway does not call Brave or a merchant. The captured origin and every request's method, path, body field names and header names are in `work/brave-evidence/client-traffic-matrix.json`. Query, grant, delivery-token and page-ID values are deliberately omitted from that artifact.

The real Android/iOS app tests call production `main()` and use the separate development gateway. They can also perform the pre-existing public RSS refresh. The successful client recorder therefore does **not** establish that actual app launch, idle Home, or native background/resume has zero network traffic. Existing RSS, signed protection updates, and explicitly approved publisher media remain separate traffic paths. No Brave live-spend, whole-device traffic audit, physical-device latency target, or production launch approval is implied.

**Reproduce the recorder**

```sh
flutter test --no-pub test/ads/client_traffic_test.dart \
  --dart-define=WINGMAN_TRAFFIC_CAPTURE=true
```

The maintained six-category corpus is `test/fixtures/wingman_search_benchmark.json`; it is test data, not a shipped asset or retained consumer history. The recorder has a fresh ephemeral origin per run. Below, `G` means that validated gateway origin (`fixtureOrigin` in the capture). In production the Search/Ads origin comes from the approved HTTPS `WINGMAN_SEARCH_URL`; the shared snapshot origin is separately configured by `WINGMAN_FEED_URL`.

| Field set | Exact request body keys |
|---|---|
| S: submitted Search | `query`, `kind`, `country`, `searchLang`, `uiLang`, `offset`, `context` |
| A: first Search ad decision | `placement`, `context`, `contextToken`, `foreground` |
| P: New Tab/news ad decision | `placement`, `context`, `foreground`, `pageId`, `country`, `language`, `section`, `organicCount`, `sponsoredCount`, `slotIndex` |
| E: ad event | `deliveryToken`, `kind`, `foreground`, `visiblePermille`, `visibleMs`, `explicitAction` |

An optional second Search unit additionally sends `slotIndex: 1`. It requires the owner-disabled app experiment, the signed server grant, and at least three initial organic results. The current recorder and actual fixture app leave that experiment disabled; the separate unit matrix tests both gates. Neither `pageId` nor an event token is a consumer identifier, and neither is persisted by the frontend.

| Action/context | Search/Ads/shared-snapshot request | Boundary evidence and limits |
|---|---|---|
| Initial construction, typing | None | Recorder sees no dispatch on construction; actual shell tests verify entering unsubmitted text makes no Search call. This is not a claim that production startup has no RSS/update traffic. |
| Normal New Tab with ads enabled | One `POST G/v1/ads/decision`, P, `placement=newtab`, `section=untargeted`, slot 0 | Repeated load/idle makes no further decision. Default ads-off and private Home produce no placement request in actual shell tests. |
| Submit normal All | One `POST G/v1/search`, S, `kind=web`, `context=normal` | No query in request URL. No remote suggestion call. One request per explicit benchmark submission; retry/fallback is absent. |
| Switch Search to News | One `POST G/v1/search`, S, `kind=news` | Existing Search sponsorship is discarded. Search News has no client ad path. |
| Shared news refresh | `GET G/v1/snapshot.json`, no body/query | Recorder verifies `If-None-Match` and `If-Modified-Since` validators and a 304 response. A shared feed contains no submitted search text or user topic query. |
| Discover topic selection | Existing feed filtering stays local; an unused eligible slot can send P to `G/v1/ads/decision` | Recorded science decision includes only coarse section and finite inventory counts. Changing the already-consumed slot to technology does not refresh it. Health/other sensitive sections cannot allocate that slot. Controller/feed tests separately cover topic filtering and no per-reader Brave scheduling. |
| Organic Search completed | Optional `POST G/v1/ads/decision`, A | Organic results are available before ad dispatch. The opaque grant, not raw query text, goes to the Ads endpoint. |
| Actual paint signal | `POST G/v1/ads/event`, E, `kind=render` | Recorder verifies event fields. Paint does not claim a viewable impression. Actual widget tests provide the paint/viewport signal. |
| Visible impression signal | `POST G/v1/ads/event`, E, `kind=view` | A 499-permille signal is rejected locally. The qualifying signal is at least 500 permille for 1,000 continuous milliseconds. Widget tests independently verify clipping, interrupted scrolling, foreground state and timer reset. |
| Deliberate sponsor click | `POST G/v1/ads/event`, E, `kind=click`, `explicitAction=true` | An approved HTTPS landing URL is returned only after the event. The client does not fetch it. All recorded sockets still terminate at G, and a repeated click emits no second event. Actual app integration does not activate a merchant link. Protected navigation is tested separately. |
| Private submitted search | One `POST G/v1/search`, S, `context=private` | No ad allocation; search submission still reaches the configured gateway. Private mode is not anonymity from the gateway/provider. Actual shell/native tests verify no prior normal ad or result leaks into private Home. |
| Managed/student search or ads | None | Managed controller rejects before dispatch. Product edition policy disables consumer Search and ad surfaces outside the consumer edition. |
| Background, resume | No ad request while ineligible; resume alone emits no new decision | Recorder exercises the controller eligibility boundary; actual widgets reset visibility timing/cancel late callbacks. Existing native RSS scheduling is outside this recorder. |
| Session discard/logout equivalent | None | Disposing transient Search/Ads state emits no identity/logout event. Wingman Search/Ads has no consumer account login API. |
| Ad service returns 503 | Decision fails closed; no fallback request | Organic results remain available, with no ad placeholder or merchant contact. |

Native POST header names observed are `accept`, `accept-encoding`, `cache-control`, `content-length`, `content-type`, `host`, and the runtime `user-agent`. The body is UTF-8 with exact Content-Length; cache control is `no-store`. The test rejects `authorization`, `cookie`, `referer`, `forwarded`, `x-forwarded-for`, and `x-real-ip`. Shared GET adds its two conditional validator headers. These are app-to-gateway observations, not an assertion that a network peer cannot see a source IP.

The web client uses Fetch with credentials omitted, redirect errors, no-store cache and no-referrer policy. Browser-supplied headers such as Origin and User-Agent can differ from this native capture. Web UI evidence verifies flows and console health; a comprehensive browser network capture has not been claimed here. The browser or reverse proxy must still be configured not to log query/body/token data. The current text-only ad renderer ignores image paths and never embeds third-party scripts, pixels, merchant favicons or remote creative assets.

Live gateway-to-Brave traffic, when explicitly enabled, is server-only HTTPS to `api.search.brave.com/res/v1/web/search` or `/res/v1/news/search`. The transport uses `q`, `country`, `search_lang`, `ui_lang`, `safesearch=strict`, `count`, and `offset`; Web additionally uses `result_filter=web` and `text_decorations=false`. The server adds its subscription credential and fixed service headers. Client cookies, IP-forwarding headers and identifiers are not forwarded. These fixed transport shapes are covered by backend contract tests; this fixture recorder makes no Brave call.

**Synthetic benchmark interpretation**

Twenty sequential requests per category exercise real Dart HTTP, DTO parsing and controller completion against a loopback synthetic response. A stopwatch ends when controller results become available; no frame raster time, WAN, provider execution, rights review, live relevance or physical-device work is included. The fixture supplies a fixed result rather than grading retrieval quality. All 120 corpus submissions succeeded in the recorded run. Its zero observed errors and small local timings cannot establish the proposed live service targets.

| Category | Maintained synthetic input | Samples | Fixture median / p95 | Manual live acceptance still required |
|---|---|---:|---|---|
| navigational | Python documentation | 20 | 5.393 / 14.162 ms | Official destination is prominent and resolves correctly. |
| local-intent | public libraries near Chicago | 20 | 4.616 / 7.736 ms | Useful local results without requesting precise location. |
| educational | how lunar phases work | 20 | 5.592 / 8.474 ms | Explanatory results with clear source attribution. |
| product | best office chairs | 20 | 5.233 / 10.608 ms | Organic quality independent of sponsorship; only reviewed commercial context is eligible. |
| current-news | NASA mission updates | 20 | 7.234 / 10.615 ms | Publisher attribution, dates only when known, and safe outbound navigation. |
| sensitive-help | how to find mental health support | 20 | 5.995 / 12.041 ms | Helpful results remain available; no advertising grant or sensitive-interest targeting. |

Proposed live targets remain **unverified**: useful results within 2 seconds at p95 on a defined network, fewer than 1% query failures, no material layout shift, and roughly one provider request per requested page. Ad decision/event requests and rendering are outside the awaited organic client request. Local eligibility checks and context-token signing still run inside the gateway search handler; tests establish completion and failure isolation, not a universal zero-latency guarantee. Any future live study must state device, build, network, corpus revision, sample count, provider settings, billing ledger deltas and error treatment. It must not reuse these fixture timings as Brave production performance.

The actual app fixture runs and screenshots are complementary evidence. They should be reported per platform and attempt, including any initial failure and repair, rather than substituting host tests for a successful native run. No user-retention experiment, incremental net contribution result, demand acceptance, or paid production ad was measured by this benchmark.

The native fixture harness now keeps the Search/News/private and Sponsored/disclosure/private scenarios in one production `main()` lifecycle and one `testWidgets` error zone. Flutter's global engine/frame callbacks outlive individual test cases; restarting the full app in a second test zone can cause an old asynchronous socket error to be reported against the completed first test. The composite retains every assertion and original-tab cleanup, emits both scenario markers, and reports **one composite test**. It does not catch or suppress test errors or lengthen the client timeout. The independent RSS cancellation regression exercises real `HttpClient` behavior, including cancellation from another error zone.
