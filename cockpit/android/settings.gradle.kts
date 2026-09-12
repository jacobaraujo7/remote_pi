pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 8.11.1 / Kotlin 2.2.20 / Gradle 8.14: a MESMA toolchain do app mobile
    // (../app/android). O template do Flutter 3.47 trazia AGP 9.1, que recusa o
    // `proguard-android.txt` ainda usado pelo flutter_inappwebview_android 1.1.3
    // e derruba o assembleRelease antes de assinar. Subir de volta só quando o
    // plugin migrar pra `proguard-android-optimize.txt`.
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
