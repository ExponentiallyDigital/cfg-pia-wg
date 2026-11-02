// Every CHANGELOG work item carries an ID, as the file's own rule says.
//
// Builds 555 to 558 shipped nine items without one: work found and done in the same pass was written as a
// note, not an item, and nothing checked (2026-11-02). Two kinds of line record what happened rather than
// work and are exempt: a release result and an audit line. Builds 541 to 552 keep some ID-free items from
// before this test, so it starts at 553.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The first release block the rule is checked in.
const int kFirstCheckedBuild = 553;

final RegExp _withId = RegExp(r'^- ID-\d{3,} [A-Z]{2,6}:');
final RegExp _releaseResult = RegExp(r'^- REL: v\d+\.\d+\.\d+ \(\d+\) ');
final RegExp _auditLine = RegExp(r'^- CHG: (WIP|1\.1|BACKLOG) ');
final RegExp _blockHeader = RegExp(r'^\d{4}-\d\d-\d\d v\d+\.\d+\.\d+ build (\d+) - ');

/// Each top-level bullet in [changelog]'s 1.1, 1.2 and release blocks from [kFirstCheckedBuild] on that
/// is neither an item with an ID nor an exempt record, with its line number.
List<String> itemsWithoutId(String changelog) {
  final out = <String>[];
  var checking = false;
  final lines = changelog.split(RegExp(r'\r?\n'));
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('### 1.1.') || line.startsWith('### 1.2.')) {
      checking = true;
    } else if (line.startsWith('### 1.3.')) {
      checking = false;
    }
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

  test('control: an item without an ID is caught, in a block and in WIP', () {
    const text = '### 1.2. WIP\n\n- FIX: no ID\n\n### 1.3. Implemented\n\n'
        '2026-11-02 v0.8.188 build 558 - x\n\n- DOC: no ID either\n';
    expect(itemsWithoutId(text), ['line 3: - FIX: no ID', 'line 9: - DOC: no ID either']);
  });

  test('control: release results, audit lines, sub-bullets and older blocks pass', () {
    const text = '### 1.3. Implemented\n\n'
        '2026-11-02 v0.8.188 build 558 - x\n\n'
        '- REL: v0.8.187 (557) passed 2026-11-02 (run 1): Android\n'
        '- CHG: WIP 8 -> 9 bullets. Added: ID-492.\n'
        '- ID-503 DOC: an item\n'
        '  - Closed 2026-11-02: evidence.\n\n'
        '2026-10-25 v0.8.172 build 542 - y\n\n- CHG: from before the test\n';
    expect(itemsWithoutId(text), isEmpty);
  });

  test('control: a planned REL item still needs its ID', () {
    const text = '### 1.2. WIP\n\n- REL: the first App Store submission is approved\n';
    expect(itemsWithoutId(text), ['line 3: - REL: the first App Store submission is approved']);
  });
}
