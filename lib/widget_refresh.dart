// widget_refresh.dart - the widget refreshing itself, without the app being open (ID-376).
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
// [refreshWidgetStatus] is the whole job and is testable with fakes: load the key and login, use
// them, read the status, hand it to the widget. The plugin glue below it - the WorkManager entry
// point, the schedule, the widget's own refresh button - is thin on purpose, for the same reason
// pushWidgetStatus is: there is nothing to assert about it without a real device.
//
// Two rules this file keeps that the app's own screens do not have to:
//
//   1. **A recorded host key is required, not optional.** openSshClient (router_slot_service.dart)
//      records an unknown key on first use and tells the user it did so - a human is there to read
//      that. Nothing is watching a 3 a.m. refresh, so this refuses to connect at all until a key
//      has been recorded by an ordinary connection in the app. A background job must not be the
//      thing that decides to trust a router it has never seen.
//   2. **Failure is silent and harmless, but never invisible.** Off the home network - the
//      router's SSH only ever answered on the LAN - the connection simply fails and nothing is
//      retried in a hurry. Nobody is notified, but every attempt that leaves the tunnel rows as
//      they were says so in the widget's footer, and why (pushWidgetAttemptFailed). The one
//      exception is no key at all: that widget was never promised a refresh.

import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'router_host_keys.dart';
import 'router_prefs.dart';
import 'router_slot_service.dart' show splitHostPort;
import 'widget_bridge.dart';
import 'widget_key.dart';
import 'widget_status.dart';
import 'widget_status_service.dart';

/// What one refresh did, so the caller - and the tests - can tell "nothing to do" from "could not
/// reach it". None of these raises a notification; all but [noKey] and [done] leave a footer
/// saying the refresh did not happen - see rule 2 in this file's header.
enum WidgetRefreshOutcome {
  /// No key is installed, so the widget was never promised a refresh. Nothing was tried.
  noKey,

  /// A key, but no remembered router address or login to use it with.
  notSetUp,

  /// The router has no recorded SSH host key yet, so this refused to connect - rule 1 above.
  noRecordedHostKey,

  /// Tried, and could not reach the router: off the home network, asleep, or refusing the key.
  unreachable,

  /// Read, and handed to the widget.
  done,

  /// Something else threw - the phone's key store, say. Caught, so a fault here is a footer on
  /// the widget rather than a worker that died with nothing to show for it.
  failed,
}

/// How a refresh opens its connection. A seam, so [refreshWidgetStatus] can be tested without a
/// router; the default is [openWidgetSshClient].
typedef WidgetSshConnector = Future<SSHClient> Function({required String ip, required String user, required String pem});

/// Connects as [user] with [pem] (the widget's key, from [openSshPrivateKeyPem]) - key only, no
/// password, and no accepting an unrecorded host key. Throws [StateError] when none is recorded,
/// and [RouterHostKeyChanged] when the router presents a different one than the app recorded.
Future<SSHClient> openWidgetSshClient({required String ip, required String user, required String pem}) async {
  final target = splitHostPort(ip);
  final id = '${target.host}:${target.port}';
  final recorded = await routerHostKeys.recorded(id);
  if (recorded == null) {
    throw StateError('No SSH host key recorded for $id; connect in the app once first.');
  }
  String? presented;
  var refused = false;
  final socket = await SSHSocket.connect(target.host, target.port, timeout: const Duration(seconds: 5));
  final client = SSHClient(
    socket,
    username: user,
    identities: SSHKeyPair.fromPem(pem),
    onVerifyHostKey: (type, fingerprint) {
      presented = String.fromCharCodes(fingerprint);
      refused = recorded != presented;
      return !refused;
    },
  );
  try {
    await client.authenticated;
  } catch (_) {
    if (refused) throw RouterHostKeyChanged(id, recorded, presented ?? '');
    rethrow;
  }
  return client;
}

/// One refresh, start to finish. Every dependency is injectable so the decisions here - when to
/// try, when not to bother, what the widget is told - are tested in
/// test/unit/widget_refresh_test.dart without a router or a device.
Future<WidgetRefreshOutcome> refreshWidgetStatus({
  WidgetKeyStore? store,
  RouterPrefs? prefs,
  WidgetSshConnector connect = openWidgetSshClient,
  Future<void> Function(WidgetStatus status, {required DateTime now, bool canRefresh})? push,
  Future<void> Function(DateTime attemptedAt, [WidgetAttemptFailure why])? onFailed,
  DateTime Function() clock = DateTime.now,
}) async {
  final failed = onFailed ?? pushWidgetAttemptFailed;
  try {
    return await _refresh(store, prefs, connect, push, failed, clock);
  } catch (_) {
    try {
      await failed(clock(), WidgetAttemptFailure.error);
    } catch (_) {
      // The widget's own storage failed too; there is nowhere left to say so.
    }
    return WidgetRefreshOutcome.failed;
  }
}

