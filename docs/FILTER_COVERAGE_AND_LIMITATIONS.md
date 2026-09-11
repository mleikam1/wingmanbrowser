# Coverage and limitations

Status: a bounded reviewed offline catalog, with unsupported capabilities closed. No production whole-web protection claim.

| Path | Current behavior | Remaining limitation |
| --- | --- | --- |
| Bundled article/title/summary | Signed exact-byte approval, context/review/expiry/revocation checks | 14 short development-reviewed articles only |
| HTTP(S), unknown/mixed domains, redirectors, POST, new windows | No content engine or live load method | Live browsing unavailable |
| Scripts, images, media, frames, CSS/font remote URLs, workers, service workers, prefetch | No live document, resource loader, or WebView plugin | Not an implementation of native resource classification |
| Authentication, uploads, downloads, blob/data/file/intent/custom schemes | Unsupported; native direct calls reject | Cannot use ordinary browser site workflows |
| Reader/preview/imported HTML | Old remote/extracted/import preview routes removed | No live Reader, file import/export, thumbnail service or remote sanitizer |
| External links/OS menus | App-owned launch/share/process-text routes removed or denied; controlled local editing | OS/host-browser menus and other apps are outside app control |
| Private/student | Same eligibility, ephemeral reviewed activity, no ads | Shared managed-device deployment not verified |
| Policy outage/expiry/corruption | No content; fixed restricted Home/settings | No operational policy-update/recovery service |

The prior Android `shouldInterceptRequest` callback is not a universal before-response decision point: platform documentation excludes certain schemes and does not supply subsequent resource-redirect URLs. Main-frame navigation callbacks do not cover all POST/resource paths. Prior iOS WK content rules and navigation delegates did not establish full positive eligibility for arbitrary page dependencies or dynamic content. These are reasons to remove live capability, not claims that a deny-list now solves it. See [Android WebViewClient](https://developer.android.com/reference/android/webkit/WebViewClient), [Android ServiceWorkerClient](https://developer.android.com/reference/android/webkit/ServiceWorkerClient), and [Apple WKNavigationDelegate](https://developer.apple.com/documentation/webkit/wknavigationdelegate).

Android and iOS actual native denial/request-counter checks are recorded separately from build results in SECURITY_TEST_MATRIX.md. Debug builds use local development networking. The release merged-manifest task passed with INTERNET removed; the release APK could not be built because the local AOT helper stalled, so release runtime behavior remains unverified. iOS source has no app content transport, but absence of observed loopback requests is not a complete device-wide packet audit. Flutter web fetches same-origin application assets and SQLite support files from its local host; it is not an extension, managed ChromeOS agent, or host-browser network firewall.

Accessibility includes semantic Flutter text, scalable article size, responsive scrolling and bounded local editing. VoiceOver/TalkBack, physical-device keyboards, full screen-capture timing and all OS menu permutations require acceptance testing before release. Android uses FLAG_SECURE; iOS inactive shielding does not prevent active-use screenshots. A zero-risk guarantee would exceed the evidence.
