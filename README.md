# Wingman Browser

**We've got your back, not your data.**

**Built for discovery. Designed with boundaries.**

Version **0.11.0+11** adds a shared live-content backend and local feed preferences,
cache, saved publisher links and explicit Launchpad pinning. NASA, NOAA and USGS
supply current English science, technology and environment coverage. Publisher
articles open in the existing native consumer browser; the web companion opens
them in the host browser. Bundled articles remain labelled evergreen/offline.
No production feed service or broad-news license has been deployed or purchased.
See [Live content acceptance and commands](docs/LIVE_CONTENT_ACCEPTANCE.md),
[Architecture](docs/LIVE_CONTENT_ARCHITECTURE.md),
[Source rights](docs/CONTENT_SOURCES_AND_RIGHTS.md), and
[Operating costs and approvals](docs/CONTENT_OPERATING_COSTS.md).

Version **0.10.0+10** restores consumer browsing through Android System WebView and iOS WKWebView while preserving Wingman's existing interface, Launchpad, Spaces and local tools. Ordinary search opens DuckDuckGo's normal Strict experience; permitted result destinations do not require inclusion in the reviewed catalog. JavaScript, forms, first-party storage and native navigation are enabled behind local category/threat controls. The web companion submits search by leaving for the strict provider in the host browser.

This recovery is not production-complete. Protection coverage, native interception limitations, incomplete update infrastructure and measured device acceptance are documented in [Consumer recovery](docs/CONSUMER_BROWSER_RECOVERY.md), [Search acceptance](docs/SEARCH_ACCEPTANCE.md), [Browser engine contract](docs/BROWSER_ENGINE_CONTRACT.md) and [Protection coverage](docs/PROTECTION_COVERAGE.md). A permitted destination is not a claim of verified safety. School allowlisting remains separate; users cannot disable the consumer mandatory baseline.

## Historical 0.9 pilot

The following pilot description is retained as historical context. Its exact-document and scriptless consumer requirements are superseded by the 0.10 recovery documents above.

Version **0.9.0+9** adds direct DuckDuckGo search with publisher-fixed Strict adult filtering on supported Android and iOS builds, without a paid search API. It displays the first, text-only results page; result links still require an independently reviewed destination. The visual-browsing pilot continues to display six exact live documents with permitted images, styles and fonts. Launchpad, local photography, Home customization, local search, 18 original reviewed articles, Spaces, reading tools, themes and private sessions remain available. There is no account requirement, advertising SDK or new Wingman cloud service.

**General-purpose browsing across desktop, iOS and Android remains unfinished.** This release is not a completed Firefox replacement or a guarantee that every live image and sentence meets every content rule. DuckDuckGo's adult filter is separate from Wingman's six-category policy: search snippets and advertisements are not fully classified against those rules, and provider filtering can miss content. Reviewed URLs can also serve changed content; there is no per-image or automatic six-category text classifier. See [Strict search](docs/STRICT_SEARCH.md) for v0.9 search behavior and [Live browsing status](docs/LIVE_BROWSING_STATUS.md) for the existing destination pilot.

Reviewed-content restrictions have no switches, exceptions, PIN bypasses or private-mode exemptions. Search has a separate fixed provider filter and clearly disclosed coverage limits. Unsupported destination addresses and operations stay closed; saving a shortcut cannot approve a website. Additional restrictions can remove access but cannot grant new access or lower Strict adult filtering. Live eligibility, including search, also requires current policy, intact build-pinned assets and an available native capability. The live scope expires at **00:00 UTC on October 11, 2026**; there is no automatic updater or unrestricted fallback.

## Reviewed website scope

| Destination | Supported scope |
| --- | --- |
| NASA | Moon facts, Moon overview, Moon exploration and Earth facts: four exact documents with listed passive assets |
| Wikipedia | The Chicago Bulls history article and its listed passive assets |
| Adafruit | The half-size breadboard product 64 page and its listed passive assets; information and photographs only |
| ESPN and Walmart | Disabled candidates; mixed betting, retail, advertising or recommendation content has not met the review boundary |

