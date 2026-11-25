// test/unit/widget_refresh_scheduler_test.dart - the widget's background refresh schedule, against a stand-in for the
// platform's scheduler (ID-717).
//
// SonarCloud showed widget_refresh.dart at 58% line coverage, the scheduling calls and the SSH opener being the
// lines no test reached. Workmanager asks its platform implementation to do the work, and a test can put its own
// in the platform's place, once `Workmanager()` has chosen its default so that it does not choose again over it.
import 'dart:async';
import 'dart:io';

import 'package:cfg_pia_wg/router_host_keys.dart';
import 'package:cfg_pia_wg/widget_key.dart';
import 'package:cfg_pia_wg/widget_refresh.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';

class _Scheduler extends WorkmanagerPlatform {
  final List<String> calls = [];
  Function? dispatcher;
  String? uniqueName, taskName;
  Duration? frequency;
  Constraints? constraints;
  ExistingPeriodicWorkPolicy? policy;

  @override
  Future<void> initialize(Function callbackDispatcher, {bool isInDebugMode = false}) async {
    calls.add('initialize');
    dispatcher = callbackDispatcher;
  }

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    ForegroundServiceConfig? foregroundServiceConfig,
  }) async {
    calls.add('registerPeriodicTask');
    this.uniqueName = uniqueName;
    this.taskName = taskName;
    this.frequency = frequency;
    this.constraints = constraints;
    policy = existingWorkPolicy;
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    calls.add('cancelByUniqueName');
    this.uniqueName = uniqueName;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Scheduler scheduler;

  setUp(() {
    Workmanager(); // chooses its platform now, so the stand-in below is not replaced on first use
    scheduler = _Scheduler();
    WorkmanagerPlatform.instance = scheduler;
  });

  test('scheduleWidgetRefresh sets the dispatcher up, then registers one periodic task that replaces any before it', () async {
    await scheduleWidgetRefresh();
    expect(scheduler.calls, ['initialize', 'registerPeriodicTask']);
    expect(scheduler.dispatcher, same(callbackDispatcher), reason: 'the top-level function the platform starts a task in');
    expect(scheduler.uniqueName, widgetRefreshTaskName());
    expect(scheduler.taskName, widgetRefreshTaskName());
    expect(scheduler.frequency, kWidgetRefreshInterval);
    expect(scheduler.policy, ExistingPeriodicWorkPolicy.replace, reason: 'a changed interval takes effect, not a second job');
    expect(scheduler.constraints?.networkType, NetworkType.connected, reason: 'no wake-up for a refresh that cannot reach the router');
  });

  test('on iOS the task has the name Apple registered', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await scheduleWidgetRefresh();
    expect(scheduler.taskName, kIosWidgetRefreshTask);
  });

  test('cancelWidgetRefresh cancels that task by its name, after setting the dispatcher up', () async {
    await cancelWidgetRefresh();
    expect(scheduler.calls, ['initialize', 'cancelByUniqueName']);
    expect(scheduler.uniqueName, widgetRefreshTaskName());
  });

  test('the dispatcher hands the platform a task handler without running one', () {
    // What a background isolate does first; the handler itself runs only when the platform starts a task.
    callbackDispatcher();
  });

  test('opening a widget connection with no host key recorded refuses, and says to connect in the app once', () async {
    await expectLater(
      openWidgetSshClient(ip: '192.168.1.1', user: 'admin', pem: 'not used'),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('connect in the app once first'))),
    );
  });

  test('a router with a port gets its host and port in the message', () async {
    await expectLater(
      openWidgetSshClient(ip: '192.168.1.1:2222', user: 'admin', pem: 'not used'),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('192.168.1.1:2222'))),
    );
  });

  // The host key a widget refresh will trust, with nobody there to ask.
  group('WidgetHostKeyCheck', () {
    final recorded = 'SHA256:${'A' * 43}';
    final other = 'SHA256:${'B' * 43}';

    test('the recorded key is accepted, and nothing is reported', () {
      final check = WidgetHostKeyCheck('192.168.1.1:22', recorded);
      expect(check.verify(recorded.codeUnits), isTrue);
      expect(check.refused, isFalse);
      expect(check.presented, recorded);
      expect(check.changedKey(), isNull);
    });

    test('a different key is refused, and a failed connection then says the key changed, naming both', () {
      final check = WidgetHostKeyCheck('192.168.1.1:22', recorded);
      expect(check.verify(other.codeUnits), isFalse);
      expect(check.refused, isTrue);
      final changed = check.changedKey()!;
      expect(changed.target, '192.168.1.1:22');
      expect(changed.recorded, recorded);
      expect(changed.presented, other);
    });

    test('before any key is presented there is nothing to report', () {
      expect(WidgetHostKeyCheck('192.168.1.1:22', recorded).changedKey(), isNull);
    });
  });

  group('runBackgroundTask', () {
    test('runs the refresh and always says it succeeded, even when the router could not be reached', () async {
      for (final outcome in WidgetRefreshOutcome.values) {
        var ran = 0;
        final ok = await runBackgroundTask(kWidgetTapTask, refresh: () async {
          ran++;
          return outcome;
        });
        expect(ran, 1, reason: '$outcome');
        expect(ok, isTrue, reason: 'a retry sooner would not fix $outcome, so WorkManager is not asked to back off');
      }
    });
  });

  group('opening a connection to a router that answers and hangs up', () {
    test('a failed connection that was not a refused key is the connection error, not a key change', () async {
      final dir = Directory.systemTemp.createTempSync('widget_ssh_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((socket) => socket.destroy());
      final keys = RouterHostKeys(directory: () async => dir);
      expect(await keys.record('127.0.0.1:${server.port}', 'SHA256:${'A' * 43}'), isTrue);
      final pair = generateWidgetKeyPair();

      // The SSH library also reports the dropped connection on a stream of its own, outside the call; those
      // errors are collected here and are not what is being asked.
      final stray = <Object>[];
      await runZonedGuarded(() async {
        await expectLater(
          openWidgetSshClient(
            ip: '127.0.0.1:${server.port}',
            user: 'admin',
            pem: openSshPrivateKeyPem(pair.seed, pair.publicKeyBytes),
            hostKeys: keys,
          ),
          throwsA(isNot(isA<RouterHostKeyChanged>())),
        );
      }, (error, _) => stray.add(error));
      expect(stray.whereType<RouterHostKeyChanged>(), isEmpty);
    });

    test('an address nothing listens on fails to connect, and is not a key change either', () async {
      final dir = Directory.systemTemp.createTempSync('widget_ssh_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      final keys = RouterHostKeys(directory: () async => dir);
      await keys.record('127.0.0.1:$port', 'SHA256:${'A' * 43}');
      final pair = generateWidgetKeyPair();

      await expectLater(
        openWidgetSshClient(
          ip: '127.0.0.1:$port',
          user: 'admin',
          pem: openSshPrivateKeyPem(pair.seed, pair.publicKeyBytes),
          hostKeys: keys,
          connectTimeout: const Duration(seconds: 2),
        ),
        throwsA(isNot(isA<RouterHostKeyChanged>())),
      );
    });
  });
}
