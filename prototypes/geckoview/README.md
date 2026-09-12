# Isolated GeckoView comparison

This is a sparse overlay of the ordinary Wingman consumer project. `prepare.py` creates a separate external project directory, copies the current consumer source and reviewed assets, and overlays only the prototype Android implementation. A destination must be empty or carry a valid matching `prototype-build.json` ownership marker; unrelated nonempty destinations are rejected before any copy. It does not change production dependencies or application data. The prototype uses `lib/main.dart`, the same Flutter UI, platform-view type and browser method/event interface, and a distinct application ID `com.wingmanbrowser.wingman_browser.gecko_prototype`. There is no engine-selection setting.

From the repository root:

```sh
python3 prototypes/geckoview/prepare.py --destination /tmp/wingman-geckoview-prototype
cd /tmp/wingman-geckoview-prototype
flutter pub get
flutter build apk --release --target lib/main.dart --target-platform android-arm64
```

The prototype release uses the checkout's local debug signing configuration; it is not a store-signed production release. Do not promote or distribute it merely because it compiles. See `docs/ENGINE_DECISION.md` and the actual acceptance matrix for unresolved gates. Root consumer builds remain separate from this copied build directory.

The mandatory bundled extension registers a blocking resource listener before configuration, verifies the same build-pinned six-category baseline, and stays closed until a trusted background-only native handshake completes. Normal and private sessions both require the ready acknowledgement and explicit private extension enablement. The copied baseline remains owned by the source asset; no second editable policy snapshot is maintained here. Pages receive no privileged native messaging API.

Stable GeckoView is pinned to Mozilla Maven `155.0.20260903215306`, source revision `5fdfd0092780e85643e2cddc0e1b590c8b9ef860`. Mozilla source and licensing: https://hg.mozilla.org/releases/mozilla-release/rev/5fdfd0092780e85643e2cddc0e1b590c8b9ef860 and https://www.mozilla.org/MPL/2.0/. Preserve bundled third-party notices and provide matching MPL-covered source to recipients before distributing a binary. The integration introduces no Firefox accounts, branding, telemetry client, service credentials or browser-components application fork. Wingman would own security updates and regression releases for any promoted bundled engine.

The stable AAR requires Android API26+, compileSdk37, AGP9.1.1, Gradle9.3.1 and Kotlin2.4.10 in the copied project. The production adapter retains API24+. GeckoView uses the supported TextureView backend for Flutter composition. The APK includes `assets/WINGMAN_GECKOVIEW_NOTICE.txt` with matching source references; bundled upstream notices are preserved. Scoped private cleanup is not acknowledged by Gecko's public void API, and signed policy hot updates are not implemented in this comparison; neither gate is implied to pass.


The recipe pins arm64 native packaging explicitly; Flutter's `--target-platform` flag alone does not filter Gecko's transitive native libraries. For clean size comparisons after changing ABIs, remove only generated `build/app/outputs/apk/<mode>`, `build/app/intermediates/incremental/package<Mode>` and the matching generated Flutter APK before rebuilding. The copied Gradle configuration bounds the heap to 2 GiB and workers to two, with Kotlin compiling in process. Do not collect runtime benchmarks during concurrent builds or heavy host swapping.

Installed opt-in probe (debug only): build `:app:assembleDebug :app:assembleDebugAndroidTest`, install the isolated APK and test APK on a task-owned emulator, then run `adb -s <serial> shell am instrument -w -e class com.wingmanbrowser.wingman_browser.GeckoResourcePolicyTest com.wingmanbrowser.wingman_browser.gecko_prototype.test/android.test.InstrumentationTestRunner`. This starts an unexported secure test activity with an owned loopback fixture; it adds no page/native JavaScript bridge. The normal/private image and normal service-worker redirect cases passed on stable155/API37/16KiB during this milestone. See the decision document for exact build and server-counter evidence.

`measure.py` records identified-artifact metrics without clearing app data. Supply both APK paths, `--serial`, `--output`, and an operator-confirmed `--scene`. `--memory webview` or `--memory gecko` requires that exact app to be foreground and saves only its process memory and owned renderer bindings. `--cold-startups` explicitly force-stops the two comparison packages and launches them alternately three times each; run it only after both apps have been placed on Home and all builds are idle. `am start` completion measures OS activity launch, not first page paint. Host swap/load and distinct main PIDs are retained so overloaded or hot-process samples cannot silently become a benchmark.
