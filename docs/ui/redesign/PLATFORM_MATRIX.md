# Platform acceptance matrix

2026-09-25. **Implemented/tested** means the stated local check passed; it does not certify every request path, physical device or distribution channel. The UI branch is `feat/wingman-wow-ui`; the separate native desktop branch is `feat/wingman-macos`.

| Feature | Android | iOS | Web companion | macOS | Windows/Linux |
|---|---|---|---|---|---|
| Consumer engine | Implemented/tested System WebView | Implemented/tested WKWebView | Host-browser handoff, explicitly scoped | Implemented AppKit WKWebView; native fixtures passed, cross-layer integration underway | Unsupported: targets absent |
| Real address/search/history/tabs | Native integration tested; ordinary final APK built | Ordinary permitted page/link/back/forward tested; final ownership artifact rendered example.com | Local tools tested; external example.com handoff verified | Native fixtures tested; ordinary runtime underway | Unsupported |
| Mandatory navigation policy | Direct/private denial, typed redaction and enforcement journey passed |13 consumer XCTests passed, including ownership follow-up | Cannot enforce host-browser navigation |14 native XCTests passed using final production asset resolver | Unsupported |
| Resource protection | Guarded native callback subset; redirect-hop limitations remain | Compiled WK content rules; outcomes unobservable | Host browser outside authority | Compiled WK content rules; outcomes unobservable | Unsupported |
| Actual blocking counters | Implemented/tested renderer-lifetime outcomes; replay/reset/privacy assertions passed | Explicitly unobservable | Explicitly unobservable | Explicitly unobservable | Unsupported |
| Normal/private storage | Real integration cookie/localStorage separation passed | Nonpersistent WK store tested; ordinary private task isolation passed | Ephemeral app state only; host storage unaffected | Normal/nonpersistent WK cookie separation passed | Unsupported |
| Redesigned local UI/tools | Shared Flutter tests; final APK built | Shared tests plus ordinary task/checklist/timer/private/boundary runtime | Ordinary task/Space/timer persistence, terms, dark Settings tested | Shared UI and focused platform tests; full suite1055 passed/6 skips | Not built or verified |
| Companion captured ownership | Shared async ownership/lifecycle tests | Shared tests and five ordinary reopen cycles; native ownership regressions passed | Restored task/notes and direct Finish navigation verified | Renderer/request/lifecycle fences in14 native tests | Unsupported |
| Hand It Over | Existing native feature preserved/regression tested | Existing native feature preserved/regression tested | Existing documented local/handoff limits | Explicitly unavailable on new target | Unsupported |
| Build artifact | Ordinary release-mode APK, debug signed for local QA | Ordinary simulator app; final ownership-patched artifact built | Final ordinary build copied with SHA256 manifest | Final corrected release compiled; cross-layer runtime integration underway | None |
| Device/UI scope | Dedicated Android16/API36.1 emulator; ordinary visual check blocked by System UI ANR/CUA access | Dedicated iOS simulator; no physical-device claim | In-app browser, loopback ordinary production build | macOS15.7.4 arm64; minimum13.0 target | None |

Shared tests cover migrations, write failures/corruption, timer clock/background rules, optional nudges behind mandatory policy, task/Space ownership, terms evidence/input limits, private isolation, existing feeds/handoff/deletion, responsive layouts and200% text. Exact totals and commands are in [VERIFICATION](VERIFICATION.md). No production feed quota was consumed.

Native source/test limits are recorded in [NATIVE_AUDIT](NATIVE_AUDIT.md), the [desktop ledger](../../../../wingman-macos/docs/ui/redesign/macos/README.md), and existing [protection coverage](../../PROTECTION_COVERAGE.md). Usable-stale installed rules do not imply active online updates or comprehensive classification. WK resource totals are not available. Android callback counts are neither unique trackers nor a complete network log.

Artifacts remain local. Android signing uses the repository's existing debug-key fallback; iOS is a simulator build; macOS is locally ad hoc signed. No push, notarization, store submission or universal desktop-support claim is made.
