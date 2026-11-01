// An address in an HTML attribute in the project's Markdown never runs over a line.
//
// README.md's "Lines of code" badge broke on GitHub, in Chrome and Edge alike, because its <img src="...">
// ended in a line break: `...&metric=ncloc` then a newline, then `" alt="Lines of code">`. The image
// address carried the newline, and SonarCloud answered nothing a browser could draw (2026-11-01).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Each `src="..."` or `href="..."` in [text] whose value holds a line break, with its line number.
List<String> brokenAttributes(String text) {
  final out = <String>[];
  for (final m in RegExp(r'''\b(src|href)=(["'])([^"']*)\2''').allMatches(text)) {
    if (m.group(3)!.contains('\n') || m.group(3)!.contains('\r')) {
      final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
      out.add('line $line: ${m.group(1)}="${m.group(3)!.replaceAll('\n', r'\n').replaceAll('\r', r'\r')}"');
    }
  }
  return out;
}

void main() {
  test('no src or href in a Markdown file runs over a line', () {
    final found = <String>[];
    for (final f in Directory('.').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll('\\', '/');
      if (!p.endsWith('.md') || p.contains('/build/') || p.contains('/.dart_tool/') || p.contains('/node_modules/')) continue;
      for (final b in brokenAttributes(f.readAsStringSync())) {
        found.add('$p $b');
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test("control: the README line as it was is caught", () {
    const was = '<a href="https://sonarcloud.io/project/overview?id=X"><img src="https://sonarcloud.io/api/project_badges/'
        'measure?project=X&metric=ncloc\n" alt="Lines of code"></a>';
    expect(brokenAttributes(was), ['line 1: src="https://sonarcloud.io/api/project_badges/measure?project=X&metric=ncloc\\n"']);
  });
}
