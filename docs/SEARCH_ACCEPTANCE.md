# Search acceptance

The starting installed iOS consumer app rendered `Chicago weather` in DuckDuckGo but denied the first ordinary Weather.com result as unapproved. The provider was reachable. The app's exact-document destination policy caused the failure.

Recovery uses DuckDuckGo's normal user-facing strict hostname, native JavaScript/networking and independent destination filtering. Query submission has no paid search API, scrape/index service, Wingman query analytics or typed-keystroke requests. Provider pagination/refinement are native interactions. Local Library and Official modes remain explicit offline choices. The web companion submits by top-level navigation and explains that filtering after departure belongs to the host browser.

Adult SafeSearch is not gambling/alcohol/drug/tobacco/threat classification. Result text, image previews, ads and dynamic sections can evade classification before a clicked URL is evaluated. Provider/network failures are recorded separately from Wingman decisions. No CAPTCHA/authentication/DRM/TLS bypass is part of acceptance.

## Evidence ledger

Ordinary application entry point `lib/main.dart`, consumer 0.10.0+10, installed and launched on Android emulator-5554 and iPhone17Pro/iOS26.3. Native searches use Home/address Web mode. None of the ten destination domains below was added to an exact-document allowlist for this test.

| Native iOS query | Clicked destination | Observed result |
| --- | --- | --- |
| Chicago weather | DuckDuckGo weather results/card | Results and weather-card interaction rendered; destination not counted |
| Python documentation | docs.python.org | Full documentation, then Tutorial link worked |
| ESPN NFL scores | www.espn.com/nfl/scoreboard | Full NFL scoreboard; betting sponsorship visible, a confirmed content-filter false negative |
| Walmart notebooks | www.walmart.com notebook product | Product images loaded; carousel selection changed image. Result opened a new native tab; ad redirect took time to complete |
| NASA Artemis | www.nasa.gov/humans-in-space/artemis/ | Full Artemis page and media layout |
| NOAA ocean facts | oceanservice.noaa.gov/facts/ | Full facts page and images |
| BBC science | www.bbc.com/news/science_and_environment | Full science article cards/images |
| Wikipedia Mount Everest | en.wikipedia.org/wiki/Mount_Everest | Full article and links |
| MDN JavaScript guide | developer.mozilla.org/en-US/docs/Web/JavaScript/Guide | Full guide and chapter links |
| AP science news | apnews.com/science | Full science page/images/article cards |
| Stack Overflow Python list sort | stackoverflow.com | Question/answer page, code and comments rendered |

This establishes 11 neutral queries and 10 ordinary destination domains on iOS. Python documentation scrolled via keyboard paging, and its exact page position survived opening/closing the Wingman menu. Normal last-address restoration survived an app replacement/relaunch. Simulator mouse drags did not reliably scroll iOS pages; keyboard paging did work on documentation. This is not recorded as a verified touch-scroll pass. Back/Forward on Stack Overflow encountered a transient blank intermediate history page; deterministic fixture checks below distinguish native history from site-managed navigation.

Android completed 12 queries (11 omnibox submissions and one provider-field refinement), ten ordinary destination domains and provider More Results. Full Android journey and fixture evidence is in [Android recovery](ANDROID_BROWSER_RECOVERY.md). The ten counted domains are ESPN, Walmart, Python, MDN, NASA, NOAA, BBC, Wikipedia, AP and Stack Overflow. A DuckDuckGo promotion opened Google Play during the initial Chicago-weather attempt; that destination is excluded from the ten-domain count.

The web companion's ordinary Home query submitted `Chicago weather` by top-level navigation from the local release build to the strict provider and displayed normal results. After leaving, the host browser owns rendering and protection. A web build is not a desktop browser binary.

Further native fixture, update-transaction and final build results are recorded in the platform reports. A successful results page alone is not acceptance of the whole browser.

Final iOS continuation acceptance refined Python sorting examples to Python dictionary examples in the provider field, then More Results appended a visibly numbered second set (PYnative, FreeCodecamp, Dataquest). The final web release smoke submitted NASA Moon facts from Home and navigated top-level to https://safe.duckduckgo.com/?q=NASA+Moon+facts&kp=1&kac=-1; ordinary NASA results rendered. See the iOS UI ledger for file, TLS, media and origin-permission results.
