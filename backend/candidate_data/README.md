# Feed candidates and reviewed promotion

This directory is an operator input/review inventory, **not a runtime source list**.
The original UTF-8 CSV is byte-for-byte preserved, including its BOM and all 29
columns. `candidates.json` contains 217 category records, 201 exact publisher
labels, and 216 distinct literal feed URLs. A shared hosting domain does not merge
brands. Records and publisher/category memberships remain distinct when an exact
endpoint is shared.

All original `production_enabled`, `image_display_enabled`, and
`all_criteria_verified` values are false. Parsed booleans are separate from raw
strings; unknown values become null and never authorize anything. Importing or
re-importing does not change `reviews.json` or `backend/sources.json`.

## Commands

Run from the repository root using Python with `backend/requirements.txt` installed.
For this verification an isolated ignored environment was created at
`work/feed-candidates/venv`; replace that executable with your configured Python.

```sh
PYTHONPATH=backend python -m wingman_content candidates-import
PYTHONPATH=backend python -m wingman_content candidates-validate --batch-size 24 --concurrency 3
PYTHONPATH=backend python -m wingman_content candidates-report --output backend/candidate_data/reports/validation-report.json
PYTHONPATH=backend python -m wingman_content candidates-promote --record-id WM-0145 --review-id rights-20260915-nasa-wm-0145 --compatibility-raw work/feed-candidates/nasa-photojournal.xml --output work/feed-candidates/nasa-promotion.json
```

`--input`, `--candidates`, `--reviews`, `--state`, and `--config` select local
operator files. `--allow-input-changes` acknowledges different inventory counts;
field validation still applies. New endpoint corrections require exact original
and corrected URLs plus publisher discovery evidence in a reviewed decision.
There is no public candidate-fetch or promotion HTTP route.

The validator requests at most 24 due endpoints per invocation with three workers
and one active request per original host. Re-run it to resume later endpoints.
A persistent cursor advances only when work starts. Results save atomically after
each completion. Before a request, a durable 30-minute hold protects against an
immediate restart loop; publisher freshness, Retry-After and exponential failure
backoff can require longer waits. Existing holds are never reset to make a test
look fresh. A nonblocking local lock rejects overlapping CLI validation runs.
Malformed checkpoint pacing fails closed instead of silently starting over.

Transport is the existing bounded public-DNS-pinned HTTPS fetcher: verified TLS,
every redirect checked, no private addresses, no credentials, byte/decompression
limits, and no article/image fetches. XML inspection rejects DTDs/entities, large
structures and unsupported formats. A plain HTTP candidate is reported as needing
publisher-backed HTTPS endpoint evidence and is not silently upgraded. A 403 is
access-restricted, not declared permanently dead. Image and logo counts describe
supplied **candidates**, not image reuse rights, decoded images or visible cards.

The normal probe retains bounded counters, dates, response metadata and sample
article URLs, not an unlicensed article/photo corpus. Original NASA feed bytes were
retained separately under ignored work for the explicitly reviewed compatibility
reproduction. No app-user browsing, preference or activity data enters these files.

## Review and activation

`reviews.json` separates headline/link, excerpt, article images, branding,
full-text and storage/redistribution decisions, with exact record/endpoint,
evidence, scope, limits, review time and expiry. U.S. qualification, traffic and
content-policy review are separate facts. Unreviewed candidates stay held.

Promotion requires explicit reviewed production/content approval, the necessary
display rights, a complete validated source configuration and a successful exact
endpoint check. It emits a reviewable source patch; it never edits the production
registry. An already identical reviewed source returns an idempotent no-change
receipt; conflicting IDs/URLs are rejected. After an approved configuration change,
use the existing `registry` command and parity tests. No domain-wide inheritance
is granted to other NASA or other publisher endpoints.

NASA Photojournal has one explicit compatibility contract. The raw upstream feed
remains classified **malformed**. Its two known raw ampersands in one exact
feed-level self-link are handled only by the reviewed source-specific adapter;
ordinary XML remains strict. Promotion independently reproduces that adapter from
bounded original bytes, checks both SHA-256 digests, re-runs the strict parser,
checks the actual UTC receipt and requires exact reviewed article/image mappings.
A runtime JSON boolean cannot enable it. The original CSV false flags and earlier
hold decision remain preserved in the activation review history.

NASA's October 15 review date is a manual operator re-review deadline for new
promotion, not an automatic runtime rights expiration. NASA/JPL factual-use
rights have no stated time expiry. The app separately enforces the 30-day
publication freshness window and immediate configured association withdrawal.

## Current evidence and limits

The September 15 run accounted for all 216 literal endpoints (217 rows), including
215 HTTPS fetch attempts and one HTTP pre-network hold. Results were 85 working,
65 redirected, 24 stale, 14 review-needed, 11 access-restricted, 8 unreachable,
6 malformed, 2 HTML/login/challenge responses and 1 rate-limited. A separately
authorized NASA publisher-declared alternate endpoint also remained malformed;
it did not replace the original endpoint or erase its history.

`reports/validation-report.json` and `.md` account for every record and preserve raw
research alongside new observations and review decisions. Newly integrated NASA
Photojournal is reported separately from the 16 preserved existing source entries.
The report does not infer rendered card counts from RSS/image metadata: those
fields stay null until actual normalized/decoded/UI evidence is attached to the
main implementation acceptance report. Initials are explicitly not official logos.

The native app has a separate fixed maximum of 12 unique due endpoints per refresh,
three lanes and a 45-second deadline. Its accepted private checkpoint retains the
last actually started endpoint. Duplicate endpoints share a network result but
keep separate rights/topic normalization; conditional requests require compatible
cached records and validators for every alias. The strictest alias pacing and
intersected redirect hosts apply. Deferred sources are not given invented failures
or backoff timestamps. Topic selections never enter that scheduling input.

Rollback removes a reviewed added source and regenerates the client registry;
existing source entries and local user saves/preferences must remain intact. Do
not delete candidate history or pacing checkpoints to roll back a UI/source change.
