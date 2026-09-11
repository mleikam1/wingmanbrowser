# Wingman design system

This document describes the Flutter implementation in the UI handoff branch, version 0.6.0+6. The source is [WingmanTokens](../../lib/presentation/design_system/wingman_tokens.dart), [WingmanTheme](../../lib/presentation/theme.dart), and [shared components](../../lib/presentation/components/wingman_components.dart). The supplied [master prompt](../../Wingman_UI_Design_Handoff/WINGMAN_UI_MASTER_PROMPT.md) governs the design direction; its HTML illustrations are synthetic reference compositions, not application or security evidence.

## Semantic colors

The app uses opaque navy/blue surfaces, restrained cyan decoration, and separate text/control-boundary roles. These are UI tokens, not measurements of logo pixels.

| Role | Light | Dark |
|---|---|---|
| Canvas | `#F5F8FF` | `#08111F` |
| Surface | `#FFFFFF` | `#101D31` |
| Raised / selected / information fill | `#EDF3FF` | `#162640` |
| Main text | `#10213D` | `#EDF4FF` |
| Secondary text | `#54647B` | `#A9B9D0` |
| Action | `#0062E8` | `#79AAFF` |
| On action | `#FFFFFF` | `#071B4D` |
| Decorative divider | `#DFE7F3` | `#2A3B55` |
| Control outline | `#73829A` | `#8093AE` |
| Success / fill | `#186440` / `#EAF6EF` | `#8BDBAB` / `#123325` |
| Caution / fill | `#805100` / `#FFF5E2` | `#FFCF83` / `#342918` |
| Danger / fill | `#AD283C` / `#FFEDF0` | `#FFA1B0` / `#3B1C29` |
| Brand navy | `#071B4D` | `#071B4D` |
| Decorative cyan | `#20CFF2` | `#20CFF2` |

`ColorScheme` maps these roles into Material 3 controls. Cards and app bars remove the framework surface tint and decorative elevation. Status messages use a title, text and icon as well as color; information and category denial are not automatically danger states. Decorative dividers are not used as the sole input boundary. Focused input outlines use the action color at 2 logical pixels.

### Calculated contrast

The following opaque token pairs were recalculated from current source using the sRGB relative-luminance formula. “Minimum” means the least contrast against canvas, surface and raised backgrounds, not a minimum measured across every rendered widget.

| Pair | Light | Dark |
|---|---:|---:|
| Main text, minimum of three surfaces | 14.43:1 | 13.70:1 |
| Secondary text, minimum of three surfaces | 5.41:1 | 7.61:1 |
| Control outline, minimum of three surfaces | 3.50:1 | 4.84:1 |
| Action label / action fill | 5.37:1 | 7.08:1 |
| Success text / success fill | 6.45:1 | 8.40:1 |
| Caution text / caution fill | 6.27:1 | 9.82:1 |
| Danger text / danger fill | 5.92:1 | 7.93:1 |

[WCAG 2.2 contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) specifies 4.5:1 for ordinary text and 3:1 for large text, with defined exceptions. The product aims for these principles; the calculations and `test/ui/design_system_test.dart` do not certify whole-interface conformance. Disabled opacity, hover/pressed composition, focus placement, text over artwork, and platform assistive technology still need contextual review.

## Type, identity and local assets

The bundled `Roboto-Regular.ttf`, `Roboto-Medium.ttf` and `Roboto-Bold.ttf` are registered as weights 400, 500 and 700. Noto Sans Symbols is the explicit symbol fallback. No new font provider or runtime font package was added for the redesign.

| Flutter role | Size / line height | Weight |
|---|---|---:|
| First-run display | 36 / 42 | 700 |
| Large headline | 32 / 40 | 700 |
| Page headline | 28 / 34 | 700 |
| Small headline / wordmark | 24 / 32 | 700 |
| Section title | 20 / 28 | 700 |
| Row title | 16 / 24 | 500 |
| Small title | 14 / 20 | 700 |
| Body | 16 / 24 | 400 |
| Supporting metadata | 12 / 16 | 400 |
| Action label | 14 / 20 | 500 |
| Compact label | 12 / 16 | 500 |
| App-bar title | 18 / 26 | 700 |

The reader adds its own body measure and size multiplier. Article size is clamped to 75–200%; device text scaling remains active and is independent of that preference. Essential instructions reflow rather than using a global text-scale override. Compact metadata is not the only place where consequential limitations are explained.

The supplied original is retained at `assets/brand/source/wingman-logo-reference.png`. `assets/brand/wingman-mark.png` uses the handoff crop with white highlights preserved. `WingmanBrand` gives the raster an intentional white circular medallion, proportional `BoxFit.contain`, a decode target at twice the logical-size/device-density product, high-quality filtering and a live-text wordmark. A decorative duplicate is excluded from semantics; an identity lockup has a single Wingman label. Private mode uses a separate icon and text. Launcher/splash/favicon provenance and platform-slot validation are documented in [native brand assets](native_brand.md); generated previews are not native launch screenshots.

The web bootstrap resolves CanvasKit from the document base, and the release build uses local web resources. Roboto and known interface symbols are bundled. Flutter's conditional fallback for other Unicode scripts remains available and can contact `fonts.gstatic.com`; therefore the UI does not claim universal network silence. See [privacy architecture](../PRIVACY_ARCHITECTURE.md) and the recorded runtime evidence.

