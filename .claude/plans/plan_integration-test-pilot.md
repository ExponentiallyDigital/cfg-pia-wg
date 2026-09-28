# Plan: hand tests run by the app itself (ID-257, parked)

The pilot for ID-257, written 2026-09-28 and parked the same day, before it was ever run. It is kept here, outside the build, so it can come back without being rewritten.

## What it does

`integration_test/router_pilot_test.dart` runs the real app on an emulator or phone, against the real router, and checks the screen against the router over an SSH connection of its own. It covers SET-1, SET-2, SET-3, the heart of SET-9 and SET-10, and ROUTER LOG, which it proves by writing its own line on the router and finding it on screen. It changes nothing on the router. The login is passed with `--dart-define` and never stored; without one, every test is skipped.

## Why it is parked

The `integration_test` package is a Flutter plugin with an Android side, and it puts Android test libraries (`androidx.test`, `junit` 4.12, `guava` 28.1) into the app's **debug** build, not only its test configurations. The Gradle lockfile is strict, so `flutter run` and CI's `flutter build apk --debug` both failed until the lockfile changed. Three ways to change it were weighed:

- **Lock the new libraries.** Even a targeted `--update-locks` moved RevenueCat in the debug build, 10.20.0 to 10.22.1, and put `junit` and `guava`, which carry known vulnerabilities, into what the OSV scan covers - what ID-058 kept out.
- **Exempt the debug configurations from locking**, as ID-058 did for the Unified Test Platform. The release build stays locked (its entries did not change), but debug and release would then run different library versions, including the payment library, and debug builds could change without a commit.
- **Park the pilot** until after the release. Chosen by Andrew, 2026-09-28: no change to the build in release week.

When it comes back, choose between the first two, and see ID-058's comment in `android/build.gradle.kts`, which says to revisit that decision if instrumented tests are ever added. Then:

1. Add to `pubspec.yaml` under `dev_dependencies`: `integration_test:` with `sdk: flutter`, and `flutter pub get`.
2. Change the lockfile, or the locking, as decided, and check `flutter run` and `flutter build apk --debug`.
3. Put the file below back at `integration_test/router_pilot_test.dart`, and the run instructions back in TESTING.md's "How to use the run sheet".
4. Run it: `flutter test integration_test/router_pilot_test.dart --dart-define=ROUTER_IP=<router> --dart-define=ROUTER_USER=<ssh user> --dart-define=ROUTER_PASS=<ssh password>`, and judge it against running the same tests by hand.

## The pilot

