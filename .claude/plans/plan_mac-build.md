# Plan: building on the MacBook as well as on Windows (ID-471, ID-473, ID-474)

Where each item stands is its `Now:` line in CHANGELOG.md, not here. This file holds the detail. The three were numbered ID-470, ID-472 and ID-473 on the Mac until build 535 arrived with its own ID-470; renumbered 2026-10-24.

## Log

Moved from the CHANGELOG item, word for word, 2026-10-24, when it was made short:

- ID-471 TST: the tests pass on a Mac as well as on Windows. Found 2026-10-24, Andrew's first build from a MacBook: `scripts/build.ps1` stopped at `flutter test`, 13 of 1983 failing. build.ps1 itself was fine; on Windows the script tests run their shell in WSL, with Linux's tools, and on a Mac they get macOS's own, which differ from GNU and BusyBox.
  - `sed -i`: `scripts/check-claims.sh` edited two files in place with `sed -i`, which BSD sed reads as a backup suffix ("invalid command code f"), so the tampered server list was never tampered with. Both now write a `.new` and `mv` it over, which any sed takes. 5 tests.
  - `echo -n`: the watchdog emptied `/jffs/curllst` with `echo -n >`, and macOS's `/bin/sh` prints a literal `-n`. Now `: >`, as check-claims.sh's `curllst_clear` already did, and the token's length is counted with `printf %s`. BusyBox takes both. 1 test, and the unit test that names the command.
  - `base64 -w0`: the harness's stand-in openssl answered the DoH lookup with GNU's `base64 -w0`, which macOS's base64 refuses, so every encrypted lookup failed. Now `base64 | tr -d '\n'`. 2 tests.
  - Two timing races in the tests: `move_watch_test` restarted the firewall a fixed 1.5 s in, before a Mac's watcher had reached its loop; it now waits for the first sample. The DNS probe's six stand-in seconds, 0.05 s each, ran out under load before the background nslookup had recorded its lookup. A first fix, the stand-in nslookup marking itself in flight, passed the full suite here and then failed in Andrew's next build: traced under load (16 busy processes, 8 cores), the probe's nslookup had not even started when its six sleeps were done, so there was nothing to mark. The stand-in sleep now waits, up to 2 s, while the shell that called it has another child, which exists from the `&` on; only the two nslookups are started that way. Under the same load: 1 failure in 6 runs before, none in 10 after; the full suite took 3:20 both times. 2 tests.
  - The addKey TLS fixtures: Apple's trust code, which Dart uses on macOS and iOS, refuses a server certificate without serverAuth or valid for more than 825 days, whoever signed it (measured 2026-10-24, one certificate per combination). The fixtures had neither and ran 100 years. PIA's own have both (read from montreal422 and montreal434 on port 1337: serverAuth, about 180 days), so the iPhone app's addKey is not affected. Regenerated in PIA's shape, with the commands in `test/pia_tls_fixtures.dart`; they expire 26 January 2029, and a new test fails two months before, seen to fail with its margin pushed past that date. 3 tests.
  - build.ps1's tests on a Mac: on macOS, a pwsh transcript splits a program's output into lines and counts a bare carriage return as the end of one, so each redraw of `flutter test`'s one-line progress became a line of its own, 2000 scrolling past (measured: `one\rtwo\rthree` under a transcript reached the screen as three lines). On macOS the transcript now pauses for the tests, `script` gives flutter the terminal and keeps a copy, and the copy goes into `build.log` with each line as it was last drawn, then the transcript carries on. Windows is unchanged. Checked in a 120-column pseudo-terminal with the block lifted from build.ps1: a passing run redrew in place (31 redraws, 3 new lines), and a failing one put the failure and "Some tests failed" in the log and returned exit 1. Left: Andrew running build.ps1 itself on the Mac.
  - Checked: on the MacBook, `flutter analyze --fatal-infos` clean and `flutter test --coverage` 1983 passed, 1 skipped, 95.7% covered. Left: a run on Windows, through WSL, to confirm nothing there moved.

### 2026-10-24: Java's restricted-method warning on the Mac (ID-473)

- Every Mac build printed the four `WARNING: A restricted method in java.lang.System has been called` lines, from `net.rubygrapefruit.platform.internal.NativeLibraryLoader` in Gradle 9.8.1's `native-platform-0.22-milestone-29.jar`, on Android Studio's Java 25. ID-408 moved to 9.8.1 to stop them and measured none on Windows.
- Measured with `android/gradlew`: `./gradlew --version`, which starts no daemon, printed it, so it is the launcher's JVM, which `org.gradle.jvmargs` doesn't reach. With `GRADLE_OPTS=--enable-native-access=ALL-UNNAMED` on the launcher alone: 0, with a fresh daemon and a reused one. Without: 1.
- Fix: `DEFAULT_JVM_OPTS="--enable-native-access=ALL-UNNAMED"` in `android/gradlew`. Then 0 for `--version`, a fresh daemon and a reused one. CI's Java is 21, which takes the option. `gradlew.bat` unchanged. `test/unit/gradle_wrapper_test.dart` fails if a regenerated wrapper drops it.
- Moved, the same day: `android/gradlew` is Flutter's, and `android/.gitignore` ignores it, so the fix existed on the MacBook only, and the test that read gradlew would have failed on CI, which has no such file. gradlew is back as Flutter made it, and the option is set where the build starts: build.ps1 adds it to `GRADLE_OPTS` on macOS and Linux, build.sh always. Measured: plain gradlew 1 warning; with build.sh's export 0; with build.ps1's line 0. `test/unit/gradle_wrapper_test.dart` now checks both scripts carry it, and failed with build.sh's line taken out. A build not started by either script, such as `flutter run` from VS Code, still prints it.

### 2026-10-24: build.ps1 checks the signing key first (ID-474)

- The Mac's first release build failed at `:app:packageRelease` with `SigningConfig "release" is missing required property "storeFile"`, after the tests and a 6-minute debug build: `android/key.properties` and the keystore are git-ignored and hadn't been copied across.
- build.ps1 now checks, in its environment checks and for release, aab and all only: `android/key.properties` exists, has a `storeFile`, and that file exists, resolved from `android/app` as Gradle's `file()` does, so `../release.jks` is `android/release.jks`.
- Checked with the block lifted from build.ps1: the real setup (all) OK; debug skips the check; no key.properties stops; a storeFile that isn't there stops, naming where it looked, with CRLF line endings; an absolute storeFile OK.
- build.sh has the same check, checked in the same five cases.

### 2026-10-25: ID-473 closed

- Andrew ran `build.ps1 all` on the MacBook: it passed, with no restricted-method warning. ID-471's Mac half is the same run; its Windows run is left.

### 2026-10-25: ID-471 and ID-475 closed

- ID-475 (build.ps1 ipa) was built in build 537: `ipa` mode on a Mac, and `all` there builds the .ipa after the Android ones; elsewhere `ipa` stops at the start and `all` is unchanged. `build/cfg-pia-wg-v0.8.167_build537.ipa`, signed Apple Distribution RL4UB6WKMV, in 163 s. Without `REVENUECAT_IOS_KEY` it warns that every feature is unlocked. `test/unit/build_script_test.dart` holds the rules.
- Andrew pulled build 538 on the Windows desktop and ran `build.ps1 all`: it passed. That is ID-471's Windows half, the WSL tests after the Mac fixes, and ID-475's "Windows unchanged".

