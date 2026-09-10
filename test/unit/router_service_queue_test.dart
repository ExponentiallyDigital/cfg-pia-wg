// test/unit/router_service_queue_test.dart - surviving the router's own service queue.
//
// Measured on hardware 2026-09-10: `service restart_vpnc` hung, never cleared its rc_service
// marker, and the router spent ninety minutes discarding every event sent to it - four watchdog
// reconfigures wrote a perfect tunnel config that nothing acted on. It discarded a reboot request
// too, so a power cycle was the only way out. See the runsheet under .claude/testing/.
import 'package:cfg_pia_wg/router_service_queue.dart';
import 'package:flutter_test/flutter_test.dart';

/// A router whose rc_service marker is whatever the test says it is, and which forgets it when
/// told to. Records every command so the ORDER of clear-then-act can be asserted.
class _FakeRouter {
  _FakeRouter({String service = '', int? pid, bool alive = false})
      : _service = service,
        _pid = pid,
        _alive = alive;

  String _service;
  int? _pid;
  bool _alive;
  final List<String> commands = [];

  /// Set to run after the Nth read, so a test can make the marker clear mid-wait.
  void Function(int reads)? onRead;
  int reads = 0;

  Future<String> read(String cmd) async {
    commands.add(cmd);
    if (!cmd.contains('rc_service')) return '';
    onRead?.call(++reads);
    return '$_service@@${_pid ?? ''}@@${_alive ? 'alive' : 'dead'}';
  }

  Future<String> run(String cmd) async {
    commands.add(cmd);
    if (cmd == kClearRcServiceCommand) {
      _service = '';
      _pid = null;
      _alive = false;
    }
    return '';
  }

  void goIdle() {
    _service = '';
    _pid = null;
    _alive = false;
  }

  RouterServiceQueue get queue =>
      RouterServiceQueue(read: read, run: run, pollInterval: Duration.zero, maxPolls: 5);
}

void main() {
  group('parseRcService', () {
    test('an empty marker is idle', () {
      final s = parseRcService('@@@@dead');
      expect(s.idle, isTrue);
      expect(s.stale, isFalse);
      expect(s.busy, isFalse);
    });

    test('a marker whose process is gone is a ghost', () {
      final s = parseRcService('restart_vpnc@@4023@@dead');
      expect(s.service, 'restart_vpnc');
      expect(s.pid, 4023);
      expect(s.stale, isTrue);
      expect(s.busy, isFalse);
    });

    test('a marker whose process is alive is merely busy', () {
      final s = parseRcService('start_wgc 1@@5941@@alive');
      expect(s.busy, isTrue);
      expect(s.stale, isFalse, reason: 'a running service is not a ghost');
    });

    // A probe that does not parse must not stop the action it guards - the router sorts itself out
    // far more often than a malformed read means anything.
    test('anything unrecognisable reads as idle rather than failing', () {
      for (final junk in ['', 'nonsense', 'one@@two']) {
        expect(parseRcService(junk).idle, isTrue, reason: junk);
      }
    });
  });

  group('clearIfStale', () {
    test('clears a ghost, so the next service call is not discarded', () async {
      final r = _FakeRouter(service: 'restart_vpnc', pid: 4023, alive: false);
      final after = await r.queue.clearIfStale();

      expect(r.commands, contains(kClearRcServiceCommand));
      expect(after.idle, isTrue);
    });

    test('leaves a LIVE marker alone', () async {
      final r = _FakeRouter(service: 'restart_vpnc', pid: 4023, alive: true);
      await r.queue.clearIfStale();
      expect(r.commands, isNot(contains(kClearRcServiceCommand)));
    });

    test('does nothing at all when the router is idle', () async {
      final r = _FakeRouter();
      await r.queue.clearIfStale();
      expect(r.commands.where((c) => c.startsWith('nvram set')), isEmpty);
    });
  });

  group('awaitIdle', () {
    test('returns once the marker clears', () async {
      final r = _FakeRouter(service: 'restart_vpnc', pid: 4023, alive: true);
      // Two polls busy, then done - which is what a healthy service call looks like.
      r.onRead = (n) {
        if (n >= 3) r.goIdle();
      };
      await r.queue.awaitIdle();
      expect(r.commands, isNot(contains(kClearRcServiceCommand)));
    });

    test('a service that dies mid-wait leaves a ghost, which is cleared', () async {
      final r = _FakeRouter(service: 'restart_vpnc', pid: 4023, alive: true);
      r.onRead = (n) {
        if (n >= 2) r._alive = false; // the process goes, the marker does not
      };
      await r.queue.awaitIdle();
      expect(r.commands, contains(kClearRcServiceCommand));
    });

    // The one case the app cannot fix. Saying so beats a fifth opaque "router command failed".
    test('a marker still ALIVE after the timeout is reported as wedged', () async {
      final r = _FakeRouter(service: 'restart_vpnc', pid: 4023, alive: true);
      await expectLater(r.queue.awaitIdle(), throwsA(isA<RouterServiceWedgedException>()));
    });

    test('the wedged message names the service and says to power cycle', () {
      final e = RouterServiceWedgedException(parseRcService('restart_vpnc@@4023@@alive'));
      expect(e.toString(), contains('restart_vpnc'));
      expect(e.toString(), contains('Power cycle'));
      // The user has to know the app changed nothing, or they will go hunting for what it broke.
      expect(e.toString(), contains('has been changed by this app'));
    });
  });

  test('the probe asks for all three facts in one round trip', () {
    expect(kRcServiceCommand, contains('nvram get rc_service'));
    expect(kRcServiceCommand, contains('nvram get rc_service_pid'));
    // kill -0 tests for a process without signalling it.
    expect(kRcServiceCommand, contains('kill -0'));
  });
}
