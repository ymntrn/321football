import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The AdMob APP id lives in lib/ads/ad_config.dart, the one file that holds
// every ad id; it is read from there into the manifest placeholder below so
// nobody has to keep two copies in step.
val admobAppId: String = run {
    val config = rootProject.file("../lib/ads/ad_config.dart").readText()
    Regex("static const admobAppIdAndroid\\s*=\\s*'([^']+)'").find(config)?.groupValues?.get(1)
        ?: throw GradleException("admobAppIdAndroid not found in lib/ads/ad_config.dart")
}

// Release signing comes from android/key.properties (gitignored, never
// committed; docs/release.md step 1 creates it):
//
//   storePassword=...
//   keyPassword=...
//   keyAlias=upload
//   storeFile=C:/keys/321football-upload.jks
//
// (Forward slashes: a .properties file treats a backslash as an escape.)
// Without that file a release build is signed with the DEBUG key, so
// `flutter run --release` keeps working on any machine — but such a build
// cannot be uploaded to Play.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseKey = keystorePropertiesFile.exists()

android {
    namespace = "com.yamanturan.football321"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The Play Store identity of the app. Never change it after the first
        // upload: a different id is a different app.
        applicationId = "com.yamanturan.football321"
        // 24 = Flutter's floor, and google_mobile_ads' own minimum.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Both come from `version:` in pubspec.yaml — `1.0.0+1` is
        // versionName 1.0.0, versionCode 1. Bump the +N for EVERY upload to
        // Play; it refuses a versionCode it has seen before.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["admobAppId"] = admobAppId
    }

    // Store the bundled SQLite database uncompressed. Compressed, the first-launch
    // copy spends most of its ~12 s inflating 62 MB; stored, it is a plain file
    // copy. Costs install size, not Play download size (Play compresses anyway).
    androidResources {
        noCompress += listOf("db")
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8: shrink and obfuscate the JAVA/Kotlin side (plugins, the
            // Play services ads SDK, MainActivity's channel). The Dart code
            // — Supabase included — is AOT-compiled into libapp.so and is
            // not touched by R8. proguard-rules.pro keeps what the plugins
            // reach by reflection.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
