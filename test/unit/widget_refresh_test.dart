// test/unit/widget_refresh_test.dart - what a background refresh decides to do, and not do
// (ID-376). No router, no device, no plugins: every dependency of refreshWidgetStatus is injected.
import 'dart:io' show File;

import 'package:cfg_pia_wg/router_host_keys.dart' show RouterHostKeyChanged;
import 'package:cfg_pia_wg/router_prefs.dart';
import 'package:cfg_pia_wg/router_slot_service.dart' show buildVpncRecord, serialiseVpncClientlist;
import 'package:cfg_pia_wg/widget_bridge.dart' show WidgetAttemptFailure;
import 'package:cfg_pia_wg/widget_key.dart';
import 'package:cfg_pia_wg/widget_refresh.dart';
import 'package:cfg_pia_wg/widget_status.dart';
import 'package:cfg_pia_wg/widget_status_service.dart' show kWidgetStatusCommand;
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchdog_test_utils.dart';

/// In-memory [RouterPrefs] - the real one is file-backed, and a widget test's fake async never
/// completes real file I/O (see settings_screen_test.dart's own copy of this reasoning).
class _MemoryRouterPrefs extends RouterPrefs {
  _MemoryRouterPrefs(this.value);
  String value;

  @override
  Future<String> load() async => value;
  @override
  Future<String> remember(String ip) async => value = ip.trim();
  @override
  Future<void> forget() async => value = '';
}

/// A router that answers the status read with one tunnel up and nothing pinned.
RecordingSSHClient _answeringRouter() {
  final vpnc = serialiseVpncClientlist([buildVpncRecord(slot: 5, desc: 'Melbourne, Australia', active: true)]);
  return RecordingSSHClient(responder: (cmd) {
    if (cmd != kWidgetStatusCommand) return '';
    const m = '@@CFGPIAWG-WIDGET@@';
    return [
      '',
      vpnc,
      '', // no pins
      ' wgc5: ',
      'wgc5\tPEER\t1700000000\n---\n1700000000',
      '', '', '', '', '',
    ].join('\n$m\n');
  });
}

