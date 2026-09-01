import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials. Lives in android/key.properties (gitignored
// via android/.gitignore). The keystore file itself is also gitignored
// (**/*.keystore). Brought over from the user's RN Sunoh app so a release
// build of this Flutter app signs with the SAME stable key — without
// this, release was falling back to ~/.android/debug.keystore which
// rotates per-machine and triggered Android's "different signer" data
// wipe on every reinstall.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // Same applicationId as the RN sunoh app — same keystore (see
    // [[sunoh-android-signing]]) means installing this Flutter build over
    // the RN one is treated as an upgrade by Android, not a fresh install.
    namespace = "codes.afk.sunoh"
    // Pinned (not flutter.compileSdkVersion): innertubex-android requires
    // consumers to compile against API 37+. Flutter's default trails that,
    // so it's set explicitly here. targetSdk/minSdk are unaffected.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "codes.afk.sunoh"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Bumped from flutter default (21) to 24 — mpv_audio_kit (libmpv)
        // requires Android 7.0+. Drops Android 5/6 which is fine for this app.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Falls back to debug signing if key.properties is missing
            // (e.g., fresh clone before the user drops their key in).
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }
}

// Kotlin 2.4 removed the `kotlinOptions { jvmTarget = ... }` DSL inside the
// android block; jvmTarget now lives on the Kotlin extension's compilerOptions.
kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ── Library sync ─────────────────────────────────────────────────────
    // DocumentFile wraps the Storage Access Framework's tree API, which is
    // otherwise raw ContentResolver calls against DocumentsContract. AndroidX,
    // free software, and small — the alternative is hand-rolling directory
    // listing and file creation over a provider we do not control.
    implementation("androidx.documentfile:documentfile:1.0.1")

    // ── YouTube Music tier ───────────────────────────────────────────────
    // InnerTube extraction (client ladder, cipher/n-transform, format
    // selection, self-healing remote player configs) from the Metrolist
    // project. GPL-3.0 — see LICENSE at the repo root; linking this is
    // why sunoh is GPL-3.0.
    //
    // The catalog of playback clients is re-benchmarked upstream as Google
    // rotates its bot checks, and player configs are fetched at RUNTIME,
    // so most breakages heal without an APK release.
    implementation("com.github.MetrolistGroup.innertubex:innertubex-android:v0.2.6")

    // Coroutines — the extractor's public surface is `suspend`, and the
    // MethodChannel handler bridges those calls onto Flutter's platform
    // thread.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")

    // Ktor + OkHttp — InnerTubeX takes a caller-owned Ktor HttpClient and
    // we hand it the OkHttp engine (already present transitively, but
    // declared so the PO-token WebView's direct OkHttp use is explicit).
    implementation("io.ktor:ktor-client-okhttp:3.0.3")
    // Required by the InnerTube call shape: every response is read via
    // `.body<T>()`, which needs a JSON converter installed on the client.
    implementation("io.ktor:ktor-client-content-negotiation:3.0.3")
    implementation("io.ktor:ktor-serialization-kotlinx-json:3.0.3")
    implementation("io.ktor:ktor-client-encoding:3.0.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // The PO-token WebView parses BotGuard challenge payloads as JSON.
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // ArrayMap, used by the ported PO-token WebView.
    implementation("androidx.collection:collection-ktx:1.4.5")
}
