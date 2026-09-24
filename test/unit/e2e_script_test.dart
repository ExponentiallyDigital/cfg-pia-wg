// scripts/e2e.sh, run for real against stand-ins for `ip`, `nvram` and `logger` (ID-207).
//
// The script is what turns a hardware step into one word, so a wrong PASS from it would be worse
// than no script at all. Skipped where no POSIX shell is on the PATH.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../watchdog_harness.dart' show findShell;

const _ip = r'''#!/bin/sh
case "$1 $2" in
  "rule show") cat "$STATE/rules" 2>/dev/null ;;
  "-o link") n=2; while read -r i; do n=$((n + 1)); echo "$n: $i: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420"; done < "$STATE/up" ;;
  "route get") f="$STATE/route_$5"; if [ -f "$f" ]; then cat "$f"; else echo "RTNETLINK answers: Network is unreachable" >&2; exit 2; fi ;;
esac
''';

const _nvram = r'''#!/bin/sh
[ "$1" = "get" ] && cat "$STATE/nv_$2" 2>/dev/null
exit 0
''';

const _logger = r'''#!/bin/sh
shift 2
echo "$*" >> "$STATE/syslog"
''';

void main() {
  final shell = findShell();
  late Directory root;
  late String state;

  void write(String name, String text) => File('$state/$name').writeAsStringSync(text);

  Future<ProcessResult> e2e(List<String> args) {
    final sep = Platform.isWindows ? ';' : ':';
    return Process.run(
      shell!,
      [
        '-c',
        r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; exec sh "$@"',
        'sh',
        '${Directory.current.path}/scripts/e2e.sh',
        ...args,
      ],
      environment: {
        'PATH': '${root.path}/bin$sep${Platform.environment['PATH']}',
        'STATE': state,
        'E2E_DIR': '${root.path}/snap',
      },
    );
  }

  setUp(() {
    if (shell == null) return;
    root = Directory.systemTemp.createTempSync('e2e_');
    state = '${root.path}/state';
    Directory(state).createSync();
    Directory('${root.path}/bin').createSync();
    for (final e in {'ip': _ip, 'nvram': _nvram, 'logger': _logger}.entries) {
      File('${root.path}/bin/${e.key}').writeAsStringSync(e.value);
    }
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['+x', for (final b in ['ip', 'nvram', 'logger']) '${root.path}/bin/$b']);
    }
    write('rules', '0:\tfrom all lookup local\n32766:\tfrom all lookup main\n');
    write('up', 'wgc1\nwgc5\n');
    write('nv_vpnc_default_wan', '0');
    write('nv_vpnc_dev_policy_list', '');
  });
  tearDown(() {
    if (shell != null) root.deleteSync(recursive: true);
  });

  group('scripts/e2e.sh', () {
    test('before marks the log and takes a snapshot', () async {
      final r = await e2e(['DEV-3', 'before']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(File('$state/syslog').readAsStringSync(), contains('**TEST DEV-3** STARTED'));
      expect(File('${root.path}/snap/DEV-3.before').existsSync(), isTrue);
    });

    test('after shows what changed, checks it, and says PASS', () async {
      await e2e(['DEV-3', 'before']);
      write(
          'rules',
          '0:\tfrom all lookup local\n90:\tfrom 192.168.1.20 lookup 5 suppress_prefixlength 0\n91:\tfrom 192.168.1.20 blackhole\n'
              '100:\tfrom 192.168.1.20 lookup 5\n32766:\tfrom all lookup main\n');
      write('nv_vpnc_dev_policy_list', '<1>192.168.1.20>>5>');
      write('route_192.168.1.20', '1.1.1.1 from 192.168.1.20 dev wgc5 table 5 \n');
      final r = await e2e([
        'DEV-3',
        'after',
        'exit 192.168.1.20 wgc5',
        'rule 192.168.1.20 5',
        'guard 192.168.1.20 5',
        'default 0',
        'up wgc5',
      ]);
      final out = '${r.stdout}';
      expect(r.exitCode, 0, reason: out);
      expect(out, contains('+ 100:\tfrom 192.168.1.20 lookup 5'));
      expect(out, contains('+ 1>192.168.1.20>>5>'));
      expect(out, contains('== DEV-3: PASS'));
      expect(File('$state/syslog').readAsStringSync(), contains('**TEST DEV-3** ENDED PASS'));
    });

    test('a duplicate rule, a missing guard and a leak are each a FAIL', () async {
      write('rules', '100:\tfrom 192.168.1.20 lookup 5\n100:\tfrom 192.168.1.20 lookup 5\n');
      write('route_192.168.1.20', '1.1.1.1 from 192.168.1.20 via 192.0.2.1 dev eth0 table main \n');
      final r = await e2e(['DEV-4', 'after', 'rule 192.168.1.20 5', 'guard 192.168.1.20 5', 'exit 192.168.1.20 wgc5']);
      final out = '${r.stdout}';
      expect(r.exitCode, 1);
      expect(out, contains('FAIL  rule 192.168.1.20 5: found "5 5"'));
      expect(out, contains('FAIL  guard 192.168.1.20 5: found "0 0"'));
      expect(out, contains('FAIL  exit 192.168.1.20 wgc5: found "WAN"'));
      expect(out, contains('== DEV-4: FAIL (3)'));
    });

    test('a device the kernel has no route for reads as BLOCKED', () async {
      final r = await e2e(['GRD-2', 'after', 'exit 192.168.1.20 BLOCKED', 'down wgc9', 'noguard 192.168.1.30']);
      expect(r.exitCode, 0, reason: '${r.stdout}');
    });

    test('something removed is shown as removed', () async {
      write('rules', '100:\tfrom 192.168.1.20 lookup 9\n');
      await e2e(['DEV-5', 'before']);
      write('rules', '');
      final r = await e2e(['DEV-5', 'after']);
      expect('${r.stdout}', contains('- 100:\tfrom 192.168.1.20 lookup 9'));
    });
  }, skip: shell == null ? 'no POSIX shell on the PATH' : null);
}
