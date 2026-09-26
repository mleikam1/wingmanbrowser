# Bounded local Brave activation

Verified September 26, 2026, from merged `main` at `addfe39` in the existing
Wingman checkout. Actual Web and News requests succeeded through the web app,
Android app and iOS app. Production authorization is unchanged.

## Root cause

The deployed local preview was a fixture build: its compiled gateway URL was
`http://127.0.0.1:8895/v1/search`, and that port was running `serve-fixtures` with
`FixtureProvider`. The ordinary `serve` command supplied no provider. The only
real-provider runtime factory required production cloud configuration. There was
no complete local key → evaluation ledger → real provider → actual app workflow.
A metadata check found no configured local key and no operations directory.

Actual launch also exposed Flutter's build-output cleanup comparing relative and
absolute paths as different strings. Switching spelling for the same output
directory removed newly copied assets despite a successful build exit. Rebuilding
with the helper's consistent absolute path restored the bundle. The helper now
verifies every declared output, policy assets, manifests and SQLite web resources
before starting either server. Alternate port pairs have separate output bundles.

## Secure setup

In the owner's interactive terminal:

```sh
cd /Users/MattLeikam/Documents/Codex/2026-09-10/files-pasted-by-the-user-you/outputs/wingman_browser
python3 backend/setup_brave_secret.py
```

The prompt is `Brave API key (hidden)`. The existing authorized key is permitted
for this evaluation. Rotation is recommended but is not a prerequisite. No key
belongs in chat, shell arguments, client assets/settings, dart-defines, logs or
screenshots. The existing safe-path, ignored/untracked and owner-only file checks
remain. Local credentials do not replace production Secret Manager configuration.

## Current contract and price

Official sources were reviewed on September 26, 2026:

- [Authentication](https://api-dashboard.search.brave.com/documentation/guides/authentication): backend `X-Subscription-Token` header; `Accept: application/json`.
- [Web reference](https://api-dashboard.search.brave.com/api-reference/web/search/get): GET `/res/v1/web/search`, `web.results`, maximum count 20 and page offset 0–9; Web-only `result_filter=web` and `text_decorations=false`.
- [News reference](https://api-dashboard.search.brave.com/api-reference/news/news_search/get): GET `/res/v1/news/search`, top-level `results`, maximum count 50 and offset 0–9; optional descriptions/dates remain safe to omit.
- [Rate limits](https://api-dashboard.search.brave.com/documentation/guides/rate-limiting): multiple returned windows and Retry-After control pacing; no automatic retries are enabled.
- [Current pricing](https://api-dashboard.search.brave.com/app/plans): Search, including Web and News, lists $5 per 1,000 requests. Reserve 5,000 USD micros per attempt; do not assume free credits or an account balance. Actual charges require reconciliation.

Both endpoints enforce `safesearch=strict`. The local provider requests count 10.
Wingman's existing 400-character/50-word query limit and supported locale subset
remain within both API contracts. No extra endpoint, autocomplete, media fetch,
scraping, redirect follow or paid fallback was added.

## One persistent grant

Authorization: `wingman-brave-local-live-v3-20260926`, the same grant on repeated
prompts. Maximum 100 attempts and $0.50, stopping at either limit; at most 20
are automated verification, with remaining capacity reserved for deliberate
manual testing. It expires seven days after first initialization, without renewal.

The local ledger and initialization marker live beside the preserved legacy
smoke accounting in the common Git operations directory. All worktrees/processes
share the allowance. Legacy attempts/cost count toward the consolidated ceiling;
unused legacy smoke capacity is retired, not added. Reservations commit before
network dispatch and never refill after failure, restart, key change or resume.
Missing/corrupt established accounting stays closed. This local SQLite grant is
not a production ledger.

Account/authentication, request-validation and schema failures pause the grant
until an explicit correction is recorded. Retry-After and quota windows survive
restart. Unknown outcomes retain their reservations. Received HTTP success,
schema success, conservative reserved cost and actual reconciled charges are
reported separately. The initial aggregate pace is at most one call per two
seconds, slower when provider windows require it.

## Local launch workflow

From the repository root, inspect status without a provider request:

```sh
PYTHONPATH=backend work/brave-venv/bin/python -m wingman_search status-local
```

After hidden entry, initialize the named grant explicitly. This is idempotent for
that same grant; it never replenishes an existing allowance or replaces missing
accounting. Do not initialize the older smoke allowance too.

```sh
PYTHONPATH=backend work/brave-venv/bin/python -m wingman_search initialize-local
work/brave-venv/bin/python scripts/run_brave_local.py --platform web
```

The default manual-testing app is `http://127.0.0.1:8898`; its gateway endpoint is
`http://127.0.0.1:8897/v1/search`. The helper prints the actual selected ports and
checks that they are free. `--gateway-port` and `--web-port` can select other free
ports. It rebuilds the actual Flutter app with matching `WINGMAN_SEARCH_URL` and
`WINGMAN_SEARCH_DEVELOPMENT=true`. The default port pair builds and serves
`work/brave-live-web/current`, preserving the verified default artifact and prior
fixture preview. Other port pairs use separate matching build/server directories:
`work/brave-live-web/gateway-<gateway-port>-web-<web-port>`. A second helper on
other free ports therefore cannot overwrite the first helper's app assets.
No key is passed to Flutter. Stop with **Ctrl-C** in
the helper terminal; only its own children are stopped. Data and accounting stay.

The verified session is left running in manual mode. Subsequent launches use the
same grant and only its remaining capacity; stop the current helper before
starting another on the same ports.

For an explicit, already-running dedicated native simulator, select one platform
and device (stop the prior helper first or use a different free gateway port):

```sh
work/brave-venv/bin/python scripts/run_brave_local.py --platform android --device emulator-5556 --android-target-platform android-arm64 --adb /Users/MattLeikam/Library/Android/sdk/platform-tools/adb
work/brave-venv/bin/python scripts/run_brave_local.py --platform ios --device 66A59B40-F6ED-43F6-BE6F-1410F1942F03
```

These are launch commands, not paid acceptance tests. Root's automated acceptance
uses the explicit `--actor automated` option; deliberate owner testing defaults
to `manual`. The actor is fixed by server startup, never a consumer POST field.
The helper does not initialize or resume grants, retry searches, run acceptance
on startup, or stop unrelated port owners. A dry run prints commands only:

```sh
work/brave-venv/bin/python scripts/run_brave_local.py --platform web --dry-run
```

If a request pauses the allowance, first correct the actual cause offline. Then
record the matching correction, for example:

```sh
PYTHONPATH=backend work/brave-venv/bin/python -m wingman_search resume-local --correction request-corrected
```

Other fixed reasons include `credential-updated`, `account-corrected`,
`schema-corrected`, `rate-metadata-corrected` and `transport-reviewed`. This is
not a blanket retry instruction: only acknowledge a correction actually made.
Multiple failure reasons require their respective corrections. No correction
adds attempts, money or time. A pending uncertain attempt remains conservatively
reserved even after explicit transport review. Never reset/delete a ledger.

The local-live server binds only to loopback and validates Host, Origin, Fetch
Metadata, JSON content type and supported methods. Native clients may omit
Origin; requests from unapproved origins and form requests cannot dispatch. CORS is not the sole
boundary. Startup, health/readiness, builds and ad updates make no provider calls.

Existing advertising code and campaigns remain intact; local organic evaluation
does not require advertiser contracts or activate live charges. Explicit News
search is separate from shared Home/Discover snapshots, schedules and image rights.

## Verification and accounting

The owner authorized the existing key. It was entered through the hidden utility,
which saved the ignored backend-only file with owner-only permissions. No key was
put in shell arguments, client configuration or application logs. The current
credential status is `verified-web-and-news`. No credential or provider response
body is committed.

| Check | Current result |
|---|---|
| Transport/contract/smoke focused offline suite | 27 passed; final deadline-classification follow-up 9 passed |
| Full offline Flutter suite | 1,105 passed, 6 optional skips, 0 failures; 2m07s |
| Full analyzer | Clean; 5.0s; final message-only changes checked with 14 tests and clean focused analysis |
| Final full offline backend suite | 391 passed, 0 failures/skips; 34.952s test time, 38.35s wall time |
| Final credential-status/runtime follow-up | 26 passed, 0 failures; 3.836s |
| Final runtime/gateway/launcher follow-up | 37 passed, 0 failures; 9.310s, including separate build/serve directories for alternate port pairs |
| Final Android ABI launcher follow-up | 14 launcher tests passed, including matching split-APK build and replacement-install paths |
| Local evaluation ledger | 20 focused tests passed; actual named grant initialized once and preserved across gateway restarts |
| Actual app web development build | Passed; final manual launch rebuild 1.991s with complete assets, compiled endpoint `http://127.0.0.1:8897/v1/search` |
| Android actual-app acceptance | Passed on dedicated `emulator-5556`: actual `main`, `WingmanSearchView`, Web 10 and News 10, schema version 1, `fixture=false`, exactly 2 gateway connections |
| iOS actual-app acceptance | Passed on dedicated simulator `66A59B40-F6ED-43F6-BE6F-1410F1942F03`: live All and News cards, protected NASA navigation, restored Back and resume |
| Distinct second live query | Passed in web UI: NASA science results followed by Python documentation results |
| Native allowed-result navigation and cached Back | Passed: `Moon Facts - NASA Science` opened the protected native page; Back restored the same cards and nonzero scroll position, with attempts unchanged at 8 |
| Typing without submission | Passed in web and native app; initial web startup and typing left attempts at 0; Android harness asserted no typing request |
| Normal URL navigation | Passed on iOS for `https://science.nasa.gov/moon/facts/`; attempts remained 9 |
| Resume, rebuild, health and ad updates | iOS background/resume, gateway restart and web rebuild left attempts at 9; health/status GETs made no calls; offline rebuild/resume/delayed-ad regressions passed |
| Forced failures, unsafe input, exhausted budgets and privacy transitions | Offline fixtures only; included in passing backend/Flutter suites |

### Live endpoint and UI evidence

The actual web build is served at `http://127.0.0.1:8898/`. Its compiled organic
and ad gateway configuration points to `http://127.0.0.1:8897/v1/search`; the
loopback gateway reports `mode=local-live`, `provider=brave`, count 10 and no
automatic retries. Its final actor is `manual` for deliberate owner testing.
The old preview at port 8894 remains a separate fixture build.

| Endpoint | Provider outcome | Schema and count evidence | Actual interface evidence |
|---|---|---|---|
| Web | 4 attempts, 4 HTTP 200, 4 schema successes | `web.results`; Android actual-app assertion observed 10 normalized results, `fixture=false` | Web showed NASA Science and Python documentation for distinct queries; iOS showed Moon Facts and NASA Space Place |
| News | 5 attempts, 5 HTTP 200, 5 schema successes | top-level `results`; Android actual-app assertion observed 10 normalized results, `fixture=false`; web NASA News list contained 10 source labels | Web showed NASA-funded research; iOS News showed Moon Facts and National Geographic Kids |

Web UI verification used five submissions (2 Web, 3 News), including one explicit
repeated News submission while checking text input. Android used two and iOS used
two. There was no automatic retry, unmetered probe, screenshot-triggered search or
provider failure. The iOS checks used the ordinary app build; Android's opt-in
acceptance ran only through the actual app and had a two-connection ceiling.

The final nonsecret status snapshot and native acceptance logs are retained in
ignored `work/brave-live-evidence/`. Screenshots are outside the repository in the
task's output folder: `wingman-live-web.png`, `wingman-live-second-query.png`,
`wingman-live-news.png`, `wingman-live-ios-web.png`, `wingman-live-ios-news.png`,
`wingman-live-ios-before-open.png`, `wingman-live-ios-protected-page.png` and
`wingman-live-ios-back-restored.png`. The before/after images show the first Moon
Facts card at the same scroll position. No screenshot includes a credential.

### Final allowance

| Measurement | Value |
|---|---|
| Grant | `wingman-brave-local-live-v3-20260926` |
| First initialization | September 26, 2026 at 17:06:14.895515 UTC |
| Expiration | October 3, 2026 at 17:06:14.895515 UTC (12:06:14 CDT) |
| Attempts used | 9 total, all automated; 0 manual; 0 inherited smoke attempts |
| Confirmed HTTP / schema successes | 9 / 9 |
| Unknown outcomes | 0 |
| Conservative reserved estimate | $0.045 (45,000 USD micros) |
| Remaining total/manual-test capacity | 91 requests and $0.455, stopping at either limit or expiry |
| Remaining automated ceiling | 11 within the same total; no more acceptance calls planned |
| Actual reconciled charges | Unknown; no invoice/account-credit reconciliation was performed |
| Paused / expired | No / no |

The final live `/statusz` check returned HTTP 200, manual actor, both credential
verification flags true, 9 attempts and 91 remaining. A boundary scan confirmed
the secret file is ignored/untracked with mode 0600 and its value is absent from
all 24 staged files, the compiled web JavaScript and the ordinary Android and iOS
app kernels.

All local accounting and initialization markers remain intact. Ordinary launch
does not initialize, reset, renew or consume the allowance. No advertiser charge,
production infrastructure, public endpoint, DNS/IAM change or agreement was made.

### Limitations and recovered checks

The initial incomplete web bundle was corrected and its cause now has a launch
regression test. The first attempt to restore the ordinary Android universal APK
hit `INSTALL_FAILED_INSUFFICIENT_STORAGE`; the existing installation and user data
were preserved. The corrective restore used an arm64-only ordinary build with an
explicit replacement install. That 97,711,219-byte build passed in 40.2s, the single
corrected `adb install -r` succeeded, and the ordinary app cold-launched
successfully. The opt-in acceptance entry is no longer installed. App data was
preserved without uninstall, reset or file deletion. The ordinary app retains
the 8897 gateway reverse mapping; all previous mappings were preserved and the
acceptance-only VM forward was removed. The helper's optional
`--android-target-platform android-arm64` reproduces this smaller build.

Physical devices and release-store builds were not tested. The six optional
Flutter host-suite skips are not platform acceptance passes. Shared Home/Discover
news redistribution and production deployment remain outside this local grant.
Brave account credits and actual billed amounts remain unverified.

The earlier fixture release report is historical. This record documents the
subsequent live activation and actual application checks.

## Changed files

- `backend/setup_brave_secret.py`: accurate hidden-entry prompt for the existing authorized key.
- `backend/wingman_search/local_budget.py` and `budget.py`: explicit shared finite grant, legacy accounting consolidation, durable reservations, expiry, pause/correction and provider quota handling.
- `backend/wingman_search/local_runtime.py` and `__main__.py`: distinct local-live runtime, safe credential status, explicit initialize/status/resume commands and loopback startup.
- `backend/wingman_search/provider.py`, `contracts.py` and `gateway.py`: bounded count, actual transport/error classification, safe error metadata and local HTTP request boundary.
- `lib/search/client.dart`, `models.dart`, `transport_native.dart` and `transport_web.dart`: distinct safe client configuration, network and provider error states.
- `scripts/run_brave_local.py`: repeatable actual-app build/launch/stop helper with data-preserving Android replacement installation.
- `backend/tests/test_brave_live_transport.py`, `test_brave_local_budget.py` and `test_brave_local_runtime.py`: offline transport, spending, runtime, gateway and launch regression coverage.
- `test/search/native_transport_test.dart`, `search_test.dart` and `test/ui/strict_search_shell_test.dart`: client failure and no-extra-request/navigation regressions.
- `integration_test/wingman_search_live_app_test.dart` and `test_driver/wingman_live_driver.dart`: explicitly opted-in native app acceptance with a two-request ceiling; not run as part of startup or ordinary offline testing.
- `README.md`, `docs/BRAVE_SETUP.md` and this record: secure setup, mode separation, bounded grant and repeatable launch instructions.
