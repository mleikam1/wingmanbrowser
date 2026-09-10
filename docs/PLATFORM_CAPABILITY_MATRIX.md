# Platform capability matrix — Phase 3A

Recorded on 2026-09-10. This matrix distinguishes the installed combination from API availability and future approval work. Emulator and simulator results do not establish physical-device, third-party password-provider or App Store acceptance.

## Installed and built combination

| Component | Observed version / target |
|---|---|
| Flutter / Dart | Flutter 3.44.4 stable (`ad70ec4617`), Dart 3.12.2; engine `a10d8ac38d` |
| Official WebView bindings | `webview_flutter` 4.14.1; Android 4.14.1; WK 3.26.1 with the documented narrow local patch |
| Android native compatibility library | AndroidX WebKit 1.15.0 |
| Android toolchain | Android Studio JBR 21.0.9 is the effective build JDK; Java/Kotlin bytecode target 17 |
| Android test device | Dedicated 2 GB / 2-core emulator, Android 16 / API 36, security patch 2026-01-05 |
| Android website engine | Google System WebView **134.0.6998.135**, queried from the running emulator |
| Apple toolchain | Xcode 26.3, build 17C529 |
| Apple test device | iPhone 17 Pro simulator, iOS 26.3.1 (23D8133) |
| Apple website engine | OS-provided WKWebView; no separate engine binary version was measured |

Baseline debug builds passed: Android 8.3 seconds and iOS simulator 13.8 seconds. Logs are retained in the parent workspace `work/phase3-baseline-android.log` and `work/phase3-baseline-ios.log`. Build times are workstation observations, not product startup measurements.

## Privacy and authentication boundaries

| Capability | Android installed combination | iOS installed combination |
|---|---|---|
| Private website session | Unique native profile, feature-gated on multi-profile and complete deletion. Independent cookies/localStorage and fresh reopening are fixture tested. Temporary profile data may be written to disk. | New nonpersistent WK store configured before construction. Independent cookies/localStorage and fresh reopening are fixture tested. |
| Private close | Clears the profile's complete browsing data; empty profile registration/remnants are removed on later process startup because a loaded profile cannot be deleted immediately. | Stops/detaches the view and clears its nonpersistent store. |
| OS screenshots / recents | Global secure activity flag before first frame; API 33+ recents screenshots disabled. Applies to all Wingman routes. Download dialog has its own secure flag. Actual final-app emulator screenshot showed a black app surface. | Neutral per-scene cover on resign-active/background. A real Simulator App Switcher transition showed the visible portion of the overlapping Wingman card as neutral white; full-card coverage/timing was not observed. Active screenshots/recordings are not blocked by this API. |
| HTTP Basic authentication | HTTPS, same-host and active-request checks before/after prompts. No app database/vault persistence. Synthetic HTTPS fixture **passed**: private receives its own challenge, denial does not authenticate, private credentials work, normal session survives private close, next private is fresh. | Same guards; private credentials use persistence `none`, normal WK credentials use `forSession`. The same synthetic HTTPS separation/preservation fixture **passed**. This does not establish every real-site/provider/auth scheme combination. |
| OS password autofill | Google autofill service was configured on this emulator, but no real vault/account was used. Actual suggestion, save and private-provider behavior remain **unverified**. `setSaveFormData(false)` does not disable modern OS autofill. | Native WK/system mediation may offer autofill, but no real vault/account or third-party provider was used. Actual behavior, including private suggestions, remains **unverified**. |
| Passkeys / arbitrary sites | WebAuthn mode remains the native **NONE** default. Browser-mode credential-provider trust/approval is not configured. Unsupported, with no application-mode workaround. | No verified browser entitlement/approval or relying-party association setup. Arbitrary-site passkeys and actual credential-provider acceptance remain **unsupported/unverified**. |
| Default-browser status | HTTP(S) role request and incoming-intent plumbing implemented; it does not silently make Wingman the default. | Build/readiness only. Apple approval, entitlement and signed distribution setup remain external requirements. |

No Wingman credential vault, password scraping, authentication bridge, trust-all TLS handler, account signup or device-wide trust certificate was added. Independent website-store tests do not prove isolation for every HTTP-auth/cache/IndexedDB/OS-provider combination. Private browsing is not network anonymity and cannot hide activity from a website, network operator or compromised device.

