// android/app/build.gradle.kts
//
// SIGNING STRATEGY
// ----------------
// Both local release builds and GitHub Actions CI builds sign with the same
// keystore so Android accepts over-the-top APK installations without requiring
// a manual uninstall first.
//
// Local developer workflow:
//   1. Generate a keystore once:
//        keytool -genkey -v -keystore release.jks -alias pia-wireguard \
//                -keyalg RSA -keysize 2048 -validity 10000
//   2. Place release.jks somewhere OUTSIDE the repo (e.g. ~/.android/).
//   3. Create android/key.properties (already in .gitignore):
//        storeFile=/Users/andrew/.android/release.jks
//        storePassword=YOUR_STORE_PASSWORD
//        keyAlias=pia-wireguard
//        keyPassword=YOUR_KEY_PASSWORD
//
// GitHub Actions CI workflow:
//   1. Base64-encode the same JKS:  base64 -i release.jks | pbcopy
//   2. Add four repository secrets:
//        KEYSTORE_BASE64      <- the base64 blob
//        KEYSTORE_PASSWORD    <- storePassword value
//        KEY_ALIAS            <- keyAlias value
//        KEY_PASSWORD         <- keyPassword value
//   3. The release.yml workflow decodes the JKS and writes a key.properties
//      file before calling `flutter build apk --release`, so CI and local
//      builds use identical credentials.
//
// WHY THIS MATTERS
// Android enforces that every APK update must be signed by the same certificate
// as the installed version. Mixing a debug-signed local APK with a release-
// signed CI APK (or vice versa) causes a INSTALL_FAILED_UPDATE_INCOMPATIBLE
// rejection. Unifying on one release keystore eliminates this entirely.

import java.util.Properties
import java.io.FileInputStream
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import org.jetbrains.kotlin.gradle.plugin.KotlinBasePlugin
import org.jetbrains.kotlin.gradle.plugin.getKotlinPluginVersion

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Load signing credentials from android/key.properties if present.
// Falls back gracefully so the project still syncs on machines without the
// keystore file (e.g. a fresh clone before the developer sets up signing).
// ---------------------------------------------------------------------------
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

// ---------------------------------------------------------------------------
// Build provenance for the in-app "About" screen (lib/screens/about_screen.dart).
//
// Everything below runs at CONFIGURATION time and must degrade to `unknownValue`
// rather than fail the build: a source tarball has no .git, and git may not be on
// the Gradle daemon's PATH (common on Windows, where it often lives only inside
// Git Bash). Values reach Dart via BuildConfig -> MainActivity's MethodChannel.
// ---------------------------------------------------------------------------
val unknownValue = "unknown"

/** Absolute path inside the git work tree. rootProject.projectDir is <repo>/android. */
val gitWorkTree: String = rootProject.projectDir.absolutePath

/**
 * Runs `git -C <android/> <args>` via providers.exec, which Gradle records as a declared
 * build input. A raw ProcessBuilder here would instead be reported as an "external
 * process started at configuration time" configuration-cache problem.
 *
 * `-C` is used in preference to ExecSpec.workingDir so the command never depends on the
 * daemon's working directory: git walks up from android/ and finds <repo>/.git.
 *
 * Returns `unknownValue` when git is not on PATH (the process cannot start, which throws
 * on query and is NOT covered by isIgnoreExitValue), when .git is absent (git exits 128),
 * or when stdout is blank.
 */
fun git(vararg args: String): String {
    val execOutput = providers.exec {
        commandLine("git", "-C", gitWorkTree, *args)
        isIgnoreExitValue = true
    }
    return try {
        if (execOutput.result.get().exitValue != 0) {
            unknownValue
        } else {
            execOutput.standardOutput.asText.get().trim().ifEmpty { unknownValue }
        }
    } catch (_: Exception) {
        unknownValue
    }
}

// A single git process yields both the abbreviated SHA and the commit date.
// --abbrev=7 pins the width: bare %h honours core.abbrev, which auto-grows with
// repository size and would make the displayed hash drift over time.
val gitLogFields: List<String> = git("log", "-1", "--abbrev=7", "--format=%h%x09%cI").split("\t")
val commitHash: String = gitLogFields.getOrNull(0)?.takeIf { it.isNotBlank() } ?: unknownValue
val commitDate: String = gitLogFields.getOrNull(1)?.takeIf { it.isNotBlank() } ?: unknownValue

// GITHUB_REF_NAME is authoritative in CI. release.yml triggers on tag pushes, where
// actions/checkout leaves a DETACHED HEAD and `git rev-parse --abbrev-ref HEAD` returns
// the literal string "HEAD" -- never the tag -- so the git fallback must reject it.
// providers.environmentVariable (not System.getenv) keeps this a declared build input.
val gitBranch: String =
    providers.environmentVariable("GITHUB_REF_NAME").orNull?.takeIf { it.isNotBlank() }
        ?: git("rev-parse", "--abbrev-ref", "HEAD").takeIf { it != "HEAD" }
        ?: unknownValue

val runnerId: String =
    providers.environmentVariable("GITHUB_RUN_ID").orNull?.takeIf { it.isNotBlank() }
        ?: "Local Build"

