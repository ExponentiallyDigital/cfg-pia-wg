// router_session.dart - one SSH connection to the router, shared by every action.
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
// Every user action used to open its own connection: socket, handshake, password auth, a handful
// of commands, close. That is a `dropbear[NNNN]: Password auth succeeded` line in the router log
// per button press, and a full handshake's latency before anything visibly happens.
//
// The old code was not careless about it - a fresh client per action meant a dropped connection
// self-healed on the next one, which is a real property. Reuse has to replace it explicitly, and
// that is what the retry below is for: without it we would have traded log noise for intermittent
// action failures, which is a bad trade.
//
// This is an `SSHClient` itself rather than a wrapper with a `client()` getter, so nothing
// downstream had to change: the services still take an `SSHClient`, and the test fakes still
// substitute for one.

import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Errors that mean the connection is gone rather than the command being wrong.
///
/// `client.run` does not throw for a non-zero exit status - it returns whatever the command wrote -
/// so a throw is nearly always transport-level. The list is still explicit: retrying an error we do
/// not understand risks running a command twice for no reason.
bool isConnectionLost(Object error) {
  if (error is SSHStateError || error is SSHAuthAbortError) return true;
  final s = error.toString().toLowerCase();
  return s.contains('closed') ||
      s.contains('connection reset') ||
      s.contains('broken pipe') ||
      s.contains('socketexception');
}

/// A long-lived router connection that opens on demand and survives a drop.
///
/// One instance lives on `SessionController` for as long as the app holds router credentials.
/// [close] is the session teardown, so **an action must never call it** - it would pull the
/// connection out from under the next one. A source scan in `test/unit/router_session_test.dart`
/// enforces that.
class RouterSession implements SSHClient {
  /// Opens a brand-new authenticated client. Injected so tests need no socket.
  final Future<SSHClient> Function() connect;

  final void Function(String, {bool isError, bool isSuccess})? onLog;

  SSHClient? _client;
  Future<SSHClient>? _opening;
  bool _closed = false;

  RouterSession({required this.connect, this.onLog});

  /// How many connections this session has opened. Reuse is the whole point, so it is worth being
  /// able to assert on it.
  int get connectCount => _connectCount;
  int _connectCount = 0;

  /// True while a client is held. Deliberately not `!_client!.isClosed`: that only goes true after
  /// a clean close, so a connection the router silently dropped still reports itself open. A failed
  /// command is the honest liveness test, which is what [run]'s retry is for.
  bool get isConnected => _client != null;

  /// The live client, opening one if there is none. Concurrent callers share a single open rather
  /// than racing to make two connections - the slot modal fires several actions off one tap.
  Future<SSHClient> client() {
    _closed = false;
    final existing = _client;
    if (existing != null) return Future.value(existing);
    return _opening ??= _open();
  }

  Future<SSHClient> _open() async {
    try {
      final c = await connect();
      _connectCount++;
      _client = c;
      return c;
    } finally {
      _opening = null;
    }
  }

  /// Forgets the current client without waiting on it. A connection the router has already dropped
  /// can hang on close, and there is nothing to salvage.
  void _drop() {
    final dead = _client;
    _client = null;
    if (dead != null) {
      unawaited(Future(() async {
        try {
          await dead.close();
        } catch (_) {
          // Already gone; closing was only tidiness.
        }
      }));
    }
  }

  @override
  Future<Uint8List> run(
    String command, {
    Map<String, String>? environment,
    bool runInPty = false,
    bool stderr = true,
    bool stdout = true,
  }) async {
    final c = await client();
    try {
      return await c.run(command, environment: environment, runInPty: runInPty, stderr: stderr, stdout: stdout);
    } catch (e) {
      if (_closed || !isConnectionLost(e)) rethrow;
      // One reconnect, one retry. `service restart_vpnc` and `restart_firewall` can take the
      // session down mid-action, and this is what used to happen for free by connecting afresh.
      //
      // A command that had already run when the connection died will run twice. Everything sent
      // here is idempotent (`nvram set`, `cru a`, `nvram commit`) except a chunked heredoc append,
      // where a double write shows up as a byte-count mismatch in `_writeScript` and is reported
      // rather than silently accepted - and the next deploy truncates the file first anyway.
      _drop();
      onLog?.call('Router SSH connection dropped; reconnecting.', isError: true);
      final fresh = await client();
      return await fresh.run(command, environment: environment, runInPty: runInPty, stderr: stderr, stdout: stdout);
    }
  }

  /// Resolves once a client is up. `openSshClient` already awaits authentication, so reaching here
  /// at all means the router accepted the credentials.
  @override
  Future<void> get authenticated => client();

  /// Session teardown - idempotent, and safe to call on a connection that is already gone.
  ///
  /// Only `SessionController` should call this: on wipe, and when the app goes to the background
  /// (an authenticated session held open behind a locked screen is a wider exposure than
  /// credentials sitting in memory).
  @override
  Future<void> close() async {
    _closed = true;
    final c = _client;
    _client = null;
    _opening = null;
    if (c == null) return;
    try {
      await c.close();
    } catch (_) {
      // The router may have dropped it already; nothing to report.
    }
  }

  @override
  bool get isClosed => _client == null;

  // Nothing downstream touches the rest of the SSHClient surface (sftp, forwarding, shells), and
  // forwarding it would mean holding a client open just to hand it out.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
