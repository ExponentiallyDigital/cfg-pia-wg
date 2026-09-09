// test/watchdog_test_utils.dart - shared SSH fake for watchdog tests.
import 'dart:convert';
import 'dart:typed_data';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the detected-firmware flag for one test and restores the unset default afterwards.
///
/// The flag is a library global (see lib/firmware.dart), so a test that leaves it set will leak
/// into the next one. Every test touching router code should call this or [useMerlin].
void useFirmware(RouterFirmware firmware) {
  setRouterFirmware(firmware);
  addTearDown(resetRouterFirmware);
}

void useMerlin() => useFirmware(RouterFirmware.merlin);
void useStock() => useFirmware(RouterFirmware.stock);

/// The router clock the fake reports, for both `date +%s` and a WireGuard handshake stamp -
/// equal, so the handshake reads as having just happened.
const int kFakeNow = 1700000000;

/// A fake [SSHClient] that records every command and returns canned output.
///
/// - [responder] maps a command string to its stdout (default: empty string).
/// - [throwOn] is a list of substrings; any command containing one throws,
///   used to exercise error-handling paths.
///
/// A healthy WireGuard handshake is assumed unless a test says otherwise: `latest-handshakes` and
/// `date +%s` both answer [kFakeNow] when the responder has nothing to say, so ENABLE's handshake
/// gate passes and tests about other things stay about other things. Return `'0'` for
/// `latest-handshakes` to model a tunnel the peer never answered.
class RecordingSSHClient implements SSHClient {
  final List<String> commands = [];
  final String Function(String cmd)? responder;
  final List<String> throwOn;

  RecordingSSHClient({this.responder, this.throwOn = const []});

  @override
  Future<void> get authenticated => Future.value();

  /// Commands the fake should report as having FAILED, by substring. The exit code is 1 and the
  /// text becomes stderr, so a test can exercise the strict-write path without an SSH server.
  final Map<String, String> failWith = {};

  /// The path the app takes since 413: stdout and stderr apart, plus an exit code.
  ///
  /// [run] is kept delegating to this so the two can never disagree about what a command did.
  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    final out = await run(command, environment: environment, runInPty: runInPty, stderr: stderr, stdout: stdout);
    for (final entry in failWith.entries) {
      if (command.contains(entry.key)) {
        return SSHRunResult(
          output: out,
          stdout: Uint8List(0),
          stderr: Uint8List.fromList(utf8.encode(entry.value)),
          exitCode: 1,
          exitSignal: null,
        );
      }
    }
    return SSHRunResult(output: out, stdout: out, stderr: Uint8List(0), exitCode: 0, exitSignal: null);
  }

  @override
  Future<Uint8List> run(
    String command, {
    Map<String, String>? environment,
    bool runInPty = false,
    bool stderr = true,
    bool stdout = true,
  }) async {
    commands.add(command);
    for (final t in throwOn) {
      if (command.contains(t)) {
        throw Exception('fake-fail:$t');
      }
    }
    _rememberHeredoc(command);
    _rememberEnabledSlot(command);
    var out = responder?.call(command) ?? '';
    // A slot the app has just switched on reports as up. Since 409 the watchdog deploy waits for
    // the interface before running the script, and a fake that never came up would make every
    // deploy test sit through the full poll.
    if (out.isEmpty && command == 'ip -o link show up') out = _enabledSlots.map((s) => 'wgc$s').join(' ');
    if (out.isEmpty && (command.contains('latest-handshakes') || command.contains('date +%s'))) {
      out = kFakeNow.toString();
    }
    if (out.isEmpty) out = _sizeOf(command) ?? '';
    return Uint8List.fromList(utf8.encode(out));
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  /// Slots switched on during this fake's lifetime, so `wg show interfaces` can answer honestly.
  final Set<int> _enabledSlots = {};
  static final _enableFlag = RegExp(r'nvram set wgc(\d)_enable=([01])');

  void _rememberEnabledSlot(String command) {
    for (final m in _enableFlag.allMatches(command)) {
      final slot = int.parse(m.group(1)!);
      m.group(2) == '1' ? _enabledSlots.add(slot) : _enabledSlots.remove(slot);
    }
  }

  /// Contents of the files written by heredoc, so `wc -c` can answer honestly - the deploy writes
  /// the script in chunks and then checks the size, and a fake that forgot would fail that check.
  final Map<String, StringBuffer> files = {};

  static final _heredoc = RegExp(r"^cat (>>?) '([^']+)' <<'WATCHDOG_EOF'\n");

  void _rememberHeredoc(String command) {
    final m = _heredoc.firstMatch(command);
    if (m == null) return;
    final body = command.substring(m.end, command.length - "WATCHDOG_EOF\n".length);
    final buf = files.putIfAbsent(m.group(2)!, StringBuffer.new);
    if (m.group(1) == '>') buf.clear();
    buf.write(body);
  }

  /// Answers `wc -c < 'path'` from what was written.
  String? _sizeOf(String command) {
    final m = RegExp(r"wc -c < '([^']+)'").firstMatch(command);
    if (m == null) return null;
    return (files[m.group(1)]?.length ?? 0).toString();
  }

  /// True if any recorded command contains [needle].
  bool ran(String needle) => commands.any((c) => c.contains(needle));

  /// Count of recorded commands containing [needle].
  int count(String needle) => commands.where((c) => c.contains(needle)).length;
}
