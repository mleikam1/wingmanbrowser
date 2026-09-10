# Phase 2 Web runtime verification

The release Web build was served locally, without publishing, and exercised through the browser UI on September 10, 2026. The final conditional Web transport compile passed with `flutter build web --release --no-web-resources-cdn`, including the Wasm dry run. The transport has no configured production endpoint.

The final copy-adjusted release build passed in 50.1 seconds (`work/phase2-web-copy-final.log`). Reloading it on the same local origin restored the completed onboarding state and rendered Home with the explicit mobile-companion Guard wording.

Observed flows:

- Onboarding showed the privacy promise, Set up Guard and the option to continue normally. No lifestyle category was selected.
- Set up Guard opened the real Guard screen. Its Web limitation was visible above the controls.
- Guard, Adult content, Alcohol and Recreational drugs were enabled through the UI. Gambling and Tobacco/vaping remained unselected.
- Reloading the same local origin restored those saved preferences. Home's collapsed card did not expose their category names.
- Home and Guard settings were inspected at 1280×720 and 320×640. Content remained scrollable without horizontal overflow. Large text and both color themes also have host widget coverage.
- A fresh origin was used for the final signed-manifest schema. Onboarding and Guard setup loaded successfully with all lifestyle choices off.
- The final-schema pack reported version 1.0.0, 49 rules, and verified integrity. Check for updates displayed that no service is configured and the verified local pack remains active.

This is a companion UI verification, not proof of filtering pages in another browser. Native navigation blocking is verified separately in the mobile integration tests. Web pages, settings and local databases remain scoped to their browser origin; changing the preview port starts a separate store.
