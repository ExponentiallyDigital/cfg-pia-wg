// test/unit/router_command_test.dart - a failed router command must not look like an answer.
//
// Until build 413 every command went through `utf8.decode(await client.run(cmd)).trim()`, which
// merges stderr into stdout and throws the exit code away. Two consequences, and the first is the
// serious one:
//
//   - a failing `nvram get` returned its ERROR MESSAGE where its value should have been, and the
//     app carried on with that as data;
//   - 115 of 125 commands could fail in complete silence.
//
// So these tests are about failure, not success: that stderr never reaches a caller as a value,
// that a write which fails is fatal, that a read which fails is not, that both are logged, and
// that nothing logged carries a credential.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cfg_pia_wg/router_command.dart';
import 'package:cfg_pia_wg/router_slot_service.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

/// Answers one command with whatever the test asks for.
class _Fake implements SSHClient {
  _Fake({this.stdout = '', this.stderr = '', this.exitCode = 0});
  final String stdout, stderr;
  final int? exitCode;

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async =>
      SSHRunResult(
        output: Uint8List.fromList(utf8.encode(this.stdout + this.stderr)),
        stdout: Uint8List.fromList(utf8.encode(this.stdout)),
        stderr: Uint8List.fromList(utf8.encode(this.stderr)),
        exitCode: exitCode,
        exitSignal: null,
      );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('RouterResult', () {
    test('a null exit code counts as success', () {
      // Some `service` calls return without one. Inventing a failure from absent metadata would be
      // worse than assuming it worked.
      expect(const RouterResult(stdout: '', stderr: '', exitCode: null).ok, isTrue);
      expect(const RouterResult(stdout: '', stderr: '', exitCode: 0).ok, isTrue);
      expect(const RouterResult(stdout: '', stderr: '', exitCode: 1).ok, isFalse);
    });

    test('failureDetail leads with the code and adds what the command said', () {
      expect(const RouterResult(stdout: '', stderr: '', exitCode: 7).failureDetail, 'exit 7');
      expect(
        const RouterResult(stdout: '', stderr: 'nvram: not found', exitCode: 127).failureDetail,
        'exit 127: nvram: not found',
      );
      expect(const RouterResult(stdout: '', stderr: 'boom', exitCode: null).failureDetail, 'no exit code: boom');
    });

    test('only the first line of stderr, and it is capped', () {
      final r = RouterResult(stdout: '', stderr: 'first\nsecond\nthird', exitCode: 1);
      expect(r.failureDetail, 'exit 1: first');
      expect(RouterResult(stdout: '', stderr: 'x' * 400, exitCode: 1).failureDetail.length, lessThan(200));
    });
  });

  group('redactCommand', () {
    // The app log is shown on screen and pasted into bug reports. A failed `nvram set` of a
    // password must not report the password.
    test('masks the value of a secret-looking key', () {
      expect(redactCommand("nvram set wgc1_wd_smtp_pass='hunter2'"), 'nvram set wgc1_wd_smtp_pass=<redacted>');
      expect(redactCommand('nvram set cfg_pia_wg_password=s3cret'), 'nvram set cfg_pia_wg_password=<redacted>');
      expect(redactCommand("nvram set wgc1_priv='abc123='"), 'nvram set wgc1_priv=<redacted>');
      expect(redactCommand('nvram set wgc1_psk=xyz'), 'nvram set wgc1_psk=<redacted>');
    });

    test('redacts the PIA username too - it identifies an account', () {
      expect(redactCommand('nvram set cfg_pia_wg_user=p1234567'), 'nvram set cfg_pia_wg_user=<redacted>');
    });

    test('leaves harmless assignments legible, or the message is useless', () {
      expect(redactCommand('nvram set wgc1_enable=1'), 'nvram set wgc1_enable=1');
      expect(redactCommand("nvram set wgc1_desc='pia-aus_melbourne'"), "nvram set wgc1_desc='pia-aus_melbourne'");
      expect(redactCommand('nvram get wgc1_ep_addr'), 'nvram get wgc1_ep_addr');
    });

    test('caps the length so one command cannot flood the log', () {
      final long = redactCommand('nvram set wgc1_desc=${'a' * 500}');
      expect(long.length, lessThanOrEqualTo(123));
      expect(long, endsWith('...'));
    });

    test('every fragment in the list actually redacts', () {
      for (final f in kSecretKeyFragments) {
        expect(redactCommand('nvram set some_${f}_thing=value'), contains('<redacted>'), reason: f);
      }
    });
  });

