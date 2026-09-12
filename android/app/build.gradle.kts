import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val wingmanEdition = (project.findProperty("dart-defines") as? String).orEmpty()
    .split(',').mapNotNull { encoded -> runCatching { String(Base64.getDecoder().decode(encoded)) }.getOrNull() }
    .firstOrNull { it.startsWith("WINGMAN_EDITION=") }?.substringAfter('=') ?: "consumer"

android {
    buildFeatures { buildConfig = true }
    namespace = "com.wingmanbrowser.wingman_browser"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wingmanbrowser.wingman_browser"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("String", "WINGMAN_EDITION", "\"${if (wingmanEdition == "consumer") "consumer" else "managed"}\"")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}


dependencies {
    implementation("androidx.webkit:webkit:1.15.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
}
