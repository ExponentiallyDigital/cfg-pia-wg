// screens/settings_screen.dart - the things that undo what the app has done.
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
// Nearly everything here removes something. FORGET ROUTER IP and REMOVE CACHED PIA CERT used to sit on ABOUT, among
// the build metadata and the licence text, which is a page people open to read rather than to act
// on - and the uninstall belongs beside them rather than anywhere a stray tap could reach it.
//
// On the main menu as well as in the drawer since 2026-09-13. It used to be drawer-only, on the grounds
// that an uninstall is not something to offer on the way in; the decision now is that nothing should
// need the hamburger to be found.

import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../widgets/app_button.dart';

import '../app_colors.dart';
import '../device_assignment_service.dart';
import '../entitlement.dart';
import '../firmware.dart';
import '../router_slot_service.dart' show RouterSlotService, kDefaultStockMaxActiveSlots, openSshClient, splitHostPort;
import '../review_service.dart';
import '../router_watchdog.dart';
import '../router_session.dart' show routerConnectMessage;
import '../server_list_signature.dart';
import '../session_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/paywall.dart';
import '../widgets/error_presenter.dart';
import '../widgets/ssh_creds_dialog.dart';
import '../widget_key.dart';
import '../widget_key_service.dart';
import '../widget_refresh.dart' show cancelWidgetRefresh, scheduleWidgetRefresh;
import '../widget_status_service.dart' show kWidgetStatusCommand;
import 'router_dns_screen.dart';

class SettingsScreen extends StatefulWidget {
  /// Injected by tests so the router actions can run without a router.
  final Future<SSHClient> Function(String ip, String user, String pass)? testClientFactory;

  /// Injected by tests in place of the store's restore; it also shows RESTORE PURCHASE in a build with no store key.
  final Future<bool> Function()? testRestore;

  /// Injected by tests in place of the check that the router answers again after a reboot.
  final Future<bool> Function(String host, int port)? testRouterAnswers;

  /// Injected by tests in place of the real Keystore-backed store (ID-376), so WIDGET KEY can be
  /// exercised without a device's secure storage.
  final WidgetKeyStore? testWidgetKeyStore;

  /// Injected by tests in place of WorkManager's own scheduling (ID-376), which needs a device.
  final Future<void> Function()? testScheduleRefresh, testCancelRefresh;

