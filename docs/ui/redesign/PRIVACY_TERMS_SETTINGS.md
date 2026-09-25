# Privacy, boundaries, supplied terms, and settings

Implemented September 25, 2026, against the current source without changing policy authority or adding a network service.

## Connected production changes

- Privacy & protection now separates installed configuration, observed request outcomes, and limitations. Usable-current, usable-stale, unavailable baseline, unobservable request counters, and observable-without-an-event states have distinct labels. Counts are provided by the actual originating page engine; the screen does not infer them from the Trust Receipt journal. Saturated counts display a plus sign. Scope names the current page engine, renderer-lifetime resets, repeated requests, and the lack of unique-tracker or whole-network coverage.
- Mandatory categories have lock indicators and explicit read-only labels. Additional restrictions, installed-rule details, Trust Receipt, quiet pause, and review preparation retain working routes. The information-flow section explains website, DuckDuckGo, configured feed/image, protection-update, and local-tool destinations, with Updates/private/configuration state derived from the supplied controller.
- Boundary recovery uses the real Wingman logo and local static painter artwork, a reason derived from the actual decision, task/session-bound callbacks, a safe back action, Home fallback, and “Prepare review details.” Category, unavailable protection, unsupported capability, and security decisions remain distinct. There is no mandatory-policy bypass.
- Before You Commit has a responsive supplied-text/evidence comparison. The existing bounded local analyzer still supplies every finding, status, excerpt, and source location. Missing/conflicting evidence, language errors, sensitive-line handling, cancellation, export preview, explicit saves, and transient private analyses retain their existing paths.
- Settings groups appearance, Home/Spaces, local tools, privacy, protection, search, Updates, and About. Local theme previews are actual controls. Gary/Wallace/Betty and reduce-motion controls use the passed session preference controller. Owner appearance and reading-size writes are now explicitly unavailable from private sessions.
- Trust Receipt gets grouped Material panels while keeping hourly redaction, preview-before-copy, session/lifecycle hiding, failure status, and deletion limits. Its existing freshness field is accurately labeled **offline article catalog freshness**, separate from consumer browsing baseline availability.

## Evidence

The `screenshots/05-privacy-*`, `06-boundary-*`, `07-commit-*`, and `08-settings-*` files are captures of production Flutter widgets running in the Flutter test renderer, with synthetic QA data only. They are not reference-gallery screenshots or proof of native-engine behavior. Captures cover 390 and 1440 logical pixels in light and dark, with an explicitly private populated terms analysis. Actual native engine acceptance is recorded separately by the native workstream.

Visual QA compared these captures to boards 05–08 and mobile-boundary. The original asset is present in boundary screenshots. The split theme preview, evidence panels, and card Material backgrounds were inspected and corrected. Additional text and scrolling intentionally preserve honest scope and readable controls; the mobile and 200% layouts stack rather than compress evidence into narrow columns. The concept's illustrative request count and subscription price are not production defaults. Practice terms appear only after an explicit practice action, and captures run the real deterministic analyzer with a fixed QA timestamp.

## Verification performed

Commands ran in the task worktree with `/opt/homebrew/bin/flutter` and exit 0 after fixes:

- `flutter test --no-pub test/signature/commit_review_test.dart test/ui/settings_library_protection_test.dart test/ui/settings_protection_visual_test.dart`: **31 passed**. Logs: `evidence/protection-settings-tests.log`.
- `flutter test --no-pub test/signature/route_commit_screens_test.dart test/signature/ui_routes_commit_test.dart test/ui/official_commit_visual_test.dart test/signature/privacy_export_widgets_test.dart`: **28 passed**. Logs: `evidence/commit-widget-tests.log`. Includes supplied-text/save/export ownership and light/dark 200% layout sweeps.
- `flutter test --no-pub --dart-define=WINGMAN_REDESIGN_CAPTURES=true test/ui/redesign_privacy_boundaries_test.dart test/ui/redesign_preferences_test.dart`: **9 passed**. Logs: `evidence/redesign-privacy-preferences-tests.log`. Six-width 200% checks cover 320/390/430/768/1024/1440; screenshot runs cover 390/1440. Preference tests verify schema 1 preservation and schema 2 writes, all tones, malformed/future-state preservation, failed-write rollback/retry, and private-session isolation.
- `flutter test --no-pub test/signature/privacy_export_widgets_test.dart test/signature/privacy_journal_test.dart test/ui/redesign_preferences_test.dart`: **24 passed** after the receipt freshness label correction. Logs: `evidence/privacy-receipt-preferences-tests.log`.
- An invocation including `test/signature/integrated_workspaces_test.dart` and the four redesign widget tests passed **12 tests**, including the real contextual-analysis-to-Trust-Receipt journey.
- Focused `flutter analyze --no-pub` on owned production modules and both new test files reported **No issues found**. Logs: `evidence/privacy-analysis.log`.

These counts describe separate overlapping invocations; they are not an aggregate unique-test total. Full-suite and native-device results are maintained in the central implementation status. No native build or release certification is implied by these widget tests.

## Full-suite handoff and backend regression

The first full Flutter invocation, `flutter test --no-pub --reporter expanded`, finished in 1:27 with **1013 passed, 6 skipped, 19 failed** (exit 1). Log: `evidence/full-tests-first.log`. None of the privacy, boundary, terms, settings, or new preference tests failed. Failures were Home/companion layout or old expectations, expanded-shell control reachability, workspace visual reachability, two intentional Home goldens, and a discovery-order expectation. Root and the workspace workstream own the remaining fixes and the final full rerun. No golden was updated by this slice.

The discovery-order test now checks Launchpad before chosen collections before secondary discovery, plus the new default module order. Persisted explicit ordering remains covered by migration tests. `flutter test --no-pub test/discovery/discovery_widgets_test.dart` passed **6 tests**, exit 0. Log: `evidence/discovery-tests.log`.

The final capture invocation passed **4 tests**, exit 0, with real initialized UI preferences and all optional settings tools shown. Log: `evidence/privacy-final-captures.log`. The policy dashboard now uses the runtime's clock consistently and labels counters as the snapshot observed when that view opened.

Backend regressions used a project-local virtual environment because system Python did not have the two required dependencies. Installed only the pinned `defusedxml==0.7.1` and `Pillow==11.3.0` from `backend/requirements.txt`; no global Python changes or upgrades. Command:

```
PYTHONPATH=backend work/redesign/backend-venv/bin/python -m unittest discover -s backend/tests
```

Final result: **186 passed**, exit 0, 11.285 seconds. Logs: `evidence/backend-tests.log` and `evidence/backend-dependencies.log`.

An initial backend run with dependencies installed exposed a pre-existing calendar-sensitive HTTP test: its content was ingested on the fixed September 11 fixture date but served using the real September 25 clock, so correct expiry filtering made the expected item unavailable. Only that test now fixes `server.datetime.now()` to its ingestion fixture time. Production backend code and the independent expiry tests are unchanged.
