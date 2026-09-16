#!/usr/bin/env bash
# Run against the separately started fixture reader, preserving the installation.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 ]]; then
  echo 'Usage: scripts/test_currents_app.sh <dedicated-emulator-or-simulator-id>' >&2
  exit 2
fi
exec flutter test integration_test/currents_app_test.dart --no-uninstall -d "$1" \
  --dart-define=WINGMAN_FEED_URL=http://127.0.0.1:8893/v1/snapshot.json \
  --dart-define=WINGMAN_FEED_ALLOW_LOCAL=true
