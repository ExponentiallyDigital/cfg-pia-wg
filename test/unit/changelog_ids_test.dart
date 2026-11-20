// Every work item carries an ID, as CHANGE-PROCESS.md says.
//
// Builds 555 to 558 shipped nine items without one: work found and done in the same pass was written as a
// note, not an item, and nothing checked (2026-11-02). Two kinds of line record what happened rather than
// work and are exempt: a release result and an audit line. Builds 541 to 552 keep some ID-free items from
// before this test, so it starts at 553. Since ID-635 the items not yet done live in BACKLOG.md's Current
// Release and Next Release, so they are read there, and the done items in CHANGELOG.md's release blocks.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The first release block the rule is checked in.
const int kFirstCheckedBuild = 553;

final RegExp _withId = RegExp(r'^- ID-\d{3,} [A-Z]{2,6}:');
final RegExp _releaseResult = RegExp(r'^- REL: v\d+\.\d+\.\d+ \(\d+\) ');
final RegExp _auditLine = RegExp(r'^- CHG: (WIP|1\.1|BACKLOG) ');
final RegExp _blockHeader = RegExp(r'^\d{4}-\d\d-\d\d v\d+\.\d+\.\d+ build (\d+) - ');

/// The BACKLOG.md sections whose items are checked: the two release sections.
bool isCheckedBacklogHeading(String line) => line.startsWith('## 1. Current Release') || line.startsWith('## 2. Next Release');

/// Each top-level bullet in [text] that is neither an item with an ID nor an exempt record, with its line number:
/// those in a checked BACKLOG.md section, and those in a release block from [kFirstCheckedBuild] on.
List<String> itemsWithoutId(String text) {
  final out = <String>[];
  var checking = false;
  final lines = text.split(RegExp(r'\r?\n'));
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('## ')) checking = isCheckedBacklogHeading(line);
    final header = _blockHeader.firstMatch(line);
    if (header != null) checking = int.parse(header.group(1)!) >= kFirstCheckedBuild;
    if (!checking || !line.startsWith('- ')) continue;
    if (_withId.hasMatch(line) || _releaseResult.hasMatch(line) || _auditLine.hasMatch(line)) continue;
    out.add('line ${i + 1}: ${line.length > 80 ? line.substring(0, 80) : line}');
  }
  return out;
}

void main() {
  test('every CHANGELOG work item from build $kFirstCheckedBuild on has an ID', () {
    final found = itemsWithoutId(File('CHANGELOG.md').readAsStringSync());
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('every item in BACKLOG.md Current Release and Next Release has an ID', () {
    final text = File('BACKLOG.md').readAsStringSync();
    expect(text, contains('## 1. Current Release'), reason: 'the section is found');
    expect(text, contains('## 2. Next Release'), reason: 'and so is the next one');
    final found = itemsWithoutId(text);
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('control: an item without an ID is caught, in a release section and in a block', () {
    const text = '## 1. Current Release\n\n- FIX: no ID\n\n## 1. Implemented\n\n'
        '2026-11-02 v0.8.188 build 558 - x\n\n- DOC: no ID either\n';
    expect(itemsWithoutId(text), ['line 3: - FIX: no ID', 'line 9: - DOC: no ID either']);
  });

  test('control: items parked in a section that is not checked, release results, audit lines and older blocks pass', () {
    const text = '## 3. Backlog\n\n- FTR: parked, no ID yet\n\n## 4. New work items\n\n- an idea\n\n'
        '## 1. Implemented\n\n'
        '2026-11-02 v0.8.188 build 558 - x\n\n'
        '- REL: v0.8.187 (557) passed 2026-11-02 (run 1): Android\n'
        '- CHG: WIP 8 -> 9 bullets. Added: ID-492.\n'
        '- ID-503 DOC: an item\n'
        '  - Closed 2026-11-02: evidence.\n\n'
        '2026-10-25 v0.8.172 build 542 - y\n\n- CHG: from before the test\n';
    expect(itemsWithoutId(text), isEmpty);
  });

  test('control: a planned REL item still needs its ID', () {
    const text = '## 2. Next Release\n\n- REL: the first App Store submission is approved\n';
    expect(itemsWithoutId(text), ['line 3: - REL: the first App Store submission is approved']);
  });
}
