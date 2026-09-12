# Android consumer browser implementation and evidence

The Android adapter uses the existing `wingman/protected-browser` channel and `wingman/protected-web` platform view with Android System WebView. Consumer mode is `consumerWeb`; the native build receives `WINGMAN_EDITION` from Flutter's build defines and does not open the consumer adapter for a managed edition.

## Implemented transport and lifecycle

- Chromium owns page networking, request bodies, normal redirects, JavaScript, IndexedDB/localStorage, cache, first-party cookies and rendering. The old exact-resource `HttpURLConnection` transport and injected CSP are removed.
- The build-pinned local mandatory domain/path baseline checks top-level navigations, initial resource requests and service-worker requests. Unknown domains are allowed under policy, never described as verified safe. Tracker suffixes apply to third-party resources; functional third parties are not blanket denied.
- Normal tabs use the default persistent WebView profile. Private tabs use fresh AndroidX WebKit profiles only when both `MULTI_PROFILE` and `DELETE_BROWSING_DATA` are supported. Private profile data is cleared after its view closes and abandoned profiles are deleted at the next startup. It is never reused as normal data. Unsupported providers report private unavailable.
- Hiding a normal tab or backgrounding the app pauses it without destroying its renderer, position, or WebView navigation stack. Explicit tab closure and the Hand It Over security gate release content views. Browser startup migration no longer deletes normal cookies/storage on every launch.
- Back/forward check their destination and use native history. Reload, stop, find, find-next, share and user-initiated new-window events use native APIs. Popup transport views have networking disabled until the destination is checked and a normal protected tab is created.
- File uploads use `ACTION_OPEN_DOCUMENT` and restrict returned handles to content URIs; the selected origin is rechecked. Downloads ask the user to choose an `ACTION_CREATE_DOCUMENT` destination and use a separate bounded downloader which checks every redirect and never carries cookies across origins. Executable filename extensions are unsupported; files are never executed or automatically opened. Download bytes are not the general browser transport.
- Camera/microphone/coarse location prompt for the current HTTPS origin, then request the specific OS permission. The request is checked again before grant. Grants are not silently persisted. Media requires user gesture and supports native fullscreen.
- HTTP(S) incoming links reach the ordinary app. Android 10+ default-browser setup invokes the system browser role chooser, with default-app settings fallback on older supported Android.

## Maintained platform references and limits

