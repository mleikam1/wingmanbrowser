# Redesign privacy and capability boundaries

Current implementation note, 2026-09-25, version 0.16.0+19. This updates the redesign's presentation and local state; it is not a published operator privacy policy or release certification. See the [platform matrix](PLATFORM_MATRIX.md) and [verification ledger](IMPLEMENTATION_STATUS.md) for current execution status.

## Protection and observation

Mandatory pornography, gambling, alcohol, illegal-drug, tobacco/vape and malicious-content protections retain the existing policy authority. There is no category-off switch, temporary allow path, tone-dependent rule or Finish Mode exception. Additional restrictions can narrow access. Known coverage gaps, update/distribution limitations and engine limits remain documented in [PROTECTION_COVERAGE](../../PROTECTION_COVERAGE.md) and the [engine contract](../../BROWSER_ENGINE_CONTRACT.md). A permitted address is not a safety certification.

The dashboard distinguishes configured rules, actual observed activity and limitations. It reads installed browsing baseline freshness separately from offline article-catalog freshness. It does not fabricate a threat total, privacy score, unique-tracker count or time saved.

| Surface/platform | Honest observation scope |
|---|---|
| Android | Actual policy-denied `shouldInterceptRequest` outcomes from this tab's current native page engine. Renderer lifetime only; resets on release/recreation. Retries of one address are separate outcomes. Count saturates at 100,000 and is labelled with a plus when saturated. |
| iOS | Request-level blocking totals are not observable by this adapter; value remains unavailable, not zero. |
| Web companion | Cannot observe or enforce unrelated host-browser traffic. No blocking total is invented. |
| macOS | Separate native worktree implements AppKit WKWebView; request-level totals remain explicitly unobservable. Native acceptance is recorded in its own ledger. |

A dashboard reading is a snapshot at opening. An observable engine without a status value says no observation is available yet. Android counters exclude other renderers, main-frame decisions, TLS failures, downloads and traffic that does not pass the guarded interception callback. No URL metadata is required for the counter. Normal/private counters stay separate; obsolete native callbacks are rejected. See [NATIVE_AUDIT](NATIVE_AUDIT.md) for source and test evidence.

Typed native denial events preserve reason without exporting blocked URL/title. Calm boundary text differentiates category refusal, unavailable protection, a security failure and unsupported navigation. Home, safe back, an eligible captured task and review preparation remain recovery paths; none overrides mandatory policy.

## Local data and private handling

- The companion shows only the captured tab/task's real checklist, notes and available actions. Pending edits recheck ownership; an invalidated capture stops exposing stale content. Opening the panel does not extract a page or call cloud AI.
- Space/task schema 2 adds bounded explicitly saved permitted pages. Only normal-session explicit saves persist. Policy is rechecked on save/open; pages are labelled from safe host metadata. No screenshot, article text, automatic browsing history or remote preview is stored by this feature. See [Spaces and Finish Mode](spaces-finish-mode.md) for exact URL bounds and migration behavior.
- Timer state is local and optional. Background/restart restores a paused saved checkpoint. Abrupt process death can lose the fraction since the last successful checkpoint. Parking is in-memory tab organization, not a promise to unload engines or preserve forms.
- Before You Commit analyzes supplied text locally and presents evidence, source positions and uncertainty. It does not silently inspect arbitrary pages or promise legal/financial conclusions. Saves are explicit and normal-only; private results are transient. Export remains explicit preview/copy, with existing scope and lifecycle checks.
- `UiPreferences` schema 2 stores local tone and reduced motion beside Home layout. Old schema 1 documents preserve explicit choices; an explicit successful edit migrates. Corrupt/future data is preserved until explicit reset, and failed writes retain the previous snapshot. Private preferences are ephemeral and do not access the normal document. Global appearance controls are read-only in private Settings.
- Trust Receipt remains a bounded local journal with previewed export. Its catalog freshness wording now explicitly separates offline article status from the installed browsing baseline.

Android private browsing uses the supported disposable native profile; iOS uses a nonpersistent WKWebView store. The web companion's private app state cannot make the user's host browser private. OS/browser storage, website behavior, clipboard recipients and network observers retain their documented boundaries. This redesign does not introduce telemetry or a backend page-analysis service.

## Existing feeds

Production feed retrieval, source lists, filtering, ordering, caching, refresh schedule and backend behavior are unchanged. Settings and the dashboard link to the existing Updates preferences and describe their actual status. Tone, private appearance and the companion do not add polling. The backend regression repair only freezes a pre-existing HTTP ETag test clock; it changes no production backend code. Full test/build acceptance is tracked separately.
