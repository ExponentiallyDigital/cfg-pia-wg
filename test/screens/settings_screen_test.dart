// test/screens/settings_screen_test.dart - the screen that undoes what the app has done.
//
// DEL PIA CERT and FORGET ROUTER IP moved here from ABOUT in 422, and their tests came with them.
// ABOUT is a page people open to read; every button on this one destroys something.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/entitlement.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_prefs.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:cfg_pia_wg/screens/settings_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/ssh_creds_dialog.dart';

import '../watchdog_test_utils.dart';

/// In-memory stand-in for [RouterPrefs]. A widget test body runs under fake async, which drives
/// timers and microtasks but does NOT complete real file I/O - so a store backed by the filesystem
/// leaves the await hanging and the test reports "did not complete" rather than failing usefully.
class _MemoryRouterPrefs extends RouterPrefs {
  String value = '';

  @override
  Future<String> load() async => value;

  @override
  Future<String> remember(String ip) async => value = ip.trim();

  @override
  Future<void> forget() async => value = '';
}

SessionController _quietController() => SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

Future<void> _pumpSettings(WidgetTester tester, {SessionController? controller}) async {
  // Scaffold mirrors production, where AppChrome supplies one above the Navigator; the
  // confirmation snackbars need it.
  final c = controller ?? _quietController();
  if (controller == null) addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(home: SessionScope(controller: c, child: const Scaffold(body: SettingsScreen()))),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Reported from a tablet on 423: DEL PIA CERT, the ABOUT script-version link and the router log
  // all tried to connect to 192.168.50.1 instead of asking for credentials. Opening MANAGE writes
  // the FACTORY DEFAULT address into routerIp before the user types anything, so a test of "are
  // these three fields filled in" says yes for a session that has never reached a router.
  group('asks before acting when no connection has been made', () {
    testWidgets('a filled-in but never-connected session still gets the login prompt', (tester) async {
      final c = SessionController(tickInterval: const Duration(hours: 1))
        ..routerIp = kDefaultRouterIp
        ..sshUsername = 'admin'
        ..sshPassword = 'pw';
      // routerConnected deliberately left false - that is the whole point.
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: SessionScope(
          controller: c,
          child: Scaffold(body: SettingsScreen(testClientFactory: (_, __, ___) async => RecordingSSHClient(responder: (_) => ''))),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();

      expect(find.byType(SshCredsDialog), findsOneWidget);
      expect(c.canReuseRouterSession, isFalse);
    });

    testWidgets('a connected session is not asked again', (tester) async {
      final c = SessionController(tickInterval: const Duration(hours: 1))
        ..routerIp = '192.168.1.1'
        ..sshUsername = 'admin'
        ..sshPassword = 'pw'
        ..routerConnected = true;
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: SessionScope(
          controller: c,
          child: Scaffold(body: SettingsScreen(testClientFactory: (_, __, ___) async => RecordingSSHClient(responder: (_) => ''))),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();

      expect(find.byType(SshCredsDialog), findsNothing);
      expect(find.byKey(const Key('settings_del_cert_confirm')), findsOneWidget);
    });
  });

  // Puts a router back the way the app found it. The one thing it must never do is leave a
  // half-undone router: restore the boot scripts BEFORE removing the directory, so a failure at
  // the last step still leaves a router that boots the way it did originally.
  group('uninstall from router', () {
    Future<RecordingSSHClient> pumpAndConfirm(WidgetTester tester, {required bool backupsExist}) async {
      final ssh = RecordingSSHClient(responder: (cmd) {
        if (!cmd.contains('.old')) return '';
        return backupsExist ? 'RESTORED' : 'REMOVED';
      });
      final c = SessionController(tickInterval: const Duration(hours: 1))
        ..routerIp = '192.168.1.1'
        ..sshUsername = 'admin'
        ..sshPassword = 'pw'
        ..routerConnected = true;
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: SessionScope(
          controller: c,
          child: Scaffold(body: SettingsScreen(testClientFactory: (_, __, ___) async => ssh)),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_uninstall')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_uninstall_confirm')));
      await tester.pumpAndSettle();
      // The second ask. This is the one action in the app that cannot be undone from inside it.
      await tester.tap(find.byKey(const Key('settings_uninstall_really')));
      await tester.pumpAndSettle();
      return ssh;
    }

    testWidgets('restores both boot scripts, then removes the app directory', (tester) async {
      final ssh = await pumpAndConfirm(tester, backupsExist: true);

      final order = ssh.commands.where((c) => c.contains('.old') || c.contains('rm -rf')).toList();
      expect(order.length, 3, reason: 'two scripts and the directory');
      // Cron and NVRAM go too, or an "uninstalled" router keeps firing a schedule at a script that
      // is not there and keeps the app's settings for the next person to wonder about.
      expect(ssh.commands.contains('cru l'), isTrue);
      expect(ssh.commands.any((c) => c.contains('nvram unset cfg_pia_wg_user')), isTrue);
      expect(order[0], contains('S50downloadmaster.old'));
      expect(order[1], contains('S50asuslighttpd.old'));
      expect(order[2], contains('rm -rf'));
      expect(order[2], contains(kRouterAppDir));

      expect(find.textContaining('Restored the original S50downloadmaster'), findsOneWidget);
      expect(find.textContaining('Restored the original S50asuslighttpd'), findsOneWidget);
      // Cron entries are gone but a running watchdog process is not, and the firmware keeps its own
      // idea of what is configured until it restarts.
      expect(find.text('Please restart your router.'), findsOneWidget);
    });

    // A missing .old means the original was gone before the app ever wrote a backup - true for
    // anyone who installed before 419. Removing the app's copy is right; claiming to have restored
    // something is not.
    testWidgets('says so when there was no original to put back', (tester) async {
      await pumpAndConfirm(tester, backupsExist: false);
      expect(find.textContaining('no original was saved to put back'), findsWidgets);
    });

    testWidgets('CANCEL touches nothing', (tester) async {
      final ssh = RecordingSSHClient(responder: (_) => '');
      final c = SessionController(tickInterval: const Duration(hours: 1))
        ..routerIp = '192.168.1.1'
        ..sshUsername = 'admin'
        ..sshPassword = 'pw'
        ..routerConnected = true;
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: SessionScope(
          controller: c,
          child: Scaffold(body: SettingsScreen(testClientFactory: (_, __, ___) async => ssh)),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_uninstall')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_uninstall_cancel')));
      await tester.pumpAndSettle();

      expect(ssh.commands, isEmpty);
    });

    // Tunnels, watchdog settings and cron entries are NOT part of this, and the prompt says so -
    // an uninstall that silently tore down a working VPN would be a much bigger action.
    testWidgets('the prompt says what it does NOT remove', (tester) async {
      final c = SessionController(tickInterval: const Duration(hours: 1));
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: SessionScope(controller: c, child: const Scaffold(body: SettingsScreen())),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_uninstall')));
      await tester.pumpAndSettle();

      expect(find.textContaining('are NOT touched'), findsOneWidget);
      expect(find.textContaining('reconfigure history'), findsOneWidget);
      expect(find.textContaining('web interface'), findsOneWidget);
    });

    // A second ask, because REMOVE on the first dialog is one tap from a screen full of buttons
    // and this is the only action in the app that cannot be undone from inside it.
    testWidgets('a second confirmation stands between REMOVE and the router', (tester) async {
      final ssh = RecordingSSHClient(responder: (_) => '');
      final c = SessionController(tickInterval: const Duration(hours: 1))
        ..routerIp = '192.168.1.1'
        ..sshUsername = 'admin'
        ..sshPassword = 'pw'
        ..routerConnected = true;
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: SessionScope(
          controller: c,
          child: Scaffold(body: SettingsScreen(testClientFactory: (_, __, ___) async => ssh)),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_uninstall')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_uninstall_confirm')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Are you sure?'), findsOneWidget);
      // The one moment in the app where asking for a review is fair: the user is leaving, and why
      // they are leaving is the most useful thing they could tell us.
      expect(find.textContaining('leaving us a review'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings_uninstall_really_cancel')));
      await tester.pumpAndSettle();
      expect(ssh.commands, isEmpty, reason: 'cancelling the second ask touches nothing');
    });
  });

  group('DEL PIA CERT', () {
    Future<void> pumpWithSsh(WidgetTester tester, SessionController c, RecordingSSHClient ssh) async {
      addTearDown(() => c.dispose());
      await tester.pumpWidget(MaterialApp(
        home: SessionScope(
          controller: c,
          child: Scaffold(body: SettingsScreen(testClientFactory: (_, __, ___) async => ssh)),
        ),
      ));
      await tester.pumpAndSettle();
    }

    SessionController connectedController() => SessionController(tickInterval: const Duration(hours: 1))
      ..routerIp = '192.168.1.1'
      ..sshUsername = 'admin'
      ..sshPassword = 'pw'
        ..routerConnected = true;

    // Every action on this screen is a full-width row with a line under it saying what it removes.
    // A bare label leaves the user guessing how much, which is not a guess to invite here.
    testWidgets('each action is a full-width row that explains what it removes', (tester) async {
      await _pumpSettings(tester);

      const keys = ['settings_uninstall', 'settings_del_pia_cert', 'settings_forget_router_ip', 'settings_reboot_router'];
      for (final key in keys) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      // Stacked in that order, and REBOOT last: it is the only one that acts on the whole router
      // rather than on this app's own footprint.
      final tops = [for (final k in keys) tester.getCenter(find.byKey(Key(k))).dy];
      expect(tops, orderedEquals(List.of(tops)..sort()));
      // The two category headings are gone: four rows that each say what they touch do not need
      // sorting into "ROUTER" and "THIS DEVICE".
      expect(find.text('ROUTER'), findsNothing);
      expect(find.text('THIS DEVICE'), findsNothing);
      expect(tester.takeException(), isNull, reason: 'no overflow');
    });

    // RESTORE PURCHASE is the one row here that gives something back rather than taking it away,
    // and it is conditional: a build with no store key cannot sell and so has nothing to restore.
    // Showing it there would offer a recovery that can only ever report "no purchase found".
    testWidgets('RESTORE PURCHASE is absent in a build that cannot sell', (tester) async {
      await _pumpSettings(tester);

      expect(Entitlement.purchasingAvailable, isFalse, reason: 'no --dart-define under flutter test');
      expect(find.byKey(const Key('settings_restore_purchase')), findsNothing);
    });

    // ABOUT is reachable without ever visiting a router screen, so the credentials are asked for
    // here rather than sending the user away to fetch them.
    testWidgets('asks for router credentials inline when the session has none', (tester) async {
      final ssh = RecordingSSHClient(responder: (_) => 'DELETED');
      final c = SessionController(tickInterval: const Duration(hours: 1)); // no ip/user/pass
      await pumpWithSsh(tester, c, ssh);

      await tester.ensureVisible(find.byKey(const Key('settings_del_pia_cert')));
      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();

      expect(find.text('Router SSH details'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Router IP'), '192.168.1.1');
      await tester.enterText(find.widgetWithText(TextFormField, 'SSH Username'), 'admin');
      await tester.enterText(find.widgetWithText(TextFormField, 'SSH Password'), 'pw');
      await tester.tap(find.byKey(const Key('about_ssh_continue')));
      await tester.pumpAndSettle();

      // Straight on to the confirmation, then the delete.
      await tester.tap(find.byKey(const Key('settings_del_cert_confirm')));
      await tester.pumpAndSettle();

      expect(ssh.ran(kPiaCaCertPath), isTrue);
      // Kept in the session, so a router screen opened afterwards is already filled in.
      expect(c.routerIp, '192.168.1.1');
      expect(c.sshUsername, 'admin');
      expect(c.sshPassword, 'pw');
    });

    // Reported from a device: the keyboard covered the credentials form. On a short viewport the
    // form is allowed to scroll - what it must never do is overflow, or leave a field stranded
    // under the keyboard with no way to reach it. (The in-chrome case, where the bug actually
    // showed, is covered by edge_to_edge_test.dart.)
    testWidgets('the credentials form scrolls rather than hiding under the keyboard', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      tester.view.viewInsets = const FakeViewPadding(bottom: 500);
      addTearDown(tester.view.reset);

      final ssh = RecordingSSHClient();
      await pumpWithSsh(tester, SessionController(tickInterval: const Duration(hours: 1)), ssh);

      await tester.ensureVisible(find.byKey(const Key('settings_del_pia_cert')));
      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'no overflow');
      const keyboardTop = 800.0 - 500.0;
      final ip = find.widgetWithText(TextFormField, 'Router IP');
      expect(tester.getRect(ip).height, greaterThan(0), reason: 'the form collapsed');
      expect(tester.getRect(ip).bottom, lessThanOrEqualTo(keyboardTop));

      // Everything below the fold has to be reachable by scrolling.
      await tester.scrollUntilVisible(find.byKey(const Key('about_ssh_continue')), -60, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const Key('about_ssh_continue'))).bottom, lessThanOrEqualTo(keyboardTop));
    });

    // Reported: the form opened empty while the router screens start from the usual defaults.
    testWidgets('starts from the same defaults as the router screens', (tester) async {
      final ssh = RecordingSSHClient();
      await pumpWithSsh(tester, SessionController(tickInterval: const Duration(hours: 1)), ssh);

      await tester.ensureVisible(find.byKey(const Key('settings_del_pia_cert')));
      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, kDefaultRouterIp), findsOneWidget);
      // The username is deliberately NOT prefilled - a password manager will not overwrite a field
      // that already has content, so a default costs a manual clear before every autofill.
      expect(find.widgetWithText(TextFormField, kDefaultSshUsername), findsNothing);
    });

    testWidgets('a session value beats the default', (tester) async {
      final ssh = RecordingSSHClient();
      final c = SessionController(tickInterval: const Duration(hours: 1))
        ..routerIp = '10.0.0.1'
        ..sshUsername = 'root'; // no password, so the form still opens
      await pumpWithSsh(tester, c, ssh);

      await tester.ensureVisible(find.byKey(const Key('settings_del_pia_cert')));
      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, '10.0.0.1'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'root'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, kDefaultRouterIp), findsNothing);
    });

    testWidgets('an incomplete credentials form is refused', (tester) async {
      final ssh = RecordingSSHClient();
      await pumpWithSsh(tester, SessionController(tickInterval: const Duration(hours: 1)), ssh);

      await tester.ensureVisible(find.byKey(const Key('settings_del_pia_cert')));
      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Router IP'), '192.168.1.1');
      await tester.tap(find.byKey(const Key('about_ssh_continue')));
      await tester.pumpAndSettle();

      expect(find.textContaining('are all required'), findsOneWidget);
      expect(ssh.commands, isEmpty);
    });

    testWidgets('cancelling the credentials form touches nothing', (tester) async {
      final ssh = RecordingSSHClient();
      final c = SessionController(tickInterval: const Duration(hours: 1));
      await pumpWithSsh(tester, c, ssh);

      await tester.ensureVisible(find.byKey(const Key('settings_del_pia_cert')));
      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('about_ssh_cancel')));
      await tester.pumpAndSettle();

      expect(ssh.commands, isEmpty);
      expect(c.routerIp, isEmpty);
      expect(find.byKey(const Key('settings_del_cert_confirm')), findsNothing);
    });

    testWidgets('credentials already in the session go straight to the confirmation', (tester) async {
      final ssh = RecordingSSHClient(responder: (_) => 'DELETED');
      await pumpWithSsh(tester, connectedController(), ssh);

      await tester.ensureVisible(find.byKey(const Key('settings_del_pia_cert')));
      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();

      expect(find.text('Router SSH details'), findsNothing);
      expect(find.byKey(const Key('settings_del_cert_confirm')), findsOneWidget);
    });

    testWidgets('CANCEL leaves the router alone', (tester) async {
      final ssh = RecordingSSHClient();
      await pumpWithSsh(tester, connectedController(), ssh);

      await tester.ensureVisible(find.byKey(const Key('settings_del_pia_cert')));
      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_del_cert_cancel')));
      await tester.pumpAndSettle();

      expect(ssh.commands, isEmpty);
    });

    testWidgets('DELETE removes the cert from the app directory and confirms', (tester) async {
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('pia_ca') ? 'DELETED' : '');
      final c = connectedController();
      await pumpWithSsh(tester, c, ssh);

      await tester.ensureVisible(find.byKey(const Key('settings_del_pia_cert')));
      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_del_cert_confirm')));
      await tester.pumpAndSettle();

      expect(ssh.ran(kPiaCaCertPath), isTrue);
      expect(ssh.ran('/jffs/pia_ca.rsa.4096.crt'), isFalse, reason: 'the cert moved into the app directory');
      expect(find.text('Cached PIA certificate deleted.'), findsOneWidget);
      expect(c.log.any((e) => e.message.contains('Deleted cached PIA certificate')), isTrue);
    });

    testWidgets('reports when there was nothing cached', (tester) async {
      final ssh = RecordingSSHClient(responder: (_) => 'ABSENT');
      await pumpWithSsh(tester, connectedController(), ssh);

      await tester.ensureVisible(find.byKey(const Key('settings_del_pia_cert')));
      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_del_cert_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('No cached PIA certificate on the router.'), findsOneWidget);
    });

    testWidgets('a failed SSH round trip is reported, not swallowed', (tester) async {
      final ssh = RecordingSSHClient(throwOn: ['pia_ca']);
      await pumpWithSsh(tester, connectedController(), ssh);

      await tester.ensureVisible(find.byKey(const Key('settings_del_pia_cert')));
      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_del_cert_confirm')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not delete the cached certificate'), findsOneWidget);
    });
  });

  // ── FORGET ROUTER IP ────────────────────────────────────────────────────────────────────────
  //
  // The router address is the only thing the app writes to device storage, so the promise that it
  // can be cleared has to be real. The button is also the only place a user can see that anything
  // IS stored, which is why it is greyed rather than hidden when there is nothing to forget.
  group('FORGET ROUTER IP', () {
    late _MemoryRouterPrefs prefs;

    setUp(() => prefs = _MemoryRouterPrefs());

    SessionController controllerWith() {
      final c = SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {}, routerPrefs: prefs);
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('is greyed out when nothing is stored', (tester) async {
      await _pumpSettings(tester, controller: controllerWith());

      final button = tester.widget<OutlinedButton>(find.byKey(const Key('settings_forget_router_ip')));
      expect(button.onPressed, isNull);
    });

    testWidgets('clears the stored address, and greys itself out once it has', (tester) async {
      final c = controllerWith();
      await c.rememberRouterIp('192.168.1.1');
      await _pumpSettings(tester, controller: c);

      expect(tester.widget<OutlinedButton>(find.byKey(const Key('settings_forget_router_ip'))).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('settings_forget_router_ip')));
      await tester.pumpAndSettle();

      expect(find.text('Remembered router address deleted.'), findsOneWidget);
      expect(c.rememberedRouterIp, '');
      expect(await prefs.load(), '');
      // The form goes back to the shipped default, not to a stale value.
      expect(c.routerIpPrefill, kDefaultRouterIp);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('settings_forget_router_ip'))).onPressed, isNull);
    });

    testWidgets('the inline SSH prompt prefills with the remembered address', (tester) async {
      final c = controllerWith();
      await c.rememberRouterIp('192.168.1.1');
      await _pumpSettings(tester, controller: c);

      // No session credentials, so DEL PIA CERT asks for them - and should not make the user
      // retype an address the app already knows.
      await tester.tap(find.byKey(const Key('settings_del_pia_cert')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '192.168.1.1'), findsOneWidget);
    });
  });

  group('REBOOT ROUTER', () {
    SessionController connected() => SessionController(tickInterval: const Duration(hours: 1))
      ..routerIp = '192.168.1.1'
      ..sshUsername = 'admin'
      ..sshPassword = 'pw'
      ..routerConnected = true;

    Future<void> pump(WidgetTester tester, SessionController c, RecordingSSHClient ssh) async {
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: SessionScope(
          controller: c,
          child: Scaffold(body: SettingsScreen(testClientFactory: (_, __, ___) async => ssh)),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('asks first, and CANCEL sends nothing', (tester) async {
      final ssh = RecordingSSHClient(responder: (_) => '');
      await pump(tester, connected(), ssh);

      await tester.tap(find.byKey(const Key('settings_reboot_router')));
      await tester.pumpAndSettle();
      expect(find.text('Are you sure? This will disconnect all devices including WiFi connections.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings_reboot_cancel')));
      await tester.pumpAndSettle();
      expect(ssh.ran('reboot'), isFalse);
    });

    testWidgets('clears a ghost service marker BEFORE asking the router to reboot', (tester) async {
      // Measured 2026-09-10: a wedged queue discards a reboot request like any other event, and
      // the web interface reported a reboot that never happened. A recovery control that can
      // silently do nothing is worse than no control at all.
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('rc_service') ? 'restart_vpnc@@999@@dead' : '');
      await pump(tester, connected(), ssh);

      await tester.tap(find.byKey(const Key('settings_reboot_router')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_reboot_confirm')));
      await tester.pumpAndSettle();

      final cleared = ssh.commands.indexWhere((c) => c.contains('rc_service='));
      final reboot = ssh.commands.indexOf('reboot');
      expect(cleared, isNot(-1), reason: 'the ghost has to be cleared');
      expect(reboot, isNot(-1), reason: 'and the reboot still has to be sent');
      expect(cleared, lessThan(reboot));
      expect(find.textContaining('Reboot requested'), findsOneWidget);
    });
  });
}
