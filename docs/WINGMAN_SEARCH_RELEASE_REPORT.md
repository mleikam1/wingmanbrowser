# Wingman Search, News and Ads — implementation and local release evidence

September 26, 2026. This work extends the existing Wingman Flutter application,
its protected native browsing flow and Python backend. It is implemented local
code, not a production launch or a revenue claim.

Repository: `/Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser`

Branch: `feat/wingman-brave-search-revenue`. Baseline: `e8d4d8930f2a1352d7c4d0c868659abba2a501b6`.
The primary checkout was clean. Other worktrees, consumer data, branding,
Android WebView, Apple WKWebView, Spaces, bookmarks and existing content sources
were preserved. No applicable AGENTS.md was found. The complete supplied v2 pack
was read, including addendum 07 from the outset, and copied unchanged into the repo.

## State at handoff

| Area | Implemented / locally verified | Authorization and remaining limit |
|---|---|---|
| Wingman Search | All/News UI, strict Web/News contracts, backend-only credential, transient queries/results, protected activation, locales and pagination | Replacement key remains unconfigured; real Brave response/quality not verified |
| Cost control | Durable reserve-before-dispatch local ledger and shared GCS generation-CAS implementation; finite caps, rate windows, uncertain outcomes, restart and rotation controls | Real GCS/Secret Manager, deployment target, cloud costs and production budget unapproved/unverified |
| Wingman News | Rights-gated Brave adapter, finite scheduled pools, durable scheduling, shared reader, original publisher attribution, no invented publication time | Brave shared cache/CDN/media rights unresolved; source and polling remain off |
| Wingman Ads | Direct prepaid campaigns, restrained first-party placements, short-lived signed tokens, exact transactional CPC/CPM settlement, no profiles or third-party creatives | All live ad/billing gates off; no paying advertiser, accepted contract, verified real funds or connected partner |
| Operator / finance | Private authenticated operator UI, advertiser intake, manual invoice/receipt/adjustment reconciliation, test-money reports, editable scenarios | Production private access/TLS, business retention, real payment reconciliation and operator approval still required |
| Native / browser | Actual Web UI and native fixture acceptance recorded below; baseline protections retained | Simulators are not physical devices; web companion retains its existing external-browser boundary |
| Commercial result | Fixture delivery and arithmetic only | Real provider spend **$0**; advertiser charges **$0**; cash collected **$0**; earned revenue **$0** |
| Release | Explicit configuration/commands, independent gates and rollback prepared | No cloud resources, DNS/IAM changes, deployment, app-store publication, outreach or agreements performed |

Wingman remains free and ad-supported. There is no subscription, paid privacy,
named assistant, paid organic ranking, history-based targeting or insertion of
ads into external web pages.

## Implementation checkpoints and changed areas

- `fabe93c`: Phase 01 credentials, privacy contracts, non-resettable accounting,
  spending/rights defaults and setup utility.
- `e720a1b`: Phase 02 branded search, transient tab state, native protected routing,
  independent Library search and initial actual-app acceptance.
- `1685c82`: Phase 03 durable shared accounting, scheduled news, rights gates,
  explicit production provider/WSGI construction and deployment preparation.
- `a8ea1aa`: Phase 04 contextual placements, prepaid campaign store, event
  settlement, frontend viewability and Home controller regression repair.
- `42ffe4e`: Phase 05 private operator/intake, invoice/receipt reconciliation,
  contribution calculator and commercial pilot documents.
- `7780abe`: Phase 06 integrated traffic/benchmark evidence, advertising-rights
  failure isolation and native cancellation lifecycle repair. Final native
  harness/evidence follow in the last checkpoint.

The complete changed-file inventory is appended below. Main source areas are
`backend/wingman_search/`, `backend/wingman_ads/`, `backend/wingman_content/`,
`lib/search/`, `lib/ads/`, the existing browser shell and first-party live-content
views. Native engines were not replaced. The dependency lockfile is unchanged.
The new Search/Ads backend does not expose operator routes on the public gateway.

## Test results and actual platform evidence

