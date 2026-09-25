#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export FLUTTER_SUPPRESS_ANALYTICS=true
exec flutter run -d macos "$@"
