// test/unit/router_session_test.dart - one connection, reused, and honest about losing it.
//
// Every action used to open its own SSH connection: a dropbear login line in the router log and a
// full handshake's latency per button press. Sharing one connection is easy; the hard part is that
// the old code got a real property for free - a dropped connection self-healed because the next
// action simply connected again. RouterSession has to reproduce that deliberately, or the trade is
// log noise for intermittent action failures, which is a bad trade.
//
// So the tests that matter are the failure ones: a lost connection reconnects and the command
// still runs, a second failure is reported rather than retried forever, and an ordinary error is
// never retried at all (running `nvram set` twice because a command failed for its own reasons
// would be worse than the original problem).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/router_session.dart';
import 'package:cfg_pia_wg/session_controller.dart';

/// A client that answers every command, and can be told to fail the next N of them.
class _FakeClient implements SSHClient {
  final List<String> commands = [];
  final Object? Function(int callIndex)? failWith;
  bool closed = false;
  int _calls = 0;

  _FakeClient({this.failWith});

  @override
  Future<Uint8List> run(
    String command, {
    Map<String, String>? environment,
    bool runInPty = false,
    bool stderr = true,
    bool stdout = true,
  }) async {
    final failure = failWith?.call(_calls++);
    commands.add(command);
    if (failure != null) throw failure;
    return Uint8List.fromList(utf8.encode('ok:$command'));
  }

  @override
  Future<void> close() async => closed = true;

  @override
  Future<void> get authenticated => Future.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hands out a new [_FakeClient] per connect, recording each one.
class _Opener {
  final List<_FakeClient> opened = [];
  final Object? Function(int callIndex)? Function(int clientIndex)? failures;

  _Opener({this.failures});

