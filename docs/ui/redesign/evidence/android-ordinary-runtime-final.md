# Ordinary Android release runtime verification — 2026-09-25

Artifact: `artifacts/android/Wingman-0.16.0+19-local-release.apk`, ordinary `lib/main.dart` release-mode build. Package `com.wingmanbrowser.wingman_browser`, version0.16.0 / code19, minSdk24 / targetSdk36. SHA256 `ca3ae31469cf94a65768f6495ceb6842e384c7189680b72db6ffd42c6c856620`. Existing local debug-signing fallback was unchanged; this is local release-mode QA, not store-signing acceptance.

Target: dedicated task AVD `Wingman_Redesign_QA_20260925`, emulator-5560. Other emulators and personal devices were untouched. The task-local AVD disk/data were retained; no wipe or uninstall was performed.

## Verified

- Installed the ordinary APK with `adb -s emulator-5560 install -r ...`: Success.
- Launched `com.wingmanbrowser.wingman_browser/.MainActivity`: command succeeded. The installed package reports versionCode19 and versionName0.16.0; resumed activity is the expected MainActivity.
- Read-only device screenshot succeeded. Inspection shows **Android “System UI isn’t responding”** over a black screen. It does not establish that Wingman crashed, nor that Wingman Home rendered. The dedicated crash-buffer read was empty.
- APK metadata and installed metadata/hash are retained in `android-ordinary-apk-metadata.txt` and `android-ordinary-installed-metadata.json`.

## Verification blocker

Manual Home/companion/native-browser CUA journeys are **not verified** on this ordinary release installation. The standalone SDK emulator is absent from CUA app inventory; selecting its exact binary path or observed process name returns “Invalid app”. Android Studio selection timed out twice, and a fresh CUA inventory exposed no usable emulator window. No alternate UI-input automation was used.

Only this dedicated AVD was temporarily restarted in GUI mode to expose it to CUA. That did not expose a supported surface and its adb requests stalled. A targeted reconnect affected only emulator-5560. The AVD was then gracefully stopped and restored to its original headless invocation, with disk/data preserved. The first immediate install retry encountered “Can't find service: package” while Android was still booting; retry after `sys.boot_completed=1` installed successfully. The final screenshot then revealed the System UI ANR above. No further retry or data reset was performed.

Evidence image: `docs/ui/redesign/screenshots/android-release-launch-blocked-system-ui.png`.

The separate final native integration result in `android-native-final-integration.log` passed its real WebView resource-counting, typed/redacted boundary, additional-restriction, normal/private storage, and renderer-lifetime journey before this ordinary APK install. That remains separate evidence; it is not a substitute for the blocked ordinary-app visual/manual journey.
