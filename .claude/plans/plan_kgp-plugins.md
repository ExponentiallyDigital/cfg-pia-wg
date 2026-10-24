# Plan: plugins that apply the Kotlin Gradle Plugin (ID-414)

Where it stands is ID-414's `Now:` line in BACKLOG.md, not here. This file holds the detail. Logged on the Mac as ID-472 on 2026-10-24, then found to repeat ID-414, raised 2026-10-16; ID-472 was removed on 2026-10-25 and its check is below.

## Log

Moved from the BACKLOG item, word for word, 2026-10-24, when it was made short:

- ID-472 BLD: `home_widget` and `workmanager_android` apply the Kotlin Gradle Plugin, which a future Flutter will refuse to build. Seen 2026-10-24 on every Android build, debug and release, on Flutter 3.47.7: "Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): home_widget, workmanager_android. Future versions of Flutter will fail to build if your app uses plugins that apply KGP." It comes from the plugins, not the machine. The locked versions, home_widget 0.10.0 and workmanager 0.10.10 (workmanager_android 0.10.9), are the latest on 2026-10-24, so there is nothing to upgrade to yet. Flutter's guide for apps: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers
  - Next: at each Flutter or package update (`weekly_updates.yml`), check both plugins' changelogs for Built-in Kotlin support; if neither has an issue open for it, raise one, as the guide asks.
  - DoD: an Android build prints no KGP warning, with both plugins on versions that use Built-in Kotlin and the suite passing.
