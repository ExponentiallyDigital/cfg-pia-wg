// test/unit/device_list_join_test.dart - joining the router's four device sources into one list.
//
// The fixtures are shaped exactly like the router's, including the two things that were found only
// by running it: the non-device keys `nmp_cache.js` mixes in among the MAC-keyed ones, and the
// /jffs inventory's `online` lagging the web interface by minutes (ID-165).
//
// MACs here are invented - see test/unit/no_lan_identifiers_test.dart.
import 'package:cfg_pia_wg/device_assignment.dart';
import 'package:flutter_test/flutter_test.dart';

const _nmpClJson = '''
{
  "11:22:33:44:55:66": {"mac":"11:22:33:44:55:66","name":"console","vendor":"MS","type":0,"online":0,"conn_ts":0},
  "22:33:44:55:66:77": {"mac":"22:33:44:55:66:77","name":"laptop","vendor":"Dell","type":9,"online":1,"conn_ts":1788851904},
  "33:44:55:66:77:88": {"mac":"33:44:55:66:77:88","name":"meshnode","vendor":"Asus","type":24,"online":1,"conn_ts":0}
}''';

// The console is off in both. The cache is the web interface's source, and wins where they differ.
const _nmpCache = '''
{
  "maclist": ["11:22:33:44:55:66","22:33:44:55:66:77","33:44:55:66:77:88"],
  "ClientAPILevel": "5",
  "11:22:33:44:55:66": {"name":"console","nickName":"Console","ip":"192.168.1.87","isOnline":"0","type":"76"},
  "22:33:44:55:66:77": {"name":"laptop","nickName":"","ip":"192.168.1.20","isOnline":"1","type":"9"},
  "33:44:55:66:77:88": {"name":"meshnode","nickName":"","ip":"192.168.1.90","isOnline":"1","type":"24"}
}''';

const _customClientlist = 'Console>11:22:33:44:55:66>0>76>>>>>';
const _dhcpStaticlist = '<11:22:33:44:55:66>192.168.1.87>>Console<44:55:66:77:88:99>192.168.1.40>>Absent';

// The router (flag 1) and one mesh node (flag 0).
const _cfgDeviceList = '<RT-ABCD>192.168.1.1>AA:BB:CC:DD:EE:FF>1<RT-EFGH>192.168.1.90>33:44:55:66:77:88>0';

List<LanDevice> _join({String? cache}) => buildDeviceList(
      nmpClJson: _nmpClJson,
      nmpCache: cache ?? _nmpCache,
      customClientlist: _customClientlist,
      dhcpStaticlist: _dhcpStaticlist,
      cfgDeviceList: _cfgDeviceList,
    );

