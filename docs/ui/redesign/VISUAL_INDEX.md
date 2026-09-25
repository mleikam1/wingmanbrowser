# Redesign visual evidence index

Updated 2026-09-25. [Open the local visual gallery](evidence-preview.html) to inspect full-resolution files. The gallery is an evidence viewer, not the application.

The indexed files include **54 production-widget renders**, **17 actual iOS simulator captures** (including one SpringBoard setup image), **10 final ordinary web captures**, **1 Android captures**, and one ordinary web baseline capture. Supplied concept boards remain design references; none is presented as a screenshot of the implementation. Reference filenames/hashes are recorded in [REFERENCE_MANIFEST](REFERENCE_MANIFEST.json).

## How to read the evidence

- **Production-widget render:** real production Flutter widgets executed in the Flutter test renderer with deterministic synthetic QA data and local controllers. These validate composition and exercised interaction/layout paths. They are not a native app/device capture or proof of WebView security, real keyboard behavior, persistence on hardware, performance or full accessibility.
- **Ordinary runtime capture:** the running production `lib/main.dart` app or its standard web build, captured through the host UI. iOS files are simulator captures, not physical-device evidence. The SpringBoard installation image only records setup.
- **Reference:** supplied PNG concept; illustrative prices, tasks and totals are not production defaults. The app uses real empty/populated state and unavailable observation where appropriate.

Final aggregate test/build status belongs to [IMPLEMENTATION_STATUS](IMPLEMENTATION_STATUS.md) and [PLATFORM_MATRIX](PLATFORM_MATRIX.md); exact final results are recorded there. Native source/test scope is in [NATIVE_AUDIT](NATIVE_AUDIT.md). The separate macOS worktree records its adapter tests, captures and limits in `../wingman-macos/docs/ui/redesign/macos/README.md`. Windows/Linux native engines remain absent.

## All nine boards

Saving and failed-first-run captures additionally come from `test/ui/preferences_reset_welcome_test.dart`, with its gated write/failure fixtures and the production theme. Widget images use a 1× capture ratio; listed PNG dimensions are also the tested logical viewport. Additional 200% text checks are recorded in the slice notes and test logs; these screenshots themselves use standard text scale. Mobile pages scroll, so one viewport is not a full-route inventory.

### 01 · Home

Reference: `01-home.png`. Capture source: [`test/ui/redesign_companion_test.dart`](../../../test/ui/redesign_companion_test.dart).

| Capture | Size |
|---|---|
| [01-home-1440-dark.png](screenshots/01-home-1440-dark.png) | 1440 × 1080 |
| [01-home-1440-light.png](screenshots/01-home-1440-light.png) | 1440 × 1080 |
| [01-home-empty-1440-dark.png](screenshots/01-home-empty-1440-dark.png) | 1440 × 1080 |
| [01-home-empty-1440-light.png](screenshots/01-home-empty-1440-light.png) | 1440 × 1080 |

### 02 · Browsing companion

Reference: `02-browse.png`. Capture source: [`test/ui/redesign_companion_test.dart`](../../../test/ui/redesign_companion_test.dart).

| Capture | Size |
|---|---|
| [02-companion-1440-dark.png](screenshots/02-companion-1440-dark.png) | 1440 × 1080 |
| [02-companion-1440-light.png](screenshots/02-companion-1440-light.png) | 1440 × 1080 |

### 03 · Spaces

Reference: `03-spaces.png`. Capture source: [`test/ui/workspace_visual_test.dart`](../../../test/ui/workspace_visual_test.dart).