[WebViewClient](https://developer.android.com/reference/android/webkit/WebViewClient) documents that `shouldInterceptRequest` is not called for subsequent URLs in a resource redirect chain and excludes some internal URL schemes. Main-frame navigations have separate policy checks, but the URL filter cannot claim complete category coverage of redirected subresources, generated blobs, WebSockets, page bodies, mixed-topic feeds, or changing ads. AndroidX WebKit 1.15.0 does not expose a universal content-classification network hook. A stronger maintained engine filtering integration is still needed to close these gaps.

[Profile](https://developer.android.com/reference/androidx/webkit/Profile) and [ProfileStore](https://developer.android.com/reference/androidx/webkit/ProfileStore) define isolated browsing data and feature-gated deletion. A private profile is disk-backed while alive; it is isolated and explicitly purged, not represented as a memory-only process. OS/process failure can defer deletion until next startup; private tabs are never restored.

[WebChromeClient](https://developer.android.com/reference/android/webkit/WebChromeClient) provides chooser, permission, media and popup callbacks. Downloads created by page `blob:` URLs, HTTP Basic Auth dialogs, client-certificate selection, WebAuthn and provider-restricted sign-in flows are not fully implemented or verified by this milestone. TLS certificate errors always cancel; no certificate override UI exists. HTTPS mixed-content loads remain `MIXED_CONTENT_NEVER_ALLOW` even when ordinary HTTP top-level browsing is supported.

## Check record

- Native build: `flutter build apk --debug`, ordinary `lib/main.dart`, successfully built and installed `com.wingmanbrowser.wingman_browser/.MainActivity` version `0.10.0`, code `10` on `emulator-5554`.
- Selected emulator: Android API 37 Pixel 9 Pro XL, Android System WebView `151.0.7922.199` (package `com.google.android.webview`). No Wingman package was installed on that device before the recovery build.
- `android/gradlew :app:testDebugUnitTest` passed 3 native test methods covering query serialization, ordinary punctuation/Unicode, encoded/fullwidth bang redirects, control rejection, and query limits. This is a serializer regression suite, not proof of browser acceptance.
- Actual app execution and native platform test outcomes are recorded in `SEARCH_ACCEPTANCE.md`; no unexecuted journey should be inferred from implementation alone.

The local `scripts/serve_browser_fixtures.py` server runs only on loopback port 8810 and contains synthetic JS/form/login/upload/download/redirect cases. It neither logs nor saves submitted body data. Fixture logins are explicitly synthetic and create no third-party account. The invalid TLS case uses `expired.badssl.com` and must remain blocked.

## Ordinary installed-app journey ledger, September 11

These outcomes were observed through Android Studio's emulator display using native UI actions, ordinary `lib/main.dart`, consumer edition, version 0.10.0+10. No integration-test entry point or mock renderer was used.

- Local loopback fixtures: JavaScript changed visible text; GET site-search form returned its query; a synthetic POST login followed a 303 to a signed-in page; localStorage persisted. Normal cookie and storage survived an APK replacement and relaunch. A private tab at the same origin started signed out with empty storage. Relaunch discarded private tabs and preserved normal tab records.
- Back and forward traversed real fixture history. A permitted redirect loaded the second page. A category redirect and prohibited new window were blocked while the permitted page remained visible; a user-initiated permitted new window created another private tab. The expired.badssl.com TLS error showed a blocked secure-connection error with no bypass.
- Harmless text download: the app displayed the filename, origin and private-download persistence disclosure, then Android's save picker. The generated `wingman-test.txt` (53 bytes) was saved with a visible success toast. The upload picker selected that same generated file; the synthetic localhost endpoint confirmed 246 multipart request bytes received and discarded.
- Search `Chicago weather` produced ordinary strict-provider results and an interactive weather card. The initial result-click attempt hit the provider browser promotion; play.google.com opened, but this is not counted as a Weather.com success.
- Search `ESPN football scores` opened the organic ESPN NFL scoreboard with rendered scores. The neutral page visibly included DraftKings sponsorship/odds; this is a demonstrated mixed-page promotion false negative of domain/path filtering, not evidence of perfect mandatory content classification.
- Search `Walmart notebooks` opened the organic “Shop Notebooks by Brand” category with product cards and 1000+ results.
- Search `Python tutorial` returned results and the More Results button appended page two. Refining the query in the provider's own input to `Python tutorial docs.python.org` returned the Python tutorial, which opened at docs.python.org with the full article.
- Search `MDN JavaScript guide` opened developer.mozilla.org with the full JavaScript Guide. Opening Find in page, entering `loops`, then Next and Done exposed a Flutter `_dependents.isEmpty` assertion; reported to the Flutter owner for repair. Both Find defects were repaired and the final release was retested successfully as recorded below.
- Search `NASA Artemis mission` opened the NASA source link at www.nasa.gov, with the normal homepage rendered. Search `NOAA ocean facts` opened oceanservice.noaa.gov/facts with images and article cards.
- Search `BBC science news` opened the first BBC Science & Environment result at www.bbc.com, with headline cards and images. `Wikipedia Mount Everest` opened en.wikipedia.org/wiki/Mount_Everest with the full article and mountain image.
- Search `AP News science` opened apnews.com/science, rendering the science listing. `Stack Overflow Python sort list` opened the answer source at stackoverflow.com/questions/64975026 with the complete answer and comments visible. No CAPTCHA was bypassed.

Search matrix total at this point: 12 submitted queries (11 omnibox submissions plus one in-provider refinement), 10 ordinary result destination domains visibly rendered. The provider's More Results append, JavaScript form refinement, first-party functional assets, normal navigation, multiple tabs, scrolling and real page history were exercised. Search results were not replaced by a local reader.

## Authenticated policy updates

Android independently validates the signed Ed25519 envelope against bundled trust keys, payload purpose, exact release metadata, data digest and six-category schema. It parses an immutable candidate before returning a preparation token. Activation quiesces renderers, commits native current/previous receipts and the sequence high-water mark, swaps the snapshot, then acknowledges. A failed durable Dart commit can revert the prepared generation; the high-water mark never decreases. Startup capabilities and both resource/service-worker request gates require the loaded sequence and digest to match the acknowledged current receipt. A missing or corrupt cached generation cannot silently reopen against the older bundled generation after an update was accepted.

The shipped update-key asset is empty and no production update endpoint or signing key was invented. The installed app therefore uses the pinned baseline. Signed-release tests use ephemeral generated keys in the JVM test process; they do not authorize production updates. Devices without platform Ed25519 support retain the pinned baseline and cannot install updates.

### Final release follow-up

The final ordinary release APK (68.1 MB, non-debug package flags, version 0.10.0+10) replaced the debug installation without clearing data. The normal localhost session still showed the synthetic signed-in cookie and saved localStorage marker. The repaired Find dialog accepted `session`, advanced with Next and dismissed without the earlier Flutter assertion; native yellow matches and the active orange match were visible afterward. A subsequent review found that `findResult` events with no URL were incorrectly treated as invalid page metadata by Dart, suspending the renderer; this event-routing fix was installed and the final Find → next-page test passed without a blank renderer.

The app's Default browser action opened Android's system browser-role chooser. Wingman was selected and set as default on the emulator; the system role holder was independently read back as `com.wingmanbrowser.wingman_browser`.

The synthetic media fixture at `/media` uses a generated canvas stream with no camera, microphone or third-party media. User-initiated Play showed advancing frames and the native fullscreen view worked. System Back initially did not exit fullscreen; the Android adapter now registers the supported Back callback for fullscreen and the legacy Activity fallback. The final release successfully exited fullscreen with Android system Back, restoring the playing inline video and browser controls.

The latest JVM native suite passed eight test methods: three strict-query tests and five authenticated consumer-update tests, with no failures or errors. The update tests use ephemeral Ed25519 key pairs and cover tampered/truncated bytes, changed signatures, unknown keys, purpose/version/path metadata, missing categories and malformed rules. These tests do not claim a real production policy release was installed.

### Final acceptance and artifact status

- Final source build: `flutter build apk --release`, log `work/android-recovery/final-permission-release-build.log`, succeeded in 35.2 seconds after the preceding complete 311.4-second release build. The current 68.1 MB APK was installed with replacement, keeping normal data, and the ordinary app was left at Wingman Home. Version remains 0.10.0+10, entry point `lib/main.dart`, consumer edition.
- This is a release-mode **local verification APK**, using the checkout's existing debug signing configuration. It is not signed for an app-store production release.
- Final generated-video test: Play showed advancing canvas-stream frames; fullscreen entered; Android system Back restored inline playback and browser chrome.
- Final Find test: searched `media`, advanced with Next, dismissed Done, and immediately followed the fixture Home link. The match stayed visible during the dialog and the next page rendered immediately. No scope error, suspension, blank renderer or dismissal assertion occurred.
- The HTTPS WebRTC sample at `https://webrtc.github.io/samples/src/content/getusermedia/gum/` displayed a native camera permission prompt naming `https://webrtc.github.io/`. Choosing Deny returned `NotAllowedError` to the page. No camera, microphone or location access was granted. Positive sensor-grant flows remain unverified.
- Default-browser role selection passed through the actual OS chooser. Read-only Android package resolution for both HTTP and HTTPS `ACTION_VIEW` + `BROWSABLE` URLs chose `com.wingmanbrowser.wingman_browser/.MainActivity` as default. An end-to-end external-app link tap remains **unverified**: the enabled computer-use surface did not expose the emulator's synthetic incoming-message controls. Resolver evidence is not represented as a successful external tap.
- Both temporary loopback fixture servers were stopped after Android and iOS acceptance, and the Android 8810/8811 reverse-port mappings were removed. The generated text download remains a user-selected fixture file; normal browser data was retained.
