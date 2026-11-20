// test/unit/change_process_test.dart - CHANGELOG.md and BACKLOG.md hold work items, and the process lives
// in CHANGE-PROCESS.md (ID-635).
//
// The rules for work items were in CHANGELOG's header, BACKLOG's header and ARCHITECTURE's appendix 14, and
// they drifted apart. They now live in one file, and each of the two work item files opens with a line that
// says to read it first. Those lines are what makes an agent or a person who opens only CHANGELOG.md or
// BACKLOG.md find the rules, so losing one is a failure, and so is a rule growing back in either file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The line both work item files open with.
const String kPointerLine = 'Always read and follow [CHANGE-PROCESS.md](CHANGE-PROCESS.md) before changing this file.';

/// Headings and phrases that belong to CHANGE-PROCESS.md and must not be written again in a work item file.
const List<String> kProcessOnly = [
  '| Prefix | Meaning',
  'Work items: less is better',
  'Unique IDs',
  'When asked to triage BACKLOG',
  'Every commit is a build',
  'Before the commit',
  'flowchart TB',
];

/// Whether the first lines of [text], where a reader looks first, hold the pointer.
bool opensWithPointer(String text) => text.split(RegExp(r'\r?\n')).take(8).contains(kPointerLine);

final RegExp _blockHeader = RegExp(r'^\d{4}-\d\d-\d\d v\d+\.\d+\.\d+ build \d+ - ', multiLine: true);

/// [text] up to its first release block. CHANGELOG.md's old blocks quote the rules they were written under, so
/// the history is not read; everything above it is.
String aboveReleaseBlocks(String text) {
  final first = _blockHeader.firstMatch(text);
  return first == null ? text : text.substring(0, first.start);
}

/// The phrases of [kProcessOnly] found in [text].
List<String> processRulesIn(String text) => [for (final p in kProcessOnly) if (text.contains(p)) p];

void main() {
  final process = File('CHANGE-PROCESS.md');
  final changelog = File('CHANGELOG.md').readAsStringSync();
  final backlog = File('BACKLOG.md').readAsStringSync();

  test('CHANGE-PROCESS.md exists and holds every rule', () {
    expect(process.existsSync(), isTrue);
    final text = process.readAsStringSync();
    for (final p in kProcessOnly) {
      expect(text, contains(p), reason: 'the process file holds "$p"');
    }
    expect(text, contains('step'), reason: 'and the commit steps');
  });

  test('CHANGELOG.md and BACKLOG.md each open with the line that says to read CHANGE-PROCESS.md', () {
    expect(opensWithPointer(changelog), isTrue, reason: 'CHANGELOG.md must open with: $kPointerLine');
    expect(opensWithPointer(backlog), isTrue, reason: 'BACKLOG.md must open with: $kPointerLine');
  });

  test('no process rule is written again in CHANGELOG.md or BACKLOG.md', () {
    expect(processRulesIn(aboveReleaseBlocks(changelog)), isEmpty, reason: 'CHANGELOG.md holds work items only');
    expect(processRulesIn(backlog), isEmpty, reason: 'BACKLOG.md holds work items only');
  });

  test("ARCHITECTURE.md's appendix 14 points at CHANGE-PROCESS.md and draws no diagram of its own", () {
    final arch = File('ARCHITECTURE.md').readAsStringSync();
    final start = arch.indexOf('## 14. <a name=');
    final end = arch.indexOf('## 15. <a name=', start);
    expect(start, greaterThan(0));
    final appendix = arch.substring(start, end);
    expect(appendix, contains('(CHANGE-PROCESS.md)'));
    expect(appendix, isNot(contains('```mermaid')));
  });

  group('the check itself', () {
    test('a file without the pointer in its first lines fails', () {
      expect(opensWithPointer('# BACKLOG.md\n\n- [Contents](#c)\n'), isFalse);
      expect(opensWithPointer('# BACKLOG.md\n\n$kPointerLine\n'), isTrue);
    });

    test('a process rule heading is found, and ordinary work items are not', () {
      expect(processRulesIn('**Work items: less is better.**'), ['Work items: less is better']);
      expect(processRulesIn('- ID-635 DOC: move the process out\n'), isEmpty);
    });

    test('the history is not read for process phrases, since old blocks quote them', () {
      const text = '# CHANGELOG.md\n\n## 1. Implemented\n\n2026-11-19 v0.8.217 build 587 - x\n\n- ID-1 DOC: Every commit is a build\n';
      expect(processRulesIn(aboveReleaseBlocks(text)), isEmpty);
      expect(processRulesIn(aboveReleaseBlocks('Every commit is a build\n\n$text')), ['Every commit is a build']);
    });
  });
}
