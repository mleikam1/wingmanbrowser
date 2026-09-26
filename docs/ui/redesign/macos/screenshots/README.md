# macOS runtime screenshots

All images are actual application screenshots saved as JPEG. They are not mockups.

| Image | Source and meaning |
| --- | --- |
| [01-welcome.jpg](01-welcome.jpg) | Ordinary release app onboarding, native macOS window |
| [02-home.jpg](02-home.jpg) | Ordinary release app Home, production asset resolver working |
| [03-integration-native-page.jpg](03-integration-native-page.jpg) | Actual `app.main` Flutter integration, benign local HTML rendered by native AppKitView/WKWebView, native same-document address visible in shell |
| [04-integration-native-boundary.jpg](04-integration-native-boundary.jpg) | Same integration: real native redirect denial produces the branded mandatory-gambling boundary without exposing its blocked URL |
| [05-release-native-input.jpg](05-release-native-input.jpg) | Final packaged ordinary release: native keyboard form text and button response |
| [06-release-native-scroll.jpg](06-release-native-scroll.jpg) | Final packaged release: native scroll reaches footer |
| [07-release-native-back.jpg](07-release-native-back.jpg) / [08-release-native-forward.jpg](08-release-native-forward.jpg) | Native toolbar traversal settles to matching page and address |
| [09-release-hidden-cover.jpg](09-release-hidden-cover.jpg) | Explicit Hide menu shields webpage content |
| [10-release-after-return.jpg](10-release-after-return.jpg) | Subsequent interaction after Raise ended at Home; not proof of context-preserving resume |
| [initial-capability-unavailable.jpg](initial-capability-unavailable.jpg) | Before-fix evidence: ordinary release failed closed while macOS assets were incorrectly resolved through the iOS bundle path |

The integration screenshots were captured during test-only holds. Attaching the
native accessibility capture mid-run caused Flutter's end-of-test semantics-handle
check to fail on that capture pass; no production behavior or Flutter test guard
was disabled. The subsequent clean run, without mid-test CUA attachment, passed
all app interactions and cleanup (1 test, 11 seconds, exit 0).

Screens 05–08 establish packaged-release keyboard/mouse/scroll/history acceptance.
Context-preserving inactive return and native file-panel acceptance remain open;
see the [current ledger](../README.md).
