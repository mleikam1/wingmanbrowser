# Historical live content acceptance — 0.11

The September 13 native direct-feed implementation and its current coverage are
recorded in [Content discovery acceptance](CONTENT_DISCOVERY_ACCEPTANCE.md).
The endpoint-only setup and three-publisher coverage below describe the earlier
0.11 milestone; they do not describe ordinary 0.13 native builds.

Wingman 0.11.0+11 extends the consumer-browser recovery at commit
`a1b4fd683d5bf7f0a58f80463cc8cd83b3f8365a`. This is a local implementation and
acceptance record. Production resources, provider purchases and service
publication remain unapproved and were not performed. The owner separately
approved merging this implementation into the repository's `origin/main` on
September 12, 2026.

## Actual coverage and live data

The first ingestion on September 12, 2026 at 00:40:31 UTC received HTTP 200 from
NASA Technology, NOAA and USGS. Its common snapshot contained 43 eligible items:
10 NASA, 3 NOAA and 30 USGS. These are three independent agency sources, all U.S.
federal institutional publishers. Available coverage is English science,
technology and environment. Broad general news, sports and lifestyle coverage
remain unavailable pending a suitable publisher agreement.

The real leading item was USGS's “Environmental DNA monitoring leads to early
detection of invasive zebra mussel DNA in the Colorado River, Utah,” published
September 11, 2026 at 18:36:38 UTC. NASA's “NASA’s Life-Saving Technology Where
Cell Signals Can’t Go” was published September 10 at 20:12:39 UTC. Publisher
timestamps were parsed from the live feeds; they were not inferred from fetches.

The second ingestion runner pass respected the persisted 30-minute source
interval and reported `not-due` for all three publishers. It published the common
snapshot without a premature publisher fetch. Native client smoke verification
parsed all 43 items, admitted all 43 against the bundled source registry and
consumer destination policy, then received an ETag conditional HTTP 304.

The next permitted network ingestion completed at **01:10:50 UTC**. All three
publishers returned HTTP 200, producing snapshot
`93470a9470abea5c1f3d39bc592edd8f`: **48 items, 52,486 bytes, NASA 10 / NOAA 8 /
USGS 30**. Forty-four items supplied author credits. Two NOAA items remained
held because their article paths had not been reviewed. The final sample has
48 science, 38 environment and 3 technology items (overlapping topics), all with
publisher dates. Missing dates are demonstrated by tests, not fabricated in this
live sample. Thus there were three runner passes and **two actual network
ingestion runs** separated by the configured publisher interval.

The source review, exclusions and specific rights are recorded in
[CONTENT_SOURCES_AND_RIGHTS.md](CONTENT_SOURCES_AND_RIGHTS.md). No story data is
bundled as a live fallback. Fixtures exist only under tests. Existing installed
articles remain labeled evergreen/offline.

## Endpoint inventory

| Endpoint | Purpose |
| --- | --- |
| `http://127.0.0.1:8891/v1/snapshot.json` | Local, read-only common snapshot; GET and conditional GET, plus exact-path CORS preflight |
| `http://127.0.0.1:8891/healthz` | Service liveness only; not proof of a fresh snapshot |
| `https://www.nasa.gov/technology/feed/` | Configured server-only NASA RSS ingestion |
| `https://www.noaa.gov/rss.xml` | Configured server-only NOAA RSS ingestion |
| `https://www.usgs.gov/news/all/feed` | Configured server-only USGS RSS ingestion |
| Publisher canonical article URLs | Opened by the user's explicit action through the normal consumer navigation policy |

There is no client ingestion route, arbitrary-URL fetch route, per-user feed,
account endpoint, analytics endpoint, image proxy or moderation upload. Native
clients send no topic/source choices, browsing addresses, queries or identifiers.
Web fetch omits credentials and referrer and rejects redirects. Infrastructure
can still observe ordinary connection metadata. Web article opening is a separate
top-level navigation in the host browser.

## Local reproduction

Run commands from the repository root:

