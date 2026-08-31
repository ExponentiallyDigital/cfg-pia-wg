# Add an "About" screen to cfg-pia-wg

## Context

The app currently exposes no build provenance beyond the `v0.6.24` string in the header bar
([app_scaffold.dart:124-130](lib/widgets/app_scaffold.dart#L124-L130)). When a user reports a bug there is no way
to tell which commit, branch, CI run, build type or install source produced their binary — and no in-app view of the
GPL-3 licence or the project's policy documents.

This change adds an **About** entry at the bottom of the hamburger drawer (directly below "View app log") opening a
scrollable screen that shows build/runtime metadata, tappable links to the project's docs, and the full GPL-3 text.
Metadata is injected at build time into `BuildConfig` by Gradle and read at runtime in Kotlin, then delivered to
Flutter over the project's **first** `MethodChannel`.

CHANGELOG.md:46 already carries the entry for this work under `2026-07-28 v0.6.24 build 354`.

### Decisions confirmed with the user
- **Link colour:** `kHighlight` (`0xFF00D4AA`, the app's teal accent). The app has no green constant.
- **LICENCE body colour:** `Colors.white70` (deliberate one-off, not a palette entry).
- **SECURITY.md URL:** corrected to `.../blob/main/SECURITY.md` (the spec's version omitted `/blob/main/` and 404s).
- **Build timestamp:** exact seconds on every build. Accepted cost — see "Known trade-off" below.

---

## 1. Android: build-time metadata → `BuildConfig`

**File: [android/app/build.gradle.kts](android/app/build.gradle.kts)**

`buildConfig` is currently **off** (AGP 8+ defaults it to `false`, and AGP 9 removed the
`android.defaults.buildfeatures.buildconfig` property escape hatch), so `BuildConfig` is not generated at all today.

1. **Imports** after line 38 (`import java.io.FileInputStream`):
   `java.time.Instant`, `java.time.ZoneOffset`, `java.time.format.DateTimeFormatter`,
   `org.jetbrains.kotlin.gradle.plugin.KotlinBasePlugin`,
   `org.jetbrains.kotlin.gradle.plugin.getKotlinPluginVersion`.

2. **Metadata helpers** between the `keyProperties` block (line 54) and `android {` (line 56):

   - `fun git(vararg args: String): String` using **`providers.exec { commandLine("git", "-C", gitWorkTree, *args); isIgnoreExitValue = true }`**.
     - Use `providers.exec`, *not* `ProcessBuilder` — Gradle instruments the latter and reports it as a
       configuration-cache violation.
     - Use `git -C <abs path>` rather than `ExecSpec.workingDir`; `rootProject.projectDir` is `<repo>/android` and git
       walks upward to `<repo>/.git`. The `../../build` relocation in
       [android/build.gradle.kts:22-26](android/build.gradle.kts#L22-L26) affects only `layout.buildDirectory`.
     - Wrap the `.get()` in `try/catch` returning `"unknown"` — a missing `git` binary throws on query (it is **not**
       covered by `isIgnoreExitValue`), and a source tarball with no `.git` exits 128.
   - One git call for both SHA and commit date: `git("log", "-1", "--abbrev=7", "--format=%h%x09%cI")`, split on tab
     → `commitHash`, `commitDate`. Pin `--abbrev=7`; bare `%h` honours `core.abbrev`, which grows with repo size.
   - `gitBranch`: `providers.environmentVariable("GITHUB_REF_NAME")` first, then
     `git("rev-parse", "--abbrev-ref", "HEAD").takeIf { it != "HEAD" }`, else `"unknown"`.
     **The `"HEAD"` filter is load-bearing:** [release.yml](.github/workflows/release.yml) triggers on tag pushes, which
     leaves a detached HEAD where `--abbrev-ref` returns the literal string `HEAD`, never the tag.
   - `runnerId`: `providers.environmentVariable("GITHUB_RUN_ID")` else `"Local Build"`.
     Use `providers.environmentVariable`, not `System.getenv`, so the value is a declared build input.
   - `buildTimestamp`: `Instant.now()` formatted `yyyy-MM-dd HH:mm:ss 'UTC'` via
     `DateTimeFormatter.…withZone(ZoneOffset.UTC)`. Do **not** use `SimpleDateFormat`/`Date().toString()` (locale- and
     machine-dependent).
   - `kotlinVersion`: `runCatching { getKotlinPluginVersion() }.getOrNull() ?: plugins.findPlugin(KotlinBasePlugin::class.java)?.pluginVersion ?: "unknown"`.
     The import resolves because [android/settings.gradle.kts:23](android/settings.gradle.kts#L23) declares
     `org.jetbrains.kotlin.android version "2.3.20" apply false`, putting KGP on every project's build-script classpath
     — the same mechanism that already makes `JvmTarget` resolve at line 125.
     **Do not** add `id("org.jetbrains.kotlin.android")` to the app `plugins {}` block: Flutter's
     `FlutterPluginUtils.detectApplyingKotlinGradlePlugin` would then log an AGP-9 migration warning at **error** level
     on every single build. **Do not** use `KotlinVersion.CURRENT` (that is Gradle's embedded stdlib, ~2.2.x — silently
     wrong) or `KotlinCompilerVersion.VERSION` (deprecated internal API scheduled for removal).
   - `val compileSdkInt: Int = flutter.compileSdkVersion` — a plain `Int`, not a provider. Hoisted so `android.compileSdk`
     and the BuildConfig field cannot drift. Name it `compileSdkInt`, **not** `compileSdkVersion`, which collides with the
     legacy `BaseExtension.compileSdkVersion(...)` DSL method.
   - `fun javaStringLiteral(value: String): String` — wraps in quotes and escapes `\`, `"`, `\r`, `\n`.
     `buildConfigField`'s third argument is emitted **verbatim** into `BuildConfig.java`, so an unescaped branch name
     like `foo"bar` produces uncompilable generated Java. This is not cosmetic — every value here comes from git or the
     environment.

3. Change line 58 to `compileSdk = compileSdkInt`.

4. **Add after line 59** (`ndkVersion = flutter.ndkVersion`):
   ```kotlin
   buildFeatures { buildConfig = true }
   ```

5. **Add inside `defaultConfig`** after line 82 (`base.archivesName.set(...)`), all via `javaStringLiteral(...)`:
   `BUILD_TIMESTAMP`, `GIT_COMMIT_HASH`, `GIT_COMMIT_DATE`, `GIT_BRANCH`, `CI_RUNNER_ID`, `COMPILE_SDK`,
   `KOTLIN_VERSION`.

   **Do NOT declare** `BUILD_TYPE`, `VERSION_NAME`, `VERSION_CODE`, `APPLICATION_ID` or `DEBUG` — AGP generates all five
   for an application module automatically once `buildConfig = true`.

   **Do NOT** name any field `*_KEY`, `*_TOKEN`, `*_SECRET` or `API_*`: mobsfscan's `android_hardcoded` rule keys off
   those identifiers. `HASH` is not in its pattern set.

### Known trade-off (user-accepted)
A fresh `Instant.now()` per configuration means `GenerateBuildConfig` is never up to date, cascading into
`compileKotlin` → `dex` → `package` on **every** build, and — with `org.gradle.caching=true`
([gradle.properties:9](android/gradle.properties#L9)) — filling the build cache with single-use entries. Local
`flutter run` cycles get slower. Additionally, **if `org.gradle.configuration-cache` is ever enabled**, the timestamp
would be frozen into the CC entry and silently go stale; `GIT_COMMIT_DATE` is also surfaced as a reproducible
cross-check for exactly that reason.

### No lockfile regeneration required
STRICT dependency locking is on. `buildFeatures.buildConfig`, `providers.exec` and `providers.environmentVariable` add
no resolved dependencies, so `android/app/gradle.lockfile`, `android/gradle.lockfile` and
`android/buildscript-gradle.lockfile` stay untouched. **This is why the Kotlin side must not use
`androidx.core`/`PackageInfoCompat`** even though `androidx.core:core:1.13.1` is present transitively — declaring it
would force `--write-locks` and three regenerated lockfiles.

---

## 2. Android: runtime metadata + MethodChannel

**File: [MainActivity.kt](android/app/src/main/kotlin/com/exponentiallydigital/pia_wireguard_cfga/MainActivity.kt)** —
currently 15 lines that only set `FLAG_SECURE`. Keep `onCreate` exactly as is; add:

- `override fun configureFlutterEngine(flutterEngine: FlutterEngine)` that calls
  **`super.configureFlutterEngine(flutterEngine)` FIRST** — that is where the generated plugin registrant runs;
  omitting it silently breaks `path_provider`, `share_plus`, `url_launcher` and `package_info_plus`.
  Then registers `MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.exponentiallydigital.pia_wireguard_cfga/build_info")`
  handling `"getBuildInfo"` → `result.success(collectBuildInfo())`, else `result.notImplemented()`.
- `override fun cleanUpFlutterEngine(...)` setting the handler to `null` so the engine does not retain the Activity.
- `private fun collectBuildInfo(): Map<String, String>` — **all values String** so the channel hands Dart a plain
  `Map<String, String>` with no mixed-type codec surprises. Keys: `versionName`, `buildNumber`, `installer`,
  `buildTimestamp`, `buildType`, `commitHash`, `commitDate`, `gitBranch`, `runnerId`, `cpuAbi`, `osVersion`,
  `compileSdk`, `kotlinVersion`.
- Helpers, each with the deprecation suppression scoped to the one-line function rather than blanketing callers:
  - `ownPackageInfo()` — `PackageManager.PackageInfoFlags.of(0L)` on API 33+, legacy `getPackageInfo(name, 0)` below.
    Catch `NameNotFoundException` and fall through to `"unknown"` rather than crashing the screen.
  - `longVersionCodeOf(info)` — `longVersionCode` on API 28+, `versionCode.toLong()` below (minSdk is 24).
  - `installerLabel()` — `getInstallSourceInfo(packageName).installingPackageName` on API 30+, else
    `getInstallerPackageName(packageName)`. Call `getInstallSourceInfo` **inline** in the `SDK_INT >= R` branch; an
    unannotated helper would trip lint's `NewApi` and annotating it would drag in `androidx.annotation`.
    Map known packages to friendly labels (`com.android.vending` → "Google Play", `com.android.shell` → "adb / shell",
    `org.fdroid.fdroid` → "F-Droid", the system package installers, …); fall back to the raw package name for anything
    unrecognised, and `"Sideloaded (no install source)"` for null/blank (the normal local-debug case).
  - `osVersionLabel()` → `"Android $release (API ${Build.VERSION.SDK_INT})"`, using `RELEASE_OR_CODENAME` on API 30+
    (plain `RELEASE` returns the useless `"REL"` on preview builds).
  - `cpuAbi` → `Build.SUPPORTED_ABIS?.firstOrNull() ?: "unknown"` — the *device's* preferred ABI, which is the right
    semantic since `flutter build apk` ships a universal APK.

No `BuildConfig` import needed: `namespace` equals the MainActivity package.
No new ProGuard rules needed — [proguard-rules.pro:7](android/app/proguard-rules.pro#L7) already keeps
`com.exponentiallydigital.pia_wireguard_cfga.**`, and `BuildConfig` String constants are inlined into callers' constant
pools by the compiler anyway.

**Note:** Flutter adds a third build type, `profile`, so `BUILD_TYPE` can be `debug` / `profile` / `release`.

---

## 3. Dart: metadata service

**New file: `lib/build_info_service.dart`** (services live at `lib/` root — cf. [pia_service.dart](lib/pia_service.dart),
[router_slot_service.dart](lib/router_slot_service.dart)). Include the standard GPL header comment block used by every
other file in the repo.

- `const MethodChannel buildInfoChannel = MethodChannel('com.exponentiallydigital.pia_wireguard_cfga/build_info');`
- Immutable `class BuildInfo` with the 13 String fields, a `BuildInfo.fromMap(Map<String, String>)` that defaults each
  missing key to `'unknown'`, and a `BuildInfo.unknown()` const fallback.
- `Future<BuildInfo> loadBuildInfo({MethodChannel channel = buildInfoChannel})` calling
  `channel.invokeMapMethod<String, String>('getBuildInfo')`, wrapped in `try/catch` on **both**
  `MissingPluginException` and `PlatformException` → `BuildInfo.unknown()`.
  **This catch is what keeps `flutter test --coverage` green** — the channel has no implementation under the test
  binding, and it also makes the code safe on any non-Android host.

**New file: `lib/license_text.dart`** — `const String kLicenseText = r'''…''';` holding [LICENSE](LICENSE) verbatim
(674 lines, ~36 KB). Verified: the file contains no `'''` sequence, and a raw string neutralises its `$` and `\`
characters. Per the spec this is embedded at development time — **not** loaded at runtime and **not** registered as an
asset in `pubspec.yaml`. Kept in its own file so `about_screen.dart` stays readable.

---

## 4. Dart: navigation

**[lib/session_controller.dart:31-40](lib/session_controller.dart#L31-L40)** — add `about('about', 'About')` as the
last `AppDestination` value.

**[lib/widgets/app_drawer.dart](lib/widgets/app_drawer.dart)** — add `case AppDestination.about: return const AboutScreen();`
to `screenForDestination` (line 32, exhaustive switch — it will not compile until this is added), import the new screen,
and append `AppDestination.about` to `_destinations` (line 93) after `AppDestination.log`.

That is the whole drawer change: the tiles are generated from `_destinations`, so the entry lands directly below
"View app log", automatically gets `key: Key('drawer_about')`, the `kHighlight` selected colour, `RouteSettings(name: 'about')`
for `DestinationObserver`, and no-op-on-current behaviour — all for free.

**No change to [main_menu_screen.dart](lib/screens/main_menu_screen.dart)**: its buttons are enumerated explicitly, so
adding an enum value does not add a main-menu button. The user asked for the drawer only.

---

## 5. Dart: the About screen

**New file: `lib/screens/about_screen.dart`** — a `StatefulWidget` (not `StatelessWidget`) so the `Future<BuildInfo>` is
created once in `initState` and stored, rather than re-invoking the channel on every rebuild. Do not copy the inline
`future: PackageInfo.fromPlatform()` pattern at [app_scaffold.dart:125](lib/widgets/app_scaffold.dart#L125).

Wrap the body in `AppScaffold(child: …)` exactly as [log_screen.dart:28](lib/screens/log_screen.dart#L28) does. That
already supplies the `kBg` background, `EdgeInsets.all(20)` padding, the `SingleChildScrollView`, and the bottom
`HOME` button; the `kSurface` header bar comes from the global `AppChrome`. **No new Scaffold or AppBar** — this app has
exactly one Scaffold, rendered above the Navigator.

Content is a `Column(crossAxisAlignment: CrossAxisAlignment.stretch)` in three blocks separated by
`SizedBox(height: 20)`, all `fontFamily: 'monospace'` (the theme default) to match the log screen:

1. **Metadata**, one line each, driven by the `FutureBuilder`:
   ```
   cfg-pia-wg v<versionName> build <buildNumber>
   Built by: <installer> at <buildTimestamp>
   Build type: <buildType>
   Commit hash: <commitHash>
   Git branch/tag: <gitBranch>
   Build runner ID: <runnerId>
   CPU Architecture (ABI): <cpuAbi>
   Target Android version: <osVersion>
   Compile SDK: <compileSdk>
   Kotlin: <kotlinVersion>
   ```
   Rendered as `Text.rich` per line: label span `kText` + `FontWeight.w600`, value span `kText` normal weight, so long
   values wrap instead of being clipped by a fixed label column. The spec fixes labels as white and reserves colour for
   links, so values stay white too. Title line at `fontSize: 14`, the rest at `12`. While the future is pending, show
   the same rows with `'…'` values so the layout does not jump.

2. **Links**, each a `Text.rich` of `label: ` (`kText`, w600) + the URL as a tappable span
   (`kHighlight`, `TextDecoration.underline`) carrying a `TapGestureRecognizer` created in `initState` and disposed in
   `dispose`. A `TapGestureRecognizer` span — rather than an `InkWell` around a whole row — is what lets a long
   GitHub URL wrap mid-paragraph on a 360dp phone while keeping the tap target on the URL itself.
   Reuse the established launch pattern from [app_scaffold.dart:70-75](lib/widgets/app_scaffold.dart#L70-L75)
   (`Uri.parse` → `canLaunchUrl` guard → `launchUrl(url, mode: LaunchMode.platformDefault)`, silent no-op on failure).
   `url_launcher: ^6.3.2` is already a direct dependency — **no pubspec change**.

   | Label | URL |
   |---|---|
   | GitHub source code repository: | `https://github.com/ExponentiallyDigital/cfg-pia-wg` |
   | ReadMe: | `…/blob/main/README.md` |
   | Change log: | `…/blob/main/CHANGELOG.md` |
   | Architecture: | `…/blob/main/ARCHITECTURE.md` |
   | Security policy: | `…/blob/main/SECURITY.md` *(corrected)* |
   | Privacy policy: | `https://www.exponentiallydigital.com/cfg-pia-wg/privacy.html` |

3. **LICENCE** — a single `Text(kLicenseText, style: TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace', height: 1.4))`.

---

## 6. Tests

`flutter analyze --fatal-infos` and `flutter test --coverage` both gate CI
([quality_and_security.yml](.github/workflows/quality_and_security.yml)), and `release.yml` needs that workflow to pass.

**New file: `test/screens/about_screen_test.dart`**, following the harness conventions in
[test/app_test_harness.dart](test/app_test_harness.dart) and the mock-handler pattern already used in
[test/main_test.dart:69-73](test/main_test.dart#L69-L73)
(`tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(...)` plus an `addTearDown` that nulls it):

- Happy path: mock `getBuildInfo` → a full map with sentinel values; assert each label and value renders and that the
  first line of the GPL text is present.
- Fallback path: mock handler throwing `MissingPluginException`; assert `'unknown'` renders and no exception is thrown.
  This is the single most likely way the feature red-lights CI, so it gets an explicit test.
- Presence/format of all six URLs.

**Edit [test/screens/main_menu_screen_test.dart](test/screens/main_menu_screen_test.dart)** — mirror the existing
`drawer_log` assertions at lines 101-103 for `drawer_about`, confirming the tile exists below "View app log" and
navigates. Register the channel mock in that file too, since tapping it now builds `AboutScreen`.

Existing tests assert individual drawer keys, not tile counts, so nothing else needs updating.

---

## 7. Documentation

- **[ARCHITECTURE.md](ARCHITECTURE.md)** — document the `…/build_info` MethodChannel (the project's first platform
  channel) and the new `BuildConfig` fields with their provenance and fallbacks.
- **[CHANGELOG.md:46](CHANGELOG.md#L46)** — expand the existing `- ADD: "About" menu option to the hamburger menu.`
  line with the detail level used elsewhere in the file: the BuildConfig injection, the MethodChannel, the embedded
  licence, and the accepted incremental-build cost of the exact timestamp.

---

## Verification

1. **BuildConfig lands correctly** (fastest check, no full build):
   ```
   .\android\gradlew -p android :app:generateDebugBuildConfig
   ```
   then read `build\app\generated\source\buildConfig\debug\com\exponentiallydigital\pia_wireguard_cfga\BuildConfig.java`
   — note the **relocated** path (`<repo>\build`, not `android\app\build`). Confirm all seven custom fields plus
   AGP's `BUILD_TYPE`/`VERSION_NAME`/`VERSION_CODE` are present and correctly quoted.
2. **Graceful degradation:** temporarily rename `.git` (or run the same task with `git` off `PATH`) and confirm the
   build still succeeds with `"unknown"` values rather than failing.
3. `flutter analyze --fatal-infos` — must be clean.
4. `flutter test` — full suite, confirming no regression in the drawer/navigation tests.
5. `flutter run` on a device: hamburger → **About**. Verify every field is populated (not `unknown`), that
   `Build type: debug` and `Built by: Sideloaded (no install source)` for a local run, that the whole screen scrolls
   through the full GPL text, and **tap all six links** to confirm each opens in the system browser and resolves
   (particularly the corrected SECURITY.md URL).
6. `flutter build apk --release` then install and reopen About — confirms R8/resource-shrinking has not stripped
   anything and that `Build type: release` is reported.
7. If a tagged CI build is run, confirm `Git branch/tag` shows the tag (not `HEAD`) and `Build runner ID` shows the
   numeric `GITHUB_RUN_ID`.
