# Wingman Browser

**We've got your back, not your data.**

**Built for discovery. Designed with boundaries.**

Version 0.5 adds seven connected consumer experiences to permanent protection: Official Routes, Before You Commit, Your Spaces, Finish Mode, Hand It Over, Trust Receipt, and Compatibility Repair. The offline library contains 18 original reviewed articles; the separate Official Routes catalog contains 18 reviewed organizational destinations. Local search, session tabs, bookmarks, reading lists, themes and text sizing remain available. There is no advertising SDK or account requirement.

**Live websites and external navigation are disabled.** The previous native engines could not establish positive eligibility for every response and resource before rendering. Their plugins and launch paths have been removed. This useful bounded milestone is not a production whole-web classifier, managed-school deployment, or store release.

Core restrictions have no switches, exceptions, PIN bypasses, or private-mode exemptions. Unknown, expired, corrupted, or unsupported content stays closed. Additional restrictions can hide optional collections; they cannot approve new content. A source citation never grants website access.

Previous tabs, history, bookmarks, and reading-list metadata are quarantined before UI startup. Raw titles, addresses, previews, and external-search suggestions are hidden; original records remain in local storage. Reviewed saves use separate resource IDs. Normal reviewed saves persist, private activity does not, and the student/unknown editions keep reviewed-session saves in memory. Reset semantics and external-file limits are explained in Settings.

## Preview

From this repository, with Flutter installed:

```sh
flutter pub get
flutter run -d emulator-5556
```

Use `flutter devices` for the actual device ID. The inspected iOS simulator is:

```sh
flutter run -d C157677F-A33F-45B2-BFFB-F3DED552D4F4
```

For the ad-free student packaging choice (same mandatory policy, no runtime edition switch):

```sh
flutter run -d emulator-5556 --dart-define=WINGMAN_EDITION=student
```

For a local web preview:

```sh
flutter build web --no-web-resources-cdn --no-tree-shake-icons
python3 -m http.server 8791 --bind 127.0.0.1 --directory build/web
```

Open [the local preview](http://127.0.0.1:8791/). The web build is a catalog application, not a browser extension or a filter for the host browser. Browser-owned menus and other applications are outside its boundary. Stop an existing preview on that port before starting another.

## Use the new experiences

Home offers an explicit Library/Official search choice and your selected Spaces. Use **Page tools** for Before You Commit, Spaces & Finish Mode, and compatibility reporting. Open an approved article to find **Share with Hand It Over**. **Protection details → Trust Receipt** shows actual recorded feature events separately from configuration.

Create Home Projects, Learning and Sports yourself; nothing is inferred. Spaces contain notes/checklists and reviewed resources. Home Projects includes unit conversion; Sports uses your choices and reviewed official-source evidence, without a live score feed. Finish Mode owns only explicitly associated companion tabs. Finishing previews save/close choices; ordinary closure offers undo, private closure does not.

Before You Commit accepts bounded pasted English text and the current signed article. Its clearly labeled practice example uses invented terms. Evidence is transient until an explicit local save; private analyses cannot be saved. Clipboard exports show their exact contents before copying and say that nothing was submitted.

Native Hand It Over shares only a previewed static public text collection. Set and confirm a fresh owner-return code; remember it before starting. Handoff uses no website renderer or owner credentials. Web shows the feature as unavailable. See [handoff security](docs/HANDOFF_SECURITY.md) for supported boundaries and interrupted-return semantics.

## Hot reload and rebuilds

`flutter run` works from a terminal, Codex, Android Studio or Xcode's Flutter workflow; VS Code is optional. While a debug run is attached, press `r` for hot reload, `R` for a full Dart restart and `q` to stop. Stateful initializers or schema changes may need a restart. Changes to Kotlin/Swift, native channels, plugins, entitlements, manifests, build settings or bundled assets require stopping and rebuilding. Rebuild the compiled web output and reload the preview after changes. Native release/AOT builds are tracked separately from debug validation.

For web hot reload with a supported installed Chrome target:

```sh
flutter run -d chrome --web-port=8792
```

## Verification and scope

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter test integration_test/protected_app_test.dart --no-uninstall -d emulator-5556
flutter test integration_test/signature_app_test.dart --no-uninstall -d emulator-5556
flutter test integration_test/browser_engine_test.dart --no-uninstall -d emulator-5556
flutter test integration_test/guard_engine_test.dart --no-uninstall -d emulator-5556
```

Native test commands use `--no-uninstall` to preserve the installation; handoff restart testing requires it. The signature test creates clearly synthetic local records and deletes only its own records on success.

The catalog expires on March 10, 2027. It uses a development signing key whose private seed is outside Git. A production review/signing/distribution operation is not delivered. Re-signing instructions are in [content policy](docs/CONTENT_POLICY.md).

See [signature feature status](docs/SIGNATURE_FEATURES_STATUS.md), [acceptance journeys](docs/FEATURE_ACCEPTANCE_TESTS.md), and [platform capabilities](docs/PLATFORM_CAPABILITIES.md) for honest per-feature coverage and remaining release blockers.

Review [actual screenshots](docs/SIGNATURE_SCREENSHOTS.md). The example Spaces and terms in those captures were created for review.

Read [migration](docs/PERMANENT_PROTECTION_MIGRATION.md), [coverage](docs/FILTER_COVERAGE_AND_LIMITATIONS.md), [search](docs/SEARCH_ENFORCEMENT.md), [privacy](docs/PRIVACY_ARCHITECTURE.md), [school deployment](docs/SCHOOL_DEPLOYMENT.md), [monetization](docs/MONETIZATION_POLICY.md), and [release readiness](docs/RELEASE_READINESS.md). The [security matrix](docs/SECURITY_TEST_MATRIX.md) separates actual native observations from compilation and deferred capabilities.

Phase 1–3A documents and [the earlier README](docs/history/README_PHASE3A.md) are historical. Their optional Guard, allowed live-page, ad, Reader, external search, and import/export behavior is superseded by 0.4. Earlier tests that required those capabilities were retired; they are not counted as passes for this milestone.
