# Monetization policy — permanent protection

**Product rule:** every consumer, family, guest and private experience keeps Wingman's mandatory protections. Student experiences are ad-free. Protection never depends on payment.

## Current capability

**Disabled pending review:** all programmatic advertising, including Google test inventory. Google Mobile Ads and UMP are removed from application dependencies and native registration/configuration in this milestone. There is no advertising initialization, consent request, live ad unit, debug opt-in, attribution service or marketing SDK.

**Implemented and tested:** the SDK-free boundary described below. Eight focused tests passed in each of consumer, student and invalid-edition builds with the retired ad defines deliberately present. Scoped analysis is clean. The final clean Android Student debug APK and iOS consumer simulator app passed the removal inspection below. An Android release APK remains **Blocked** by local AOT tool execution. No commercial placement, contract, school license, subscription, price or revenue is being announced.

The compile-time `WINGMAN_EDITION` selects `consumer` or `student`; an invalid value is unknown and cannot enable commerce. This is not a runtime student-to-consumer switch or proof of school enrollment. Changing editions never changes the mandatory content baseline.

## Empty commerce boundary

The default catalog is empty, makes no requests and renders no reserved advertising space. The policy denies all current inventory. Student/unknown editions, private sessions, external webpages, school collections, support, blocked pages and sensitive settings cannot become commercial surfaces.

The preserved interface describes possible future **static, reviewed consumer placements**. Its asset and destination IDs are references, not approval tokens. Constructing a record does not make a creative or destination eligible. Before any future implementation can render one, it must resolve both through the authoritative signed content policy and an approved commercial review process.

A future integration must provide:

- A fixed creative asset and digest; no arbitrary HTML, remote tracking pixels or unreviewed thumbnail fetch.
- A narrow approved destination/content scope and dependencies, with mandatory policy checks on every navigation and redirect.
- Sponsor disclosure, review identity/date, policy version, expiration and revocation.
- Local audience/surface eligibility before asset access, display and explicit activation; stale approvals must not survive an update or route/session change.
- No creative substitution or redirect that escapes the approved scope.
- No browsing-derived interests, sensitive inference, student targeting, categories, search terms, URLs or history supplied to commercial systems.

Current inventory stays disabled even if a future-looking record has complete metadata. Enabling reviewed placements requires implementation, tests, provider/privacy review and explicit approval; no environment flag or remote configuration can silently activate them.

School deployment/support licensing may be considered separately. It would not introduce student ads, paid protection unlocks or baseline bypasses. There is no billing implementation.

## Why the former integration was removed

The former debug integration used official Google test banners, explicit opt-in, UMP and route/private/Guard gates. Those checks did not establish compatibility with the new permanent positive-eligibility policy. A network content rating is not approval of a fixed creative and destination.

Widget gating also does not exclude SDK code from a build. Before removal, generated iOS registration/package locks contained GMA/UMP, and Android's merged manifest contained an ad initialization provider, components and AdServices permissions. This was artifact evidence, not a claim that the old default Home made an ad request.

Google documents its Flutter integration's SDK import, native app IDs and initialization surfaces. Removing those surfaces avoids relying on unsupported creative inspection or modification. [Google integration documentation](https://developers.google.com/admob/flutter/quick-start)

The shared route observer remains under presentation ownership. The former remote Reader and library routes were retired with the live-browser capability.

## Student privacy and external review

Wingman's student ad prohibition is a product decision. Limited advertising exceptions in platform policies do not relax it. Apple Kids Category rules restrict third-party analytics/advertising and outbound distractions; Google Play Families rules require accurate audiences and constrain SDKs, identifiers and commercial content. Audience classification and store acceptance remain external review items. [Apple App Review §1.3](https://developer.apple.com/app-store/review/guidelines/#kids-category), [Google Play Families](https://support.google.com/googleplay/android-developer/answer/9893335)

A teacher or parent PIN is not legal consent. School authorization under COPPA is limited to the educational context; it does not authorize unrelated advertising use. [FTC school guidance](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions)

## Verification record

