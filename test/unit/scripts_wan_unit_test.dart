// test/unit/scripts_wan_unit_test.dart - the hardware scripts name the WAN unit carrying the traffic (ID-722).
//
// With the first WAN down and a phone on USB carrying the traffic (measured 2026-11-25), `wan0_ipaddr` read
// 0.0.0.0, `wan0_ifname` named a port with nothing on it and a script's `restart_wan_if 0` restarted the
// wrong WAN. Each script now reads the unit from `wan_primary`, and this fails when one reads wan0's keys
// or restarts unit 0 by hand again.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The lines of [script] that read a `wan0_` key or run `restart_wan_if 0`, as `line: text`, comments left out.
List<String> wanZeroReads(String script) {
  final found = <String>[];
  final lines = script.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('#')) continue;
    if (line.contains('wan0_') || line.contains('restart_wan_if 0')) found.add('${i + 1}: ${line.trim()}');
  }
  return found;
}

/// The one-line way each script finds the unit, so a script that uses it has defined it.
const _unitLine = r'WU="$(nvram get wan_primary)"; case "$WU" in 0 | 1) ;; *) WU=0 ;; esac';

void main() {
  final scripts = Directory('scripts').listSync().whereType<File>().where((f) => f.path.endsWith('.sh')).toList();

  group('the check itself', () {
    test('a script that reads wan0_ipaddr, wan0_ifname or restarts unit 0 by hand is found', () {
      expect(wanZeroReads('A="\$(nvram get wan0_ifname)"\nservice "restart_wan_if 0"\n'), hasLength(2));
    });

    test('a comment, and a script that uses the unit, are not found', () {
      expect(wanZeroReads('# wan0_ipaddr was the old way\nA="\$(nvram get wan\${WU}_ifname)"\nservice "restart_wan_if \$WU"\n'), isEmpty);
    });
  });

  test('there are scripts to check', () => expect(scripts.length, greaterThan(5)));

  for (final f in scripts) {
    final name = f.uri.pathSegments.last;
    final text = f.readAsStringSync();
    test('$name does not read wan0_ keys or restart unit 0 by hand', () {
      expect(wanZeroReads(text), isEmpty, reason: '$name must name the unit from wan_primary');
    });
    if (RegExp(r'wan\$\{?WU2?\}?|restart_wan_if \$WU').hasMatch(text)) {
      test('$name defines the unit before it uses it', () {
        expect(text.contains(_unitLine), isTrue, reason: '$name uses \$WU, so it must contain: $_unitLine');
        expect(text.indexOf(_unitLine), lessThan(text.indexOf(RegExp(r'wan\$\{?WU|restart_wan_if \$WU'))), reason: name);
      });
    }
  }
}
