// test/unit/device_assignment_service_test.dart - the read and the write, over a fake SSH client.
//
// The write tests are the ones that matter. Two of them guard against destroying configuration the
// user set up elsewhere: a policy record naming a VPN this app does not manage must survive an
// apply untouched, and an apply must refuse outright if the router changed under it.
//
// MACs are invented - see test/unit/no_lan_identifiers_test.dart.
import 'package:cfg_pia_wg/device_assignment_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

const _clientlist = 'pia-aus_melbourne>WireGuard>1>>password>1>9>>>0>0>cfg-pia-wg'
    '<pia-aus_perth>WireGuard>5>>password>1>5>>>0>0>cfg-pia-wg'
    '<office>OpenVPN>1>>password>1>3>>>0>0>';

const _policyList = '1>192.168.1.20>>9><1>192.168.1.50>>3>';
const _staticlist = '<11:22:33:44:55:66>192.168.1.20>>Box';
const _cfgDeviceList = '<RT-ABCD>192.168.1.1>AA:BB:CC:DD:EE:FF>1<RT-EFGH>192.168.1.90>33:44:55:66:77:88>0';

const _clJson = '{'
    '"11:22:33:44:55:66":{"name":"box","online":1},'
    '"22:33:44:55:66:77":{"name":"laptop","online":0},'
    '"33:44:55:66:77:88":{"name":"meshnode","online":1}}';

const _cache = '{'
    '"maclist":["11:22:33:44:55:66"],'
    '"ClientAPILevel":"5",'
    '"11:22:33:44:55:66":{"nickName":"Box","ip":"192.168.1.20","isOnline":"1"},'
    '"22:33:44:55:66:77":{"nickName":"Laptop","ip":"192.168.1.50","isOnline":"1"},'
    '"33:44:55:66:77:88":{"nickName":"Node","ip":"192.168.1.90","isOnline":"1"}}';

const _sep = '@@CFGPIAWG@@';

/// Builds the marker-delimited blob the batched read expects.
String _blob({String cache = _cache, String policy = _policyList}) => [
      '',
      _clientlist,
      policy,
      '9',
      _staticlist,
      '',
      _cfgDeviceList,
      _clJson,
      cache,
      '',
    ].join('\n$_sep\n');

RecordingSSHClient _client({String cache = _cache, String policy = _policyList, String? policyOnReRead}) {
  return RecordingSSHClient(responder: (cmd) {
    if (cmd.contains('cfg_device_list')) return _blob(cache: cache, policy: policy);
    if (cmd == 'nvram get vpnc_dev_policy_list') return policyOnReRead ?? policy;
    if (cmd == 'nvram get vpnc_clientlist') return _clientlist;
    if (cmd == 'nvram get dhcp_staticlist') return _staticlist;
    // The default-connection sequence polls these two. `restart_default_wan` resetting the key to
    // 0 is what the service waits for, and the target interface coming back is the other.
    if (cmd == 'nvram get vpnc_default_wan') return '0';
    if (cmd == 'ip -o link show up') return 'wgc1 wgc5';
    return '';
  });
}

/// No real waiting: `notify_rc` queueing is what the poll interval exists for, and the fake has no
/// queue.
DeviceAssignmentService _svc(RecordingSSHClient c) =>
    DeviceAssignmentService(c, pollInterval: Duration.zero);

Future<AssignmentState> _state(RecordingSSHClient c) => DeviceAssignmentService(c).read();

