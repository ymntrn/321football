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
    Regex("admobAppIdAndroid\\s*=\\s*'([^']+)'").find(config)?.groupValues?.get(1)
        ?: throw GradleException("admobAppIdAndroid not found in lib/ads/ad_config.dart")
}

android {
    namespace = "com.yamanturan.football321"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.yamanturan.football321"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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
