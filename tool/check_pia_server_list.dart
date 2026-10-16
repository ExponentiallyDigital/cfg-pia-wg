// tool/check_pia_server_list.dart - has PIA changed the key it signs its server list with? (ID-409)
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see https://www.gnu.org/licenses/.
//
// Copyright (C) 2026 Andrew Newbury.
//
// Run daily by pia_key_check.yml:
// `dart run tool/check_pia_server_list.dart --out out [--list-failed-last-time] [--swap-key]`.
//
// Since build 497 the app and the watchdog refuse a list that fails PIA's signature check and fall back
// to the last one that passed (ID-325). That carries users through a key change, and hides one. This
// says when the key has changed, so a build with the new key can follow, and says NOTHING otherwise:
// Andrew's requirement, 2026-10-16, is an email if and only if the key changes.
//
// Either of two signals means it changed:
//  1. The key PIA publishes - `Environment::defaultRegionsListPublicKey` in pia-foss/desktop's
//     `daemon/src/environment.cpp` - isn't ours.
//  2. PIA's live list downloads but fails our check, on this run and the last one too. One failure
//     alone could be a bad download; two in a row aren't. This also catches a key PIA moves on its
//     servers before its desktop source.
// A download that fails, or a source file that has moved or changed shape, is neither: it is printed
// as a warning and changes nothing.
//
// Writes `changed` and `list_failed` to $GITHUB_OUTPUT when that is set, and the report for the email
// and the issue to <out>/report.txt. Always exits 0, whatever it finds or fails to find: a failed run
// would itself send GitHub's failed-workflow email, which is an email that isn't a key change.

import 'dart:convert';
import 'dart:io';

import 'package:cfg_pia_wg/server_list_verify.dart';

const String kPublishedKeySource = 'https://raw.githubusercontent.com/pia-foss/desktop/master/daemon/src/environment.cpp';
const String kServerListUrl = 'https://serverlist.piaservers.net/vpninfo/servers/v6';
const String kIssueTitle = 'PIA server list key changed';

/// What the published key says.
enum PublishedKey { matches, differs, unavailable }

/// What PIA's live list says.
enum LiveList { passes, fails, unavailable }

/// The key PEM in pia-foss/desktop's environment.cpp, or null when the definition isn't there or isn't
/// the shape it was on 2026-10-16: string literals, one per PEM line, inside `QByteArrayLiteral(...)`.
String? publishedKeyFromSource(String cpp) {
  final start = RegExp(r'defaultRegionsListPublicKey\s*=\s*QByteArrayLiteral\(').firstMatch(cpp);
  if (start == null) return null;
  final end = cpp.indexOf(');', start.end);
  if (end < 0) return null;
  final literals = RegExp(r'"((?:[^"\\]|\\.)*)"').allMatches(cpp.substring(start.end, end));
  final pem = literals.map((m) => m.group(1)!.replaceAll(r'\n', '\n')).join();
  return pem.contains('-----BEGIN PUBLIC KEY-----') && pem.contains('-----END PUBLIC KEY-----') ? pem : null;
}

/// The key's base64, with the PEM armour and all whitespace gone, so line endings can't make two
/// copies of the same key differ.
String keyBody(String pem) => pem.split('\n').where((l) => !l.startsWith('-----')).join().replaceAll(RegExp(r'\s'), '');

/// [pem] with one character of its key changed: a different key, for the hand test of the email.
String swappedKey(String pem) {
  final at = pem.indexOf('\n', pem.indexOf('\n') + 1) + 10; // in the second base64 line: the modulus
  return pem.replaceRange(at, at + 1, pem[at] == 'A' ? 'B' : 'A');
}

PublishedKey comparePublished(String? cpp, String ourPem) {
  final published = cpp == null ? null : publishedKeyFromSource(cpp);
  if (published == null) return PublishedKey.unavailable;
  return keyBody(published) == keyBody(ourPem) ? PublishedKey.matches : PublishedKey.differs;
}

LiveList checkLive(List<int>? body, String ourPem) {
  if (body == null || body.isEmpty) return LiveList.unavailable;
  return verifySignedServerList(body, ourPem) == null ? LiveList.fails : LiveList.passes;
}

/// Whether the key has changed: the published key differs, or the live list failed now and last time.
bool keyChanged(PublishedKey published, LiveList live, {required bool listFailedLastTime}) =>
    published == PublishedKey.differs || (live == LiveList.fails && listFailedLastTime);

