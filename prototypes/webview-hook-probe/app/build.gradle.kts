plugins { id("com.android.application") }
android {
 namespace = "com.wingmanbrowser.hookprobe"
 compileSdk = 36
 useLibrary("android.test.runner")
 useLibrary("android.test.base")
 defaultConfig { applicationId = "com.wingmanbrowser.hookprobe"; minSdk = 24; targetSdk = 36; versionCode = 1; versionName = "1.0"; testInstrumentationRunner = "android.test.InstrumentationTestRunner" }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
