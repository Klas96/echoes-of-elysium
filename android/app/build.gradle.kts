import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing:
//  - locally: android/key.properties (gitignored) with storeFile, storePassword,
//    keyAlias, keyPassword
//  - in CI:   env vars ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD,
//    ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD
// If neither is present, release builds fall back to the debug key so
// `flutter run --release` keeps working for contributors without the key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

fun signingValue(propKey: String, envKey: String): String? =
    keystoreProperties.getProperty(propKey)?.takeIf { it.isNotBlank() }
        ?: System.getenv(envKey)?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val hasReleaseSigning = releaseStoreFile != null &&
    signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD") != null &&
    signingValue("keyAlias", "ANDROID_KEY_ALIAS") != null

android {
    namespace = "se.klasholmgren.echoesofelysium"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "25.1.8937393" // Use a stable NDK version

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "se.klasholmgren.echoesofelysium"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 21 // Minimum SDK for Bonfire compatibility
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
                    ?: signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("No release keystore configured (android/key.properties or ANDROID_KEYSTORE_* env); signing release with the debug key.")
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
