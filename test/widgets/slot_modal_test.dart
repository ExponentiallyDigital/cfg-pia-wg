// test/widgets/slot_modal_test.dart - the parameterised slot modal (manage + watchdog modes).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wireguard/pia_service.dart';
import 'package:cfg_pia_wireguard/router_slot_service.dart';
import 'package:cfg_pia_wireguard/session_controller.dart';
import 'package:cfg_pia_wireguard/widgets/slot_modal.dart';

import '../watchdog_test_utils.dart';

class _FakePia extends PiaService {
  @override
  Future<List<Region>> fetchRegions({void Function(String)? onProgress}) async => const [
        Region(id: 'aus_melbourne', wgServers: [WgServer(ip: '1.2.3.4', cn: 'aus')])
      ];

  @override
  Future<String> generateConfig({
    required String region,
    required String username,
    required String password,
    required String dns,
    void Function(String)? onProgress,
  }) async =>
      '[Interface]\nPrivateKey = p\nAddress = 10.0.0.2/32\nDNS = 1.1.1.1\nMTU = 1420\n\n'
      '[Peer]\nPublicKey = q\nEndpoint = 1.2.3.4:1337\nAllowedIPs = 0.0.0.0/0\n';
}

SessionController _controller() => SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

SlotInfo _slot(int i,
        {String desc = '', bool killSwitch = false, bool enabled = false, bool watchdog = false, bool emailAlerting = false}) =>
    SlotInfo(
        index: i,
        desc: desc,
        killSwitch: killSwitch,
        enabled: enabled,
        watchdogActive: watchdog,
        emailAlerting: emailAlerting);

RouterSlots _slots(Map<int, SlotInfo> override, {int? active, bool merlin = true}) {
  final m = {for (var i = 1; i <= 5; i++) i: _slot(i)};
  override.forEach((k, v) => m[k] = v);
  return RouterSlots(slots: m, activeSlot: active, isMerlin: merlin);
}