void main() {
  group('parseDeviceJson', () {
    test('SKIPS the non-device keys nmp_cache.js mixes in', () {
      // `maclist` is an array and `ClientAPILevel` a string. Assuming every value is a device
      // object throws on a real router - which is exactly how this was found.
      final parsed = parseDeviceJson(_nmpCache);
      expect(parsed.keys, isNot(contains('MACLIST')));
      expect(parsed.keys, isNot(contains('CLIENTAPILEVEL')));
      expect(parsed.length, 3);
    });

    test('malformed or empty input yields an empty map rather than throwing', () {
      // /tmp/nmp_cache.js may simply not be there. The screen must degrade, not break.
      expect(parseDeviceJson(''), isEmpty);
      expect(parseDeviceJson('not json at all'), isEmpty);
      expect(parseDeviceJson('[1,2,3]'), isEmpty);
    });

    test('keys are upper-cased, so the join needs no normalisation', () {
      expect(parseDeviceJson('{"aa:bb:cc:dd:ee:ff":{"x":1}}').keys.single, 'AA:BB:CC:DD:EE:FF');
    });
  });

  group('the NVRAM list parsers', () {
    test('dhcp_staticlist gives MAC to reserved IP', () {
      final r = parseDhcpStaticlist(_dhcpStaticlist);
      expect(r['11:22:33:44:55:66'], '192.168.1.87');
      expect(r.length, 2);
    });

    test('custom_clientlist gives MAC to the user name, tolerating short records', () {
      // Records run from six to nine fields on a real router.
      final r = parseCustomClientlistNames('A>11:22:33:44:55:66>0>4>>>>><B>22:33:44:55:66:77>0>9>>');
      expect(r['11:22:33:44:55:66'], 'A');
      expect(r['22:33:44:55:66:77'], 'B');
    });

    test('cfg_device_list gives every MAC to exclude, router and node alike', () {
      expect(parseCfgDeviceListMacs(_cfgDeviceList), {'AA:BB:CC:DD:EE:FF', '33:44:55:66:77:88'});
    });

    test('empty lists parse to nothing', () {
      expect(parseDhcpStaticlist(''), isEmpty);
      expect(parseCustomClientlistNames(''), isEmpty);
      expect(parseCfgDeviceListMacs(''), isEmpty);
    });
  });

  group('buildDeviceList', () {
    test('THE MESH NODE AND THE ROUTER ARE EXCLUDED', () {
      // Without cfg_device_list a mesh node is indistinguishable from a laptop - it carries
      // isGateway "0" in nmp_cache.js exactly like an ordinary client.
      final macs = _join().map((d) => d.mac).toList();
      expect(macs, isNot(contains('33:44:55:66:77:88')), reason: 'mesh node');
      expect(macs, isNot(contains('AA:BB:CC:DD:EE:FF')), reason: 'router');
      expect(macs.length, 2);
    });

    // ID-165, measured 2026-09-27: the web interface and the cache changed within a second of each
    // other; the /jffs inventory was 8.5 minutes late going offline and 3 late coming back.
    test("online comes from the cache, the web interface's source, where the two disagree", () {
      LanDevice join(String inv, String cache) => buildDeviceList(
            nmpClJson: '{"AA:BB:CC:00:00:01":{"name":"tablet","online":$inv}}',
            nmpCache: '{"AA:BB:CC:00:00:01":{"name":"tablet","ip":"192.168.1.30","isOnline":"$cache"}}',
            customClientlist: '',
            dhcpStaticlist: '',
            cfgDeviceList: '',
          ).single;
      expect(join('1', '0').online, isFalse, reason: 'switched off: the inventory has not caught up');
      expect(join('0', '1').online, isTrue, reason: 'switched back on: the same lag the other way');
    });

    test('a device the cache does not list takes its state from the inventory', () {
      final d = buildDeviceList(
        nmpClJson: '{"AA:BB:CC:00:00:01":{"name":"ghost","online":0}}',
        nmpCache: '{"maclist":[],"ClientAPILevel":"5"}',
        customClientlist: '',
        dhcpStaticlist: '<AA:BB:CC:00:00:01>192.168.1.31>>Ghost',
        cfgDeviceList: '',
      ).single;
      expect(d.online, isFalse);
    });

    test('an OFFLINE device keeps its address and stays assignable', () {
      final box = _join().firstWhere((d) => d.mac == '11:22:33:44:55:66');
      expect(box.ip, '192.168.1.87');
      expect(box.assignable, isTrue);
    });

    test('nickName wins over the detected name', () {
      expect(_join().firstWhere((d) => d.mac == '11:22:33:44:55:66').displayName, 'Console');
    });

    test('an empty nickName falls through to the detected name', () {
      expect(_join().firstWhere((d) => d.mac == '22:33:44:55:66:77').displayName, 'laptop');
    });

    test('reserved comes from dhcp_staticlist membership', () {
      final devices = _join();
      expect(devices.firstWhere((d) => d.mac == '11:22:33:44:55:66').reserved, isTrue);
      expect(devices.firstWhere((d) => d.mac == '22:33:44:55:66:77').reserved, isFalse);
    });

    test('with no /tmp cache, the reservation supplies the address', () {
      // /tmp is rebuilt at boot, so a device that has not connected since has no cache entry. A
      // reserved one still has an address; an unreserved one has none at all and cannot be
      // assigned, because the policy record is keyed by IP.
      final devices = _join(cache: '');
      final box = devices.firstWhere((d) => d.mac == '11:22:33:44:55:66');
      expect(box.ip, '192.168.1.87', reason: 'from dhcp_staticlist');
      expect(box.customName, 'Console', reason: 'from custom_clientlist');

      final laptop = devices.firstWhere((d) => d.mac == '22:33:44:55:66:77');
      expect(laptop.ip, isNull);
      expect(laptop.assignable, isFalse, reason: 'unreserved, and no cached address to fall back on');
    });

    // Online first, then by name. 'Console' sorts before 'laptop' alphabetically but is offline,
    // so it sinks - scrolling past greyed rows to reach a device that is actually there was the
    // common case on a list this long.
    test('the result comes back sorted, online devices first', () {
      expect(_join().map((d) => d.displayName).toList(), ['laptop', 'Console']);
    });

    test('a device known only to the cache is still listed', () {
      // The two files agreed on the test router, but one that knows a device the other does not
      // should be listed rather than silently dropped.
      final devices = buildDeviceList(
        nmpClJson: '{}',
        nmpCache: '{"55:66:77:88:99:AA":{"nickName":"Only","ip":"192.168.1.5"}}',
        customClientlist: '',
        dhcpStaticlist: '',
        cfgDeviceList: '',
      );
      expect(devices.single.displayName, 'Only');
      expect(devices.single.online, isTrue, reason: 'unknown liveness is not reported as offline');
    });
  });
}