Future<WidgetRefreshOutcome> _refresh(
  WidgetKeyStore? store,
  RouterPrefs? prefs,
  WidgetSshConnector connect,
  Future<void> Function(WidgetStatus status, {required DateTime now, bool canRefresh})? push,
  Future<void> Function(DateTime attemptedAt, [WidgetAttemptFailure why]) failed,
  DateTime Function() clock,
) async {
  final keys = store ?? WidgetKeyStore();
  final seed = await keys.read();
  if (seed == null) return WidgetRefreshOutcome.noKey;

  final user = await keys.readLogin();
  final ip = (await (prefs ?? RouterPrefs()).load()).trim();
  if (user == null || user.isEmpty || ip.isEmpty) {
    await failed(clock(), WidgetAttemptFailure.needsApp);
    return WidgetRefreshOutcome.notSetUp;
  }

  final pair = widgetKeyPairFromSeed(seed);
  final pem = openSshPrivateKeyPem(pair.seed, pair.publicKeyBytes, comment: kWidgetKeyComment);

  SSHClient client;
  try {
    client = await connect(ip: ip, user: user, pem: pem);
  } on StateError {
    await failed(clock(), WidgetAttemptFailure.needsApp);
    return WidgetRefreshOutcome.noRecordedHostKey;
  } on RouterHostKeyChanged {
    // Not "could not reach": something answered with a different key. The app is where that is
    // explained and decided, so the footer sends the reader there.
    await failed(clock(), WidgetAttemptFailure.needsApp);
    return WidgetRefreshOutcome.unreachable;
  } catch (_) {
    // Off the home network, router asleep, key refused - all the same to the widget, which goes on
    // showing its last good reading, now marked with the attempt that failed. Nothing is raised to
    // the user: silent means no notification, not no trace (see pushWidgetAttemptFailed).
    await failed(clock());
    return WidgetRefreshOutcome.unreachable;
  }

  try {
    final status = await WidgetStatusService(client, clock: clock).read();
    await (push ?? pushWidgetStatus)(status, now: clock(), canRefresh: true);
    return WidgetRefreshOutcome.done;
  } catch (_) {
    await failed(clock());
    return WidgetRefreshOutcome.unreachable;
  } finally {
    client.close();
  }
}

/// The name WorkManager knows the periodic refresh by, and the tag it is cancelled with.
const String kWidgetRefreshTask = 'cfg-pia-wg-widget-refresh';

/// Android's own floor for a periodic job. Asking for less does not get less.
const Duration kWidgetRefreshInterval = Duration(minutes: 15);

/// The task name a tap on the widget's refresh button arrives as - WidgetRefreshReceiver.kt's
/// TAP_TASK. [callbackDispatcher] treats it exactly like [kWidgetRefreshTask].
const String kWidgetTapTask = 'cfg-pia-wg-widget-tap';

/// WorkManager's entry point, for both the fifteen-minute refresh and a tap on the widget's
/// refresh button ([kWidgetTapTask]). A top-level function with `vm:entry-point` because it is
/// called in a fresh background isolate, which has none of the app's state and has to register
/// the plugins it uses for itself.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    DartPluginRegistrant.ensureInitialized();
    await refreshWidgetStatus();
    // Always true: a refresh that could not reach the router has not failed in a way retrying
    // sooner would fix, and WorkManager's backoff is not the right answer to being out of the
    // house. The next scheduled run is soon enough.
    return true;
  });
}

/// Starts the periodic refresh, replacing any existing one. Called when a key is installed. The
/// refresh button needs nothing here: it is live whenever the widget was last told a key exists.
///
/// It also reads the router once, straight away. WorkManager runs a periodic task at the END of
/// its first interval, not at registration, and Android may defer it further - so without this the
/// widget sits on whatever it last knew for fifteen minutes or more after the key goes in, which
/// looks exactly like a feature that does not work (reported on a real phone, 2026-10-12).
Future<void> scheduleWidgetRefresh() async {
  await Workmanager().initialize(callbackDispatcher);
  unawaited(refreshWidgetStatus());
  await Workmanager().registerPeriodicTask(
    kWidgetRefreshTask,
    kWidgetRefreshTask,
    frequency: kWidgetRefreshInterval,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

/// Stops the periodic refresh. Called when the key is removed - a job that can no longer log in
/// has nothing to do but wake the phone up.
Future<void> cancelWidgetRefresh() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().cancelByUniqueName(kWidgetRefreshTask);
}

/// True where the app has a home screen widget: Android. Read through [defaultTargetPlatform], so a
/// test can run as iOS (ID-425).
bool homeWidgetSupported() => defaultTargetPlatform == TargetPlatform.android;

/// Points WorkManager - and so the widget's refresh button, which runs through it - at THIS
/// build's entry point, and does nothing else: no schedule is started here. Called from `main()`
/// on every start, because the handle the plugin stores is specific to the build that registered
/// it: after an app update the stored handle is stale, and a background refresh fails with
/// nothing to show for it.
///
/// Safe with no key installed: registering an entry point does not schedule anything, and
/// [refreshWidgetStatus] returns [WidgetRefreshOutcome.noKey] if something does call it.
/// Deliberately swallows its errors - a platform without the plugin (a test, a desktop build)
/// must not stop the app from starting over a widget it does not have.
///
/// Android only: the widget is Android's, and iOS has none yet (ID-425, until ID-438). [initialize]
/// stands in for the plugin in a test.
Future<void> reregisterWidgetRefresh({Future<void> Function()? initialize}) async {
  if (!homeWidgetSupported()) return;
  try {
    await (initialize ?? () => Workmanager().initialize(callbackDispatcher))();
  } catch (_) {
    // Nothing to report and nobody to report it to: the widget simply will not refresh itself.
  }
}