```sh
python3 -m venv work/live-content/venv
work/live-content/venv/bin/pip install -r backend/requirements.txt
PYTHONPATH=backend work/live-content/venv/bin/python -m wingman_content registry
PYTHONPATH=backend work/live-content/venv/bin/python -m wingman_content ingest
PYTHONPATH=backend work/live-content/venv/bin/python -m wingman_content serve --host 127.0.0.1 --port 8891
```

Run `ingest` in another terminal for a second scheduling pass. It respects each
source's persisted next-refresh time, conditional validators and error backoff.
Do not remove that state to accelerate publisher requests for a demonstration.

Loopback requires an explicit development define and a non-release build:

```sh
flutter build ios --simulator --debug --dart-define=WINGMAN_FEED_URL=http://127.0.0.1:8891/v1/snapshot.json --dart-define=WINGMAN_FEED_ALLOW_LOCAL=true
flutter build apk --profile --target-platform android-arm64 --dart-define=WINGMAN_FEED_URL=http://127.0.0.1:8891/v1/snapshot.json --dart-define=WINGMAN_FEED_ALLOW_LOCAL=true
adb -s emulator-5554 reverse tcp:8891 tcp:8891
flutter build web --profile --dart-define=WINGMAN_FEED_URL=http://127.0.0.1:8891/v1/snapshot.json --dart-define=WINGMAN_FEED_ALLOW_LOCAL=true
python3 -m http.server 8871 --bind 127.0.0.1 --directory build/web
```

A normal release build requires an approved public HTTPS endpoint. Omitting it
leaves an honest unconfigured feed state and keeps ordinary browsing available.
The loopback endpoint is not a production address or a phone-accessible service.

## Automated verification

```sh
PYTHONPATH=backend work/live-content/venv/bin/python -m unittest discover -s backend/tests -v
flutter analyze
flutter test
flutter test test/ui/live_content_shell_test.dart --reporter expanded
```

The backend suite exercises RSS/Atom parsing, missing and invalid publication
dates, canonical URL deduplication, distinct same-title reports, DTD/entity
rejection, public-address DNS pinning and rebinding, redirects, wire/XML/gzip
bounds, transport failures, quota Retry-After/backoff, conditional 304, source
removal, explicit tombstones, revoked records and GET/CORS behavior.

Client tests exercise cache-first initialization, refresh failure preservation,
local choices after controller restart, saved identity after expiry, revocation
and rights withdrawal, failed disk writes, context cancellation, feed opt-out,
finite pagination, URL/path validation and private/handoff isolation. Six UI
tests exercise cards, missing-date labels, attribution/local artwork, actions,
preferences, unavailable saved records, failure feedback and large text.

The connected Shell test saves a card, opens its native route, returns to the
same Home offset, opens it from Reading List, immediately redacts saved content
after an additional destination restriction, then verifies private-session
isolation. Synthetic tests do not claim to run a native renderer.

It also saves a long-headline shortcut through the actual Launchpad editor.
Live-article suggested names now respect Launchpad's existing 80 UTF-16-unit
limit at whole grapheme boundaries; the publisher card and saved headline remain
unchanged. The regression includes a multi-code-unit emoji crossing that limit.

Final results: **768 Flutter tests passed, four opt-in tests skipped; 63 backend
tests passed; `flutter analyze` and `git diff --check` passed.** The four skips are
two existing performance benchmarks, the external live HTTP smoke test, and the
real-data screenshot capture. The latter two were also run explicitly and passed.
The native transport smoke received real service data and conditional 304; the
final capture uses the 48-item snapshot. No fixture story is compiled as a live
fallback. The iOS simulator debug, Android ARM64 profile and web profile builds
succeeded. Device results are recorded below. Delivery builds were regenerated
after the bounded Launchpad prefill correction; the screenshots show the same
feed and native browser behavior before that isolated name-prefill correction.

