### Prompt for Claude Code: add "About" hamburger menu item

Add an "About" screen to the app, accessible from the hamburger menu.

### 1. Navigation & Menu Setup

* Add an "About" menu option at the bottom of the hamburger drawer, directly below the "View app log" entry.
* Tapping this option will open a new scrollable screen formatted similarly to the "View app log" screen (matching dark background, app bar, padding, and font styling).

### 2. Styling & Layout Requirements

* **Labels / Item names:** White text (e.g., "Privacy policy:", "Commit hash:").
* **Clickable Links:** Green text matching the app's existing primary green color constant/theme.
* **LICENSE Text:** Light grey text, styled for readability on dark backgrounds.
* All external URLs must be tapable and open in the system browser using `url_launcher`.

### 3. Screen Content & Formatting

Format the screen using the exact layout below (with vertical spacing/padding between sections):

---
cfg-pia-wg v<versionNumber> build <buildNumber>
Built by: <installer source> at <build timestamp/compilation date and time>
Build type: <debug, release, or specific build flavor>
Commit hash: <Git commit SHA>
Git branch/tag: <branch or tag used to trigger build>
Build runner ID: <CI Runner ID>
CPU Architecture (ABI): <active architecture running on device e.g. arm64-v8a, x86_64>
Target Android version: <OS version currently running on device e.g. Android 15 (API 35)>
Compile SDK: <compileSdk>
Kotlin: <kotlin_version>

GitHub source code repository: https://github.com/ExponentiallyDigital/cfg-pia-wg
ReadMe: https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md
Change log: https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/CHANGELOG.md
Architecture: https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/ARCHITECTURE.md
Security policy: https://github.com/ExponentiallyDigital/cfg-pia-wg/SECURITY.md
Privacy policy: https://www.exponentiallydigital.com/cfg-pia-wg/privacy.html

<Full content of LICENSE file>
---

### 4. Technical Implementation Details

1. **LICENSE Text Embedding (Development Time):**
   * Read the contents of the local `./LICENSE` file in the project root during implementation.
   * Embed the raw text of `./LICENSE` directly into the Dart source code as an inlined string constant (e.g., `const String _licenseText = r'''...''';`). 
   * Do NOT load the license dynamically at runtime or register it as an asset in `pubspec.yaml`.

2. **Build Metadata Injection (Gradle):**
   * Update `android/app/build.gradle.kts` to capture and inject the following into `BuildConfig`:
     - Short Git commit SHA (`git rev-parse --short HEAD`)
     - Git branch/tag (`GITHUB_REF_NAME` env var, falling back to `git rev-parse --abbrev-ref HEAD`)
     - `GITHUB_RUN_ID` (defaulting to "Local Build" if null)
     - Compilation UTC timestamp (e.g. `java.time.Instant.now().toString()`)
     - `compileSdk` version and `kotlin_version`

3. **Runtime Metadata & Native Channel (Kotlin / MainActivity.kt):**
   * Query Android system info and package details in `MainActivity.kt`:
     - Installer source via `PackageManager` (`getInstallSourceInfo` for API 30+ / `getInstallerPackageName` legacy)
     - CPU Architecture via `Build.SUPPORTED_ABIS[0]`
     - Android OS Version & API level via `Build.VERSION.RELEASE` and `Build.VERSION.SDK_INT`
     - Build Type via `BuildConfig.BUILD_TYPE`
   * Expose a `MethodChannel` to deliver all build and runtime metadata fields (`versionName`, `buildNumber`, `installer`, `buildTimestamp`, `buildType`, `commitHash`, `gitBranch`, `runnerId`, `cpuAbi`, `osVersion`, `compileSdk`, `kotlinVersion`) to Flutter for display.
