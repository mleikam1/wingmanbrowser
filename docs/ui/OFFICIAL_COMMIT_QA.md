# Official Routes and Before You Commit UI evidence

September 11, 2026. These are captures of production Flutter widgets under an isolated host test, using the app theme and bundled fonts. Every image labels its synthetic scope. No owner storage is loaded, no website is opened, and clipboard operations use intercepted callbacks. This is host widget evidence, not a physical-device or live-browser claim.

## Verification

- Existing and new O/C focused checks: **34 passed**, including real matcher/source eligibility, disabled live action, private storage exclusion, request validation, exact export preview, delayed completion and route/lifecycle interruption. Parent-workspace log: `work/ui-official-commit-tests.log`.
- Final visual checks: **4 passed in 4 seconds**. Three real screens (Official catalog, analysis setup, review request) each render at 320, 360, 390, 430, 600, 768, 1024 and 1440 logical widths, 640 logical height, and 200% text, in light and dark themes: 48 screen combinations. Controls are revealed and checked for framework layout exceptions. Log: `work/ui-oc-visual-tests.log`.
- The same visual file captures 18 real-widget scene images at 390×844 and normal text scale. Pending analysis comes from a held future and is canceled; findings come from the real deterministic analyzer against the explicitly invented practice example.
- Final scoped analysis: **no issues, 2.0 seconds**, including both modules, the gallery, visual test, and updated host/native Shell journey tests. Log: `work/ui-oc-analyze-final.log`.
- The updated host Shell journey test passed all **10 cases** with Home/search routes, Menu, normal/private tab groups, mandatory denial, storage errors and policy invalidation preserved. Native integration source was updated and analyzed; device execution is recorded separately by the integration owner.

## Captures

The 390-wide images are scroll positions within actual pages. Cropped content at the viewport boundary remains scrollable; the evidence and export are not shortened to fit a screenshot.

| Flow | Light | Dark |
|---|---|---|
| O01 local identities and filters | [Catalog](screenshots/oc-o01-light.png) | [Catalog](screenshots/oc-o01-dark.png) |
| O02 exact identity evidence, disabled live action | [Evidence](screenshots/oc-o02-light.png) | [Evidence](screenshots/oc-o02-dark.png) |
| O03 invalid user-entered URL | [Validation](screenshots/oc-o03-invalid-light.png) | [Validation](screenshots/oc-o03-invalid-dark.png) |
| O03 exact local request preview | [Preview](screenshots/oc-o03-preview-light.png) | [Preview](screenshots/oc-o03-preview-dark.png) |
| C01 source and bounded selection | [Setup](screenshots/oc-c01-light.png) | [Setup](screenshots/oc-c01-dark.png) |
| C02 actual pending check and cancellation | [Pending](screenshots/oc-c02-pending-light.png) | [Pending](screenshots/oc-c02-pending-dark.png) |
| C03 actual evidence and source time | [Evidence](screenshots/oc-c03-evidence-light.png) | [Evidence](screenshots/oc-c03-evidence-dark.png) |
| C03 cancellation finding | [Finding](screenshots/oc-c03-cancellation-light.png) | [Finding](screenshots/oc-c03-cancellation-dark.png) |
| C04 exact findings export preview | [Preview](screenshots/oc-c04-preview-light.png) | [Preview](screenshots/oc-c04-preview-dark.png) |

Visual inspection covered the rendered light evidence sheet and request/export previews, and dark findings cards. The evidence wording separates identity review, content policy, directly stated text, and unsupported claims. The live action remains disabled. The UI does not display a fabricated merchant result or imply that a local draft was submitted.

## Development gallery

`tool/ui_gallery/official_commit_scenes.dart` exposes `OfficialCommitGalleryMenu` and isolated `OfficialCommitGallery(scene: ...)` scenes. They cover catalog/empty/expired/revoked/unavailable identity states, blank local requests, normal/private analysis, actual pending cancellation, failed save and unconfirmed copy. Each owns disposable memory policy/journal/report state. The gallery is excluded from the release entry point and intercepts clipboard writes.

The gallery's scenario source is analyzed; the functional captures instantiate the same production widgets directly. This distinction avoids claiming that static fixture metadata or an analyzer pass proves every gallery interaction. Actual OS clipboard access, platform keyboard/accessibility behavior and production-device performance need separate runtime evidence.
