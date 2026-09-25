# Wingman design system

This document describes the Flutter implementation in the 2026-09-25 redesign candidate, version 0.16.0+19, on `feat/wingman-wow-ui`. The source is [WingmanTokens](../../lib/presentation/design_system/wingman_tokens.dart), [WingmanTheme](../../lib/presentation/theme.dart), and [shared components](../../lib/presentation/components/wingman_components.dart). The supplied PNG redesign references guide composition; the original logo and existing brand identity remain. Reference images are design inputs, not application or security evidence. Current rendered evidence is indexed in [VISUAL_INDEX](redesign/VISUAL_INDEX.md).

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
| Home content maximum | 1280 logical pixels; hero changes composition below 700 |
| Redesigned broad surfaces | Protection 1440; terms 1480; Settings 1360; boundary 1040; Trust Receipt 1000 |
| Evidence/search override | Official Routes uses 840 |
| Reader maximum | 760; line length varies with scaling and content |
| Buttons / inputs | 16 radius; primary button minimum height 52 |
| Shared cards / dialogs and sheets | 20 / 28 radius; redesigned panels may use 24 |
| Icon target / row minimum | 48×48 / 64, with expandable text |

`WingmanPage` provides the app bar, safe area, width constraint, responsive padding and optional scroll view. Screens that own a `ListView` pass `scrollable: false`. App bars grow with large title scaling. `WingmanSection`, `WingmanSettingsRow`, `WingmanStatus` and `WingmanEmptyState` share the hierarchy and tone. `BrowserDock` and grouped menu composition live in `browser_chrome.dart`.

`showWingmanSheet` uses a safe-area, keyboard-inset-aware bottom sheet below 1024 logical pixels, with a 90%-height limit. At 1024+ it uses a centered dialog up to 440 wide and 85% high. This is an implemented dialog adaptation, not the handoff's optional anchored side panel. Tabs choose grid/list presentation, reducing columns for narrow available space or larger text. Home Space previews use two columns when their available width is at least 320 and text scale is below 1.5; otherwise they stack. Space controls provide button-based ordering rather than requiring drag. Home now uses a 1280-pixel bound and a responsive ribbon hero. Protection and terms use side-by-side sections when space and text scaling allow, then stack. The companion is a captured-page side panel on sufficiently wide layouts and a dedicated surface on compact layouts; it never silently changes task ownership.

The shell adapts browser controls to available width and text scale. Compact native browsing retains Back, Forward, Home, Tabs and Menu, with actual live page state; expanded native layouts add tab/address chrome. Web remains an app companion with external host-browser navigation. An address-position preference and master/detail view in every older library/settings route are not implied by the wider reference artwork.

## Motion, input and accessibility boundary

The token values are 120 ms for button feedback, 200 ms for shared sheets, and 250 ms for `WingmanRoute`. The custom page transition is an opaque canvas with a small horizontal slide; it returns the child without that slide when `MediaQuery.disableAnimations` is true. The local `reduceMotion` preference is combined with the device setting; captured-session routes also receive the preference and use zero transition duration when selected. `WingmanRoute` disables route snapshotting, and app theme changes are immediate. The shared sheet helper uses 200 ms in both directions for bottom sheets and its expanded dialog, with zero animation when `MediaQuery.disableAnimations` is true. Other framework dialogs are not implicitly covered by that helper. Real busy indicators reflect actual work; there are no invented loading stages or idle engagement animations.

48×48 logical-pixel interaction targets are the product's chosen floor and match [Flutter's accessibility checklist](https://docs.flutter.dev/ui/accessibility). This is distinct from the CSS-pixel criteria and exceptions in [WCAG target-size guidance](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html). Labeled controls, expanded text, keyboard-safe scrolling and non-drag choices are implemented. Home search is a separate labelled button that opens the entry route, not a disabled editable field or a semantic container for the whole Home. `home_search_semantics_test.dart` checks the enabled action, heading separation and assistive-technology activation for normal/private fixtures; the current verification results are recorded in the redesign ledger. Whole-app TalkBack/VoiceOver behavior, every keyboard focus restoration, largest OS display scaling and complete reduced-motion coverage are verification tasks, not certified outcomes of token tests.

Sensitive routes remain opaque. Native capture shielding and the inactive-scene cover remain enabled; the theme does not weaken them. Development screenshots use labelled synthetic memory scenes and intercepted clipboard callbacks. No tab thumbnail loads a website, captures owner content or allocates a WebView. Policy status is read from the authoritative runtime, not inferred from a color or stored switch.

## Local preferences and identity

`UiPreferences` schema 2 adds `companionTone` (`gary`, `wallace`, `betty`) and `reduceMotion`; tone adjusts local wording only. These controls do not change permissions, protection, analysis or available tools. Schema 1 documents retain their saved Home order, visibility, shortcuts and artwork. A successful explicit edit writes schema 2; read failures/future schemas preserve the saved document for recovery. Private sessions use an ephemeral controller and do not read or write the normal document. Global theme and reading-size controls are read-only from private Settings.

New layouts default to shortcuts, task, Spaces, then Official discovery. Existing saved order is respected. The hero and boundary illustrations use local code and semantic roles (`heroStart`, `heroEnd`, `panel`, `selectedTab`, `focusRing`); ribbon accents are `#2369F5` and `#56D9EC`. Dark hero text roles are `heroInk #102D54`, `onHeroInk #EDF5FF` and `heroMuted #B5CBE5`. No remote artwork, page thumbnail, generative service or new analytics dependency was introduced.

## Evidence

The [visual index](redesign/VISUAL_INDEX.md) links every redesign board, compact variants and actual iOS simulator captures, with capture provenance. The [implementation ledger](redesign/IMPLEMENTATION_STATUS.md) and [platform matrix](redesign/PLATFORM_MATRIX.md) own current aggregate test/build status; verification is still in progress. Older [QA_REPORT](QA_REPORT.md) and associated historical screenshot documents describe earlier milestones and must not be read as this candidate's final test results.

Representative production-widget layout checks exercise both themes and 200% text at widths including 320, 390, 430, 768, 1024 and 1440. The exact per-surface capture sizes and tests are recorded in the index and slice notes. Widget renders do not establish native interception, real keyboard/assistive-technology behavior, physical-device performance or whole-interface accessibility acceptance. Base-token contrast calculations above describe opaque color pairs only.
