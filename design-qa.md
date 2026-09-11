# Wingman UI design comparison

**Final result: passed** — the final production Web rebuild, Home semantic action, search/results/article navigation and reviewed clipboard exports were verified. No unresolved P0–P2 finding remains in the inspected scope. Physical-device and release acceptance limits remain documented separately.

## Visual truth and normalization

Source: `Wingman_UI_Design_Handoff/WINGMAN_UI_MASTER_PROMPT.md`, `WINGMAN_UI_VISUAL_REFERENCE.html`, `reference-previews/`, and the original/cropped logo files. The whole HTML composition and selected previews were inspected. Source screenshot pixels are390×812, including a24px illustrative OS status strip. The normalized comparison removes only that strip to390×788. No fake status strip is drawn inside Flutter. Reference corner masking and unavailable website imagery are not treated as application requirements.

Implementation: production Flutter widgets and actual `lib/main.dart` Web runtime. Host Home/Shell captures are390×788 at devicePixelRatio1. O/C and other feature captures use their documented390×812 or390×844 viewports and are compared at the app-content boundary; different height/content states are explicitly distinguished. Native capture shields remain enabled; host fixtures are synthetic in-memory models, not captures of owner/private data. Runtime Web compact images are390×788; Official wide is1280×720, and the final Home/findings images use the actual711×720 review panel. Nothing is rasterized into the production app to imitate a screenshot.

Combined full-view evidence (source on left, implementation on right):

- `docs/ui/screenshots/comparisons/home-light-final.png` — same local test goal/checklist pattern as the reference, real controller progress; different actual tab count.
- `docs/ui/screenshots/comparisons/settings-dark-runtime.png` — actual Web Settings, with current capability-specific labels.
- `docs/ui/screenshots/comparisons/protection-dark-runtime.png` — actual Web Protection, with actual18-article coverage.
- Scoped full-view comparisons and all20 Shell state inspections are recorded in `docs/ui/SHELL_VISUAL_QA.md`, `OFFICIAL_COMMIT_QA.md`, `workspace_handoff_visual_qa.md`, and `SETTINGS_LIBRARY_PRIVACY_QA.md`.

Focused evidence: `docs/ui/screenshots/comparisons/home-detail-final.png` compares the original raster/wordmark, small controls and Official/Finish spacing at native pixel size. Settings/Protection full-width390px images have readable rows/hero text in the combined input; another crop adds no information. Feature-owned evidence panels/keypads were also opened at full readable size in their scoped reviews.

## Comparison history and corrections

| Severity / location | Earlier observed issue | Applied correction | Revised evidence |
|---|---|---|---|
| P2 Home composition | Headline wrapping and repeated section gaps pushed the task/Spaces down; quick actions did not match the reference rhythm |28/34 headline; deliberate two-line phrase; compact Home-only group labels/gaps; full-card task action and actual compact progress; two-column Space previews | Final Home full and detail comparisons; both Home goldens; normal/private responsive Shell tests |
| P2 brand raster | White square corners and low-resolution small decode weakened the supplied mark | Preserved exact source/crop; white circular treatment, proportional image, high-quality2× decode without extra padding | Final Home detail; Welcome light/dark; native generated-slot provenance |
| P2 tab count | A red notification badge gave an ordinary count error-like emphasis | Bordered native-style count control; independent48px action and truthful disabled Back/Forward | Home/Shell dock captures in both themes |
| P2 Settings | Oversized groups/duplicate vertical spacing and absent icon tiles/dividers weakened hierarchy | Settings-only16px group labels,14px support,40px raised icon tiles, dividers and compact spacing | Actual dark Web Settings comparison and updated light/dark host captures |
| P2 Protection | Original implementation lacked the intended hero and clear read-only policy rows | Navy/blue hero, cyan standard shield, read-only rows and separate truthful limited-coverage message | Actual dark Web Protection comparison plus both host themes |
| P2 Spaces | Tall repeated cards and an always-expanded converter reduced useful first-view content | Compact actual cards, prominent Create picker, deliberate converter disclosure and responsive fields |22 Workspace/Handoff captures and scoped final report |
| P2 Welcome capture | Earlier light frame had not decoded the W, showing an empty white disc | Capture helper now awaits exact current Image providers and a painted frame | Reopened `shell-f02-welcome-{light,dark}.png` |
| P2 suggestions capture | Earlier screenshot ran before typed-query painting and duplicated the empty field | Pump/precache before capture; assert actual `moon` query and reviewed match | Reopened `shell-f04-suggestions-{light,dark}.png` |
| P2 information sheet | Fixed80% height left several hundred unused pixels | Content-sized shared adaptive sheet with explicit48px Close | Reopened `shell-f07-information-{light,dark}.png` |
| P2 result rows | Cards sized to their text, creating inconsistent right edges | Fill bounded result column width | Reopened `shell-f05-results-{light,dark}.png`, both x20–370 |
| P1 Home Web semantics | Search entry merged surrounding Home into a disabled text-field node | Independent labelled/enabled button with SemanticsAction.tap and explicit search callback | Both normal/private semantics tests pass; the rebuilt Web Home exposes an independent enabled search button, and activating it opens the working search field |

