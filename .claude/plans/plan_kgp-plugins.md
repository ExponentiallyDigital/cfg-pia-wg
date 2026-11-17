# Plan: plugins that apply the Kotlin Gradle Plugin (ID-414)

Where it stands is ID-414's `Now:` line in BACKLOG.md, not here. This file holds the detail. Logged on the Mac as ID-472 on 2026-10-24, then found to repeat ID-414, raised 2026-10-16; ID-472 was removed on 2026-10-25 and its check is below.

## Log

Moved from the BACKLOG item, word for word, 2026-10-24, when it was made short:

- ID-472 BLD: `home_widget` and `workmanager_android` apply the Kotlin Gradle Plugin, which a future Flutter will refuse to build. Seen 2026-10-24 on every Android build, debug and release, on Flutter 3.47.7: "Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): home_widget, workmanager_android. Future versions of Flutter will fail to build if your app uses plugins that apply KGP." It comes from the plugins, not the machine. The locked versions, home_widget 0.10.0 and workmanager 0.10.10 (workmanager_android 0.10.9), are the latest on 2026-10-24, so there is nothing to upgrade to yet. Flutter's guide for apps: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers
  - Next: at each Flutter or package update (`weekly_updates.yml`), check both plugins' changelogs for Built-in Kotlin support; if neither has an issue open for it, raise one, as the guide asks.
  - DoD: an Android build prints no KGP warning, with both plugins on versions that use Built-in Kotlin and the suite passing.

## 2026-11-17: measured, the warning is a false positive in this build

- `android/gradle.properties` has `android.builtInKotlin=true` and the app applies no KGP of its own. Both plugins guard the line (`home_widget` 0.10.0: `if (!useBuiltInKotlin) { apply plugin: 'kotlin-android' }`; `workmanager_android` 0.10.9: the same, `if (!builtInKotlin)`).
- A Gradle init script run as `gradlew -I kgpcheck.gradle :app:help --offline -q` printed each project's plugins after evaluation: no project, the plugins and `:app` included, has `kotlin-android` or `org.jetbrains.kotlin.android` applied, by either id; only the Kotlin base and metrics plugins are present, which built-in Kotlin brings. The warning printed in the same run.
- Flutter 3.50.0's `detectApplyingKotlinGradlePlugin` adds a plugin to the warning's list when `kgpRegexGroovy` matches its build file text. The regex allows leading whitespace, so a guarded line matches.
- Upstream: home_widget #461 (closed: the guard means KGP isn't applied), #479 (closed unmerged 2026-10-09, would remove the text), workmanager #744 (closed unmerged 2026-10-09, same). No human comments on #479 or #744. No Flutter issue found on the scan ignoring a guard.
- Decision, Andrew, 2026-11-17: option 3, leave it and treat the warning as cosmetic; no issue with Flutter, no forks. ID-414 closed. Options considered: raise the false positive with Flutter (the scan should read the guard, or the warning should be conditional on the resolved plugin state); override the two plugins with patched copies (two forks to maintain, which is the supply-chain cost ID-414 meant to avoid); or leave it and record that it is cosmetic.
