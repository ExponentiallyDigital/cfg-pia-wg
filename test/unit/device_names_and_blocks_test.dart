// test/unit/device_names_and_blocks_test.dart - renaming a device, and disabling its internet (ID-261).
//
// Pure functions against the router's own formats, as measured on hardware on 2026-09-28. The
// fixtures are the values the web interface wrote then, with the MACs and names replaced.
//
// MACs are invented - see test/unit/no_lan_identifiers_test.dart.
import 'package:cfg_pia_wg/device_assignment.dart';
import 'package:flutter_test/flutter_test.dart';

const _tablet = '11:22:33:44:55:66';
const _console = '22:33:44:55:66:77';

void main() {
  group('a device name', () {
    test('may be anything the web interface accepts: spaces, an apostrophe, an ampersand, 32 characters', () {
      expect(checkDeviceName('Kids tablet'), isNull);
      expect(checkDeviceName("Andrew's & co"), isNull);
      expect(checkDeviceName('x' * kMaxDeviceNameLength), isNull);
    });

    test('may be empty, which shows the detected name again', () {
      expect(checkDeviceName(''), isNull);
      expect(checkDeviceName('   '), isNull);
    });

    test('may not hold the list delimiters, or run past 32 characters', () {
      expect(checkDeviceName('a<b'), contains('< or >'));
      expect(checkDeviceName('a>b'), contains('< or >'));
      expect(checkDeviceName('x' * (kMaxDeviceNameLength + 1)), contains('32'));
    });
  });

  group('setCustomName', () {
    const list = '<NAS>AA:BB:CC:00:00:01>0>4>>>><Tablet>$_tablet>0>20>>>><Console>$_console>0>75>>>>';

    test('renames a device in place, keeping its other fields and every other record', () {
      expect(setCustomName(list, mac: _tablet, name: 'Kids tablet'),
          '<NAS>AA:BB:CC:00:00:01>0>4>>>><Kids tablet>$_tablet>0>20>>>><Console>$_console>0>75>>>>');
    });

    test('stores the name as typed, not percent-encoded', () {
      expect(setCustomName(list, mac: _tablet, name: "Andrew's & co"), contains("<Andrew's & co>$_tablet>"));
    });

    test("an empty name removes the record, so the router shows the detected name", () {
      expect(setCustomName(list, mac: _tablet, name: ''), '<NAS>AA:BB:CC:00:00:01>0>4>>>><Console>$_console>0>75>>>>');
    });

    test('a device with no record gets one shaped like the web interface writes, with its type', () {
      expect(setCustomName(list, mac: '33:44:55:66:77:88', name: 'Laptop', type: '9'),
          endsWith('<Laptop>33:44:55:66:77:88>0>9>>>>'));
    });

    test('a device with no type gets 0, and a MAC is matched whatever its case', () {
      expect(setCustomName('', mac: '33:44:55:66:77:88', name: 'Laptop'), '<Laptop>33:44:55:66:77:88>0>0>>>>');
      expect(setCustomName(list, mac: _tablet.toLowerCase(), name: 'T'), contains('<T>$_tablet>0>20>'));
    });

    test('clearing the only record leaves the key empty', () {
      expect(setCustomName('<Tablet>$_tablet>0>20>>>>', mac: _tablet, name: ''), '');
    });
  });

  group('Time Scheduling, as run 4 measured it', () {
    // Run 4: TABLET added first and set to block, CONSOLE second and set to disable.
    final twoDevices = {
      'MULTIFILTER_ALL': '1',
      'MULTIFILTER_MAC': '$_tablet>$_console',
      'MULTIFILTER_DEVICENAME': 'Tablet>Console',
      'MULTIFILTER_ENABLE': '2>0',
      'MULTIFILTER_MACFILTER_DAYTIME_V2': '$kParentalDefaultSchedule>$kParentalDefaultSchedule',
    };

    test('parses the parallel lists in order', () {
      final pc = parseParentalControls(twoDevices);
      expect(pc.on, isTrue);
      expect([for (final e in pc.entries) e.name], ['Tablet', 'Console']);
      expect([for (final e in pc.entries) e.mode], ['2', '0']);
      expect(pc.entries.first.schedule, kParentalDefaultSchedule);
    });

    test('a device set to block has no internet; one set to disable still does', () {
      final pc = parseParentalControls(twoDevices);
      expect(pc.isBlocked(_tablet), isTrue);
      expect(pc.isBlocked(_console), isFalse);
      expect(pc.isBlocked('33:44:55:66:77:88'), isFalse);
    });

    test('with Time Scheduling off, nothing is blocked whatever the entries say', () {
      final pc = parseParentalControls({...twoDevices, 'MULTIFILTER_ALL': '0'});
      expect(pc.isBlocked(_tablet), isFalse);
    });

    test('writes back exactly what it read', () {
      expect(parseParentalControls(twoDevices).toNvram(), twoDevices);
    });

    test('empty keys are an empty list, and a short list is padded rather than misaligned', () {
      expect(parseParentalControls(const {}).entries, isEmpty);
      final pc = parseParentalControls({'MULTIFILTER_MAC': '$_tablet>$_console', 'MULTIFILTER_ENABLE': '2'});
      expect(pc.entries[1].mode, '0');
      expect(pc.entries[1].name, '');
    });
  });

  group('applyBlocks', () {
    test('disabling a device with no entry adds one at the end, as the web interface does, and turns Time Scheduling on',
        () {
      final after = applyBlocks(ParentalControls.empty, {_tablet: true}, names: {_tablet: 'Tablet'});
      expect(after.toNvram(), {
        'MULTIFILTER_ALL': '1',
        'MULTIFILTER_MAC': _tablet,
        'MULTIFILTER_DEVICENAME': 'Tablet',
        'MULTIFILTER_ENABLE': '2',
        'MULTIFILTER_MACFILTER_DAYTIME_V2': kParentalDefaultSchedule,
      });
    });

    test('enabling it again removes the entry, and Time Scheduling goes off with nothing left in it', () {
      final blocked = applyBlocks(ParentalControls.empty, {_tablet: true}, names: {_tablet: 'Tablet'});
      final after = applyBlocks(blocked, {_tablet: false});
      expect(after.entries, isEmpty);
      expect(after.on, isFalse);
    });

    test('every other entry is left exactly as it was', () {
      final pc = parseParentalControls({
        'MULTIFILTER_ALL': '1',
        'MULTIFILTER_MAC': _console,
        'MULTIFILTER_DEVICENAME': 'Console',
        'MULTIFILTER_ENABLE': '1',
        'MULTIFILTER_MACFILTER_DAYTIME_V2': 'W01E08001700',
      });
      final after = applyBlocks(pc, {_tablet: true}, names: {_tablet: 'Tablet'});
      expect(after.entries.first.mac, _console);
      expect(after.entries.first.mode, '1');
      expect(after.entries.first.schedule, 'W01E08001700');
      expect(after.entries.last.mac, _tablet);
    });

    test("disabling a device someone scheduled keeps its schedule, and enabling it keeps the entry at disable", () {
      final pc = parseParentalControls({
        'MULTIFILTER_ALL': '1',
        'MULTIFILTER_MAC': _console,
        'MULTIFILTER_DEVICENAME': 'Console',
        'MULTIFILTER_ENABLE': '1',
        'MULTIFILTER_MACFILTER_DAYTIME_V2': 'W01E08001700',
      });
      final blocked = applyBlocks(pc, {_console: true});
      expect(blocked.entries.single.mode, kParentalBlock);
      expect(blocked.entries.single.schedule, 'W01E08001700');
      final enabled = applyBlocks(blocked, {_console: false});
      expect(enabled.entries.single.mode, '0', reason: 'a schedule set up by hand is kept for them');
      expect(enabled.on, isTrue);
    });

    test('a name with the list delimiters in it cannot break the lists', () {
      final after = applyBlocks(ParentalControls.empty, {_tablet: true}, names: {_tablet: 'a<b>c'});
      expect(after.entries.single.name, 'abc');
    });
  });

  group('schedulesSwitchedOn', () {
    final offWithSchedule = parseParentalControls({
      'MULTIFILTER_ALL': '0',
      'MULTIFILTER_MAC': '$_console>AA:BB:CC:00:00:01',
      'MULTIFILTER_DEVICENAME': 'Console>NAS',
      'MULTIFILTER_ENABLE': '1>0',
      'MULTIFILTER_MACFILTER_DAYTIME_V2': 'W01E08001700>W01E08001700',
    });

    test('names the schedules left off that disabling a device would put into force', () {
      final after = applyBlocks(offWithSchedule, {_tablet: true});
      final on = schedulesSwitchedOn(offWithSchedule, after, {_tablet});
      expect([for (final e in on) e.name], ['Console'], reason: 'NAS is at disable, so nothing comes into force');
    });

    test('says nothing when Time Scheduling was already on, or had nothing else in it', () {
      final alreadyOn = parseParentalControls({
        'MULTIFILTER_ALL': '1',
        'MULTIFILTER_MAC': _console,
        'MULTIFILTER_DEVICENAME': 'Console',
        'MULTIFILTER_ENABLE': '1',
        'MULTIFILTER_MACFILTER_DAYTIME_V2': 'W01E08001700',
      });
      expect(schedulesSwitchedOn(alreadyOn, applyBlocks(alreadyOn, {_tablet: true}), {_tablet}), isEmpty);
      expect(schedulesSwitchedOn(ParentalControls.empty, applyBlocks(ParentalControls.empty, {_tablet: true}), {_tablet}),
          isEmpty);
    });
  });

  group('the device list', () {
    test("custom_clientlist's name wins over the cache's, which lags a rename", () {
      final devices = buildDeviceList(
        nmpClJson: '{"$_tablet":{"name":"android-1","online":1,"type":20}}',
        nmpCache: '{"$_tablet":{"nickName":"Old name","ip":"192.168.1.20","isOnline":"1","type":"20"}}',
        customClientlist: '<New name>$_tablet>0>20>>>>',
        dhcpStaticlist: '',
        cfgDeviceList: '',
      );
      expect(devices.single.displayName, 'New name');
      expect(devices.single.type, '20');
    });
  });
}
