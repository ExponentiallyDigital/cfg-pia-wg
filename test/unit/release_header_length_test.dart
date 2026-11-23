// A release block's header summary is very brief, and there is no prose under it (Andrew, 2026-11-22).
//
// CHANGE-PROCESS.md section 7 said "a very brief summary in one sentence or less", and nothing measured it:
// build 588's header was 292 characters, with a paragraph of prose under it, and builds 586 and 587 before it were
// 250 and 208. The header is also the commit subject word for word, and the release note is the ```play fence, so
// the prose says nothing the fence doesn't. At most 100 characters and one sentence, and no prose. Only the newest
// block is read, and only once it no longer says `in progress`: the older headers were released as they were and
// are not changed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'work_item_length_test.dart' show sentenceCount;

/// The most characters a header's summary may have.
const int kMaxSummaryChars = 100;

final RegExp _header = RegExp(r'^(\d{4}-\d\d-\d\d v\d+\.\d+\.\d+ build \d+) - (.*)$');

/// What is wrong with a block's [header] and the [prose] under it, one sentence each. A block still `in progress` has
/// no summary to check.
List<String> headerProblems(String header, List<String> prose) {
  final m = _header.firstMatch(header);
  if (m == null) return ['not a block header: "$header"'];
  final summary = m.group(2)!.trim();
  final out = <String>[];
  if (summary != 'in progress') {
    if (summary.length > kMaxSummaryChars) out.add('${m.group(1)}: the summary is ${summary.length} characters, and at most $kMaxSummaryChars are allowed');
    if (sentenceCount(summary) > 1) out.add('${m.group(1)}: the summary is more than one sentence');
  }
  if (prose.any((l) => l.trim().isNotEmpty)) out.add('${m.group(1)}: there is prose under the header, and the play fence is the release note');
  return out;
}

/// The header lines in [lines] and, for each, the prose between it and the play fence or the first item.
List<(String, List<String>)> blocksIn(List<String> lines) {
  final out = <(String, List<String>)>[];
  for (var i = 0; i < lines.length; i++) {
    if (!_header.hasMatch(lines[i])) continue;
    final prose = <String>[];
    for (var j = i + 1; j < lines.length; j++) {
      if (lines[j].startsWith('```') || lines[j].startsWith('- ') || _header.hasMatch(lines[j])) break;
      prose.add(lines[j]);
    }
    out.add((lines[i], prose));
  }
  return out;
}

void main() {
  final lines = File('CHANGELOG.md').readAsLinesSync();
  final blocks = blocksIn(lines);

  group('the check itself', () {
    test('a brief summary with no prose passes, and a block in progress has none to check', () {
      expect(headerProblems('2026-11-22 v0.8.220 build 590 - the Merlin guard updates itself', const ['']), isEmpty);
      expect(headerProblems('2026-11-22 v0.8.220 build 590 - in progress', const []), isEmpty);
    });

    test('a summary over the limit fails, and so does one of two sentences', () {
      expect(headerProblems('2026-11-22 v0.8.220 build 590 - ${'a' * 101}', const []), hasLength(1));
      expect(headerProblems('2026-11-22 v0.8.220 build 590 - One thing. Another thing.', const []), hasLength(1));
      expect(headerProblems('2026-11-22 v0.8.220 build 590 - ${'a' * 100}', const []), isEmpty);
    });

    test('any prose under the header fails', () {
      expect(headerProblems('2026-11-22 v0.8.220 build 590 - brief', ['One sentence.']), hasLength(1));
      expect(headerProblems('2026-11-22 v0.8.220 build 590 - in progress', ['Prose.']), hasLength(1));
    });

    test('blocks are found by their header, and the prose stops at the play fence or the first item', () {
      final found = blocksIn(['2026-11-22 v0.8.220 build 590 - a', '', 'Prose.', '', '```play', 'x', '```', '- ID-1 A: b.', '2026-11-20 v0.8.219 build 589 - c']);
      expect(found, hasLength(2));
      expect(found.first.$2.where((l) => l.isNotEmpty), ['Prose.']);
    });

    // The headers released before this rule were not changed, so they are what shows the check can fail.
    test('it flags the headers of builds 587 and 588, which were released as they were', () {
      for (final b in ['build 587', 'build 588']) {
        final block = blocks.firstWhere((x) => x.$1.contains('$b - '));
        expect(headerProblems(block.$1, block.$2), isNotEmpty, reason: b);
      }
    });

    test('and passes build 589, whose summary is under the limit and which has no prose', () {
      final block = blocks.firstWhere((x) => x.$1.contains('build 589 - '));
      expect(headerProblems(block.$1, block.$2), isEmpty);
    });
  });

  test('the newest block\'s header is brief, and has no prose under it', () {
    expect(headerProblems(blocks.first.$1, blocks.first.$2), isEmpty);
  });
}
