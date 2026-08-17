import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Release signing ─────────────────────────────────────────────
// Reads android/key.properties (git-ignored — see key.properties.example
// for the template). Falls back to debug signing if that file is
// missing, so `flutter run --release` / CI keep working before signing
// is set up — but a debug-signed build will be REJECTED by Play
// Console, so this must resolve to the release config before you submit.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.communitydome.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Changed from the default "com.example.communitydome" — Play
        // Console blocks any com.example.* package name outright. This
        // requires a matching update to android/app/google-services.json
        // (register a new Android app under this package name in the
        // Firebase console) and to the release SHA-1 registered for
        // Google Sign-In — see PLAY_STORE_DEPLOYMENT.md.
        applicationId = "com.communitydome.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                // rootProject.file (not file) — resolves relative to
                // android/, where key.properties and the .jks both live,
                // not android/app/ where this build script's own project
                // dir is. Using plain file() here was pointing at
                // android/app/<keystore>, which doesn't exist.
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    lint {
        // AGP runs an automatic "lintVital" check on every module pulled
        // into a release build, including flutter_stripe's bundled
        // :stripe_android module. That module's own lint classpath still
        // references the unresolvable play-services-tapandpay dependency
        // (see the configurations.all exclude below — it only covers our
        // own :app dependency graph, not :stripe_android's internal lint
        // tooling). Skipping the automatic release lint gate avoids that;
        // it doesn't disable lint entirely, just the pre-release "vital"
        // pass — you can still run `flutter analyze` / `./gradlew lint`
        // manually any time.
        checkReleaseBuilds = false
    }

    buildTypes {
        release {
            // Real release signing once key.properties exists; falls back to
            // debug signing otherwise. A debug-signed build will be
            // rejected by Play Console — don't submit until this resolves
            // to signingConfigs["release"].
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Extra R8 keep/dontwarn rules on top of Flutter's own defaults —
            // currently just the flutter_stripe push-provisioning classes
            // that R8 flagged as missing (see proguard-rules.pro for why).
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// flutter_stripe (via its native :stripe_android module) pulls in Stripe's
// card-issuing push-provisioning SDK, which in turn depends on
// com.google.android.gms:play-services-tapandpay — a Google Pay Issuer API
// artifact that requires separate Google approval and isn't resolvable from
// any repo this project has configured. We don't use Stripe Issuing /
// add-to-Google-Pay-wallet features (this app takes regular payments only),
// so exclude the dependency outright rather than fighting to resolve it.
// The -dontwarn rules in proguard-rules.pro handle the resulting R8
// "missing classes" warnings for the same reason.
configurations.all {
    exclude(group = "com.stripe", module = "stripe-android-issuing-push-provisioning")
}