No whole destination domain is approved. Scripts, forms, sign-in, checkout, uploads, downloads, video and interactive embeds are unsupported. Unreviewed links and changing resource URLs may leave a page incomplete. Most ordinary search-result destinations remain unavailable under this six-document scope. The web companion runs in desktop browsers without rendering live websites or filtering the host browser. Native desktop builds and engines are not implemented. See the exact scope, sources and licensing in [Live browsing policy](docs/LIVE_BROWSING_POLICY.md).

Android uses an independently gated WebView with mediated HTTPS requests. The iOS 18.4+ pilot uses WKWebView with compiled resource rules and nonpersistent website storage; older iOS retains the offline app. Their guarantees differ: iOS does **not** provide Android's per-subresource response MIME/body inspection or streamed byte limits. Neither mechanism classifies future page content. The retired unrestricted engine APIs remain closed; the pilot uses a separate protected bridge.

## Strict web search

Use the native address/search field, choose **Web**, and submit. Wingman builds `https://safe.duckduckgo.com/lite/?q=<encoded-query>&kp=1` and opens the provider's ordinary page directly. Only the first text results page and one fixed stylesheet are permitted. Search images, pagination, provider forms and scripts are unavailable; enter each new query in Wingman's field. No scraping service, private search API, paid search subscription or custom endpoint is configured.

**Settings → Search** explains the fixed provider filter and current capability. **Protection → Additional boundaries → Disable web search** can remove access while keeping local library search. Private tabs inherit that setting without changing the owner's preferences. There is no Moderate/Off control. Changing the publisher baseline requires code changes, review and an app release; Firebase or an admin setting cannot lower it.

Submitted queries and the connection's IP address reach DuckDuckGo. Typing makes no remote-suggestion request. Wingman does not persist query history or allow search pages to be pinned; search terms remain temporary session state. Reloading, revisiting or resuming a search tab can request that submitted query again. The provider may display advertisements and applies its own privacy policy. Wingman does not add parameters that remove DuckDuckGo branding or advertising. [Strict search documentation](docs/STRICT_SEARCH.md) records the provider sources, privacy limits and enforcement design.

## Preview

From this repository, with Flutter installed:

```sh
flutter pub get
flutter devices
flutter run -d <android-or-ios-device-id>
```

For the student packaging choice, which retains the same mandatory policy:

```sh
flutter run -d <device-id> --dart-define=WINGMAN_EDITION=student
```

For the local web companion:

```sh
flutter build web --no-web-resources-cdn --no-tree-shake-icons
python3 -m http.server 8791 --bind 127.0.0.1 --directory build/web
```