| Capture | Size |
|---|---|
| [03-spaces-1024-dark.png](screenshots/03-spaces-1024-dark.png) | 1024 × 1080 |
| [03-spaces-1024-light.png](screenshots/03-spaces-1024-light.png) | 1024 × 1080 |
| [03-spaces-1440-dark.png](screenshots/03-spaces-1440-dark.png) | 1440 × 1080 |
| [03-spaces-1440-light.png](screenshots/03-spaces-1440-light.png) | 1440 × 1080 |
| [03-spaces-320-dark.png](screenshots/03-spaces-320-dark.png) | 320 × 844 |
| [03-spaces-320-light.png](screenshots/03-spaces-320-light.png) | 320 × 844 |
| [03-spaces-390-dark.png](screenshots/03-spaces-390-dark.png) | 390 × 844 |
| [03-spaces-390-light.png](screenshots/03-spaces-390-light.png) | 390 × 844 |
| [03-spaces-430-dark.png](screenshots/03-spaces-430-dark.png) | 430 × 844 |
| [03-spaces-430-light.png](screenshots/03-spaces-430-light.png) | 430 × 844 |
| [03-spaces-768-dark.png](screenshots/03-spaces-768-dark.png) | 768 × 844 |
| [03-spaces-768-light.png](screenshots/03-spaces-768-light.png) | 768 × 844 |

### 04 · Finish Mode

Reference: `04-focus.png`. Capture source: [`test/ui/workspace_visual_test.dart`](../../../test/ui/workspace_visual_test.dart).

| Capture | Size |
|---|---|
| [04-focus-1024-dark.png](screenshots/04-focus-1024-dark.png) | 1024 × 1080 |
| [04-focus-1024-light.png](screenshots/04-focus-1024-light.png) | 1024 × 1080 |
| [04-focus-1440-dark.png](screenshots/04-focus-1440-dark.png) | 1440 × 1080 |
| [04-focus-1440-light.png](screenshots/04-focus-1440-light.png) | 1440 × 1080 |
| [04-focus-320-dark.png](screenshots/04-focus-320-dark.png) | 320 × 844 |
| [04-focus-320-light.png](screenshots/04-focus-320-light.png) | 320 × 844 |
| [04-focus-390-dark.png](screenshots/04-focus-390-dark.png) | 390 × 844 |
| [04-focus-390-light.png](screenshots/04-focus-390-light.png) | 390 × 844 |
| [04-focus-430-dark.png](screenshots/04-focus-430-dark.png) | 430 × 844 |
| [04-focus-430-light.png](screenshots/04-focus-430-light.png) | 430 × 844 |
| [04-focus-768-dark.png](screenshots/04-focus-768-dark.png) | 768 × 844 |
| [04-focus-768-light.png](screenshots/04-focus-768-light.png) | 768 × 844 |

### 05 · Privacy and protection

Reference: `05-privacy.png`. Capture source: [`test/ui/redesign_privacy_boundaries_test.dart`](../../../test/ui/redesign_privacy_boundaries_test.dart).

| Capture | Size |
|---|---|
| [05-privacy-1440-dark.png](screenshots/05-privacy-1440-dark.png) | 1440 × 1100 |
| [05-privacy-1440-light.png](screenshots/05-privacy-1440-light.png) | 1440 × 1100 |
| [05-privacy-390-dark.png](screenshots/05-privacy-390-dark.png) | 390 × 900 |
| [05-privacy-390-light.png](screenshots/05-privacy-390-light.png) | 390 × 900 |

### 06 · Calm boundary

Reference: `06-blocked.png / mobile-boundary.png`. Capture source: [`test/ui/redesign_privacy_boundaries_test.dart`](../../../test/ui/redesign_privacy_boundaries_test.dart).

| Capture | Size |
|---|---|
| [06-boundary-1440-dark.png](screenshots/06-boundary-1440-dark.png) | 1440 × 1100 |
| [06-boundary-1440-light.png](screenshots/06-boundary-1440-light.png) | 1440 × 1100 |
| [06-boundary-390-dark.png](screenshots/06-boundary-390-dark.png) | 390 × 900 |
| [06-boundary-390-light.png](screenshots/06-boundary-390-light.png) | 390 × 900 |

### 07 · Before You Commit

Reference: `07-commit.png`. Capture source: [`test/ui/redesign_privacy_boundaries_test.dart`](../../../test/ui/redesign_privacy_boundaries_test.dart).

