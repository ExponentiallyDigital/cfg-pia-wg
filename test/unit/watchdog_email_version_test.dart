// Every email the watchdog sends says which app version and build deployed it (ID-634).
//
// Slots are deployed separately, so an alert can come from a script a build or more behind the app, and
// the email has to say which. The version was stamped into each script's header and into the Watchdog row
// of the emails the script sends; nothing checked it, and the app's own test email didn't carry it. Run for
// real against the fake router in test/watchdog_harness.dart: each email type, from a script of its own
// build, and a second slot's script from an older one.
@Timeout(Duration(minutes: 2))
library;

import 'package:cfg_pia_wg/firmware.dart' show appVersionLabel;
import 'package:cfg_pia_wg/watchdog_email_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_harness.dart';

const _build = 'v0.8.218 build 588';
const _older = 'v0.8.184 build 554';

void main() {
  final shell = findShell();
  final skip = shell == null ? 'no POSIX shell on the PATH' : null;
  late WatchdogHarness h;

  setUp(() {
    appVersionLabel = _build;
    if (shell != null) {
      h = WatchdogHarness.create(shell: shell)!..captureMail();
      h.tunnelUp(handshakeAgo: 30);
    }
  });
  tearDown(() {
    appVersionLabel = '';
    if (shell != null) h.dispose();
  });

  String row(String mail) => mail.split('\n').firstWhere((l) => l.startsWith('Watchdog:'), orElse: () => '(no Watchdog row)');

  test('a SUCCESS email, after a rebuild, names the version and build that deployed the script', () async {
    h.tunnelDown();
    final r = await h.run();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final mail = h.mails.single;
    expect(mail, contains('has been rebuilt'), reason: mail);
    expect(row(mail), contains('deployed by cfg-pia-wg $_build'), reason: mail);
  }, skip: skip);

  test('a FAILED email, when the rebuild fails, names it too', () async {
    h.tunnelDown();
    h.piaDown();
    final r = await h.run();
    expect(r.exitCode, isNot(2), reason: '${r.stdout}${r.stderr}');
    final mail = h.mails.single;
    expect(mail, contains('could NOT be rebuilt'), reason: mail);
    expect(row(mail), contains('deployed by cfg-pia-wg $_build'), reason: mail);
  }, skip: skip);

  test('a RECOVERED email, when the tunnel mends itself, names it too', () async {
    h.backoff(2, 60);
    await h.run();
    final mail = h.mails.single;
    expect(mail, contains('working again without a rebuild'), reason: mail);
    expect(row(mail), contains('deployed by cfg-pia-wg $_build'), reason: mail);
  }, skip: skip);

  test('the email a deploy sends names it too', () async {
    h.tunnelDown();
    await h.run(mode: 'deploy');
    final mail = h.mails.single;
    expect(row(mail), contains('deployed by cfg-pia-wg $_build'), reason: mail);
  }, skip: skip);

  test('the fault email, from a script that could not do its job, names it too', () async {
    await h.run(mode: 'fault', args: ['guard.sh is damaged']);
    final mail = h.mails.single;
    expect(mail, contains('could not do its job'), reason: mail);
    expect(row(mail), contains('deployed by cfg-pia-wg $_build'), reason: mail);
  }, skip: skip);

  test('a slot deployed from an older build shows its own, not the app\'s', () async {
    appVersionLabel = _older;
    final older = h.script();
    appVersionLabel = _build;
    expect(older, contains('APPVER="$_older"'));
    h.tunnelDown();
    // The script on the router is the older one: the app has moved on, and the email must not say so.
    await h.run(edit: (_) => older);
    final mail = h.mails.single;
    expect(row(mail), contains('deployed by cfg-pia-wg $_older'), reason: mail);
    expect(mail, isNot(contains(_build)));
  }, skip: skip);

  test('control: a script that does not stamp the version is seen, so these checks can fail', () async {
    h.tunnelDown();
    await h.run(edit: (s) => s.replaceAll('deployed by cfg-pia-wg', 'deployed by'));
    expect(row(h.mails.single), isNot(contains('deployed by cfg-pia-wg $_build')));
  }, skip: skip);

  test('a script written by a build that knew no version says nothing rather than something false', () async {
    appVersionLabel = '';
    h.tunnelDown();
    await h.run();
    expect(row(h.mails.single), isNot(contains('deployed by')));
  }, skip: skip);

  group('the test email, which the app sends itself', () {
    final facts = RouterEmailFacts.parse('X');

    test('says which version and build sent it', () {
      expect(facts.routerRows(1, desc: 'pia-nz', sentBy: _build).last, 'Watchdog: wgc1:pia-nz, sent by cfg-pia-wg $_build');
    });

    test('says nothing about it when the app does not know its own version', () {
      expect(facts.routerRows(1, desc: 'pia-nz').last, 'Watchdog: wgc1:pia-nz');
    });
  });
}