| Check | Result | Evidence / scope |
|---|---|---|
| Original Flutter baseline | 1,055 passed; 6 optional skips | Locked dependency map repaired before baseline; no lockfile update |
| Original Python baseline | 186 passed | Isolated Python 3.12 environment with pinned Pillow/defusedxml |
| Original Android JVM baseline | 23 passed | Existing native policy/navigation unit tests |
| Final Python suite | **332 passed, 0 failed, 0 skipped** | `final-python-tests.log`; 28.472s; synthetic/fake-cloud only |
| Direct ads/operator/finance subset | **50 passed** (included in Python total) | 17 core, 17 finance, 7 operator HTTP, 9 independent review |
| Production runtime independence subset | **11 passed** (included in Python total) | Ads rights/store failure cannot stop authorized organic requests; organic rights revocation still stops dispatch |
| Flutter regression suite | **1,099 passed, 6 skipped, 0 failures**; analyzer clean | 5m33s with two workers; full analyzer clean in 26.0s; final harness analysis clean in 2.3s |
| Controlled native client traffic | **1 passed**, 132 local requests/132 local socket contacts | Production clients/controllers against a rejecting loopback socket recorder; no Brave/merchant/RSS request |
| Android JVM final | **23 passed; 0 failed/errors/skipped** | Gradle build successful; XML results counted |
| Web actual build/UI | **Passed** | Rebuilt Flutter debug web; Home→All→Sponsored→Why this ad→News; no new console errors on repaired flow |
| Android actual app | **1 composite test passed; 0 failed/skipped** (2m52s; first fixture search 6,093 ms) | Dedicated simulator, production main(), local fixture gateway, installed data preserved |
| iOS actual app | **1 composite test passed; 0 failed/skipped** (24s; first fixture search 383 ms) | Fresh iPhone 17 Pro iOS 26.3 simulator; production main(), local fixture gateway |
| Operator actual browser | **Passed in Safari** | Sign-in, authenticated dashboard and editable working scenario; separate fixture store |
| Container / deployed infrastructure | **Not run** | Docker unavailable; no production target or deployment authorization |
| Physical devices / this change on macOS native | **Not run** | Existing macOS engine/code preserved; no new native desktop claim |

The six optional Flutter skips remain explicit opt-in suites for live content,
editorial/native live traffic, guard/catalog benchmarks and live smoke. They were
not enabled to consume unapproved network or paid traffic.

Failures were investigated rather than omitted: the initial full Flutter run had
11 failures (nine old tests used the newly changed default Web path, two Home
goldens reflected the deliberate provider-disclosure wrap). Those tests now
explicitly select Library and retain their original coverage; golden differences
were visually reviewed. Actual web acceptance exposed a ScrollController disposal
race across desktop selection/rebuilds; stable per-tab controllers and a regression
fixed it. Android acceptance exposed late RSS connection cancellation during
private-tab transitions; final handling and verification are recorded below.
An earlier iOS simulator could build but not launch; a fresh disposable simulator
was created without erasing it. The first fresh iOS run had one local timeout and
one passing logical scenario; the following run passed both, with first fixture
search 321 ms. This is a single fixture observation, not a latency SLA.

### Reproduction commands

