// 1. Lock the plugins and build toolchain dependencies (What SonarQube wants)
buildscript {
    dependencyLocking {
        ignoredDependencies.add("io.flutter:*")
        lockAllConfigurations()
    }
}

// 2. Lock standard project configurations (Kept for completeness)
dependencyLocking {
    ignoredDependencies.add("io.flutter:*")
    lockAllConfigurations()
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    dependencyLocking {
        ignoredDependencies.add("io.flutter:*")
        lockAllConfigurations()
    }
}
subprojects {
    project.evaluationDependsOn(":app")
    dependencyLocking {
        ignoredDependencies.add("io.flutter:*")
        lockAllConfigurations()
    }
    // ID-058: every configuration is locked except the Android Gradle plugin's Unified Test Platform - the tooling
    // that runs instrumented tests on a device or emulator, through 13 internal `_internal-unified-test-platform-*`
    // configurations. This app has no instrumented tests, so nothing uses them, yet locking pinned 150 of their
    // libraries, 18 of which carry 86 known vulnerabilities (Netty, protobuf, Bouncy Castle, httpclient, commons-lang3)
    // that the OSV scan reports. None of it ships in the app. Unlocked, they stay out of the lockfile, so the lockfile
    // and the scan cover what the app ships and builds with. Revisit this if instrumented tests are ever added: those
    // tools would then run, and unpinned.
    //
    // Here, after the lockAllConfigurations() above, and not in app/build.gradle.kts: evaluationDependsOn(":app")
    // evaluates the app script before that call, so an unlock made there is switched back on by it.
    configurations.matching { it.name.startsWith("_internal-unified-test-platform") }.configureEach {
        resolutionStrategy.deactivateDependencyLocking()
    }
    // ID-481: Android Lint, which the plugin's release build runs as lintVitalRelease, came with AGP 9.4.1 carrying
    // five libraries with seven known vulnerabilities (Guava, commons-lang3, httpclient, Bouncy Castle). It runs at
    // build time and never ships, but unlike the test platform above it does run, so it stays locked, on the fixed
    // versions instead. Remove a line here once the plugin's own lint tool carries that version or newer.
    configurations.matching { it.name == "androidLintTool" }.configureEach {
        resolutionStrategy.force(
            "com.google.guava:guava:33.7.2-jre",
            "org.apache.commons:commons-lang3:3.21.0",
            "org.apache.httpcomponents:httpclient:4.5.14",
            "org.bouncycastle:bcprov-jdk18on:1.86",
            "org.bouncycastle:bcpkix-jdk18on:1.86",
            "org.bouncycastle:bcutil-jdk18on:1.86",
        )
    }
    // ID-217: a plugin module that still compiles its Java at source and target 8 made javac print three "value 8 is
    // obsolete" warnings on every build. The app itself is on 17 (app/build.gradle.kts). Silenced for the plugins
    // only, with the switch javac's own warning names, so the app's compile keeps every warning it has.
    if (project.name != "app") {
        tasks.withType<JavaCompile>().configureEach {
            options.compilerArgs.add("-Xlint:-options")
        }
    }
}

tasks.register<Delete>("clean") {
    group = "build"
    description = "Deletes the root build directory to completely clean the Android project outputs."   
    delete(rootProject.layout.buildDirectory)
}