# Plan: iOS home screen widgets, like Android's (ID-438, ID-424, ID-439)

Where each item stands is its `Now:` line in CHANGELOG.md, not here. Android's widget is `.claude/plans/plan_widget-id-376.md` (ID-376).

## Order

Agreed 2026-10-21 (Andrew's go): ID-438 first, since it needs no background refresh; then ID-424, since measuring needs the code that asks iOS for background time; then ID-439, built on what ID-424 measures.

## Known before starting

- Android refreshes on a schedule the app sets. iOS decides when an app gets background time, often only a few times a day, so an iOS widget may show older status than Android's. ID-424 gives the real rate.
- A widget is an extension: a second target with its own bundle ID, sharing the status with the app through an App Group. CI's automatic signing may register both; if it can't, Andrew makes them on the developer site, with steps written out.

## Design, agreed 2026-10-21 (Andrew's go)

- Not a separate app, and no second code base. Dart decides everything, as it does for Android; each platform only draws. iOS draws in SwiftUI, an app extension inside the same app, reading the same `home_widget` keys. ARCHITECTURE 10.5 describes it as built.
- No refresh while the phone is locked, Andrew's choice. The key keeps iOS's default keychain protection, readable only while unlocked. A refresh that finds the phone locked writes nothing, so the last reading stands with no failure shown. Android to match: ID-470 in BACKLOG.
- Until ID-439, the app reads the router as it opens and as it comes back, and a tap on the widget opens the app.

## Log

The CHANGELOG items as they were, 2026-10-21, before they were made short:

- ID-438 ADD: **an iOS home screen widget showing the last status the app read.** After ID-431.
  - **Done when:** it shows each tunnel's state as last read.
- ID-424 TST: **measure how often iOS lets the app refresh in the background, for an iOS widget like Android's (ID-376).** After ID-422.
  - **Done when:** a day's refresh times from an iPhone are recorded.
- ID-439 ADD: **the iOS widget refreshes itself in the background.** After ID-424 and ID-438.
  - **Done when:** it updates with the app closed.

### 2026-10-21: ID-438 built, in build 535

- Dart: `homeWidgetSupported()` is true on iOS; `backgroundRefreshSupported()` stays Android's; `refreshWidgetOnOpen()` runs from `app_shell.dart` at start and on resume; `WidgetKeyStore.readable()` and the `locked` outcome; `pushWidgetStatus` names the app group and redraws by iOS kind too.
- iOS: `ios/CfgPiaWgWidget/` (the SwiftUI, its Info.plist and entitlements), `ios/Runner/Runner.entitlements`, and the target in `project.pbxproj`, embedded before Thin Binary.
- Tests: `test/unit/widget_ios_test.dart` (new); `widget_refresh_test`, `ios_info_plist_test` and `settings_screen_test` updated. Each new test was seen to fail with its code broken: a Swift key renamed, the embed moved after Thin Binary, the lock check taken out. The full suite passed, 1,992 tests.
- Not yet seen: an Xcode build of it (CI), signing with the new bundle ID and app group, and WGT-8 on an iPhone.

### 2026-10-25: ID-424's background refresh, in build 537

- Andrew has two iPhone 11s, so one can be left for a day with the app installed from TestFlight.
- The widget's refresh is now scheduled on iOS too, as a BGAppRefreshTask through workmanager_apple: `com.exponentiallydigital.cfgpiawg.widget-refresh` in Info.plist's `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes` `fetch`, and `WidgetRefresh.register()` in `AppDelegate.didFinishLaunching`, since a scene-based app must register the handler before that returns. The background engine registers the plugins through `setPluginRegistrantCallback`. Android keeps its job name, `cfg-pia-wg-widget-refresh`, under which phones already have it.
- Each scheduled run, not a tap, writes its start time and outcome to `background_refresh.txt` in app support (`lib/background_refresh_log.dart`, newest 500). As the app starts, the LOG screen gets the last 48 hours: a count, then `2026-10-25 03:07 phone locked, nothing read` and so on, ready to share.
- The key stays readable only while the phone is unlocked (Andrew's choice, ID-438), so a run on a locked phone records `locked` and reads nothing. The log counts those too: they are the background time iOS gave.
- The app still refreshes the widget as it opens and comes back on iOS, since background time may come only a few times a day.
- Checked: new tests in `background_refresh_log_test.dart`, `widget_refresh_test.dart` and `ios_info_plist_test.dart`, each seen to fail with its code broken (the registration taken out of AppDelegate, a tap recorded, iOS left without background refresh). `flutter build ios --release --no-codesign` builds; its first try caught an Int passed where workmanager_apple takes an NSNumber.
- ID-439 is mostly this same code; what it still needs is decided by what ID-424 measures, and by the locked phone.

### 2026-10-25: ID-438 closed

- Andrew installed build 537 from TestFlight (v0.8.167, the first tag to upload its own iOS build) on the spare iPhone 11, installed the widget key and put both widgets on the home screen. WGT-8 passed.
- The same phone now runs ID-424: Andrew reads its LOG on 2026-10-26.

### 2026-10-25: ID-424 moved to B11

- D11's measurement was cut short the same day: an earlier `flutter run` from the MacBook, meant for the Pixel, picked D11 over Wi-Fi and installed a debug build over the TestFlight one, which iOS won't launch from the home screen. The run's record went with it. Andrew installed the TestFlight build on B11, his other iPhone 11, to carry the measurement; it needs the widget key and widgets there too.


### 2026-10-26: ID-424's measurement, B11

B11's LOG at 21:54 on 2026-10-26, build 545 from TestFlight, widget key and both widgets in place:

```text
Background refreshes in the last 48 hours: 14
  2026-10-25 14:38 phone locked, nothing read
  2026-10-25 15:45 phone locked, nothing read
  2026-10-26 08:53 read the router
  2026-10-26 09:09 read the router
  2026-10-26 09:25 read the router
  2026-10-26 09:41 read the router
  2026-10-26 09:56 read the router
  2026-10-26 11:52 phone locked, nothing read
  2026-10-26 14:22 phone locked, nothing read
  2026-10-26 14:55 phone locked, nothing read
  2026-10-26 15:54 phone locked, nothing read
  2026-10-26 18:54 phone locked, nothing read
  2026-10-26 19:10 phone locked, nothing read
  2026-10-26 20:03 phone locked, nothing read
```

- 14 runs in about 30 hours, but uneven: none for 17 hours overnight, then five about 16 minutes apart, the shortest interval asked for, while the phone was in use.
- Only those five read the router. The other nine came while the phone was locked, so, by the design agreed for ID-438, they read nothing. Most of the background time iOS gives comes while the phone is locked.
- One phone, one day: a pattern, not a rate to promise.

### 2026-10-26: no refresh while locked kept, and ID-439 closed

- Offered, and declined: keeping the key readable after the first unlock ("after first unlock, this device only"), which would have let the 9 locked runs read the router. Andrew chose A: the key stays readable only while the phone is unlocked.
- ID-439 closed on B11's log: the background refresh already built for ID-424 updated the widget with the app not open, 5 times.

### 2026-10-26: A kept, and ID-470 closed

- Andrew considered B again, then kept A for the iPhone. Nothing was changed for B.
- ID-470 closed as won't do: Android keeps refreshing while locked, so the two platforms differ here by choice.
