// test/unit/router_log_coverage_test.dart - a file that changes the router writes the router's log (ID-617).
//
// Andrew's rule, 2026-11-16 (CONTEXT.md section 1): every change the app makes to the router is
// logged to the app log and to the router's, success and failure, always. It was a rule only item by
// item, and HOME SCREEN WIDGET KEY broke it from build 494 to build 582 without anything failing
// (ID-616). This is the check that fails.
//
// It is coarse, on purpose: a file in lib/ that holds a command which changes the router must also
// hold a way to write the router's log, or be on the list below with the reason it needs none.
// ID-616's own tests hold each path of one service to both logs; this holds the rest to at least
// having a writer.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A command that changes the router, as it appears in lib/'s code: NVRAM, cron, the firmware's
/// services, files in the app's folder or the router's jffs, and routing rules.
final RegExp kChangesRouter = RegExp(
  r'nvram (set|unset)\b|\bcru (a|d)\b|\bservice\s+(restart|start|stop)\b|\bmv \S|\brm -f\b|(>>?|tee) ?\S*/jffs|\bip rule (add|del)\b',
);

/// A way to write a line to the router's log.
final RegExp kLogsToRouter = RegExp(r'buildLoggerCommand|_logRouter|logToRouter|logRouter\b');

/// Files that change the router and need no writer of their own, each with why. An entry that is
/// no longer true fails below, so this list cannot go stale quietly.
const Map<String, String> kExempt = {
  'lib/device_assignment.dart': 'a command constant; DeviceAssignmentService, which runs it, logs',
  'lib/fail_closed_guard.dart': 'builds the guard script and its commands; RouterWatchdog, which deploys them, logs',
  'lib/merlin_guard.dart': "builds Merlin's guard script; RouterWatchdog, which deploys it, logs",
  'lib/network_lookup.dart': "the measuring rule for one lookup, added and removed at once: NETWORK's, not a change that stays",
  'lib/router_ops.dart': 'delegates to RouterSlotService, which logs',
  'lib/s50_template.dart': 'the text of the router script; RouterWatchdog, which installs it, logs',
};

/// Code with its comment lines dropped: a command named in a comment is not one that runs.
String _code(String source) => source.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// The files that change the router with no router-log writer and no reason on [exempt], and the
/// entries of [exempt] that are wrong: missing, no longer changing the router, or logging now.
({List<String> missing, List<String> stale}) routerLogGaps(Map<String, String> files, Map<String, String> exempt) {
  final missing = <String>[];
  for (final e in files.entries) {
    final code = _code(e.value);
    if (kChangesRouter.hasMatch(code) && !kLogsToRouter.hasMatch(code) && !exempt.containsKey(e.key)) missing.add(e.key);
  }
  final stale = <String>[];
  for (final name in exempt.keys) {
    final source = files[name];
    if (source == null) {
      stale.add('$name: no such file');
    } else if (!kChangesRouter.hasMatch(_code(source))) {
      stale.add('$name: no longer changes the router');
    } else if (kLogsToRouter.hasMatch(_code(source))) {
      stale.add('$name: writes the router log now, so it needs no exemption');
    }
  }
  return (missing: missing, stale: stale);
}

Map<String, String> _libFiles() => {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
        f.path.replaceAll(r'\', '/'): f.readAsStringSync(),
    };

void main() {
  test('every file in lib/ that changes the router can write the router log, or says why not', () {
    final gaps = routerLogGaps(_libFiles(), kExempt);
    expect(gaps.missing, isEmpty,
        reason: 'These files hold a command that changes the router and no way to write its log. Log each change to the app log and the '
            "router's (CONTEXT.md section 1, ID-616), or add the file to kExempt with the reason it needs none.");
    expect(gaps.stale, isEmpty, reason: 'These kExempt entries are no longer true; take them out.');
  });

  group('the check itself', () {
    const changes = "await run('nvram set foo=bar; nvram commit');";

    test('a file that changes the router and never logs is found', () {
      expect(routerLogGaps({'lib/a.dart': changes}, const {}).missing, ['lib/a.dart']);
    });

    test('a router-log writer, under any of the names the app uses, clears it', () {
      for (final writer in ['buildLoggerCommand(m)', '_logRouter(m)', 'svc.logToRouter(m)', 'logRouter: _logRouter']) {
        expect(routerLogGaps({'lib/a.dart': '$changes\n$writer;'}, const {}).missing, isEmpty, reason: writer);
      }
    });

    test('a command named only in a comment does not count', () {
      expect(routerLogGaps({'lib/a.dart': '// run nvram set foo=bar\nfinal x = 1;'}, const {}).missing, isEmpty);
    });

    test('prose with the word "service" in it is not a change', () {
      expect(routerLogGaps({'lib/a.dart': "final t = 'trade names, trademarks, or service marks';"}, const {}).missing, isEmpty);
    });

    test('an exempt file is not reported, and an exemption that is no longer true is', () {
      expect(routerLogGaps({'lib/a.dart': changes}, {'lib/a.dart': 'builds only'}).missing, isEmpty);
      expect(routerLogGaps({'lib/a.dart': changes}, {'lib/gone.dart': 'x'}).stale, ['lib/gone.dart: no such file']);
      expect(routerLogGaps({'lib/a.dart': 'final x = 1;'}, {'lib/a.dart': 'x'}).stale, ['lib/a.dart: no longer changes the router']);
      expect(routerLogGaps({'lib/a.dart': '$changes\n_logRouter(m);'}, {'lib/a.dart': 'x'}).stale, hasLength(1));
    });
  });
}
