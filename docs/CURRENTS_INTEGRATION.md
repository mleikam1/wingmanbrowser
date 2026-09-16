# Shared Currents integration

## Delivery identity and boundaries

Implementation branch: `feat/currents-shared-ingestion`. Starting commit:
`0c740f094c4fa64c00f31758dfe96d8869023dea`; the working tree was clean.
This extends the existing Python ingestion, read-only snapshot/media service,
Flutter Home/Discover and native engines. It does not create another source
candidate list or an alternate application.

One scheduled ingestion process calls Currents. Readers get the same finite,
filtered Wingman snapshot. Topic selection, refresh and pagination operate on
that snapshot and local preferences; the public service has no ingestion, search,
URL-fetch or administrative route. Native NewsUSA photos retain their separately
approved handling without fetching its RSS twice.

No production backend target or `WINGMAN_FEED_URL` was configured at the starting
commit. The unrelated `wingman-interactive-live`, Trivia Tussle and Grumpy Skies
resources are not deployment targets. No project, paid resource, billing or IAM
change is authorized by these examples. A local service is development evidence,
not installed-phone delivery. The public reader never loads the Currents secret.

## Credentials and commands

Replace any key previously exposed in chat before production. Enter it only in
your own terminal, using the hidden prompt:

```sh
python3 backend/setup_currents_secret.py
```

The command creates ignored `backend/.env.currents` with mode `0600`. It does not
make a network request. The writer prefers `CURRENTS_API_KEY` from its environment
or secret store; the local file is a development alternative. Do not pass the key
as a command argument, URL, dart-define or client setting. Local loading rejects
symlinks, non-owned files and group/world permissions. Key replacement requires
no client rebuild and never resets the ledger.

Use an isolated Python environment with `backend/requirements.txt` installed:

```sh
python3 -m venv work/currents-venv
work/currents-venv/bin/python -m pip install -r backend/requirements.txt
export PYTHONPATH=backend
# FIRST INSTALL ONLY. Never delete/reinitialize an established ledger.
work/currents-venv/bin/python -m wingman_content currents-init
# One budgeted /v1/auth check plus missing/stale category/region/language metadata.
work/currents-venv/bin/python -m wingman_content currents-setup
# One paced pass through the canonical categories; no RSS refetch for screenshots.
work/currents-venv/bin/python -m wingman_content currents-bootstrap
# Normal scheduled composition with existing approved sources, every 30 minutes.
work/currents-venv/bin/python -m wingman_content ingest
# Administrative output; do not expose through the public service.
work/currents-venv/bin/python -m wingman_content currents-status
# Read-only development endpoint, never a production address.
work/currents-venv/bin/python -m wingman_content serve --host 127.0.0.1 --port 8891
```

For deliberate credential replacement, run the hidden prompt again, then one
`currents-setup --replace-credential`. Do not repeatedly test a failing key.
`--store` identifies content; `--ledger` identifies independent persistent local
operational storage. Production uses explicit `--project` and `--bucket`; its
CAS ledger object is `wingman-operations/currents-ledger.json`, outside the
`wingman-content/` cache prefix. Deleting a cache, redeploying or changing the key
must not delete that object. A missing/corrupt ledger fails closed for upstream
requests while eligible cached content and other providers remain available.

## API and editorial mapping

Requests use HTTPS with `Authorization: Bearer` only to
`api.currentsapi.services`. Redirects are rejected. There is no API key query
parameter, implicit retry, cursor walking or per-reader request. Latest requests
use `/v2/latest-news` with exactly `language=en`, `country=US`, one canonical
`category`, `page_number=1`, `page_size=20`. Country is a provider filter, not a
claim about publisher headquarters or audience.

| Canonical provider category | Wingman category / retained entry points | Interval |
| --- | --- | --- |
| general | Headlines / General | 2 hours |
| sport | Sports | 2 hours |
| arts_culture_entertainment | Arts & Entertainment / Entertainment | 2 hours |
| science_technology | Science & Technology; evidence-based Science, Technology | 2 hours |
| economy_business_finance | Business & Finance / Business | 2 hours |
| society | Society | 6 hours |
| politics_government | Politics & Government | 6 hours |
| lifestyle_leisure | Lifestyle & Leisure | 6 hours |
| human_interest | Human Interest | 6 hours |
| crime_law_justice | Crime, Law & Justice | 6 hours |
| education | Education | 6 hours |
| environment | Environment | 6 hours |
| labour | Work & Labor | 6 hours |
| health | Health | 6 hours |
| automotive | Automotive | 6 hours |
| real_estate | Real Estate | 6 hours |

