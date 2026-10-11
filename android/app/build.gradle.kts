import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Single source of truth for the app version: <repo root>/version.txt, format "versionName+versionCode"
// (example: 1.0.2.1+5). Edit that one file to release a new version.
val versionParts = rootProject.projectDir.parentFile.resolve("version.txt").readText().trim().split("+")
require(versionParts.size == 2) { "version.txt must look like 1.0.2.1+5" }
val appVersionName = versionParts[0].trim()
val appVersionCode = versionParts[1].trim().toInt()

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val allAbis = listOf("armeabi-v7a", "arm64-v8a", "x86_64", "x86")
val abiByPlatform = mapOf(
    "android-arm" to "armeabi-v7a",
    "android-arm64" to "arm64-v8a",
    "android-x64" to "x86_64",
)
val selectedAbis: List<String> = run {
    val fromEnv = (System.getenv("ABI_FILTER") ?: "").split(" ", ",").filter { it.isNotBlank() }
    val fromProp = (project.findProperty("target-platform") as String?)
        ?.split(",")?.mapNotNull { abiByPlatform[it.trim()] } ?: emptyList()
    if (fromEnv.isNotEmpty()) fromEnv else fromProp
}

android {
    namespace = "com.mounsokdara.video_player"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mounsokdara.video_player"
        minSdk = 24
        targetSdk = 36
        versionCode = appVersionCode
        versionName = appVersionName

        // Plugin libraries (libmpv, ffmpeg) are packed for every CPU unless filtered here, so each
        // split APK would be as big as the universal one. The list comes from ABI_FILTER (set by the
        // CI workflow) or, as a fallback, from the -Ptarget-platform property Flutter passes.
        if (selectedAbis.isNotEmpty()) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(selectedAbis)
            }
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            // Belt and braces: drop every CPU that was not asked for, whatever the plugins bundle.
            if (selectedAbis.isNotEmpty()) {
                allAbis.filter { it !in selectedAbis }.forEach { excludes += "**/lib/$it/**" }
            }
        }
    }

    // F-Droid: do not embed the Google "Dependency metadata" signing block in the APK
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 on, with proguard-rules.pro keeping everything except the unused Google Play wrappers (F-Droid).
            isMinifyEnabled = true
            isShrinkResources = false
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

// F-Droid: Flutter's embedding pulls in Google Play Core (only used for Play Store
// deferred components, which this app does not use). Exclude it so no proprietary classes ship.
configurations.configureEach {
    exclude(group = "com.google.android.play")
}

dependencies {
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.media:media:1.7.0")
}