| Capture | Size |
|---|---|
| [07-commit-1440-dark.png](screenshots/07-commit-1440-dark.png) | 1440 × 1100 |
| [07-commit-1440-light.png](screenshots/07-commit-1440-light.png) | 1440 × 1100 |
| [07-commit-390-dark.png](screenshots/07-commit-390-dark.png) | 390 × 900 |
| [07-commit-390-light.png](screenshots/07-commit-390-light.png) | 390 × 900 |

### 08 · Settings

Reference: `08-settings.png`. Capture source: [`test/ui/redesign_privacy_boundaries_test.dart`](../../../test/ui/redesign_privacy_boundaries_test.dart).

| Capture | Size |
|---|---|
| [08-preferences-saving-light.png](screenshots/08-preferences-saving-light.png) | 800 × 600 |
| [08-settings-1440-dark.png](screenshots/08-settings-1440-dark.png) | 1440 × 1100 |
| [08-settings-1440-light.png](screenshots/08-settings-1440-light.png) | 1440 × 1100 |
| [08-settings-390-dark.png](screenshots/08-settings-390-dark.png) | 390 × 900 |
| [08-settings-390-light.png](screenshots/08-settings-390-light.png) | 390 × 900 |

### 09 · Mobile and private

Reference: `09-mobile.png / mobile-home.png / mobile-wingman.png`. Capture source: [`test/ui/redesign_companion_test.dart`](../../../test/ui/redesign_companion_test.dart).

| Capture | Size |
|---|---|
| [09-mobile-home-dark.png](screenshots/09-mobile-home-dark.png) | 390 × 844 |
| [09-mobile-home-light.png](screenshots/09-mobile-home-light.png) | 390 × 844 |
| [09-mobile-wingman-dark.png](screenshots/09-mobile-wingman-dark.png) | 390 × 844 |
| [09-mobile-wingman-light.png](screenshots/09-mobile-wingman-light.png) | 390 × 844 |
| [09-private-home-dark.png](screenshots/09-private-home-dark.png) | 390 × 844 |
| [09-private-home-light.png](screenshots/09-private-home-light.png) | 390 × 844 |
| [09-welcome-save-failure-light.png](screenshots/09-welcome-save-failure-light.png) | 800 × 600 |

## Ordinary running iOS app and setup

These original files are 1206 × 2622 physical pixels from a dedicated iOS simulator. They show the installed ordinary application; no synthetic gallery entry point is involved. QA notes/tasks were entered for the exercise. They do not establish physical-device or App Store acceptance. Exact build/runtime/native-test results are recorded separately.

| Capture | Observed surface |
|---|---|
| [ios-companion-final-restored.png](screenshots/ios-companion-final-restored.png) | Ordinary iOS simulator capture; see runtime ledger for exact journey. |
| [ios-finish-final-checklist.png](screenshots/ios-finish-final-checklist.png) | Ordinary iOS simulator capture; see runtime ledger for exact journey. |
| [ios-finish-final-paused-restart.png](screenshots/ios-finish-final-paused-restart.png) | Ordinary iOS simulator capture; see runtime ledger for exact journey. |
| [ios-finish-final-running.png](screenshots/ios-finish-final-running.png) | Ordinary iOS simulator capture; see runtime ledger for exact journey. |
| [ios-home-current.png](screenshots/ios-home-current.png) | Ordinary production app Home after setup. |
| [ios-home-final-populated.png](screenshots/ios-home-final-populated.png) | Ordinary iOS simulator capture; see runtime ledger for exact journey. |
| [ios-install-springboard.png](screenshots/ios-install-springboard.png) | Simulator SpringBoard installation/setup. This is not an application-screen capture. |
| [ios-native-example-page.png](screenshots/ios-native-example-page.png) | Ordinary app WKWebView displaying benign example.com. |
| [ios-native-forward-iana.png](screenshots/ios-native-forward-iana.png) | Ordinary app WKWebView after forward navigation to IANA. |
| [ios-ordinary-first-launch.png](screenshots/ios-ordinary-first-launch.png) | Ordinary production app first launch. |
| [ios-ownership-final-companion.png](screenshots/ios-ownership-final-companion.png) | Ordinary iOS simulator capture; see runtime ledger for exact journey. |
| [ios-ownership-final-example.png](screenshots/ios-ownership-final-example.png) | Ordinary iOS simulator capture; see runtime ledger for exact journey. |
| [ios-private-boundary-final.png](screenshots/ios-private-boundary-final.png) | Ordinary iOS simulator capture; see runtime ledger for exact journey. |
| [ios-private-companion-final.png](screenshots/ios-private-companion-final.png) | Ordinary iOS simulator capture; see runtime ledger for exact journey. |
| [ios-private-home-final.png](screenshots/ios-private-home-final.png) | Ordinary iOS simulator capture; see runtime ledger for exact journey. |
| [ios-wingman-empty.png](screenshots/ios-wingman-empty.png) | Ordinary app companion before task population. |
| [ios-wingman-populated.png](screenshots/ios-wingman-populated.png) | Ordinary app companion with explicitly entered QA task/checklist/notes. |

