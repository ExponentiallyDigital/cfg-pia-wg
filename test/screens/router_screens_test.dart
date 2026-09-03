// test/screens/router_screens_test.dart - Manage-router + VPN-watchdog connect screens.
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:cfg_pia_wg/screens/manage_router_screen.dart';
import 'package:cfg_pia_wg/screens/watchdog_management_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';

import '../watchdog_test_utils.dart';

SessionController _controller() => SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

/// A router that reports Merlin and has nothing else configured.
RecordingSSHClient _merlinSsh([String Function(String)? extra]) => RecordingSSHClient(
      responder: (cmd) => cmd.contains('3rd-party') ? 'merlin' : (extra?.call(cmd) ?? ''),
    );

/// Stock reports an empty 3rd-party tag; `[ -x … ]` probes answer 1 when the binary is present.
RecordingSSHClient _stockSsh({bool jq = true, bool mailsend = true, String Function(String)? extra}) => RecordingSSHClient(
      responder: (cmd) {
        if (cmd.contains(kStockJqPath) && cmd.contains('-x')) return jq ? '1' : '0';
        if (cmd.contains(kStockMailsendPath) && cmd.contains('-x')) return mailsend ? '1' : '0';
        return extra?.call(cmd) ?? '';
      },
    );

RouterSlotService _fastSvc(SSHClient c, SessionController ctrl) =>
    RouterSlotService(c, onLog: ctrl.onLog, verifyPollInterval: Duration.zero, verifyMaxAttempts: 1);

Widget _manage(RecordingSSHClient ssh, SessionController c) => SessionScope(
      controller: c,
      child: MaterialApp(
        home: Scaffold(
          body: ManageRouterScreen(testClientFactory: (ip, u, p) async => ssh, slotServiceFactory: (cl) => _fastSvc(cl, c)),
        ),
      ),
    );

Widget _watchdog(RecordingSSHClient ssh, SessionController c) => SessionScope(
      controller: c,
      child: MaterialApp(
        home: Scaffold(
          body: WatchdogManagementScreen(testClientFactory: (ip, u, p) async => ssh, slotServiceFactory: (cl) => _fastSvc(cl, c)),
        ),
      ),
    );

Future<void> _fillCreds(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Router IP'), '192.168.0.254');
  await tester.enterText(find.widgetWithText(TextFormField, 'SSH Username'), 'admin');
  await tester.enterText(find.widgetWithText(TextFormField, 'SSH Password'), 'pw');
  await tester.pump();
}