Evidence logs are under `work/`: `live-content-flutter-tests-delivery.log`,
`live-content-analyze-delivery.log`, `live-content-semantics-regression-final.log`,
`live-content-long-headline-integration.log`, `live-content-capture-tests-final.log`,
and `live-content/backend-tests.log`. The three `live-content-*-build-delivery.log`
files record the final native and web builds. Both native delivery builds were
reinstalled without deleting data and launched successfully; the final web build
was reloaded and showed the current snapshot, byline and persisted choices.
The delivery bundle includes copies of final receipts and logs under `reports/`.

## Real browser and device acceptance

The web companion ran at `http://127.0.0.1:8871/` against the shared local service.
Its genuine NASA card opened the canonical publisher page as a top-level host
browser navigation. Returning preserved the local Technology choice and saved
NASA link. Reading List opened a real Launchpad editor; explicit Save Shortcut
created a website shortcut with the original canonical URL and a local globe
icon. After a full reload, that shortcut, saved link and topic choice remained.
The final build labels the shortcut Website and bounds its visible title.

Stopping the feed service and refreshing kept cached cards and original dates,
with restrained cached/refresh-unavailable text. Reloading while the service
remained stopped retained the cache, saved link, local topic and Launchpad pin.
Unfollowing NASA removed its technology cards and showed an honest empty
selection while preserving the user's saved link and shortcut. A further reload
preserved the unfollowed source. Following NASA again restored eligible cards.
The final web build loaded the 01:10 snapshot and publisher byline.

On an iPhone 17 Pro simulator (iOS 26.3), the final 0.11.0+11 developer build
loaded the real shared snapshot. Technology selected three actual NASA technology
stories. The Life-Saving Technology card displayed the publisher date, NASA
attribution, Andrew Wagner byline and credited local artwork. Save became Saved.
Open loaded NASA's actual article inside Wingman's WKWebView with its address
dock and native navigation controls. Back returned to the **same visible Home
position** with the saved card intact. After terminating and relaunching Wingman,
Technology remained selected and Reading List retained the NASA link. Opening
that saved link again loaded the native publisher browser.

On the Pixel 9 Pro XL ARM64 emulator (Android API 37), the profile build loaded
the same real snapshot. Selecting Technology, saving NASA, opening the actual
publisher in Wingman's Android WebView, and returning to the same visible saved
card position all passed. Android's address dock and navigation stayed visible.
`android-live-nasa-saved-card.png` and `android-native-nasa-article.png` are actual
device screenshots captured with Android Studio's Take Screenshot/Save UI.
The first x86-64 development package installed but could not start on this ARM64
emulator; it was replaced with the verified ARM64 profile package without wiping
app data. This was a development packaging correction, not a feed failure.

Actual iOS screenshots in the delivery `screenshots/` folder are
`ios-live-nasa-saved-card.png`, `ios-native-nasa-article.png`, and
`ios-home-position-restored.png`. They were captured with Simulator's Save Screen
UI. Simulator status-bar time is simulator-controlled; the card's UTC publication
and snapshot dates are actual feed metadata. The three additional
`*-flutter-realdata.png` captures are explicitly labelled Flutter renders of the
real snapshot; they demonstrate layout, not a native browsing journey.

Cloud configuration rendering was checked locally, but Docker is unavailable on
this host, so the container image was not built here. GCS generation handling is
covered by five mocked adapter tests; no deployed-cloud behavior is claimed.

## Remaining production approvals

Approve a dedicated project, region, public HTTPS read service, budget and
operational retention settings before production deployment. Existing cloud
projects were inspected read-only and were not reused for this unrelated service.
Review the concrete templates and post-approval commands in
[backend/deploy/README.md](../backend/deploy/README.md).

For broader publisher coverage, Guardian Open Platform Commercial requires a
negotiated quote and distribution agreement. No price is invented and no free
developer key is treated as that agreement. See
[CONTENT_OPERATING_COSTS.md](CONTENT_OPERATING_COSTS.md).

An offline device cannot learn a new withdrawal until it reconnects. Feed-card
expiry bounds stale display; saved records retain their local identity and are
redacted when updated rights or policy make them unavailable. Saved links do not
download full publisher articles. Scope-based eligibility and text exclusions
are limited controls, not a claim of perfect classification.
