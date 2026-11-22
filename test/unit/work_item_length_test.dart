// A work item is a summary, not a record: every line of it is at most two sentences (Andrew, 2026-11-22).
//
// CHANGE-PROCESS.md section 3 already said "less is better", and in build 588 about 25 items grew into paragraphs
// of measurements and file names anyway, which CONTEXT.md 1.1 puts one rung up, as a test. The detail belongs in
// the item's plan file. This reads CHANGELOG.md's newest block and BACKLOG.md's Current Release, where work is
// being written; older blocks keep the longer form they were written in.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sub-lines a work item may have: CHANGE-PROCESS.md section 3, and the two ways it closes.
final RegExp kAllowedSubLine = RegExp(r'^  - (DoD:|Plan:|Now:|Closed |Partly done )');

final RegExp _blockHeader = RegExp(r'^\d{4}-\d\d-\d\d v\d+\.\d+\.\d+ build \d+ - ');

/// How many sentences [line] has, counted as a reader would. Code, links and numbers like 388.13 don't end one.
int sentenceCount(String line) {
  var t = line
      .replaceAll(RegExp(r'`[^`]*`'), 'x')
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'https?://\S+'), 'x')
      .replaceAll(RegExp(r'\b(e\.g|i\.e|vs|etc|approx|no)\.', caseSensitive: false), 'x');
  t = t.trim();
  if (t.isEmpty) return 0;
  return RegExp(r'[.!?](?=\s+[A-Z"(\[])').allMatches(t).length + 1;
}

/// One work item: its first line and its sub-lines.
class WorkItem {
  WorkItem(this.id, this.lines);
  final String id;
  final List<String> lines;
}

/// The work items in [text], each a `- ID-NNN` line and the `  - ` lines that follow it.
List<WorkItem> workItemsIn(Iterable<String> text) {
  final out = <WorkItem>[];
  List<String>? cur;
  String id = '';
  for (final l in text) {
    final m = RegExp(r'^- (ID-\d+) ').firstMatch(l);
    if (m != null) {
      id = m.group(1)!;
      cur = [l];
      out.add(WorkItem(id, cur));
    } else if (cur != null && l.startsWith('  - ')) {
      cur.add(l);
    } else {
      cur = null;
    }
  }
  return out;
}

/// What is wrong with [item], one sentence each.
List<String> problemsWith(WorkItem item) {
  final out = <String>[];
  for (final (i, l) in item.lines.indexed) {
    final body = i == 0 ? l.replaceFirst(RegExp(r'^- ID-\d+ [A-Z]+: '), '') : l.replaceFirst(RegExp(r'^  - [^:]*:? '), '');
    final n = sentenceCount(body);
    if (n > 2) out.add('${item.id}: a line is $n sentences, and a work item line is at most two: "${l.length > 70 ? '${l.substring(0, 70)}...' : l}"');
    if (i > 0 && !kAllowedSubLine.hasMatch(l)) out.add('${item.id}: a line that is not DoD, Plan, Now or Closed: "${l.length > 50 ? '${l.substring(0, 50)}...' : l}"');
    if (l.contains('**')) out.add('${item.id}: bold inside a work item');
  }
  return out;
}

List<String> _newestBlock(String changelog) {
  final lines = changelog.split(RegExp(r'\r?\n'));
  final start = lines.indexWhere(_blockHeader.hasMatch);
  final end = lines.indexWhere(_blockHeader.hasMatch, start + 1);
  return lines.sublist(start + 1, end < 0 ? lines.length : end);
}

List<String> _currentRelease(String backlog) {
  final lines = backlog.split(RegExp(r'\r?\n'));
  final start = lines.indexWhere((l) => l.startsWith('## 1. Current Release'));
  final end = lines.indexWhere((l) => l.startsWith('## '), start + 1);
  return lines.sublist(start + 1, end < 0 ? lines.length : end);
}

void main() {
  group('the check itself', () {
    test('a sentence ends at a full stop and a capital, not at code, a link or a number', () {
      expect(sentenceCount('One. Two. Three.'), 3);
      expect(sentenceCount('Seen on Merlin 388.13 with `a.b. C` and v0.8.218 build 588; and more.'), 1);
      expect(sentenceCount('See [ROUTER-DNS.md](ROUTER-DNS.md). It says so.'), 2);
      expect(sentenceCount('For example, e.g. this one. And that.'), 2);
      expect(sentenceCount(''), 0);
    });

    test('a line of three sentences fails, and of two passes', () {
      expect(problemsWith(WorkItem('ID-1', ['- ID-1 BUG: One. Two. Three.'])), hasLength(1));
      expect(problemsWith(WorkItem('ID-1', ['- ID-1 BUG: One. Two.', '  - Closed 2026-11-22: Done. Seen.'])), isEmpty);
    });

    test('a sub-line that is not DoD, Plan, Now or Closed fails', () {
      expect(problemsWith(WorkItem('ID-1', ['- ID-1 BUG: x.', '  - Decided 2026-11-22: x.'])), hasLength(1));
      for (final ok in ['  - DoD: x.', '  - Plan: [p](p.md)', '  - Now: x.', '  - Closed 2026-11-22: x.', '  - Partly done 2026-11-22: x. Remainder: ID-2.']) {
        expect(problemsWith(WorkItem('ID-1', ['- ID-1 BUG: x.', ok])), isEmpty, reason: ok);
      }
    });

    test('bold fails', () {
      expect(problemsWith(WorkItem('ID-1', ['- ID-1 BUG: a **bold** word.'])), hasLength(1));
    });

    test('items are found by their ID line and the indented lines after it', () {
      final items = workItemsIn(['- ID-1 A: x.', '  - DoD: y.', '', '- ID-2 B: z.', 'prose', '  - not an item line']);
      expect(items.map((i) => i.lines.length), [2, 1]);
    });
  });

  test('every item in the newest release block is a summary', () {
    final items = workItemsIn(_newestBlock(File('CHANGELOG.md').readAsStringSync()));
    expect(items, isNotEmpty);
    expect([for (final i in items) ...problemsWith(i)], isEmpty);
  });

  test('every item in BACKLOG.md\'s Current Release is a summary', () {
    final items = workItemsIn(_currentRelease(File('BACKLOG.md').readAsStringSync()));
    expect([for (final i in items) ...problemsWith(i)], isEmpty);
  });
}
