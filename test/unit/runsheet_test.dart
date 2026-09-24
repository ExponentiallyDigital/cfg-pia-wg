// test/unit/runsheet_test.dart - the run sheet holds everything a person must do, and nothing else (ID-204).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/runsheet.dart';

const _doc = '''# Testing

# Part 1. Run sheet

## <a name='how-to-use'></a>How to use the run sheet

```bash
T=192.168.1.20   # TABLET's address
D=192.168.1.30   # DESKTOP's address
```

## <a name='aaa'></a>AAA. First group

**Slots:** wgc1 up.

**AAA-1** By hand [hand]

- Do: something.

**AAA-2** Checked by a script [script]

- Do: `sh /jffs/e2e.sh AAA-2 before`

**AAA-3** Covered by CI [ci]

- Covered by `test/unit/x_test.dart`.

---

## <a name='bbb'></a>BBB. All automated

**BBB-1** Gone [retired]

- Retired.

---

# Part 2. Reference

**ZZZ-1** Not a test [hand]
''';

void main() {
  group('extractRunsheet', () {
    final out = extractRunsheet(_doc, vars: {'T': '192.0.2.7'});

    test('keeps the hand and script tests, in order, each with a Result line', () {
      expect(out.indexOf('**AAA-1**'), lessThan(out.indexOf('**AAA-2**')));
      expect(RegExp(r'- Result:').allMatches(out), hasLength(2));
    });

    test('leaves out what a machine already runs, and Part 2', () {
      expect(out, isNot(contains('AAA-3')));
      expect(out, isNot(contains('BBB')), reason: 'a group with nothing left to do is left out whole');
      expect(out, isNot(contains('ZZZ-1')));
    });

    test("keeps each group's start state", () {
      expect(out, contains('## <a name=\'aaa\'></a>AAA. First group\n\n**Slots:** wgc1 up.'));
    });

    test('fills in the shell variables it is given, and leaves the rest', () {
      expect(out, contains('T=192.0.2.7   # TABLET'));
      expect(out, contains('D=192.168.1.30'));
    });
  });

  group('readTests refuses a sheet that would lose a test', () {
    test('a title with no tag', () {
      expect(() => readTests(_doc.replaceFirst('By hand [hand]', 'By hand')), throwsFormatException);
    });

    test('a label used twice', () {
      expect(() => readTests(_doc.replaceFirst('**AAA-2**', '**AAA-1**')), throwsFormatException);
    });
  });

  group('TESTING.md', () {
    final md = File('TESTING.md').readAsStringSync();

    test('every test is tagged, and every label is used once', () {
      expect(readTests(md).length, greaterThan(150));
    });

    // A [ci] tag takes a test off the run sheet, so it has to say where the automated one is.
    test('every [ci] test names an automated test file that exists', () {
      final part1 = md.substring(md.indexOf('# Part 1. Run sheet'), md.indexOf('# Part 2. Reference'));
      for (final t in readTests(md).where((t) => t.tier == Tier.ci)) {
        final start = part1.indexOf('**${t.label}**');
        final next = part1.indexOf(RegExp(r'\n\*\*[A-Z]{2,3}-\d+\*\*|\n## '), start + 1);
        final body = part1.substring(start, next < 0 ? part1.length : next);
        final files = RegExp(r'test/[\w/]+_test\.dart').allMatches(body).map((m) => m.group(0)!).toList();
        expect(files, isNotEmpty, reason: '${t.label} is [ci] but names no test file');
        for (final f in files) {
          expect(File(f).existsSync(), isTrue, reason: '${t.label} names $f, which does not exist');
        }
      }
    });

    test('the run sheet extracts', () {
      final sheet = extractRunsheet(md);
      expect(sheet, contains('**PRE-5**'));
      expect(sheet, isNot(contains('# Part 2')));
    });
  });
}
