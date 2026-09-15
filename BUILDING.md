# BUILDING.md

- [1. Prerequisites](#1-prerequisites)
- [2. Building](#2-building)
  - [2.1. Clean and install dependencies](#21-clean-and-install-dependencies)
    - [2.1.1. Generate assets (launcher icons)](#211-generate-assets-launcher-icons)
    - [2.1.2. Test and run](#212-test-and-run)
    - [2.1.3. App signing \& keystore configuration](#213-app-signing--keystore-configuration)
    - [2.1.4. Local developer set up (One-time)](#214-local-developer-set-up-one-time)
    - [2.1.5. CI/CD environment setup (GitHub Actions)](#215-cicd-environment-setup-github-actions)
    - [2.1.6. Build release APK](#216-build-release-apk)
    - [2.1.7. Local output destinations](#217-local-output-destinations)
    - [2.1.8. Sideload](#218-sideload)
    - [2.1.9. Release: merge, then tag](#219-release-merge-then-tag)
- [3. Package dependencies](#3-package-dependencies)
- [4. Dependency pinning \& reproducible builds](#4-dependency-pinning--reproducible-builds)
  - [4.1. Why this matters](#41-why-this-matters)
    - [4.1.1. The strict mode safeguard](#411-the-strict-mode-safeguard)
    - [4.1.2. When to regenerate lockfiles](#412-when-to-regenerate-lockfiles)
    - [4.1.3. How to regenerate lockfiles](#413-how-to-regenerate-lockfiles)
- [5. Updating GitHub action SHAs](#5-updating-github-action-shas)
  - [5.1. Example transformation](#51-example-transformation)
    - [5.1.1. Why this is a best practice](#511-why-this-is-a-best-practice)
  - [5.2. Reading the output](#52-reading-the-output)
- [6. Build chain \& utility notes](#6-build-chain--utility-notes)

The scripts `build.ps1` / `build.sh` in the `./scripts` folder automate a local build or if you prefer to compile and test the application locally, follow the below steps.

## 1. Prerequisites

- **Flutter SDK:** version 3.10 or later ([Flutter installation guide](https://flutter.dev/docs/get-started/install))
- **Android SDK / Studio:** [download Android Studio](https://developer.android.com/studio) and configure with Java Development Kit (JDK 17), also install Android SDK Command-line Tools and check your config with `flutter doctor`
- A connected physical Android device (with USB Debugging enabled) or an active Android Virtual Device (AVD) Emulator.

## 2. Building

A shell script `build-optimisation` is included in the ./scripts folder, this can be used to set up the build environment for 8, 16, 32, 64 GB RAM configuations. It could significantly speed up building/debugging runs.

> [!CAUTION]
> Please fully understand what the script does **before** use, as it makes fundamental changes to your build environment!

### 2.1. Clean and install dependencies

Clean the build environment and pull the tracking package constraints defined within the project manifests:

```bash
flutter clean
flutter pub get --enforce-lockfile
```

#### 2.1.1. Generate assets (launcher icons)

The app leverages the `flutter_launcher_icons` framework to generate adaptive foreground and background configurations for Android launchers. Before your initial compilation, generate the native resource files:

```bash
dart run flutter_launcher_icons
```

#### 2.1.2. Test and run

The command `fcr` belongs to the `flutter_coverage_report` package. It is a fantastic pure-Dart tool that takes your dense, ugly lcov.info file and parses it into a sleek, interactive HTML webpage right in your browser. Install via

```bash
dart pub global activate flutter_coverage_report
```

Execute tests and run a hot-reloaded debug instance directly onto your attached mobile/emulated device:

```bash
flutter analyze
flutter test --coverage
fcr coverage/lcov.info --open ## creates & opens ./coverage/coverage-report.html
flutter run -d <device_id>    ## get your device ID via "flutter devices"
```

You may need to install the Android emulator for `flutter run` to execute

```bash
sudo apt install google-android-emulator-installer
emulator -list-avds       ## show emulated devices
emulator -avd Pixel_7_Pro ## replace Pixel_7_Pro with your device name
flutter devices           ## check it is installed
```

#### 2.1.3. App signing & keystore configuration

To ensure that both local release builds and GitHub Actions CI builds produce matching digital signatures, this project uses a unified keystore strategy. This allows Android devices to accept over-the-top APK installations (sideloading updates) without requiring a manual uninstall first.

> [!CAUTION]
> Android strictly enforces that every APK update must be signed by the exact same certificate as the installed version. Mixing a debug-signed local APK with a release-signed CI APK (or vice versa) results in an `INSTALL_FAILED_UPDATE_INCOMPATIBLE` rejection.

#### 2.1.4. Local developer set up (One-time)

1. **Generate the keystore:** execute the following command to generate a 2048-bit RSA key pair valid for 10,000 days:

   ```bash
   keytool -genkey -v -keystore release.jks -alias pia-wireguard \
       -keyalg RSA -keysize 2048 -validity 10000
   ```

2. Secure the keystore file: move release.jks completely OUTSIDE of the repository folder (e.g., place it securely in your user home directory: ~/.android/). Never commit a .jks file to source control.

3. Configure local environment credentials: create a local configuration file named android/key.properties (this file is already safely ignored by .gitignore) and provide the exact absolute path and passwords:

   ```ini
   storeFile=/Users/YOUR_USERNAME/.android/release.jks
   storePassword=YOUR_STORE_PASSWORD
   keyAlias=pia-wireguard
   keyPassword=YOUR_KEY_PASSWORD
   ```

#### 2.1.5. CI/CD environment setup (GitHub Actions)

The `release.yml` workflow is designed to dynamically assemble this footprint before compilation so developers and automation stay perfectly in sync:

1. **Base64 encode the keystore**: to inject the binary keystore into GitHub without committing it, encode it to a clean text blob and copy it to your clipboard:
   - **macOS**: `base64 -i release.jks | pbcopy`
   - **Linux**: `base64 -w 0 release.jks`
   - **Windows (PowerShell)**: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks")) | Set-Clipboard`

2. Add repository secrets: in your GitHub Repository, navigate to Settings > Secrets and variables > Actions and create four secrets using the values you created above:
   - KEYSTORE_BASE64 (The string blob copied from the base64 command)
   - KEYSTORE_PASSWORD
   - KEY_ALIAS
   - KEY_PASSWORD

The pipeline will decode the base64 asset and provision a temporary `key.properties` dynamically before executing `flutter build apk --release`.

#### 2.1.6. Build release APK

Once your local `android/key.properties` or GitHub Repository Secrets are mapped out (see header comments in `android\app\build.gradle.kts`), create a stand-alone production compilation targeted for distribution:

```bash
flutter build apk --release
```

#### 2.1.7. Local output destinations

- Standard Flutter pipeline archive: build/app/outputs/flutter-apk/app-release.apk
- Gradle pipeline build output: build/app/outputs/apk/release/cfg-pia-wg-release.apk

#### 2.1.8. Sideload

To push the compiled app to your phone via Android Debug Bridge (ADB):

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

#### 2.1.9. Release: merge, then tag

A release is a version tag pushed to GitHub. The tag starts `release.yml`, which runs the quality and security checks, builds the app bundle, uploads it to the Play internal track, and publishes a GitHub release.

1. Merge `dev` into `main` through a pull request.
2. Read the version in `pubspec.yaml` on `main`, for example `version: 0.8.80+450`. The tag is `v` followed by the part before the `+`: `v0.8.80`. The part after it is the build number, which Play calls the version code.
3. Tag the merge commit and push the tag:

```bash
git checkout main
git pull
grep '^version:' pubspec.yaml
git tag v0.8.80
git push origin v0.8.80
```

The GitHub release notes are every CHANGELOG block newer than the previous tag, so a tag that names the wrong version publishes the wrong notes. The release's first job, **Tag matches pubspec.yaml**, fails within seconds when the tag is not `v` followed by the version in `pubspec.yaml`, before anything is built or uploaded (ID-062). Its error names the right tag. To recover, delete the wrong tag locally and on the remotes, then tag the same commit correctly:

```bash
git tag -d v0.8.78
git push origin :refs/tags/v0.8.78
```

Play accepts each version code once. Once a build's upload has succeeded, a second tag for the same build fails at the upload, so fix that release's tag and notes on GitHub rather than running the release again.

---

## 3. Package dependencies

Direct dependencies only; see `pubspec.lock` for the resolved transitive graph and `THIRD-PARTY-NOTICES.md` for licences.

| Package             | Purpose                                                                             |
| ------------------- | ----------------------------------------------------------------------------------- |
| `dartssh2`          | SSH connection to the router - every slot and watchdog operation runs over it       |
| `http`              | HTTP REST connection pipelines to PIA APIs                                          |
| `in_app_review`     | Opens the app's Play Store listing from the home-screen review link                 |
| `package_info_plus` | Querying app package metadata dynamically from `pubspec.yaml` for version reporting |
| `path_provider`     | Platform directories for saving a generated config                                  |
| `share_plus`        | Share/save config file via Android share sheet                                      |
| `url_launcher`      | Opens external links - help, GitHub issues, donations                               |
| `x25519`            | Ephemeral WireGuard keypair generation                                              |

## 4. Dependency pinning & reproducible builds

Project and build-toolchain dependencies are strictly pinned to mitigate supply-chain vulnerabilities and ensure fully reproducible, deterministic builds across all local environments and CI/CD pipelines.

In `android\app\build.gradle.kts` we utilise Gradle's dependency locking feature enforced in **Strict Mode** (`LockMode.STRICT`). This guarantees that dynamic versions or changing dependencies cannot secretly pull in untested, unreviewed, or malicious updates. The build environment remains identical for every developer, every time.

### 4.1. Why this matters

- **Supply-chain security**: prevents "dependency confusion" or compromised upstream updates from automatically making their way into our builds.
- **Consistency**: eliminates the infamous "it works on my machine" dilemma by freezing the entire dependency graph—including transitive dependencies.
- **Auditability**: changes to dependencies appear clearly in pull request diffs, allowing reviewers to catch unintended upgrades.

#### 4.1.1. The strict mode safeguard

If a dependency version is changed or a new package is added _without_ updating the lockfiles, the local build and CI/CD pipeline will intentionally crash with an error resembling:

> `> Resolved dependency 'androidx.core:core-ktx:1.12.0' which is not configured in the lockfile.`

This is expected and correct behavior designed to block untracked dependency updates from making it into production.

#### 4.1.2. When to regenerate lockfiles

You must regenerate the Gradle lockfiles whenever you:

1. Add a new package or dependency to build.gradle.
2. **Add a Flutter plugin with native Android code** - `flutter pub add` alone is not enough. The plugin drags its own Android dependencies into the Gradle graph, and the build fails until they are locked. Adding `in_app_review` pulled in the Play review library and three Play Services artifacts.
3. Update the version of an existing package. eg via `flutter pub upgrade | flutter pub upgrade --major-versions`.
4. Modify or upgrade build plugins.

#### 4.1.3. How to regenerate lockfiles

From the project root folder, execute the appropriate command for your operating system to update the three lockfiles:

CMD/PS1

```DOS
.\android\gradlew -p android :dependencies :app:dependencies --write-locks
```

Linux

```bash
./android/gradlew -p android :dependencies :app:dependencies --write-locks
```

> [!NOTE]
> After running this command, make sure to commit the updated lockfiles (\*.lockfile) to Git along with your build.gradle changes. If the lockfiles are missing or out of sync, the CI/CD pipeline will fail the build.

## 5. Updating GitHub action SHAs

The `scripts\pin-actions-latest.sh/ps1` scripts automate the process of hardening GitHub Actions by pinning them to secure commit SHAs, then check every pin. `build.ps1` and `build.sh` run them before the tests, and stop the build if a pin does not match its tag.

For each action in `.github/workflows/*.yml` the script finds the highest semver tag through the GitHub API, resolves it to a full commit SHA, and rewrites the line in place. Both are cached for 24 hours in the untracked `.github/pin-cache.json`, and a cached SHA is only reused for the tag it was resolved from. When the API cannot answer (offline, rate limited, or a bad token) the tag and SHA come from `git ls-remote`, which needs no token. Last of all, every pin is checked against the tag named in its comment, again with `git ls-remote`, independently of the API and the cache.

The token comes from `GITHUB_TOKEN`. Options: `-n` / `-DryRun` writes nothing, `-f` / `-ForceRefresh` bypasses the tag cache, `-v` / `-Verbose` shows every API request and git lookup, `-d` / `-WorkflowDir` and `-t` / `-Token` override the defaults. Set `NO_COLOR` to turn off colours.

### 5.1. Example transformation

Before:

```bash
     uses: google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@v1.0.3
```

After:

```bash
     uses: google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@9a498708959aeaef5ef730655706c5a1df1edbc2 # v2.3.8
```

#### 5.1.1. Why this is a best practice

Pinning workflows to a specific commit SHA, rather than a mutable version tag like v1 or latest, is a critical security practice recommended by GitHub for several reasons:

- Defends against supply chain attacks: Git tags are mutable. If a malicious actor compromises a third-party dependency repository, they can move an existing version tag (like v1.0.3) to point to malicious code. Commit SHAs are cryptographically immutable and cannot be spoofed.

- Ensures build reproducibility: pinning guarantees that the exact same code runs during every workflow execution, preventing unexpected breaking changes or hidden updates from disrupting your CI/CD pipeline.

- Maintains readability via automation: while SHAs are great for security, they are terrible for human readability. The script solves this by automatically appending a comment with the human-readable version tag (e.g., # v2.3.8), giving you the best of both worlds: strict security and clear version tracking.

### 5.2. Reading the output

A run prints a header, one line per action (an action used on several lines shows once, as `xN`), then what was written, the check and a summary:

```text
Pin GitHub Actions: 3 workflow files, 27 uses: lines, 14 actions
  token    set (API quota 5000 of 5000 left, resets 09:17)
  cache    .github/pin-cache.json, 14 entries, 24h TTL
  mode     write
  git      tags listed for 14 of 14 actions in 3.8s

  actions/checkout x5                  v7.0.1    ok         tag cache 45m, sha cache
  actions/setup-java x4                v6.0.1    FIXED      dd06d9cba3e5 -> de7274f081f3 (old SHA: v6.0.0)
  google/osv-scanner-action            v2.6.0    FIXED      6e4298ebc4db -> a345acffa64b (old SHA: v2.5.1)
  ...

  written  quality_and_security.yml (7 lines), release.yml (3 lines)
  verify   27 of 27 pins match their tag (git ls-remote)
  result   10 FIXED, 0 UPDATED, 0 PINNED, 17 ok, 0 SKIPPED, 0 UNRESOLVED; 0 API calls; 6.4s
```

| Status | Meaning |
| --- | --- |
| `ok` | Already pinned to the latest tag's commit. The detail says where the tag and SHA came from: `cache`, `API`, `git`, or `stale cache` when nothing else could answer. |
| `UPDATED` | A newer release was pinned. |
| `FIXED` | Same version, but the pinned SHA was not that tag's commit; the detail names the tag the old SHA really was. |
| `PINNED` | A tag or branch reference (`@v4`) was replaced by a SHA. |
| `SKIPPED` | The newest tag is older than the pinned one, so the line is left alone rather than downgraded. |
| `UNRESOLVED` | The tag or SHA could not be looked up; the line is left as it is. |

Exit codes: `0` when every pin matches its tag, `1` when one does not (the check lists each mismatch) or the workflow directory is missing. If GitHub cannot be reached at all, the check reports the pins it could not verify as a warning and exits `0`, so a build without network access still completes.

## 6. Build chain & utility notes

- keep your build environment up to date with:

  ```cmd
  flutter upgrade
  flutter pub upgrade --major-versions
  .\android\gradlew -p android :dependencies :app:dependencies --write-locks
  ```

- To run **OSV-Scanner** locally (scans dependencies against Google's OSV vulnerability database):

  ```bash
  ## 1. Download the latest Linux binary (run from repo root, e.g. under WSL)
  sudo curl -L https://github.com/google/osv-scanner/releases/latest/download/osv-scanner_linux_amd64 \
    -o /usr/local/bin/osv-scanner
  sudo chmod +x /usr/local/bin/osv-scanner

  ## 2. Basic scan (recursively scans all supported lockfiles in the project)
  osv-scanner .

  ## 3. Scan only the Dart/Flutter lockfile
  osv-scanner --lockfile=pubspec.lock

  ## 4. Scan Android Gradle dependencies (expect many!)
  osv-scanner --lockfile=android/app/gradle.lockfile
  ```
