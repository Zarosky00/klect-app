plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase Cloud Messaging (push notifications). Reads google-services.json
    // in this directory. See docs/OPERATIONS.md §2 for the server-side wiring.
    id("com.google.gms.google-services")
}

val klectKeystorePath = System.getenv("KLECT_KEYSTORE_PATH")
val klectKeystorePassword = System.getenv("KLECT_KEYSTORE_PASSWORD")
val klectKeyAlias = System.getenv("KLECT_KEY_ALIAS")
val klectKeyPassword = System.getenv("KLECT_KEY_PASSWORD")
val hasKlectReleaseSigning = listOf(
    klectKeystorePath,
    klectKeystorePassword,
    klectKeyAlias,
    klectKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "com.klect.klect"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on API < 26; desugaring
        // backports it. Pairs with the coreLibraryDesugaring dependency below.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.klect.klect"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKlectReleaseSigning) {
            create("release") {
                storeFile = file(klectKeystorePath!!)
                storePassword = klectKeystorePassword
                keyAlias = klectKeyAlias
                keyPassword = klectKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Pull requests can still verify a release build without secrets,
            // while the tagged release workflow always supplies the stable key.
            signingConfig = signingConfigs.getByName(
                if (hasKlectReleaseSigning) "release" else "debug",
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

dependencies {
    // Java 8+ API desugaring (java.time et al) — required by
    // flutter_local_notifications. Keep in sync with the AGP-recommended
    // version; 2.1.4+ is what current AGP asks for.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-telecom:1.0.0")
    implementation(platform("com.google.firebase:firebase-bom:34.15.0"))
    implementation("com.google.firebase:firebase-messaging")
    testImplementation("junit:junit:4.13.2")
}
