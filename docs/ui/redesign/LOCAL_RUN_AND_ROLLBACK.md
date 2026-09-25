# Local run and rollback

The UI candidate lives in the isolated `outputs/wingman-browser` worktree on `feat/wingman-wow-ui`, based on verified `origin/main` at `254c907`. The pre-existing checkout and its branch were preserved. Record the final candidate commit from the [implementation ledger](IMPLEMENTATION_STATUS.md) once verification and local commits finish; do not assume the starting commit contains the redesign.

## Ordinary application

From this worktree, with the repository's Flutter toolchain available:

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

The `macos` script argument requires a `macos/` target. Use the separate `feat/wingman-macos` worktree after that adapter exists and its results are documented; the UI worktree does not imply completed desktop protection. No Windows/Linux native adapter is provided.

## Preferences and data

Normal preferences use the existing local document store. UI schema 2 adds tone/reduced motion; workspace schema 2 adds explicit saved pages/timer-related state. Supported old records migrate in memory and are written only on successful explicit changes. A failed read/write is recoverable and does not authorize clearing the user's data. Private sessions remain ephemeral.

For acceptance, use a dedicated disposable QA profile/store. A saved URL does not preserve website forms, content, credentials or network history. A paused timer can restore only its last durable checkpoint.

## Return to a prior build

1. Stop only the candidate process/server you launched. Preserve its logs and any uncommitted work before switching checkouts.
2. Use the untouched original checkout, or create a separate clean worktree at a verified prior commit. Do not use a destructive reset/clean on either checkout.
3. Run the earlier application with its own disposable QA data. Do not downgrade a live user store that has been migrated by this candidate; older readers may reject newer documents.
4. Retain the candidate worktree and explicit local data backups for review/recovery. Avoid uninstalling an existing user app, changing default browsers, clearing OS security settings or replacing signing identities.

No remote branch, deployed service or published app needs rollback because this task has not pushed or published. Returning to an earlier checkout must not be used to disable mandatory protection on a user's current browsing profile.
