// Every Mermaid diagram in the project's Markdown draws its labels as SVG text.
//
// GitHub draws a label as HTML by default. Chrome on an Android tablet cut the end off labels drawn that
// way, in most of ARCHITECTURE.md's diagrams, while desktop Chrome showed them whole (2026-11-02). SVG text
// is measured as it is drawn, so it fits on both. HTML tags don't work in SVG text, so emphasis is
// written as a Markdown label instead: "`plain\n*italic*`".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The line every diagram starts with.
const String kSvgLabelsDirective = '%%{init: {"htmlLabels": false, "flowchart": {"wrappingWidth": 400}}}%%';

/// What is wrong with each Mermaid block in [text], with the line it starts on.
List<String> mermaidProblems(String text) {
  final out = <String>[];
  for (final m in RegExp(r'```mermaid\r?\n([\s\S]*?)```').allMatches(text)) {
    final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
    final code = m.group(1)!;
    if (!code.trimLeft().startsWith(kSvgLabelsDirective)) out.add('line $line: no SVG labels directive');
    if (RegExp(r'</?(i|b|em|strong)>').hasMatch(code)) out.add('line $line: an HTML tag SVG text would show as text');
  }
  return out;
}

void main() {
  test('every Mermaid diagram in a Markdown file draws its labels as SVG text', () {
    final found = <String>[];
    for (final f in Directory('.').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll('\\', '/');
      if (!p.endsWith('.md') || p.contains('/build/') || p.contains('/.dart_tool/') || p.contains('/node_modules/')) continue;
      for (final problem in mermaidProblems(f.readAsStringSync())) {
        found.add('$p $problem');
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('control: a diagram as it was is caught twice', () {
    const was = 'text\n```mermaid\nflowchart TB\n    F{"Which firmware?<br/><i>nvram get 3rd-party</i>"}\n```\n';
    expect(mermaidProblems(was), ['line 2: no SVG labels directive', 'line 2: an HTML tag SVG text would show as text']);
  });

  test('control: a diagram as it is now passes', () {
    const now = '```mermaid\n$kSvgLabelsDirective\nflowchart TB\n    F{"`Which firmware?\n*nvram get 3rd-party*`"}\n```\n';
    expect(mermaidProblems(now), isEmpty);
  });
}
