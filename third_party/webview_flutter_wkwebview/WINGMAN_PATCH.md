# Wingman local extension

Upstream: Flutter team's `webview_flutter_wkwebview` **3.26.1**, copied unmodified from pub.dev except the three source changes below (two API additions and one lint-only comment). The upstream BSD license, authors, generated files, examples and tests are retained.

1. `lib/src/webkit_webview_controller.dart`: exposes `wingmanConfigurationIdentifier` on `WebKitWebViewControllerCreationParams`.
2. `darwin/webview_flutter_wkwebview/Sources/webview_flutter_wkwebview/WebViewFlutterWKWebViewExternalAPI.swift`: exposes `wingmanConfiguration(forIdentifier:registrar:)`, following the existing view lookup pattern.
3. `lib/src/common/webkit_constants.dart`: adds a comment and `ignore_for_file: constant_identifier_names`, retaining upstream Apple constant names without changing execution.

The application uses this narrow extension to obtain the native `WKWebViewConfiguration` **before** constructing its WebView. It assigns a newly created `WKWebsiteDataStore.nonPersistent()`, awaits completion, then creates the official controller. Its native post-creation configuration verifies that the store is nonpersistent and refuses to navigate otherwise.

No generated Pigeon protocol, JavaScript API, navigation behavior, TLS behavior or WebView delegate behavior was changed in this dependency. Native code in the app handles the additional OS integrations.

This extension is needed because the official Dart creation parameters do not expose an ephemeral data store. Do not replace it with clearing default cookies or changing `webView.configuration.websiteDataStore` after creation; neither provides private/normal session isolation. Remove the local override once an upstream equivalent is available and the isolation integration tests pass. Re-audit these changes when updating the dependency.

Apple documents pre-creation configuration and nonpersistent storage at [WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore).
