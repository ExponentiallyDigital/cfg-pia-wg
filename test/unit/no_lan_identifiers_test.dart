// test/unit/no_lan_identifiers_test.dart - the maintainer's real LAN must never reach the repo.
//
// Build 409 committed `.claude/testing/2026-06-09_10-40_e2e_manual_test.md`, a verbatim SSH session
// log carrying a DDNS hostname, a LAN IP, a router login name and a PIA username. It was caught
// before the push, but only by hand. Working agreement in `.claude/CONTEXT.md`.
//
// The real values cannot be listed here - writing them into a test would commit the very thing the
// test exists to prevent. So this checks the two structural properties instead: verbatim hardware
// logs stay out of the working tree, and any MAC address written down is a visibly invented one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Directories git never sees, plus the build and coverage output.
const _skipDirs = {'.git', '.dart_tool', 'build', 'coverage', '.gradle', '.idea'};

/// MAC addresses that are obviously placeholders: every octet is drawn from a repeating or
/// sequential pattern. A real NIC address will not survive this.
final _inventedMac = RegExp(r'^(([0-9A-F])\2:)|^(00:01:02|05:04:03|0A:0B:0C|FF:F0:E0|DE:AD:BE)');

final _macPattern = RegExp(r'\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b');

Iterable<File> _repoFiles() sync* {
  final stack = <Directory>[Directory('.')];
  while (stack.isNotEmpty) {
    for (final e in stack.removeLast().listSync()) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is Directory) {
        if (!_skipDirs.contains(name)) stack.add(e);
      } else if (e is File && const {'.md', '.dart', '.sh', '.py', '.svg', '.yaml'}.any(name.endsWith)) {
        yield e;
      }
    }
  }
}

void main() {
  test('verbatim hardware session logs are not tracked by git', () {
    // `.claude/testing/` holds raw SSH and app output, so it is ignored wholesale rather than
    // scrubbed file by file - scrubbing relies on spotting every identifier, which failed once.
    final ignored = File('.gitignore').readAsLinesSync().map((l) => l.trim());
    expect(ignored, contains('.claude/testing/'),
        reason: '.claude/testing/ must stay in .gitignore - see .claude/CONTEXT.md');

    final tracked = Process.runSync('git', ['ls-files', '.claude/testing']).stdout.toString().trim();
    expect(tracked, isEmpty, reason: 'these files are verbatim hardware logs and must not be tracked:\n$tracked');
  });

  test('every MAC address written down is a visibly invented one', () {
    final offenders = <String>[];
    for (final file in _repoFiles()) {
      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final m in _macPattern.allMatches(lines[i])) {
          final mac = m.group(0)!.toUpperCase();
          if (mac == 'AA:BB:CC:DD:EE:FF') continue;
          if (_inventedMac.hasMatch(mac)) continue;
          offenders.add('${file.path}:${i + 1}  $mac');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'use an invented MAC such as AA:BB:CC:DD:EE:FF - see .claude/CONTEXT.md:\n${offenders.join('\n')}');
  });
}