The blank-logo/empty-query frames were rejected and replaced. No build/lint step is counted as a visual iteration. The most recent host comparison includes post-fix pictures; passing tests alone did not resolve a visual finding.

## Required fidelity surfaces

**Fonts and typography:** Bundled Roboto400/500/700 preserved, no remote font swap. Actual face raster test matches the separately aliased Regular/Medium/Bold files exactly. Body16/24, support14/20 and sparse12/16 metadata remain readable; page28/34 and first-run36/42. Important reference labels that are smaller than the brief's readable body/support size are intentionally larger. Platform raster antialiasing and standard Material icon shapes differ; those are accepted, not replaced artwork. Headline wrapping, large-type reflow and important labels were inspected.

**Spacing and layout:** Shared gutters/radii/buttons, bounded pages, stable native dock and app-only Web rail. Home's720px wide maximum and384px shortcut strip avoid excessively spread controls. Phone Space cards reflow to one column with large text. The expanded menu/evidence dialog is a compact focus-contained adaptation rather than a claimed anchored live-browser panel. Real scrolling lists can continue below the initial viewport; essential fixed controls retain their own allocated safe area.

**Colors/tokens:** The supplied light/dark palette is centralized; state colors and control outlines have measured contrast in DESIGN_SYSTEM. One restrained Protection gradient is accepted. Red tab-count emphasis was removed. Extra caution copy reflects actual reviewed-only scope; it intentionally occupies more space than synthetic small-print coverage in the source.

**Image quality:** Original logo source is byte-preserved, the supplied crop is registered, white highlights remain and no custom drawn substitute was created. Home detail verifies the final mark at its actual size. Platform launcher/splash/favicon slots derive from that same crop; asset verification is distinct from OS-launcher observation. No arbitrary website thumbnail, favicon fetch or generated imitation was introduced.

**Copy/content:** Reference tasks, evidence, origins and progress are synthetic. Production uses real local records or honest empty/unavailable states. Local article titles replace sample website origins; no Reload, live threat count, sports feed, successful report submission or protection score is fabricated. Mission/section hierarchy follows the handoff. Private mode is explicit in either theme and contains no normal-user preview.

## Actual runtime and accessibility scope

Actual Web interactions inspected: Official Routes open/back, Settings, Appearance, persisted dark theme and Protection. After the final25.5s release rebuild, Home exposed an independent enabled search button; activating it, entering `moon`, submitting, opening one of two actual matches and returning through the grouped menu worked. Both full-width result cards and the signed article were inspected. Compatibility issue selection, diagnostic preview and explicit copy produced the current0.6.0 report with the optional domain omitted. Before You Commit analyzed its explicitly labelled invented practice text; preview/copy retained evidence positions, uncertainty and the no-submission statement. The actual browser clipboard matched both reviewed exports, then its prior contents were restored. No analysis was saved during this final check. Console warning/error inspection returned no entries after these flows. Screenshots: `runtime-web-home-dark-final.png`, `runtime-web-home-wide-final.png`, `runtime-web-results-dark-final.png`, `runtime-web-article-dark-final.png`, `runtime-web-report-copy-final.png`, `runtime-web-findings-copy-final.png`. The final Home wide image is an actual711px panel after resetting the temporary viewport override; a clipped capture under the earlier1280px override was rejected and replaced.

Host evidence spans320–1440 logical widths, light/dark,200% text and short/landscape variants; Home includes320% landscape. Functional tests verify page/trail/scroll preservation, policy routing, explicit confirmation and durable writes. Native integrations separately verify real keyboards and capture/guest-isolation boundaries. Full physical-device TalkBack/VoiceOver, every focus/keyboard combination, split-screen/foldable hinge behavior and release-frame timing are residual acceptance gaps, not claimed from screenshots.

## Completion checklist

- [x] Source and actual implementation opened together; density/status strip normalized.
- [x] Full-view and focused asset/type/spacing comparisons completed.
- [x] All observed host P0–P2 findings fixed, recaptured and inspected.
- [x]431 host tests pass,2 optional skips; analyzer clean.
- [x] Final production Web rebuild and Home semantic-action runtime verification.
- [x] Confirm final result after actual runtime inspection and clipboard verification.

Follow-up P3 polish: exact standard-icon stroke parity and minor engine-specific antialiasing remain acceptable differences. No original brand artwork is replaced. See `docs/ui/QA_REPORT.md` for live capability and device-release limitations independent of visual QA.
