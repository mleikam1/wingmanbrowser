# Wingman Browser 0.15.0 (17)

Released to the existing **Wingman Device Testing** internal TestFlight group on
September 15, 2026. App Store Connect completed processing and the group build
row was verified as **Testing**, with one existing internal tester and 90 days
remaining. This confirms TestFlight availability, not installation or testing on
a physical device.

- Bundle: `com.wingmanbrowser.app`
- App Store Connect app: `6811628410`
- Apple build ID: `b6c37f62-1d79-44cd-a33c-86308a1695a8`
- Feature source: `7d8ace3d0c7605150867a263d49af209fecc274c`, plus the
  `pubspec.yaml` version increment to `0.15.0+17`.
- Upload: Xcode Organizer, **TestFlight Internal Only**; completed at 5:15 PM CDT.
- Compliance: existing standard-encryption answer and no distribution in France,
  consistent with the user-confirmed U.S.-only beta. No encryption code changed.
- Testing notes were saved before assigning the internal group. No new testers,
  external testing group, public TestFlight link or App Store release was created.

## Changes to test

Refreshed Home and Discover story cards show permitted story images, original
headlines, publisher names, excerpts and dates. Test category switching,
including Travel; opening an original story and returning with Back should
preserve the category and scroll position. Exercise Save, Share, Hide, About
this story and saved links after restarting. Check Sponsored features with their
complete articles, images, attribution and publisher links.

Also test larger text, dark mode, VoiceOver, private tabs, turning Discover off,
DuckDuckGo search, tabs and ordinary browsing. Content availability varies, and
some categories have few or no eligible stories. Live images require a network
connection. Current content and network behavior is documented in
[Feed candidate integration](FEED_CANDIDATE_INTEGRATION.md) and
[Content refresh](CONTENT_REFRESH.md).

## Validation and artifacts

The feature source passed 928 Flutter tests (five optional skips), 111 backend
tests and Flutter analysis before merging. Its Android, iOS and web builds passed.
For this version-only release, `flutter build ipa --release` with internal-only
export options completed successfully. Archive settings confirmed version,
build number, bundle identifier and iOS 15 deployment target. Deep, strict code
signature checks passed for the archive app and exported IPA; the IPA uses the
App Store provisioning profile and does not permit debugging.

The separately verified local export is 31,430,627 bytes, SHA-256
`ea5a41b2c3a4a47a2f9e07da54639c495b44ca7d7dea48566ee507870dc21262`.
Organizer distributed the same archive through its own export/upload workflow;
this hash identifies the local IPA, not a downloaded Apple-processed binary.
Local build, signing, upload and group receipts are in ignored
`work/testflight-0.15.0/`.
