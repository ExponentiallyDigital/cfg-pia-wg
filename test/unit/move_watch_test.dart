// test/unit/move_watch_test.dart - scripts/move-watch.sh against a fake router (ID-302).
//
// The watcher's answer rests on two things that are easy to get wrong and can't be seen on the
// router afterwards: that its leak counters keep counting across a firewall restart, which takes its
// counting chains away, and that it leaves nothing behind. So both run here, against stand-ins: an
// iptables that keeps the mangle chains in files and counts 5 packets each time a counter is read,
// and can be told to "restart the firewall" (drop the chains and their counts) mid-run.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

const _nvram = r'''#!/bin/sh
case "$2" in
  wan0_ifname) printf eth0 ;;
  vpnc_dev_policy_list) cat "$STATE/policy" 2>/dev/null ;;
esac
''';

// rule show from $STATE/rules; route get answers from $STATE/route; link show up from $STATE/up.
// Each route get is one sample, counted in $STATE/samples.
const _ip = r'''#!/bin/sh
case "$1 $2" in
  "rule show") cat "$STATE/rules" 2>/dev/null ;;
  "route get") echo x >> "$STATE/samples"; cat "$STATE/route" ;;
  "-o link") cat "$STATE/up" 2>/dev/null ;;
esac
''';

// Only the forms move-watch.sh uses. Mangle chains are files $STATE/m_<chain>; jumps are lines in
// $STATE/m_jumps; a read of a chain (-L) adds 5 to its count first. $STATE/restart, when present,
// makes the next look at the chains find them gone, as a firewall restart leaves them.
const _iptables = r'''#!/bin/sh
if [ -f "$STATE/restart" ]; then rm -f "$STATE/restart" "$STATE"/m_MOVEWATCH* ; : > "$STATE/m_jumps"; fi
[ "$1" = -t ] && shift 2
case "$1" in
  -S)
    case "$2" in
      FORWARD|POSTROUTING) grep "^$2 " "$STATE/m_jumps" 2>/dev/null | sed 's/^[A-Z]* \(.*\)/-A X \1/' ;;
      MOVEWATCH*) [ -f "$STATE/m_$2" ] || exit 1 ;;
    esac ;;
  -N) [ -f "$STATE/m_$2" ] && exit 1; echo 0 > "$STATE/m_$2" ;;
  -F) [ -f "$STATE/m_$2" ] && echo 0 > "$STATE/m_$2" ;;
  -X) rm -f "$STATE/m_$2" ;;
  -A) : ;;
  -I) echo "$2 $5 $6 $7 $8" >> "$STATE/m_jumps"; echo "$2" >> "$STATE/inserted" ;;
  -D) grep -q "^$2 " "$STATE/m_jumps" 2>/dev/null || exit 1; grep -v "^$2 " "$STATE/m_jumps" > "$STATE/j.new"; mv "$STATE/j.new" "$STATE/m_jumps" ;;
  -L)
    [ -f "$STATE/m_$2" ] || exit 1
    n=$(( $(cat "$STATE/m_$2") + 5 )); echo "$n" > "$STATE/m_$2"
    echo "Chain $2 (1 references)"; echo "    pkts      bytes target     prot opt in     out     source               destination"
    echo "    $n   $((n * 84)) RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0" ;;
esac
exit 0
''';

const _cru = '#!/bin/sh\nexit 0\n';

