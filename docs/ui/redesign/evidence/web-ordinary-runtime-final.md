# Ordinary web companion runtime

2026-09-25. Final production `lib/main.dart` build served at loopback port8799; source UI commit1a31bfd. Build command/result and file hashes are in `web-build-manifest.json`. CUA drove the standard app, without injected application state or a capture entry point. Synthetic QA text was entered through visible controls.

- Completed first run; empty Home showed optional task creation, no fabricated task/progress.
- Created “Plan a weekend project,” two checklist steps and a note. Reload restored the task, notes and checklist-derived progress. The Home Continue action remained independently accessible after progress was given its own semantic container; its regression test is retained.
- Opened/closed the companion repeatedly and focused its note field. Restored notes were visible. Companion → Finish Mode opened the actual selected task after fixing the restored-task callback.
- Started the25-minute timer, observed24:53, paused, reloaded and observed the same paused24:53 state. This complements deterministic background/clock tests; it is not a performance measurement.
- Created a Home Projects Space from the existing template; edited its explicit notes. Reload preserved the Space and note. No page capture or remote thumbnail service was involved.
- Entering `example.com` handed navigation to the host browser at `https://example.com/`. Browser Back returned to the companion. Its local toolbar did not claim authority over that external page.
- Protection displayed unavailable request observation and distinguished the usable-stale installed browsing baseline from unconfigured online services.
- Switched this dedicated QA app profile to Dark; ordinary Settings matched the chosen dark preview. Before You Commit analyzed a supplied synthetic186-character selection, showing directly stated trial, recurring amount, billing, cancellation/refund and seller wording with source excerpts. It disclosed the scope and did not identify the dollar currency or certify the seller. No save, purchase or external submission occurred.

Screenshots: `web-home-empty.jpg`, `web-companion-populated.jpg`, `web-companion-restored.jpg`, `web-focus-running.jpg`, `web-space-saved.jpg`, `web-external-handoff.jpg`, `web-protection-scope.jpg`, `web-settings-dark.jpg`, `web-terms-evidence-dark.jpg`. These are original CUA JPEG bytes. The web companion cannot enforce or observe unrelated host-browser traffic.

The final runtime used the same local assets as the copied `artifacts/web-companion` directory. The local run script was separately exercised through a successful ordinary web build and server startup. No startup latency, memory-leak or jank number is claimed.
