# iOS native callback ownership follow-up

2026-09-25. Source changes in the UI worktree, coordinated with the separate macOS adapter. Final verification passed: 13 selected iOS native tests, 1,041 Flutter tests (6 skipped), and analyzer with no issues. An ordinary iOS simulator app was rebuilt after native testing.

The independent macOS review identified callback ownership patterns also present in `ios/Runner/ProtectedWebBridge.swift`:

- A queued redirect callback from a retired WKWebView could publish a denial using its replacement's current request ID. The callback now requires the same current renderer and an available mandatory protection baseline.
- Restriction compilation retained the old page URL but restored it using the latest request ID. A newer explicit navigation could therefore briefly receive state for the old destination. Restore now captures its original request ID and the renderer lifetime immediately after the intentional restriction-release operation. Both must remain current before reopening.
- Deferred opens while rules compile now capture that same lifetime revision. Every native release increments it, so close/cleanup invalidates queued loads even while Flutter still retains the platform-view wrapper. Compiled rules may finish preparing, but a late completion cannot authorize restoring a released page.

Mandatory classification, installed content rules, strict search, private website stores, popup ownership and ordinary history behavior are unchanged. The UI iOS adapter retains its existing inline Apple helpers; the macOS branch's shared-source extraction was not copied into this worktree. iOS already covers inactive scenes natively, so the separate macOS privacy-cover fix does not apply here.

## Regression exercised

`RunnerTests/RunnerTests/testHistoryAPIUpdatesNativeAddressWithoutReloadOrNewDocument` now exercises the real adapter, compiled WebKit rules and the existing bounded local HTTP fixture. Its original history, denied-redirect and no-request-to-denied-path assertions remain. Added assertions cover:

1. A retired renderer's redirect callback cannot emit a boundary for its replacement.
2. A newer explicit navigation does not receive an old restore URL under its request ID.
3. Closing during pending compilation cancels a polling open; its URL never reaches the fixture server.
4. Closing during compilation with **no** newer request also cancels the saved restore. The previously opened fixture URL is requested exactly once and no renderer reappears.

The test messenger records completed native method calls so close assertions wait for rule compilation to finish. The tests use benign loopback fixture pages and do not visit prohibited destinations.

The expanded test passed after a source rebuild, alongside these existing ownership regressions:

- `RunnerTests/RunnerTests/testNativePopupAdoptionRetainsPostOpenerAndPrivateProfile`
- `RunnerTests/RunnerTests/testPopupLeaseRejectsChangedDocumentProfileRestrictionAndExpiry`
- `RunnerTests/RunnerTests/testHiddenWebActivityEndsCaptureAndReturnNeverRestartsCapture`
- `RunnerTests/RunnerTests/testConsumerConfigurationPreservesNormalCookiesSeparatesPrivateAndEnablesJavaScript`
- `RunnerTests/RunnerTests/testExpectedPolicyCancellationNeverSuppressesCertificateOrNetworkErrors`

## Final verification

| Check | Result | Evidence |
| --- | --- | --- |
| iOS native XCTest, 13 selected methods | 13 passed; 0 failed; 0 skipped; 27.355 seconds of XCTest execution | [Native log](evidence/ios-native-final-20260925T203524Z.log), [xcresult summary](evidence/ios-ownership-xctest-summary-20260925T203524Z.json) |
| Expanded history and ownership fixture | Passed in 5.024 seconds | Same native log and result bundle |
| Ordinary `lib/main.dart` simulator build | Exit 0; 59.09 seconds | [Build log](evidence/ios-simulator-final-20260925T203524Z.log) |
| Complete Flutter suite after native follow-up | 1,041 passed; 6 skipped; 0 failed; 2m10s | [Full suite log](evidence/flutter-final-after-ios-20260925T204000Z.log) |
| Saving and failure screenshot fixtures | 5 passed; 0 failed; 4 seconds | [Capture log](evidence/preferences-state-captures-final-20260925T204500Z.log) |
| Flutter analyzer | No issues; 7.2 seconds | [Analyzer log](evidence/analyzer-final-after-ios-20260925T204600Z.log) |

Native testing used the dedicated **Wingman Redesign QA** iPhone 17 simulator, iOS 26.3.1 (23D8133), arm64, ID `01739195-2E55-4714-98D6-85598023A7D8`. These are simulator results, not physical-device certification. The native selection intentionally excludes the two historical restricted-mode fixtures named in the [complete command and source manifest](evidence/ios-final-summary-20260925T203524Z.json); it does not claim the entire native test target ran.

The ordinary artifact is [Wingman-20260925T203524Z.app](../../../artifacts/ios-simulator/Wingman-20260925T203524Z.app), bundle `com.wingmanbrowser.app`, version **0.16.0**, build **19**. It uses `lib/main.dart` and contains no `.xctest` bundle. All Dart sources, iOS Swift sources/tests, the Xcode project and pubspec were hashed before and after the native tests/build and remained unchanged. The manifest stores both hash sets, commands, selected method names and artifact metadata. The local binary is intentionally excluded from Git.

The native invocation was `xcodebuild test` against `ios/Runner.xcworkspace`, scheme `Runner`, Debug simulator configuration, the device above, no parallel testing and `CODE_SIGNING_ALLOWED=NO FLUTTER_TARGET=lib/main.dart`. Its exact 13 `-only-testing` arguments and result-bundle path are recorded in the manifest. The ordinary build command was:

```sh
flutter build ios --simulator --debug --no-pub --target lib/main.dart
```

The final shared checks were:

```sh
flutter test --no-pub --reporter expanded
flutter test --no-pub --reporter expanded --dart-define=WINGMAN_REDESIGN_CAPTURES=true test/ui/preferences_reset_welcome_test.dart
flutter analyze --no-pub
```

The two additional images are widget-harness captures of production saving/failure UI, not native-device screenshots. Earlier runtime screenshots precede this Swift follow-up; current artifact runtime checks are documented separately by the runtime QA task. `git diff --check` passes for the changed Swift files and this note.

