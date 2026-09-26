#!/usr/bin/env bash
# Only a separately started synthetic fixture gateway; preserve installation.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 ]]; then
  echo 'Usage: scripts/test_wingman_search_app.sh <dedicated-emulator-or-simulator-id>' >&2
  exit 2
fi
if [[ "$1" == emulator-* ]]; then
  adb -s "$1" reverse tcp:8895 tcp:8895
fi
exec flutter test integration_test/wingman_search_app_test.dart --no-uninstall -d "$1" \
  --dart-define=WINGMAN_SEARCH_URL=http://127.0.0.1:8895/v1/search \
  --dart-define=WINGMAN_SEARCH_DEVELOPMENT=true
