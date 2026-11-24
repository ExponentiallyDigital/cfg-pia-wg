// A GitHub alert in the project's Markdown starts at the left margin (ID-562).
//
// GitHub draws `> [!CAUTION]` as an alert only when the quote is not inside anything else. BUILDING.md's
// caution under iOS step 11 was indented to sit inside the numbered list, and showed as a plain quote
// with "[!CAUTION]" written in it (2026-11-12).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The line numbers in [text] of an alert that does not start at the left margin.
List<int> indentedAlerts(String text) {
  final alert = RegExp(r'^\s+>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]');
  final lines = text.split('\n');
  return [for (var i = 0; i < lines.length; i++) if (alert.hasMatch(lines[i])) i + 1];
}

/// The line numbers in [text] of an alert marker that GitHub will not draw as a box: one with a title or any
/// other text after it on the same line, or with no space after the ">" (2026-11-24: ROUTER-DNS.md and
/// QUICKSTART.md showed as plain quotes because a title followed the marker).
List<int> malformedMarkers(String text) {
  final marker = RegExp(r'^>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]');
  final good = RegExp(r'^> \[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$');
  final lines = text.split('\n');
  return [for (var i = 0; i < lines.length; i++) if (marker.hasMatch(lines[i]) && !good.hasMatch(lines[i])) i + 1];
}

void main() {
  test('every GitHub alert in a Markdown file starts at the left margin', () {
    final found = <String>[];
    for (final f in Directory('.').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.endsWith('.md') || p.contains('/build/') || p.contains('/.dart_tool/') || p.contains('/node_modules/')) continue;
      for (final n in indentedAlerts(f.readAsStringSync())) {
        found.add('$p line $n');
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('every GitHub alert marker is alone on its line, after "> "', () {
    final found = <String>[];
    for (final f in Directory('.').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.endsWith('.md') || p.contains('/build/') || p.contains('/.dart_tool/') || p.contains('/node_modules/')) continue;
      for (final n in malformedMarkers(f.readAsStringSync())) {
        found.add('$p line $n');
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('control: a marker with a title after it, or with no space after ">", is caught', () {
    expect(malformedMarkers('> [!TIP] The short version:\n> - a\n'), [1]);
    expect(malformedMarkers('>[!TIP]\n> text\n'), [1]);
    expect(malformedMarkers('> [!TIP]\n> **The short version:**\n'), isEmpty);
  });

  test('control: the BUILDING.md caution as it was is caught, and one at the margin is not', () {
    const was = '11. **Running on an iPhone from VS Code.**\n\n    > [!CAUTION]\n    > A debug build replaces...\n';
    expect(indentedAlerts(was), [3]);
    expect(indentedAlerts('> [!CAUTION]\n> A debug build replaces...\n'), isEmpty);
  });
}
