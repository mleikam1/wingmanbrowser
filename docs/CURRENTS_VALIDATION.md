# Currents verification — September 16, 2026

Implementation is in the existing `mleikam1/wingmanbrowser` repository on
`feat/currents-shared-ingestion`, starting at clean commit
`0c740f094c4fa64c00f31758dfe96d8869023dea`. App version remains `0.15.1+18`.
See [setup, architecture, commands and rollback](CURRENTS_INTEGRATION.md).

## Actual mode and endpoint

- Verified app mode: **shared snapshot**, using debug-only
  `http://127.0.0.1:8893/v1/snapshot.json`.
- The real Python read service served normalized, explicitly labeled **Fixture**
  records. It was not a standalone mock application or a Currents API proxy.
- Production HTTPS endpoint: **not configured**. Release defaults have no
  `WINGMAN_FEED_URL`; installed-phone Currents delivery is therefore blocked.
- Hosting: no confirmed authorized target; no resources, billing/IAM changes,
  subscription purchases, cloud deployment or app-store release.
- The remaining deployment decision is to identify/authorize a dedicated Wingman
  backend target and its operating budget. Do not use the unrelated projects
  named in the implementation request or rely on a default gcloud project.

## Automated and actual-app evidence

| Check | Result |
| --- | --- |
| Backend suite | 186 passed |
| Currents gateway/ledger/provider focused suite | 36 passed, including optimized Python `-O` |
| Flutter analyzer | No issues found |
| Full Flutter suite | 999 passed; 6 opt-in skips |
| Focused feed/UI regression | 240 passed; 3 opt-in skips |
| Android actual app | Passed on emulator-5558, Android 17/API37 |
| iOS actual app | Passed on iPhone Air simulator, iOS26.3 |
| Browser actual app | Home/Discover previews, Sports, Entertainment, all 21-topic menu and Real Estate inspected visually |
| Original article link | Native protected surface verified; browser opened exact original fixture URL and left Discover state intact |
| Protection/private context | Native integration checked private redaction and return to ordinary context; existing protection tests included in full suite |
| Final builds | Android debug, iOS simulator debug and web debug all passed |

The native test starts actual `app.main()`, visits all 21 controls, asserts relevant
Sports/Entertainment cards, verifies original protected navigation and exact
return scroll, enters a real private tab, confirms redaction, and restores feed
preferences. The final small RSS-attribution regression fix was separately
verified and rebuilt after these native journeys. No physical phone was connected.
The final manual native screen inspection was blocked when the Mac locked; native
journeys above are automated app execution, not a claimed final visual sign-off.

Fixture content included 12 normalized items in each 16 canonical category, 192
items total; derived Science/Technology/Food/Fashion/Travel had explicit matching
evidence. This verifies wiring and behavior, **not current U.S. publisher supply**.
No fixture photo is presented as a news photograph. Browser screenshots displayed
neutral publisher initials, original fixture titles, short previews and the linked
Currents attribution. Browser navigation opened
`https://example.com/wingman-fixture/real_estate/11`, the supplied original link.

The 48-hour fake-clock test asserts 104 base calls on each UTC day, at most 12
supplement calls/day, minimum 6-hour supplement intervals, max 4 calls/tick and
no effective-cap overrun. Tests cover all 150 local reservations, concurrent
SQLite clients, GCS CAS, crashes/restarts, lease fencing, stale content writers,
headers, UTC rollover, all specified HTTP errors, empty responses, secret
redaction, redirects/SSRF, expiry, revocations and existing source contracts.
Hundreds of repeated snapshot reads and client refresh/topic actions produce no
new upstream provider requests.

## Live API and rights status

The local durable ledger was explicitly initialized independently of content:
**0 of 150 attempts**, provider-reported remaining allowance **unknown**.
`CURRENTS_API_KEY` was absent, and the owner did not enter the local secret during
this run. Therefore `/v1/auth`, live taxonomy discovery and the single paced live
bootstrap were **not run**. Fixtures were used; no live call was bypassed around
the ledger and no failing key was retried.

| Canonical category | Live returned / permitted / visible / image counts |
| --- | --- |
| general | Not checked — local key entry pending |
| sport | Not checked — local key entry pending |
| arts_culture_entertainment | Not checked — local key entry pending |
| science_technology | Not checked — local key entry pending |
| economy_business_finance | Not checked — local key entry pending |
| society | Not checked — local key entry pending |
| politics_government | Not checked — local key entry pending |
| lifestyle_leisure | Not checked — local key entry pending |
| human_interest | Not checked — local key entry pending |
| crime_law_justice | Not checked — local key entry pending |
| education | Not checked — local key entry pending |
| environment | Not checked — local key entry pending |
| labour | Not checked — local key entry pending |
| health | Not checked — local key entry pending |
| automotive | Not checked — local key entry pending |
| real_estate | Not checked — local key entry pending |

Normal engineering expectation is 104–116 calls/day, below the 150-attempt ceiling;
250 provider calls/day and 20 results/request remain an account assumption to
verify from actual headers. Setup and metadata share the cap. No live empty
category has been diagnosed or padded with unrelated content.

API preview/link-out configuration is enabled. No separate Currents article-photo
grant has been configured, so unresolved photos are omitted and permitted text
cards stay available. Specific future image/branding grants must cover the exact
asset and pass the trusted pipeline. NewsUSA's sponsored reader/photo contract is
preserved; its native transient media path does not refetch its feed.

## Verification incident: simulator data preservation

The first Android/iOS integration commands accidentally omitted `--no-uninstall`.
Flutter's default removed the test installations after completion. Targets were
**emulator-5558** and the **iPhone Air simulator**
`81E59BB3-50A1-415D-8D5E-BC29E3AD96E0`; no physical device or other emulator was
used. This violated the requested preservation constraint: any prior app data in
those installations cannot be claimed preserved or recovered. The mistake was
disclosed during the task. No verified backup of those specific installations was
found. An older iOS container with a different bundle ID was left untouched.

The normal app was subsequently rebuilt/reinstalled. Reinstallation is not data
recovery. `scripts/test_currents_app.sh` now always passes `--no-uninstall`, and the
reproduction docs include that flag and require a dedicated test simulator.

## Reproducibility and local records

Relevant logs are under the repository's ignored `work/` directory:
`currents-backend-final.log`, `currents-analyze.log`,
`currents-flutter-final.log`, `currents-flutter-feed-final.log`,
`currents-android-integration.log`, `currents-ios-integration.log`,
`currents-android-build-final.log`, `currents-ios-build-final.log`,
`currents-web-build-final.log`, and `currents-local-ledger-status.json`.
They contain no real API key. The final task outputs include a copy of this report,
the operator guide and core verification logs. The source of truth remains the
feature branch in the real repository.
