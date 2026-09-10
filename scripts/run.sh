#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
  web) exec flutter run -d chrome --web-port 7357 ;;
  android) exec flutter run -d "${2:-emulator-5556}" ;;
  ios) exec flutter run -d "${2:-C157677F-A33F-45B2-BFFB-F3DED552D4F4}" ;;
  *) echo 'Usage: ./scripts/run.sh web|android|ios [device-id]'; exit 2 ;;
esac
