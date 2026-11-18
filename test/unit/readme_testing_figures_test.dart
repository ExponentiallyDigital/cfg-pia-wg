// test/unit/readme_testing_figures_test.dart - README's manual-test figures are TESTING.md's tags (ID-627).
//
// README section 2's Testing bullet states how many manual tests there are, how many need a script or a
// Play build, and how many used to be manual and are now automated. All of those can be counted from the
// tags at the end of TESTING.md's test headings, and on 2026-11-17 README said 190 manual tests where the
// tags gave 188, with nothing to say so. The automated count and the coverage can't be derived, so they
// stay a step in CLAUDE.md.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the tags in a TESTING.md say, counted the way CLAUDE.md says to: manual is [hand] plus [script].
class TestingCounts {
  TestingCounts(String testing) {
    final heading = RegExp(r'^\*\*([A-Z]+)-\d+[a-z]?\*\*.*\[([a-z ,]+)\]\s*$', multiLine: true);
    for (final m in heading.allMatches(testing)) {
      final group = m.group(1)!;
      final tag = m.group(2)!;
      if (tag == 'hand' || tag == 'script') {
        manual++;
        if (tag == 'script') script++;
        if (group == 'IOB') simulator++;
        if (group == 'LCK' || group == 'BUY') play++;
      } else if (tag == 'ci' || tag == 'live') {
        automated++;
      }
    }
  }

  int manual = 0, script = 0, simulator = 0, play = 0, automated = 0;
  int get realRouter => manual - simulator;
}

/// The figures in README's Testing bullet, or null when its sentence isn't found in the form below.
({int manual, int realRouter, int simulator, int script, int play, int automated})? readmeFigures(String readme) {
  final m = RegExp(
    r'(\d+) manual end-to-end tests, (\d+) of them on a real router and (\d+) in the iOS simulator - (\d+) of them with a script '
    r'on the router doing the checking, and (\d+) needing a build distributed by Play\. Another (\d+) that used to be manual',
  ).firstMatch(readme);
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i)!);
  return (manual: g(1), realRouter: g(2), simulator: g(3), script: g(4), play: g(5), automated: g(6));
}

void main() {
  test("README's manual, script, Play-build and once-manual figures are the counts of TESTING.md's tags", () {
    final counts = TestingCounts(File('TESTING.md').readAsStringSync());
    final figures = readmeFigures(File('README.md').readAsStringSync());
    expect(figures, isNotNull, reason: "README section 2's Testing bullet is in the form this test reads");
    expect(counts.manual, greaterThan(100), reason: "TESTING.md's headings are found");
    expect({
      'manual': figures!.manual,
      'on a real router': figures.realRouter,
      'in the iOS simulator': figures.simulator,
      'with a script': figures.script,
      'needing a Play build': figures.play,
      'once manual, now automated': figures.automated,
    }, {
      'manual': counts.manual,
      'on a real router': counts.realRouter,
      'in the iOS simulator': counts.simulator,
      'with a script': counts.script,
      'needing a Play build': counts.play,
      'once manual, now automated': counts.automated,
    }, reason: "Update README section 2's Testing bullet from TESTING.md's tags (CLAUDE.md): manual is [hand] plus [script].");
  });

  group('the reading of both files', () {
    test('the tags are counted by kind and by group', () {
      final c = TestingCounts('**SET-1** a [hand]\n**SET-2** b [script]\n**IOB-1** c [hand]\n**LCK-1** d [hand]\n'
          '**BUY-1** e [script]\n**NET-1** f [live]\n**RES-1** g [ci]\n**OLD-1** h [retired]\ntext **X-1** not a heading [hand]');
      expect((c.manual, c.script, c.simulator, c.play, c.automated, c.realRouter), (5, 2, 1, 2, 2, 4));
    });

    test('the sentence in README is read, and a README that changed shape is null, not zeros', () {
      const s = 'as at build 585, 2323 automated tests run, and 189 manual end-to-end tests, 185 of them on a real router and 4 in the iOS '
          'simulator - 24 of them with a script on the router doing the checking, and 13 needing a build distributed by Play. Another 26 '
          'that used to be manual are now automated.';
      expect(readmeFigures(s), (manual: 189, realRouter: 185, simulator: 4, script: 24, play: 13, automated: 26));
      expect(readmeFigures('189 manual tests'), isNull);
    });
  });
}
