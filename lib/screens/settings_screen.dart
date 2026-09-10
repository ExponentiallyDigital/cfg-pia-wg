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
// Everything here removes something. FORGET ROUTER IP and DEL PIA CERT used to sit on ABOUT, among
// the build metadata and the licence text, which is a page people open to read rather than to act
// on - and the uninstall belongs beside them rather than anywhere a stray tap could reach it.
//
// Drawer only, never on the main menu: an uninstall is not something to offer on the way in.

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../firmware.dart';
import '../router_slot_service.dart' show openSshClient;
import '../router_watchdog.dart';
import '../session_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/error_presenter.dart';
import '../widgets/ssh_creds_dialog.dart';

class SettingsScreen extends StatefulWidget {
  /// Injected by tests so the router actions can run without a router.
  final Future<SSHClient> Function(String ip, String user, String pass)? testClientFactory;
  const SettingsScreen({super.key, this.testClientFactory});

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

  Future<void> _uninstall() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kSurface,
            title: const Text('Remove cfg-pia-wg from the router?', style: TextStyle(color: kHighlight, fontSize: 14)),
            content: const SingleChildScrollView(
              child: Text(
                'Puts back the two boot scripts the app replaced, and deletes $kRouterAppDir '
                'along with everything in it - the watchdog scripts, the cached PIA certificate, '
                'and the helper binaries the app installed.\n\n'
                'Your VPN tunnels and their settings are NOT touched, and neither are any '
                'watchdogs that are currently scheduled. Delete those first if you want them gone '
                'too, or the next reboot will leave a watchdog with no script to run.\n\n'
                'The app itself keeps working. Deploying a watchdog again puts everything back.',
                style: TextStyle(color: kText, fontSize: 12),
              ),
            ),
            actions: [
              TextButton(
                key: const Key('settings_uninstall_cancel'),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCEL'),
              ),
              TextButton(
                key: const Key('settings_uninstall_confirm'),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('REMOVE', style: TextStyle(color: kError)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    final creds = await _credentials();
    if (creds == null || !mounted) return;
    final (ip, user, pass) = creds;

    setState(() => _busy = true);
    List<String>? done;
    String? error;
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      done = await RouterWatchdog(client, onLog: _c.onLog).uninstallFromRouter();
      await _c.rememberRouterIp(ip);
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
        content: Text(done!.join('\n'), style: const TextStyle(color: kText, fontSize: 12)),
        actions: [
          TextButton(
            key: const Key('settings_uninstall_done'),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
              TextButton(
                key: const Key('settings_del_cert_cancel'),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCEL'),
              ),
              TextButton(
                key: const Key('settings_del_cert_confirm'),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('DELETE', style: TextStyle(color: kError)),
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
      await _c.rememberRouterIp(ip);
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

  /// No confirm prompt: nothing is lost that cannot be retyped, and the button is only enabled when
  /// there is something to clear.
  Future<void> _forgetRouterIp() async {
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
        const Text('ROUTER', style: TextStyle(color: kHighlight, fontSize: 12, letterSpacing: 1.5)),
        const SizedBox(height: 12),
        _Action(
          keyValue: 'settings_uninstall',
          label: 'UNINSTALL FEATURES INSTALLED TO ROUTER',
          note: 'Restores the two boot scripts the app replaced and deletes $kRouterAppDir. '
              'Tunnels, watchdog settings and cron entries are left alone.',
          icon: Icons.delete_forever_outlined,
          destructive: true,
          onTap: _busy ? null : _uninstall,
        ),
        _Action(
          keyValue: 'settings_del_pia_cert',
          label: 'DEL PIA CERT',
          note: 'Removes $kPiaCaCertPath. The watchdog downloads a fresh copy on its next run.',
          icon: Icons.gpp_bad_outlined,
          onTap: _busy ? null : _deletePiaCert,
        ),
        const SizedBox(height: 20),
        const Text('THIS DEVICE', style: TextStyle(color: kHighlight, fontSize: 12, letterSpacing: 1.5)),
        const SizedBox(height: 12),
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
    final enabled = onTap != null;
    final tint = !enabled
        ? kMuted
        : destructive
            ? kError
            : kHighlight;
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
