# Isolated Android WebView redirect callback probe

This is an owned neutral loopback instrumentation test, **not the ordinary Wingman consumer application**. It creates an ephemeral local HTTP server, directly requests a neutral 1×1 PNG at a test-only denied path, then requests a permitted path that HTTP302 redirects to that same path. It counts both native interception callbacks and server requests, and checks image load/error state through the owned document title. It does not visit prohibited material, modify production policy, expose a privileged page bridge, or erase application data.

Build with the repository's wrapper:

```sh
./android/gradlew -p prototypes/webview-hook-probe :app:assembleDebug :app:assembleDebugAndroidTest
adb -s emulator-5554 install -r prototypes/webview-hook-probe/app/build/outputs/apk/debug/app-debug.apk
adb -s emulator-5554 install -r prototypes/webview-hook-probe/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s emulator-5554 shell am instrument -w com.wingmanbrowser.hookprobe.test/android.test.InstrumentationTestRunner
```

The test intentionally passes when it demonstrates the documented callback gap: direct resource denied before server access, redirect target loaded without a second interception callback. This is engine API evidence and must be labeled separately from the consumer acceptance matrix. Package ID is isolated (`com.wingmanbrowser.hookprobe`), and capture protection remains enabled.
