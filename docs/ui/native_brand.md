# Native brand and protected handoff UI

The supplied source at `assets/brand/source/wingman-logo-reference.png` and crop at `assets/brand/wingman-mark.png` remain byte-identical to the handoff package. The artwork is RGB with deliberate white highlights/background. No tracing, recoloring, white removal, invented monochrome icon or artificial vector replacement was performed.

## Platform assets

`scripts/generate_platform_brand.py` uses Pillow for proportional Lanczos resizing and added padding only. It regenerates the existing platform slots plus adaptive/splash variants. `native_brand_assets.json` records 40 generated writes with their sizes and source hash. Repeated iOS filename slots refer to the same generated image.

- Android keeps the 48/72/96/144/192px legacy launcher sizes. API 26+ uses 108 dp foreground layers with 60 dp artwork inside the 66 dp safe region and a white background. No monochrome layer is supplied because the approved source is full-color artwork. Android may apply user-selected automatic icon theming on newer system versions. [Android adaptive icon documentation](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive).
- Pre-Android 12 launch shows a 96 dp white medallion on the light/dark brand canvas. API 31+ uses the system splash attributes with a 288 dp icon canvas and 192 dp safe circle. The app adds no launch delay or animation. [Android splash screen requirements](https://developer.android.com/develop/ui/views/launch/splash-screen).
- iOS retains the existing all-size AppIcon asset catalog, including the opaque 1024 px marketing slot. LaunchImage has 96/192/288 px variants, displayed at 96 pt on a light/dark named-color background. Source artwork remains intact within added white-medallion padding. This keeps the existing static launch storyboard instead of introducing an SDK. [Apple app icon configuration](https://developer.apple.com/documentation/xcode/configuring-your-app-icon/), [launch screen configuration](https://developer.apple.com/documentation/xcode/specifying-your-apps-launch-screen).
- Web gets 192/512 px icons, 64 px favicon and 180 px Apple touch icon. Separate maskable assets keep the entire crop inside the centered 40%-radius safe circle; the manifest uses the navy theme and unrestricted orientation for responsive layouts. [Web app manifest maskable-icon guidance](https://web.dev/learn/pwa/web-app-manifest?hl=en).

`native_brand_asset_preview.png` is a visually inspected generated-asset contact sheet with illustrative masks. It is **not** a launcher or native app screenshot. A syntax check passed for native XML/JSON, every generated image's dimensions were checked, and all iOS AppIcon PNGs were verified RGB/opaque. The updated Android resources compiled in the browser-boundary debug integration build (21.3 s Gradle), and the updated iOS asset catalog/launch storyboard compiled in its simulator build (26.9 s Xcode). Both fixture suites passed with zero content views/requests: `work/ui-native-browser-android.log` and `work/ui-native-browser-ios.log`. These builds do not establish actual launcher masking or launch appearance; that visual observation remains separate.

Reproduce with a Python environment containing Pillow:

```sh
python3 scripts/generate_platform_brand.py
```

No native activity, privacy shield, secure-storage option, channel or permission was changed by this branding work. Android capture protection and the iOS inactive-scene cover remain intact. A separate tested startup reliability correction now acknowledges an actually completed iOS quarantine within the same native process; it does not change the shield, live capability boundary or explicit Clear data. See `native_validation.md`. There is no app-version capability addition; version 0.6.0+6 is supplied by the existing Flutter project configuration.

## H01–H03

The owner preview now clearly separates the exact reviewed text, shared scope and owner-return code. It has a three-step progress label, complete text preview and one primary action per step. Its scroll state resets on step changes; the code fields and lifecycle interruption remain owned by the existing setup state.

The guest has a separate opaque `Shared view` shell with a responsive Return to owner action, static-content explanation and readable article measure. Owner return uses the same code verifier, persisted marker, retry state and native incoming-link discard. The custom keypad still creates no TextInput connection, editable field, selection, clipboard or autofill session. Masked code dots wrap without exposing digit values. Error and unconfirmed-return copy retain the existing security semantics. Busy feedback reflects real operations and uses a static icon when reduced motion is requested.

`handoff_controller.dart` and `handoff_store.dart` are unchanged. No owner preference or stored workspace is read to style the guest. The gate remains above the owner MaterialApp and never builds the owner subtree while active/unavailable.

`test/ui/handoff_layout_test.dart` covers light/dark at 320×640 and 768×480 with 200% text, scroll reachability, minimum keypad targets, absent owner/input/selection and back/deep-route confinement. `handoff_visual_test.dart` provides synthetic 390×844 render captures using the bundled Roboto font. Its optional capture switch exists only in the test file, never in the app:

```sh
flutter test --no-pub test/signature/handoff_test.dart test/ui/handoff_layout_test.dart test/ui/handoff_visual_test.dart --dart-define=WINGMAN_HANDOFF_UI_CAPTURES=true
```

Scoped analysis passed in 2.3 s; 33 tests passed in 2 s (23 existing handoff security tests, 8 responsive layout checks and 2 capture journeys). Logs: `work/ui-handoff-analyze.log` and `work/ui-handoff-focused.log` in the parent workspace. Initial visual inspection caught missing icon-font loading in the capture harness and an explicit app-bar style without the shared font family. Both were corrected; all six refreshed light/dark H01–H03 captures were inspected. The combined follow-up run passed all 33 Handoff tests; the final full-suite capture run then passed 402 tests (two optional benchmark skips), and all six H renders were checked again. No app security behavior changed. These widget captures are not physical-device, screen-reader, OS-authentication or app-switcher acceptance evidence. The existing static-only handoff capability limitations in `docs/HANDOFF_SECURITY.md` still apply.

The updated Handoff UI then passed all four native preserved-install start/resume phases on Android 16 and iOS 26.3.1. Separate process IDs, real secure storage/derivation, owner-input positive control, guest/return input absence, wrong-code denial, durable owner return and zero content views/controlled requests were verified. Android's three real incoming VIEW windows also passed without later replay. See `docs/HANDOFF_SECURITY.md` for exact timings, logs and the distinction between fixture gate restoration and a production-key owner-session restart.

Final normal main artifacts were rebuilt, installed and launched after integration testing: Android debug 14.5 s and iOS simulator debug 19.8 s, both version 0.6.0+6. Android's foreground app window was confirmed secure. Logs are `work/ui-native-main-android.log` / `ui-native-main-ios.log` and their install/launch companions. These confirm packaged asset compilation and successful main launch commands, not a visual launcher-mask or splash-duration audit. The separate 40-asset contact sheet and synthetic Flutter captures retain their stated scope.