/// The email and issue text.
String report({
  required PublishedKey published,
  required LiveList live,
  required bool listFailedLastTime,
  required String? publishedPem,
  required bool swapped,
}) {
  final b = StringBuffer();
  if (swapped) {
    b.writeln('TEST RUN: this run checked with a deliberately wrong key (swap_key), to prove the email '
        'and the issue fire. Nothing has changed at PIA. Close this issue to re-arm the check.\n');
  }
  b.writeln("PIA's server list key appears to have changed.\n");
  b.writeln('The key PIA publishes (pia-foss/desktop, daemon/src/environment.cpp): ${switch (published) {
    PublishedKey.differs => 'DIFFERS from ours',
    PublishedKey.matches => 'matches ours',
    PublishedKey.unavailable => "couldn't be read",
  }}.');
  b.writeln('PIA\'s live server list: ${switch (live) {
    LiveList.fails => listFailedLastTime ? 'FAILS our check, and failed on the last run too' : 'fails our check (first time)',
    LiveList.passes => 'passes our check',
    LiveList.unavailable => "couldn't be downloaded",
  }}.');
  if (published == PublishedKey.differs && publishedPem != null) {
    b.writeln('\nThe key PIA publishes now:\n\n$publishedPem');
  }
  b.writeln('\nUntil a build carries the new key, the app and the watchdog keep using the last list that '
      'passed, and every region picker says so.\n');
  b.writeln('To do: confirm the new key from PIA\'s source, put it in kPiaServerListKeyPem in '
      'lib/server_list_verify.dart (the watchdog takes it from there), run the tests, and release. Then '
      'close this issue: while it is open, no further email is sent.');
  return b.toString();
}

/// One GET, or null for anything but a 200 with a body: a failed download is never a finding.
Future<List<int>?> download(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 30));
    final response = await request.close().timeout(const Duration(seconds: 60));
    final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      stdout.writeln('::warning::$uri returned HTTP ${response.statusCode}');
      return null;
    }
    return bytes;
  } catch (e) {
    stdout.writeln('::warning::$uri could not be downloaded: $e');
    return null;
  } finally {
    client.close(force: true);
  }
}

/// The check, with the downloads passed in so a test can run it without the network.
Future<({bool changed, LiveList live, String report})> runCheck({
  required Future<List<int>?> Function(Uri) fetch,
  required bool listFailedLastTime,
  bool swapKey = false,
}) async {
  final ours = swapKey ? swappedKey(kPiaServerListKeyPem) : kPiaServerListKeyPem;
  final source = await fetch(Uri.parse(kPublishedKeySource));
  final cpp = source == null ? null : utf8.decode(source, allowMalformed: true);
  final published = comparePublished(cpp, ours);
  if (cpp != null && published == PublishedKey.unavailable) {
    stdout.writeln('::warning::environment.cpp downloaded but defaultRegionsListPublicKey was not found in it: '
        'the source has moved or changed shape, so only the live list is being checked');
  }
  final live = checkLive(await fetch(Uri.parse(kServerListUrl)), ours);
  final changed = keyChanged(published, live, listFailedLastTime: listFailedLastTime);
  stdout.writeln('published key: ${published.name}; live list: ${live.name}; '
      'failed last time: $listFailedLastTime; changed: $changed${swapKey ? ' (TEST: swapped key)' : ''}');
  return (
    changed: changed,
    live: live,
    report: report(
      published: published,
      live: live,
      listFailedLastTime: listFailedLastTime,
      publishedPem: cpp == null ? null : publishedKeyFromSource(cpp),
      swapped: swapKey,
    ),
  );
}

Future<void> main(List<String> args) async {
  String? outDir;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--out' && i + 1 < args.length) outDir = args[++i];
  }
  var changed = false, listFailed = false;
  try {
    final r = await runCheck(
      fetch: download,
      listFailedLastTime: args.contains('--list-failed-last-time'),
      swapKey: args.contains('--swap-key'),
    );
    changed = r.changed;
    listFailed = r.live == LiveList.fails;
    if (outDir != null) {
      Directory(outDir).createSync(recursive: true);
      File('$outDir/report.txt').writeAsStringSync(r.report);
    }
  } catch (e) {
    stdout.writeln('::warning::the check itself failed, so nothing is reported: $e');
  }
  final output = Platform.environment['GITHUB_OUTPUT'];
  if (output != null && output.isNotEmpty) {
    File(output).writeAsStringSync('changed=$changed\nlist_failed=$listFailed\n', mode: FileMode.append);
  }
}
