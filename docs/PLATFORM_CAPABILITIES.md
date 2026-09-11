# Consumer signature platform capabilities

0.5.0 development/review build, 2026-09-11. Android/iOS run Flutter's signed plaintext reader; live website engines remain disabled. Web is a companion application. No extension is present.

| Experience | Android | iOS | Flutter web |
| --- | --- | --- | --- |
| Official Routes | Local identity catalog/evidence; live opening unavailable | Same | Same; cannot control unrelated host tabs |
| Before You Commit | Pasted English text or current signed article; local analysis | Same | Same; no cross-tab DOM access |
| Your Spaces | SQLite local documents,3 starter types and utility | Same | SQLite web worker/browser-origin storage; browser can evict it |
| Finish Mode | Explicitly saved task references/notes, normal closure undo | Same | Same within companion tabs; no host-browser tab control |
| Hand It Over | Static public signed text only, secure marker + fresh owner-return code; native input checks | Same; nonpersistent WebKit not needed because no web renderer exists | Unavailable; cannot isolate host cookies or establish the native owner gate |
| Trust Receipt | Local bounded journal and previewed clipboard export | Same | Same; clipboard subject to browser permissions/context |
| Compatibility Repair | Local report/export; fixed-schema text-wrap registry | Same | Same |

Interactive handoff, website authentication, uploads/downloads, media, live search, live DOM extraction, remote correction packs and diagnostic submissions are not enabled. Official identity does not authorize those capabilities. The compatibility production registry is empty; controlled eligible fixtures test the correction engine without shipping an invented production fix.

Native capability reads are narrow platform-channel methods inaccessible to websites: static-content support, secure-storage availability, OS owner-authentication availability, and read-only input diagnostics for tests. Owner return uses a fresh8–12digit handoff code, not an OS biometric claim. The Android test emulator has no configured device credential; its security configuration was not changed. See [handoff security](HANDOFF_SECURITY.md) for lifecycle, retry and persistent-gate semantics and test results.

Handoff is not device-wide kiosk mode. System UI, screenshots where the OS allows them, other applications, OS backups and clipboard readers remain outside its guarantee. No owner cookie or website store is copied or cleared; no live website renderer is created.

## Development targets

- Android: emulator-5556, Android16/API36. Installed WebView134.0.6998.135 is observed platform metadata, **not an active Wingman renderer**.
- iOS: iPhone17Pro simulator C157677F-A33F-45B2-BFFB-F3DED552D4F4, iOS26.3 family, Xcode26.3. No production signing/store release validation.
- Web: local compiled Flutter companion, not an extension/filter for another browser.

Exact execution results and limitations are recorded in [status](SIGNATURE_FEATURES_STATUS.md) and [acceptance tests](FEATURE_ACCEPTANCE_TESTS.md). Simulator performance does not establish physical-device or low-end-device performance.
