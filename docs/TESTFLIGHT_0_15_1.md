# TestFlight 0.15.1 (18) — September 16, 2026

The editorial delivery repair was fast-forward merged and pushed to `origin/main` at `69ba153d4a44cc8b00c9313bb05d2662f8e6ada8`, then archived from that merged source. Xcode Organizer uploaded **0.15.1 (18)** using **TestFlight Internal Only**. Apple processing completed; the existing **Wingman Device Testing** group shows **Testing**, with one internal tester and the new testing notes saved.

- App: `com.wingmanbrowser.app`; U.S. internal beta.
- Apple build ID: `8585a6bc-48b4-4d9e-81df-6820ef7fa2c6`.
- Archive and exported IPA passed deep/strict signature checks. Both AOT binaries contain the merged commit and version `0.15.1+18`.
- Native RSS is enabled without a local or shared feed endpoint override. Registry SHA-256: `c8c346c8ddf9357203fba7971f6ac008b815da9648b4eb3f577f1d7408f34806`.
- Local IPA SHA-256: `8a13513add665695ec7479e16aac621d3f7394cde196d20146311a8a41d216e3` (31,470,560 bytes). Organizer separately exported and uploaded the same verified archive.
- Encryption answers retain the previous build's standard-encryption and no-France treatment; encryption code and dependencies did not change.

This release follows the user's subsequent merge and TestFlight authorization. The earlier [repair delivery report](EDITORIAL_REPAIR_DELIVERY.md) records the state before that authorization. Its validation results remain applicable: 985 Flutter tests passed, six opt-in tests skipped, 126 backend tests passed, and Flutter analysis found no issues. This release additionally passed signed archive/export and embedded-identity checks. A further simulator smoke attempt did not complete because simulator startup reported a data-migration failure and its launch command stalled; no device data was cleared. Physical-device testing remains for the beta audience.

Stories remain readable when optional photos are missing, loading or unavailable. Only permitted photos appear. Sports and Entertainment supply remains limited; this release does not add a broad U.S. publisher catalog or resolve the documented content-supply targets. TestFlight notes call out those limits and request category, navigation, save/hide/share, accessibility, refresh, private-tab and DuckDuckGo checks.

Build, signing and final delivery receipts, export options, upload notes and the retained IPA are under the local `work/testflight-0.15.1/` directory. This release record is a documentation-only follow-up to the uploaded source commit.
