// test/router_push_sheet_test.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartssh2/dartssh2.dart';

import 'package:pia_wireguard_cfga/router_push.dart';

// --- FAKE SSH CLIENT ---
class FakeSSHClient implements SSHClient {
  final Future<String> Function(String command) onRun;

  FakeSSHClient({required this.onRun});

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
    final result = await onRun(command);
    return Uint8List.fromList(utf8.encode(result));
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const String sampleWgConfig = '''
[Interface]
PrivateKey = xxxxx=
Address = 10.0.0.2/32
DNS = 1.1.1.1
MTU = 1420

[Peer]
PublicKey = yyyyy=
Endpoint = 192.168.1.50:51820
AllowedIPs = 0.0.0.0/0
''';

  Widget buildTestableWidget({
    required Function(String, {bool isError, bool isSuccess}) onLog,
    Future<SSHClient> Function(String ip, String user, String pass)? testClientFactory,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: RouterPushSheet(
          config: sampleWgConfig,
          regionId: 'US-East',
          onLog: onLog,
          testClientFactory: testClientFactory,
        ),
      ),
    );
  }

  // Helper method to enter credentials and proceed past Step 0
  Future<void> loginAndProceedToSlots(WidgetTester tester) async {
    final Finder textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), '192.168.1.1');
    await tester.enterText(textFields.at(1), 'admin');
    await tester.enterText(textFields.at(2), 'password123');
    await tester.pumpAndSettle();

    await tester.tap(find.text('CONNECT'));
    await tester.pumpAndSettle();
  }

  group('RouterPushSheet - 100% Coverage Suite', () {
    testWidgets('Step 0: fetchSlots retrieves configs and handles empty slots warning', (tester) async {
      String? lastLog;
      await tester.pumpWidget(buildTestableWidget(
        onLog: (msg, {isError = false, isSuccess = false}) => lastLog = msg,
        testClientFactory: (ip, user, pass) async => FakeSSHClient(onRun: (cmd) async {
          return '';
        }),
      ));

      await loginAndProceedToSlots(tester);

      expect(lastLog, contains('Successfully retrieved router config.'));
      expect(find.text('WRITE TO WIREGUARD SLOT'), findsOneWidget);
    });

    testWidgets('Step 1: pushToRouter (Happy Path with Handshake & Active Tunnel Stop)', (tester) async {
      List<String> logs = [];
      await tester.pumpWidget(buildTestableWidget(
        onLog: (msg, {isError = false, isSuccess = false}) => logs.add(msg),
        testClientFactory: (ip, user, pass) async => FakeSSHClient(onRun: (cmd) async {
          if (cmd.contains('nvram get wgc1_desc')) {
            return 'Old-Config'; // Pre-populate to trigger backup path safely
          }
          if (cmd.contains('wg show interfaces')) {
            return 'wgc1';
          }
          if (cmd.contains('nvram get wgc1_rip')) {
            return '203.0.113.1';
          }
          if (cmd.contains('nvram get wgc1_addr')) {
            return '10.0.0.2/32';
          }
          return 'mock_value';
        }),
      ));

      await loginAndProceedToSlots(tester);

      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('CONFIRM WRITE TO ROUTER'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(logs.any((l) => l.contains('Backing up existing wgc1 config')), isTrue);
      expect(logs.any((l) => l.contains('Connected via US-East')), isTrue);
      expect(logs.any((l) => l.contains('Push complete.')), isTrue);
    });

    testWidgets('Step 1: pushToRouter verify loop throws Timeout Exception', (tester) async {
      bool errorThrown = false;
      await tester.pumpWidget(buildTestableWidget(
        onLog: (msg, {isError = false, isSuccess = false}) {
          if (isError && msg.contains('Check tunnel status via SSH')) {
            errorThrown = true;
          }
        },
        testClientFactory: (ip, user, pass) async => FakeSSHClient(onRun: (cmd) async {
          if (cmd.contains('wg show interfaces')) {
            return '';
          }
          return '';
        }),
      ));

      await loginAndProceedToSlots(tester);

      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('CONFIRM WRITE TO ROUTER'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(errorThrown, isTrue);
    });

    testWidgets('Step 1: pushToRouter triggers Error Recovery and restores backups successfully', (tester) async {
      bool restoredSlot = false;
      bool simulateFailure = false; // 1. Initialize our one-time trigger flag

      await tester.pumpWidget(buildTestableWidget(
        onLog: (msg, {isError = false, isSuccess = false}) {
          if (msg.contains('wgc1 config restored')) {
            restoredSlot = true;
          }
        },
        testClientFactory: (ip, user, pass) async => FakeSSHClient(onRun: (cmd) async {
          if (cmd.contains('nvram get wgc1_desc')) {
            return 'Old-Config'; // Crucial: Ensures _slots[1] is populated during step 0
          }
          if (cmd.contains('wg show interfaces')) {
            return 'wgc2';
          }
          if (cmd.contains('nvram get wgc1_')) {
            return 'backup_val';
          }

          // 2. Intercept the VERY FIRST command of the write phase and crash it.
          // By turning the flag off immediately, subsequent recovery commands will succeed.
          if (simulateFailure) {
            simulateFailure = false;
            throw Exception('Simulated crash during write sequence');
          }

          return '';
        }),
      ));

      await loginAndProceedToSlots(tester);
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      // 3. Arm the trigger right before the write action begins
      simulateFailure = true;

      await tester.tap(find.text('CONFIRM WRITE TO ROUTER'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(restoredSlot, isTrue);
    });

    testWidgets('Step 1: pushToRouter Error Recovery experiences a CRITICAL Failure', (tester) async {
      bool criticalLogged = false;

      await tester.pumpWidget(buildTestableWidget(
        onLog: (msg, {isError = false, isSuccess = false}) {
          if (msg.contains('CRITICAL: Could not restore')) {
            criticalLogged = true;
          }
        },
        testClientFactory: (ip, user, pass) async => FakeSSHClient(onRun: (cmd) async {
          // 1. Allow the backup process to succeed so slotBackup is populated
          if (cmd.contains('nvram get wgc1_desc')) {
            return 'Old-Config';
          }
          if (cmd.contains('nvram get wgc1_')) {
            return 'backup_val';
          }

          // 2. Force an exception on write/restart commands.
          // This ensures the initial push fails (triggering the recovery block)
          // AND the recovery push fails (triggering the CRITICAL catch block).
          if (cmd.contains('nvram set') || cmd.contains('service "restart_wgc')) {
            throw Exception('Simulated SSH write/execution failure');
          }

          return 'wgc1';
        }),
      ));

      await loginAndProceedToSlots(tester);
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONFIRM WRITE TO ROUTER'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(criticalLogged, isTrue);
    });
  });
}
