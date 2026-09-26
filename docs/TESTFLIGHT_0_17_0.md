# TestFlight 0.17.0 (20) — September 26, 2026

The hosted Brave release was fast-forward merged and pushed to `origin/main` at
`60f54689bc296ad303583f5dea3e0d47ba01439c`, then archived from that source with the
ordinary `lib/main.dart` entry point. Apple accepted the internal-only upload at
**2:03 PM America/Chicago**. Apple processing completed. Build **0.17.0 (20)** is now **Testing** in the
existing **Wingman Device Testing** internal group. English (U.S.) testing notes
are saved; external testing is not applicable to this internal-only upload.

- App: `com.wingmanbrowser.app`; App Store Connect app `6811628410`.
- Apple build ID: `67447b07-5af9-4e28-ab9a-a7689035ede0`.
- Export compliance preserves build 19’s `usesNonExemptEncryption=false` setting;
  encryption code and dependencies did not change. No new declaration was created.
- Build team: `9SBP4RY8ST`; arm64; minimum iOS 15.0; Xcode 26.3.
- Public gateway: `https://wingman-search-599739618634.us-central1.run.app/v1/search`.
- Local IPA SHA-256: `0edda617d3958bbefa32b0742c017c2d3cbbf13b034c926bab0f80b7bebd6013`
  (31,701,148 bytes). Xcode separately exported the same verified archive for upload.

Deep/strict signatures pass for the archive and exported app. The exported IPA
uses Apple Distribution signing with `get-task-allow=false`, an App Store beta
profile, no provisioned-device list and no all-devices entitlement. Both AOT
binaries contain the exact source commit, `0.17.0+20`, and the hosted HTTPS endpoint.
The configured Brave key is absent from every IPA entry and archive app file.
No checked debug kernels, fixture payload markers or local endpoint markers were
present. Native publisher RSS remains the feed default; shared Brave/Currents
feeds and paid advertising remain disabled.

The hosted gateway passed six unpaid boundary checks. Actual iOS UI verification
returned genuine Web and News results, displayed News imagery, opened a permitted
NASA article and restored the image and scroll position with Back. Exactly two
provider attempts were made, one per endpoint, both HTTP/schema successes and zero
unknowns. The fixed $5 hosted allowance has $0.01 conservatively reserved and
$4.99 remaining at final verification; image rendering/navigation/Back added no paid
Search call. The original local allowance was not changed. Details and rollback
controls are in [BRAVE_HOSTED_DEPLOYMENT.md](BRAVE_HOSTED_DEPLOYMENT.md).

Release validation: 421 backend tests and 32 focused app version/UI tests passed,
plus the actual simulator, signed archive and IPA builds. The preceding source
baseline passed 1,117 Flutter tests with six existing optional skips and clean
analysis. No simulator or device app was uninstalled or cleared. Physical-device
acceptance remains for the beta audience.

The uploaded build and saved notes/group relationship were read back through the
App Store Connect API: processing `VALID`, audience `INTERNAL_ONLY`, internal
state `IN_BETA_TESTING`, external state `NOT_APPLICABLE`. The existing API key
was reused after its issuer and key ID were verified in the authenticated Apple
account; no new key or expanded permissions were created.

Ignored receipts, exact export/upload options, the retained archive/IPA, testing
notes and verification reports are under `work/testflight-0.17.0/`. This record is
a documentation-only follow-up to the uploaded source commit.
