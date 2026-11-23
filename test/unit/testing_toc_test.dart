// TESTING.md's contents list matches its headings (ID-563, rewritten for ID-684).
//
// ID-563: R1 to R10 were listed under Part 1 as well as Part 2, and Part 2's entries pointed at `#r1` where
// every other entry uses its heading's own anchor (2026-11-12). ID-684: the headings went one level deeper
// so Markdown All in One builds one nested list itself on save, but it doesn't when a file is changed any
// other way, so this builds the list from the `##` to `######` headings the way the extension does and
// compares it with the one in the file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// GitHub's heading anchor: lower case, punctuation dropped, spaces to hyphens.
String _slug(String text) => text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 _-]'), '').replaceAll(' ', '-');

/// The contents list [testing]'s headings call for, one line each, indented two spaces a level below `##`.
List<String> expectedContents(String testing) {
  final out = <String>[];
  var inFence = false;
  for (final line in testing.split('\n')) {
    if (line.startsWith('```')) inFence = !inFence;
    final m = inFence ? null : RegExp(r'^(#{2,6}) (.*)$').firstMatch(line.trimRight());
    if (m == null) continue;
    final text = m.group(2)!.replaceAll(RegExp(r"<a name='[^']*'></a>"), '').trim();
    out.add('${'  ' * (m.group(1)!.length - 2)}- [$text](#${_slug(text)})');
  }
  return out;
}

/// The first list of links in [testing], one line each.
List<String> contentsInFile(String testing) {
  final lines = testing.split('\n').map((l) => l.trimRight()).toList();
  final start = lines.indexWhere((l) => l.startsWith('- ['));
  expect(start, greaterThanOrEqualTo(0), reason: 'TESTING.md has no contents list');
  final out = <String>[];
  for (var i = start; i < lines.length && lines[i].trimLeft().startsWith('- ['); i++) {
    out.add(lines[i]);
  }
  return out;
}

void main() {
  final testing = File('TESTING.md').readAsStringSync();

  test('the contents list is the headings, in order', () {
    expect(contentsInFile(testing), expectedContents(testing),
        reason: 'TESTING.md changed: update its contents list (Markdown All in One: Update Table of Contents)');
  });

  test('control: an entry with the wrong anchor, or listed in the wrong place, is caught', () {
    const doc = '- [Part 1. Run sheet](#part-1-run-sheet)\n  - [R1. Broken](#r1)\n\n'
        "## Part 1. Run sheet\n\n### <a name='r1'></a>R1. Broken\n";
    expect(contentsInFile(doc), isNot(expectedContents(doc)));
    expect(expectedContents(doc), ['- [Part 1. Run sheet](#part-1-run-sheet)', '  - [R1. Broken](#r1-broken)']);
  });
}
