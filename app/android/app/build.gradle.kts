import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing — loaded from android/key.properties when present.
// If the file is missing (CI without secrets, fresh clone for debug-only
// work), release builds fall back to the debug keys so `flutter run
// --release` still works locally without forcing every contributor to
// configure signing.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        load(FileInputStream(f))
    }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "work.jacobmoura.remotepi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "work.jacobmoura.remotepi"
        // plan/23 § "Versão mínima Android" — the remote_pi_identity
        // plugin requires API 34 (Block Store + modern biometry), so
        // the app inherits the same floor. Bump intentional, recorded
        // in the plano.
        minSdk = 34
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // 16 KB page-size compliance (Google Play, enforced since Nov 2025).
    // mobile_scanner 5.2.3 pulls ML Kit + CameraX whose prebuilt native libs
    // are only 4 KB-aligned (libbarhopper_v3.so, libimage_processing_util_jni.so),
    // which Play now rejects. Force the newer, 16 KB-aligned releases — Gradle
    // version-conflict resolution picks these over mobile_scanner's transitive
    // 17.2.0 / 1.3.3. No Dart-side scanner API change. CameraX modules are kept
    // on one matching version to avoid cross-module runtime mismatches.
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
    implementation("androidx.camera:camera-core:1.4.2")
    implementation("androidx.camera:camera-camera2:1.4.2")
    implementation("androidx.camera:camera-lifecycle:1.4.2")
}
