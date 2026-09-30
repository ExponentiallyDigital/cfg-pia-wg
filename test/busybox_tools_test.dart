// test/busybox_tools_test.dart - nothing sent to the router calls a tool stock firmware lacks.
//
// Stock ASUS BusyBox has no hexdump, od, xxd, base64, timeout, sha256sum, seq or `command`; the
// router has no logread or scp; over SSH `sh` is a Broadcom memory tool, so a piped `sh -s` crashes;
// and the firmware's curl ignores --doh-url. The watchdog tests run on a desktop shell that has all
// of these, so a script using one passes every harness test and fails on the router. This test reads
// the scripts as deployed, and every string in lib/, for those names.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/fail_closed_guard.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/router_watchdog.dart';
import 'package:cfg_pia_wg/s50_template.dart';

/// Each missing tool, matched only where it would run as a command (not inside a longer word or a
/// flag such as --connect-timeout, and `openssl base64` is openssl's own).
final Map<String, RegExp> _missing = {
  'hexdump': RegExp(r'(?<![\w-])hexdump\b'),
  'od': RegExp(r'(^|[;|&(`]\s*|\$\(\s*)od\s+-'),
  'xxd': RegExp(r'(?<![\w-])xxd\b'),
  'base64': RegExp(r'(?<![\w-])(?<!openssl )base64\s+-'),
  'timeout': RegExp(r'(?<![\w-])timeout\s+\d'),
  'sha256sum': RegExp(r'(?<![\w-])sha256sum\b'),
  'seq': RegExp(r'(?<![\w-])seq\s+\d'),
  'command -v': RegExp(r'(?<![\w-])command\s+-v\b'),
  'logread': RegExp(r'(?<![\w-])logread\b'),
  'scp': RegExp(r'(?<![\w-])scp\s'),
  'sh -s': RegExp(r'(?<![\w/-])sh\s+-s\b'),
  '--doh-url': RegExp(r'--doh-url'),
};

/// The lines of [text] that are not shell or Dart comments.
Iterable<String> _code(String text) => text
    .split('\n')
    .where((l) => !RegExp(r'^\s*(#(?!!)|//)').hasMatch(l))
    .map((l) => l.replaceFirst(RegExp(r'\s//\s.*$'), ''));

/// A tool tried only after a stock one failed (`openssl ... || sha256sum`), or named in a message,
/// is not a dependency.
bool _allowed(String line, String tool) =>
    line.contains('|| $tool') || RegExp('\\([^)]*\\b${RegExp.escape(tool)}\\)').hasMatch(line);

List<String> _uses(String name, String text) => [
      for (final line in _code(text))
        for (final e in _missing.entries)
          if (e.value.hasMatch(line) && !_allowed(line, e.key)) '$name uses ${e.key}: ${line.trim()}',
    ];

WatchdogConfig _config({required bool email}) => WatchdogConfig(
      slotIndex: 1,
      cronIntervalMinutes: 5,
      primaryIp: '8.8.8.8',
      secondaryIp: '1.1.1.1',
      piaUsername: 'p1234567',
      piaPassword: 'secret',
      emailAlertsEnabled: email,
      emailFrom: email ? 'from@example.com' : '',
      emailTo: email ? 'to@example.com' : '',
      emailSubject: email ? 'Alert' : '',
      smtpServer: email ? 'smtp.example.com:465' : '',
      smtpUsername: email ? 'smtpuser' : '',
      smtpPassword: email ? 'smtppass' : '',
    );

void main() {
  test('the patterns catch each missing tool', () {
    for (final bad in [
      'X=\$(hexdump -C f)',
      'printf x | od -An -tx1',
      'xxd -p f',
      'echo x | base64 -d',
      'timeout 5 curl x',
      'sha256sum f',
      'for i in \$(seq 1 3); do',
      'command -v jq',
      'logread | tail',
      'scp f r:/tmp',
      'cat f | ssh r sh -s',
      'curl --doh-url https://x',
    ]) {
      expect(_uses('t', bad), isNotEmpty, reason: bad);
    }
    for (final ok in [
      'openssl base64 -A -d',
      'curl --connect-timeout 10 x',
      '/bin/sh -c x',
      '# no hexdump on stock',
      'awk \'{print \$1}\'',
      'nvram get wgc1_dns',
      'openssl dgst -sha256 f || sha256sum f',
      "'no checksum tool on the router (openssl, sha256sum)'",
    ]) {
      expect(_uses('t', ok), isEmpty, reason: ok);
    }
  });

  test('the deployed scripts use only tools stock BusyBox has', () {
    final problems = <String>[
      for (final fw in RouterFirmware.values)
        for (final email in [false, true])
          ..._uses('watchdog ${fw.name} email=$email', buildWatchdogScript(_config(email: email), firmware: fw)),
      ..._uses('guard.sh', kGuardScript),
      ..._uses('S50', buildS50Script([kGuardCronLine])),
    ];
    expect(problems, isEmpty);
  });

  test('no string in lib/ asks the router for a tool it lacks', () {
    final problems = <String>[
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
        ..._uses(f.path.replaceAll('\\', '/'), f.readAsStringSync()),
    ];
    expect(problems, isEmpty);
  });
}
