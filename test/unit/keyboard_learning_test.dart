// Every text field tells the keyboard not to learn from what is typed (ID-314).
//
// SECURITY.md and the Play listing said keyboard learning was off in every sensitive field, but only
// autocorrect and suggestions were: `enableIMEPersonalizedLearning` defaults to true and was never
// set, so Android's keyboard was never sent IME_FLAG_NO_PERSONALIZED_LEARNING (claims audit, #8).
// It is now set on every field in the app, not just the sensitive ones, so a new field cannot be
// the one that was missed.
//
// This is a source scan, a shape test: whether a given keyboard honours the flag is up to the
// keyboard. What it proves is that the app asks, on every field, which is what the docs claim.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every TextField and TextFormField in lib/ sets enableIMEPersonalizedLearning: false', () {
    final missing = <String>[];
    var fields = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      for (final m in RegExp(r'\b(TextField|TextFormField)\(').allMatches(s)) {
        fields++;
        // The constructor's own arguments: up to the matching close bracket.
        var depth = 1;
        var close = m.end;
        while (depth > 0 && close < s.length) {
          final c = s[close];
          if (c == '(') depth++;
          if (c == ')') depth--;
          close++;
        }
        if (!s.substring(m.end, close).contains('enableIMEPersonalizedLearning: false')) {
          final line = s.substring(0, m.start).split('\n').length;
          missing.add('${f.path}:$line');
        }
      }
    }
    expect(fields, greaterThan(10), reason: 'the scan found the fields');
    expect(missing, isEmpty);
  });
}
