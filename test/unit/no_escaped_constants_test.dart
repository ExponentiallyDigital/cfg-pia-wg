// test/unit/no_escaped_constants_test.dart - a Dart constant must not be sent to the router as text.
//
// Reported: a running watchdog showed as PAUSED. The probe contained '\$kRouterAppDir', so the
// ROUTER was asked to expand a Dart constant it knows nothing about; it expanded to nothing and the
// file test always failed. `\$` in a shell command string is nearly always this mistake - the
// author meant Dart interpolation and escaped it by accident.
//
// A shell variable the router SHOULD expand is written in a raw string (r'...$IFACE'), which needs
// no backslash, so a legitimate case does not look like this one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no command string escapes a dollar in front of a Dart constant or variable', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        // \$ followed by a lower-case k (a constant) or a lower-case identifier: Dart naming.
        // Shell variables in this codebase are upper-case ($IFACE, $SLOT, $BEST_IP).
        // Both escapes matter. r'\\$' is a literal backslash followed by the end-of-string ANCHOR,
        // which nothing can follow - written that way the guard matched nothing and passed
        // vacuously, missing a real one in session_controller.dart in 406.
        if (RegExp(r'\\\$[a-z]').hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'these reach the router as literal text - drop the backslash to interpolate in Dart');
  });
}
