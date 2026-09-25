# iOS toolbar history follow-up

2026-09-25. Verified: 13 selected native iOS tests passed, the ordinary simulator app rebuilt, 22 focused Dart tests passed, and the analyzer reported no issues. This artifact supersedes the earlier ownership-only build.

## Problem and change

The macOS cross-layer integration exposed a shared Apple adapter bug: pressing the toolbar Back button traversed same-document history inside WebKit, but native `pageState` retained the later URL. That left Flutter's address bar behind the actual page. A deferred URL observation alone did not resolve the integration failure.

The iOS adapter now also observes the URL when `isLoading`, `canGoBack`, or `canGoForward` changes. URL KVO still receives an immediate check and one deferred check captured to its original request and renderer lifetime. Each path passes through the existing current-renderer, current history-item and mandatory policy checks. No provisional denied destination is adopted as committed page metadata; no page script or private WebKit API was introduced.

This follows WebKit's pending navigation behavior: a toolbar traversal can publish its pending target URL before the history item settles; finishing that traversal can clear the pending request without changing the active URL again. See the upstream [page-load state implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/PageLoadState.cpp) and [history navigation implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/WebPageProxy.cpp). The runtime failure and subsequent native integration pass motivated the fix; these source details explain the observed timing.

## Regression coverage

The existing selected native method `testHistoryAPIUpdatesNativeAddressWithoutReloadOrNewDocument` now invokes Back and Forward through the native channel, matching toolbar behavior. It checks the original document entry and movement between interior entries where both history-availability flags remain true. Assertions require the native address and emitted page state to match the actual page while preserving the same renderer, document generation and page marker, with no network reload for the synthetic history entries.

The fixture retains denied-redirect and denied-history handling, retired-renderer rejection, superseded restriction restore rejection, and close-during-compilation checks from the [ownership follow-up](IOS_OWNERSHIP_FOLLOWUP.md).

## Verification

| Check | Result | Evidence |
| --- | --- | --- |
| iOS native XCTest, same 13 selected methods | 13 passed; 0 failed; 0 skipped; 20.346 seconds of XCTest execution | [Native log](evidence/ios-native-final-20260925T211144Z.log), [xcresult summary](evidence/ios-history-xctest-summary-20260925T211144Z.json) |
| Expanded history/ownership fixture | Passed in 4.503 seconds | Same native log |
| Ordinary `lib/main.dart` simulator build | Exit 0; 29.29 seconds | [Build log](evidence/ios-simulator-final-20260925T211144Z.log) |
| Dart bridge, boundary and toolbar regression files | 22 passed; 0 failed; 2 seconds | [Focused log](evidence/ios-history-dart-regressions-20260925T211144Z.log) |
| Flutter analyzer | No issues; 4.8 seconds | [Analyzer log](evidence/ios-history-analyzer-20260925T211144Z.log) |

The new ordinary artifact is [Wingman-20260925T211144Z.app](../../../artifacts/ios-simulator/Wingman-20260925T211144Z.app), bundle `com.wingmanbrowser.app`, version **0.16.0**, build **19**, with no `.xctest` bundle. It targets the same dedicated Wingman Redesign QA iPhone 17 simulator, iOS 26.3.1 (23D8133), ID `01739195-2E55-4714-98D6-85598023A7D8`. The local binary is intentionally outside Git.

The [complete native/build manifest](evidence/ios-final-summary-20260925T211144Z.json) records commands, selected/excluded test methods, source hashes, device and artifact metadata. All tracked source inputs remained unchanged across the run. Comparing these inputs with the earlier `T203524Z` run shows changes only in `ios/Runner/ProtectedWebBridge.swift` and `ios/RunnerTests/RunnerTests.swift`. Production Dart, the pubspec and Xcode project are identical, so the earlier complete **1,041 passed / 6 skipped** Flutter run remains applicable; it was not rerun for this Swift-only follow-up.

The latest focused Dart command was:

```sh
flutter test --no-pub --reporter expanded test/browser/protected_web_controller_test.dart test/browser/native_boundary_decision_test.dart test/ui/browser_back_popup_test.dart
flutter analyze --no-pub
```

Native testing remains the 13-method consumer/ownership selection, not a claim that every historical native target test ran. A subsequent [ordinary runtime smoke](evidence/ios-ownership-final-runtime.md) installed this final artifact, restored its task/checklist/notes and rendered example.com; [the final capture](screenshots/ios-history-final-example.png) records that run. The real WKWebView regression establishes the corrected native history behavior. `git diff --check` passes for source and follow-up notes.
