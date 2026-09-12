# iOS ordinary-app UI acceptance

September 11, 2026; consumer 0.10.0+10, ordinary `lib/main.dart`, iPhone 17 Pro simulator/iOS 26.3 (C157677F-A33F-45B2-BFFB-F3DED552D4F4). Tests below are actual native-app UI interactions via Simulator, not a fixture app substituted for Wingman. Native engine compilation/security unit tests are separately recorded in [iOS implementation evidence](IOS_CONSUMER_ACCEPTANCE.md).

## Search and real websites

Eleven ordinary neutral queries and ten result destination domains passed: see [search ledger](SEARCH_ACCEPTANCE.md). Documentation navigation worked on docs.python.org; Walmart's product carousel changed its image; ESPN's scoreboard rendered but also showed betting sponsorship, which is a confirmed mandatory-category coverage gap.

Python documentation's scroll position survived opening/closing Wingman's menu. It also restored its last address after app replacement. Simulator mouse drags did not reliably move native pages; keyboard Space paged through the Python tutorial. Touch-scroll verification remains separate from that keyboard result.

## Local synthetic fixture

Fixture server: `scripts/serve_browser_fixtures.py` on `http://127.0.0.1:8810`. Only generated, harmless data is used; no personal login or file data is transmitted.

| Check | Observed result |
| --- | --- |
| JavaScript | Run JavaScript changed the visible message to JavaScript worked |
| GET form | Submit site search produced Form submitted and the exact neutral fixture query |
| Back | Returned to the fixture, retaining JavaScript worked |
| Forward | Returned to the form response |
| Controlled login | POST/303 login displayed signed in as synthetic-user |
| Website storage | Save storage marker changed Storage:empty to Storage:saved |
| Normal persistence | Replaced and relaunched the ordinary app; restored session address still displayed signed in as synthetic-user and Storage:saved |
| Private separation | New private tab on the same origin displayed signed out and Storage:empty |
| Private restoration | After replacement/relaunch, tab sheet displayed Normal (2), Private (0); private tabs were absent |
| New windows | Prohibited synthetic-category popup was blocked without adding a tab; permitted popup opened a fourth tab in the private session and displayed Second fixture page |
| Permitted redirect | /redirect completed at Second fixture page |
| Blocked redirect | Prohibited synthetic-category destination was blocked; final build retained the usable Security fixtures page with a block notice and no network-error overlay |
| Prohibited path | Synthetic alcohol promotion path produced a block notice while retaining the current document |
| Invalid TLS | expired.badssl.com produced The secure connection could not be verified. The connection was blocked; no exception was offered |
| Download | Confirmed wingman-test.txt from 127.0.0.1, exported with native Save picker; picker showed the generated file as 53 bytes |
| Upload | Native Choose File picker selected that same wingman-test.txt; POST response displayed Upload received and 246 request bytes received and discarded |

## Final-build media, permissions and search continuation

The final ordinary app replacement was built in 146.4 seconds and installed without clearing normal data. Its tab sheet showed Normal (2), Private (0), and the restored session still displayed the synthetic login and saved storage.

In the normal provider page, Python sorting examples was refined using DuckDuckGo's own field/clear control to Python dictionary examples. Results changed accordingly. Keyboard Space paged through the first set; More Results appended a visibly numbered second set containing PYnative, FreeCodecamp and Dataquest. An intermediate input concatenation caused by Simulator keyboard selection was corrected with the provider's clear button; it is not counted as a clean query. This supplements the original eleven-query/ten-domain matrix.

Find's text entry, Next and Done dismissed without an assertion or hidden page; the following media navigation rendered normally. Visual selection highlighting was not established in the fast dialog interaction, so that is not a confirmed match-highlighting pass. Native implementation uses WKWebView.find; matchFound is returned but the current shell does not show a no-match message.

The generated canvas-stream fixture on http://127.0.0.1:8811/media displayed Playback started and advancing frames (54, 137, 153). The user-triggered Fullscreen video control entered native fullscreen; Close returned to the same browser page. No camera, microphone, protected media or DRM source was used for playback.

The HTTPS WebRTC sample at https://webrtc.github.io/samples/src/content/getusermedia/gum/ showed a permission dialog naming webrtc.github.io after Open camera. Don’t Allow returned a visible NotAllowedError. No device sensor access was granted. Grant-side capture, location and physical-device behavior remain unverified.

The app was left running on ordinary Home. Synthetic fixture servers are temporary and are not part of the application. No personal file, credential or production resource was used.

## Repaired app failures

An intermediate build took minutes to compile resource-rule regexes. Native stack sampling identified WebKit NFA/DFA compilation, not a provider failure. Restoring efficient per-domain patterns and isolating a small set of broad alias-blocking rules compiled all 14 rule sets within a five-second observation window; ordinary startup and browsing then resumed. This failure and repair are included rather than hidden by earlier successful builds.

A canceled prohibited redirect initially showed the intended block notice followed by a generic network overlay over the committed page. Native handling now ignores WebKit's expected policy-interruption error (102), while retaining genuine network/TLS failures. Auxiliary native callbacks such as URL-free findResult are also separated from pageState validation; a host regression verifies that they preserve the committed page and allow subsequent navigation.