// Wall-clock "now" at configuration time is deliberate (exact build provenance was the
// requirement), but it does invalidate GenerateBuildConfig on EVERY build, cascading into
// compileKotlin -> dex -> package. GIT_COMMIT_DATE below is the reproducible cross-check.
val buildTimestamp: String =
    DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss 'UTC'")
        .withZone(ZoneOffset.UTC)
        .format(Instant.now())

// getKotlinPluginVersion() resolves because settings.gradle.kts declares
// org.jetbrains.kotlin.android `apply false`, which puts KGP on every project's
// build-script classpath -- the same mechanism that makes JvmTarget resolve below.
// It reports the KGP that actually compiled this module, which is the honest answer for
// an About screen. Fallback: KotlinBasePlugin.pluginVersion lives in the *stable*
// kotlin-gradle-plugin-api artifact and is what Flutter's own VersionFetcher.kt uses.
// KGP is applied to :app by the Flutter plugin during the plugins {} block above.
val kotlinVersion: String =
    runCatching { getKotlinPluginVersion() }.getOrNull()
        ?: plugins.findPlugin(KotlinBasePlugin::class.java)?.pluginVersion
        ?: unknownValue

// flutter.compileSdkVersion is a plain Int, not a Provider. Hoisted so android.compileSdk
// and BuildConfig.COMPILE_SDK cannot drift apart. Named `compileSdkInt` because
// `compileSdkVersion` collides with the legacy BaseExtension.compileSdkVersion(...) method.
val compileSdkInt: Int = flutter.compileSdkVersion

/**
 * buildConfigField's value argument is copied VERBATIM into BuildConfig.java, so a String
 * must arrive already wrapped in quotes with backslashes, quotes and newlines escaped.
 * Values here come from git and the environment, so this is mandatory rather than
 * cosmetic: a branch named `foo"bar` would otherwise emit uncompilable generated Java.
 */
fun javaStringLiteral(value: String): String =
    "\"" + value
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\r", "\\r")
        .replace("\n", "\\n") + "\""

android {
    namespace = "com.exponentiallydigital.pia_wireguard_cfga"
    compileSdk = compileSdkInt
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        // AGP 8.0+ defaults buildConfig to false, and AGP 9 removed the
        // android.defaults.buildfeatures.buildconfig escape hatch, so this DSL flag is the
        // only way to get a BuildConfig class. AGP then generates DEBUG, APPLICATION_ID,
        // BUILD_TYPE, VERSION_CODE and VERSION_NAME for an application module itself --
        // only the custom fields in defaultConfig below need declaring by hand.
        buildConfig = true
    }

    dependencyLocking {
        // Enforce strict lock compliance (fails the build if lockfiles are out of date)
        lockMode.set(org.gradle.api.artifacts.dsl.LockMode.STRICT)
        ignoredDependencies.add("io.flutter:*")
        lockAllConfigurations()
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

// untold pain and suffering if you try to rename a project: reverted back to
// "com.exponentiallydigital.pia_wireguard_cfga" from "com.exponentiallydigital.cfg_pia_wireguard"
// now I understand why signal is from "thought crimes" :)
    defaultConfig {
        applicationId = "com.exponentiallydigital.pia_wireguard_cfga"
//        minSdk = flutter.minSdkVersion
        minSdk = 24 // Android 24: "Android 7.0 (Nougat)"
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        base.archivesName.set("cfg_pia_wireguard")

        // --- "About" screen provenance; helpers are above the android {} block. ---
        // BUILD_TYPE / VERSION_NAME / VERSION_CODE / APPLICATION_ID / DEBUG are NOT listed
        // here: AGP generates those for an application module automatically.
        buildConfigField("String", "BUILD_TIMESTAMP", javaStringLiteral(buildTimestamp))
        buildConfigField("String", "GIT_COMMIT_HASH", javaStringLiteral(commitHash))
        buildConfigField("String", "GIT_COMMIT_DATE", javaStringLiteral(commitDate))
        buildConfigField("String", "GIT_BRANCH", javaStringLiteral(gitBranch))
        buildConfigField("String", "CI_RUNNER_ID", javaStringLiteral(runnerId))
        buildConfigField("String", "COMPILE_SDK", javaStringLiteral(compileSdkInt.toString()))
        buildConfigField("String", "KOTLIN_VERSION", javaStringLiteral(kotlinVersion))
    }

    // ---------------------------------------------------------------------------
    // Signing configs
    // Release builds use the shared keystore loaded from key.properties.
    // If key.properties is absent (e.g. a cold CI clone before secrets are
    // written), the block still compiles -- the build will fail at signing time
    // with a clear error rather than silently using the debug certificate.
    // ---------------------------------------------------------------------------
    signingConfigs {
        create("release") {
            storeFile = keyProperties["storeFile"]?.let { file(it) }
            storePassword = keyProperties["storePassword"] as String?
            keyAlias = keyProperties["keyAlias"] as String?
            keyPassword = keyProperties["keyPassword"] as String?
        }
    }

    buildTypes {
        // Debug builds continue to use the default debug signing certificate.
        // They will NOT be installable over a release-signed APK -- that is
        // intentional and correct behaviour.
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }

        // Release builds use the shared keystore so local and CI APKs are
        // always signed by the same certificate.
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
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
