# Local run and rollback

The combined repository contains the shared redesign and native macOS target for `main`, based on verified `origin/main` at `254c907`. The integration preserves the source histories from `feat/wingman-wow-ui` (`908cbce`) and `feat/wingman-macos` (`c4d2832`). [Merge acceptance](MERGE_ACCEPTANCE.md) records the resulting commit, checks and remote publication; the [implementation ledger](IMPLEMENTATION_STATUS.md) retains the earlier milestones.

## Ordinary application

From the repository root, with its Flutter toolchain available:

```sh
./scripts/run_redesign.sh web
```

This resolves existing packages, builds the ordinary `lib/main.dart` web companion using local web resources and serves `http://127.0.0.1:8799`. Open that address in a browser. The web companion hands external navigation to its host; it is not a native protected browsing engine. Do not use gallery routes, synthetic state, storage resets or protection bypasses for runtime acceptance. Stop this launched server with Ctrl-C in its terminal.

For a dedicated Android emulator or iOS simulator, select the actual available identifier:

```sh
flutter devices
./scripts/run_redesign.sh DEVICE_ID
```

The script invokes `flutter run -d DEVICE_ID -t lib/main.dart`. `DEVICE_ID` is a placeholder to replace from the device listing. Build artifacts, device identifiers and exact verified commands are recorded in the ledger/evidence, not inferred from these instructions. Existing user installations and production signing are outside this local run.

The native macOS target is included in this checkout. Run `./scripts/run_redesign.sh macos` or `./scripts/run_macos.sh` from the same repository root. Its [native run/evidence ledger](macos/README.md) records actual coverage and remaining acceptance gaps. No Windows/Linux native adapter is provided.

## Preferences and data

Normal preferences use the existing local document store. UI schema 2 adds tone/reduced motion; workspace schema 2 adds explicit saved pages/timer-related state. Supported old records migrate in memory and are written only on successful explicit changes. A failed read/write is recoverable and does not authorize clearing the user's data. Private sessions remain ephemeral.

For acceptance, use a dedicated disposable QA profile/store. A saved URL does not preserve website forms, content, credentials or network history. A paused timer can restore only its last durable checkpoint.

## Return to a prior build

1. Stop only the candidate process/server you launched. Preserve its logs and any uncommitted work before switching checkouts.
2. Create a separate clean worktree at a verified prior commit for local comparison. Do not use a destructive reset/clean or rewrite shared branch history.
3. Run the earlier application with its own disposable QA data. Do not downgrade a live user store that has been migrated by this candidate; older readers may reject newer documents.
4. Retain the candidate worktree and explicit local data backups for review/recovery. Avoid uninstalling an existing user app, changing default browsers, clearing OS security settings or replacing signing identities.

For a shared-source rollback, use a reviewed revert commit on top of the published branch instead of a force push. This merge does not deploy or publish an application. Returning to an earlier checkout must not be used to disable mandatory protection on a user's current browsing profile.

## Preserved local builds

The paths below identify pre-merge build artifacts, which remain outside Git. Android, iOS and web artifacts live in the original `outputs/wingman-browser` worktree; macOS artifacts live in the original `outputs/wingman-macos` worktree. A fresh checkout of combined `main` includes source and evidence, not these binaries. Use the commands above to build the checked-out source; the manifests preserve the exact earlier build provenance.

- Android: `artifacts/android/Wingman-0.16.0+19-local-release.apk` (ordinary entrypoint, existing debug signing fallback).
- iOS simulator: `artifacts/ios-simulator/Wingman-20260925T211144Z.app` (ordinary app with ownership/history corrections, no XCTest bundle).
- Web companion: `artifacts/web-companion/`, with91 file hashes in `artifacts/web-companion-manifest.json`. Serve this existing build without rebuilding: `python3 -m http.server 8799 --bind 127.0.0.1 --directory artifacts/web-companion` when that port is free.
- macOS: `artifacts/macos/Wingman Browser Preview.app` and `artifacts/macos/Wingman-Browser-Preview-macOS.zip`, with source/signature evidence in `artifacts/macos/BUILD_MANIFEST.json` and the [native ledger](macos/README.md).

Prior simulator artifacts are retained for provenance; use the newest verified artifact above. Copied builds and most raw logs are excluded from the source repository; selected native/build evidence logs and concise manifests are committed.
