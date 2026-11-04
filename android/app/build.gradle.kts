import java.io.FileInputStream
import java.util.Properties
import com.android.build.gradle.internal.api.ApkVariantOutputImpl

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

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
val splitPerAbi: Boolean = project.findProperty("split-per-abi")?.toString()?.toBoolean() ?: false
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

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    defaultConfig {
        applicationId = "com.mounsokdara.video_player"
        minSdk = 24
        targetSdk = 36
        versionCode = appVersionCode
        versionName = appVersionName

        if (selectedAbis.isNotEmpty() && !splitPerAbi) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(selectedAbis)
            }
        }
        externalNativeBuild {
            cmake {
                val cmakeAbis = if (selectedAbis.isNotEmpty()) selectedAbis else listOf("arm64-v8a", "armeabi-v7a", "x86_64")
                abiFilters.addAll(cmakeAbis)
                arguments += listOf("-DANDROID_STL=c++_static")
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
            if (selectedAbis.isNotEmpty()) {
                allAbis.filter { it !in selectedAbis }.forEach { excludes += "**/lib/$it/**" }
            }
        }
    }

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
            isMinifyEnabled = true
            isShrinkResources = false
        }
    }
}

val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)
android.applicationVariants.configureEach {
    val variant = this
    variant.outputs.forEach { output ->
        val abiVersionCode = abiCodes[output.filters.find { it.filterType == "ABI" }?.identifier]
        if (abiVersionCode != null) {
            (output as ApkVariantOutputImpl).versionCodeOverride = variant.versionCode * 10 + abiVersionCode
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

configurations.configureEach {
    exclude(group = "com.google.android.play")
}

dependencies {
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.media:media:1.7.0")
}
