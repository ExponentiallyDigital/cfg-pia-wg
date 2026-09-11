// test/unit/markdown_links_test.dart - every link between the repo's own Markdown files resolves.
//
// The documents cross-reference each other constantly, and the anchors are generated from heading
// text, so any reword breaks the links pointing at it. That is exactly the moment a written-down
// rule is forgotten, which is why this is a test instead. The 2026-09-11 documentation rebuild
// found fourteen references inside ARCHITECTURE.md alone that had pointed at nothing for weeks,
// and nothing had reported them.
//
// Working notes are out of scope: `.claude/plans/` records what was believed at the time and
// `.claude/testing/` is not tracked at all.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _skipDirs = {'.git', '.dart_tool', 'build', 'coverage', '.gradle', '.idea'};

/// Drafts and verbatim logs. Both are records of a moment, not documents kept current.
const _skipPaths = {'.claude/plans', '.claude/testing'};

/// `[text](target)`, ignoring image embeds and reference-style definitions.
final _link = RegExp(r'(?<!\!)\[[^\]\[]*\]\(([^)\s]+)\)');

/// An explicit anchor: `<a name='foo'></a>`, single or double quoted.
final _explicitAnchor = RegExp('<a name=[\'"]([^\'"]+)[\'"]></a>');

// Up to three leading spaces is still a heading, and BACKLOG.md indents some of its own
// inside a list. Four would be a code block.
final _heading = RegExp(r'^ {0,3}#{1,6}\s+(.*)$');

/// GitHub's own rule: drop HTML and anything that is not a word character, space or hyphen, then
/// lowercase and turn each remaining space into a hyphen. Each space, not each RUN of spaces -
/// `Security & QA` loses the ampersand and keeps both spaces, so its anchor carries a double
/// hyphen. A leading section number survives too, which is why a numbered heading answers to both
/// its number-bearing slug and its explicit `<a name>`.
String _slug(String heading) {
  var t = heading.replaceAll(RegExp('<[^>]*>'), '');
  t = t.replaceAll(RegExp(r'[^\w\- ]', unicode: true), '');
  return t.trim().toLowerCase().replaceAll(RegExp(r'\s'), '-');
}

Iterable<File> _markdownFiles() sync* {
  final stack = <Directory>[Directory('.')];
  while (stack.isNotEmpty) {
    for (final e in stack.removeLast().listSync()) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is Directory) {
        if (!_skipDirs.contains(name)) stack.add(e);
      } else if (e is File && name.toLowerCase().endsWith('.md')) {
        // Uri.path normalises Windows separators, so one form matches on both platforms.
        if (_skipPaths.any(e.uri.path.contains)) continue;
        yield e;
      }
    }
  }
}

Set<String> _anchorsOf(File f) {
  final out = <String>{};
  var inFence = false;
  for (final line in f.readAsLinesSync()) {
    if (line.trimLeft().startsWith('```')) inFence = !inFence;
    if (inFence) continue;
    for (final m in _explicitAnchor.allMatches(line)) {
      out.add(m.group(1)!.toLowerCase());
    }
    final h = _heading.firstMatch(line);
    if (h != null) out.add(_slug(h.group(1)!));
  }
  return out;
}

void main() {
  test('every intra-repo Markdown link resolves', () {
    final anchors = <String, Set<String>>{};
    final broken = <String>[];

    for (final file in _markdownFiles()) {
      final dir = file.parent;
      final lines = file.readAsLinesSync();
      var inFence = false;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('```')) inFence = !inFence;
        if (inFence) continue;
        for (final m in _link.allMatches(lines[i])) {
          final target = m.group(1)!;
          if (RegExp(r'^[a-z][a-z0-9+.-]*:').hasMatch(target)) continue; // http:, mailto:, tel:
          final hash = target.indexOf('#');
          final path = hash < 0 ? target : target.substring(0, hash);
          final anchor = hash < 0 ? '' : Uri.decodeFull(target.substring(hash + 1)).toLowerCase();
          final where = '${file.path}:${i + 1}';

          final File targetFile;
          if (path.isEmpty) {
            targetFile = file;
          } else {
            targetFile = File('${dir.path}${Platform.pathSeparator}$path');
            if (!targetFile.existsSync()) {
              broken.add('$where  no such file: $target');
              continue;
            }
            if (!path.toLowerCase().endsWith('.md')) continue; // a script or an image: existence is enough
          }
          if (anchor.isEmpty) continue;
          final key = targetFile.absolute.path.toLowerCase();
          final have = anchors[key] ??= _anchorsOf(targetFile);
          if (!have.contains(anchor)) broken.add('$where  no such anchor: $target');
        }
      }
    }

    expect(broken, isEmpty,
        reason: 'these Markdown links point at nothing. Anchors come from heading text, so a '
            'reworded heading breaks every link into it:\n${broken.join('\n')}');
  });
}
