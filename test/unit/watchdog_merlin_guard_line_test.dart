// test/unit/watchdog_merlin_guard_line_test.dart - the Merlin watchdog email's kill switch line
// says what the app's guard holds (ID-608).
//
// Since build 577 it is the guard's `prohibit` that keeps a device VPN Director sends to a tunnel
// offline once that tunnel is switched off: Merlin's own kill switch goes with the slot (measured
// 2026-11-12 to 14, ARCHITECTURE 6.10). The email still gave only Merlin's own setting,
// `wgcN_enforce`, where stock's counts the guard's rules from the kernel and names each device
// (ID-320, ID-242). This runs the block the Merlin script carries, in a shell, against a fake
// `nvram` and `ip`, and reads the three sentences it sets. Addresses and names are invented.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/merlin_vpn_director.dart' show merlinGuardPriority;
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../posix_shell.dart';
import '../watchdog_harness.dart' show findShell;

const _noShell = 'no POSIX shell';

const _nvram = r'''#!/bin/sh
[ "$1" = get ] && cat "$STATE/nv/$2" 2>/dev/null
exit 0
''';

const _ip = r'''#!/bin/sh
[ "$1 $2" = "rule show" ] && cat "$STATE/rules" 2>/dev/null
exit 0
''';

void main() {
  final shell = findShell();
  late Directory dir;
  late String state;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wd_merlin_line_');
    state = '${dir.path}/state';
    Directory('$state/nv').createSync(recursive: true);
    Directory('${dir.path}/bin').createSync();
    File('${dir.path}/bin/nvram').writeAsStringSync(_nvram);
    File('${dir.path}/bin/ip').writeAsStringSync(_ip);
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', ...Directory('${dir.path}/bin').listSync().map((f) => f.path)]);
    // The tablet has a reservation and a name; the desktop has neither, so it is named by address.
    File('$state/nv/dhcp_staticlist').writeAsStringSync('<AA:BB:CC:DD:EE:01>192.168.1.55>>');
    File('$state/nv/custom_clientlist').writeAsStringSync('<TABLET>AA:BB:CC:DD:EE:01>0>9>>');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// The block run for [slot], with VPN Director's [rulelist] and the kernel's [rules], and the
  /// three sentences it leaves: tunnel up, tunnel rebuilt, tunnel down.
  Future<List<String>> line(
      {int slot = 1, String enforce = '1', required String rulelist, List<String> rules = const []}) async {
    File('$state/rulelist').writeAsStringSync(rulelist);
    File('$state/rules').writeAsStringSync(rules.join('\n'));
    File('$state/block.sh').writeAsStringSync(
        '${kKillSwitchMerlinShell.replaceAll('/jffs/openvpn/vpndirector_rulelist', 'rulelist').replaceAll('/jffs/nmp_cl_json.js', 'none.js')}\n'
        'printf \'%s\\n\' "\$KILLSW_UP" "\$KILLSW_FIXED" "\$KILLSW_DOWN"\n');
    final sep = Platform.isWindows ? ';' : ':';
    final env = {
      'PATH': '${dir.path}/bin$sep${Platform.environment['PATH']}',
      'STATE': state,
      'SLOT': '$slot',
      'ENFORCE': enforce,
      'JQ': 'jq',
    };
    const cmd = r'P="${PATH%%:*}"; PATH="$P:/usr/bin:/bin:$PATH"; export PATH; cd "$STATE" && exec sh block.sh';
    final r = await runSh(shell!, ['-c', cmd], environment: env);
    expect(r.stderr, isEmpty, reason: 'the block writes nothing to the run\'s error file');
    return (r.stdout as String).trim().split('\n');
  }

  String hold(String ip, [int slot = 1]) => '${merlinGuardPriority(slot)}:\tfrom $ip prohibit';
  const merlinOn = "ON in the router's settings, so Merlin blocks the devices it routes through this tunnel if the tunnel drops";

  test('with every rule held, each sentence names the devices the guard holds, after Merlin\'s own setting', () async {
    if (shell == null) return markTestSkipped(_noShell);
    final out = await line(
        rulelist: '<1>tab>192.168.1.55>>WGC1<1>pc>192.168.1.250>>WGC1<1>other>192.168.1.60>>WGC5<1>default>192.168.1.0/24>>WGC5',
        rules: ['0:\tfrom all lookup local', hold('192.168.1.55'), hold('192.168.1.250'), hold('192.168.1.60', 5)]);
    expect(out[0],
        "$merlinOn. The app's guard also holds TABLET, 192.168.1.250 to this tunnel: no internet if it breaks or is switched off, until it is back");
    expect(out[1], endsWith("The app's guard kept TABLET, 192.168.1.250 pinned to this tunnel, and off the internet while it was down"));
    expect(out[2], endsWith("The app's guard is keeping TABLET, 192.168.1.250 pinned to this tunnel, and off the internet until it is back"));
    expect(out.join(), isNot(contains('192.168.1.60')), reason: "another slot's device is not this tunnel's");
  });

  test('with one rule missing, every sentence says the guard is not fully in place, and how to put it back', () async {
    if (shell == null) return markTestSkipped(_noShell);
    final out = await line(
        rulelist: '<1>tab>192.168.1.55>>WGC1<1>pc>192.168.1.250>>WGC1',
        // The desktop's hold is at another slot's priority, which doesn't hold it to this one.
        rules: [hold('192.168.1.55'), hold('192.168.1.250', 5)]);
    for (final s in out) {
      expect(
          s,
          endsWith("The app's guard is not fully in place: it covers 1 of the 2 devices pinned to this tunnel (TABLET, 192.168.1.250), "
              'so the others can reach the internet another way while it is switched off. Opening DEVICES in the app and '
              'applying any change puts it back'));
    }
  });

  test("with nothing pinned to the tunnel, the line is Merlin's own setting and nothing more", () async {
    if (shell == null) return markTestSkipped(_noShell);
    // A switched-off rule, a range, a rule with a remote address and a WAN pin are none of them pins to it.
    final out = await line(
        rulelist: '<0>off>192.168.1.55>>WGC1<1>range>192.168.1.128/25>>WGC1<1>site>192.168.1.60>8.8.8.8>WGC1<1>wan>192.168.1.94>>WAN',
        rules: [hold('192.168.1.55')]);
    expect(out[0], merlinOn);
    expect(out.join(), isNot(contains("app's guard")));
  });

  test("the guard is reported with Merlin's own switch off too: it is what holds through DISABLE", () async {
    if (shell == null) return markTestSkipped(_noShell);
    final out = await line(enforce: '0', rulelist: '<1>tab>192.168.1.55>>WGC1', rules: [hold('192.168.1.55')]);
    expect(out[0], startsWith('OFF - the kill switch is available but is not enabled. The app\'s guard also holds TABLET'));
  });

  test('with no rules file at all, nothing is added and nothing is complained of', () async {
    if (shell == null) return markTestSkipped(_noShell);
    final out = await line(rulelist: '');
    File('$state/rulelist').deleteSync();
    expect(out[0], merlinOn);
  });

  test('the Merlin script carries the block, and stock does not', () {
    const cfg = WatchdogConfig(slotIndex: 1, cronIntervalMinutes: 5, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1');
    expect(buildWatchdogScript(cfg, firmware: RouterFirmware.merlin), contains(kKillSwitchMerlinShell));
    expect(buildWatchdogScript(cfg, firmware: RouterFirmware.stock), isNot(contains("The app's guard also holds")));
  });
}
