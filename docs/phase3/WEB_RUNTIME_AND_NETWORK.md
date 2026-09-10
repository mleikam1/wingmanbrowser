# Phase 3A Web runtime and network observations

Recorded 10 September 2026. This is a real local release build tested through the Codex in-app browser, not a deployed website or mobile browser substitute. The final command `flutter build web --no-web-resources-cdn` passed in **49.1 seconds** (`work/phase3-web-build-delivery.log`). A loopback-only server served the unchanged build on port 8791 with no-store response headers. The earlier verification origin used port 8790; each port has independent local browser storage.

## Observed journeys

- Completed onboarding without an account or permission prompt.
- Selected an explicitly created synthetic Netscape HTML file through the real browser file chooser. Preview showed **2 new, 1 duplicate, 2 rejected**. A script-shaped title remained literal text; unsafe JavaScript and credential-bearing destinations were rejected.
- Cancelled preview: the library stayed empty and export stayed disabled. Selected again, confirmed Import 2, and saw two saved bookmark records. Earlier-origin records also survived reload.
- Confirmed the final Web export disclosure. The app produced a download link named `wingman-bookmarks.html`. The browser automation's download-event wait timed out, but an actual **387-byte file appeared in Downloads**, where none existed before the action. Filesystem inspection verified exactly the two expected URLs and the escaped literal script-shaped title, with no active script/image markup. The UI returned to usable Bookmarks without errors. This distinction prevents mistaking a tool notification limitation for either a failed export or an unobserved success.
- Added `https://example.com/read-later` explicitly to Reading list without opening the website, marked it read, reloaded the companion and confirmed the record with **0 unread**. No reading-list page body was fetched or stored.

Fixtures, the downloaded synthetic export and request logs are local development artifacts, not user browsing records or product analytics. The export is deliberately plaintext; external downloads/share caches are not erased by clearing Wingman data.

## Instrumentation and limits

| Traffic class | Observed evidence | What this does not establish |
|---|---|---|
| Wingman-owned/control services | No active configured Browser account/sync/AI/filter/report endpoint in source. The actual Web startup resource inventory observed 16 resources, all on the loopback origin. Server logs additionally observed the SQLite worker and WASM requests | No comprehensive network capture of every possible runtime path; a future deployment would have hosting/provider metadata |
| User-requested websites | Synthetic import and Add address did not navigate. The import fixture included local script/image trap URLs; neither appeared in the actual server request log. Native fixtures independently count allowed/blocked requests and verify Reader adds no fetch | Arbitrary websites can contact their own third parties; this does not enumerate their traffic |
| Browser-engine security services | Native protections remain enabled; their processing is described in the platform/privacy docs | Loopback logs and browser resource inventory cannot decrypt or comprehensively enumerate OS security traffic |
| Ad and AI providers | Web ads are unsupported; production mobile inventory stays disabled. Fake-provider tests verify that disallowed contexts make no consent/SDK initialization/load calls. No AI provider is configured | Fake-call tests do not prove that a linked mobile SDK has zero startup/background processing. The historical native test-ad smoke is not a fresh full SDK traffic audit |
| Validation-only external fixture | Both native authentication tests explicitly requested `https://httpbin.org/basic-auth/wingman-fixture/test-only`, using public synthetic values | This is not an application backend, actual account, real password-vault test or generic credential-isolation guarantee |

The final server request log contains application/bootstrap/CanvasKit/font/icon files, SQLite worker/WASM, Guard public keys/manifest/starter and tracker data. No import script/image trap request appeared. Console error/warning inspection returned none for the tested Web flow. Logs do not observe encrypted traffic outside this local server, all worker-originated resources, OS/background traffic, provider retention or every SDK endpoint. No proxy, trust certificate, TLS bypass or browsing recorder was installed.

## Build-cache finding

The first compiled Web bundle retained an old generated Flutter plugin registrant that omitted the newly added file-selector plugin. The actual file-chooser action exposed the problem; compilation alone had passed. Invalidating only generated Web entrypoint/compiler stamps regenerated the correct registry, and real import then passed. No application plugin-registration workaround or broad SDK upgrade was added. A later browser cache retained an earlier bundle, so final runtime verification used a fresh local origin and no-store development headers. These development-cache findings are not claimed as production hosting behavior.

Mobile file-provider/share, actual app-switcher and physical credential-provider results belong in [native validation](NATIVE_VALIDATION.md) and the [platform matrix](../PLATFORM_CAPABILITY_MATRIX.md). The complete application destination/data inventory is in [privacy architecture](../PRIVACY_ARCHITECTURE.md).
