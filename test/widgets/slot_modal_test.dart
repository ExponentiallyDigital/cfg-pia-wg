// test/widgets/slot_modal_test.dart - the parameterised slot modal (manage + watchdog modes).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/pia_service.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/slot_modal.dart';

import '../watchdog_test_utils.dart';

class _FakePia extends PiaService {
  @override
  Future<List<Region>> fetchRegions({void Function(String)? onProgress}) async => const [
        Region(
          id: 'aus_melbourne',
          wgServers: [WgServer(ip: '1.2.3.4', cn: 'aus')],
        ),
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

SlotInfo _slot(
  int i, {
  String desc = '',
  bool killSwitch = false,
  bool enabled = false,
  bool watchdog = false,
  // Settings on the router. A scheduled watchdog always has them; DISABLE leaves them behind
  // without the schedule, which is the state ENABLE acts on.
  bool? watchdogConfigured,
  bool emailAlerting = false,
}) =>
    SlotInfo(
      index: i,
      desc: desc,
      killSwitch: killSwitch,
      enabled: enabled,
      watchdogActive: watchdog,
      watchdogConfigured: watchdogConfigured ?? watchdog,
      emailAlerting: emailAlerting,
    );

// [active] names every slot whose interface is up — more than one may be.
RouterSlots _slots(Map<int, SlotInfo> override, {Set<int> active = const {}, bool merlin = true, int? maxActive}) {
  final m = {for (var i = 1; i <= 5; i++) i: _slot(i)};
  override.forEach((k, v) => m[k] = v);
  return RouterSlots(slots: m, activeSlots: active, isMerlin: merlin, maxActiveSlots: maxActive);
}

Widget _host(RecordingSSHClient ssh, SlotModalMode mode, RouterSlots initial, SessionController c, {int verifyMaxAttempts = 1}) {
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
                slotServiceFactory: (cl) => RouterSlotService(cl,
                    onLog: c.onLog, verifyPollInterval: Duration.zero, verifyMaxAttempts: verifyMaxAttempts),
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

      // Configured but stopped -> everything except DISABLE, which has nothing to stop.
      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      expect(_btn(tester, 'slot_create').onPressed, isNotNull);
      expect(_btn(tester, 'slot_enable').onPressed, isNotNull);
      expect(_btn(tester, 'slot_edit').onPressed, isNotNull);
      expect(_btn(tester, 'slot_disable').onPressed, isNull);
      expect(_btn(tester, 'slot_delete').onPressed, isNotNull);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('DISABLE runs disableSlot', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.manage, _slots({1: _slot(1, desc: 'aus_melbourne', enabled: true)}), c));
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
      expect(ssh.ran('nvram set wgc2_desc="pia-aus_melbourne"'), isTrue); // stored with the app prefix
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
      final ssh = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('wd_primary_ip')) return '8.8.8.8';
          if (cmd.contains('wd_secondary_ip')) return '1.1.1.1';
          if (cmd.contains('wg show interfaces')) return 'wgc1';
          if (cmd.contains('ping')) return 'OK';
          return '';
        },
      );
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
      final ssh = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('wg show interfaces')) return 'wgc1';
          if (cmd.contains('ping')) return 'OK';
          return ''; // wd_*_ip empty -> prompt
        },
      );
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

      expect(find.text('EDIT wgc1:aus_melbourne'), findsOneWidget);
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
      await tester.pumpWidget(
        _host(
          ssh,
          SlotModalMode.watchdog,
          _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true), 2: _slot(2, desc: 'us_east')}),
          c,
        ),
      );
      await _open(tester);

      // Watchdog active slot -> CREATE/EDIT + VIEW LOG.
      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      expect(_btn(tester, 'slot_edit').onPressed, isNotNull);
      expect(_btn(tester, 'slot_view_log').onPressed, isNotNull);

      // Watchdog inactive slot -> CREATE/EDIT stays live, VIEW LOG is greyed.
      await tester.tap(find.byKey(const Key('slot_row_2')));
      await tester.pump();
      expect(_btn(tester, 'slot_edit').onPressed, isNotNull);
      expect(_btn(tester, 'slot_view_log').onPressed, isNull);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('EMAIL ALERTING badge shows next to WATCHDOG ACTIVE when email alerts are enabled', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(
        _host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true, emailAlerting: true)}), c),
      );
      await _open(tester);

      expect(find.text('◆ WATCHDOG ACTIVE'), findsOneWidget);
      expect(find.text('✉ EMAIL ALERTING'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('EMAIL ALERTING badge is hidden when email alerts are disabled', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(
        _host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true)}), c),
      );
      await _open(tester);

      expect(find.text('◆ WATCHDOG ACTIVE'), findsOneWidget);
      expect(find.text('✉ EMAIL ALERTING'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    // A watchdog that has been DISABLEd keeps its settings on the router, so the row has to say
    // so - otherwise a paused watchdog is indistinguishable from one that was never configured.
    testWidgets('WATCHDOG PAUSED badge marks a configured watchdog with no schedule', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(
          ssh,
          SlotModalMode.watchdog,
          _slots({
            1: _slot(1, desc: 'aus_melbourne', watchdog: true),
            2: _slot(2, desc: 'aus_perth', watchdog: false, watchdogConfigured: true),
            3: _slot(3, desc: 'aus_sydney'),
          }),
          c));
      await _open(tester);

      expect(find.text('◆ WATCHDOG ACTIVE'), findsOneWidget, reason: 'wgc1 only');
      expect(find.text('⏸ WATCHDOG PAUSED'), findsOneWidget, reason: 'wgc2 only');

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    // /tmp/watchdog_wgcN.log outlives the schedule, and the run that prompted a DISABLE is
    // exactly the one you want to read afterwards.
    testWidgets('VIEW LOG stays available for a paused watchdog', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(
          ssh,
          SlotModalMode.watchdog,
          _slots({
            2: _slot(2, desc: 'aus_perth', watchdog: false, watchdogConfigured: true),
            3: _slot(3, desc: 'aus_sydney'),
          }),
          c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_2')));
      await tester.pump();
      expect(_btn(tester, 'slot_view_log').onPressed, isNotNull);

      // A slot that never had a watchdog has no log to show.
      await tester.tap(find.byKey(const Key('slot_row_3')));
      await tester.pump();
      expect(_btn(tester, 'slot_view_log').onPressed, isNull);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('the two watchdog badges are mutually exclusive', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(
        _host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true)}), c),
      );
      await _open(tester);

      // A scheduled watchdog is configured too; it must not carry both badges.
      expect(find.text('◆ WATCHDOG ACTIVE'), findsOneWidget);
      expect(find.text('⏸ WATCHDOG PAUSED'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('an empty slot carries no watchdog badge', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(
        _host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, watchdogConfigured: true)}), c),
      );
      await _open(tester);

      expect(find.text('⏸ WATCHDOG PAUSED'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('VIEW ROUTER WATCHDOG LOG fetches and displays the log', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('watchdog_wgc1.log') ? 'LOG-DATA-XYZ' : '');
      await tester.pumpWidget(
        _host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true)}), c),
      );
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

    testWidgets('COPY button copies the watchdog log text without arming the auto-clear', (tester) async {
      String? copiedText;
      final c = SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (text) async => copiedText = text);
      // Pretend a config was copied first: the countdown it armed must be stood down, not left
      // running over the log the user has just put on the clipboard.
      await c.copyToClipboard('[Interface] secret');
      expect(c.clipboardSeconds, greaterThan(0));
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('watchdog_wgc1.log') ? 'LOG-DATA-XYZ' : '');
      await tester.pumpWidget(
        _host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true)}), c),
      );
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_view_log')));
      await tester.tap(find.byKey(const Key('slot_view_log')));
      await tester.pumpAndSettle();

      expect(find.byType(SelectableText), findsOneWidget);
      await tester.tap(find.byKey(const Key('watchdog_log_copy')));
      await tester.pumpAndSettle();

      expect(copiedText, 'LOG-DATA-XYZ');
      // A watchdog log is not a secret: no countdown, so the conf screen shows none and nothing
      // wipes the clipboard 60 seconds later.
      expect(c.clipboardSeconds, 0);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    // CREATE/EDIT is the only way to bring a watchdog up; ENABLE / DISABLE no longer exist here.

    // The watchdog's ENABLE / DISABLE act on the cron SCHEDULE, not on the tunnel.
    group('schedule enable / disable', () {
      testWidgets('DISABLE is live only for a scheduled watchdog, ENABLE only for a stopped one', (tester) async {
        final c = _controller();
        final ssh = RecordingSSHClient();
        await tester.pumpWidget(_host(
            ssh,
            SlotModalMode.watchdog,
            _slots({
              1: _slot(1, desc: 'aus_melbourne', watchdog: true), // scheduled
              2: _slot(2, desc: 'aus_perth', watchdog: false, watchdogConfigured: true), // disabled
              3: _slot(3, desc: 'aus_sydney'), // never configured
            }),
            c));
        await _open(tester);

        await tester.tap(find.byKey(const Key('slot_row_1')));
        await tester.pump();
        expect(_btn(tester, 'slot_wd_disable').onPressed, isNotNull);
        expect(_btn(tester, 'slot_wd_enable').onPressed, isNull, reason: 'already scheduled');

        await tester.tap(find.byKey(const Key('slot_row_2')));
        await tester.pump();
        expect(_btn(tester, 'slot_wd_enable').onPressed, isNotNull, reason: 'settings kept, schedule gone');
        expect(_btn(tester, 'slot_wd_disable').onPressed, isNull);

        await tester.tap(find.byKey(const Key('slot_row_3')));
        await tester.pump();
        expect(_btn(tester, 'slot_wd_enable').onPressed, isNull, reason: 'nothing configured to re-enable');
        expect(_btn(tester, 'slot_wd_disable').onPressed, isNull);

        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      testWidgets('DISABLE removes the cron entries and keeps the settings, script and tunnel', (tester) async {
        final c = _controller();
        final ssh = RecordingSSHClient();
        await tester
            .pumpWidget(_host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true)}), c));
        await _open(tester);

        await tester.tap(find.byKey(const Key('slot_row_1')));
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('slot_wd_disable')));
        await tester.tap(find.byKey(const Key('slot_wd_disable')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('DISABLE').last); // confirm
        await tester.pumpAndSettle();

        expect(ssh.ran('cru d watchdog_wgc1'), isTrue);
        expect(ssh.ran('cru d watchdog_log_rotate_wgc1'), isTrue);
        expect(ssh.ran('rm -f /jffs/cfg-pia-wg/watchdog_wgc1.sh'), isFalse, reason: 'DELETE does that, not DISABLE');
        expect(ssh.commands.any((cmd) => cmd.contains('nvram unset wgc1_wd_')), isFalse);
        expect(ssh.ran('nvram set wgc1_enable=0'), isFalse, reason: 'the VPN keeps running, unsupervised');

        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      testWidgets('cancelling DISABLE touches nothing', (tester) async {
        final c = _controller();
        final ssh = RecordingSSHClient();
        await tester
            .pumpWidget(_host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true)}), c));
        await _open(tester);

        await tester.tap(find.byKey(const Key('slot_row_1')));
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('slot_wd_disable')));
        await tester.tap(find.byKey(const Key('slot_wd_disable')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('CANCEL'));
        await tester.pumpAndSettle();

        expect(ssh.ran('cru d watchdog_wgc1'), isFalse);

        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      testWidgets('ENABLE puts the schedule back at the stored interval', (tester) async {
        final c = _controller();
        final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('wgc2_wd_check_interval') ? '20' : '');
        await tester.pumpWidget(
            _host(ssh, SlotModalMode.watchdog, _slots({2: _slot(2, desc: 'aus_perth', watchdogConfigured: true)}), c));
        await _open(tester);

        await tester.tap(find.byKey(const Key('slot_row_2')));
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('slot_wd_enable')));
        await tester.tap(find.byKey(const Key('slot_wd_enable')));
        await tester.pumpAndSettle();

        expect(ssh.commands.any((cmd) => cmd.contains('cru a watchdog_wgc2') && cmd.contains('*/20')), isTrue);
        expect(ssh.ran('cru a watchdog_log_rotate_wgc2'), isTrue);

        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });
    });

    // Watchdogs are no longer mutually exclusive, but deploying one brings a tunnel up, so the
    // stock cap applies to CREATE/EDIT exactly as it does to MANAGE's ENABLE.
    testWidgets('CREATE/EDIT refuses to exceed the stock VPN limit', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient();
      await tester.pumpWidget(_host(
          ssh,
          SlotModalMode.watchdog,
          _slots({
            1: _slot(1, desc: 'aus_melbourne', enabled: true),
            2: _slot(2, desc: 'aus_perth', enabled: true),
            3: _slot(3, desc: 'aus_sydney'),
          }, active: {
            1,
            2
          }, merlin: false, maxActive: 2),
          c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_3')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_edit')));
      await tester.tap(find.byKey(const Key('slot_edit')));
      await tester.pumpAndSettle();

      expect(find.text('VPN limit reached'), findsOneWidget);
      expect(find.text('WATCHDOG - wgc3'), findsNothing, reason: 'the dialog is not worth filling in');

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('a second watchdog is allowed while one is already running', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
      await tester.pumpWidget(_host(
          ssh,
          SlotModalMode.watchdog,
          _slots({
            1: _slot(1, desc: 'aus_melbourne', enabled: true, watchdog: true),
            2: _slot(2, desc: 'aus_perth'),
          }, active: {
            1
          }, merlin: false, maxActive: 2),
          c));
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_2')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_edit')));
      await tester.tap(find.byKey(const Key('slot_edit')));
      await tester.pumpAndSettle();

      expect(find.text('VPN limit reached'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('CREATE/EDIT opens the watchdog dialog', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (cmd) => cmd.contains('which jq') ? '/opt/bin/jq' : '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne')}), c));
      await _open(tester);

      expect(find.text('CREATE/EDIT'), findsOneWidget);
      expect(find.text('EDIT'), findsNothing);
      // The MANAGE enable/disable buttons are not here; the watchdog has its own pair, which act
      // on the schedule rather than the tunnel.
      expect(find.byKey(const Key('slot_enable')), findsNothing);
      expect(find.byKey(const Key('slot_disable')), findsNothing);
      expect(find.byKey(const Key('slot_wd_enable')), findsOneWidget);
      expect(find.byKey(const Key('slot_wd_disable')), findsOneWidget);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_edit')));
      await tester.tap(find.byKey(const Key('slot_edit')));
      await tester.pumpAndSettle();

      expect(find.text('WATCHDOG · wgc1:aus_melbourne'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('DELETE confirms then removes the watchdog and clears the slot', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(
        _host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true)}), c),
      );
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

  // Regression: the badge came from RegExp.firstMatch over `wg show interfaces`, so only one slot
  // could ever be marked ACTIVE however many tunnels were actually up.
  group('ACTIVE badge', () {
    testWidgets('every slot whose interface is up is badged', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(
        _host(
          ssh,
          SlotModalMode.manage,
          _slots(
            {1: _slot(1, desc: 'aus_melbourne', enabled: true), 3: _slot(3, desc: 'aus_perth', enabled: true)},
            active: {1, 3},
          ),
          c,
        ),
      );
      await _open(tester);

      expect(find.text('● ACTIVE'), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    // Slots run side by side now: enabling one must not disturb another.
    testWidgets('ENABLE leaves a slot whose interface is up alone', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('wg show interfaces')) return 'wgc2';
          if (cmd.contains('ping')) return 'OK';
          if (cmd.contains('wd_primary_ip')) return '8.8.8.8';
          if (cmd.contains('wd_secondary_ip')) return '1.1.1.1';
          return '';
        },
      );
      await tester.pumpWidget(
        _host(
          ssh,
          SlotModalMode.manage,
          // wgc5 reports enabled:false yet its interface is up.
          _slots(
            {5: _slot(5, desc: 'aus_perth'), 2: _slot(2, desc: 'us_east')},
            active: {5},
          ),
          c,
        ),
      );
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_2')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_enable')));
      await tester.tap(find.byKey(const Key('slot_enable')));
      await tester.pumpAndSettle();

      expect(ssh.ran('nvram set wgc2_enable=1'), isTrue); // target enabled
      expect(ssh.ran('nvram set wgc5_enable=0'), isFalse); // the other tunnel keeps running

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    // Reported: after DISABLE the ACTIVE badge stayed until the modal was reopened, because the
    // refresh read `wg show interfaces` before the router had finished stopping the tunnel.
    testWidgets('the badge clears after DISABLE without reopening the modal', (tester) async {
      final c = _controller();
      var stopped = false;
      var pollsSinceStop = 0;
      final ssh = RecordingSSHClient(
        responder: (cmd) {
          // notify_rc returns immediately; the interface lingers for a moment after that, which is
          // exactly the window the old code refreshed in.
          if (cmd.contains('service') && cmd.contains('stop')) stopped = true;
          if (cmd.contains('wg show interfaces')) {
            if (!stopped) return 'wgc1';
            return pollsSinceStop++ < 2 ? 'wgc1' : '';
          }
          if (cmd.contains('wgc1_desc')) return 'pia-aus_melbourne';
          return '';
        },
      );
      await tester.pumpWidget(
        _host(ssh, SlotModalMode.manage, _slots({1: _slot(1, desc: 'pia-aus_melbourne', enabled: true)}, active: {1}), c,
            verifyMaxAttempts: 5),
      );
      await _open(tester);
      expect(find.text('● ACTIVE'), findsOneWidget);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_disable')));
      await tester.tap(find.byKey(const Key('slot_disable')));
      await tester.pumpAndSettle();

      // Still the same open modal - no reopen.
      expect(find.text('WIREGUARD CONFIGURATION'), findsOneWidget);
      expect(find.text('● ACTIVE'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('no badge when nothing is up, even for a configured slot', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(
        _host(ssh, SlotModalMode.manage, _slots({5: _slot(5, desc: 'aus_perth')}), c),
      );
      await _open(tester);

      expect(find.text('● ACTIVE'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('HOME button', () {
    for (final mode in SlotModalMode.values) {
      testWidgets('is teal, not muted, in ${mode.name} mode', (tester) async {
        final c = _controller();
        addTearDown(c.dispose);
        await tester.pumpWidget(
          _host(RecordingSSHClient(responder: (_) => ''), mode, _slots({1: _slot(1, desc: 'pia-aus')}), c),
        );
        await _open(tester);

        final home = tester.widget<Text>(find.text('HOME'));
        expect(home.style?.color, kHighlight);
        expect(home.style?.color, isNot(kMuted));

        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('DISABLE gating', () {
    Future<ElevatedButton> disableBtn(WidgetTester tester, SlotInfo slot, {Set<int> active = const {}}) async {
      final c = _controller();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        _host(RecordingSSHClient(responder: (_) => ''), SlotModalMode.manage, _slots({1: slot}, active: active), c),
      );
      await _open(tester);
      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      return _btn(tester, 'slot_disable');
    }

    testWidgets('live for an enabled slot', (tester) async {
      final b = await disableBtn(tester, _slot(1, desc: 'pia-aus', enabled: true), active: {1});
      expect(b.onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('greyed once the slot is down', (tester) async {
      final b = await disableBtn(tester, _slot(1, desc: 'pia-aus'));
      expect(b.onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('greyed for an empty slot', (tester) async {
      final b = await disableBtn(tester, _slot(1));
      expect(b.onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    // The flag and the interface can disagree. Gating on the flag alone would strand a user with a
    // running tunnel and no way to stop it.
    testWidgets('live when the interface is up even though the flag reads 0', (tester) async {
      final b = await disableBtn(tester, _slot(1, desc: 'pia-aus'), active: {1});
      expect(b.onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // Slots run concurrently now. Stock caps how many via vpnc_max_conn; Merlin has no cap.
  group('concurrency gate', () {
    RecordingSSHClient enableReady() => RecordingSSHClient(
          responder: (cmd) {
            if (cmd.contains('wd_primary_ip')) return '8.8.8.8';
            if (cmd.contains('wd_secondary_ip')) return '1.1.1.1';
            if (cmd.contains('wg show interfaces')) return 'wgc3';
            if (cmd.contains('ping')) return 'OK';
            return '';
          },
        );

    Future<void> tapEnable(WidgetTester tester, int row) async {
      await tester.tap(find.byKey(Key('slot_row_$row')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_enable')));
      await tester.tap(find.byKey(const Key('slot_enable')));
      await tester.pumpAndSettle();
    }

    testWidgets('a second slot is allowed under the stock cap of 2', (tester) async {
      final c = _controller();
      final ssh = enableReady();
      await tester.pumpWidget(
        _host(ssh, SlotModalMode.manage,
            _slots({1: _slot(1, desc: 'a', enabled: true), 3: _slot(3, desc: 'b')}, active: {1}, maxActive: 2), c),
      );
      await _open(tester);
      await tapEnable(tester, 3);

      expect(find.text('VPN limit reached'), findsNothing);
      expect(ssh.ran('nvram set wgc3_enable=1'), isTrue);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('a third slot is refused with the ASUS-limit dialog and no router write', (tester) async {
      final c = _controller();
      final ssh = enableReady();
      await tester.pumpWidget(
        _host(
            ssh,
            SlotModalMode.manage,
            _slots({1: _slot(1, desc: 'a', enabled: true), 2: _slot(2, desc: 'b', enabled: true), 3: _slot(3, desc: 'c')},
                active: {1, 2}, maxActive: 2),
            c),
      );
      await _open(tester);
      await tapEnable(tester, 3);

      expect(find.text('VPN limit reached'), findsOneWidget);
      expect(find.textContaining('at most 2 WireGuard VPNs'), findsOneWidget);
      expect(find.textContaining('Disable another slot'), findsOneWidget);
      expect(ssh.ran('nvram set wgc3_enable=1'), isFalse); // nothing was written
      expect(ssh.ran('nvram set wgc1_enable=0'), isFalse); // and nothing was torn down
      // Reported: the refusal used to arrive AFTER the ping-target prompt. The gate needs no
      // router round trip, so it comes first - and nothing is read from the router either.
      expect(find.text('Connectivity check targets'), findsNothing);
      expect(ssh.ran('nvram get wgc3_wd_primary_ip'), isFalse);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('the cap follows the router, not a hardcoded 2', (tester) async {
      final c = _controller();
      final ssh = enableReady();
      await tester.pumpWidget(
        _host(ssh, SlotModalMode.manage,
            _slots({1: _slot(1, desc: 'a', enabled: true), 3: _slot(3, desc: 'b')}, active: {1}, maxActive: 1), c),
      );
      await _open(tester);
      await tapEnable(tester, 3);

      expect(find.textContaining('at most 1 WireGuard VPNs'), findsOneWidget);
      expect(ssh.ran('nvram set wgc3_enable=1'), isFalse);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    // Re-enabling a slot that is already up must not count itself against the cap.
    testWidgets('the target slot is excluded from the count', (tester) async {
      final c = _controller();
      final ssh = enableReady();
      await tester.pumpWidget(
        _host(ssh, SlotModalMode.manage, _slots({3: _slot(3, desc: 'b')}, active: {3}, maxActive: 1), c),
      );
      await _open(tester);
      await tapEnable(tester, 3);

      expect(find.text('VPN limit reached'), findsNothing);
      expect(ssh.ran('nvram set wgc3_enable=1'), isTrue);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('Merlin has no cap, so any number may be enabled', (tester) async {
      final c = _controller();
      final ssh = enableReady();
      await tester.pumpWidget(
        _host(
            ssh,
            SlotModalMode.manage,
            // maxActive omitted => null => unlimited, which is what fetchSlots reports on Merlin.
            _slots({1: _slot(1, desc: 'a', enabled: true), 2: _slot(2, desc: 'b', enabled: true), 3: _slot(3, desc: 'c')},
                active: {1, 2}),
            c),
      );
      await _open(tester);
      await tapEnable(tester, 3);

      expect(find.text('VPN limit reached'), findsNothing);
      expect(ssh.ran('nvram set wgc3_enable=1'), isTrue);

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

    testWidgets('manage ENABLE leaves the previously-active interface (and its watchdog) running', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(
        responder: (cmd) {
          if (cmd.contains('wd_primary_ip')) return '8.8.8.8';
          if (cmd.contains('wd_secondary_ip')) return '1.1.1.1';
          if (cmd.contains('wg show interfaces')) return 'wgc2';
          if (cmd.contains('ping')) return 'OK';
          return '';
        },
      );
      await tester.pumpWidget(
        _host(
          ssh,
          SlotModalMode.manage,
          _slots({1: _slot(1, desc: 'aus_melbourne', enabled: true, watchdog: true), 2: _slot(2, desc: 'us_east')}, active: {1}),
          c,
        ),
      );
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_2')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('slot_enable')));
      await tester.tap(find.byKey(const Key('slot_enable')));
      await tester.pumpAndSettle();

      expect(ssh.ran('nvram set wgc2_enable=1'), isTrue); // target enabled
      // Slots now run side by side, so nothing else is torn down.
      expect(ssh.ran('cru d watchdog_wgc1'), isFalse);
      expect(ssh.ran('nvram set wgc1_enable=0'), isFalse);

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

    // CREATE/EDIT must stay live on an empty slot — that is the CREATE half of the action.
    testWidgets('watchdog DELETE is greyed for an empty slot but CREATE/EDIT is not', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(_host(ssh, SlotModalMode.watchdog, _slots({}), c)); // all empty
      await _open(tester);

      await tester.tap(find.byKey(const Key('slot_row_1')));
      await tester.pump();
      expect(_btn(tester, 'slot_delete').onPressed, isNull);
      expect(_btn(tester, 'slot_edit').onPressed, isNotNull);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('watchdog DELETE confirm shows the region warning', (tester) async {
      final c = _controller();
      final ssh = RecordingSSHClient(responder: (_) => '');
      await tester.pumpWidget(
        _host(ssh, SlotModalMode.watchdog, _slots({1: _slot(1, desc: 'aus_melbourne', watchdog: true)}), c),
      );
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