## Ordinary web baseline

[before-home-web.jpg](screenshots/before-home-web.jpg) — actual ordinary pre-redesign web companion at 1280 × 720. The original CUA JPEG bytes are preserved; its filename extension was corrected from `.png` to `.jpg`. This is the before image, not a final redesign runtime screenshot.

## Behavior and verification records

- [Privacy, boundary, terms and Settings slice](PRIVACY_TERMS_SETTINGS.md): 390/1440 captures, six-width/200% checks, real analyzer and preference durability/privacy tests.
- [Spaces and Finish Mode slice](spaces-finish-mode.md): layout widths, local state migration, timer, save and task scope checks.
- [Native audit](NATIVE_AUDIT.md): what Android can count and what iOS cannot observe; actual native regression evidence.
- [Initial aggregate test log](evidence/full-tests-first.log): a historical failing run that drove fixes; not the final result.
- [Backend regression log](evidence/backend-tests.log): existing feed backend tests after only a fixed-clock test-fixture repair. Production feed/backend behavior is unchanged.
- [Run/rollback instructions](LOCAL_RUN_AND_ROLLBACK.md), [privacy/capability scope](PRIVACY_CAPABILITIES.md), [release notes](RELEASE_NOTES.md).

The static gallery contains no analytics, remote assets or production app logic. Open an individual image for full resolution. Rebuild the index after adding captures with `python3 work/redesign/build_evidence_index.py` from the UI worktree; this only updates documentation/index files and does not run Flutter.

## Final web companion

Ordinary lib/main.dart web companion; scope and journeys in evidence/web-ordinary-runtime-final.md.

| Capture | Size |
|---|---|
| [web-companion-populated.jpg](screenshots/web-companion-populated.jpg) | 1280 × 720 |
| [web-companion-restored.jpg](screenshots/web-companion-restored.jpg) | 1280 × 720 |
| [web-external-handoff.jpg](screenshots/web-external-handoff.jpg) | 1280 × 720 |
| [web-focus-running.jpg](screenshots/web-focus-running.jpg) | 1280 × 720 |
| [web-home-empty.jpg](screenshots/web-home-empty.jpg) | 1280 × 720 |
| [web-home-final-dark.jpg](screenshots/web-home-final-dark.jpg) | 1280 × 720 |
| [web-protection-scope.jpg](screenshots/web-protection-scope.jpg) | 1280 × 720 |
| [web-settings-dark.jpg](screenshots/web-settings-dark.jpg) | 1280 × 720 |
| [web-space-saved.jpg](screenshots/web-space-saved.jpg) | 1280 × 720 |
| [web-terms-evidence-dark.jpg](screenshots/web-terms-evidence-dark.jpg) | 1280 × 720 |

## Android ordinary runtime

Dedicated emulator; read the Android runtime ledger for observed and blocked UI checks.

| Capture | Size |
|---|---|
| [android-release-launch-blocked-system-ui.png](screenshots/android-release-launch-blocked-system-ui.png) | 1080 × 2400 |
