# Wingman Browser

**We've got your back, not your data.**

**Built for discovery. Designed with boundaries.**

Version 0.4 is the first local milestone of permanent protection. It provides a signed offline library of 14 original reviewed articles, local search, collections, session tabs, bookmarks, a reading list, themes, and adjustable article text. It contains no advertising SDK and requires no account.

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
flutter build web --no-web-resources-cdn
python3 -m http.server 8791 --bind 127.0.0.1 --directory build/web
```

Open [the local preview](http://127.0.0.1:8791/). The web build is a catalog application, not a browser extension or a filter for the host browser. Browser-owned menus and other applications are outside its boundary. Stop an existing preview on that port before starting another.

## Verification and scope

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter test integration_test/browser_engine_test.dart -d emulator-5556
flutter test integration_test/guard_engine_test.dart -d emulator-5556
```

The catalog expires on March 10, 2027. It uses a development signing key whose private seed is outside Git. A production review/signing/distribution operation is not delivered. Re-signing instructions are in [content policy](docs/CONTENT_POLICY.md).

Read [migration](docs/PERMANENT_PROTECTION_MIGRATION.md), [coverage](docs/FILTER_COVERAGE_AND_LIMITATIONS.md), [search](docs/SEARCH_ENFORCEMENT.md), [privacy](docs/PRIVACY_ARCHITECTURE.md), [school deployment](docs/SCHOOL_DEPLOYMENT.md), [monetization](docs/MONETIZATION_POLICY.md), and [release readiness](docs/RELEASE_READINESS.md). The [security matrix](docs/SECURITY_TEST_MATRIX.md) separates actual native observations from compilation and deferred capabilities.

Phase 1–3A documents and [the earlier README](docs/history/README_PHASE3A.md) are historical. Their optional Guard, allowed live-page, ad, Reader, external search, and import/export behavior is superseded by 0.4. Earlier tests that required those capabilities were retired; they are not counted as passes for this milestone.
