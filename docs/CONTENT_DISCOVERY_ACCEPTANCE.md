# Free content discovery — 0.13.0+14

September 13, 2026. This milestone implements the user’s Opera reference request
inside the existing Wingman consumer browser. The six supplied screenshots are
layout references, not authority to copy Opera branding, content or photographs.
No browser-engine migration, account creation, paid API or cloud deployment was
needed. The active native feed now works without WINGMAN_FEED_URL.

## Reference review and resulting flow

1. Opera Home presents a small article preview beneath search and shortcuts.
   Wingman retains its Home/search/Launchpad and adds three compact, credited titles
   with a View all action. Long titles wrap rather than hiding the essential text.
2. The supplied News screenshots use a persistent category strip and mixed card
   sizes. Wingman Updates has a fixed single-choice topic strip, a first featured
   card, compact subsequent rows and deliberate Load more. There is no infinite
   scroll, behavioral recommendation system or notification prompt.
3. The supplied reader view makes source and date visible. Wingman labels supplied
   descriptions as publisher excerpts and opens the original article through normal
   protected navigation. It does not present a shortened excerpt as a full article
   or duplicate full article bodies. Author and license credits remain on saved items.
4. Opera’s menu sits above its browser controls. Wingman keeps its own dock/menu,
   protection rules, saved links and private-session boundaries. No remote article
   thumbnails were copied. Existing licensed category art is labeled as category
   art; topic icons supply the remaining visual cues.

The images permit visual/layout review only. They do not establish Opera’s live
accessibility semantics, tap targets, behavior, article accuracy or license rights.
Wingman’s own focused tests cover fixed-topic selection, Home/Updates/back flow,
protected callbacks, saved credit, honest empty state and 320px width at 200% text
in light and dark themes. Actual screen renders use live publisher data, not sample
headlines. They are Flutter rendering evidence, separate from native browser QA.

## Actual network evidence

The default Dart native transport fetched all 12 reviewed feeds successfully at
2026-09-13T22:23:53Z in 4,581ms. This single observation is not a performance SLA.
The resulting snapshot contains 78 eligible unique articles, 94,526 serialized
bytes and no remote images. All 12 sources were fresh. Publisher pacing was saved;
the next permitted refresh was 22:53:53Z. The opt-in verification reuses state and
cannot force premature requests simply by rerunning it.

| Topic | Articles in the native sample |
| --- | ---: |
| Headlines (general feed only) | 7 |
| Sports | 3 |
| Entertainment | 4 |
| Technology | 9 |
| Business | 4 |
| Fashion | 2 |
| Science | 48 |
| Food | 1 |
| Health | 3 |
| Environment | 37 |

Topics overlap. The UI’s Headlines tab is the complete mixed feed, not just those
seven general-feed entries. Four independent publishers supply 12 sections: NASA,
NOAA, USGS and Global Voices. Global Voices coverage is international and not an
exhaustive US breaking-news, league-score or celebrity service. Food’s newest
accepted article is August 21; Fashion September 4; Sports September 5. Dates are
kept visible. No fabricated freshness or unrelated filler compensates for sparse
sections. Known publications older than 30 days are omitted.

The separate Python backend also completed one real 12-source HTTP-200 ingestion.
An offline correction removed a Fashion-only topic mismatch from global revocations,
recovering one valid Sports story: 79 backend articles. Its retained source state
proves the correction without another upstream pass. The native sample has 78
because the client’s additional text admission checks omit one more NOAA item.
The client always applies its own current eligibility gates to either provider.

Receipts in the local work directory:
- work/rss-direct/{snapshot,report,state}.json and verification.log
- work/content-discovery/ingestion-validation/receipt-original.json
- work/content-discovery/ingestion-validation/receipt-final.json
- work/content-discovery/ui/capture-receipt.json and six PNG renders

## Validation and limits

The full Flutter host suite passes **817 tests with five opt-in skips**; the analyzer
reports no issues. The backend suite passes **70 deterministic tests**. The 31
focused RSS tests are included in the host total. Six actual-data Flutter renders
were reviewed; the dedicated UI flow suite passes 11 tests.

The Android release APK builds successfully (71.0 MB reported by Flutter). The
first attempt retained an integration-test registration in generated Java; rerunning
the release build with normal Flutter tooling generation removed that stale dev-only
registration and succeeded. No generated file or native security control was patched.
The APK retains the repository’s existing development signing configuration and is
for emulator/device testing, not a Play Store release-signing claim.
The Android APK was installed with data-preserving update on emulator-5554;
package metadata confirms versionName 0.13.0 and versionCode 14.
The unsigned iOS release build also passes for `com.wingmanbrowser.app` (38.1 MB
reported by Flutter); this compile result alone is not a device installation or
TestFlight upload. Direct simulator UI inspection was unavailable because the
Mac was locked; the user was asked to unlock it. No native browser journey on
this new build is claimed by the rendered screenshots. A signed iOS archive
succeeded and passed deep/strict code-signature verification; archived metadata
confirms com.wingmanbrowser.app, version 0.13.0, build 14 and the existing team.

New backend regressions cover Fashion
classification without cross-source revocation, mandatory author attribution,
dated article paths and rights/promotion precedence. The app’s checkpoint tests
cover normal restart/cache deletion, private/handoff cancellation, persisted opt-out,
failed writes, corrupt checkpoints, partial-source warnings and immediate saved-text
redaction after withdrawal even when the checkpoint cannot be saved.

Native fetch tests use the real consumer policy asset. Deterministic RSS tests cover
malformed and oversized XML, DTD/entities, URL and DNS restrictions, feed redirects,
conditional cache validation, quota/backoff, bounded cancellation, expiry and topic
selection/deduplication. The explicit live-network test is skipped by default.

A failed checkpoint write disables further fetches in the current controller. If
the process exits before a newly received Retry-After can be persisted, that newer
value cannot be guaranteed after restart; the last successfully stored state is
all that survives. Corrupt checkpoints are preserved and block refresh; this
version does not add an in-app checkpoint repair flow. Publisher removals learned
while offline are likewise unknowable until reconnecting; finite excerpt expiry
limits cached display. These are storage/network limits, not blanket content-safety
or perpetual-rights guarantees.

Source/article eligibility is conservative and layered with the unchanged mandatory
consumer policy. It does not classify every future sentence, image or linked page.
Publisher feed origin cannot grant a browser bypass. The U.S.-only beta scope concerns
distribution; the content itself includes reporting from around the world.

Native builds need no backend account or key. Web direct RSS is unsupported because
publisher CORS is absent; web uses an explicitly configured common HTTPS snapshot
service, which has not been deployed. No new API subscription or cloud cost was added.
Read [Source rights](CONTENT_SOURCES_AND_RIGHTS.md),
[Architecture](LIVE_CONTENT_ARCHITECTURE.md) and
[Privacy](PRIVACY_ARCHITECTURE.md) for exact boundaries.
