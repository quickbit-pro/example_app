import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val brandProperties = Properties().apply {
    file("brand.properties").inputStream().use { load(it) }
}
// Firebase belongs to the selected customer only.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val playUploadStoreFile = System.getenv("PLAY_UPLOAD_STORE_FILE")
val playUploadStorePassword = System.getenv("PLAY_UPLOAD_STORE_PASSWORD")
val playUploadKeyAlias = System.getenv("PLAY_UPLOAD_KEY_ALIAS")
val playUploadKeyPassword = System.getenv("PLAY_UPLOAD_KEY_PASSWORD")
val playUploadSigningConfigured = listOf(
    playUploadStoreFile,
    playUploadStorePassword,
    playUploadKeyAlias,
    playUploadKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "global.hoppa.mobile_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = brandProperties.getProperty("applicationId")
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (playUploadSigningConfigured) {
            create("playUpload") {
                storeFile = file(playUploadStoreFile!!)
                storePassword = playUploadStorePassword
                keyAlias = playUploadKeyAlias
                keyPassword = playUploadKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (playUploadSigningConfigured) {
                signingConfig = signingConfigs.getByName("playUpload")
            }
        }
    }
}

flutter {
    source = "../.."
}