Food, Fashion and Travel retain their preference IDs. They are derived locally
from explicit title/description evidence; lifestyle is not automatically all
three topics. Science and Technology keep their combined parent for ambiguous
items. Live `/v2/available/categories` is authoritative, with reviewed known IDs
only. Regions/languages/categories cache for seven days. Failed refresh retains
validated last-known metadata. New categories require mapping, policy and budget
review before activation.

When a derived pool has fewer than five usable current stories, fixed editorial
Boolean searches may supplement it, at most once per topic per six hours and
12 total/day. `/v2/search` receives a params object, `query` without `keywords`,
seven-day UTC RFC3339 date bounds, en/US and page size 20. It does not receive
reader input or a restrictive parent-category filter. Empty/failing searches do
not immediately try another variant. Tight budgets skip supplements.

## Budget and failure behavior

The engineering plan assumes 250 provider calls/day and 20 results/request;
actual account response headers govern the effective allowance. Five fast
categories × 12 and eleven slow categories × 4 give **104 routine calls/day**.
Supplements give **104–116 healthy routine calls/day**. Setup/metadata/errors are
additional attempts under the **150 total attempts/UTC day hard ceiling**.
The cap never increases when more quota or another key is available.

Each attempted auth, metadata, latest or search request reserves a durable slot
before I/O. Timeouts and uncertain outcomes remain spent. SQLite transactions
coordinate local processes; generation-CAS coordinates GCS instances. Shared
expiring leases, fencing and persisted due slots prevent duplicate dispatch.
No network I/O runs inside a retryable storage callback. Normal ticks make at
most four upstream calls, one in flight, spaced and staggered. Missed schedules
do not trigger a catch-up crawl; the oldest deferred work resumes fairly.

A separate renewable content-writer lease covers the entire read/ingest/publish
operation. Acquiring it fences the content generation before upstream I/O;
an expired worker cannot overwrite a successor's content, even before the
successor publishes. Every provider/media request and publication checks the
writer guard. This prevents spending quota on successful category responses
that would otherwise be lost to a competing snapshot write.

Provider `X-RateLimit-Limit` and `X-RateLimit-Remaining` are read case-insensitively.
Five calls remain reserved for possible external usage. Operational diagnostics
separate local attempts from provider remaining quota. Provider reset is midnight
UTC; `Retry-After` may impose a longer wait. Invalid queries (400) are held;
auth/entitlement errors (401/403) pause; 429 waits; transport/5xx retries occur
later with bounded exponential backoff. `status=ok, news=[]` is a successful
empty poll with a normal next due time, not a reason to refill immediately.

## Content, attribution and rights

Canonical URL identity preserves original links and publication dates. Provider
identity is separate from the original publisher, which comes from validated
metadata or the article domain, never an author or API hostname. Category pools
merge URL membership without treating equal titles at distinct URLs as duplicates
or combining incompatible source rights/assets.

Currents previews use the supplied title and permitted short description, original
publisher credit, real time and a linked **Powered by Currents News API** notice.
There is no article scraping, full-body archive or AI summary. Operational
retention is at most 24 hours after successful retrieval, reduced by stricter
response directives. Reads, failed polls and republication never extend it.
Saved items become links rather than permanent syndicated preview/photo copies.

The documented API-preview allowance is separate from image, branding and
full-text rights. API access does not grant every third-party photo. Unresolved
photos are omitted while permitted text cards remain. Any image grant must cover
the exact API-associated URL and pass the existing bounded media pipeline;
there are no guessed CDN variants, Open Graph scraping, remote logo lookup or
stock/AI replacement news photos. Approved bundled branding may be reused;
otherwise publisher initials are neutral. NewsUSA retains its labeled sponsored
reader and article-plus-image contract.

Destination protection and item-level content checks apply in every category.
These checks do not establish perfect semantic or automatic image safety. Private,
handoff, inactive and Updates-off contexts cancel work and reject late callbacks.
No remote preference storage, history uploads, tracking or advertising SDK was
added.

## Shared service, release and operations

The existing 300-item / 512-KiB envelope balances category and publisher coverage
before truncation, bounds individual fields and retains healthy categories on
partial failures. Conditional ETag/304 reads keep original timestamps. An active
ordinary session can check the snapshot every 15 minutes; this is not background
polling. Manual refresh revalidates only the shared Wingman cache.

`backend/deploy/` contains the existing Python Cloud Run service/job/scheduler
shape. The job has zero platform retries and the schedule is every 30 minutes.
Only the writer receives a reference to an existing backend secret. The reader
has no provider key and accepts only finite snapshot/media reads. CORS is not
access control. Keep operator diagnostics private and ingestion authenticated.

For an already authorized dedicated target, render reviewable configuration:

