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

/// A fake [SSHClient] that records every command and returns canned output.
///
/// - [responder] maps a command string to its stdout (default: empty string).
/// - [throwOn] is a list of substrings; any command containing one throws,
///   used to exercise error-handling paths.
class RecordingSSHClient implements SSHClient {
  final List<String> commands = [];
  final String Function(String cmd)? responder;
  final List<String> throwOn;

  RecordingSSHClient({this.responder, this.throwOn = const []});

  @override
  Future<void> get authenticated => Future.value();

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
    return Uint8List.fromList(utf8.encode(responder?.call(command) ?? ''));
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  /// True if any recorded command contains [needle].
  bool ran(String needle) => commands.any((c) => c.contains(needle));

  /// Count of recorded commands containing [needle].
  int count(String needle) => commands.where((c) => c.contains(needle)).length;
}