void main() {
  late Map<String, String> backing;
  late WidgetKeyStore store;

  setUp(() {
    backing = {};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(backing);
    store = WidgetKeyStore();
  });

  /// A key and login that are set up and usable, as they are after GENERATE succeeds.
  Future<void> setUpKey() async {
    await store.save(generateWidgetKeyPair().seed);
    await store.saveLogin('admin');
  }

  test('no key installed: nothing is tried, and nothing is written', () async {
    var connected = false, recorded = false;
    final outcome = await refreshWidgetStatus(
      store: store,
      prefs: _MemoryRouterPrefs('192.168.1.1'),
      connect: ({required ip, required user, required pem}) async {
        connected = true;
        throw StateError('should not be reached');
      },
      onFailed: (at, [why = WidgetAttemptFailure.unreachable]) async => recorded = true,
    );

    expect(outcome, WidgetRefreshOutcome.noKey);
    expect(connected, isFalse, reason: 'a widget with no key was never promised a refresh');
    expect(recorded, isFalse, reason: 'so its footer is not told one failed');
  });

  test('a key but no remembered router address: nothing is tried, and the footer says to open the app', () async {
    await setUpKey();
    var connected = false;
    WidgetAttemptFailure? said;
    final outcome = await refreshWidgetStatus(
      store: store,
      prefs: _MemoryRouterPrefs(''),
      connect: ({required ip, required user, required pem}) async {
        connected = true;
        throw StateError('should not be reached');
      },
      onFailed: (at, [why = WidgetAttemptFailure.unreachable]) async => said = why,
    );

    expect(outcome, WidgetRefreshOutcome.notSetUp);
    expect(connected, isFalse);
    // Silent until 2026-10-12: a tap on the refresh button changed nothing on screen, which looked
    // exactly like a button that does not work.
    expect(said, WidgetAttemptFailure.needsApp);
  });

  test('a key but no login beside it: not set up - neither is any use alone', () async {
    await store.save(generateWidgetKeyPair().seed); // no saveLogin
    final outcome = await refreshWidgetStatus(
      store: store,
      prefs: _MemoryRouterPrefs('192.168.1.1'),
      connect: ({required ip, required user, required pem}) async => throw StateError('unreachable'),
      onFailed: (at, [why = WidgetAttemptFailure.unreachable]) async {},
    );

    expect(outcome, WidgetRefreshOutcome.notSetUp);
  });

  test('no recorded host key: refuses to connect rather than trusting a router it has not seen', () async {
    await setUpKey();
    WidgetAttemptFailure? said;
    final outcome = await refreshWidgetStatus(
      store: store,
      prefs: _MemoryRouterPrefs('192.168.1.1'),
      // openWidgetSshClient throws StateError for this case; the seam reproduces it.
      connect: ({required ip, required user, required pem}) async => throw StateError('No SSH host key recorded'),
      onFailed: (at, [why = WidgetAttemptFailure.unreachable]) async => said = why,
    );

    expect(outcome, WidgetRefreshOutcome.noRecordedHostKey);
    expect(said, WidgetAttemptFailure.needsApp, reason: 'connecting once in the app is what records it');
  });

  test('a router presenting a different host key is sent to the app, not called unreachable', () async {
    await setUpKey();
    WidgetAttemptFailure? said;
    final outcome = await refreshWidgetStatus(
      store: store,
      prefs: _MemoryRouterPrefs('192.168.1.1'),
      connect: ({required ip, required user, required pem}) async => throw RouterHostKeyChanged('192.168.1.1:22', 'a', 'b'),
      onFailed: (at, [why = WidgetAttemptFailure.unreachable]) async => said = why,
    );

    expect(outcome, WidgetRefreshOutcome.unreachable);
    expect(said, WidgetAttemptFailure.needsApp);
  });

  test('a fault anywhere else is caught and shown as a failed refresh, not a dead worker', () async {
    FlutterSecureStoragePlatform.instance = _ThrowingSecureStorage();
    WidgetAttemptFailure? said;
    final outcome = await refreshWidgetStatus(
      store: WidgetKeyStore(),
      prefs: _MemoryRouterPrefs('192.168.1.1'),
      onFailed: (at, [why = WidgetAttemptFailure.unreachable]) async => said = why,
    );

    expect(outcome, WidgetRefreshOutcome.failed);
    expect(said, WidgetAttemptFailure.error);
  });

  test('a fault that also breaks the footer still returns, rather than throwing out of the worker', () async {
    FlutterSecureStoragePlatform.instance = _ThrowingSecureStorage();
    final outcome = await refreshWidgetStatus(
      store: WidgetKeyStore(),
      prefs: _MemoryRouterPrefs('192.168.1.1'),
      onFailed: (at, [why = WidgetAttemptFailure.unreachable]) async => throw StateError('no widget storage'),
    );

    expect(outcome, WidgetRefreshOutcome.failed);
  });

  test('off the home network: the last good reading is kept, and the failed attempt is recorded', () async {
    await setUpKey();
    var pushed = false;
    DateTime? failedAt;
    WidgetAttemptFailure? said;
    final outcome = await refreshWidgetStatus(
      store: store,
      prefs: _MemoryRouterPrefs('192.168.1.1'),
      connect: ({required ip, required user, required pem}) async => throw const SocketExceptionStub(),
      push: (status, {required now, canRefresh = false}) async => pushed = true,
      onFailed: (at, [why = WidgetAttemptFailure.unreachable]) async {
        failedAt = at;
        said = why;
      },
      clock: () => DateTime.utc(2026, 10, 12, 19, 45),
    );

    expect(outcome, WidgetRefreshOutcome.unreachable);
    expect(pushed, isFalse, reason: 'a failed read must not overwrite the last good one');
    // Silent means no notification, not no trace: without this, "tried and could not reach the
    // router" and "never tried at all" look identical on the phone (2026-10-12).
    expect(failedAt, DateTime.utc(2026, 10, 12, 19, 45));
    expect(said, WidgetAttemptFailure.unreachable);
  });

  test('a reachable router: the status is read and handed to the widget, marked refreshable', () async {
    await setUpKey();
    WidgetStatus? handed;
    bool? refreshable;
    final outcome = await refreshWidgetStatus(
      store: store,
      prefs: _MemoryRouterPrefs('192.168.1.1'),
      connect: ({required ip, required user, required pem}) async => _answeringRouter(),
      push: (status, {required now, canRefresh = false}) async {
        handed = status;
        refreshable = canRefresh;
      },
      clock: () => DateTime.utc(2026, 10, 12, 12),
    );

    expect(outcome, WidgetRefreshOutcome.done);
    expect(handed!.tunnels.single.region, 'Melbourne, Australia');
    expect(handed!.badge, WidgetBadge.protected);
    expect(refreshable, isTrue, reason: 'the key exists, so the widget may offer its own refresh');
    expect(handed!.checkedAt, DateTime.utc(2026, 10, 12, 12));
  });

  test('the login and address stored are the ones actually used to connect', () async {
    await store.save(generateWidgetKeyPair().seed);
    await store.saveLogin('root-admin');
    String? sawIp, sawUser, sawPem;
    await refreshWidgetStatus(
      store: store,
      prefs: _MemoryRouterPrefs('192.168.1.9:2222'),
      connect: ({required ip, required user, required pem}) async {
        sawIp = ip;
        sawUser = user;
        sawPem = pem;
        return _answeringRouter();
      },
      push: (status, {required now, canRefresh = false}) async {},
    );

    expect(sawIp, '192.168.1.9:2222');
    expect(sawUser, 'root-admin');
    expect(sawPem, startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'));
  });

  test('the key it signs with is the stored one, rebuilt from the seed', () async {
    final pair = generateWidgetKeyPair();
    await store.save(pair.seed);
    await store.saveLogin('admin');
    String? sawPem;
    await refreshWidgetStatus(
      store: store,
      prefs: _MemoryRouterPrefs('192.168.1.1'),
      connect: ({required ip, required user, required pem}) async {
        sawPem = pem;
        return _answeringRouter();
      },
      push: (status, {required now, canRefresh = false}) async {},
    );

    // The PEM handed to the connector must carry the same public key the router was told to trust.
    final parsed = SSHKeyPair.fromPem(sawPem!).single.toPublicKey().encode();
    final expected = SSHKeyPair.fromPem(openSshPrivateKeyPem(pair.seed, pair.publicKeyBytes)).single.toPublicKey().encode();
    expect(parsed, expected);
  });

  test('a router that connects but will not answer the read is unreachable, not a crash', () async {
    await setUpKey();
    var pushed = false, recorded = false;
    final outcome = await refreshWidgetStatus(
      store: store,
      prefs: _MemoryRouterPrefs('192.168.1.1'),
      connect: ({required ip, required user, required pem}) async => RecordingSSHClient(throwOn: const ['@@CFGPIAWG-WIDGET@@']),
      push: (status, {required now, canRefresh = false}) async => pushed = true,
      onFailed: (at, [why = WidgetAttemptFailure.unreachable]) async => recorded = true,
    );

    expect(outcome, WidgetRefreshOutcome.unreachable);
    expect(pushed, isFalse);
    expect(recorded, isTrue, reason: 'a router that answers the door but not the question still counts as a failed attempt');
  });

  test('the periodic job asks for no less than Android will give', () {
    expect(kWidgetRefreshInterval, const Duration(minutes: 15));
  });

  test('the tap task name is the one WidgetRefreshReceiver.kt sends', () {
    // Dart cannot import the Kotlin constant, so read it: a rename on one side only would leave
    // the button queueing work under a name nothing here knows about.
    final kotlin =
        File('android/app/src/main/kotlin/com/exponentiallydigital/pia_wireguard_cfga/widget/WidgetRefreshReceiver.kt').readAsStringSync();
    expect(kotlin, contains('const val TAP_TASK = "$kWidgetTapTask"'));
  });

  // ID-425: the widget is Android's, so iOS registers no background refresh for it.
  group('reregisterWidgetRefresh', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('registers on Android', () async {
      var calls = 0;
      await reregisterWidgetRefresh(initialize: () async => calls++);
      expect(calls, 1);
    });

    test('does nothing on iOS, where there is no widget', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var calls = 0;
      await reregisterWidgetRefresh(initialize: () async => calls++);
      expect(calls, 0);
      expect(homeWidgetSupported(), isFalse);
    });

    test("a plugin that fails doesn't stop the app starting", () async {
      await reregisterWidgetRefresh(initialize: () async => throw StateError('no plugin'));
    });
  });
}

/// A phone whose key store fails outright - the one dependency the refresh does not otherwise
/// guard.
class _ThrowingSecureStorage extends TestFlutterSecureStoragePlatform {
  _ThrowingSecureStorage() : super({});

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async => throw StateError('keystore unavailable');
}

/// Stands in for a connection failure without pulling in dart:io's own exception.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