The native store and profile behavior follows [Android Profile](https://developer.android.com/reference/androidx/webkit/Profile), [ProfileStore](https://developer.android.com/reference/androidx/webkit/ProfileStore), and [WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore). Snapshot handling follows [Apple's background UI guidance](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background), [Android FLAG_SECURE](https://developer.android.com/reference/android/view/WindowManager.LayoutParams#FLAG_SECURE), and [recents screenshot controls](https://developer.android.com/reference/android/app/Activity#setRecentsScreenshotEnabled(boolean)).

WebAuthn limitations are based on [Android WebSettingsCompat](https://developer.android.com/reference/androidx/webkit/WebSettingsCompat#setWebAuthenticationSupport(android.webkit.WebSettings,int)), [privileged credential callers](https://developer.android.com/identity/sign-in/privileged-apps), and [WebView Credential Manager integration](https://developer.android.com/identity/sign-in/credential-manager-webview). Apple distinguishes [embedded-app passkey support](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys) from [browser passkey use](https://developer.apple.com/documentation/authenticationservices/passkey-use-in-web-browsers). Autofill behavior depends on [site HTML](https://developer.apple.com/documentation/security/enabling-password-autofill-on-an-html-input-element) and [Android provider/runtime integration](https://developer.android.com/identity/autofill/autofill-optimize); [Android 8's form-data API change](https://developer.android.com/about/versions/oreo/android-8.0-changes) prevents treating the legacy flag as an OS-vault control.

## Reader, scaling and reliability

| Capability | Delivered boundary |
|---|---|
| Reader | iOS only, explicit user action, ephemeral plain text from the rendered main document, isolated WK content world. No form values, editable/hidden/blurred/clipped text or subframe extraction. Semantic modal dialogs and large positioned overlays cause refusal. Conservative access-gate detection is incomplete and can reject ordinary layouts. No access gate is removed or remotely bypassed. |
| Android Reader | Disabled. The installed AndroidX 1.15 binding has no supported isolated execution-world API; shared-world helpers could be overwritten by the website. The newer API documented under [WebViewCompat](https://developer.android.com/reference/androidx/webkit/WebViewCompat) is not presumed supported by this older installed combination. |
| Page size | 75–200%; native Android text zoom and iOS [pageZoom](https://developer.apple.com/documentation/webkit/wkwebview/pagezoom), which scales all WK page content. |
| Guard stale callbacks | Native request tokens and generations reject queued reports from an old navigation. Main-thread delivery avoids an avoidable posted-report race. History actions bind their request identity before native navigation. |
| Site-data deletion | Success requires native completion. After 15 seconds the UI receives a failure; new loads remain paused until deletion completes. Another selection cannot report success using an earlier pending operation. |
| Mobile engine budget | At most three resident views. Eviction/restart preserves normal metadata, not the evicted engine's history stack, forms or scroll position. Private engine eviction closes that session. |
| TLS and website security | Certificate failures remain closed; Android mixed content is denied, Safe Browsing remains enabled with reporting opt-out behavior documented separately. No new remote URL-reputation service was introduced. |

The initial Android Guard baseline failed once when an allowed return retained a previous block, then passed unchanged on repeat. The initial iOS browser baseline stalled during clear-data waiting; its runner was interrupted and is **not** counted as a pass. Subsequent diagnosis and regression outcomes are recorded in [native Phase 3 validation](phase3/NATIVE_VALIDATION.md). These baseline failures remain part of the evidence rather than being replaced by successful reruns.

The final iOS main app also passed manual simulator Files import, import preview/confirmation, export confirmation, the actual share sheet and Save to Files; the resulting 387-byte file was checked for the two expected synthetic URLs and escaped title. Its Reader displayed the local article without textarea/hidden markers, and Larger text visibly increased Reader's font. Closing a manually opened private article preserved the normal tab; read-only database counts found zero private-marker rows and one normal article row in each of `tabs` and `history`. The actual app-switcher observation is limited to the visible portion of an overlapping card, as described above; it is not exhaustive snapshot/privacy proof.

## Performance and unverified acceptance

Before-change measurements used the existing debug native fixture, a synthetic indexed 100,000-rule SQLite pack, and no host cache: 1,000 native evaluations had p50 **432.583 µs**, p95 **4,655.875 µs**. Main-process PSS was **309,280 KB** idle and **351,018 KB** with three views; renderer memory was not measured. Three loopback loads took 1,215 / 156 / 339 ms. Thirty debug tester-pump tab switches had p50 66.691 ms and p95 112.790 ms. These are fixture/debug observations, not production frame times or a smoothness guarantee. Host swap use was 18,250.62 MB even without concurrent heavy builds. See native validation for the matching after-change measurement.

Still unverified: physical low-end Android hardware, older physical iPhones, release/profile frame latency, total browser process-tree memory, actual browser-ready cold startup, full process-death restoration timing, third-party autofill providers, real-account/passkey acceptance, and exhaustive cache/HTTP-auth isolation beyond the synthetic HTTPS Basic fixture. No claim of store readiness, browser entitlement approval or cross-device sync follows from these tests.