void main() {
  final shell = findShell();
  late Directory dir;
  late String state;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('move_watch_');
    state = '${dir.path}/state';
    Directory(state).createSync();
    Directory('${dir.path}/bin').createSync();
    for (final e in {'nvram': _nvram, 'ip': _ip, 'iptables': _iptables, 'cru': _cru}.entries) {
      File('${dir.path}/bin/${e.key}').writeAsStringSync(e.value);
    }
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', ...Directory('${dir.path}/bin').listSync().map((f) => f.path)]);
    File('$state/policy').writeAsStringSync('1>192.0.2.20>>5>');
    File('$state/rules').writeAsStringSync('90:\tfrom 192.0.2.20 lookup 205\n91:\tfrom 192.0.2.20 blackhole\n');
    File('$state/route').writeAsStringSync('1.1.1.1 from 192.0.2.20 dev wgc5 table 205\n');
    File('$state/up').writeAsStringSync('5: wgc5: <POINTOPOINT,UP> mtu 1420\n');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Runs the watcher for [seconds], and calls [during] once its loop has taken a sample. Returns its log.
  ///
  /// Not at a fixed time: a Mac's shell starts processes slowly enough that 1.5 s in, the watcher had
  /// not yet reached its loop, and the restart was taken by the setup before it, where no restart is
  /// counted.
  Future<String> watch(int seconds, {void Function()? during}) async {
    final sep = Platform.isWindows ? ';' : ':';
    final env = {'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}', 'STATE': state};
    const cmd = r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; '
        r'cd "$STATE" && sed "s#/tmp/move-watch#$STATE/move-watch#g" "$1" > mw.sh && exec sh mw.sh 192.0.2.20 "$2"';
    final p = await startSh(shell!, ['-c', cmd, 'sh', '${Directory.current.path}/scripts/move-watch.sh', '$seconds'], environment: env);
    if (during != null) {
      final samplesFile = File('$state/samples');
      for (var i = 0; i < 100 && !samplesFile.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      during();
    }
    await p.exitCode;
    return File('$state/move-watch.log').readAsStringSync();
  }

  int samples() => File('$state/samples').readAsLinesSync().length;
  int answer(String log, String label) => int.parse(RegExp('$label[^:\\n]*: (\\d+)').firstMatch(log)!.group(1)!);

  test('the leak counters carry on across a firewall restart, and every packet counted is counted once', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    final log = await watch(4, during: () => File('$state/restart').writeAsStringSync(''));
    // Each sample reads each counter once, and each read is 5 more packets: so 5 per sample. A
    // restart that lands between a sample's two reads loses that sample's 5 for the second counter,
    // the up-to-a-second loss the watcher reports; never more than that one sample.
    expect(answer(log, 'packets it sent out of the internet connection'), inInclusiveRange(5 * samples() - 5, 5 * samples()), reason: log);
    expect(answer(log, 'packets to it from the internet connection'), inInclusiveRange(5 * samples() - 5, 5 * samples()), reason: log);
    expect(answer(log, 'put back after a firewall restart'), 1, reason: log);
  });

  test('a guarded device routed through its tunnel reads as guarded throughout', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    final log = await watch(3);
    expect(log, contains('pin=1>192.0.2.20>>5> r=11 f=0 route=wgc5 up=wgc5'));
    expect(answer(log, 'without both guard rules'), 0);
    expect(answer(log, 'routed it to the WAN'), 0);
  });

  test('a device with no guard rules and a WAN route is counted as both, for the whole run', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    File('$state/rules').writeAsStringSync('');
    File('$state/policy').writeAsStringSync('');
    File('$state/route').writeAsStringSync('1.1.1.1 from 192.0.2.20 via 198.51.100.1 dev eth0\n');
    final log = await watch(3);
    expect(log, contains('pin=none r=00'));
    expect(answer(log, 'without both guard rules'), samples());
    expect(answer(log, 'routed it to the WAN'), samples());
  });

  test('it leaves nothing behind: both chains and both jumps are taken out', () async {
    if (shell == null) return markTestSkipped('no POSIX shell');
    await watch(2, during: () => File('$state/restart').writeAsStringSync(''));
    expect(File('$state/m_jumps').readAsStringSync().trim(), isEmpty);
    expect(Directory(state).listSync().where((f) => f.path.contains('m_MOVEWATCH')), isEmpty);
    expect(File('$state/move-watch.pid').existsSync(), isFalse);
  });
}
