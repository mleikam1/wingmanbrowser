# Browser engine contract

`BrowserEngine` defines the consumer page operations. `ProtectedWebController` is its Flutter adapter; `wingman/protected-browser` binds it to Android System WebView and iOS WKWebView. The old BrowserEnginePool is an isolated compatibility rejection boundary for obsolete callers, not the consumer transport.

## Ownership and messages

Each platform view is owned by a stable tab ID, immutable normal/private scope and build edition. Capabilities must report `mode: consumerWeb` and `supported: true`; private, uploads, downloads and default-browser availability are reported independently. Missing/corrupt mandatory data prevents renderer capability. A catalog expiry cannot grant/deny the independent consumer baseline.

Commands: `open(url)`, `openSearch(query)`, `back`, `forward`, `reload`, `stop`, `find(query)`, `findNext(forward)`, `share`, `setActive(active)`, `updateRestrictions`, `close`. Each page request has a monotonically increasing request ID; stale IDs and closed-view events cannot alter current state. No website can invoke these Flutter channels. Query submission constructs the strict endpoint natively; it does not accept a page-provided permission token.

Native accepted navigations run in the native history stack and emit `pageState` including URL, title, progress, loading and back/forward flags. Flutter updates tab metadata without reloading the URL. A blocked navigation emits a local explanation while retaining the committed page. User-initiated new windows emit `newWindowRequested` and are checked again before tab allocation. Arbitrary scripts are not accepted through the production channel.

`navigationBlocked` contains the captured `viewId`/`requestId`, static reason,
validated `reasonCode`, and an optional native-confirmed category. Supported
reason codes are `blockMandatoryCategory`, `blockSecurityThreat`,
`blockAdditionalRestriction`, `blockPolicyUnavailable`, and
`blockUnsupportedCapability`. It omits the denied URL/title. Unknown values
cannot invent a confirmed content category. Network/TLS errors remain separate
page errors and never imply a category denial.

`setActive(false)` pauses/hides without deleting cookies, history or renderer state. Menus, theme changes, feature screens, Home and bounded inactive tabs retain ownership. `close` disposes it. Hand It Over removes owner surfaces completely, respecting its existing isolation boundary. Four live engines are bounded by least recently selected order. Evicted tabs restore their last address; no complete session-history/form restoration claim is made.

## Security and platform limits

Both adapters retain platform TLS validation and sandboxing, restrict schemes/file access, and evaluate top-level navigations and new windows. Android additionally checks exposed resource/service worker callbacks and enables available Safe Browsing. WKWebView uses compiled category/tracker rule lists plus navigation decisions. Neither native API provides reliable classification of every changing response, sentence, image or advertisement. Android interception does not report every subresource redirect hop; WK rule lists have different observability from WebView request callbacks. See PROTECTION_COVERAGE.md for data/source and coverage limits.

Uploads use OS pickers. Downloads use native platform flows with destination checks and user-selected/exported files. Permissions are origin scoped and require OS/site consent; granting camera/media is not automatic. iOS default browser status requires Apple's signing entitlement; a registered URL scheme alone does not establish it.

The web companion performs explicit top-level HTTPS navigation. It does not create a native engine, embed third-party pages, proxy browsing, or control the host browser after leaving Wingman.

## Observed request counters

Native capabilities report `resourceCountersObservable` and `resourceCounterScope`.
Android reports `rendererLifetime`: `blockedResources` counts actual policy-denied
responses from `WebViewClient.shouldInterceptRequest` only. Navigation delegates,
service workers, TLS errors and downloads do not add to it. Repeated `pageState`
delivery returns snapshots, not incremental events. Distinct intercepted retries
can count separately even when their addresses match; this is never a unique
tracker count or a complete traffic total.

Counters are synchronized, contain no addresses or titles, and reset when the
renderer is released/replaced (including eviction), not on every navigation.
Generation tokens reject callbacks from released renderers. Each view owns its
own normal/private counter; none persist or aggregate across sessions. A missing
renderer reports null. Values cap at 100,000 and `resourceCounterSaturated` signals
an exceeded limit. Permitted `requestAttempts` indicate interception only, not
successful network loads.

iOS reports `resourceCountersObservable: false`, `resourceCounterScope:
unobservable`, and null counts. Its installed WK content rules cannot provide
these outcomes. The UI must explain that activity is not observable on that
platform instead of showing zero. See [redesign native audit](ui/redesign/NATIVE_AUDIT.md)
for the implementation and current fixture evidence.

Implementation references: [Flutter state retention](https://api.flutter.dev/flutter/widgets/Visibility/maintainState.html), [Dart JS interop](https://dart.dev/interop/js-interop/usage), [Android WebView](https://developer.android.com/reference/android/webkit/WebView), [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview).
