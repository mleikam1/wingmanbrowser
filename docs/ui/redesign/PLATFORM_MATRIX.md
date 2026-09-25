> **Native macOS branch addendum (2026-09-25).** This branch starts from the completed UI checkpoint and adds the native macOS target. The current shared UI/mobile/web evidence is maintained in the [sibling UI implementation status](../../../../wingman-browser/docs/ui/redesign/IMPLEMENTATION_STATUS.md). The desktop implementation, exact tests, artifact, and remaining foreground-input acceptance gap are recorded in [macOS verification](macos/README.md). Older checklist text below is inherited checkpoint history, not the final desktop result.

# Platform acceptance matrix

Initial audit, 2026-09-25. All implementation/test columns are pending until recorded evidence exists.

| Feature | Android | iOS | Web companion | macOS | Windows/Linux |
|---|---|---|---|---|---|
| Existing consumer engine | System WebView | WKWebView | Host browser handoff only | Absent initially | Absent |
| Native mandatory navigation policy | Existing; regression pending | Existing; regression pending | No host enforcement | Pending separate workstream | Unsupported |
| Native request observation | Supported callback subset | Not observable | Not observable | Pending adapter | Unsupported |
| Redesigned shell/local tools | In progress | In progress | In progress | UI reusable; engine absent | Unverified UI only |
| Private sessions | Disposable native profile | Nonpersistent store | Ephemeral app state only | Pending | Unsupported |
| Build/device verification | Pending | Pending | Pending | Pending | Unsupported |

A successful compile is not security acceptance. Existing coverage and filtering limitations remain in `docs/PROTECTION_COVERAGE.md`.