The focused suite is `test/commerce_policy_test.dart`: **8 passed** for each compile-time consumer, student and unknown target, with `WINGMAN_TEST_ADS=true` and a former banner-ID define still supplied. It verifies edition selection, every audience/surface/private combination denied, covered/background Home denied and an empty catalog. Parent-workspace logs: `work/permanent-commerce-{consumer,student,unknown}-final.log`. Scoped analysis passed (`work/permanent-commerce-analyze.log`). These pure tests use `--no-test-assets` and do not imply app UI, network or native artifact acceptance.

`flutter pub get` removed GMA and the former WebView packages; generated native registrants and the generated Swift package contain neither. The two obsolete Swift lockfiles held only GMA/UMP pins and were removed. Subsequent dependency cleanup removed external URL-launching, sharing and file-picker plugins, and removed the old optional Guard packs from production assets. Dependency logs: `work/permanent-pub-get.log` and `work/permanent-pub-get-final.log`.

After `flutter clean` removed stale prior build output, the final main artifacts were inspected:

| Artifact | Verified result |
|---|---|
| Android Student debug APK, 0.4.0 (4) | DEX package inspection found no GMA/UMP, Flutter WebView, share, URL-launcher or file-picker implementation. Packaged manifest has no ad provider/components, AdServices/ad-ID, camera, microphone or location permissions and no PROCESS_TEXT query. Its permissions are INTERNET for developer tooling and the app's signature-level receiver permission. Restored main APK SHA-256: `a347763a7c86cff449c035bbea55620afa55b07ec21f61afa06e6dddc476a5a2` |
| iOS consumer simulator app, 0.4.0 (4) | Packaged frameworks are App, Flutter, objective_c and sqlite3; resource bundles are secure storage and SQLite. Framework inventory, linked libraries, symbols and executable byte markers contain no retired SDK/plugin implementation. No GMA IDs or retired camera/microphone/location/ATS keys remain. The system WebKit link supports legacy-store cleanup; no Flutter WebView plugin is present |
| Packaged policy data | Android contains the 14 reviewed text articles plus signed catalog, manifest and public keys. Neither old Guard/tracker runtime packs nor `catalog.source.json` are bundled |
| Android release merged manifest | `:app:processReleaseMainManifest` passed in 25 seconds without invoking AOT or building an APK. The merged intermediate declares only the app's signature-level receiver permission: no INTERNET, ad/AdServices, camera, microphone or location permissions; no external-process-text query or ad metadata/provider. AndroidX's ordinary startup provider remains |
| Android release APK | **Blocked**: the local release AOT compiler stalled before execution. No release binary or distribution-signing acceptance is claimed |

Inspection logs in the parent workspace are `work/mandatory-final-android-debug-manifest.xml`, `work/mandatory-final-android-debug-dex.txt`, `work/mandatory-final-ios-binary-audit.txt`, `work/mandatory-release-manifest-task.log` and `work/mandatory-final-android-release-merged-manifest.xml`. These records describe the final main artifacts built from the locally committed `119f64e` implementation. They are separate from the native integration-test harnesses. Secure storage, SQLite and Flutter's integration-test plugin remain; this is not a claim that all plugin code was removed. The release manifest is a verified build intermediate, not a release binary or runtime result.

After the final integration runs overwrote standard output paths, the actual Android Student main APK (with retired `WINGMAN_TEST_ADS=true` still supplied) and consumer iOS main app were rebuilt, installed and launched. Their final reinspection preserved every removal result above; the APK hash above identifies this restored main artifact. Current evidence is `work/mandatory-restored-android-debug-manifest.xml`, `work/mandatory-restored-android-debug-dex.txt` and `work/mandatory-restored-ios-binary-audit.json`. The iOS framework/bundle inventory is unchanged, and Runner, Runner.debug.dylib and App contain no retired SDK/plugin symbols or byte markers.

Actual Android Student app integration passed startup, reviewed content, saves and external-navigation denial with zero fixture requests/content WebViews. Those counters cover the fixture, not all device traffic. This milestone does not load live websites. Operating-system and developer-tool traffic remain outside Wingman commerce; finite captures and SDK removal are not promises of device-wide network anonymity. School distribution and complete shared-device sanitation remain external acceptance gates described in [School deployment](SCHOOL_DEPLOYMENT.md).
