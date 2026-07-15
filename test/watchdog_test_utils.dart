// test/watchdog_test_utils.dart - shared SSH fake for watchdog tests.
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';

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
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  /// True if any recorded command contains [needle].
  bool ran(String needle) => commands.any((c) => c.contains(needle));

  /// Count of recorded commands containing [needle].
  int count(String needle) => commands.where((c) => c.contains(needle)).length;
}
