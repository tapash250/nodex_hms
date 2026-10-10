import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material is supplied out-of-band: a gitignored
// android/key.properties pointing at an upload keystore (see
// key.properties.example), or CI secrets. When it is absent the release build
// falls back to the debug key so `flutter build apk --release` still succeeds
// for verification builds — a distribution build MUST provide a real keystore.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}
val hasReleaseSigning =
    keystorePropertiesFile.exists() &&
        keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.nodex.nodex_hms"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nodex.nodex_hms"

        // Encrypted SQLite via powersync 2.x (SQLite3MultipleCiphers) requires
        // API 23+; flutter_secure_storage
        // uses EncryptedSharedPreferences, which also needs 23+. Ward tablets below
        // this level cannot store clinical data under the required protection.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storePassword = keystoreProperties.getProperty("storePassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { path ->
                    val file = file(path)
                    if (file.isAbsolute) file else rootProject.file(path)
                }
            }
        }
    }

    buildTypes {
        release {
            // A real keystore when one is configured, otherwise the debug key so
            // verification builds succeed. Never silently ships a debug-signed
            // artifact as a release distribution: provisioning the keystore is the
            // step that flips this to a real upload key.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }

        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/*.kotlin_module",
            )
        }
    }

    lint {
        // A lint error in a clinical build is a release blocker, not a warning to
        // triage later.
        abortOnError = true
        checkReleaseBuilds = true
        warningsAsErrors = false
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
