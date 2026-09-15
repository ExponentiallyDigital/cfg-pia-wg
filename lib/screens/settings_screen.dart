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
import '../entitlement.dart';
import '../firmware.dart';
import '../router_slot_service.dart' show RouterSlotService, kDefaultStockMaxActiveSlots, openSshClient, splitHostPort;
import '../review_service.dart';
import '../router_watchdog.dart';
import '../session_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/paywall.dart';
import '../widgets/error_presenter.dart';
import '../widgets/ssh_creds_dialog.dart';

class SettingsScreen extends StatefulWidget {
  /// Injected by tests so the router actions can run without a router.
  final Future<SSHClient> Function(String ip, String user, String pass)? testClientFactory;

  /// Injected by tests in place of the store's restore; it also shows RESTORE PURCHASE in a build with no store key.
  final Future<bool> Function()? testRestore;

  /// Injected by tests in place of the check that the router answers again after a reboot.
  final Future<bool> Function(String host, int port)? testRouterAnswers;
  const SettingsScreen({super.key, this.testClientFactory, this.testRestore, this.testRouterAnswers});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SessionController _c;
  bool _busy = false;

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
      builder: (_) => SshCredsDialog(initialIp: _c.routerIpPrefill, initialUser: user, initialPass: pass),
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
                'in it - the watchdog scripts, the cached PIA certificate, and the helper '
                'binaries.\n\n'
                'Your VPN tunnels are NOT touched. They keep working, and you can manage them '
                "from your router's own web interface.\n\n"
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
    String? error;
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      done = await RouterWatchdog(client, onLog: _c.onLog).uninstallFromRouter();
      await _connected(ip);
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (error != null) {
      await AppErrors.system(context, _c, 'Could not remove the app from the router: $error');
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
          Text(done!.join('\n'), style: const TextStyle(color: kText, fontSize: 12)),
          // Amber, and set apart. The cron entries are gone but a running watchdog process is
          // not, and the firmware keeps its own idea of what is configured until it restarts.
          const SizedBox(height: 16),
          const Text('Please restart your router.', style: TextStyle(color: kWarn, fontSize: 12)),
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
    String? error;
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      deleted = await RouterWatchdog(client, onLog: _c.onLog).deleteCachedPiaCert();
      await _connected(ip);
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (error != null) {
      await AppErrors.system(context, _c, 'Could not delete the cached certificate: $error');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(deleted ? 'Cached PIA certificate deleted.' : 'No cached PIA certificate on the router.'),
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
    String? error;
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      await RouterWatchdog(client, onLog: _c.onLog).rebootRouter();
      await _connected(ip);
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (error != null) {
      await AppErrors.system(context, _c, 'Could not reboot the router: $error');
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
          _c.logEntry(message, isSuccess: isSuccess, isWarning: isWarning);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        },
      ),
    );
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
    String message;
    var failed = false;
    try {
      message = await (widget.testRestore ?? Entitlement.restore)() ? RestoreMessages.restored : RestoreMessages.noneFound;
    } catch (e) {
      message = RestoreMessages.failed(e);
      failed = true;
    }
    _c.logEntry(message, isSuccess: message == RestoreMessages.restored, isError: failed);
    if (!mounted) return;
    setState(() => _busy = false);
    _c.setUnlocked(Entitlement.isUnlocked);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Changes stock's cap on simultaneous VPNs. See [RouterSlotService.setMaxActiveVpns] for why this is a
  /// user decision behind a warning rather than something the app recommends.
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
    String? error;
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      svc = RouterSlotService(client, onLog: _c.onLog);
      firmware = classifyFirmwareTag(await svc.readFirmwareTag());
      if (firmware == RouterFirmware.stock) current = await svc.readMaxActiveVpns();
      await _connected(ip);
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (error != null) {
      await AppErrors.system(context, _c, 'Could not read the router: $error');
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
      error = e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (error != null) {
      await AppErrors.system(context, _c, 'Could not change the limit: $error');
      return;
    }
    final message = 'Maximum active VPNs set to $chosen.';
    _c.logEntry(message, isWarning: chosen > 2);
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
      const SnackBar(content: Text('Remembered router address deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      maxContentWidth: kFormMaxWidth,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The order agreed on 2026-09-13.
        _Action(
          keyValue: 'settings_reboot_router',
          label: 'REBOOT ROUTER',
          note: 'Restarts the router. Everything on your network loses its connection while it comes back.',
          icon: Icons.restart_alt_outlined,
          destructive: true,
          onTap: _busy ? null : _rebootRouter,
        ),
        // The router address is the one thing the app keeps on device storage, so it needs a way to
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
        _Action(
          keyValue: 'settings_uninstall',
          label: 'UNINSTALL FEATURES DEPLOYED TO ROUTER',
          note: 'Restores the two boot scripts the app replaced, deletes $kRouterAppDir, and removes the '
              'watchdog schedules and every setting the app wrote. Your VPN tunnels are left alone.',
          icon: Icons.delete_forever_outlined,
          destructive: true,
          onTap: _busy ? null : _uninstall,
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
      _finish('The router has not answered after ${_RebootProgressDialog.seconds} seconds. It may still be starting; '
          'try again in a minute.', isWarning: true);
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
            'Closes when the router answers again. Back leaves this screen; the reboot carries on.',
            style: TextStyle(color: kMuted, fontSize: 12),
          ),
        ]),
      );
}