```dart
// integration_test/router_pilot_test.dart - hand tests run by the app itself, against a real router (ID-257).
//
// A pilot: the SET group's safe tests, the two DNS windows and ROUTER LOG, which need no PIA login
// and change nothing on the router. The test taps through the real app on the emulator or a phone,
// reads the screen, and checks it against the router over an SSH connection of its own.
//
// The router's details come from the command line and are never written to the repo:
//
//   flutter test integration_test/router_pilot_test.dart -d emulator-5554 \
//     --dart-define=ROUTER_IP=192.168.1.1 --dart-define=ROUTER_USER=router-admin \
//     --dart-define=ROUTER_PASS='...'
//
// Without them every test is skipped.
import 'package:cfg_pia_wg/app_shell.dart';
import 'package:cfg_pia_wg/router_slot_service.dart' show openSshClient;
import 'package:cfg_pia_wg/widgets/common_fields.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _ip = String.fromEnvironment('ROUTER_IP');
const _user = String.fromEnvironment('ROUTER_USER');
const _pass = String.fromEnvironment('ROUTER_PASS');
// No router given: skip, rather than fail, so the folder can sit beside a normal `flutter test`.
const _noRouter = _ip == '' || _user == '' || _pass == '';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The test's own view of the router: a separate SSH connection, never the app's.
  Future<String> onRouter(String command) async {
    final SSHClient c = await openSshClient(_ip, _user, _pass);
    try {
      return String.fromCharCodes(await c.run(command)).trim();
    } finally {
      c.close();
    }
  }

  /// Pumps until [finder] finds something, for screens that wait on the router.
  Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 45)}) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for $finder');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Finder shown(String text) => find.textContaining(text, findRichText: true);

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpWidget(const PiaWgApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu_settings')));
    await tester.pumpAndSettle();
  }

  Future<void> tapAction(WidgetTester tester, String key) async {
    final row = find.byKey(Key(key));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Fills in the router login and presses CONTINUE.
  Future<void> logIn(WidgetTester tester, {String pass = _pass}) async {
    await pumpUntil(tester, find.byType(RouterIpField));
    Finder field(Type t) => find.descendant(of: find.byType(t), matching: find.byType(TextField));
    await tester.enterText(field(RouterIpField), _ip);
    await tester.enterText(field(SshUsernameField), _user);
    await tester.enterText(field(SshPasswordField), pass);
    await tester.tap(find.byKey(const Key('about_ssh_continue')));
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('SET', () {
    testWidgets('SET-1 every row is there', (tester) async {
      await openSettings(tester);
      for (final label in [
        'REBOOT ROUTER',
        'FORGET ROUTER IP',
        'REMOVE CACHED PIA CERT',
        'UNINSTALL FEATURES DEPLOYED TO ROUTER',
        'MAX ACTIVE VPNS',
        'ROUTER RESOLVER STATUS',
        'ROUTER DNS ROUTING',
      ]) {
        final row = find.text(label);
        await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
        expect(row, findsOneWidget, reason: label);
      }
    }, skip: _noRouter);

    testWidgets('SET-3 a refused login keeps the dialog open and says so', (tester) async {
      await openSettings(tester);
      await tapAction(tester, 'settings_resolver_status');
      await logIn(tester, pass: '$_pass-wrong');
      await pumpUntil(tester, shown('The router refused that username or password.'));
      expect(find.byType(RouterIpField), findsOneWidget, reason: 'the login stays open');
      await tester.tap(find.byKey(const Key('about_ssh_cancel')));
      await tester.pumpAndSettle();
    }, skip: _noRouter);

    testWidgets('SET-2, SET-9 and SET-10: one login covers both DNS windows, and they match the router',
        (tester) async {
      await openSettings(tester);

      // SET-9: the live check, and the files as the router has them.
      await tapAction(tester, 'settings_resolver_status');
      await logIn(tester);
      await pumpUntil(tester, find.byKey(const Key('resolver_body')));
      await pumpUntil(tester, shown('checked '));
      expect(find.byKey(const Key('resolver_heading')), findsOneWidget);
      expect(shown('dnsmasq'), findsWidgets);
      for (final f in ['/etc/dnsmasq.conf', '/etc/resolv.conf', '/tmp/resolv.dnsmasq', 'Active DNS settings (nvram)']) {
        expect(shown(f), findsWidgets, reason: f);
      }
      final resolv = await onRouter('cat /etc/resolv.conf');
      for (final line in resolv.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty)) {
        expect(shown(line), findsWidgets, reason: '/etc/resolv.conf on the router has "$line"');
      }
      await tester.tap(find.text('HOME'));
      await tester.pumpAndSettle();

      // SET-2: back into SETTINGS, and the second window asks for no second login.
      await tester.tap(find.byKey(const Key('menu_settings')));
      await tester.pumpAndSettle();
      await tapAction(tester, 'settings_dns_routing');
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(RouterIpField), findsNothing, reason: 'one login covers the screen');

      // SET-10: the verdict is one of the three, and the evidence is the router's own rules.
      await pumpUntil(tester, find.byKey(const Key('dns_routing_body')));
      await pumpUntil(tester, shown('read '));
      final verdicts = [
        "Some of the router's own lookups go through a tunnel",
        "Only pinned devices' lookups go through a tunnel.",
        'No lookups go through a tunnel.',
      ];
      expect(verdicts.where((v) => shown(v).evaluate().isNotEmpty), hasLength(1));
      final rules = await onRouter("ip rule show | grep 'iif lo'");
      for (final rule in rules.split('\n').where((l) => l.trim().isNotEmpty)) {
        final body = rule.trim().split(RegExp(r'\s+')).skip(1).join(' ');
        expect(shown(body), findsWidgets, reason: 'EVIDENCE shows "$rule"');
      }
    }, skip: _noRouter);
  });

  group('ROUTER LOG', () {
    testWidgets('a line written on the router just now is in ROUTER LOG', (tester) async {
      final marker = 'cfg-pia-wg pilot ${DateTime.now().millisecondsSinceEpoch}';
      await onRouter('logger "**ID-257 START** $marker"');

      await tester.pumpWidget(const PiaWgApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu_router_log')));
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byType(RouterIpField).evaluate().isNotEmpty) await logIn(tester);
      await pumpUntil(tester, shown(marker));
      expect(find.byKey(const Key('router_log_heading')), findsOneWidget);

      await onRouter('logger "**ID-257 END** $marker"');
    }, skip: _noRouter);
  });
}
```
