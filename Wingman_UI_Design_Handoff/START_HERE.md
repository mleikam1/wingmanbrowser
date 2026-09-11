# Wingman Browser — UI handoff

## Contents

- `WINGMAN_UI_MASTER_PROMPT.md`: the complete Codex implementation brief, with the logo-based design system and 51 screen/flow entries.
- `WINGMAN_UI_VISUAL_REFERENCE.html`: a self-contained clickable reference with 26 illustrative screen compositions, light/dark switching, and a wider preview.
- `WINGMAN_UI_OVERVIEW.png`: a quick visual overview.
- `wingman-logo-reference.png`: the original supplied logo, unchanged.
- `wingman-logo-cropped.png`: a derivative cropped only around the outer whitespace, preserving the original white highlights and interior background.
- `DESIGN_REFERENCE_NOTES.md`: scope, visual-reference limitations, and contrast calculations.
- `REFERENCE_QA.json`: limited HTML runtime/layout checks. This is not a Flutter or native-browser test report.
- `reference-previews/`: screenshots of the HTML reference, not screenshots of a running Wingman build.

No font files are included. The production prompt preserves the repository's existing bundled font setup.

## Open the visual reference

Download and extract this package. Open `WINGMAN_UI_VISUAL_REFERENCE.html` in a desktop browser. Select screens from the left navigation or use the in-app links. Switch the theme and preview width with the controls above it. Screen content scrolls inside the example device.

All values, findings, tasks, and catalog entries illustrated in the HTML are synthetic design fixtures. No site is visited, purchase is analyzed, message is sent, or security protection is enforced by this reference.

The complete written prompt covers more states and flows than the 26 selected visual compositions. It governs behavior and capability limits.

## Give the package to Codex

Open your existing Wingman repository in Codex. Put this package's contents under `design/wingman-ui/` in that repository, or attach the files to the Codex conversation and identify their actual locations. Do not replace the repository with this folder.

Paste this launcher prompt:

```text
Read design/wingman-ui/WINGMAN_UI_MASTER_PROMPT.md in full before coding. It is the implementation specification for this UI milestone, not optional inspiration.

Use design/wingman-ui/WINGMAN_UI_VISUAL_REFERENCE.html for visual hierarchy, components, spacing, and light/dark direction. It is a reference prototype, not the production architecture. Use wingman-logo-reference.png as the unchanged brand source; preserve its white highlights. Consult DESIGN_REFERENCE_NOTES.md for the reference's limitations.

Inspect the actual local Wingman checkout. The brief reviewed main at 060839b8b656f89ea1a1998b2843f3322f7e33b3; do not reset to that snapshot or overwrite newer work. Preserve native WebView patches, state/lifecycle protections, and existing local data.

Implement this design in the Flutter application, covering every screen/flow in the registry and all seven signature-feature interfaces. Connect real local behavior; do not stop at Home, simply alter the HTML, or substitute production placeholder data for unimplemented features.

Reconcile the old optional Guard controls with the user's permanent-protection policy. Do not present an active-protection claim unless the underlying policy and coverage support it. Treat missing enforcement as a prerequisite, not a color or badge change.

Keep Wingman consumer-first, with the supplied navy/blue/cyan identity and monetization deferred. No ads, SDK additions, subscriptions, affiliate cards, school dashboard, or unrelated framework migration.

Start by recording the Git baseline, inspecting the screen inventory and tests, and then implement tested milestones. Run supported builds, inspect actual light/dark screens, preserve accessibility and privacy, and report unverified or blocked capabilities honestly. Do not push, publish, or modify production resources without approval.
```

## Scope of the review

The brief was based on a source review of the GitHub main-branch snapshot above, including the presentation layer, Guard-facing wiring, configuration, and status documents. The native application was not built or run during this design handoff. The HTML reference was separately rendered and smoke-tested; its QA must not be interpreted as mobile app acceptance.
