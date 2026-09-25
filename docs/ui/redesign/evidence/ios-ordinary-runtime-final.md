# Ordinary iOS runtime verification — 2026-09-25

Device: dedicated `Wingman Redesign QA`, iPhone17 / iOS26.3, UUID `01739195-2E55-4714-98D6-85598023A7D8`. The physical iPhone and existing personal simulators were not used. Installed the ordinary `lib/main.dart` artifact `artifacts/ios-simulator/Wingman-stable-20260925T201929Z.app`; preserved current QA data. Bundle `com.wingmanbrowser.app`, version 0.16.0 build19. All UI interactions used CUA. `simctl` installed/launched/restarted the app and captured the dedicated simulator only.

## Observed results

- Home restored the explicitly entered QA task “Plan a weekend garden” and displayed its compact Continue action directly below search, before the empty Launchpad. Progress remained 1 of 2 checked.
- The companion restored “Choose a sunny corner” checked, “List supplies” unchecked, and the saved note “Synthetic QA note: compare two planters.” Five close/open cycles each retained that goal, checklist, and note. Native address input later accepted the complete synthetic fixture URI, confirming input remained usable after those cycles. This does not claim unsaved draft persistence across panel disposal.
- Companion “Open Finish Mode” opened the actual restored task detail, not just the task list. The previously saved IANA result remained listed.
- Added the real optional 15-minute timer. It counted down from 14:58 to 13:38 during inspection. Sent the app to background using the simulator Home button, then terminated and relaunched it. Home retained its task progress; Continue opened the timer paused at 13:30 with Start timer available. Returning to the companion again verified the saved checklist and note. This confirms the documented foreground checkpoint / paused restart behavior, not background execution.
- Opened a private tab. Home showed its private-session banner and no normal task Continue action. Its companion showed the empty user-entered-goal form with no normal task name, checklist, or notes.
- Through the ordinary private address UI, entered the reserved synthetic URI `http://gambling.protection.test/direct` already used by the native test fixture. The branded mandatory boundary reported gambling and wagering, omitted the attempted URI, offered safe recovery, and had no Continue/override. No real explicit-content site was visited. Back to Home returned to private Home.
- Closed only the synthetic private QA tab and returned to the retained normal Home. The original task remained 1/2 checked. No normal QA data was cleared.

## Captures

All paths below are in `docs/ui/redesign/screenshots/` and show actual ordinary native application UI:

- `ios-home-final-populated.png`
- `ios-companion-final-restored.png`
- `ios-finish-final-running.png`
- `ios-finish-final-checklist.png`
- `ios-finish-final-paused-restart.png`
- `ios-private-home-final.png`
- `ios-private-companion-final.png`
- `ios-private-boundary-final.png`

The later native delegate-ownership follow-up is independently tested and rebuilt; these captures establish the final shared UI and runtime behavior before that native-only follow-up. They do not claim coverage of every native permission, malformed callback, or website.
