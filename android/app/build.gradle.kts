import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties (local builds) or from
// environment variables (CI). Without either, release builds fall back to the
// debug key so `flutter run --release` keeps working.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(property: String, env: String): String? =
    keystoreProperties.getProperty(property) ?: System.getenv(env)

val releaseStoreFile = signingValue("storeFile", "BPM_KEYSTORE_PATH")

android {
    namespace = "flkaiser.de.bpmcounter"
    // Android 17
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "flkaiser.de.bpmcounter"
        // Android 8.0, the first version with adaptive launcher icons.
        minSdk = 26
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStoreFile != null) {
            create("release") {
                storeFile = file(releaseStoreFile)
                storePassword = signingValue("storePassword", "BPM_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "BPM_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "BPM_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    dependenciesInfo {
        // No Google-encrypted dependency blob in the APK (keeps F-Droid & co. happy).
        includeInApk = false
        includeInBundle = false
    }

    packaging {
        jniLibs {
            // Store the native libraries (Flutter engine and app code) compressed. With
            // minSdk 23 or higher they are stored uncompressed by default, which more than
            // doubles the size of the APK people download.
            useLegacyPackaging = true
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
