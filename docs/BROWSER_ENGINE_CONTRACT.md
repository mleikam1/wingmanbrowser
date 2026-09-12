# Browser engine contract

`BrowserEngine` defines the consumer page operations. `ProtectedWebController` is its Flutter adapter; `wingman/protected-browser` binds it to Android System WebView and iOS WKWebView. The old BrowserEnginePool is an isolated compatibility rejection boundary for obsolete callers, not the consumer transport.

## Ownership and messages

Each platform view is owned by a stable tab ID, immutable normal/private scope and build edition. Capabilities must report `mode: consumerWeb` and `supported: true`; private, uploads, downloads and default-browser availability are reported independently. Missing/corrupt mandatory data prevents renderer capability. A catalog expiry cannot grant/deny the independent consumer baseline.

Commands: `open(url)`, `openSearch(query)`, `back`, `forward`, `reload`, `stop`, `find(query)`, `findNext(forward)`, `share`, `setActive(active)`, `updateRestrictions`, `close`. Each page request has a monotonically increasing request ID; stale IDs and closed-view events cannot alter current state. No website can invoke these Flutter channels. Query submission constructs the strict endpoint natively; it does not accept a page-provided permission token.

Native accepted navigations run in the native history stack and emit `pageState` including URL, title, progress, loading and back/forward flags. Flutter updates tab metadata without reloading the URL. A blocked navigation emits a local explanation while retaining the committed page. User-initiated new windows emit `newWindowRequested` and are checked again before tab allocation. Arbitrary scripts are not accepted through the production channel.

`setActive(false)` pauses/hides without deleting cookies, history or renderer state. Menus, theme changes, feature screens, Home and bounded inactive tabs retain ownership. `close` disposes it. Hand It Over removes owner surfaces completely, respecting its existing isolation boundary. Four live engines are bounded by least recently selected order. Evicted tabs restore their last address; no complete session-history/form restoration claim is made.

## Security and platform limits

Both adapters retain platform TLS validation and sandboxing, restrict schemes/file access, and evaluate top-level navigations and new windows. Android additionally checks exposed resource/service worker callbacks and enables available Safe Browsing. WKWebView uses compiled category/tracker rule lists plus navigation decisions. Neither native API provides reliable classification of every changing response, sentence, image or advertisement. Android interception does not report every subresource redirect hop; WK rule lists have different observability from WebView request callbacks. See PROTECTION_COVERAGE.md for data/source and coverage limits.

Uploads use OS pickers. Downloads use native platform flows with destination checks and user-selected/exported files. Permissions are origin scoped and require OS/site consent; granting camera/media is not automatic. iOS default browser status requires Apple's signing entitlement; a registered URL scheme alone does not establish it.

The web companion performs explicit top-level HTTPS navigation. It does not create a native engine, embed third-party pages, proxy browsing, or control the host browser after leaving Wingman.

Implementation references: [Flutter state retention](https://api.flutter.dev/flutter/widgets/Visibility/maintainState.html), [Dart JS interop](https://dart.dev/interop/js-interop/usage), [Android WebView](https://developer.android.com/reference/android/webkit/WebView), [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview).