void main() {
  // Detection caches into a library global; every test must start from "not yet detected".
  setUp(resetRouterFirmware);
  tearDown(resetRouterFirmware);

  testWidgets('CONNECT is disabled until IP + username + password are filled', (tester) async {
    final c = _controller();
    final ssh = RecordingSSHClient(responder: (_) => '');
    await tester.pumpWidget(_manage(ssh, c));
    await tester.pumpAndSettle();

    expect(tester.widget<ElevatedButton>(find.byKey(const Key('connect_router'))).onPressed, isNull);
    await _fillCreds(tester);
    expect(tester.widget<ElevatedButton>(find.byKey(const Key('connect_router'))).onPressed, isNotNull);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('router IP and SSH username default to 192.168.0.254 / admin', (tester) async {
    final c = _controller();
    final ssh = RecordingSSHClient(responder: (_) => '');
    await tester.pumpWidget(_manage(ssh, c));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '192.168.0.254'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'admin'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('auto-reconnects and opens the modal when already connected this session', (tester) async {
    final c = _controller()
      ..routerIp = '192.168.0.254'
      ..sshUsername = 'admin'
      ..sshPassword = 'pw'
      ..routerConnected = true;
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('3rd-party') ? 'merlin' : '');
    await tester.pumpWidget(_manage(ssh, c));
    await tester.pumpAndSettle();

    // No manual CONNECT tap — the modal opens automatically.
    expect(find.text('WIREGUARD CONFIGURATION'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('SSH credentials pre-fill from the shared session', (tester) async {
    final c = _controller()
      ..routerIp = '10.0.0.1'
      ..sshUsername = 'root';
    final ssh = RecordingSSHClient(responder: (_) => '');
    await tester.pumpWidget(_manage(ssh, c));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '10.0.0.1'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'root'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('manage CONNECT opens the slot modal', (tester) async {
    final c = _controller();
    final ssh = RecordingSSHClient(
      responder: (cmd) {
        if (cmd.contains('3rd-party')) return 'merlin';
        if (cmd.contains('wgc1_desc')) return 'aus_melbourne';
        return '';
      },
    );
    await tester.pumpWidget(_manage(ssh, c));
    await tester.pumpAndSettle();

    await _fillCreds(tester);
    await tester.tap(find.byKey(const Key('connect_router')));
    await tester.pumpAndSettle();

    expect(find.text('WIREGUARD CONFIGURATION'), findsOneWidget);
    expect(find.text('aus_melbourne'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('watchdog CONNECT opens the slot modal on Merlin', (tester) async {
    final c = _controller();
    final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('3rd-party') ? 'merlin' : '');
    await tester.pumpWidget(_watchdog(ssh, c));
    await tester.pumpAndSettle();

    await _fillCreds(tester);
    await tester.tap(find.byKey(const Key('connect_router')));
    await tester.pumpAndSettle();

    expect(find.text('WATCHDOG CONFIGURATION'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  group('firmware detection', () {
    testWidgets('an empty 3rd-party tag is stock, and the watchdog screen opens once both binaries exist', (tester) async {
      final c = _controller();
      await tester.pumpWidget(_watchdog(_stockSsh(), c));
      await tester.pumpAndSettle();

      await _fillCreds(tester);
      await tester.tap(find.byKey(const Key('connect_router')));
      await tester.pumpAndSettle();

      expect(routerFirmware, RouterFirmware.stock);
      expect(find.text('WATCHDOG CONFIGURATION'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('an unrecognised firmware is rejected with a tappable README link', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('3rd-party') ? 'tomato' : '');
      await tester.pumpWidget(_watchdog(ssh, c));
      await tester.pumpAndSettle();

      await _fillCreds(tester);
      await tester.tap(find.byKey(const Key('connect_router')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Your firmware type is not supported'), findsOneWidget);
      expect(find.byKey(const Key('firmware_notice_link')), findsOneWidget);
      expect(find.text('WATCHDOG CONFIGURATION'), findsNothing);
      // The flag stays unset so the next navigation re-probes.
      expect(firmwareDetected, isFalse);

      await tester.tap(find.byKey(const Key('firmware_notice_ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('firmware_notice')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('a failed firmware probe surfaces an error and leaves the flag unset', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(throwOn: ['3rd-party']);
      await tester.pumpWidget(_manage(ssh, c));
      await tester.pumpAndSettle();

      await _fillCreds(tester);
      await tester.tap(find.byKey(const Key('connect_router')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unable to determine router firmware type'), findsOneWidget);
      expect(firmwareDetected, isFalse);
      expect(find.text('WIREGUARD CONFIGURATION'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    // Once detected, the flag is authoritative for the rest of the session: a router that would
    // now answer "merlin" must not flip an already-cached stock verdict.
    testWidgets('an already-detected firmware is not re-probed', (tester) async {
      useStock();
      final c = _controller();
      final ssh = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('3rd-party')) return 'merlin';
          if (cmd.contains('-x')) return '1';
          return '';
        },
      );
      await tester.pumpWidget(_manage(ssh, c));
      await tester.pumpAndSettle();

      await _fillCreds(tester);
      await tester.tap(find.byKey(const Key('connect_router')));
      await tester.pumpAndSettle();

      expect(routerFirmware, RouterFirmware.stock);
      expect(ssh.ran(kStockJqPath), isTrue); // took the stock path despite the merlin tag
      expect(ssh.ran('nvram get vpnc_clientlist'), isTrue);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('stock helper binaries', () {
    testWidgets('watchdog mode names both missing binaries and does not open the modal', (tester) async {
      final c = _controller();
      await tester.pumpWidget(_watchdog(_stockSsh(jq: false, mailsend: false), c));
      await tester.pumpAndSettle();

      await _fillCreds(tester);
      await tester.tap(find.byKey(const Key('connect_router')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unable to locate: $kStockJqPath, $kStockMailsendPath'), findsOneWidget);
      expect(find.byKey(const Key('firmware_notice_link')), findsOneWidget);
      expect(find.text('WATCHDOG CONFIGURATION'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('a single missing binary is named on its own', (tester) async {
      final c = _controller();
      await tester.pumpWidget(_watchdog(_stockSsh(mailsend: false), c));
      await tester.pumpAndSettle();

      await _fillCreds(tester);
      await tester.tap(find.byKey(const Key('connect_router')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unable to locate: $kStockMailsendPath'), findsOneWidget);
      expect(find.textContaining(kStockJqPath), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('manage mode ignores a missing mail binary — it never sends email', (tester) async {
      final c = _controller();
      await tester.pumpWidget(_manage(_stockSsh(mailsend: false), c));
      await tester.pumpAndSettle();

      await _fillCreds(tester);
      await tester.tap(find.byKey(const Key('connect_router')));
      await tester.pumpAndSettle();

      expect(find.text('WIREGUARD CONFIGURATION'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('manage mode is still blocked when jq is missing', (tester) async {
      final c = _controller();
      await tester.pumpWidget(_manage(_stockSsh(jq: false), c));
      await tester.pumpAndSettle();

      await _fillCreds(tester);
      await tester.tap(find.byKey(const Key('connect_router')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unable to locate: $kStockJqPath'), findsOneWidget);
      expect(find.text('WIREGUARD CONFIGURATION'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('Merlin is never probed for the stock binaries', (tester) async {
      final c = _controller();
      final ssh = _merlinSsh();
      await tester.pumpWidget(_watchdog(ssh, c));
      await tester.pumpAndSettle();

      await _fillCreds(tester);
      await tester.tap(find.byKey(const Key('connect_router')));
      await tester.pumpAndSettle();

      expect(ssh.ran(kRouterAppDir), isFalse);
      expect(find.text('WATCHDOG CONFIGURATION'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}
