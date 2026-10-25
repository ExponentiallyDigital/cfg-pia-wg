// live/network_live_test.dart - TESTING.md's NET tests, run unattended against a real router (ID-458).
//
//   flutter test live/network_live_test.dart --reporter expanded
//
// Outside test/, so CI never runs it. Skipped unless CFG_LIVE_ROUTER, CFG_LIVE_USER and CFG_LIVE_PASS
// are set (the same names as devices_live_test.dart). It changes nothing NETWORK doesn't change each time
// it opens: one routing rule per tunnel, added for the request and taken out again, which NET-2 and
// NET-3 check is gone. It asks PIA through the app's own code, as NETWORK does, from this computer for
// "This device" and from the router through each tunnel. The log goes to .claude/testing/, which git
// ignores: it holds real addresses.
//
//   NET-1  PIA answers this computer with an address, a place and a provider.
//   NET-2  every tunnel that is up answers through itself, each with its own address, none the WAN's,
//          and no lookup rule is left on the router.
//   NET-3  a slot that isn't up is not asked: stock's route read-back answers NOROUTE, so nothing is
//          sent, and no rule is left. A tunnel that is set up but down if there is one, else an empty
//          slot: either way the slot's table has no route through a tunnel, which is what is tested.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/network_lookup.dart';
import 'package:cfg_pia_wg/router_command.dart';
import 'package:cfg_pia_wg/router_host_keys.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

const _needed = ['CFG_LIVE_ROUTER', 'CFG_LIVE_USER', 'CFG_LIVE_PASS'];

/// An RFC 1918, carrier-grade NAT or link-local address, which no internet service would answer with.
bool _private(String ip) {
  final a = InternetAddress.tryParse(ip);
  if (a == null || a.type != InternetAddressType.IPv4) return false;
  final b = a.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] < 32) ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 100 && b[1] >= 64 && b[1] < 128) ||
      (b[0] == 169 && b[1] == 254);
}

void main() {
  final env = Platform.environment;
  final missing = [for (final n in _needed) if ((env[n] ?? '').trim().isEmpty) n];
  test('NETWORK, on a live router', () async {
    final run = _NetworkRun(env['CFG_LIVE_ROUTER']!.trim(), env['CFG_LIVE_USER']!.trim(), env['CFG_LIVE_PASS']!);
    try {
      await run.go();
    } finally {
      await run.close();
    }
    expect(run.failures, isEmpty, reason: run.failures.join('\n'));
  }, skip: missing.isEmpty ? false : 'set ${missing.join(', ')}');
}

class _NetworkRun {
  _NetworkRun(this.router, this.user, this.pass);

  final String router, user, pass;
  final List<String> failures = [];
  final StringBuffer _log = StringBuffer();
  SSHClient? _client;

  void _say(String line) {
    // ignore: avoid_print
    print(line);
    _log.writeln(line);
  }

  void _result(String id, bool pass, String why) {
    _say('$id ${pass ? 'PASS' : 'FAIL'}: $why');
    if (!pass) failures.add('$id: $why');
  }

  Future<String> _sh(String cmd) async => (await runRouterCommand(_client!, cmd, allowFailure: true)).stdout.trim();

  Future<int> _leftoverRules() async => int.tryParse(await _sh("ip rule show | grep -c '^$kTunnelLookupPriority:'")) ?? -1;

  Future<void> go() async {
    // NET-1: from this computer, as "This device" is asked from the phone.
    NetworkFacts? device;
    try {
      device = await lookUpThisPhone();
      _result('NET-1', device.place.isNotEmpty && device.provider.isNotEmpty,
          '${kIpLookupService.name} answered ${device.ip}, ${device.place}, ${device.provider}');
    } catch (e) {
      _result('NET-1', false, 'no answer from ${kIpLookupService.name}: $e');
    }

    _say('Connecting to $router as $user...');
    final keys = RouterHostKeys(directory: () async => Directory('${Directory.systemTemp.path}/cfg-pia-wg-live')..createSync());
    _client = await openSshClient(router, user, pass, hostKeys: keys);
    final firmware = classifyFirmwareTag(await _sh('nvram get 3rd-party'));
    if (firmware == null) {
      _result('NET-2', false, 'this router firmware is not supported');
      return;
    }
    setRouterFirmware(firmware);
    final stock = firmware == RouterFirmware.stock;
    final wan = await _sh('nvram get wan0_ipaddr');
    _say('Firmware ${firmwareLabel(firmware)}, WAN $wan.');
    if (device != null) {
      _say(device.ip == wan
          ? 'This computer goes out by the WAN.'
          : 'This computer is not on the WAN address ($wan): pinned to a tunnel, or the router is behind another NAT.');
    }

    final slots = await RouterSlotService(_client!).fetchSlots();
    final address = await tunnelLookupAddress();
    if (address == null) {
      _result('NET-2', false, "no address for ${kIpLookupService.name} that a tunnel carries");
      return;
    }

    // NET-2: every tunnel that is up.
    final up = slots.activeSlots.toList()..sort((a, b) => b.compareTo(a));
    if (up.isEmpty) {
      _say('NET-2 SKIP: no tunnel is up.');
    } else {
      final found = parseTunnelLookups(await _sh(tunnelLookupCommand(up, address, stock: stock)), up);
      final ips = <String>[];
      for (final s in up) {
        final r = found[s]!;
        final ok = r.outcome == TunnelLookupOutcome.found && (r.facts!.ip != wan || _private(wan));
        _result('NET-2 wgc$s', ok,
            r.facts == null ? r.outcome.name : '${r.facts!.ip}, ${r.facts!.place}, ${r.facts!.provider} (${slots.slots[s]?.desc})');
        if (r.facts != null) ips.add(r.facts!.ip);
      }
      _result('NET-2 distinct', ips.toSet().length == ips.length, 'each tunnel has its own address: ${ips.join(', ')}');
      final left = await _leftoverRules();
      _result('NET-2 clean', left == 0, '$left lookup rule(s) left at priority $kTunnelLookupPriority');
    }

    // NET-3: a slot that isn't up is never asked. On stock the route read-back says NOROUTE; Merlin
    // binds to an interface that isn't there, so nothing answers. A tunnel set up but down is the case
    // NETWORK meets; with none, an empty slot's table is just as empty of a route through a tunnel.
    final notUp = [for (final s in slots.slots.keys) if (!slots.activeSlots.contains(s)) s]..sort();
    final setUpDown = [for (final s in notUp) if (!slots.slots[s]!.isEmpty) s];
    final down = setUpDown.isNotEmpty ? setUpDown : notUp.take(1).toList();
    if (down.isEmpty) {
      _say('NET-3 SKIP: every slot is up.');
    } else {
      _say('NET-3 asks through ${down.map((s) => 'wgc$s').join(', ')}, ${setUpDown.isNotEmpty ? 'set up but down' : 'an empty slot'}.');
      final found = parseTunnelLookups(await _sh(tunnelLookupCommand(down, address, stock: stock)), down);
      for (final s in down) {
        final want = stock ? TunnelLookupOutcome.noRoute : TunnelLookupOutcome.failed;
        _result('NET-3 wgc$s', found[s]!.outcome == want, '${found[s]!.outcome.name}, want ${want.name}');
      }
      final left = await _leftoverRules();
      _result('NET-3 clean', left == 0, '$left lookup rule(s) left at priority $kTunnelLookupPriority');
    }
  }

  Future<void> close() async {
    _client?.close();
    final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '');
    final f = File('.claude/testing/${stamp}_live_network.log');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(_log.toString());
    _say('Log: ${f.path}');
  }
}
