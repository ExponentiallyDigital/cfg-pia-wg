// ARCHITECTURE.md, SECURITY.md and ROUTER-DNS.md number every heading below the title, in order, and
// open with a contents list of exactly those headings (ID-565).
//
// SECURITY.md and ROUTER-DNS.md had neither (2026-11-12).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const numberedDocs = ['ARCHITECTURE.md', 'SECURITY.md', 'ROUTER-DNS.md'];

/// A heading as GitHub shows it: its `<a name>` tag dropped.
String _plain(String title) => title.replaceAll(RegExp(r'<a [^>]*></a>'), '').trim();

/// GitHub's anchor for a heading's text.
String slug(String title) => _plain(title).toLowerCase().replaceAll(RegExp(r'[^\w\- ]'), '').replaceAll(' ', '-');

/// Every heading below the title, outside code fences, as (depth, text).
List<(int, String)> headingsOf(String text) {
  final out = <(int, String)>[];
  var fenced = false;
  for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
    if (line.trimLeft().startsWith('```')) fenced = !fenced;
    final m = RegExp(r'^(#{2,6}) (.*)$').firstMatch(line);
    if (!fenced && m != null) out.add((m.group(1)!.length, _plain(m.group(2)!)));
  }
  return out;
}

/// What is wrong with [text]'s numbering: each heading must carry the next number at its depth.
List<String> numberingProblems(String text) {
  final hs = headingsOf(text);
  if (hs.isEmpty) return ['no headings'];
  final top = hs.map((h) => h.$1).reduce((a, b) => a < b ? a : b);
  final counters = <int>[];
  final out = <String>[];
  for (final (depth, title) in hs) {
    final level = depth - top;
    while (counters.length > level + 1) {
      counters.removeLast();
    }
    while (counters.length < level + 1) {
      counters.add(0);
    }
    counters[level]++;
    final want = '${counters.join('.')}. ';
    if (!title.startsWith(want)) out.add('"$title" should start "$want"');
  }
  return out;
}

/// The contents list [text] should open with, built from its headings.
List<String> wantedContents(String text) {
  final hs = headingsOf(text);
  final top = hs.map((h) => h.$1).reduce((a, b) => a < b ? a : b);
  return [for (final (d, t) in hs) '${'  ' * (d - top)}- [$t](#${slug(t)})'];
}

/// The contents list [text] has: the `- [..](#..)` lines before the first heading below the title.
List<String> contentsOf(String text) {
  final out = <String>[];
  for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
    if (RegExp(r'^#{2,6} ').hasMatch(line)) break;
    if (RegExp(r'^\s*- \[.*\]\(#[^)]*\)$').hasMatch(line)) out.add(line.replaceAll(r'\&', '&'));
  }
  return out;
}

void main() {
  for (final doc in numberedDocs) {
    group(doc, () {
      final text = File(doc).readAsStringSync();
      test('every heading below the title is numbered, in order', () {
        final problems = numberingProblems(text);
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
      test('the contents list every heading once, in order, with its anchor', () {
        expect(contentsOf(text), wantedContents(text));
      });
    });
  }

  test('control: an unnumbered heading, a number out of order and a missing contents entry are caught', () {
    const doc = '# T\n\n- [1. A](#1-a)\n\n## 1. A\n\n### 1.1. B\n\n## 3. C\n\n## D\n';
    expect(numberingProblems(doc), ['"3. C" should start "2. "', '"D" should start "3. "']);
    expect(contentsOf(doc), isNot(wantedContents(doc)));
    expect(wantedContents(doc), ['- [1. A](#1-a)', '  - [1.1. B](#11-b)', '- [3. C](#3-c)', '- [D](#d)']);
  });
}