  /// Injected by tests in place of the phone's copy of the last PIA server list that passed (ID-325).
  final ServerListStore? testServerListStore;
  const SettingsScreen({
    super.key,
    this.testClientFactory,
    this.testRestore,
    this.testRouterAnswers,
    this.testWidgetKeyStore,
    this.testScheduleRefresh,
    this.testCancelRefresh,
    this.testServerListStore,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SessionController _c;
  bool _busy = false;
  late final WidgetKeyStore _widgetKeyStore = widget.testWidgetKeyStore ?? WidgetKeyStore();
  late final ServerListStore _serverListStore = widget.testServerListStore ?? ServerListStore();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c = SessionScope.of(context);
  }

  /// Resolves router credentials, asking for them when the session has none.
  ///
  /// Returns null when the user dismisses the prompt, which every caller treats as "do nothing" -
  /// dismissing a login is a decision, not a failure to report.
  Future<(String, String, String)?> _credentials() async {
    final ip = _c.routerIp.trim(), user = _c.sshUsername.trim(), pass = _c.sshPassword;
    if (_c.canReuseRouterSession) return (ip, user, pass);
    final entered = await showDialog<(String, String, String)?>(
      context: context,
      builder: (_) => SshCredsDialog(
        initialIp: _c.routerIpPrefill,
        initialUser: user,
        initialPass: pass,
        verify: (ip, user, pass) => verifyRouterLogin(_c, ip, user, pass, testClientFactory: widget.testClientFactory),
      ),
    );
    if (entered == null || !mounted) return null;
    _c
      ..routerIp = entered.$1
      ..sshUsername = entered.$2
      ..sshPassword = entered.$3;
    return entered;
  }

  /// Records a router action that reached the router. The session then counts as connected, so the next
  /// action on this screen or any other reuses the credentials rather than asking again (ID-046), and the
  /// address is remembered.
  Future<void> _connected(String ip) async {
    _c.routerConnected = true;
    await _c.rememberRouterIp(ip);
  }

  Future<void> _uninstall() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kSurface,
            title: const Text('Remove cfg-pia-wg from the router?', style: TextStyle(color: kHighlight, fontSize: 14)),
            content: const SingleChildScrollView(
              child: Text(
                'This will remove your watchdog reconfigure history, every setting the app '
                'wrote to your router, and any watchdog schedules. It puts back the two boot '
                'scripts the app replaced, and deletes $kRouterAppDir along with everything '
                'in it - the watchdog scripts, the cached PIA certificate and server list, and the '
                'helper binaries.\n\n'
                'Your VPN tunnels are NOT touched. They keep working, and you can manage them '
                "from your router's own web interface.\n\n"
                'Devices pinned to a tunnel keep their pin but lose the fail-closed guard: '
                'whenever their tunnel is down, they reach the internet through the default '
                'connection, which may be your internet connection with no VPN.\n\n'
                'The app itself keeps working. Deploying a watchdog again puts everything back.',
                style: TextStyle(color: kText, fontSize: 12),
              ),
            ),
            actions: [
              AppButton(
                keyValue: 'settings_uninstall_cancel',
                label: 'CANCEL',
                role: ButtonRole.dismiss,
                onPressed: () => Navigator.pop(ctx, false),
              ),
              AppButton(
                keyValue: 'settings_uninstall_confirm',
                label: 'REMOVE',
                role: ButtonRole.destructive,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    if (!await _reallySure() || !mounted) return;

    final creds = await _credentials();
    if (creds == null || !mounted) return;
    final (ip, user, pass) = creds;

    setState(() => _busy = true);
    List<String>? done;
    String? error, errorDetail;
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      done = await RouterWatchdog(client, onLog: _c.onLog).uninstallFromRouter();
      await _connected(ip);
    } catch (e) {
      // Plain English on screen, the raw exception in the log (ID-108).
      final plain = routerConnectMessage(e, ip);
      errorDetail = plain == null ? null : e.toString();
      error = plain ?? e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (error != null) {
      await AppErrors.system(context, _c, errorDetail == null ? 'Could not remove the app from the router: $error' : error,
          logDetail: errorDetail);
      return;
    }
    // What happened, itemised. "Restored yours" and "removed ours" are different outcomes and the
    // user is entitled to know which of the two they got for each script.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Removed from the router', style: TextStyle(color: kHighlight, fontSize: 14)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // What was done in the body colour, what was not done - nothing there, or not the app's -
          // in red, so a second uninstall reads as the no-op it is (ID-287, Andrew's request).
          for (final line in done!)
            Text(line, style: TextStyle(color: uninstallStepDidNothing(line) ? kError : kText, fontSize: 12)),
          // Amber, and set apart. The cron entries are gone but a running watchdog process is
          // not, and the firmware keeps its own idea of what is configured until it restarts.
          // Only when something was removed: a run that changed nothing has nothing to restart for.
          if (!done.every(uninstallStepDidNothing)) ...[
            const SizedBox(height: 16),
            const Text('Please restart your router.', style: TextStyle(color: kWarn, fontSize: 12)),
          ],
        ]),
        actions: [
          AppButton(keyValue: 'settings_uninstall_done', label: 'OK', onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }

  /// The second ask, and the last thing between a tap and an uninstall.
  ///
  /// The first confirmation explains what happens; this one is the "are you sure". It also asks for
  /// a review, which is the one moment in the app where asking is fair - the user is leaving, and
  /// why they are leaving is the most useful thing they could tell us.
  Future<bool> _reallySure() async {
    final recogniser = TapGestureRecognizer()..onTap = _openReview;
    try {
      return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: kSurface,
              content: Text.rich(
                TextSpan(style: const TextStyle(color: kText, fontSize: 13), children: [
                  const TextSpan(text: 'Are you sure?\n\n'),
                  const TextSpan(text: 'Please consider '),
                  TextSpan(
                    text: 'leaving us a review',
                    style: const TextStyle(
                      color: kHighlight,
                      decoration: TextDecoration.underline,
                      decorationColor: kHighlight,
                    ),
                    recognizer: recogniser,
                  ),
                  const TextSpan(text: " on the Google Play store with why you're uninstalling."),
                ]),
              ),
              // House style, in the order every other confirmation uses: the way out first, then the
              // action. Both were teal-bordered here, the destructive UNINSTALL included.
              actions: [
                AppButton(
                  keyValue: 'settings_uninstall_really_cancel',
                  label: 'CANCEL',
                  role: ButtonRole.dismiss,
                  onPressed: () => Navigator.pop(ctx, false),
                ),
                AppButton(
                  keyValue: 'settings_uninstall_really',
                  label: 'UNINSTALL',
                  role: ButtonRole.destructive,
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      recogniser.dispose();
    }
  }

  /// The same destination the home screen's review link uses.
  Future<void> _openReview() async {
    if (!await openPlayStoreReview() && mounted) {
      _c.logEntry('Could not open the Play Store listing on this device.', isError: true);
    }
  }

  Future<void> _deletePiaCert() async {
    final creds = await _credentials();
    if (creds == null || !mounted) return;
    final (ip, user, pass) = creds;

    // Confirms even though the cache is regenerated on the next watchdog run: the button is one
    // tap from a screen full of other destructive buttons, and a stray tap should cost a dialog
    // rather than a round trip to PIA.
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kSurface,
            title: const Text('Delete cached PIA certificate?', style: TextStyle(color: kHighlight, fontSize: 14)),
            content: const Text(
              'Removes $kPiaCaCertPath from the router. The watchdog downloads a fresh copy on its '
              'next run. Nothing else is changed.',
              style: TextStyle(color: kText, fontSize: 12),
            ),
            actions: [
              AppButton(
                keyValue: 'settings_del_cert_cancel',
                label: 'CANCEL',
                role: ButtonRole.dismiss,
                onPressed: () => Navigator.pop(ctx, false),
              ),
              AppButton(
                keyValue: 'settings_del_cert_confirm',
                label: 'DELETE',
                role: ButtonRole.destructive,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    var deleted = false;
    String? error, errorDetail;
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      deleted = await RouterWatchdog(client, onLog: _c.onLog).deleteCachedPiaCert();
      await _connected(ip);
    } catch (e) {
      // Plain English on screen, the raw exception in the log (ID-108).
      final plain = routerConnectMessage(e, ip);
      errorDetail = plain == null ? null : e.toString();
      error = plain ?? e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (error != null) {
      await AppErrors.system(context, _c, errorDetail == null ? 'Could not delete the cached certificate: $error' : error,
          logDetail: errorDetail);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(deleted ? 'Cached PIA certificate deleted.' : 'No cached PIA certificate on the router.'),
    ));
  }

  /// REMOVE CACHED PIA SERVERS (ID-325): the last server list that passed PIA's signature check, on
  /// the router and on this phone. Modelled on REMOVE CACHED PIA CERT. Each copy is what a list that
  /// fails falls back on, so with them gone a list that fails is refused until one passes again.
  Future<void> _deleteServerLists() async {
    final creds = await _credentials();
    if (creds == null || !mounted) return;
    final (ip, user, pass) = creds;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kSurface,
            title: const Text('Delete the cached PIA server lists?', style: TextStyle(color: kHighlight, fontSize: 14)),
            content: const SingleChildScrollView(
              child: Text(
                "Removes $kPiaServerListPath from the router, and this phone's copy. Each is the last PIA server "
                "list that passed PIA's signature check, kept so a list that fails can be refused without "
                'stopping a rebuild or CREATE.\n\n'
                'The next list that passes is kept again. Until then, a list that fails is refused outright. '
                'Nothing else is changed.',
                style: TextStyle(color: kText, fontSize: 12),
              ),
            ),
            actions: [
              AppButton(
                keyValue: 'settings_del_servers_cancel',
                label: 'CANCEL',
                role: ButtonRole.dismiss,
                onPressed: () => Navigator.pop(ctx, false),
              ),
              AppButton(
                keyValue: 'settings_del_servers_confirm',
                label: 'DELETE',
                role: ButtonRole.destructive,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    // The phone's copy first: it needs no router, so a router that can't be reached doesn't keep it.
    bool? onPhone;
    String? phoneError;
    try {
      onPhone = await _serverListStore.remove();
      _c.logEntry(onPhone ? "Deleted this phone's cached PIA server list." : 'No cached PIA server list on this phone.',
          isSuccess: onPhone);
    } catch (e) {
      phoneError = e.toString();
    }
    var onRouter = false;
    String? error, errorDetail;
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      onRouter = await RouterWatchdog(client, onLog: _c.onLog).deleteCachedServerList();
      await _connected(ip);
    } catch (e) {
      // Plain English on screen, the raw exception in the log (ID-108).
      final plain = routerConnectMessage(e, ip);
      errorDetail = plain == null ? null : e.toString();
      error = plain ?? e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    final phone = phoneError != null
        ? "This phone's copy could not be deleted."
        : onPhone!
            ? "This phone's copy deleted."
            : 'None on this phone.';
    if (phoneError != null) _c.logEntry("Could not delete this phone's cached PIA server list: $phoneError", isError: true);
    if (error != null) {
      await AppErrors.system(context, _c,
          errorDetail == null ? 'Could not delete the cached server list on the router: $error $phone' : '$error $phone',
          logDetail: errorDetail);
      return;
    }
    if (phoneError != null) {
      await AppErrors.system(context, _c, "${onRouter ? "The router's copy deleted." : 'None on the router.'} $phone");
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${onRouter ? 'Cached PIA server list deleted from the router.' : 'None on the router.'} $phone'),
    ));
  }

  Future<void> _rebootRouter() async {
    final creds = await _credentials();
    if (creds == null || !mounted) return;
    final (ip, user, pass) = creds;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kSurface,
            title: const Text('Reboot the router?', style: TextStyle(color: kHighlight, fontSize: 14)),
            content: const Text(
              'Are you sure? This will disconnect all devices including WiFi connections.',
              style: TextStyle(color: kText, fontSize: 12),
            ),
            actions: [
              AppButton(
                keyValue: 'settings_reboot_cancel',
                label: 'CANCEL',
                role: ButtonRole.dismiss,
                onPressed: () => Navigator.pop(ctx, false),
              ),
              AppButton(
                keyValue: 'settings_reboot_confirm',
                label: 'REBOOT',
                role: ButtonRole.destructive,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    String? error, errorDetail;
    var bootBefore = '';
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      final wd = RouterWatchdog(client, onLog: _c.onLog);
      // Read before asking, so "it restarted" can be checked rather than assumed (ID-335).
      bootBefore = await wd.bootId();
      await wd.rebootRouter();
      await _connected(ip);
    } catch (e) {
      // Plain English on screen, the raw exception in the log (ID-108).
      final plain = routerConnectMessage(e, ip);
      errorDetail = plain == null ? null : e.toString();
      error = plain ?? e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (error != null) {
      await AppErrors.system(context, _c, errorDetail == null ? 'Could not reboot the router: $error' : error,
          logDetail: errorDetail);
      return;
    }
    // The shared connection went down with the router; the next action opens a fresh one.
    unawaited(_c.closeRouterSession());
    final target = splitHostPort(ip);
    // ID-054: a count to 100 seconds, as the ASUS WebUI shows, that closes as soon as the router answers again.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RebootProgressDialog(
        host: target.host,
        port: target.port,
        answers: widget.testRouterAnswers ?? _routerAnswers,
        onFinished: (message, {bool isSuccess = false, bool isWarning = false}) {
          if (isSuccess) {
            unawaited(_confirmRestarted(ip, user, pass, bootBefore, message));
            return;
          }
          _c.logEntry(message, isSuccess: isSuccess, isWarning: isWarning);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        },
      ),
    );
  }

  /// "The router answered again" meant only that its SSH port took a connection after one failed
  /// probe: a Wi-Fi blip and a dropped reboot request read the same (ID-335). The kernel's boot id
  /// changes on every restart and nothing else, so it is compared, over a fresh connection.
  Future<void> _confirmRestarted(String ip, String user, String pass, String bootBefore, String answered) async {
    String after = '';
    try {
      await _c.closeRouterSession();
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      after = await RouterWatchdog(client, onLog: _c.onLog).bootId();
    } catch (_) {}
    final String message;
    final bool ok;
    if (bootBefore.isEmpty || after.isEmpty) {
      ok = false;
      message = '$answered Whether it restarted could not be checked.';
    } else if (after != bootBefore) {
      ok = true;
      message = answered.replaceFirst('The router answered again', 'The router restarted and answered again');
    } else {
      ok = false;
      message = 'The router answered, but it has not restarted: the reboot request was probably dropped. '
          'Try REBOOT again, or switch it off and on.';
    }
    _c.logEntry(message, isSuccess: ok, isWarning: !ok);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Whether the router accepts a connection on its SSH port again - up enough to log in to.
  static Future<bool> _routerAnswers(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// No confirm prompt: nothing is lost that cannot be retyped, and the button is only enabled when
  /// there is something to clear.
  /// Only ever from this button. See `Entitlement.restore` for why it is never automatic.
  Future<void> _restorePurchase() async {
    // Logged the way the paywall's restore is, with the same messages; this one wrote nothing (ID-047).
    _c.logEntry('Restore started.');
    setState(() => _busy = true);
    // What the entitlement was BEFORE the store was asked, so "restored" is said only when
    // something actually changed (ID-091).
    final wasUnlocked = _c.isUnlocked;
    String message;
    String? storeError;
    try {
      final found = await (widget.testRestore ?? Entitlement.restore)();
      message = !found
          ? RestoreMessages.noneFound
          : wasUnlocked
              ? RestoreMessages.alreadyUnlocked
              : RestoreMessages.restored;
    } catch (e) {
      message = RestoreMessages.failedPlain;
      storeError = RestoreMessages.failed(e);
    }
    if (storeError == null) _c.logEntry(message, isSuccess: message == RestoreMessages.restored);
    if (!mounted) return;
    setState(() => _busy = false);
    _c.setUnlocked(Entitlement.isUnlocked);
    // A failure is a popup, because it is the one outcome that needs an answer; the store's own
    // wording goes to the app log behind it.
    if (storeError != null) {
      await AppErrors.system(context, _c, message, logDetail: storeError);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Changes stock's cap on simultaneous VPNs. See [RouterSlotService.setMaxActiveVpns] for why this is a
  /// user decision behind a warning rather than something the app recommends.
  /// Opens ROUTER RESOLVER STATUS or ROUTER DNS ROUTING on the shared router session.
  ///
  /// The window reads the router itself, and shows its own error if it cannot; the session counts
  /// as connected once a read has reached the router.
  Future<void> _openDnsReport(
      DnsReportScreen Function({Key? key, required SSHClient client, VoidCallback? onLoaded}) screen) async {
    final creds = await _credentials();
    if (creds == null || !mounted) return;
    final (ip, user, pass) = creds;
    final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
    await Navigator.of(context).push<void>(MaterialPageRoute(
      settings: RouteSettings(name: AppDestination.settings.routeName),
      builder: (_) => screen(client: client, onLoaded: () => _connected(ip)),
    ));
  }

  Future<void> _maxActiveVpns() async {
    // Paid first, so a locked user is not asked for router credentials only to meet the paywall after.
    if (!_c.isUnlocked) {
      if (!await Paywall.show(context, _c, pitch: Pitch.maxVpns) || !mounted) return;
    }
    final creds = await _credentials();
    if (creds == null || !mounted) return;
    final (ip, user, pass) = creds;

    setState(() => _busy = true);
    RouterSlotService? svc;
    RouterFirmware? firmware;
    var current = kDefaultStockMaxActiveSlots;
    String? error, errorDetail;
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      svc = RouterSlotService(client, onLog: _c.onLog);
      firmware = classifyFirmwareTag(await svc.readFirmwareTag());
      if (firmware == RouterFirmware.stock) current = await svc.readMaxActiveVpns();
      await _connected(ip);
    } catch (e) {
      // Plain English on screen, the raw exception in the log (ID-108).
      final plain = routerConnectMessage(e, ip);
      errorDetail = plain == null ? null : e.toString();
      error = plain ?? e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (error != null) {
      await AppErrors.system(context, _c, errorDetail == null ? 'Could not read the router: $error' : error,
          logDetail: errorDetail);
      return;
    }
    if (firmware != RouterFirmware.stock || svc == null) {
      // Merlin has no such key and no such limit; writing it there would create a setting nothing reads.
      final message = firmware == RouterFirmware.merlin
          ? 'Merlin has no limit on active VPNs, so there is nothing to change.'
          : 'This router firmware is not supported, so nothing was changed.';
      _c.logEntry(message);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final chosen = await showDialog<int>(context: context, builder: (_) => _MaxVpnsDialog(current: current));
    if (chosen == null || !mounted) return;
    if (chosen == current) {
      _c.logEntry('Maximum active VPNs left at $current, unchanged.');
      return;
    }

    setState(() => _busy = true);
    try {
      await svc.setMaxActiveVpns(chosen);
    } catch (e) {
      // Plain English on screen, the raw exception in the log (ID-108).
      final plain = routerConnectMessage(e, ip);
      errorDetail = plain == null ? null : e.toString();
      error = plain ?? e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (error != null) {
      await AppErrors.system(context, _c, errorDetail == null ? 'Could not change the limit: $error' : error,
          logDetail: errorDetail);
      return;
    }
    final message = 'Maximum active VPNs set to $chosen.';
    _c.logEntry(message, isWarning: chosen > 2);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// HOME SCREEN WIDGET KEY (ID-376): the dialog handles the phone side (Keystore) itself; these
  /// two do the router side, the same credential flow every other action on this screen uses.
  /// Nothing is saved on the phone unless the router side succeeds - see _WidgetKeyDialog._generate
  /// and ._remove - so "a key exists" always means it is actually installed, not just made.
  Future<void> _widgetKey() => showDialog<void>(
        context: context,
        builder: (_) => _WidgetKeyDialog(
          store: _widgetKeyStore,
          installOnRouter: _installWidgetKeyOnRouter,
          removeFromRouter: _removeWidgetKeysFromRouter,
        ),
      );

  /// Installs the line, remembers the login it was installed under (the key cannot be used without
  /// it - see WidgetKeyStore's header), and starts the periodic refresh. Returns null, or a
  /// plain-English reason the dialog shows instead of claiming success.
  Future<String?> _installWidgetKeyOnRouter(String publicKeyLine) async {
    final creds = await _credentials();
    if (creds == null || !mounted) return 'Cancelled - nothing was made or installed.';
    final (ip, user, pass) = creds;
    // GENERATE on a phone that already has a key replaces it: the old line goes in the same write.
    final old = await _widgetKeyStore.read();
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      await WidgetKeyRouterService(client, onLog: _c.onLog)
          .install(publicKeyLine, replacing: old == null ? null : widgetKeyPairFromSeed(old).publicKeyBytes);
      await _connected(ip);
      await _widgetKeyStore.saveLogin(user);
      await (widget.testScheduleRefresh ?? scheduleWidgetRefresh)();
      return null;
    } catch (e) {
      return _widgetKeyFailure(e, ip, 'the key was saved', 'nothing was saved on this phone');
    }
  }

  /// Takes every widget key off the router - every device's, leftovers included (ID-407) - and stops
  /// the periodic refresh. The phone's own key and login are cleared by the dialog, and only once
  /// this has succeeded.
  Future<String?> _removeWidgetKeysFromRouter() async {
    final creds = await _credentials();
    if (creds == null || !mounted) return "Cancelled - nothing was removed from your router or this phone.";
    final (ip, user, pass) = creds;
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      final n = await WidgetKeyRouterService(client, onLog: _c.onLog).removeAll();
      _c.logEntry('Removed $n widget key(s) from the router.', isSuccess: true);
      await _connected(ip);
      await (widget.testCancelRefresh ?? cancelWidgetRefresh)();
      return null;
    } catch (e) {
      return _widgetKeyFailure(e, ip, 'the keys were removed', "this phone's key was kept");
    }
  }

  /// What the widget key dialog says when its router side failed (ID-407): the service's own reading
  /// as it is, a connection failure as routerConnectMessage puts it, and anything else in plain words,
  /// with the raw error in the app log. "SSHStateError(SSH connection closed)" told nobody anything.
  String _widgetKeyFailure(Object e, String ip, String what, String phone) {
    if (e is WidgetKeyRouterException) return e.message;
    final plain = routerConnectMessage(e, ip);
    _c.logEntry('Widget key: $e', isError: true);
    return plain ?? 'The router closed the connection before $what, so $phone. Try again.';
  }

  /// SECURE STARTUP (ID-356): whether pings to the internet are blocked for every device not on a
  /// VPN, which is the only way stock can stop a pinned device's pings leaking while it starts. The
  /// firmware's filter holds pings for the whole network or not at all (ID-348). Free, like the guard
  /// it completes: protection is never behind the paywall.
  Future<void> _secureStartup() async {
    final creds = await _credentials();
    if (creds == null || !mounted) return;
    final (ip, user, pass) = creds;

    setState(() => _busy = true);
    DeviceAssignmentService? svc;
    RouterFirmware? firmware;
    var blocked = false;
    String? error, errorDetail;
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      firmware = classifyFirmwareTag(await RouterSlotService(client, onLog: _c.onLog).readFirmwareTag());
      if (firmware != null) setRouterFirmware(firmware);
      if (firmware == RouterFirmware.stock) {
        svc = DeviceAssignmentService(client, onLog: _c.onLog);
        blocked = await svc.readPingBlock();
      }
      await _connected(ip);
    } catch (e) {
      // Plain English on screen, the raw exception in the log (ID-108).
      final plain = routerConnectMessage(e, ip);
      errorDetail = plain == null ? null : e.toString();
      error = plain ?? e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (error != null) {
      await AppErrors.system(context, _c, errorDetail == null ? 'Could not read the router: $error' : error,
          logDetail: errorDetail);
      return;
    }
    if (firmware != RouterFirmware.stock || svc == null) {
      // Merlin's own kill switch already holds a VPN client's traffic, pings included.
      final message = firmware == RouterFirmware.merlin
          ? "Merlin's own kill switch already covers this, so there is nothing to change."
          : 'This router firmware is not supported, so nothing was changed.';
      _c.logEntry(message);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final chosen = await showDialog<bool>(context: context, builder: (_) => _SecureStartupDialog(blocked: blocked));
    if (chosen == null || chosen == blocked || !mounted) return;

    setState(() => _busy = true);
    var held = false, pinned = true;
    try {
      held = await svc.setPingBlock(chosen);
      if (chosen && !held) pinned = await svc.anyPinned();
    } catch (e) {
      final plain = routerConnectMessage(e, ip);
      errorDetail = plain == null ? null : e.toString();
      error = plain ?? e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (error != null) {
      await AppErrors.system(context, _c, errorDetail == null ? 'Could not change secure startup: $error' : error,
          logDetail: errorDetail);
      return;
    }
    final (String message, bool ok) = switch ((chosen, held, pinned)) {
      (true, true, _) => (
          "Secure startup on: devices not on a VPN can't ping the internet. Devices on a VPN still ping through "
              'their tunnels.',
          true
        ),
      (true, false, false) => ('Secure startup saved. Pings will be blocked once a device is assigned to a VPN.', true),
      // Nothing asks again on a timer since ID-364. The choice is saved, and the guard puts it into the
      // router's filter on its next run, which the router's next firewall restart brings (ID-368).
      (true, false, true) => (
          "Secure startup is saved, but the router hasn't applied it yet. It will the next time the router "
              'restarts its firewall, which it does whenever a tunnel starts or stops, or the router restarts.',
          false
        ),
      (false, true, _) => (
          'Secure startup off, but the router still blocks pings: something else set it, in Firewall, '
              'Network Services Filter.',
          false
        ),
      (false, false, _) => ('Secure startup off: every device can ping the internet again.', true),
    };
    // What didn't go as asked is a popup the user dismisses; a snackbar is gone in four seconds (ID-368).
    if (!ok) return AppErrors.warning(context, _c, message);
    _c.logEntry(message, isSuccess: true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _forgetRouterIp() async {
    // ID-052: asks first, like the other rows on this screen that remove something.
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kSurface,
            title: const Text('Forget the router address?', style: TextStyle(color: kHighlight, fontSize: 14)),
            content: Text(
              'Deletes ${_c.rememberedRouterIp} from this phone. The next connect screen starts from the factory '
              'default instead. No router credentials are stored on this device, so nothing else is removed.',
              style: const TextStyle(color: kText, fontSize: 12),
            ),
            actions: [
              AppButton(
                keyValue: 'settings_forget_ip_cancel',
                label: 'CANCEL',
                role: ButtonRole.dismiss,
                onPressed: () => Navigator.pop(ctx, false),
              ),
              AppButton(
                keyValue: 'settings_forget_ip_confirm',
                label: 'FORGET',
                role: ButtonRole.destructive,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await _c.forgetRouterIp();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Remembered router address and its SSH key deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      maxContentWidth: kFormMaxWidth,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Named after the menu item that opened it, in that item's colour (ID-112).
        destinationHeading(AppDestination.settings, key: const Key('settings_heading')),
        const SizedBox(height: 16),
        // The order Andrew set on 2026-10-14 (ID-325): the uninstall last. RESTORE PURCHASE, shown only
        // where purchasing is, sits just above it.
        _Action(
          keyValue: 'settings_reboot_router',
          label: 'REBOOT ROUTER',
          note: 'Restarts the router. Everything on your network loses its connection while it comes back.',
          icon: Icons.restart_alt_outlined,
          destructive: true,
          onTap: _busy ? null : _rebootRouter,
        ),
        // Two read-only windows on the router's name lookups (ID-194), each with an icon used nowhere
        // else in the app. Neither changes anything, so neither is behind the paywall.
        _Action(
          keyValue: 'settings_resolver_status',
          label: 'ROUTER RESOLVER STATUS',
          note: 'Checks the router is answering name lookups, and shows the files and settings behind them. '
              'Changes nothing.',
          icon: Icons.troubleshoot_outlined,
          onTap: _busy ? null : () => _openDnsReport(DnsReportScreen.resolver),
        ),
        _Action(
          keyValue: 'settings_dns_routing',
          label: 'ROUTER DNS ROUTING',
          note: "Shows where each device's, the router's and the watchdogs' lookups go: through a tunnel, or to the "
              'Internet. Changes nothing.',
          icon: Icons.alt_route_outlined,
          onTap: _busy ? null : () => _openDnsReport(DnsReportScreen.routing),
        ),
        // ID-376: makes or removes the widget's key, on the router and the phone. The dialog itself
        // reads the current state, so nothing here needs it in advance.
        _Action(
          keyValue: 'settings_widget_key',
          label: 'HOME SCREEN WIDGET KEY',
          note: "Makes or removes the key the home screen widget will use to check your router's status "
              'on its own.',
          icon: Icons.key_outlined,
          onTap: _busy ? null : _widgetKey,
        ),
        // The router address and its host key fingerprint are kept on the phone, so they need a way to
        // be cleared. Greyed out when there is nothing stored.
        ListenableBuilder(
          listenable: _c,
          builder: (context, _) => _Action(
            keyValue: 'settings_forget_router_ip',
            label: 'FORGET ROUTER IP',
            note: 'Deletes the remembered router address. No router SSH credentials are stored on this device.',
            icon: Icons.wifi_off_outlined,
            onTap: _c.rememberedRouterIp.isEmpty || _busy ? null : _forgetRouterIp,
          ),
        ),
        _Action(
          keyValue: 'settings_del_pia_cert',
          label: 'REMOVE CACHED PIA CERT',
          note: 'Removes $kPiaCaCertPath. The watchdog downloads a fresh copy on its next run.',
          icon: Icons.gpp_bad_outlined,
          onTap: _busy ? null : _deletePiaCert,
        ),
        // ID-325: both copies of the last server list that passed PIA's signature check.
        _Action(
          keyValue: 'settings_del_pia_servers',
          label: 'REMOVE CACHED PIA SERVERS',
          note: "Removes $kPiaServerListPath and this phone's copy: the last PIA server lists that passed "
              "PIA's signature check. The next list that passes is kept again.",
          icon: Icons.dns_outlined,
          onTap: _busy ? null : _deleteServerLists,
        ),
        // A user decision behind a plain warning, and deliberately not written up outside the code - see
        // RouterSlotService.setMaxActiveVpns. Red because the warning is the point of the row.
        _Action(
          keyValue: 'settings_max_vpns',
          label: 'MAX ACTIVE VPNS',
          note: 'Unsupported by ASUS. Lets more than the default of 2 VPNs run at once, on stock firmware.',
          icon: Icons.warning_amber_outlined,
          destructive: true,
          onTap: _busy ? null : _maxActiveVpns,
        ),
        // ID-356: hidden once the router is known to be Merlin, whose own kill switch covers it. Before
        // the firmware is known it shows, and says on tap if there is nothing to change, as MAX ACTIVE
        // VPNS does.
        if (!(firmwareDetected && routerFirmware == RouterFirmware.merlin))
          _Action(
            keyValue: 'settings_secure_startup',
            label: 'SECURE STARTUP',
            note: 'Stops devices on a VPN leaking pings while the router starts.',
            icon: Icons.security_outlined,
            onTap: _busy ? null : _secureStartup,
          ),
        // The only row here that gives something back rather than removing it. It is on this screen
        // because this is where the app's one-off actions live, and because someone hunting for it
        // after a new phone will look under settings before they look at a paywall.
        if (Entitlement.purchasingAvailable || widget.testRestore != null)
          _Action(
            keyValue: 'settings_restore_purchase',
            label: 'RESTORE PURCHASE',
            note: 'Recovers the unlock on a new phone or after a reinstall. Nothing is stored on this device: '
                'the purchase belongs to your Google account.',
            icon: Icons.restore_outlined,
            onTap: _busy ? null : _restorePurchase,
          ),
        _Action(
          keyValue: 'settings_uninstall',
          label: 'UNINSTALL FEATURES DEPLOYED TO ROUTER',
          note: 'Restores the two boot scripts the app replaced, deletes $kRouterAppDir, and removes the '
              'watchdog schedules and every setting the app wrote. Your VPN tunnels are left alone.',
          icon: Icons.delete_forever_outlined,
          destructive: true,
          onTap: _busy ? null : _uninstall,
        ),
        if (_busy) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator(color: kHighlight)),
        ],
      ]),
    );
  }
}

/// One labelled action with a line explaining what it removes.
///
/// The explanation is not optional here: every button on this screen destroys something, and a bare
/// label leaves the user to guess how much.
class _Action extends StatelessWidget {
  const _Action({
    required this.keyValue,
    required this.label,
    required this.note,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  final String keyValue, label, note;
  final IconData icon;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tint = AppButton.tint(destructive ? ButtonRole.destructive : ButtonRole.action, enabled: onTap != null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OutlinedButton.icon(
          key: Key(keyValue),
          style: OutlinedButton.styleFrom(
            foregroundColor: tint,
            side: BorderSide(color: tint),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            alignment: Alignment.centerLeft,
          ),
          onPressed: onTap,
          icon: Icon(icon, size: 18, color: tint),
          label: Text(label, style: TextStyle(color: tint, fontSize: 12)),
        ),
        const SizedBox(height: 6),
        Text(note, style: const TextStyle(color: kMuted, fontSize: 12)),
      ]),
    );
  }
}

/// Asks for the new cap, with the warning above the field rather than behind a link.
///
/// A Dialog with its own scroll view rather than an AlertDialog, for the keyboard reason
/// SshCredsDialog gives.
class _MaxVpnsDialog extends StatefulWidget {
  const _MaxVpnsDialog({required this.current});
  final int current;

  @override
  State<_MaxVpnsDialog> createState() => _MaxVpnsDialogState();
}

class _MaxVpnsDialogState extends State<_MaxVpnsDialog> {
  late final _ctrl = TextEditingController(text: '${widget.current}');
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final n = int.tryParse(_ctrl.text.trim());
    if (n == null || n < 2 || n > 5) {
      setState(() => _error = 'Enter a number from 2 to 5.');
      return;
    }
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Maximum active VPNs', style: TextStyle(color: kHighlight, fontSize: 14)),
                const SizedBox(height: 12),
                Container(
                  key: const Key('max_vpns_warning'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: kError), borderRadius: BorderRadius.circular(8)),
                  child: const Text(
                    'Unsupported by ASUS, whose default is 2. This changes the limit for every VPN on the router - '
                    'WireGuard and OpenVPN alike, not only the slots this app manages - and a value above 2 may stop '
                    'the router booting. It is your decision.',
                    style: TextStyle(color: kError, fontSize: 12, height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  enableIMEPersonalizedLearning: false,
                  key: const Key('max_vpns_field'),
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(
                    labelText: 'Active VPNs at once',
                    helperText: 'A number from 2 to 5.',
                  ),
                  onSubmitted: (_) => _save(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, key: const Key('max_vpns_error'), style: const TextStyle(color: kError, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  AppButton(
                    keyValue: 'max_vpns_cancel',
                    label: 'CANCEL',
                    role: ButtonRole.dismiss,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  AppButton(keyValue: 'max_vpns_save', label: 'SAVE', role: ButtonRole.destructive, onPressed: _save),
                ]),
              ]),
            ),
          ),
        ),
      );
}

/// SECURE STARTUP's choice (ID-356): pings to the internet allowed, the default, or blocked for every
/// device not on a VPN. SAVE is live only once the other option is picked, so CANCEL is always the
/// way out with nothing changed. Wording agreed with Andrew on 2026-10-01.
/// ID-376: shows whether the widget's key exists, and makes/installs or removes it. The router
/// round trip (asking for credentials if the session needs them, connecting, logging) is
/// [installOnRouter]/[removeFromRouter], from _SettingsScreenState - this dialog only ever touches
/// [store], the phone side, and only once the router side has already succeeded.
class _WidgetKeyDialog extends StatefulWidget {
  const _WidgetKeyDialog({required this.store, required this.installOnRouter, required this.removeFromRouter});
  final WidgetKeyStore store;
  final Future<String?> Function(String publicKeyLine) installOnRouter;
  final Future<String?> Function() removeFromRouter;

  @override
  State<_WidgetKeyDialog> createState() => _WidgetKeyDialogState();
}

class _WidgetKeyDialogState extends State<_WidgetKeyDialog> {
  bool _loading = true;
  bool _exists = false;
  bool _working = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final exists = await widget.store.exists();
    if (!mounted) return;
    setState(() {
      _exists = exists;
      _loading = false;
    });
  }

  Future<void> _generate() async {
    setState(() => _working = true);
    final pair = generateWidgetKeyPair();
    final line = openSshPublicKeyLine(
      pair.publicKeyBytes,
      restriction: widgetKeyRestriction(kWidgetStatusCommand),
      comment: kWidgetKeyComment,
    );
    final error = await widget.installOnRouter(line);
    if (error == null) await widget.store.save(pair.seed);
    if (!mounted) return;
    setState(() {
      _exists = error == null;
      _working = false;
      _note = error == null
          ? 'Made, and installed on your router. The widget can refresh itself once the background refresh is built.'
          : 'Not installed: $error';
    });
  }

  Future<void> _remove() async {
    // It takes other devices' keys too, so it asks first (ID-407).
    final sure = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kSurface,
            title: const Text('Remove every widget key?', style: TextStyle(color: kHighlight, fontSize: 14)),
            content: const Text(
              'This takes the widget keys of all your phones and tablets off your router, not just this one. '
              'Each widget stops refreshing until GENERATE is used on that device.',
              style: TextStyle(color: kText, fontSize: 12),
            ),
            actions: [
              AppButton(
                  keyValue: 'widget_key_remove_cancel',
                  label: 'CANCEL',
                  role: ButtonRole.dismiss,
                  onPressed: () => Navigator.pop(ctx, false)),
              AppButton(
                  keyValue: 'widget_key_remove_confirm',
                  label: 'REMOVE',
                  role: ButtonRole.destructive,
                  onPressed: () => Navigator.pop(ctx, true)),
            ],
          ),
        ) ??
        false;
    if (!sure || !mounted) return;
    setState(() => _working = true);
    final error = await widget.removeFromRouter();
    if (error == null) await widget.store.remove();
    if (!mounted) return;
    setState(() {
      _exists = error == null ? false : _exists;
      _working = false;
      _note = error == null ? "Every widget key removed from your router, and this phone's key deleted." : 'Not removed: $error';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Home screen widget key', style: TextStyle(color: kHighlight, fontSize: 14)),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator(color: kHighlight)),
              )
            // The text scrolls on a small screen; the buttons stay in view (ID-407: with the result below
            // the help, it overflowed a phone-sized screen).
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(
                      _exists
                          ? "Key created: saved to Android's local keystore, and installed on your router."
                          : 'No key exists yet.',
                      key: const Key('widget_key_status'),
                      style: const TextStyle(color: kText, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "This allows the home screen widget to display your router's VPN status, and do nothing else. "
                      'An unlocked stolen phone could read the status but it could not change anything at all.',
                      style: TextStyle(color: kText, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'GENERATE makes a new key for this phone and installs it on your router. Keys belonging to your '
                      'other phones or tablets are left alone.\n\n'
                      'REMOVE takes every widget key off your router, including those of your other phones and tablets, '
                      "and deletes this phone's key. Their widgets stop refreshing until you tap GENERATE on each one "
                      "again. Use it if GENERATE fails, or after clearing the app's storage.",
                      key: Key('widget_key_help'),
                      style: TextStyle(color: kText, fontSize: 12, height: 1.4),
                    ),
                    if (_note != null) ...[
                      const SizedBox(height: 8),
                      Text(_note!, key: const Key('widget_key_note'), style: const TextStyle(color: kHighlight, fontSize: 12)),
                    ],
                  ]),
                ),
              ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              AppButton(
                keyValue: 'widget_key_close',
                label: 'CLOSE',
                role: ButtonRole.dismiss,
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              // All three, always (ID-407): REMOVE has to be there for a phone whose own key was lost with its
              // storage, which is just when leftovers on the router stop GENERATE working.
              if (!_loading) ...[
                AppButton(
                  keyValue: 'widget_key_remove',
                  label: 'REMOVE',
                  role: ButtonRole.destructive,
                  onPressed: _working ? null : _remove,
                ),
                const SizedBox(width: 8),
                AppButton(
                  keyValue: 'widget_key_generate',
                  label: 'GENERATE',
                  onPressed: _working ? null : _generate,
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

class _SecureStartupDialog extends StatefulWidget {
  const _SecureStartupDialog({required this.blocked});
  final bool blocked;

  @override
  State<_SecureStartupDialog> createState() => _SecureStartupDialogState();
}

class _SecureStartupDialogState extends State<_SecureStartupDialog> {
  late bool _block = widget.blocked;

  Widget _option(bool block, String label, String key) => InkWell(
        key: Key(key),
        onTap: () => setState(() => _block = block),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(_block == block ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: kHighlight, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(color: kText, fontSize: 13))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const bold = TextStyle(fontWeight: FontWeight.bold);
    return Dialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Secure startup', style: TextStyle(color: kHighlight, fontSize: 14)),
            const SizedBox(height: 12),
            // The text scrolls on a small screen; the choice and the buttons stay in view.
            _option(false, 'ALLOW pings (default)', 'secure_startup_allow'),
            _option(true, 'BLOCK pings', 'secure_startup_block'),
            const SizedBox(height: 12),
            const Flexible(
              child: SingleChildScrollView(
                child: Text.rich(
                  key: Key('secure_startup_text'),
                  TextSpan(style: TextStyle(color: kText, fontSize: 12, height: 1.4), children: [
                    TextSpan(text: 'Allow: ', style: bold),
                    TextSpan(
                        text: 'every device can ping the internet. But briefly while the router starts, or for about '
                            'half a minute after it resets its network, devices on a VPN can ping outside their '
                            'tunnel, showing your real internet address.\n\n'),
                    TextSpan(text: 'Block: ', style: bold),
                    TextSpan(text: 'closes that gap, but devices not on a VPN can never ping '),
                    TextSpan(text: 'anything', style: TextStyle(color: kError, fontWeight: FontWeight.bold)),
                    TextSpan(
                        text: ' on the internet, which makes troubleshooting harder. Devices on a VPN still ping '
                            'through their tunnels.\n\n'),
                    TextSpan(text: "Stock ASUS firmware can't block pings for just some devices."),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              AppButton(
                keyValue: 'secure_startup_cancel',
                label: 'CANCEL',
                role: ButtonRole.dismiss,
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              AppButton(
                keyValue: 'secure_startup_save',
                label: 'SAVE',
                onPressed: _block == widget.blocked ? null : () => Navigator.pop(context, _block),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Counts a reboot up to 100 seconds, one per cent a second as the ASUS WebUI does, and closes as soon as the
/// router answers again - it is often back well before 100 (ID-054). No buttons: the back key leaves it, and
/// the reboot carries on either way.
///
/// "Answers again" means answering AFTER having stopped: the router takes a few seconds to go down, and a
/// check that caught it before then would close the count straight away.
class _RebootProgressDialog extends StatefulWidget {
  const _RebootProgressDialog({required this.host, required this.port, required this.answers, required this.onFinished});

  final String host;
  final int port;
  final Future<bool> Function(String host, int port) answers;
  final void Function(String message, {bool isSuccess, bool isWarning}) onFinished;

  static const int seconds = 100;
  static const int checkEverySeconds = 3;

  @override
  State<_RebootProgressDialog> createState() => _RebootProgressDialogState();
}

class _RebootProgressDialogState extends State<_RebootProgressDialog> {
  Timer? _timer;
  int _elapsed = 0;
  bool _wentDown = false;
  bool _checking = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_done || !mounted) return;
    setState(() => _elapsed++);
    if (_elapsed >= _RebootProgressDialog.seconds) {
      _finish(
          'The router has not answered after ${_RebootProgressDialog.seconds} seconds. It may still be starting; '
          'try again in a minute.',
          isWarning: true);
      return;
    }
    if (_checking || _elapsed % _RebootProgressDialog.checkEverySeconds != 0) return;
    _checking = true;
    final up = await widget.answers(widget.host, widget.port);
    _checking = false;
    if (_done || !mounted) return;
    if (!up) {
      _wentDown = true;
    } else if (_wentDown) {
      _finish('The router answered again after $_elapsed seconds.', isSuccess: true);
    }
  }

  void _finish(String message, {bool isSuccess = false, bool isWarning = false}) {
    _done = true;
    _timer?.cancel();
    widget.onFinished(message, isSuccess: isSuccess, isWarning: isWarning);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Rebooting the router', style: TextStyle(color: kHighlight, fontSize: 14)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('$_elapsed%', key: const Key('reboot_progress_percent'), style: const TextStyle(color: kText, fontSize: 28)),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _elapsed / _RebootProgressDialog.seconds, color: kHighlight),
          const SizedBox(height: 12),
          const Text(
            'Closes when the router answers again. Back leaves this screen; the reboot will continue.',
            style: TextStyle(color: kMuted, fontSize: 12),
          ),
        ]),
      );
}