void main() {
  setUp(useStock);

  group('read', () {
    test('one round trip fetches everything', () async {
      final c = _client();
      await _state(c);
      // Eight sources, one command. A phone on wifi pays for every round trip.
      expect(c.commands.where((cmd) => cmd.contains('nvram get')).length, 1);
    });

    test('the mesh node and the router are absent from the device list', () async {
      final s = await _state(_client());
      expect(s.devices.map((d) => d.mac), isNot(contains('33:44:55:66:77:88')));
      expect(s.devices.length, 2);
    });

    test('online comes from nmp_cl_json, not the stale isOnline', () async {
      final s = await _state(_client());
      expect(s.devices.firstWhere((d) => d.mac == '22:33:44:55:66:77').online, isFalse);
    });

    test('reads the default connection and the profiles', () async {
      final s = await _state(_client());
      expect(s.defaultIndex, 9);
      expect(s.profiles.length, 3);
    });

    test('a missing /tmp cache does not break the read', () async {
      // `cat` on an absent file writes to stderr and yields nothing; the join degrades to
      // dhcp_staticlist for the address.
      final s = await _state(_client(cache: ''));
      expect(s.devices.length, 2);
      expect(s.devices.firstWhere((d) => d.mac == '11:22:33:44:55:66').ip, '192.168.1.20');
    });

    test('profileFor names the profile a device is on, WireGuard or not', () async {
      final s = await _state(_client());
      final box = s.devices.firstWhere((d) => d.mac == '11:22:33:44:55:66');
      final laptop = s.devices.firstWhere((d) => d.mac == '22:33:44:55:66:77');
      expect(s.profileFor(box)?.desc, 'pia-aus_melbourne');
      // The laptop is on the OpenVPN profile. It must be reported as such, not as unassigned.
      expect(s.profileFor(laptop)?.protocol, 'OpenVPN');
    });
  });

  group('apply', () {
    test('does nothing at all when nothing was staged', () async {
      final c = _client();
      final s = await _state(c);
      c.commands.clear();
      await _svc(c).apply(base: s, changes: {}, reservationsToCreate: {});
      expect(c.commands, isEmpty);
    });

    test('REFUSES when the policy list changed under it, and writes nothing', () async {
      final c = _client(policyOnReRead: '1>192.168.1.99>>5>');
      final s = await _state(c);
      c.commands.clear();
      await expectLater(
        _svc(c)
            .apply(base: s, changes: {'192.168.1.20': 5}, reservationsToCreate: {}),
        throwsA(isA<AssignmentConflictException>()),
      );
      expect(c.commands.any((cmd) => cmd.contains('nvram set')), isFalse, reason: 'nothing written');
    });

    test('REFUSES when the profile list changed under it', () async {
      final c = RecordingSSHClient(responder: (cmd) {
        if (cmd.contains('cfg_device_list')) return _blob();
        if (cmd == 'nvram get vpnc_dev_policy_list') return _policyList;
        if (cmd == 'nvram get vpnc_clientlist') return 'something>else>1>>password>1>9>>>0>0>';
        return '';
      });
      final s = await _state(c);
      await expectLater(
        _svc(c)
            .apply(base: s, changes: {'192.168.1.20': 5}, reservationsToCreate: {}),
        throwsA(isA<AssignmentConflictException>()),
      );
    });

    test('THE OPENVPN RECORD SURVIVES BYTE FOR BYTE', () async {
      // 192.168.1.50 is pinned to an OpenVPN profile. Moving a different device must not rewrite,
      // reorder or drop it - that would silently destroy an assignment made in the web interface.
      final c = _client();
      final s = await _state(c);
      await _svc(c)
          .apply(base: s, changes: {'192.168.1.20': 5}, reservationsToCreate: {});
      final write = c.commands.firstWhere((cmd) => cmd.startsWith('nvram set vpnc_dev_policy_list'));
      expect(write, contains('1>192.168.1.50>>3>'));
      expect(write, contains('1>192.168.1.20>>5>'));
    });

    test('unassigning disables the record rather than deleting it', () async {
      final c = _client();
      final s = await _state(c);
      await _svc(c)
          .apply(base: s, changes: {'192.168.1.20': null}, reservationsToCreate: {});
      final write = c.commands.firstWhere((cmd) => cmd.startsWith('nvram set vpnc_dev_policy_list'));
      expect(write, contains('0>192.168.1.20>>0>'));
    });

    test('creates a reservation for an unreserved device, and NEVER restarts the network', () async {
      // The web interface takes restart_net_and_phy for this same job, which bounces every switch
      // port and re-leases the WAN. Measured 2026-09-08: writing the reservation ourselves and
      // calling only the light pair applies it with nothing bouncing.
      final c = _client();
      final s = await _state(c);
      await _svc(c).apply(
        base: s,
        changes: {'192.168.1.50': 5},
        reservationsToCreate: {'22:33:44:55:66:77': '192.168.1.50'},
      );
      expect(c.ran('nvram set dhcp_staticlist'), isTrue);
      expect(c.commands.firstWhere((cmd) => cmd.startsWith('nvram set dhcp_staticlist')),
          contains('<22:33:44:55:66:77>192.168.1.50>>'));
      expect(c.ran('restart_net_and_phy'), isFalse, reason: 'the whole point of the light pair');
    });

    test('an existing reservation is not duplicated', () async {
      final c = _client();
      final s = await _state(c);
      await _svc(c).apply(
        base: s,
        changes: {'192.168.1.20': 5},
        reservationsToCreate: {'11:22:33:44:55:66': '192.168.1.20'},
      );
      final write = c.commands.firstWhere((cmd) => cmd.startsWith('nvram set dhcp_staticlist'));
      expect(RegExp('11:22:33:44:55:66').allMatches(write).length, 1);
    });

    test('commits, then calls the light pair in order', () async {
      final c = _client();
      final s = await _state(c);
      await _svc(c)
          .apply(base: s, changes: {'192.168.1.20': 5}, reservationsToCreate: {});
      final order = c.commands.where((cmd) => cmd.contains('commit') || cmd.contains('service')).toList();
      expect(order, ['nvram commit', 'service restart_dnsmasq', 'service restart_vpnc_dev_policy']);
    });

    // Without this the whole feature is cosmetic. Measured on hardware 2026-09-10: stock leaves
    // the old rule in place when a device moves, both sit at priority 100, and the kernel takes
    // them in insertion order - so NVRAM, the web interface and this app all said wgc5 while the
    // traffic went out wgc1. See staleRuleTables for the evidence.
    group('stale routing rules', () {
      /// A router that actually applies the deletes, so the sweep terminates the way it does on
      /// hardware rather than looping against a fixed reply.
      RecordingSSHClient ruleClient(List<String> rules) {
        final live = [...rules];
        return RecordingSSHClient(responder: (cmd) {
          if (cmd.contains('cfg_device_list')) return _blob();
          if (cmd == 'nvram get vpnc_dev_policy_list') return _policyList;
          if (cmd == 'nvram get vpnc_clientlist') return _clientlist;
          if (cmd == 'nvram get dhcp_staticlist') return _staticlist;
          if (cmd == 'ip rule show') return live.join('\n');
          if (cmd.startsWith('ip rule del ')) {
            final m = RegExp(r'from (\S+) lookup ([0-9]+)').firstMatch(cmd)!;
            live.removeWhere((r) => r.contains('from ${m.group(1)} lookup ${m.group(2)}'));
            return '';
          }
          return '';
        });
      }

      test('the rule for the tunnel the device left is deleted', () async {
        final c = ruleClient([
          '100:\tfrom 192.168.1.20 lookup 9',
          '100:\tfrom 192.168.1.20 lookup 5',
          '10000:\tfrom all iif br0 lookup 5',
        ]);
        final s = await _state(c);
        await _svc(c).apply(base: s, changes: {'192.168.1.20': 5}, reservationsToCreate: {});

        expect(c.commands, contains('ip rule del from 192.168.1.20 lookup 9'));
        expect(c.commands.any((x) => x.contains('lookup 5')), isFalse, reason: 'the new rule stays');
        expect(c.ran('restart_net_and_phy'), isFalse, reason: 'deleting the rule is the light fix');
      });

      test('the sweep runs after the service that installs the new rule', () async {
        final c = ruleClient(['100:\tfrom 192.168.1.20 lookup 9']);
        final s = await _state(c);
        await _svc(c).apply(base: s, changes: {'192.168.1.20': 5}, reservationsToCreate: {});
        expect(c.commands.indexOf('service restart_vpnc_dev_policy'),
            lessThan(c.commands.indexWhere((x) => x.startsWith('ip rule del'))));
      });

      test('unassigning clears every per-device rule and leaves the default connection alone', () async {
        final c = ruleClient([
          '100:\tfrom 192.168.1.20 lookup 9',
          '10000:\tfrom all iif br0 lookup 9',
        ]);
        final s = await _state(c);
        await _svc(c).apply(base: s, changes: {'192.168.1.20': null}, reservationsToCreate: {});

        expect(c.commands, contains('ip rule del from 192.168.1.20 lookup 9'));
        expect(c.commands.any((x) => x.contains('from all')), isFalse);
      });

      test('nothing is deleted when the rules are already right', () async {
        final c = ruleClient(['100:\tfrom 192.168.1.20 lookup 5']);
        final s = await _state(c);
        await _svc(c).apply(base: s, changes: {'192.168.1.20': 5}, reservationsToCreate: {});
        expect(c.commands.any((x) => x.startsWith('ip rule del')), isFalse);
      });

      test('a default-connection change on its own touches no per-device rule', () async {
        final c = ruleClient(['100:\tfrom 192.168.1.20 lookup 9']);
        final s = await _state(c);
        await _svc(c).apply(base: s, changes: {}, reservationsToCreate: {}, newDefaultIndex: 5);
        expect(c.commands.any((x) => x.startsWith('ip rule del')), isFalse);
      });
    });

    // The app log is the only record of an assignment once the screen has moved on, and the
    // router log said nothing at all about a default-connection change - which is exactly the
    // change that explains an outage days later.
    group('what gets logged', () {
      test('each device change is named, one line each', () async {
        final c = _client();
        final s = await _state(c);
        final logged = <String>[];
        final svc = DeviceAssignmentService(c, pollInterval: Duration.zero,
            onLog: (m, {isError = false, isSuccess = false}) => logged.add(m));

        await svc.apply(
          base: s,
          changes: {'192.168.1.20': 5},
          reservationsToCreate: {},
          changeDescriptions: const ['Box: default - Internet -> wgc5:pia-aus_perth'],
        );

        expect(logged, contains('Applying 1 device change:'));
        expect(logged, contains('  Box: default - Internet -> wgc5:pia-aus_perth'));
        // The same line in the ROUTER log: the app log dies with the app, and a reassignment that
        // explains a device's traffic weeks later has to survive.
        expect(c.commands.firstWhere((x) => x.contains('logger'), orElse: () => ''), contains('reassigned'));
        expect(logged.any((l) => l == 'Applying...'), isFalse, reason: 'that told the reader nothing');
      });

      test('a default-connection change is named in BOTH logs, from and to', () async {
        final c = _client();
        final s = await _state(c);
        final logged = <String>[];
        final svc = DeviceAssignmentService(c, pollInterval: Duration.zero,
            onLog: (m, {isError = false, isSuccess = false}) => logged.add(m));

        await svc.apply(
          base: s,
          changes: const {},
          reservationsToCreate: {},
          newDefaultIndex: 5,
          defaultFrom: 'Internet',
          defaultTo: 'wgc5:pia-aus_perth',
        );

        expect(logged.join('\n'), contains('from Internet to wgc5:pia-aus_perth'));
        final syslog = c.commands.firstWhere((x) => x.contains('logger'), orElse: () => '');
        expect(syslog, contains('default WAN connection set from Internet to wgc5:pia-aus_perth'));
      });
    });

    test('THE DEFAULT CONNECTION SEQUENCE IS EXACT', () async {
      // Eleven probes on hardware to find this. Every element is load-bearing and the order is
      // the part that is not guessable: restart_default_wan RESETS the key, so it has to run
      // before the values are written, and restart_vpnc is what installs the ip rules - but only
      // for the profile vpnc_unit names, which is why the row is set first.
      final c = _client();
      final s = await _state(c);
      await _svc(c)
          .apply(base: s, changes: {}, reservationsToCreate: {}, newDefaultIndex: 5);

      final steps = c.commands
          .where((cmd) =>
              cmd.contains('vpnc_unit') ||
              cmd.contains('stop_vpnc') ||
              cmd.contains('restart_default_wan') ||
              cmd.contains('vpnc_default_wan=') ||
              cmd.contains('wgc_unit') ||
              cmd == 'nvram commit' ||
              cmd.contains('restart_vpnc'))
          .toList();
      expect(steps, [
        'nvram set vpnc_unit=1', // pia-aus_perth is clientlist ROW 1
        'service stop_vpnc',
        'service restart_default_wan',
        'nvram set vpnc_default_wan=5', // index 6
        'nvram set wgc_unit=5', // SLOT number
        'nvram commit',
        'service restart_vpnc',
      ]);
    });

    test('the key is written AFTER restart_default_wan, never before', () async {
      // The single fact that took the longest to find: writing it first always ended with 0.
      final c = _client();
      final s = await _state(c);
      await _svc(c)
          .apply(base: s, changes: {}, reservationsToCreate: {}, newDefaultIndex: 5);
      final wan = c.commands.indexWhere((cmd) => cmd == 'service restart_default_wan');
      final key = c.commands.indexWhere((cmd) => cmd.startsWith('nvram set vpnc_default_wan='));
      expect(wan, lessThan(key), reason: 'restart_default_wan resets the key, so it must run first');
    });

    test('a device-only apply does NOT touch the tunnels', () async {
      // The whole point of keeping the two apart: assigning a device is instant and invisible.
      final c = _client();
      final s = await _state(c);
      await _svc(c)
          .apply(base: s, changes: {'192.168.1.20': 5}, reservationsToCreate: {});
      // Exact matches: 'restart_vpnc' is a substring of 'restart_vpnc_dev_policy', which a
      // device-only apply DOES call.
      expect(c.commands.contains('service stop_vpnc'), isFalse);
      expect(c.commands.contains('service restart_vpnc'), isFalse);
      expect(c.commands.contains('service restart_default_wan'), isFalse);
      expect(c.commands.contains('service restart_vpnc_dev_policy'), isTrue, reason: 'the light pair still runs');
    });

    test('no default change means no default_wan write at all', () async {
      final c = _client();
      final s = await _state(c);
      await _svc(c)
          .apply(base: s, changes: {'192.168.1.20': 5}, reservationsToCreate: {});
      // The batched read mentions the key, so this must look for the WRITE specifically.
      expect(c.ran('nvram set vpnc_default_wan'), isFalse);
      expect(c.ran('restart_default_wan'), isFalse);
    });
  });
}
