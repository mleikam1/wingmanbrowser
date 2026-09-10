# Phase 2 main-app acceptance — 10 September 2026

These observations used the normal `lib/main.dart` application, not an integration-test entrypoint. The final implementation is `375a649befadc73595306728816637f5b101b045`.

## iPhone simulator

The final iOS simulator build passed in 41.9 seconds, was installed into the iPhone 17 Pro simulator, and launched successfully. Native UI actions and screenshots verified:

- Onboarding's Set up Guard route opens the real settings screen. All lifestyle categories initially remain off.
- Guard plus Adult content, Alcohol and Recreational drugs can be selected independently. Gambling and Tobacco/vaping remain off.
- Home shows a collapsed active Guard card without revealing selected category names.
- `adult.guard.test`, `alcohol.guard.test` and `recreational-drugs.guard.test` produce the corresponding owned blocked page. Go back returns safely to Home. Native fixture tests separately establish pre-render/zero-request interception for their tested paths.
- Wikipedia loads inside Wingman while Guard is active.
- A private tab still blocks `adult.guard.test/private-restart-check`, shows private-mode chrome, and explains that an explicitly saved permanent exception would persist locally. The final Adult sentence has no duplicated word.
- The app was explicitly terminated and launched again, without reinstalling during this cold-restart check. The private tab disappeared, the normal Wikipedia tab restored, and all three Guard choices persisted.
- A read-only inspection of Wingman's own SQLite database after restart found one saved normal tab, zero history/tab rows containing the distinctive private test path, and the same three saved Guard blocks as before private navigation. This is stored-data evidence, not a claim that simulator RAM or the operating system contains no traces.
- The starter-listed public `heineken.com` site was blocked as Alcohol. Turning off only Alcohol let its normal age-gateway page load; no age or personal information was entered. Re-enabling Alcohol blocked the current page again. The other category choices stayed enabled throughout.
- The app was left on Home with the three demonstration choices enabled. The two additional normal public-site blocks brought the local total to five; private activity had not incremented it.

The PIN's real secure-storage behavior was tested separately on both platforms with an isolated test key. This manual cold restart did not set a production PIN and does not add an OS-restart PIN claim to those automated results.

## Android main app

The final main-entrypoint debug APK built in 20.6 seconds and installed successfully on the dedicated API 36 emulator. Its normal onboarding was visibly rendered and the app remained the top resumed activity. The launch command's 15-second wait timed out before the later visual/process confirmation; no successful startup latency is inferred. Full Guard UI behavior passed separately in the 50-second automated app integration run, including all eight acceptance flags.

No production signing or physical-device performance is claimed. Android remains on its initial onboarding; iOS remains on the verified Home screen.

## Screenshots and evidence

- [iOS choices](../screenshots/phase2-ios-guard-choices.png)
- [Alcohol block](../screenshots/phase2-ios-alcohol-block.png)
- [Private Guard and final wording](../screenshots/phase2-ios-private-guard.png)
- [Category disabled, normal public page](../screenshots/phase2-ios-category-off.png)
- [Final Home](../screenshots/phase2-ios-home-final.png)
- [Android main onboarding](../screenshots/phase2-android-main.png)

Local development logs: `work/phase2-main-ios-copy-final.log`, `phase2-ios-cold-restart.json`, `phase2-main-android-handoff-build-final.log`, and `phase2-guard-ui-android-handoff-fixed.log` in the parent workspace. No browsing database is committed.
