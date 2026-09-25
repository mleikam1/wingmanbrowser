> **Native macOS branch addendum (2026-09-25).** This branch starts from the completed UI checkpoint and adds the native macOS target. The current shared UI/mobile/web evidence is maintained in the [sibling UI implementation status](../../../../wingman-browser/docs/ui/redesign/IMPLEMENTATION_STATUS.md). The desktop implementation, exact tests, artifact, and remaining foreground-input acceptance gap are recorded in [macOS verification](macos/README.md). Older checklist text below is inherited checkpoint history, not the final desktop result.

# Verification ledger

Date:2026-09-25. macOS15.7.4 arm64; Flutter3.44.4/Dart3.12.2; Xcode26.3; Java17. Commands ran from the UI worktree unless specified. Logs are local evidence; generated build output is not a release certification.

| Check | Result at UI checkpoint | Log |
|---|---|---|
| `flutter analyze --no-pub` |0, no issues,3.9s; final rerun after lifecycle guard pending |`work/redesign/analyze-final.log`|
| Baseline `flutter test --no-pub` |997 pass,6 skipped,2 pre-existing stale AppVersion failures |`work/redesign/baseline-tests.log`|
| `flutter test --no-pub test/ui/home_navigation_test.dart test/ui/redesign_companion_test.dart --update-goldens --dart-define=WINGMAN_REDESIGN_CAPTURES=true` |0;10 pass; production Home/companion light/dark captures refreshed and inspected |`work/redesign/home-final.log`|
| `flutter test --no-pub test/ui/clear_data_navigation_test.dart test/ui/focus_scope_integration_test.dart` |0;10 pass after disposed-notifier lifecycle fix |`work/redesign/ownership-final.log`|
| Aggregate before final lifecycle guard |1039 pass,6 skipped,1 fail:confirmed clear after Shell teardown. Actual regression fixed; test retained |`work/redesign/full-tests-before-lifecycle-fix.log`|
| Final aggregate/analyzer |Running at checkpoint; replace with actual final outcome |`work/redesign/full-tests-final.log`|
| `PYTHONPATH=backend work/redesign/backend-venv/bin/python -m unittest discover -s backend/tests` |0;186 pass,11.285s. Production feeds unchanged; fixed clock only in one old cache test |`docs/ui/redesign/evidence/backend-tests.log`|
| Android JVM |0;23 pass including5 actual-counter state/concurrency tests |`docs/ui/redesign/evidence/android-native-tests.log`|
| Android native integration |Counter/private-store/reset journey passed; latest typed-event/additional-restriction assertions pending final rerun |`NATIVE_AUDIT.md`|
| iOS ordinary build/runtime |Initial simulator build and ordinary page/back/forward/task flows passed. Latest native reason changes and13 XCTest cases pending final rerun |`NATIVE_AUDIT.md`|
| Web |Baseline release build and ordinary first-run passed; final build/runtime pending |`work/redesign/baseline-web-build.log`|
| macOS |Separate branch starts from completed shared UI checkpoint; no desktop pass claimed yet |`PLATFORM_MATRIX.md`|

Six default-suite skips are existing opt-ins:live editorial native network,live RSS,live content smoke,content snapshot capture,filter benchmark,catalog benchmark. No new test was disabled. Tests use benign fixtures; no live feed quota was consumed.

Goldens changed because the Home design intentionally changed, after responsive/layout and semantic checks. Device/iOS screenshots and widget-harness screenshots are labeled separately in the visual index. No startup/jank/leak performance number is claimed without measurement. Existing native resource interception/redirect limits remain documented in the engine contract and coverage files.
