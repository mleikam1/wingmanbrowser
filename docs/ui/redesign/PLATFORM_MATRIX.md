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