  Future<SSHClient> call() async {
    final c = _FakeClient(failWith: failures?.call(opened.length));
    opened.add(c);
    return c;
  }
}

SessionController _controller() =>
    SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

void main() {
  group('reuse', () {
    test('several actions share one connection', () async {
      final opener = _Opener();
      final session = RouterSession(connect: opener.call);

      for (var i = 0; i < 5; i++) {
        await session.run('nvram get wgc${i}_desc');
      }

      expect(opener.opened, hasLength(1), reason: 'one handshake, one dropbear login line');
      expect(session.connectCount, 1);
      expect(opener.opened.single.commands, hasLength(5));
    });

    // The slot modal fires several reads off one tap. Two racing opens would be two connections,
    // and the loser would be leaked.
    test('concurrent first actions share a single open', () async {
      final opener = _Opener();
      final session = RouterSession(connect: opener.call);

      await Future.wait([session.run('a'), session.run('b'), session.run('c')]);

      expect(opener.opened, hasLength(1));
    });

    test('nothing is opened until something is actually run', () {
      final opener = _Opener();
      RouterSession(connect: opener.call);
      expect(opener.opened, isEmpty);
    });
  });

  group('a lost connection', () {
    test('reconnects once and the command still runs', () async {
      final opener = _Opener(failures: (client) => client == 0 ? (call) => SSHStateError('connection closed') : null);
      final session = RouterSession(connect: opener.call);

      final out = await session.run('nvram get wgc1_desc');

      expect(utf8.decode(out), 'ok:nvram get wgc1_desc');
      expect(opener.opened, hasLength(2), reason: 'the dead one was replaced');
      expect(opener.opened.last.commands, ['nvram get wgc1_desc'], reason: 'the retry ran on the new client');
    });

    test('is reported to the app log, so an odd pause in the log has an explanation', () async {
      final opener = _Opener(failures: (client) => client == 0 ? (call) => SSHStateError('closed') : null);
      final lines = <String>[];
      final session = RouterSession(connect: opener.call, onLog: (m, {isError = false, isSuccess = false}) => lines.add(m));

      await session.run('x');

      expect(lines, ['Router SSH connection dropped; reconnecting.']);
    });

    // Retrying forever would turn a dead router into a hang.
    test('a second failure propagates rather than retrying again', () async {
      final opener = _Opener(failures: (client) => (call) => SSHStateError('closed'));
      final session = RouterSession(connect: opener.call);

      await expectLater(session.run('x'), throwsA(isA<SSHStateError>()));
      expect(opener.opened, hasLength(2), reason: 'one reconnect, not a loop');
    });

    test('the next action after a drop reuses the replacement, not a third connection', () async {
      final opener = _Opener(failures: (client) => client == 0 ? (call) => SSHStateError('closed') : null);
      final session = RouterSession(connect: opener.call);

      await session.run('one');
      await session.run('two');

      expect(opener.opened, hasLength(2));
      expect(opener.opened.last.commands, ['one', 'two']);
    });
  });

  group('an error that is not a lost connection', () {
    // `client.run` returns a failing command's output rather than throwing, so a throw is nearly
    // always transport-level - but "nearly" is why this is not a blanket retry. Running `nvram set`
    // or a heredoc append twice because of an error we did not understand is the worse outcome.
    test('is never retried', () async {
      final opener = _Opener(failures: (client) => (call) => Exception('jq: parse error'));
      final session = RouterSession(connect: opener.call);

      await expectLater(session.run('x'), throwsA(isA<Exception>()));
      expect(opener.opened, hasLength(1), reason: 'no reconnect for an error the router itself raised');
    });

    test('isConnectionLost recognises the transport failures and nothing else', () {
      expect(isConnectionLost(SSHStateError('connection closed')), isTrue);
      expect(isConnectionLost(const SocketException('Broken pipe')), isTrue);
      expect(isConnectionLost(StateError('The connection is closed')), isTrue);
      expect(isConnectionLost(Exception('Connection reset by peer')), isTrue);

      expect(isConnectionLost(Exception('jq: command not found')), isFalse);
      expect(isConnectionLost(Exception('nvram: invalid argument')), isFalse);
      expect(isConnectionLost(FormatException('bad json')), isFalse);
    });
  });

  group('teardown', () {
    test('close is idempotent and closes the live client', () async {
      final opener = _Opener();
      final session = RouterSession(connect: opener.call);
      await session.run('x');

      await session.close();
      await session.close();

      expect(opener.opened.single.closed, isTrue);
      expect(session.isConnected, isFalse);
    });

    test('the next action after close opens a fresh connection', () async {
      final opener = _Opener();
      final session = RouterSession(connect: opener.call);
      await session.run('x');
      await session.close();

      await session.run('y');

      expect(opener.opened, hasLength(2));
      expect(session.isConnected, isTrue);
    });

    test('closing a session that never connected does nothing', () async {
      final opener = _Opener();
      await RouterSession(connect: opener.call).close();
      expect(opener.opened, isEmpty);
    });

    test('a client that throws on close does not break teardown', () async {
      final session = RouterSession(connect: () async => _ThrowingCloseClient());
      await session.run('x');
      await session.close();
      expect(session.isConnected, isFalse);
    });
  });

  group('SessionController owns it', () {
    test('hands out the same session while the credentials are unchanged', () {
      final c = _controller()
        ..routerIp = '192.168.0.254'
        ..sshUsername = 'admin'
        ..sshPassword = 'pw';
      final opener = _Opener();

      expect(identical(c.routerSession(opener.call), c.routerSession(opener.call)), isTrue);
      c.dispose();
    });

    // Reusing a connection authenticated as someone else, or to a different box, would silently
    // ignore what the user just typed.
    test('a change of credentials gets a new session', () async {
      final c = _controller()
        ..routerIp = '192.168.0.254'
        ..sshUsername = 'admin'
        ..sshPassword = 'pw';
      final opener = _Opener();
      final first = c.routerSession(opener.call);
      await first.run('x');

      c.sshPassword = 'different';
      final second = c.routerSession(opener.call);

      expect(identical(first, second), isFalse);
      expect(second.isConnected, isFalse, reason: 'it connects on demand, against the new credentials');
      c.dispose();
    });

    test('wipeAll closes it, so every exit path already tears the connection down', () async {
      final c = _controller();
      final opener = _Opener();
      await c.routerSession(opener.call).run('x');

      await c.wipeAll();

      expect(opener.opened.single.closed, isTrue);
      c.dispose();
    });

    test('closeRouterSession is safe when nothing was ever opened', () async {
      final c = _controller();
      await c.closeRouterSession();
      c.dispose();
    });
  });

  // A stray close in an action's finally would pull the connection out from under the next action -
  // exactly the intermittent-failure mode this change has to avoid. The old code had about twenty
  // of them, one per action, which was correct then and is a bug now.
  test('no screen or dialog closes the shared client', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('router_session.dart') || f.path.endsWith('pia_service.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(r'\bclient\??\.close\(\)').allMatches(src)) {
        offenders.add('${f.path}: ${m.group(0)}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'only SessionController may close the shared session (wipe, or app backgrounded)');
  });
}

class _ThrowingCloseClient extends _FakeClient {
  @override
  Future<void> close() async => throw const SocketException('already gone');
}
