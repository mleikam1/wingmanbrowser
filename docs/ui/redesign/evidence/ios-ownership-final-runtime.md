# Final iOS ownership build: ordinary runtime smoke

2026-09-25. Installed `artifacts/ios-simulator/Wingman-20260925T203524Z.app` on the existing dedicated QA simulator `01739195-2E55-4714-98D6-85598023A7D8`, preserving its data. This ordinary `lib/main.dart` app includes the final native delegate-ownership fixes. No Flutter or Xcode build commands were run during this smoke.

CUA observations after launch:

- Home restored “Plan a weekend garden”, showing 1 of2 steps complete and the compact Continue action.
- Opening Your Wingman restored “Choose a sunny corner” checked, “List supplies” unchecked, and “Synthetic QA note: compare two planters.” No task data was replaced.
- Closed the companion, opened the ordinary address entry, typed `https://example.com`, and submitted through the app UI. The real Example Domain document rendered inside the native WKWebView. The loading indicator finished and the shell exposed Reload protected page.

Actual simulator captures:

- `docs/ui/redesign/screenshots/ios-ownership-final-companion.png`
- `docs/ui/redesign/screenshots/ios-ownership-final-example.png`

This bounded smoke complements the final 13 selected XCTest results in `IOS_OWNERSHIP_FOLLOWUP.md` and the fuller preceding timer/private/boundary runtime evidence in `ios-ordinary-runtime-final.md`. It is not an additional claim of complete native feature coverage. The app is left on the permitted example.com page, with the normal QA task preserved.
