// TESTING.md's contents list each part's headings once, in order, under that part (ID-563).
//
// R1 to R10 were listed under Part 1 as well as Part 2, and Part 2's entries pointed at `#r1` where
// every other entry uses its heading's own anchor (2026-11-12).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// GitHub's anchor for a heading's text, the `<a name>` tag dropped.
String slug(String heading) => heading
    .replaceAll(RegExp(r'<a [^>]*></a>'), '')
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r"[^\w\- ]"), '')
    .replaceAll(' ', '-');

/// Each part's contents as `text|anchor`, in order: the bullets under `**Part N. ...**` before the first `---`.
Map<String, List<String>> contents(String text) {
  final out = <String, List<String>>{};
  String? part;
  for (final line in text.split('\n')) {
    if (line.trim() == '---') break;
    final p = RegExp(r'^\*\*(Part \d+)\. .*\*\*$').firstMatch(line.trim());
    if (p != null) part = p.group(1);
    final e = RegExp(r'^- \[(.*)\]\(#(.*)\)$').firstMatch(line.trim());
    if (part != null && e != null) (out[part] ??= []).add('${e.group(1)}|${e.group(2)}');
  }
  return out;
}

/// Each part's `##` headings as `text|anchor`, in order.
Map<String, List<String>> headings(String text) {
  final out = <String, List<String>>{};
  String? part;
  for (final line in text.split('\n')) {
    final p = RegExp(r'^# (Part \d+)\. ').firstMatch(line);
    if (p != null) part = p.group(1);
    final h = RegExp(r'^## (.*)$').firstMatch(line);
    if (part != null && h != null) {
      final title = h.group(1)!.replaceAll(RegExp(r'<a [^>]*></a>'), '').trim();
      (out[part] ??= []).add('$title|${slug(title)}');
    }
  }
  return out;
}

void main() {
  test("TESTING.md's contents list each part's headings once, in order, with their own anchors", () {
    final text = File('TESTING.md').readAsStringSync().replaceAll('\r\n', '\n');
    expect(contents(text), headings(text));
  });

  test('control: an R heading listed under Part 1, or pointing at #r1, is caught', () {
    const doc = '**Part 1. Run sheet**\n\n- [PRE. Before](#pre-before)\n- [R1. Broken](#r1-broken)\n\n'
        '**Part 2. Reference**\n\n- [R1. Broken](#r1)\n\n---\n\n# Part 1. Run sheet\n\n'
        "## <a name='pre'></a>PRE. Before\n\n# Part 2. Reference\n\n## <a name='r1'></a>R1. Broken\n";
    expect(contents(doc), isNot(headings(doc)));
    expect(headings(doc), {
      'Part 1': ['PRE. Before|pre-before'],
      'Part 2': ['R1. Broken|r1-broken'],
    });
  });
}
