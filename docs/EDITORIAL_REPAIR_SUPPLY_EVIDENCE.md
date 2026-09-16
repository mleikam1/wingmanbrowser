# Editorial repair supply evidence — September 16, 2026 UTC

**Delivery:** the image gate repair makes permitted text available while optional photographs are missing or deferred. **Coverage:** the requested Sports and Entertainment targets are **not met**. No new publisher was activated, no paid API was added, and these international feeds do not establish a U.S.-only inventory.

This comparison fixes the observation clock at **2026-09-16 01:18:24 UTC** (September 15, 8:18 p.m. Central). It uses the preserved September 16, 01:11–01:15 UTC publisher captures and the completed bounded photo pass. The original code is commit **`712cfd5fdf94b6b7620fb6b3b7978f40310b8a78`**; the repaired code is the uncommitted working tree based on that commit. Deployment and device verification are separate from this supply report.

The original parser and registry were replayed offline against the fourteen saved HTTP 200 bodies. Sports and Entertainment used the original version-six normalized records confirmed by the saved HTTP 304 responses. Both sides use the same **24 previously decoded, permitted Science X thumbnails**. The original `requireStoryImages: true` rule admits only those image-backed records; the repaired rule retains permitted text independently. Socket creation is disabled during this comparison. **No publisher or media request was made to prepare this report.**

| Category | Enabled publisher operators, before → after | Fetched/revalidated records, same input | Eligible cards, before → after | Image cards, before → after | Text cards, before → after | Newest eligible after, UTC | Remaining blocker |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Headlines | 5 → 5 | 285 | 24 → 172 | 24 → 24 | 0 → 148 | Sep 16, 00:40 | International mix; most stories have no currently available photo |
| Sports | 1 → 1 | 15 | 0 → 3 | 0 → 0 | 0 → 3 | Sep 5, 05:00 | No relevant story ≤72h, no second publisher or cleared photo |
| Entertainment | 1 → 1 | 15 | 0 → 1 | 0 → 0 | 0 → 1 | Sep 13, 12:00 | One relevant story ≤72h, no second publisher or cleared photo |
| Business | 2 → 2 | 45 | 0 → 5 | 0 → 0 | 0 → 5 | Sep 14, 09:19 | Only one story ≤72h; no decoded photo |
| Technology | 3 → 3 | 65 | 8 → 45 | 8 → 8 | 0 → 37 | Sep 15, 23:00 | Remaining image work is deferred within the bounded queue |
| Science | 5 → 5 | 105 | 8 → 81 | 8 → 8 | 0 → 73 | Sep 16, 00:13 | Some photos are deferred; text grants do not clear arbitrary photos |
| Food | 1 → 1 | 15 | 0 → 1 | 0 → 0 | 0 → 1 | Aug 21, 07:16 | Older feature outside the 14-day lifestyle window; no photo |
| Health | 2 → 2 | 45 | 8 → 33 | 8 → 8 | 0 → 25 | Sep 16, 00:40 | Remaining image work is deferred within the bounded queue |
| Fashion | 1 → 1 | 15 | 0 → 2 | 0 → 0 | 0 → 2 | Sep 4, 20:56 | Sparse supply from one publisher; no photo |
| Travel | 0 → 0 | 0 | 0 → 0 | 0 → 0 | 0 → 0 | None | No enabled non-sponsored editorial source |
| Environment | 2 → 2 | 40 | 0 → 37 | 0 → 0 | 0 → 37 | Sep 16, 00:13 | Configured NOAA/USGS feeds have no approved story-photo grant |

“Eligible cards” means common-delivery records surviving the indicated image rule, **before** any additional device policy/classifier or user-preference decision. This is a controlled reconstruction, not a screenshot of an old installed app. Before the image rule, the original common snapshot had 173 records; the repaired snapshot has 172. The tighter Entertainment scope removes unrelated Arts/Culture records; category provenance and URL deduplication retain one complete source representation, so topic counts are not fabricated by merging permissions across duplicate entries. Headline totals are the finite cross-category mix; category rows overlap and must not be summed.

The 30-day eligibility ceiling is a retention limit, not a freshness claim. For this report, Food, Fashion and Travel are also compared against a **14-day lifestyle window**: respectively **0, 2 and 0** stories qualify. This analytical window does not change app retention or publication dates. The report records exact dates, IDs and canonical links in its JSON evidence. Older Food/Sports entries are not relabeled as new.

## Sports and Entertainment acceptance

| Category | Relevant stories ≤72h / minimum 5 | Publishers with ≤72h stories / minimum 2 | Permitted decoded story images ≤72h / minimum 3 | Result |
| --- | ---: | ---: | ---: | --- |
| Sports | 0 / 5 | 0 / 2 | 0 / 3 | Not met |
| Entertainment | 1 / 5 | 1 / 2 | 0 / 3 | Not met |

Both categories have one configured publisher, Global Voices, but Sports has no recent article from it. Actual Sports articles concern Haiti, Cameroon and other international football reporting. The one current Entertainment item concerns Casablanca's music scene. No U.S.-based supply claim is made.

The focused rights review found commercial-use barriers for [FanSided](https://fansided.com/terms), [Yahoo Sports](https://legal.yahoo.com/us/en/yahoo/terms/otos/index.html), and [Deadline/Variety under PMC](https://www.pmc.com/terms-of-use). Their RSS links alone are not a commercial text/photo grant. Global Voices [permits attributed commercial text reuse](https://globalvoices.org/about/global-voices-attribution-policy/) but separately credited third-party photographs remain uncleared. These sources were not promoted through the text-fallback path. The [full focused rights matrix](EDITORIAL_SUPPLY_REVIEW.md) records current grants and bounded alternatives.

## Registry and evidence checks

The backend and generated client registry agree: **17 enabled entries**, of which **16 are non-sponsored editorial endpoints belonging to five independent publisher operators**. Fourteen editorial entries have explicit `publisherId`: nine Global Voices sections → `global-voices`, two NASA feeds → `nasa`, three Science X brands → `science-x`. NOAA and USGS use their distinct publisher-name fallback. Science X owns three editorial brands; the diversity totals conservatively count that shared operator once. No missing `publisherId` was interpreted as a newly discovered publisher.

NewsUSA is the seventeenth entry and remains sponsored syndication, with its complete associated article, attribution and existing image coupling preserved. It is excluded from every editorial target and table above. The four separate legacy bundled photographs are also excluded. Deferred image outcomes were not counted as failures or successes. Thumbnail availability here is historical at the observation clock; the report does not extend expired media cache permission.

Preserved machine evidence is in `work/editorial-repair/supply/before-after.json`, with per-category before/after IDs, canonical links, exact timestamps, registry hashes, original parser outcomes and next-due checkpoints. `compare_offline.py` reproduces it without network access. Original captures, `coverage.json` and `image-requests.json` retain the earlier request receipts; `measure_supply.py` was **not** rerun.

The related synthetic widget regressions passed **22/22** (`test/ui/editorial_delivery_widgets_test.dart` and `test/ui/live_content_widgets_test.dart`), checking optional-image resilience, stable IDs/scroll, denied rights, canonical links and 200% text/semantic activation. Those tests establish behavior, not live editorial supply. Real-device checks, the final working-tree build and deployment status belong to the main delivery report.