  group('runRouterCommand', () {
    test('returns stdout only - stderr never reaches the caller as a value', () async {
      // The bug this whole file exists for: `run()` merges the two, so a failing `nvram get` used
      // to hand its error message back as though it were the key's value.
      final r = await runRouterCommand(_Fake(stdout: 'the value', stderr: 'a warning'), 'nvram get x');
      expect(r.stdout, 'the value');
      expect(r.stderr, 'a warning');
    });

    test('a failing WRITE throws, carrying the code and the reason', () async {
      final fake = _Fake(stderr: 'nvram: write failed', exitCode: 1);
      await expectLater(
        () => runRouterCommand(fake, 'nvram set wgc1_enable=1'),
        throwsA(isA<RouterCommandException>()
            .having((e) => e.toString(), 'message', allOf(contains('exit 1'), contains('write failed')))),
      );
    });

    test('a failing READ does not throw, and still yields its stdout', () async {
      // `cru d` on an absent job, `grep -c` with no match, `which jq` as a probe: non-zero is the
      // answer, not a fault. Throwing here would bury the failures that matter.
      final r = await runRouterCommand(_Fake(stdout: 'partial', stderr: 'not found', exitCode: 1), 'cru d x', allowFailure: true);
      expect(r.ok, isFalse);
      expect(r.stdout, 'partial');
    });

    test('BOTH are logged - a tolerated failure is still diagnosable', () async {
      final logged = <String>[];
      await runRouterCommand(_Fake(stderr: 'nope', exitCode: 1), 'cru d x',
          allowFailure: true, onLog: (m, {bool isError = false, bool isSuccess = false, bool isWarning = false}) => logged.add(m));
      expect(logged.single, allOf(contains('exit 1'), contains('nope'), contains('cru d x')));
    });

    test('a tolerated failure is not flagged as an error, a fatal one is', () async {
      // The difference between "worth recording" and "worth interrupting someone over". If every
      // absent-key probe raised an error, the one that mattered would be dismissed with the rest.
      final flags = <bool>[];
      void capture(String m, {bool isError = false, bool isSuccess = false, bool isWarning = false}) => flags.add(isError);

      await runRouterCommand(_Fake(exitCode: 1), 'cru d x', allowFailure: true, onLog: capture);
      expect(flags.single, isFalse);

      flags.clear();
      try {
        await runRouterCommand(_Fake(exitCode: 1), 'nvram set a=b', onLog: capture);
        fail('a failing write must throw');
      } on RouterCommandException {
        // expected
      }
      expect(flags.single, isTrue);
    });

    test('the logged command is REDACTED', () async {
      final logged = <String>[];
      try {
        await runRouterCommand(_Fake(exitCode: 1), "nvram set wgc1_wd_smtp_pass='hunter2'",
            onLog: (m, {bool isError = false, bool isSuccess = false, bool isWarning = false}) => logged.add(m));
      } catch (_) {
        // expected
      }
      expect(logged.single, contains('<redacted>'));
      expect(logged.single, isNot(contains('hunter2')));
    });

    test('the exception text is redacted too, since it reaches the UI', () async {
      final e = RouterCommandException(
        "nvram set wgc1_priv='PRIVATEKEY'",
        const RouterResult(stdout: '', stderr: 'denied', exitCode: 1),
      );
      expect(e.toString(), isNot(contains('PRIVATEKEY')));
      expect(e.toString(), contains('<redacted>'));
    });

    test('success logs nothing', () async {
      final logged = <String>[];
      await runRouterCommand(_Fake(stdout: 'ok'), 'nvram get x',
          onLog: (m, {bool isError = false, bool isSuccess = false, bool isWarning = false}) => logged.add(m));
      expect(logged, isEmpty);
    });
  });

  group('through the real services', () {
    // The unit tests above prove the policy. These prove it is actually WIRED - that a failing
    // write reaches the caller as an exception rather than being swallowed the way it was before.
    test('a failing nvram write surfaces from RouterSlotService', () async {
      // Merlin: enableSlot's first act is the write, so nothing can fail ahead of it.
      useMerlin();
      final ssh = RecordingSSHClient()..failWith['nvram set wgc1_enable=1'] = 'nvram: write failed';
      final logged = <String>[];
      final svc = RouterSlotService(ssh, onLog: (m, {bool isError = false, bool isSuccess = false, bool isWarning = false}) => logged.add(m));

      await expectLater(() => svc.enableSlot(1, primaryIp: '8.8.8.8', secondaryIp: '1.1.1.1'), throwsA(anything));
      expect(logged.any((l) => l.contains('exit 1') && l.contains('write failed')), isTrue,
          reason: 'the failure must be in the app log, not only thrown');
    });

    test('a failing READ is logged but does not stop the action', () async {
      useMerlin();
      final ssh = RecordingSSHClient()..failWith['nvram get wgc1_desc'] = 'nvram: cannot read';
      final logged = <String>[];
      final svc = RouterSlotService(ssh, onLog: (m, {bool isError = false, bool isSuccess = false, bool isWarning = false}) => logged.add(m));

      // fetchSlots reads a description per slot; one unreadable key must not fail the whole read.
      await svc.fetchSlots();
      expect(logged.any((l) => l.contains('cannot read')), isTrue, reason: 'still diagnosable');
    });
  });
}
