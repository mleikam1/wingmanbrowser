# TestFlight 0.16.0 (19) — September 16, 2026

The Currents shared-ingestion integration was fast-forward merged into `main`. Release version 0.16.0+19 was committed and pushed to `origin/main` at `68616c061216485819f09b2fa880fa93624f8a94`, then archived from that source. Xcode Organizer uploaded the archive using **TestFlight Internal Only** at 9:16 AM America/Chicago. Apple processing completed, testing notes were saved, and the existing **Wingman Device Testing** internal group shows **Testing** for build 19 with one tester and 90 days remaining.

- App: `com.wingmanbrowser.app`; App Store Connect app `6811628410`.
- Apple build ID: `b7697bad-7c0c-431c-9687-cc277ff7fb29`.
- Encryption answers retain the previous standard-encryption and no-France treatment; encryption code and dependencies did not change.
- Archive and exported IPA passed deep/strict signature checks; the exported IPA has distribution signing and debugging disabled.
- Both AOT binaries contain the source commit and version `0.16.0+19`. The ordinary `lib/main.dart` entry point was used.
- Native RSS is enabled with no local or shared feed endpoint override. No known fixture markers or debug kernel were present in the payloads.
- Registry SHA-256: `67b10cb496112ff73c39f18c24caa9d8480952948bca59664e8107bbf448cd42`.
- Local IPA SHA-256: `77d1752e66c4ec279f7c2f260c433f99a211be169271a834d9f529e53bf4da74` (31,483,817 bytes). Organizer separately exported and uploaded the same verified archive.

The implementation validation recorded in `docs/CURRENTS_VALIDATION.md` remains applicable: 186 backend tests passed, 999 Flutter tests passed with six opt-in skips, and Flutter analysis found no issues. Native Android and iOS integration checks used explicitly labeled fixtures, not live Currents data. This release adds signed archive/export and embedded-identity verification; physical-device acceptance remains for the beta audience. No simulator or device apps were uninstalled during this release task.

**Live Currents is not enabled in this beta.** The release retains existing approved publisher feeds until a production shared feed endpoint and server-side key are configured. Testing notes disclose this limit and request checks of topic switching, refresh, original links and Back, Save/Hide/Share, private browsing, missing-photo fallback, accessibility, and upgrade preservation of saved items/settings.

Build, signing and delivery receipts, export options, notes, verifier, and retained IPA are under ignored local `work/testflight-0.16.0/`. This release record is a documentation-only follow-up to the uploaded source commit.
