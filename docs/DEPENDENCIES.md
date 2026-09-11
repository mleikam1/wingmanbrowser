> Historical Phase 1–3A document. Optional Guard, live browsing, external search, Reader and ad behavior described here is superseded by [permanent protection 0.4](RELEASE_READINESS.md). It is not a current capability or release claim.

# Dependency decisions

Use `pubspec.lock` and native resolution files for the exact resolved versions. Keep upgrades deliberate and rerun browser, storage and privacy checks after changes.

| Direct dependency | Why it exists | Privacy and maintenance note |
| --- | --- | --- |
| Flutter SDK | Shared application UI, themes, lifecycle and platform channels | No separate application framework required |
| `webview_flutter` 4.14.1 | Official Flutter wrapper for native browser engines | Arbitrary website traffic belongs to the selected site; never register browsing controllers with an ad SDK |
| `webview_flutter_android` 4.14.1 | Android-specific WebView controls, requests and lifecycle | Browser capabilities and storage follow Android System WebView |
| `webview_flutter_wkwebview` 3.26.1 | WKWebView controls, private-store integration and explicit teardown | A small vendored patch supports nonpersistent configuration and deterministic controller disposal; inspect its local README/diff when upgrading |
| `sqflite` 2.4.4 | Structured, transactional native local persistence | No server or account; not an encryption layer |
| `sqflite_common_ffi_web` 1.1.3 | Shared SQL repository for web through local WASM/IndexedDB | Upstream marks web support experimental; storage may be evicted and is origin-specific |
| `path` 1.9.1 | Safe database-path composition | Local pure Dart utility |
| `cryptography` 2.9.0 | SHA-256 and Ed25519 filter verification; salted PBKDF2 PIN derivation | On-device primitives; no hosted cryptography or credentials in the client |
| `flutter_secure_storage` 11.1.0 | Platform protected storage for PIN verifier and retry state | Android protected storage / iOS device-bound non-synchronizing Keychain; no PIN feature on Web |
| `url_launcher` 6.3.2 | Explicit external links and the web search companion | Opening a link hands it to the destination app/browser |
| `share_plus` 13.3.0 | User-requested platform share sheet | User chooses the receiving service; never invoked automatically |
| `file_selector` 1.1.0 | Official Flutter OS file chooser for bookmark HTML | Reads only the user-selected file, with a 2 MiB limit; no browser-profile scanning. BSD-3-Clause. |
| `html` 0.15.7 | Inert Netscape bookmark export parsing | Pure Dart parser, no script execution or network requests; preflight file/tree/candidate limits. BSD-3-Clause. |
| `google_mobile_ads` 9.1.0 | User-requested Android/iOS Google test-ad foundation and UMP | Optional demo, default off, no production request path; SDK may process technical/ad data |
| `cupertino_icons` 1.0.8 | Icon font referenced by Flutter's adaptive interface code | Assets only; prevents missing-font build warnings; no network code |

Google's installed Flutter plugin declares Android Google Mobile Ads 25.4.0 and iOS Google Mobile Ads `~> 13.7`. Review the final resolved native SDK versions when preparing disclosures. The plugin includes consent SDK integration; Wingman does not add a second analytics system. [Official plugin package](https://pub.dev/packages/google_mobile_ads)

Development-only dependencies include `flutter_test`, `integration_test`, `flutter_lints` and `sqflite_common_ffi` for real SQLite repository tests on the host. They are not runtime telemetry integrations.

No Firebase Analytics, Google Analytics, Meta, attribution library, mediation adapter, behavioral analytics SDK or standalone crash-reporting SDK has been added. Google Mobile Ads itself has documented measurement behavior; “no separate analytics SDK” does not mean “no third-party technical processing.” See [PRIVACY.md](PRIVACY.md).

The local WKWebView patch assigns the data store before creating a WKWebView for correct private isolation. Its explicit controller disposal removes the controller's observers and releases the Pigeon-owned view after native teardown, avoiding retention until Dart garbage collection. It uses existing plugin lifecycle machinery, not private WebKit APIs, and leaves generated protocols unchanged. Replace it with equivalent official support when available, preserving private-isolation, native-view-retention and data-deletion regression tests. Its existing license is retained; see [the patch manifest](../third_party/webview_flutter_wkwebview/WINGMAN_PATCH.md).

The 3A additions were checked against the current official [file_selector package](https://pub.dev/packages/file_selector) and [html package](https://pub.dev/packages/html). Mobile save-location selection is not supported by file_selector; bookmark export uses the existing OS share sheet on mobile and a direct browser download on Web, after an explicit full-address disclosure. Exported files/share caches can outlive the application session.
