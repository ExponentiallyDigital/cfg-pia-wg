// test/unit/check_reboot_test.dart - scripts/check-reboot.sh's checks before the reboot, on a fake router.
//
// The reboot itself can only be watched on hardware (TESTING.md GRD-7). What can be checked here is the
// part that decides whether the run means anything: that the machine running it is pinned to a tunnel.
// Stock reads that from VPN Fusion's list; Merlin has no such list and routes by VPN Director, often by
// a whole-network rule, so the script asks the kernel which tunnel carries the machine (ID-569).
//
// The fake router runs each command it's given against fake nvram, ip and curl. The same curl answers
// the machine's own probe of Cloudflare's trace page, with the tunnel's address in $STATE/exit.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

const _noShell = 'no POSIX shell';

const _router = r'''#!/bin/sh
SSH_CLIENT="192.168.1.20 50000 22"; export SSH_CLIENT
eval "$1"
''';

const _nvram = r'''#!/bin/sh
[ "$1" = get ] && cat "$STATE/nv/$2" 2>/dev/null
exit 0
''';

// `ip route get 1.1.1.1 from <machine> iif br0`, as the kernel answers it.
const _ip = r'''#!/bin/sh
[ "$1 $2" = "route get" ] && cat "$STATE/route"
exit 0
''';

const _curl = r'''#!/bin/sh
case "$*" in
  *api.ipify.org*) echo 203.0.113.7 ;;
  *cdn-cgi/trace*) printf 'fl=1\nip=%s\n' "$(cat "$STATE/exit")" ;;
esac
''';

void main() {
  final shell = findShell();
  late Directory dir;
  late String state;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('check_reboot_');
    state = '${dir.path}/state';
    Directory('$state/nv').createSync(recursive: true);
    Directory('${dir.path}/bin').createSync();
    for (final e in {'router': _router, 'nvram': _nvram, 'ip': _ip, 'curl': _curl}.entries) {
      File('${dir.path}/bin/${e.key}').writeAsStringSync(e.value);
    }
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', ...Directory('${dir.path}/bin').listSync().map((f) => f.path)]);
    File('$state/nv/wan0_ipaddr').writeAsStringSync('203.0.113.7');
    File('$state/exit').writeAsStringSync('198.51.100.9');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  void merlin(String route) {
    File('$state/nv/3rd-party').writeAsStringSync('merlin');
    File('$state/route').writeAsStringSync(route);
  }

  /// Runs `check-reboot.sh dry`, which stops before the reboot.
  Future<(int, String)> dry() async {
    final sep = Platform.isWindows ? ';' : ':';
    final env = {'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}', 'STATE': state, 'ROUTER_SSH': 'sh ${shPath('${dir.path}/bin/router')}'};
    const cmd = r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; exec bash "$1" dry';
    final r = await runSh(shell!, ['-c', cmd, 'sh', '${Directory.current.path}/scripts/check-reboot.sh'], environment: env);
    return (r.exitCode, '${r.stdout}${r.stderr}');
  }

  test('on Merlin, a machine VPN Director sends to a tunnel counts as pinned, named by its tunnel', () async {
    if (shell == null) return markTestSkipped(_noShell);
    merlin('1.1.1.1 from 192.168.1.20 dev wgc5\n    cache iif br0\n');
    final (code, out) = await dry();
    expect(out, contains('pinned (Merlin, routed through wgc5)'), reason: out);
    expect(code, 0, reason: out);
  });

  test('on Merlin, a machine going out by the WAN is refused, so a run there means nothing', () async {
    if (shell == null) return markTestSkipped(_noShell);
    merlin('1.1.1.1 from 192.168.1.20 via 203.0.113.1 dev eth0\n    cache iif br0\n');
    final (code, out) = await dry();
    expect(out, contains("this machine (192.168.1.20) isn't pinned to a tunnel"), reason: out);
    expect(code, 2, reason: out);
  });

  // The verdict, from probes already recorded: p.N holds the address that answered at second N, or
  // nothing when the probe was blocked. On 2026-11-14 the router's WAN address changed at a reboot,
  // and the script counted every answer that wasn't the old WAN address as the tunnel's, so a leak
  // through the new one could pass (ID-569).
  group('report', () {
    const tunnel = '198.51.100.9', wanBefore = '203.0.113.7', wanAfter = '203.0.113.88';

    Future<(int, String)> report(Map<int, String> probes, {String newBoot = '40', int last = 120}) async {
      final pd = Directory('${dir.path}/pd')..createSync();
      for (final e in probes.entries) {
        File('${pd.path}/p.${e.key}').writeAsStringSync(e.value);
      }
      final r = await runSh(shell!, ['-c', r'exec bash "$1" report "$2" "$3" "$4" "$5" "$6" "$7"', 'sh',
          '${Directory.current.path}/scripts/check-reboot.sh', pd.path, tunnel, wanBefore, wanAfter, newBoot, '$last']);
      return (r.exitCode, '${r.stdout}${r.stderr}');
    }

    Map<int, String> boot({String during = ''}) => {
          for (var i = 0; i < 30; i++) i: tunnel,
          for (var i = 30; i < 45; i++) i: '',
          for (var i = 45; i < 80; i++) i: during,
          for (var i = 80; i <= 120; i++) i: tunnel,
        };

    test('a leak through the WAN address the router got at the reboot fails', () async {
      if (shell == null) return markTestSkipped(_noShell);
      final (code, out) = await report(boot(during: wanAfter));
      expect(out, contains("FAIL REBOOT this pinned device's traffic left by the WAN at: 45s"), reason: out);
      expect(code, 1, reason: out);
    });

    test('an answer from an address that is neither the tunnel nor the WAN fails, named, never counted safe', () async {
      if (shell == null) return markTestSkipped(_noShell);
      final (code, out) = await report(boot(during: '192.0.2.50'));
      expect(out, contains('FAIL REBOOT answers came from an address that is neither'), reason: out);
      expect(out, contains('45s:192.0.2.50'), reason: out);
      expect(code, 1, reason: out);
    });

    test('blocked, then the tunnel again, passes', () async {
      if (shell == null) return markTestSkipped(_noShell);
      final (code, out) = await report(boot());
      expect(out, contains('PASS REBOOT'), reason: out);
      expect(out, contains('first tunnel answer after it at 80s'), reason: out);
      expect(code, 0, reason: out);
    });

    test('control: a leak through the WAN address from before the reboot still fails', () async {
      if (shell == null) return markTestSkipped(_noShell);
      final (code, out) = await report(boot(during: wanBefore));
      expect(out, contains('left by the WAN at: 45s'), reason: out);
      expect(code, 1, reason: out);
    });
  });

  test('control: on stock, VPN Fusion\'s list still decides, and Merlin\'s route is never asked', () async {
    if (shell == null) return markTestSkipped(_noShell);
    File('$state/nv/vpnc_dev_policy_list').writeAsStringSync('<1>192.168.1.20>>9><1>192.168.1.30>>5>');
    File('$state/route').writeAsStringSync('1.1.1.1 from 192.168.1.20 dev wgc5\n');
    final (code, out) = await dry();
    expect(out, contains('pinned (VPN Fusion profile 9)'), reason: out);
    expect(code, 0, reason: out);
  });
}