Widget _host(RecordingSSHClient ssh, SlotModalMode mode, RouterSlots initial, SessionController c) {
  return SessionScope(
    controller: c,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: ctx,
              builder: (_) => SlotModal(
                mode: mode,
                controller: c,
                connect: () async => ssh,
                initialSlots: initial,
                piaService: _FakePia(),
                slotServiceFactory: (cl) =>
                    RouterSlotService(cl, onLog: c.onLog, verifyPollInterval: Duration.zero, verifyMaxAttempts: 1),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

ElevatedButton _btn(WidgetTester tester, String key) => tester.widget<ElevatedButton>(find.byKey(Key(key)));

void main() {
  group('manage mode', () {
    testWidgets('button enablement follows slot selection and description', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.manage, _slots({1: _slot(1, desc: 'aus_melbourne')}), c));
      await _open(tester);

      // Nothing selected -> everything disabled.
      expect(_btn(tester, 'slot_create').onPressed, isNull);
      expect(_btn(tester, 'slot_enable').onPressed, isNull);

      // Empty slot selected -> only CREATE.
      await tester.tap(find.byKey(const Key('slot_row_2')));
      await tester.pump();
      expect(_btn(tester, 'slot_create').onPressed, isNotNull);
      expect(_btn(tester, 'slot_enable').onPressed, isNull);

      // Configured slot selected -> all enabled.
      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      expect(_btn(tester, 'slot_create').onPressed, isNotNull);
      expect(_btn(tester, 'slot_enable').onPressed, isNotNull);
      expect(_btn(tester, 'slot_edit').onPressed, isNotNull);
      expect(_btn(tester, 'slot_disable').onPressed, isNotNull);
      expect(_btn(tester, 'slot_delete').onPressed, isNotNull);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('DISABLE runs disableSlot', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.manage, _slots({1: _slot(1, desc: 'aus_melbourne')}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_disable')));
      await tester.tap(find.byKey(const Key('slot_disable')));
      await tester.pumpAndSettle();

      expect(ssh.ran('nvram set wgc1_enable=0'), isTrue);
      expect(ssh.ran('service "stop_wgc 1"'), isTrue);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('DELETE asks for confirmation then clears the slot', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.manage, _slots({1: _slot(1, desc: 'aus_melbourne')}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_delete')));
      await tester.tap(find.byKey(const Key('slot_delete')));
      await tester.pumpAndSettle();

      // Confirm dialog.
      await tester.tap(find.widgetWithText(TextButton, 'DELETE'));
      await tester.pumpAndSettle();

      expect(ssh.ran('nvram unset wgc1_desc'), isTrue);
      expect(ssh.ran('nvram commit'), isTrue);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('CREATE on an empty slot picks region, takes creds and writes a disabled config', (tester) async {
      final c = _controller()
        ..piaUsername = 'p1234567'
        ..piaPassword = 'secret';
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.manage, _slots({}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_2')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_create')));
      await tester.tap(find.byKey(const Key('slot_create')));
      await tester.pumpAndSettle();

      // Region picker -> choose region.
      await tester.tap(find.text('aus_melbourne').last);
      await tester.pumpAndSettle();

      // PIA credentials dialog (pre-filled) -> continue.
      await tester.tap(find.widgetWithText(TextButton, 'CONTINUE'));
      await tester.pumpAndSettle();

      expect(ssh.ran('nvram set wgc2_enable=0'), isTrue);
      expect(ssh.ran('nvram set wgc2_desc="aus_melbourne"'), isTrue);
      // Created but not started.
      expect(ssh.ran('start_wgc'), isFalse);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('CREATE on an occupied slot prompts to overwrite (cancel aborts)', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.manage, _slots({1: _slot(1, desc: 'aus_melbourne')}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_create')));
      await tester.tap(find.byKey(const Key('slot_create')));
      await tester.pumpAndSettle();

      expect(find.text('Overwrite wgc1?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'CANCEL'));
      await tester.pumpAndSettle();
      expect(find.text('aus_melbourne'), findsWidgets); // still on the modal, no region picker

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('ENABLE with stored ping targets enables the slot', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('wd_primary_ip')) return '8.8.8.8';
        if (cmd.contains('wd_secondary_ip')) return '1.1.1.1';
        if (cmd.contains('wg show interfaces')) return 'wgc1';
        if (cmd.contains('ping')) return 'OK';
        return '';
      });
      await tester.pumpWidget(_host(ssh, SlotModalMode.manage, _slots({1: _slot(1, desc: 'aus_melbourne')}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_enable')));
      await tester.tap(find.byKey(const Key('slot_enable')));
      await tester.pumpAndSettle();

      expect(ssh.ran('nvram set wgc1_enable=1'), isTrue);
      expect(ssh.ran('ping -I wgc1'), isTrue);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('ENABLE prompts for ping targets when none are stored', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('wg show interfaces')) return 'wgc1';
        if (cmd.contains('ping')) return 'OK';
        return ''; // wd_*_ip empty -> prompt
      });
      await tester.pumpWidget(_host(ssh, SlotModalMode.manage, _slots({1: _slot(1, desc: 'aus_melbourne')}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_enable')));
      await tester.tap(find.byKey(const Key('slot_enable')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('enable_primary_ip')), findsOneWidget); // prompt with defaults
      await tester.tap(find.widgetWithText(TextButton, 'ENABLE'));
      await tester.pumpAndSettle();

      expect(ssh.ran("nvram set wgc1_wd_primary_ip='8.8.8.8'"), isTrue);
      expect(ssh.ran('nvram set wgc1_enable=1'), isTrue);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('EDIT opens the params editor and saves changes', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.manage, _slots({1: _slot(1, desc: 'aus_melbourne')}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_edit')));
      await tester.tap(find.byKey(const Key('slot_edit')));
      await tester.pumpAndSettle();

      expect(find.text('EDIT wgc1'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('slot_addr')), '10.0.0.2/32');
      await tester.enterText(find.byKey(const Key('slot_desc')), 'aus_melbourne');
      await tester.enterText(find.byKey(const Key('slot_ep_addr')), '203.0.113.5');
      await tester.enterText(find.byKey(const Key('slot_ppub')), 'pub==');
      await tester.enterText(find.byKey(const Key('slot_priv')), 'priv==');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_params_save')));
      await tester.tap(find.byKey(const Key('slot_params_save')));
      await tester.pumpAndSettle();

      expect(ssh.ran("nvram set wgc1_addr='10.0.0.2/32'"), isTrue);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('watchdog mode', () {
    testWidgets('button enablement follows watchdog-active state', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(
        ssh,
        SlotModalMode.watchdog,
        _slots({
          1: _slot(1, desc: 'aus_melbourne', watchdog: true),
          2: _slot(2, desc: 'us_east'),
        }),
        c,
      ));
      await _open(tester);

      // Watchdog active slot -> DISABLE + VIEW LOG, not ENABLE.
      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      expect(_btn(tester, 'slot_enable').onPressed, isNull);
      expect(_btn(tester, 'slot_disable').onPressed, isNotNull);
      expect(_btn(tester, 'slot_view_log').onPressed, isNotNull);

      // Watchdog inactive slot -> ENABLE, not DISABLE / VIEW LOG.
      await tester.tap(find.byKey(const Key('slot_row_2')));
      await tester.pump();
      expect(_btn(tester, 'slot_enable').onPressed, isNotNull);
      expect(_btn(tester, 'slot_disable').onPressed, isNull);
      expect(_btn(tester, 'slot_view_log').onPressed, isNull);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('EMAIL ALERTING badge shows next to WATCHDOG ACTIVE when email alerts are enabled', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(
        ssh,
        SlotModalMode.watchdog,
        _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true, emailAlerting: true)}),
        c,
      ));
      await _open(tester);

      expect(find.text('◆ WATCHDOG ACTIVE'), findsOneWidget);
      expect(find.text('✉ EMAIL ALERTING'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('EMAIL ALERTING badge is hidden when email alerts are disabled', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(
        ssh,
        SlotModalMode.watchdog,
        _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true)}),
        c,
      ));
      await _open(tester);

      expect(find.text('◆ WATCHDOG ACTIVE'), findsOneWidget);
      expect(find.text('✉ EMAIL ALERTING'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('DISABLE runs stopWatchdog', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester
          .pumpWidget(_host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true)}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_disable')));
      await tester.tap(find.byKey(const Key('slot_disable')));
      await tester.pumpAndSettle();

      expect(ssh.ran('cru d watchdog_wgc1'), isTrue);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('VIEW ROUTER WATCHDOG LOG fetches and displays the log', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('watchdog_wgc1.log') ? 'LOG-DATA-XYZ' : '');
      await tester
          .pumpWidget(_host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true)}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_view_log')));
      await tester.tap(find.byKey(const Key('slot_view_log')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('watchdog_log_text')), findsOneWidget);
      expect(find.textContaining('LOG-DATA-XYZ'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('EDIT opens the watchdog dialog', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne')}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_edit')));
      await tester.tap(find.byKey(const Key('slot_edit')));
      await tester.pumpAndSettle();

      expect(find.text('WATCHDOG · wgc1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('DELETE confirms then removes the watchdog and clears the slot', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester
          .pumpWidget(_host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true)}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_delete')));
      await tester.tap(find.byKey(const Key('slot_delete')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'DELETE'));
      await tester.pumpAndSettle();

      expect(ssh.ran('cru d watchdog_wgc1'), isTrue);
      expect(ssh.ran('nvram unset wgc1_desc'), isTrue);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('round-2 behaviours', () {
    testWidgets('manage ENABLE is greyed when the slot is already enabled', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.manage, _slots({1: _slot(1, desc: 'aus_melbourne', enabled: true)}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      expect(_btn(tester, 'slot_enable').onPressed, isNull); // already active
      expect(_btn(tester, 'slot_disable').onPressed, isNotNull);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('manage ENABLE disables the previously-active interface (and its watchdog)', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('wd_primary_ip')) return '8.8.8.8';
        if (cmd.contains('wd_secondary_ip')) return '1.1.1.1';
        if (cmd.contains('wg show interfaces')) return 'wgc2';
        if (cmd.contains('ping')) return 'OK';
        return '';
      });
      await tester.pumpWidget(_host(
        ssh,
        SlotModalMode.manage,
        _slots({
          1: _slot(1, desc: 'aus_melbourne', enabled: true, watchdog: true),
          2: _slot(2, desc: 'us_east'),
        }, active: 1),
        c,
      ));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_2')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_enable')));
      await tester.tap(find.byKey(const Key('slot_enable')));
      await tester.pumpAndSettle();

      expect(ssh.ran('cru d watchdog_wgc1'), isTrue); // other slot's watchdog stopped
      expect(ssh.ran('nvram set wgc1_enable=0'), isTrue); // other slot disabled
      expect(ssh.ran('nvram set wgc2_enable=1'), isTrue); // target enabled

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('manage DELETE confirm shows the description', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.manage, _slots({1: _slot(1, desc: 'aus_melbourne')}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_delete')));
      await tester.tap(find.byKey(const Key('slot_delete')));
      await tester.pumpAndSettle();

      expect(find.textContaining('("aus_melbourne")'), findsOneWidget); // desc in the confirm dialog

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('modal HOME returns to the root', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.manage, _slots({1: _slot(1, desc: 'aus_melbourne')}), c));
      await _open(tester);
      expect(find.text('WIREGUARD CONFIGURATION'), findsOneWidget);

      await tester.ensureVisible(find.widgetWithText(TextButton, 'HOME'));
      await tester.tap(find.widgetWithText(TextButton, 'HOME'));
      await tester.pumpAndSettle();

      expect(find.text('WIREGUARD CONFIGURATION'), findsNothing); // modal closed
      expect(find.text('open'), findsOneWidget); // back at the root host

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('watchdog ENABLE and DELETE are greyed for an empty slot', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.watchdog, _slots({}), c)); // all empty
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      expect(_btn(tester, 'slot_enable').onPressed, isNull);
      expect(_btn(tester, 'slot_delete').onPressed, isNull);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('watchdog ENABLE stops any other active watchdog', (tester) async {
      final c = _controller()
        ..piaUsername = 'p1234567'
        ..piaPassword = 'secret';
      final ssh = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('wgc2_wd_primary_ip')) return '8.8.8.8';
        if (cmd.contains('wgc2_wd_secondary_ip')) return '1.1.1.1';
        if (cmd.contains('wgc2_wd_check_interval')) return '5';
        return '';
      });
      await tester.pumpWidget(_host(
        ssh,
        SlotModalMode.watchdog,
        _slots({
          1: _slot(1, desc: 'aus_melbourne', watchdog: true),
          2: _slot(2, desc: 'us_east'),
        }),
        c,
      ));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_2')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_enable')));
      await tester.tap(find.byKey(const Key('slot_enable')));
      await tester.pumpAndSettle();

      expect(ssh.ran('cru d watchdog_wgc1'), isTrue); // other watchdog stopped
      expect(ssh.ran('cru a watchdog_wgc2'), isTrue); // target deployed

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('watchdog DELETE confirm shows the region warning', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester
          .pumpWidget(_host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true)}), c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_delete')));
      await tester.tap(find.byKey(const Key('slot_delete')));
      await tester.pumpAndSettle();

      expect(find.text('This will also delete and disable the underlying region.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}
