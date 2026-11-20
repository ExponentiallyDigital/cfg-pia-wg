// test/unit/changelog_structure_test.dart - the work-item sections hold only work items (ID-627, ID-635).
//
// On 2026-11-17 a scripted edit turned the `\n` in `tr '<' '\n'` into a real line break. It split one
// bullet in two, and moving the item left the second half in 1.2 WIP, under no bullet at all.
// changelog_ids_test.dart counts IDs and could not see it; Andrew found it. BACKLOG.md's Current Release and
// Next Release (the old CHANGELOG 1.2 and 1.1, moved by ID-635) and every CHANGELOG release block from build
// 535 on (the form CHANGE-PROCESS.md says its blocks have, "Release blocks before build 535 keep their
// older, longer form") now fail if, after their first bullet, a line is neither a bullet, an indented line
// under one, a blank line, a heading, nor inside a code fence.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The first build whose release block is held to this form.
const int kFirstCheckedBuild = 535;

final RegExp _blockHeader = RegExp(r'^20\d\d-\d\d-\d\d v\d+\.\d+\.\d+ build (\d+) - ');

/// "line N: text" for each line, in the stretch [start, end) of [lines], that comes after the stretch's
/// first bullet and is not a bullet, an indented line, blank, a code fence's line or a heading.
List<String> fragmentLines(List<String> lines, int start, int end) {
  final found = <String>[];
  var seenBullet = false;
  var inFence = false;
  for (var i = start; i < end; i++) {
    final l = lines[i];
    if (l.trimLeft().startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence || l.trim().isEmpty) continue;
    if (l.startsWith('- ')) {
      seenBullet = true;
      continue;
    }
    if (!seenBullet) continue;
    // A group's introduction inside 1.1 ("Work items for the **next** release (requires ...):") is allowed.
    if (l.startsWith(' ') || l.startsWith('#') || l == '---' || l.startsWith('Work items for the ')) continue;
    final shown = l.length > 70 ? '${l.substring(0, 70)}...' : l;
    found.add('line ${i + 1}: $shown');
  }
  return found;
}

/// The names of the BACKLOG.md sections held to the form, as they are headed.
const List<String> kCheckedSections = ['Current Release', 'Next Release'];

/// The name of the checked section [line] opens, or null.
String? _checkedSection(String line) {
  for (final name in kCheckedSections) {
    if (RegExp('^## \\d+\\. $name').hasMatch(line)) return name;
  }
  return null;
}

/// Each (name, start, end) stretch of [lines] that is held to the form: BACKLOG.md's Current Release and Next
/// Release, and each CHANGELOG.md release block from [kFirstCheckedBuild] on. Any other `## ` heading ends a
/// stretch without being checked. Stretches are line ranges, so reports can name real lines.
List<({String name, int start, int end})> checkedStretches(List<String> lines) {
  final starts = <(int, String)>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.startsWith('## ') || _blockHeader.hasMatch(l)) starts.add((i, l));
  }
  final out = <({String name, int start, int end})>[];
  for (var k = 0; k < starts.length; k++) {
    final (at, head) = starts[k];
    final end = k + 1 < starts.length ? starts[k + 1].$1 : lines.length;
    final m = _blockHeader.firstMatch(head);
    final section = _checkedSection(head);
    if (m == null && section == null) continue;
    if (m != null && int.parse(m.group(1)!) < kFirstCheckedBuild) continue;
    out.add((name: m != null ? 'build ${m.group(1)}' : section!, start: at + 1, end: end));
  }
  return out;
}

void main() {
  const reason = 'A line that is not a bullet, indented under one, blank or a heading is a fragment, usually of a bullet split in two by '
      'a scripted edit. Edit the file with the Edit tool and read what was stored back (CONTEXT.md section 1).';

  test('BACKLOG.md Current Release and Next Release hold only bullets, their indented lines and fences', () {
    final lines = File('BACKLOG.md').readAsLinesSync();
    final stretches = checkedStretches(lines);
    expect(stretches.map((s) => s.name), containsAll(kCheckedSections), reason: 'the sections are found');
    final problems = [
      for (final s in stretches)
        for (final f in fragmentLines(lines, s.start, s.end)) '${s.name}: $f'
    ];
    expect(problems, isEmpty, reason: reason);
  });

  test("every CHANGELOG.md release block from build $kFirstCheckedBuild holds only bullets, their indented lines and fences", () {
    final lines = File('CHANGELOG.md').readAsLinesSync();
    final stretches = checkedStretches(lines);
    expect(stretches.length, greaterThan(10), reason: 'the release blocks are found');
    final problems = [
      for (final s in stretches)
        for (final f in fragmentLines(lines, s.start, s.end)) '${s.name}: $f'
    ];
    expect(problems, isEmpty, reason: reason);
  });

  group('the check itself', () {
    List<String> lines(String s) => s.split('\n');

    test('a bullet split in two leaves a fragment, and it is named by its line', () {
      final l = lines("- ID-1 BUG: run `tr '<' '\n  - DoD: x\n' < file`, then it passes\n- ID-2 BUG: next");
      expect(fragmentLines(l, 0, l.length), ["line 3: ' < file`, then it passes"]);
    });

    test('bullets, indented lines, blank lines, headings and a rule are fine', () {
      final l = lines('Some prose first.\n\n- ID-1 BUG: a\n  - DoD: b\n    deeper\n\n### 1.3. Next\n---\n- ID-2 BUG: c');
      expect(fragmentLines(l, 0, l.length), isEmpty);
    });

    test('prose before the first bullet is allowed, since a section and a release block may open with it', () {
      final l = lines('Work items for the next release:\nand a second line of intro\n\n- ID-1 BUG: a');
      expect(fragmentLines(l, 0, l.length), isEmpty);
    });

    test('a group introduction between bullets in 1.1 is allowed, and any other loose line is not', () {
      final l = lines('- ID-1 BUG: a\n\nWork items for the **next** release (needs stock):\n\n- ID-2 BUG: b\nloose words');
      expect(fragmentLines(l, 0, l.length), ['line 6: loose words']);
    });

    test('the text inside a code fence is not checked, as in a Play note', () {
      final l = lines('- ID-1 BUG: a\n```play\n• one\nNot a bullet\n```\n- ID-2 BUG: b');
      expect(fragmentLines(l, 0, l.length), isEmpty);
    });

    test('release blocks before build 535 keep their older form, and an unchecked section is not a stretch', () {
      final l = lines('## 1. Current Release\n- a\n## 3. Backlog\n- b\nloose\n## 1. Implemented\n'
          '2026-09-01 v0.8.1 build 500 - old\n- a\nloose\n2026-10-25 v0.8.179 build 549 - new\n- a\n  - b');
      final names = checkedStretches(l).map((s) => s.name).toList();
      expect(names, ['Current Release', 'build 549']);
    });

    test('the sections are found whatever number they carry', () {
      final l = lines('## 2. Next Release\n- a\nloose words');
      final names = checkedStretches(l).map((s) => s.name).toList();
      expect(names, ['Next Release']);
      expect(fragmentLines(l, 1, l.length), ['line 3: loose words']);
    });
  });
}
