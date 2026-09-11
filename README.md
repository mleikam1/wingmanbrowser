# Wingman Browser

**We've got your back, not your data.**

**Built for discovery. Designed with boundaries.**

Version 0.7 adds **Your Launchpad**: locally saved, editable shortcuts and single-level folders, a searchable starter catalog, and optional Sports, Shopping and Learning source collections. It extends the consumer UI and seven connected local experiences: Official Routes, Before You Commit, Your Spaces, Finish Mode, Hand It Over, Trust Receipt, and Compatibility Repair. The offline library contains 18 original reviewed articles; the separate Official Routes catalog contains 18 reviewed organizational destinations. Local search, session tabs, bookmarks, reading lists, themes and text sizing remain available. There is no advertising SDK or account requirement.

**Live websites and external navigation are disabled.** The previous native engines could not establish positive eligibility for every response and resource before rendering. Their plugins and launch paths have been removed. This useful bounded milestone is not a production whole-web classifier, managed-school deployment, or store release.

Core restrictions have no switches, exceptions, PIN bypasses, or private-mode exemptions. Unknown, expired, corrupted, or unsupported content stays closed. Additional restrictions can hide optional collections; they cannot approve new content. A source citation never grants website access.

Previous tabs, history, bookmarks, and reading-list metadata are quarantined before UI startup. Raw titles, addresses, previews, and external-search suggestions are hidden; original records remain in local storage. Reviewed saves use separate resource IDs. Normal reviewed saves persist, private activity does not, and the student/unknown editions keep reviewed-session saves in memory. Reset semantics and external-file limits are explained in Settings.

## UI handoff review

See the [complete screen registry](docs/ui/SCREEN_REGISTRY.md), [design system](docs/ui/DESIGN_SYSTEM.md), [navigation boundaries](docs/ui/NAVIGATION.md) and [UI handoff QA](docs/ui/QA_REPORT.md). That handoff was merged before this milestone. The HTML in `Wingman_UI_Design_Handoff/` is reference material, while `lib/main.dart` is the application. The separate debug gallery uses synthetic memory fixtures.

The current Launchpad work is on the local `launchpad/implementation` branch. Read its [specification](docs/ui/LAUNCHPAD_SPEC.md), [implementation status](docs/ui/LAUNCHPAD_STATUS.md), [site compatibility review](docs/ui/LAUNCHPAD_SITE_COMPATIBILITY.md), and [test results, screenshots and preview instructions](docs/ui/LAUNCHPAD_QA.md).

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

Home has one search entry, Your Launchpad, optional chosen content, an optional current task and your selected Spaces. Use **Add** for suggested resources/tools, an address or a bookmark; **Edit** and tile long-press/context actions open organization controls. Reordering saves immediately; **Organize** opens a stable item panel for consecutive keyboard moves. Choose multiple suggestions or skip; nothing is inferred from history. The Home settings control manages shortcut density, visibility, collections and other Home sections.

The starter catalog contains 8 local tools, 18 reviewed original articles and 8 researched website candidates. ESPN, Walmart, Target, Best Buy, Home Depot, Wikipedia, NASA and Khan Academy are explicitly **inactive** website records in this build. Saving one requires acknowledgment, stores only a local record and submits nothing. No website is made navigable by its name, icon, folder or category. Exact blockers and the ESPN/Walmart research journeys are recorded in the compatibility review.

For an eligible open article, **Menu → Add to Launchpad** previews a separate shortcut; Library offers the same explicit action for saved articles. Removing a shortcut does not delete its bookmark. Optional collection cards can save an eligible resource into a selected Space. Private customization stays in its temporary session; private pages cannot be pinned into normal Home. All artwork is local, with no favicon, title or preview fetch.

The focused search has an explicit Official choice. Use **Menu → Wingman tools** for Before You Commit, Spaces & Finish Mode, and Hand It Over. **Menu → Protection & settings** contains Trust Receipt and compatibility reporting. Settings, Reader and feature pages return to their originating session.

Create Home Projects, Learning and Sports yourself; nothing is inferred. Spaces contain notes/checklists and reviewed resources. Home Projects includes unit conversion; Sports uses your choices and reviewed official-source evidence, without a live score feed. Finish Mode owns only explicitly associated companion tabs. Finishing previews save/close choices and offers safe undo for normal task closure; private closure never restores destroyed data.

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
flutter test integration_test/launchpad_app_test.dart --no-uninstall -d emulator-5556
flutter test integration_test/launchpad_native_test.dart --no-uninstall -d emulator-5556
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
