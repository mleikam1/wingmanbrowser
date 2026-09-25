#!/bin/sh
# Run the ordinary production entry point. No test fixtures, data reset or bypass.
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
target=${1:-web}
case "$target" in
  web)
    flutter pub get
    flutter build web --no-web-resources-cdn --no-tree-shake-icons
    exec python3 -m http.server 8799 --bind 127.0.0.1 --directory build/web
    ;;
  macos)
    if [ ! -d macos ]; then
      echo 'Use the feat/wingman-macos worktree for the separate native desktop adapter.'
      exit 2
    fi
    exec flutter run -d macos -t lib/main.dart
    ;;
  *) exec flutter run -d "$target" -t lib/main.dart ;;
esac