```sh
python3 backend/deploy/render.py \
  --project REPLACE_AUTHORIZED_PROJECT \
  --project-number REPLACE_PROJECT_NUMBER \
  --region us-central1 \
  --bucket REPLACE_PRIVATE_BUCKET \
  --image REPLACE_IMMUTABLE_IMAGE_DIGEST \
  --currents-secret REPLACE_EXISTING_SECRET_NAME
```

No default gcloud project is accepted. Rendered examples do not authorize creating
resources or changing IAM/billing. The operational ledger must have durable
retention independent of content. Remove expired preview/media generations and
backups; exclude the operational ledger from any content TTL lifecycle. Disable
content object versioning/soft delete only through an authorized storage policy.
Scheduled cleanup must continue even if the provider is paused; if jobs stop,
reads still refuse expired items but an operator must purge dormant storage.

Clients receive only the approved HTTPS endpoint:

```sh
flutter build web --release --no-web-resources-cdn \
  --dart-define=WINGMAN_FEED_URL=https://REPLACE_APPROVED_HOST/v1/snapshot.json
flutter build apk --release \
  --dart-define=WINGMAN_FEED_URL=https://REPLACE_APPROVED_HOST/v1/snapshot.json
flutter build ios --release --no-codesign \
  --dart-define=WINGMAN_FEED_URL=https://REPLACE_APPROVED_HOST/v1/snapshot.json
```

These placeholders are not configured production releases. Verify the supplied
URL in the build command and the actual app provider diagnostics before release.
Without it, native clients retain existing approved direct sources and cannot
receive secure shared Currents content. Hosting, distribution and operations can
cost money even when the API subscription is free. No app-store release is part
of this change.

## Validation and live evidence

Normal tests use fixture responses and fake clocks. Network checks are opt-in and
all Currents network checks run through the same durable ledger. Never label
fixture category counts as live supply. Detailed final validation is recorded in
[the verification report](CURRENTS_VALIDATION.md); live bootstrap and production deployment remain pending
until local credential entry and an authorized backend target are available.

```sh
PYTHONPATH=backend work/currents-venv/bin/python -m unittest discover -s backend/tests
flutter analyze
flutter test
```

Reproduce the actual-app integration with clearly labeled fixtures, zero API
calls and the real snapshot reader (use a separate terminal for the reader):

```sh
PYTHONPATH=backend work/currents-venv/bin/python backend/tests/build_currents_app_fixture.py
PYTHONPATH=backend work/currents-venv/bin/python -m wingman_content serve \
  --store work/currents-app-fixture --port 8893
# For the chosen Android emulator, map its loopback to the local reader first.
adb -s REPLACE_EMULATOR_ID reverse tcp:8893 tcp:8893
flutter test integration_test/currents_app_test.dart --no-uninstall -d REPLACE_DEVICE_ID \
  --dart-define=WINGMAN_FEED_URL=http://127.0.0.1:8893/v1/snapshot.json \
  --dart-define=WINGMAN_FEED_ALLOW_LOCAL=true
```

The Android mapping is unnecessary for the local iOS simulator. Loopback HTTP is
debug-only and rejected by release endpoint configuration. The integration test
starts the actual application, checks Home/Discover, Sports, Entertainment, all
21 controls, original protected navigation, return scroll and private redaction,
then restores the original feed preferences. Always pass `--no-uninstall`:
Flutter otherwise uninstalls the application after an integration test. Use a
dedicated disposable simulator for fixture verification, never personal devices.

## Rollback

Pause the existing scheduler or disable only the `currents` source through the
reviewed configuration and regenerate the registry; leave existing providers
intact. Keep the operational ledger and credential-revision record. Deploy the
previous pinned backend image if necessary, preserving the ledger object. A
client rollback should use the previous build with its same local user data;
do not uninstall, clear preferences, remove explicit hides, or reset permanent
protection. Purge expired/revoked Currents previews/media from content storage,
retained generations and caches under the approved retention policy. Never
rollback by restoring a lower daily attempt count.

## Official contract reviewed

Reviewed September 16, 2026: [overview](https://currentsapi.services/en/docs/),
[authentication](https://currentsapi.services/en/docs/authentication),
[latest news](https://currentsapi.services/en/docs/latest_news),
[search](https://currentsapi.services/en/docs/search),
[rate limits](https://currentsapi.services/en/docs/ratelimit),
[pricing](https://currentsapi.services/en/product/price),
[FAQ](https://currentsapi.services/en/faq),
[terms](https://currentsapi.services/terms).

The FAQ describes previews/attribution/link-out and short-lived operational
caching; it does not settle every publisher's image rights or grant full article
republication. The 24-hour ceiling is an engineering limit, not a claimed legal
license duration. Public redistribution/OEM or unresolved publisher uses must be
scoped with the provider before production expansion.
