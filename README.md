# Wingman Browser

**We've got your back, not your data.**

**Built for discovery. Designed with boundaries.**

Version **0.8** adds a protected visual-browsing pilot on Android and iOS, plus local photography and Home customization. Eligible native builds can display a small set of live documents with their permitted images, styles and fonts. Launchpad, local search, 18 original reviewed articles, Spaces, reading tools, themes and private sessions remain available. There is no account requirement, advertising SDK or new Wingman cloud service.

**This is a bounded pilot, not a general-purpose Firefox replacement or a guarantee that every live image and sentence meets every content rule.** There is no per-image or automatic six-category text classifier. Reviewed URLs can serve changed content. The current request controls, platform differences, privacy boundaries and validation status are recorded in [Live browsing status](docs/LIVE_BROWSING_STATUS.md).

Core restrictions have no switches, exceptions, PIN bypasses or private-mode exemptions. Unsupported addresses and operations stay closed; saving a shortcut cannot approve a website. Additional restrictions can remove access but cannot grant new access. Live eligibility also requires current policy, intact build-pinned assets and an available native capability. The live scope expires at **00:00 UTC on October 11, 2026**; there is no automatic updater or unrestricted fallback.

## Current live scope

| Destination | Supported scope |
| --- | --- |
| NASA | Moon facts, Moon overview, Moon exploration and Earth facts: four exact documents with listed passive assets |
| Wikipedia | The Chicago Bulls history article and its listed passive assets |
| Adafruit | The half-size breadboard product 64 page and its listed passive assets; information and photographs only |
| ESPN and Walmart | Disabled candidates; mixed betting, retail, advertising or recommendation content has not met the review boundary |

No whole domain is approved. Scripts, forms, sign-in, checkout, general web search, uploads, downloads, video and interactive embeds are unsupported. Unreviewed links and changing resource URLs may leave a page incomplete. Web and desktop builds provide the local companion experience; they do not render protected live websites or filter their host browser. See the exact scope, sources and licensing in [Live browsing policy](docs/LIVE_BROWSING_POLICY.md).

Android uses an independently gated WebView with mediated HTTPS requests. The iOS 18.4+ pilot uses WKWebView with compiled resource rules and nonpersistent website storage; older iOS retains the offline app. Their guarantees differ: iOS does **not** provide Android's per-subresource response MIME/body inspection or streamed byte limits. Neither mechanism classifies future page content. The retired unrestricted engine APIs remain closed; the pilot uses a separate protected bridge.

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

Opening an eligible page contacts that website and its permitted asset hosts directly. Wingman does not upload the browsing URL or page content to a Wingman server, Firebase, an analytics SDK or an AI classifier. Websites and network providers still observe ordinary connection metadata; native platform security services are not a promise of anonymous traffic.

Policy decisions, the supported EasyPrivacy subset, artwork and application preferences are local. No Firebase/GCP project, paid API, deployment or recurring Browser service was added. Read-only cloud inventory found an existing Wingman-named project serving unrelated applications; it was left unchanged. This does not establish that the user's existing cloud bill is zero. See [Cloud cost plan](docs/CLOUD_COST_PLAN.md) for the verified inventory and a future static-update proposal with explicit cost limits and privacy tradeoffs.

## Validation and maintenance

The host suite passed **528 tests with two optional skips**. Native live journeys and the actual-app pin/revocation flow passed on dedicated Android and iOS simulators. See [Protected visual browsing QA](docs/PROTECTED_VISUAL_BROWSING_QA.md) for commands, observations and limits. Fresh native visual sign-off remains open because the Mac was locked during final capture attempts. A production store release, physical-device security audit and complete whole-web classification are not delivered by this pilot.

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter test integration_test/protected_live_native_test.dart --no-uninstall -d <device-id>
flutter test integration_test/protected_live_app_test.dart --no-uninstall -d <device-id>
```

The bridge fixture exercises independent request denials, supported public journeys and renderer cleanup. The actual-app fixture covers address entry, a completed-page Launchpad pin, reopening in a new tab and additional-restriction revocation. See [Protected visual browsing QA](docs/PROTECTED_VISUAL_BROWSING_QA.md) for measured results. Public sites and network conditions can change; an enabled manifest entry alone is not proof of a passed device run. `--no-uninstall` preserves the installation. Native integration tests also require the installed target/toolchain; consult individual fixtures before running them against personal state.

The signed offline article catalog separately expires on March 10, 2027 and uses a development signing key whose private seed is outside Git. The live network scope is pinned into the reviewed application build; it is not a remotely signed production publisher. Renewal requires review and a rebuilt app. See [Content policy](docs/CONTENT_POLICY.md) and [Live browsing policy](docs/LIVE_BROWSING_POLICY.md).

The [screen registry](docs/ui/SCREEN_REGISTRY.md), [design system](docs/ui/DESIGN_SYSTEM.md) and [Launchpad specification](docs/ui/LAUNCHPAD_SPEC.md) explain the existing product. Previous [Launchpad QA](docs/ui/LAUNCHPAD_QA.md), [signature status](docs/SIGNATURE_FEATURES_STATUS.md), [privacy architecture](docs/PRIVACY_ARCHITECTURE.md), [platform capabilities](docs/PLATFORM_CAPABILITIES.md) and [release readiness](docs/RELEASE_READINESS.md) record earlier milestones; their blanket no-live-network/no-renderer statements and test totals are superseded for v0.8 by the live status and policy documents. They are not new pilot acceptance evidence. Phase 1–3A documents and [the earlier README](docs/history/README_PHASE3A.md) remain historical.
