# Protected visual browsing: v0.8 status

Source review: **September 11, 2026**. This document describes the new native pilot and supersedes earlier milestone statements that Wingman never creates a website renderer or makes browsing requests. The 528-test host suite, both platforms' live journeys and actual-app pin/revocation flows have passed. Fresh native visual sign-off and production release acceptance remain open; see [Protected visual browsing QA](PROTECTED_VISUAL_BROWSING_QA.md) for the evidence and limits.

## What this milestone adds

A separate protected native bridge can render reviewed public HTML with listed images, style sheets and fonts. The existing offline library and local tools continue to work independently of live-page availability. Home gains optional locally bundled photography, credits and caller-supplied discovery cards. Plain Home is the default; private customization is isolated from the normal owner's saved preferences.

The live manifest enables **six exact documents** across three sources:

- NASA: [Moon facts](https://science.nasa.gov/moon/facts/), [Moon overview](https://science.nasa.gov/moon/), [Moon exploration](https://science.nasa.gov/moon/exploration/) and [Earth facts](https://science.nasa.gov/earth/facts/).
- Wikipedia: [Chicago Bulls history](https://en.wikipedia.org/wiki/Chicago_Bulls).
- Adafruit: [half-size breadboard, product 64](https://www.adafruit.com/product/64), for product information and photographs only.

ESPN Bulls and Walmart notebooks remain disabled candidates. The Wikipedia and Adafruit entries are explicitly separate destinations; they do not relabel or silently replace an ESPN or Walmart shortcut. Other sites, paths, queries and unlisted assets are not implicitly approved. Saving a Launchpad record or choosing a collection never widens native access. Additional restrictions can further remove eligible entries.

The exact reviewed source scope and its limitations are in [Live browsing policy](LIVE_BROWSING_POLICY.md). Native public responses can vary, fail, redirect or change their resource URLs. Missing optional assets are allowed to remain missing; there is no broad-host fallback to repair a page.

## Enforced scope and its limits

The manifest is bundled and SHA-256 pinned in Dart and independently in Kotlin/Swift. Its review window is **September 11, 2026, 00:00 UTC through October 11, 2026, 00:00 UTC, exclusive**. Missing/corrupt data, expiry, unsupported native capability or unavailable mandatory policy closes live eligibility. New scope requires a reviewed app build. No automatic policy updater or production publishing/key-rotation service is enabled.

| Boundary | Android | iOS |
| --- | --- | --- |
| Renderer | Platform WebView; independent native scope validation | WKWebView; independent native scope validation |
| Passive requests | Renderer-owned network loads disabled; default-deny mediated HTTPS path, exact reviewed URLs and GET only | Compiled default-deny WebKit content rules with exact scoped exceptions |
| Response checks | Fetcher rejects redirects and validates success status, permitted MIME and bounded streamed bytes before returning a response | Navigation response checks cover the main document; **no equivalent pre-consumption inspection of every subresource MIME/body or streamed byte limit** |
| Page behavior | Website JavaScript and automatic windows disabled; unsupported forms, media, downloads and permissions denied | Website JavaScript and automatic windows disabled; unsupported navigation/actions denied |
| Website data | Disposable cookie-free profiles; temporary disk use is possible, with teardown/startup cleanup gates | Nonpersistent WKWebsiteDataStore selected before creating each website view; cookie blocking rules |
| Resource diagnostics | Local fetch-path counts; not a complete packet capture | Subresource response and byte counts are unavailable, not zero |
| Availability | Native capability and private-profile support are checked before use | iOS 18.4 or newer; native capability and rule installation are checked before use |

All enabled iOS rule lists are prepared from the public bundled catalog at startup, independent of which sites are visited. A private visit does not trigger site-specific compilation in the persistent WebKit rule store. Android teardown awaits explicit browsing-data and cookie purges; its WebView provider retains empty disposable profile names until the next process startup. A failed purge keeps the native live gate closed.

The iOS bridge includes a fixed image-completion probe used by the native fixture for test evidence; it does not enable website scripts or accept arbitrary script text. Main-document navigation callbacks are not a claim that all rejected redirect traffic was prevented before network activity. Platform-specific behavior still requires device evidence.

**Request review is not content classification.** The manifest pins permitted request addresses, not the future HTML or image bytes returned there. There is no per-image classifier, no complete six-category text classifier and no cloud service reviewing every response. An allowed URL can later serve different material. Locked policy settings do not establish perfect detection of gambling, adult content, alcohol, drugs, nicotine or malicious content. This pilot must not be marketed as guaranteed safe whole-web browsing, a production Firefox replacement or a completed managed-school deployment.

Scripts, general web search, arbitrary websites, account sign-in, form submission, checkout, uploads, downloads, video and interactive embeds remain outside support. Web/desktop builds retain the local companion; they cannot enforce policy in the host browser. The retired unrestricted engine APIs remain disabled.

The bundled privacy layer is **2,501 supported third-party domain rules** adapted from a pinned EasyPrivacy source under CC BY-SA 3.0. It only subtracts request permission; it is not the entire EasyPrivacy engine, a comprehensive threat feed or a prohibited-content classifier. The license and modifications are available in the app's Open-source licenses screen and the policy document.

## Privacy and zero-new-cloud operation

Opening a permitted live page makes direct HTTPS requests to its website and approved resource hosts. Those hosts can observe connection metadata; this is not a VPN or anonymity service. Native platform security features may use their own provider mechanisms. No new Wingman endpoint receives browsing URLs, queries, page bodies, image bytes, screenshots or behavior profiles for classification or analytics.

Launchpad and Home choices are saved locally. Saving a website record does not upload it; opening the site necessarily contacts the site. Private application state is separate and temporary, but Android profile files, OS state, backups, keyboards and other applications must not be described as universally memory-only or securely erased. Website-view lifecycle cleanup does not promise device-wide forensic erasure.

Three bundled Home photographs total **164,819 bytes**. They load from assets without remote previews, inferred recommendations or recurring image-generation requests. Their source attribution and license records are in [Photo credits](../assets/discovery/LICENSES.md) and the local credits screen.

This milestone creates **no new Firebase/GCP resources, paid API subscription or recurring Wingman Browser service**. Existing authenticated cloud access was inspected read-only. The Wingman-named project already serves unrelated applications, which were not modified. Existing account spend was not audited and is not claimed to be zero. App distribution, local bandwidth and ongoing review/maintenance still cost money or time.

For future freshness requirements, the [Cloud cost plan](CLOUD_COST_PLAN.md) proposes common signed static update artifacts, bounded checks and explicit provider logging/cost controls. That proposal is not deployed. There is no per-page cloud classifier, browsing proxy, Firebase database, account SDK or remote artwork service in this pilot. An alerts-only cloud budget is not a spending cap; the cost plan records the narrower current provider options and their limits.

## Validation and remaining release work

The complete host suite passed **528 tests with two optional skips**, and analysis and the web build passed. The new suites cover manifest validity, policy decisions, native-event ownership, local preference isolation, private boundaries and responsive discovery UI. The web companion's actual photo-to-article flow was inspected without changing saved customization.

On dedicated Android 16/API 36 and iOS 26.3 simulators, `integration_test/protected_live_native_test.dart` passed seven normal/private page opens, JavaScript-disabled and image checks, independent native denials and lifecycle teardown. `integration_test/protected_live_app_test.dart` passed actual startup, address entry, completed-page pinning, reopening in a new tab, restriction revocation and exact fixture cleanup on both. A real WKWebView XCTest loaded its allowed image and percent-encoded-query CSS while forbidden resource and redirect targets received zero requests. These are measured local outcomes, not guarantees about future website responses.

Remaining release acceptance includes fresh native visual review on both platforms, physical-device lifecycle/network checks, current policy renewal procedures and production build/signing validation. The Mac's locked screen prevented new native captures after the fixed-user-agent styling correction; image/style counters do not replace visual sign-off. iOS response-observability limits and absent classifiers remain product limitations even when a fixture passes. Earlier no-renderer tests, screenshots, test totals and release reports remain evidence for their recorded versions only.
