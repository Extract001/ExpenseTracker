import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.alamgir.expensetracker.expense_tracker"
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

    signingConfigs {
        create("release") {
            val keyAliasVal = keystoreProperties.getProperty("keyAlias") ?: System.getenv("ANDROID_KEY_ALIAS")
            val keyPasswordVal = keystoreProperties.getProperty("keyPassword") ?: System.getenv("ANDROID_KEY_PASSWORD")
            val storeFileVal = keystoreProperties.getProperty("storeFile") ?: System.getenv("ANDROID_STORE_FILE")
            val storePasswordVal = keystoreProperties.getProperty("storePassword") ?: System.getenv("ANDROID_STORE_PASSWORD")

            if (!keyAliasVal.isNullOrBlank() &&
                !keyPasswordVal.isNullOrBlank() &&
                !storeFileVal.isNullOrBlank() &&
                !storePasswordVal.isNullOrBlank()) {
                val candidate1 = rootProject.file(storeFileVal).absoluteFile
                val candidate2 = file(storeFileVal).absoluteFile
                val resolvedStoreFile = if (candidate1.exists()) {
                    candidate1
                } else if (candidate2.exists()) {
                    candidate2
                } else {
                    candidate1
                }

                keyAlias = keyAliasVal
                keyPassword = keyPasswordVal
                storeFile = resolvedStoreFile
                storePassword = storePasswordVal
            }
        }
    }

    defaultConfig {
        applicationId = "com.alamgir.expensetracker.expense_tracker"
        // Target modern Android API requirements
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            // Production signing configuration - NEVER falls back to debug
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}


