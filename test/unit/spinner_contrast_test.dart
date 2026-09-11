// test/unit/spinner_contrast_test.dart - the "working" spinner has to be visible.
//
// Reported: the spinner was near-black in the watchdog dialog. Every in-button spinner appears
// while its button is DISABLED (onPressed is null during the work), so it sits on Material's
// disabled grey, not on the teal fill - and kOnPrimary (#12141A) is invisible there.
//
// A source scan rather than four timing-sensitive widget tests: catching the wrong constant is
// the whole point, and it is the constant that is easy to reintroduce by copying a neighbour.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no spinner is drawn in kOnPrimary or a hardcoded colour', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in RegExp(r'CircularProgressIndicator\([^)]*\)').allMatches(source)) {
        final call = match.group(0)!;
        if (!call.contains('color:')) {
          offenders.add('${file.path}: no colour at all');
        } else if (!call.contains('color: kHighlight')) {
          offenders.add('${file.path}: $call');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'spinners must be kHighlight so they show on a disabled button');
  });
}