Open [the local preview](http://127.0.0.1:8791/). Use a native target to try eligible live pages. Native code and bundled-policy changes require stopping and rebuilding; Flutter hot reload alone cannot activate them. The HTML in `Wingman_UI_Design_Handoff/` is reference material; `lib/main.dart` is the application.

## Make Home yours

Use **Add** and **Edit** in Your Launchpad to save and organize local tools, articles and website records. Eligibility is checked again when opening a website. A saved unavailable candidate stays unavailable; its name, folder or category is never an exception. Optional Sports, Shopping and Learning collections follow your choices, with no interests inferred from browsing.

Home customization saves section order, density, collections and an optional Earthrise, Forest or Creative desk photograph. Plain Home remains the default. Artwork and discovery previews are bundled locally, with readable captions and a **Photo credits** screen; no remote favicon, preview, recommendation or image-generation service is used. Image licenses and provenance are in [Photo credits](assets/discovery/LICENSES.md).

Normal consumer preferences persist locally. Private customization uses separate temporary feature state and cannot pin private activity into normal Home. Student/unknown editions keep reviewed-session saves in memory. These application-state boundaries are separate from native website storage: Android disposable profiles can use temporary disk files; iOS uses a nonpersistent data store. Private mode does not hide your IP address from a requested website or erase device backups and external files.

**Menu → Wingman tools** opens Before You Commit, Spaces & Finish Mode, and Hand It Over. **Menu → Protection & settings** contains the protection explanation, Trust Receipt and a local compatibility report. Reports and clipboard exports are previewed; nothing is automatically submitted. Hand It Over remains a static public-text handoff without a website renderer or owner credentials. See [Handoff security](docs/HANDOFF_SECURITY.md).

## Privacy and operating cost

Opening an eligible page contacts that website and its permitted asset hosts directly; submitting web search contacts DuckDuckGo with the query. Wingman does not upload the browsing URL, query or page content to a Wingman server, Firebase, an analytics SDK or an AI classifier. Websites, the search provider and network providers still observe ordinary connection metadata; native platform security services and private mode are not a promise of anonymous traffic.

Policy decisions, the supported EasyPrivacy subset, artwork and application preferences are local. No Firebase/GCP project, paid API, deployment or recurring Browser service was added; search introduces no Wingman per-query cloud charge. Read-only cloud inventory found an existing Wingman-named project serving unrelated applications; it was left unchanged. Existing account spending was not audited. App-store distribution, maintenance, policy review, updates and connectivity can still have costs. See [Cloud cost plan](docs/CLOUD_COST_PLAN.md) for the inventory and a future static-update proposal with explicit cost limits and privacy tradeoffs.

## Validation and maintenance

For **v0.9**, the full host suite passed **686 tests with two optional skips**, the analyzer reported no issues, and all three native/Dart live-manifest pins matched. Native search bridge fixtures passed normal/private sessions, and the actual app search flow passed on both platforms. A controlled WKWebView test also passed its resource, iframe and redirect checks; see [Strict search validation](docs/STRICT_SEARCH.md#validation) for the measured scope and remaining release work.

The earlier v0.8 host suite passed **528 tests with two optional skips**, and native reviewed-page journeys plus the actual-app pin/revocation flow passed. See [Protected visual browsing QA](docs/PROTECTED_VISUAL_BROWSING_QA.md) for that milestone's commands, observations and limits. Fresh native visual sign-off remained open because the Mac was locked during capture attempts. A production store release, physical-device security audit, desktop live engine and complete whole-web classification are not delivered by this release.

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter test integration_test/strict_search_native_test.dart --no-uninstall -d <device-id>
flutter test integration_test/protected_live_native_test.dart --no-uninstall -d <device-id>
flutter test integration_test/protected_live_app_test.dart --no-uninstall -d <device-id>
```

The bridge fixture exercises independent request denials, supported public journeys and renderer cleanup. The actual-app fixture covers address entry, a completed-page Launchpad pin, reopening in a new tab and additional-restriction revocation. See [Protected visual browsing QA](docs/PROTECTED_VISUAL_BROWSING_QA.md) for measured results. Public sites and network conditions can change; an enabled manifest entry alone is not proof of a passed device run. `--no-uninstall` preserves the installation. Native integration tests also require the installed target/toolchain; consult individual fixtures before running them against personal state.

The signed offline article catalog separately expires on March 10, 2027 and uses a development signing key whose private seed is outside Git. The live network scope is pinned into the reviewed application build; it is not a remotely signed production publisher. Renewal requires review and a rebuilt app. See [Content policy](docs/CONTENT_POLICY.md) and [Live browsing policy](docs/LIVE_BROWSING_POLICY.md).

The [screen registry](docs/ui/SCREEN_REGISTRY.md), [design system](docs/ui/DESIGN_SYSTEM.md) and [Launchpad specification](docs/ui/LAUNCHPAD_SPEC.md) explain the existing product. Previous [Launchpad QA](docs/ui/LAUNCHPAD_QA.md), [signature status](docs/SIGNATURE_FEATURES_STATUS.md), [privacy architecture](docs/PRIVACY_ARCHITECTURE.md), [platform capabilities](docs/PLATFORM_CAPABILITIES.md) and [release readiness](docs/RELEASE_READINESS.md) record earlier milestones. Their blanket no-live-network/no-renderer statements were superseded by the v0.8 destination pilot; blanket no-web-search statements, including those in its status report, are superseded by [v0.9 Strict search](docs/STRICT_SEARCH.md). Historical test totals are not current release acceptance evidence. Phase 1–3A documents and [the earlier README](docs/history/README_PHASE3A.md) remain historical.
