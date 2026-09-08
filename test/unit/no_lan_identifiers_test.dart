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

/// `.claude/testing/` is gitignored on purpose - it holds verbatim SSH and app session output,
/// which is full of real hostnames, addresses and MACs. Scrubbing those file by file is what
/// failed in build 409; ignoring the directory wholesale is the fix, and the first test below
/// is what enforces that it stays ignored. So it is exempt from the MAC scan rather than
/// exempt from the rules.
const _ignoredPath = '.claude/testing';

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
        // Uri.path normalises Windows separators to '/', so this matches on both platforms.
        if (e.uri.path.contains(_ignoredPath)) continue;
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
    expect(ignored, contains('.claude/testing/'), reason: '.claude/testing/ must stay in .gitignore - see .claude/CONTEXT.md');

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

  // MACs have been guarded since 2026-09-07. Hostnames and addresses were not, and both leaked
  // into ARCHITECTURE.md and a plan on 2026-09-08 while a screen mock-up was written up - the
  // sweep caught them, but only because it was run by hand. The rule covers all three, so now so
  // does the guard.
  test('no device hostname from the maintainer network is written down', () {
    // Every device on that network is named Arc<Something>. Nothing in this repo needs to be.
    final pattern = RegExp(r'\bArc[A-Z][A-Za-z0-9]');
    final offenders = <String>[];
    for (final file in _repoFiles()) {
      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) offenders.add('${file.path}:${i + 1}  ${lines[i].trim()}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'use a generic device name - Laptop, Console, NAS:\n${offenders.join('\n')}');
  });

  test('no address from the maintainer LAN subnet is written down', () {
    // That LAN sits on the 192.168.0 prefix - written without a fourth octet here, because this
    // comment is inside the range the test scans and the first draft flagged itself. Examples
    // belong in 192.168.1.x, and 192.168.50.1 is the ASUS factory default, a documented constant
    // rather than anybody's address.
    final pattern = RegExp(r'\b192\.168\.0\.\d{1,3}\b');
    final offenders = <String>[];
    for (final file in _repoFiles()) {
      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final m in pattern.allMatches(lines[i])) {
          // .1 is the gateway address everyone writes; it is not a device on that network.
          if (m.group(0) == '192.168.0.1') continue;
          offenders.add('${file.path}:${i + 1}  ${m.group(0)}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'use 192.168.1.x for examples:\n${offenders.join('\n')}');
  });
}
