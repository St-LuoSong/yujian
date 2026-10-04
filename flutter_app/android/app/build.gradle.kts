import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional release signing.
//
// Create `android/key.properties` (git ignored) plus a keystore to produce a
// properly signed release APK:
//
//     storeFile=keystore/yujian-release.jks   # relative to the android/ folder
//     storePassword=...
//     keyAlias=...
//     keyPassword=...
//
// Release builds intentionally do not fall back to the debug certificate:
// the backend trusts a certificate allow-list, so an ambiguously signed APK
// must fail at build time rather than reach the upload screen.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val requestsRelease = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (requestsRelease && !hasReleaseKeystore) {
    throw GradleException(
        "Release signing is not configured. Create android/key.properties and the release keystore."
    )
}
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.yujian.travel"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.yujian.travel"
        // Competition baseline: Android 10 (API 29) and newer devices.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) signingConfig = signingConfigs.getByName("release")
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