Run these from the repository above. The environment used was Flutter 3.44.4,
Dart 3.12.2, Python 3.12 and Xcode 26.3. Development fixtures never need a Brave key.

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub --reporter expanded --concurrency=2
PYTHONPATH=backend work/brave-venv/bin/python -m unittest discover -s backend/tests -v
flutter test --no-pub test/ads/client_traffic_test.dart --dart-define=WINGMAN_TRAFFIC_CAPTURE=true
(cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ./gradlew :app:testDebugUnitTest)
```

The isolated environment was provisioned with the bundled Python 3.12 runtime:

```sh
/Users/MattLeikam/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m venv work/brave-venv
work/brave-venv/bin/python -m pip install -r backend/requirements.txt
```
 Cloud dependencies are separately pinned in
`backend/requirements-search.txt` and are unnecessary for fixture tests.

Create a **new** fixture store once, then keep opening that same store:

```sh
PYTHONPATH=backend work/brave-venv/bin/python -m wingman_ads init-fixture --store work/brave-evidence/ads-acceptance.sqlite3
PYTHONPATH=backend work/brave-venv/bin/python -m wingman_search serve-fixtures --port 8895 --origin http://127.0.0.1:8894 --ads-fixture-store work/brave-evidence/ads-acceptance.sqlite3
flutter build web --debug --no-web-resources-cdn --no-wasm-dry-run --dart-define=WINGMAN_SEARCH_URL=http://127.0.0.1:8895/v1/search --dart-define=WINGMAN_SEARCH_DEVELOPMENT=true --dart-define=WINGMAN_ADS_ENABLED=true
python3 -m http.server 8894 --bind 127.0.0.1 --directory build/web
bash scripts/test_wingman_search_app.sh emulator-5556 --ads-fixtures
bash scripts/test_wingman_search_app.sh 66A59B40-F6ED-43F6-BE6F-1410F1942F03 --ads-fixtures
```

The final Android invocation used the equivalent direct command with locked
dependencies (after the script’s `adb -s emulator-5556 reverse tcp:8895 tcp:8895`):

```sh
flutter test --no-pub integration_test/wingman_search_app_test.dart --no-uninstall -d emulator-5556 --dart-define=WINGMAN_SEARCH_URL=http://127.0.0.1:8895/v1/search --dart-define=WINGMAN_SEARCH_DEVELOPMENT=true --dart-define=WINGMAN_ADS_ENABLED=true
```

The store above already exists after this work: **do not reinitialize it**. The
first command is for a genuinely new fixture environment only. The native script
uses `--no-uninstall`; tests restore their created tabs and original active tab.
The Android acceptance device is the existing dedicated `Wingman_API_36`
(`emulator-5556`); the iOS device is `Wingman Brave Verification 2026-09-26`.
A newly created Android `Wingman_BraveAcceptance_20260926` experienced severe
first-boot guest load before testing and was shut down without erasing it. Existing simulators remain preserved.
The operator's separate fixture store was `work/brave-evidence/operator-fixtures.sqlite3`,
served on 8896; see `docs/WINGMAN_ADS_OPERATOR.md` for hidden password setup and
manual reconciliation. A fixture password is never a production credential.

## Brave verification and request accounting

Final metadata-only command:

```sh
python3 backend/brave_smoke_test.py --status
```

Result: credential `unconfigured`; accounting `uninitialized-or-unavailable`;
`dispatchAllowed=false`. No real key was accessed and **zero Web/News requests**
were dispatched. The account was not signed up again. No credential was retrieved
from conversation logs or unrelated projects. The smoke allowance has not been
used, reset or replenished.

Owner-controlled next step, in a local interactive terminal:

```sh
cd /Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser
python3 backend/setup_brave_secret.py
```

Enter a replacement for the key previously exposed in chat. The utility uses
hidden input, requires a real terminal, writes only the ignored owner-only
backend file and refuses unsafe file links/permissions. Do not paste a key into
chat or a command argument. The utility does not make provider requests.

After metadata reports configured, initialize the allowance exactly once with
`work/brave-venv/bin/python backend/brave_smoke_test.py --initialize`, only if no allowance or marker
has ever existed. Existing, missing-after-use or corrupt accounting must be
reviewed, never replaced. Then invoke the already authorized bounded runner with
`work/brave-venv/bin/python backend/brave_smoke_test.py` (no arguments, using the
environment with backend dependencies installed). It persists each attempt before
network dispatch, permits at most one fixed synthetic Web plus one fixed
synthetic News request, count 1, strict filtering, no retry and stops at the first
failure. It refuses reuse after restart or an earlier attempt. A network failure
is not diagnosed as an invalid credential. Do not run a separate curl probe.
Ongoing developer traffic, scheduling and production require a separate budget.

At the reviewed list price of $5/1,000 successful requests, the two-attempt smoke
reserves at most $0.01; actual billed usage must be separately reconciled. This
is a price assumption, not an account balance or bill. [Brave plans](https://api-dashboard.search.brave.com/app/plans)

Local and shared accounting distinguish attempts, conservative reservations,
received successful outcomes, reconciled amounts, confirmed billed counts and
unknown/pending outcomes. They never infer unused free credits or refill on
restart. Shared tests exercise concurrent workers, generation conflicts,
missing/corrupt markers and 10,000 readers yielding one scheduled fake upstream
call. Real cloud transactions, costs and permissions remain unverified.

## Privacy, protection and resilience evidence

Search POST bodies contain query, kind, locale, country, offset and context.
Gateway→Brave traffic is fixed to the Web/News endpoints with server-enforced
strict filtering and bounded result count; no LLM/rich/context endpoint is used.
Client IP forwarding, consumer cookies and browser identifiers are not sent to
Brave. The provider still receives the submitted query and server connection
metadata. The reviewed standard notice allows query retention up to 90 days;
a zero-retention agreement has not been established. [Brave privacy notice](https://api-dashboard.search.brave.com/privacy-policy)

The controlled recorder enumerates exact fields and destinations for construction,
typing, submit, News switch/shared refresh, topic selection, Sponsored
render/view/click, private/managed, background/resume and session disposal.
Its 132 contacts all terminate on the local fixture server. No raw query/token
values enter its saved capture. It verifies no remote suggestions, no merchant
precontact, no cookie/referrer/forwarded-IP headers and no ad refresh from an
already consumed slot. See `docs/WINGMAN_TRAFFIC_AND_BENCHMARK.md`.

This is a client-boundary capture, **not whole-device packet evidence**. The
ordinary native app can still contact existing approved RSS sources and other
pre-existing services. Comprehensive actual-device startup/background traffic,
browser Fetch headers, production proxy/CDN/WAF/APM/crash paths and backups have
not been inspected in an approved deployed environment. These remain specific
launch checks, not a claim of zero network collection.

A unique synthetic query canary is tested against gateway responses, captured
application logs and aggregate metrics; raw consumer query/result fields are
absent from budget/finance schemas. Temporary test stores are removed by the
suite. Final source/APK-entry scans found no tracked credential or ledger files
and no packaged credential/database entry. The only client Brave-host string
identified is the explicit rejection of direct provider endpoints, not a client
request path. No real credential material was available to enter builds.
This scan does not certify unbuilt images or future infrastructure logs.

Backend and existing native tests cover unsupported overrides, malformed/HTML
snippets, obfuscated prohibited promotion, safe educational/helpful queries,
unsafe URLs, late responses, private isolation, forged/replayed events and changed
campaign destinations. The result/provider filters supplement the existing
native destination policy. They do not prove perfect semantic detection, safe
images on mixed-content sites or complete interception on every platform.
The web companion opens external pages through its existing disclosed boundary.
No recovery path offers a protection bypass or an alternate paid provider.

Failure drills cover 401/403, 429 and Retry-After, 5xx, timeouts/unknown outcomes,
corrupt/missing accounting, credential rotation without allowance reset,
concurrent reservations, empty/stale news pools, rights withdrawal and ad outages.
Shared budget tests use fake generation-CAS storage; they do not certify live
GCS deployment. Advertising rights/storage failure now closes ads independently
of authorized organic Search; organic-rights withdrawal still blocks dispatch.

The maintained six-category benchmark contains navigational, local, educational,
product, current-news and sensitive-help cases. Twenty loopback samples each
succeeded; fixture median/p95 values are in the traffic report. Useful live
results within 2 seconds p95, less than 1% failures, real relevance, layout stability,
physical-device latency and sustainable contribution are **unverified targets**.
Ad decision/event requests and rendering run separately from organic completion;
local eligibility checks and context-token signing still run inside the gateway
search handler. No universal zero-latency guarantee is claimed.

## Advertising and business evidence

Default density is one initial All search unit, one New Tab sponsor and up to two
news cards after six/twelve organic items, sharing the cap with NewsUSA. Private,
managed/student, sensitive/uncertain queries and Search News receive no ads.
The second Search slot and limited exploration remain off behind independent
frontend/server/owner gates. Rendered ads are text-only first-party widgets with
Sponsored, advertiser identity and Why this ad. They load no pixels, scripts,
merchant favicons or third-party creative images.

Money tests use integer USD micros. Delivery reserves available prepaid cash,
daily/total budgets and caps inside a transaction. Signed 15-minute tokens bind
campaign/creative/placement/version/price. Expiry and approvals are rechecked
inside the acquired transaction. GET, HEAD, render, hidden/background, forged,
replayed and expired events do not charge. Tests include an explicit early CPC
click before 1 second, concurrent reservations/duplicate clicks, lock-delay expiry/revocation, sequential
view/pause/refund cases and no overspend.
A controlled HTTP integration accepted a 0 ms deliberate click, settled exactly
500,000 test micros once, rejected its duplicate charge, and made no merchant
request. Widget/client tests establish the click signal; native acceptance does
not contact a merchant. This is not independently certified viewability or proof
that a client event came from a human.

Business reports separate cash, unused prepayment liability, earned delivery,
credits, refunds, chargebacks/receivables, fees and partner shares. Test-money
receipts are not real cash; `chargedMicros=0`, `billable=false` and a separate
`testChargedMicros` prevent fixture revenue claims. Operator HTTP tests cover
sign-in/session rotation, CSRF/Host/Origin, escaped content, inquiry review,
draft→invoice→reconciled receipt→approval→preview→pause and reporting.
Actual Safari rendered the workflow and working-case scenario. An initial Safari
Origin issue was repaired using same-origin referrer policy on the isolated
operator pages; consumer/merchant navigation retains no-referrer.

Revenue per 1,000 uses all submitted search-page requests, including failed,
private and noncommercial requests, with page and ad-slot counters distinct.
The supplied planning scenarios produce revenue $2.40/$9.00/$20.80 and contribution
-$4.10/$2.50/$14.30 after assumed $6.50 cost. Unprovided infrastructure/support costs, period alignment or provider billing
reconciliation stay unknown. Fee/share figures are recorded business totals,
which still require external completeness and reconciliation checks. These are editable
assumptions, not a forecast. Four weeks of verified margin ≥25% is a proposed
expansion gate, not achieved performance. See `docs/WINGMAN_COMMERCIAL_PILOT.md`.

## Owner-gated next steps and rollback

1. Enter the replacement key using hidden local setup, then run only the single
   permitted smoke allowance. Record actual contract/rate-window/accounting
   results. Do not repeat or reset on failure.
2. Verify the owner's account/application rights and exact platforms/domains.
   Keep cache/CDN/offline/media rights separately documented. All six entries in
   `backend/config/brave_rights.json` remain disabled, approved domains empty,
   account entitlements unverified and ongoing budgets zero.
3. Supply the explicit dedicated project/region/service/domain, Secret Manager
   reference, persistent shared budget location, spending ceiling, private
   canary and logging/retention configuration. No values are inferred from gcloud
   defaults. Validate the config locally; inspect and build the image in an
   available runtime before separately authorizing deployment.
4. For direct ads, obtain reviewed advertiser/offer/domain agreements, verified
   inventory and reconciled prepaid funds, operator private access and business
   retention terms. The implemented live pilot requires one durable host/store;
   per-instance SQLite on autoscaled Cloud Run is disallowed. Initialize a
   separate approved live store, never promote the fixture database. Partner
   demand/affiliate integrations stay disconnected until separately contracted.
5. Complete approved real-device/infrastructure privacy canaries, physical-device
   safety/latency/relevance tests and reconciliation. Review the evidence and
   costs before public release or traffic expansion. No auto-advance is enabled.

Deployment commands/configuration and cost unknowns are in
`backend/deploy/SEARCH_RELEASE.md`. Infrastructure build, compute, egress, GCS,
Secret Manager, fixed support and payment costs are unknown; no purchased
infrastructure was created. Optional live ad construction rechecks its rights and
owner-only finance evidence, while ordinary Search has independent gates.

Rollback: pause ingestion; close the affected live rights/ad/billing gates and
pause campaigns; withdraw disallowed shared snapshots/media and purge approved
cache generations/backups. Restore the prior known-good app/image under explicit
target IDs. Preserve consumer storage, protection settings, bookmarks, Spaces,
tabs, provider accounting/initialization markers and financial/audit records.
Reconcile in-flight unknown provider attempts and pending advertiser reserves
before reopening. Never uninstall/wipe profiles, reset ledgers or reopen the
old engine as a silent error fallback. If ledger integrity cannot be established,
remain closed until a verified recovery. Rollback itself does not authorize
spending, contracts, deployment or production release.

## Evidence package

User-facing outputs include this report, a binary-capable patch against the
baseline, screenshots of real local Flutter and Safari pages, and selected
verification logs/metadata. No secret, operational database, live invoice/contact
record, signing key or event token is included. Intermediate stores and logs
remain in the repository's ignored `work/brave-evidence/` directory.

Final native acceptance uses one application lifecycle and one test error zone,
retaining both Search and Ads logical scenarios. The RSS fix binds deferred
connection cancellation to its original Dart zone. A real `HttpClient` regression
reproduces the original SDK exception without an external socket; its negative
control and passing repair logs are included. Thirty-seven focused RSS tests pass.

The final Android run passed after the harness explicitly selected the Normal tab
group and waited for mounted, hit-testable fields on fully opened routes. Earlier
harness failures and the overloaded disposable emulator attempt remain recorded.
The iOS composite pass used the same production code and assertions before the
final test-only route-readiness waits; those waits received clean targeted analysis
and the passing Android run. Production Flutter code was unchanged after the
1,099-test full suite. Actual ordinary `lib/main.dart` iOS UI was then manually
verified through Home, Search, Sponsored, Why this ad and News, with screenshots.

Android's 6,093 ms first local fixture search exceeded the desired two-second
latency target on the loaded development host. It is a functional pass, not a
performance pass. The iOS 383 ms fixture observation also does not establish a
live production p95. Android screenshots could not be obtained through the
available UI automation surface; its native integration log is the evidence.
Native iOS and actual web screenshots are included instead.

`build-manifest.json` hashes the reviewed local debug artifacts and identifies
fixture configuration. These are development builds, not signed release or
production artifacts. The iOS artifact was subsequently rebuilt for ordinary
`lib/main.dart` manual review. The archive excludes fixture stores, device images,
secret files, session/signing material and the temporary operator login helper.

## Complete changed-file inventory

130 files changed from the baseline (including this report).

```text
.dockerignore
.gitignore
README.md
assets/live_content/sources.json
backend/.env.example
backend/Dockerfile
backend/Dockerfile.search
backend/brave_smoke_test.py
backend/config/brave_rights.json
backend/deploy/SEARCH_RELEASE.md
backend/requirements-cloud.txt
backend/requirements-search.txt
backend/setup_brave_secret.py
backend/sources.json
backend/tests/test_ads_core.py
backend/tests/test_ads_finance.py
backend/tests/test_ads_operator.py
backend/tests/test_ads_review.py
backend/tests/test_brave_contracts.py
backend/tests/test_brave_foundation.py
backend/tests/test_brave_gateway.py
backend/tests/test_brave_news.py
backend/tests/test_brave_runtime.py
backend/tests/test_brave_shared_budget.py
backend/tests/test_brave_smoke.py
backend/tests/test_content.py
backend/wingman_ads/__init__.py
backend/wingman_ads/__main__.py
backend/wingman_ads/common.py
backend/wingman_ads/demand.py
backend/wingman_ads/finance.py
backend/wingman_ads/operator.py
backend/wingman_ads/service.py
backend/wingman_ads/store.py
backend/wingman_content/__main__.py
backend/wingman_content/brave.py
backend/wingman_content/config.py
backend/wingman_content/normalize.py
backend/wingman_content/provider.py
backend/wingman_content/server.py
backend/wingman_search/__init__.py
backend/wingman_search/__main__.py
backend/wingman_search/budget.py
backend/wingman_search/config.py
backend/wingman_search/contracts.py
backend/wingman_search/gateway.py
backend/wingman_search/policy.py
backend/wingman_search/production.py
backend/wingman_search/provider.py
backend/wingman_search/runtime.py
backend/wingman_search/secrets.py
backend/wingman_search/shared_budget.py
backend/wingman_search/wsgi.py
docs/BRAVE_INTEGRATION_DECISIONS.md
docs/BRAVE_NEWS_RIGHTS_AND_DELIVERY.md
docs/BRAVE_SETUP.md
docs/DATA_FLOW_AND_RETENTION.md
docs/SEARCH_COST_CONTROLS.md
docs/WINGMAN_ADS_OPERATOR.md
docs/WINGMAN_COMMERCIAL_PILOT.md
docs/WINGMAN_SEARCH_PROGRESS.md
docs/WINGMAN_SEARCH_RELEASE_REPORT.md
docs/WINGMAN_TRAFFIC_AND_BENCHMARK.md
integration_test/wingman_search_app_test.dart
lib/ads/client.dart
lib/ads/models.dart
lib/ads/session.dart
lib/live_content/controller.dart
lib/live_content/eligibility.dart
lib/live_content/models.dart
lib/live_content/rss_transport_native.dart
lib/main.dart
lib/policy/policy_runtime.dart
lib/policy/strict_search_policy.dart
lib/presentation/ads/sponsored_placement.dart
lib/presentation/browser_shell.dart
lib/presentation/home/focused_search_screen.dart
lib/presentation/home/home_screen.dart
lib/presentation/home/welcome_screen.dart
lib/presentation/live_content/live_content_feed_screen.dart
lib/presentation/live_content/live_content_section.dart
lib/presentation/protection/additional_boundaries_screen.dart
lib/presentation/protection/protection_screen.dart
lib/presentation/search/wingman_search_view.dart
lib/presentation/settings/appearance_screen.dart
lib/presentation/settings/settings_information.dart
lib/presentation/state/tab_scroll_controller.dart
lib/search/client.dart
lib/search/controller.dart
lib/search/models.dart
lib/search/transport.dart
lib/search/transport_native.dart
lib/search/transport_web.dart
lib/signature/workspaces/discovery_session.dart
scripts/test_wingman_search_app.sh
test/ads/ads_test.dart
test/ads/client_traffic_test.dart
test/fixtures/wingman_search_benchmark.json
test/live_content/brave_shared_test.dart
test/live_content/rss_connection_cancellation_test.dart
test/protected_shell_test.dart
test/search/native_transport_test.dart
test/search/search_test.dart
test/strict_search_settings_test.dart
test/ui/goldens/home-dark.png
test/ui/goldens/home-light.png
test/ui/home_navigation_test.dart
test/ui/shell_visual_test.dart
test/ui/strict_search_shell_test.dart
test/ui/tab_scroll_controller_test.dart
web/index.html
wingman_search_revenue_pack/00_MASTER_CODEX_PROMPT.txt
wingman_search_revenue_pack/01_FOUNDATION_PRIVACY_AND_BUDGETS.txt
wingman_search_revenue_pack/02_BRAVE_BRANDED_SEARCH.txt
wingman_search_revenue_pack/03_BRAVE_NEWS_AND_RIGHTS.txt
wingman_search_revenue_pack/04_WINGMAN_CONTEXTUAL_ADS.txt
wingman_search_revenue_pack/05_COMMERCIAL_PILOT_AND_REVENUE.txt
wingman_search_revenue_pack/06_RELEASE_SECURITY_AND_ACCEPTANCE.txt
wingman_search_revenue_pack/07_BRAVE_ACTIVATION_AND_REVENUE_HARDENING.txt
wingman_search_revenue_pack/BRAVE_ACCOUNT_AND_BUSINESS_INQUIRY.md
wingman_search_revenue_pack/BRAVE_API_CONTRACT.md
wingman_search_revenue_pack/CONNECTIVITY_CHECK.json
wingman_search_revenue_pack/LOCAL_KEY_SETUP.md
wingman_search_revenue_pack/MANIFEST_SHA256.json
wingman_search_revenue_pack/REVENUE_PLAYBOOK.md
wingman_search_revenue_pack/SOURCES.md
wingman_search_revenue_pack/START_CODEX_HERE.txt
wingman_search_revenue_pack/START_HERE.md
wingman_search_revenue_pack/UPDATE_NOTES.md
wingman_search_revenue_pack/illustrative_economics.json
```
