# Native browser implementation and verification boundaries

Wingman uses the official `webview_flutter` controller and platform view on Android and iOS. The app's Flutter/native method channel is not exposed to websites. No `addJavaScriptChannel` or Android `addJavascriptInterface` is installed. On Android 8+ a narrow forwarding WebViewClient contains renderer process failures, destroys affected views, and exposes a recoverable page error. Reload creates a fresh isolated session. A debug-only app-channel integration hook can terminate the real renderer for tests; release builds reject it. Page script execution exists only for the explicitly test-only integration helper; app functionality does not export page contents.

## Engines and sessions

The live engine pool is capped at three. Metadata is persisted separately. Switching among resident engines preserves navigation stacks and form state. A fourth engine evicts the least recently used engine. Returning to an evicted normal tab reloads the last URL; its in-memory navigation stack and unsaved forms are lost. Evicting or closing a private engine destroys that site session; private tab metadata never persists. Open/close generations prevent a pending creation from resurrecting a closed engine. Widget keys and an IndexedStack preserve resident platform views across ordinary UI rebuilds.

On iOS, every private tab gets a new nonpersistent WK website store before construction. The small API extension is documented beside the vendored package. On Android, every private tab gets a separate randomly named profile and `LOAD_NO_CACHE`. Private availability requires both `MULTI_PROFILE` and `DELETE_BROWSING_DATA`; an unsupported provider is rejected before loading. Profile cookies and complete browsing data are cleared before destruction. Loaded profiles cannot be deregistered in that same Android process, so deletion of empty profile entries and unclean-exit remnants is scheduled at the next process start. Android may temporarily write this isolated data to disk while a tab is open; it is not RAM-only incognito storage.

Android backups are disabled. The iOS structured database directory is Library/Application Support/Wingman, excluded from backup and outside the Files-visible Documents directory. User-confirmed downloads are saved separately. Websites and the operating system still process browser traffic and engine data; private mode is not anonymity.

## Audited native settings

- TLS certificate errors call `cancel`; there is no bypass control or trust-all handler.
- Android mixed content is `MIXED_CONTENT_NEVER_ALLOW`; Safe Browsing is explicitly enabled when supported. WKWebView keeps WebKit's security enforcement and fraudulent website warnings.
- Android file access, arbitrary content-provider resource access, access from file URLs, and universal access from file URLs are disabled. Top-level `file:`, `content:`, `data:`, `javascript:`, `intent:` and unrecognized schemes are blocked by navigation policy. The file picker returns only explicitly user-selected document URIs; actual provider/upload combinations still need device verification.
- Plain HTTP is supported as required for a general browser. Android enables cleartext transport; iOS permits arbitrary loads only inside WebViews through `NSAllowsArbitraryLoadsInWebContent`. The UI distinguishes HTTP from HTTPS.
- Browser console messages are discarded. App/native failures return fixed messages without URLs, file names, cookies or page contents. Native web debugging is enabled only in debug builds.
- Automatic JavaScript popup windows are disabled. User-activated target-blank links open in the current tab. Android disables multiple native windows to avoid upstream temporary popup WebViews using the default profile.
- Android third-party cookies are disabled. Some cross-site sign-ins or embedded features may require a future per-site compatibility setting.

## Permissions and secondary features

Camera and microphone requests require an active HTTPS page, explicit Flutter permission approval, then the operating system permission flow. Unsupported permission resources are denied. Current page, tab and lifecycle state are checked again after asynchronous prompts. The official media callback lacks the requesting iframe origin; the prompt accurately says the displayed page including embedded content, rather than inventing a precise request origin. Android geolocation identifies the requested origin, requests approximate location only, and does not retain site permission. iOS location follows WebKit's contextual system permission flow. HTTP authentication is accepted only for HTTPS challenges matching the current page host and is never saved by Wingman.

Android file upload uses the system document picker without broad storage permission. iOS uses WebKit's system picker. Direct camera capture attributes and all picker/provider combinations need physical-device testing. JavaScript alert/confirm/prompt use native app dialogs with site context. The official prompt API returns a string, so cancel maps to an empty string. Native Android fullscreen media support comes from the platform widget; iOS uses WebKit. Background/tab changes suspend WK media and invoke Android WebView pause/resume.

Android downloads use a native confirmation and DownloadManager with sanitized filenames, validated HTTP(S) addresses, and no cookie/auth-header copying into the OS download database. Authenticated downloads may fail; blob/data downloads are blocked. Android 10+ uses Downloads; older devices use the app's external Downloads folder to avoid storage permission. iOS WKDownload handles attachments/unsupported types after confirmation and saves into Documents/Downloads, available through Files. Neither platform executes downloaded files. Downloads may outlive private sessions. Interrupted downloads, background completion, redirects and authenticated exports need further device validation.

An intentional iOS download policy change ends the page's loading indicator and restores its committed address. Only WebKit's policy-interruption error for that same armed navigation is suppressed; other navigation failures still reach the browser error UI. Failed main-frame loads preserve the attempted address, and Retry requests that address again instead of reloading the prior committed page.

SPA and back-forward-cache transitions receive two bounded metadata refreshes after URL changes/history actions, with no continuous page polling. Find-in-page uses native APIs; desktop mode requests the native WK desktop content mode or derives a desktop user agent from the installed Android engine version. There is no browser-engine version spoof fixed in app source.

## Clearing data

All live engines are stopped and released before site data is cleared. Android cache removal also works with no live view. Current Android providers support full browsing-data removal, including service workers; this API necessarily clears cookies and network cache when site storage is selected, which the dialog discloses. Older providers receive legacy storage clearing and a message explaining that complete service-worker clearing requires a WebView update. iOS removes selected WK data types from the default store; private stores are independently cleared on close. Bookmarks are unaffected.

## Default browser

Android declares general HTTP/HTTPS VIEW intent filters and uses the system browser-role request on Android 10+. Older Android opens default-app settings. Cold/warm incoming links are validated and passed into Flutter; Flutter's automatic deep-link router is disabled. iOS receives scene/app HTTP links and exposes Settings, but does not claim approval. Apple must approve the managed default-browser entitlement, followed by developer signing/store configuration. There is no fabricated entitlement or universal-link ownership claim.

Build results and actual device scenarios belong in the main README/test report. Compilation alone does not validate every permission, download, login, media or device lifecycle scenario.