## Layout and components

Available logical width drives composition. This follows the distinction between fitting a layout to available space and selecting usable platform/input behavior in [Flutter's adaptive design guidance](https://docs.flutter.dev/ui/adaptive-responsive). A breakpoint is a layout rule, not evidence that every device at that width was tested.

| Rule | Current value |
|---|---|
| Compact / medium / expanded | below 600 / 600–1023 / 1024+ |
| Outer gutter | 16 below 360; 20 below 600; 32 below 1024; 40 otherwise |
| Spacing vocabulary | 4, 8, 12, 16, 20, 24, 32, 40, 48 |
| Default form/page maximum | 720 logical pixels |
| Home content maximum | 720 logical pixels; shortcut strip up to 384 |
| Evidence/search override | Official Routes uses 840 |
| Reader maximum | 760; line length varies with scaling and content |
| Buttons / inputs | 16 radius; primary button minimum height 52 |
| Cards / dialogs and sheets | 20 / 28 radius |
| Icon target / row minimum | 48×48 / 64, with expandable text |

`WingmanPage` provides the app bar, safe area, width constraint, responsive padding and optional scroll view. Screens that own a `ListView` pass `scrollable: false`. App bars grow with large title scaling. `WingmanSection`, `WingmanSettingsRow`, `WingmanStatus` and `WingmanEmptyState` share the hierarchy and tone. `BrowserDock` and grouped menu composition live in `browser_chrome.dart`.

`showWingmanSheet` uses a safe-area, keyboard-inset-aware bottom sheet below 1024 logical pixels, with a 90%-height limit. At 1024+ it uses a centered dialog up to 440 wide and 85% high. This is an implemented dialog adaptation, not the handoff's optional anchored side panel. Tabs choose grid/list presentation, reducing columns for narrow available space or larger text. Home Space previews use two columns when their available width is at least 320 and text scale is below 1.5; otherwise they stack. Space controls provide button-based ordering rather than requiring drag. The narrower 720-pixel Home is a deliberate bounded composition, including when a desktop app rail is visible; other broad owned surfaces retain their separate constraints.

The web companion uses an app navigation rail at width 600+, height 640+, and text scale below the rail's threshold; otherwise it uses its compact app dock. Native keeps the five-control dock. A native tablet tab strip, live page omnibox, address-position switch and master/detail view in every library/settings screen are not implemented merely because the reference illustrates wider compositions.

## Motion, input and accessibility boundary

The token values are 120 ms for button feedback, 200 ms for shared sheets, and 250 ms for `WingmanRoute`. The custom page transition is an opaque canvas with a small horizontal slide; it returns the child without that slide when `MediaQuery.disableAnimations` is true. `WingmanRoute` disables route snapshotting, and app theme changes are immediate. The shared sheet helper uses 200 ms in both directions for bottom sheets and its expanded dialog, with zero animation when `MediaQuery.disableAnimations` is true. Other framework dialogs are not implicitly covered by that helper. Real busy indicators reflect actual work; there are no invented loading stages or idle engagement animations.

48×48 logical-pixel interaction targets are the product's chosen floor and match [Flutter's accessibility checklist](https://docs.flutter.dev/ui/accessibility). This is distinct from the CSS-pixel criteria and exceptions in [WCAG target-size guidance](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html). Labeled controls, expanded text, keyboard-safe scrolling and non-drag choices are implemented. Home search is a separate labelled button that opens the entry route, not a disabled editable field or a semantic container for the whole Home. `home_search_semantics_test.dart` checks the enabled action, heading separation and assistive-technology activation for normal/private fixtures; both cases pass in the final431-test suite. Whole-app TalkBack/VoiceOver behavior, every keyboard focus restoration, largest OS display scaling and complete reduced-motion coverage are verification tasks, not certified outcomes of token tests.

Sensitive routes remain opaque. Native capture shielding and the inactive-scene cover remain enabled; the theme does not weaken them. Development screenshots use labelled synthetic memory scenes and intercepted clipboard callbacks. No tab thumbnail loads a website, captures owner content or allocates a WebView. Policy status is read from the authoritative runtime, not inferred from a color or stored switch.

## Evidence

The first foundation run passed its 21 component/contrast/asset checks. The subsequent 402-test run and full analysis are recorded in the parent workspace logs `work/ui-full-test-first.log` and `work/ui-full-analyze-first.log`; the final431-test run and clean analyzer are recorded in the [QA report](QA_REPORT.md). Module-specific captures and their narrower scope are in [O/C evidence](OFFICIAL_COMMIT_QA.md), [Workspace/Handoff evidence](workspace_handoff_visual_qa.md), and the screenshot registry. The isolated font-face diagnostic compares rasterized bundled weights; it does not substitute different production fonts.

Tests cover representative widths 320, 360, 390, 430, 600, 768, 1024 and 1440 and 200% text in both themes, with some short-height/larger-scale cases. This records exercised layouts, not universal device, accessibility, live-web or performance acceptance. Native builds, actual system keyboard journeys and measured startup/frame/memory results belong to the final QA evidence, independently of these host widget captures.
