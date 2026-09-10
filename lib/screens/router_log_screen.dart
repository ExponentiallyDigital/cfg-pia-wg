// screens/router_log_screen.dart - the router's own syslog, read over the shared SSH session.
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
// Every alert email and half the failure messages in this app end with "check your router log",
// which until now meant leaving the app for an SSH client or the web interface. The watchdog's own
// lines are in here alongside the firmware's, so a reconfigure can be read in the context of
// whatever the router was doing at the time.

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../router_command.dart';
import '../router_slot_service.dart' show openSshClient;
import '../session_controller.dart';
import '../widgets/app_drawer.dart' show navigateToDestination;
import '../widgets/error_presenter.dart';
import '../widgets/ssh_creds_dialog.dart';

/// The router's syslog. Tail rather than the whole file: it can run to megabytes after an uptime
/// of weeks, and every line above the last few hundred is scrollback nobody reads on a phone.
const String kRouterLogCommand = 'tail -n 500 /tmp/syslog.log 2>/dev/null';

class RouterLogScreen extends StatefulWidget {
  /// Injected by tests so the screen can be driven without a router.
  final Future<SSHClient> Function(String ip, String user, String pass)? testClientFactory;
  const RouterLogScreen({super.key, this.testClientFactory});

  @override
  State<RouterLogScreen> createState() => _RouterLogScreenState();
}

class _RouterLogScreenState extends State<RouterLogScreen> {
  late SessionController _c;
  final _scroll = ScrollController();

  String? _log;
  bool _loading = false, _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c = SessionScope.of(context);
    if (_started) return;
    _started = true;
    // Fetch on entry rather than making the user press REFRESH to see anything at all. Prompts for
    // credentials when the session has none, because this screen has no other purpose - unlike
    // ABOUT, where arriving is not a statement of intent to touch the router.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(prompt: true);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool prompt = false}) async {
    var ip = _c.routerIp.trim(), user = _c.sshUsername.trim(), pass = _c.sshPassword;
    if (ip.isEmpty || user.isEmpty || pass.isEmpty) {
      if (!prompt) return;
      final entered = await showDialog<(String, String, String)?>(
        context: context,
        builder: (_) => SshCredsDialog(initialIp: _c.routerIpPrefill, initialUser: user, initialPass: pass),
      );
      if (entered == null || !mounted) return;
      (ip, user, pass) = entered;
      _c
        ..routerIp = ip
        ..sshUsername = user
        ..sshPassword = pass;
    }

    setState(() => _loading = true);
    String? text;
    String? error;
    try {
      final client = _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      text = (await runRouterCommand(client, kRouterLogCommand, allowFailure: true)).stdout;
      _c.routerConnected = true;
      await _c.rememberRouterIp(ip);
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (text != null) _log = text.trimRight();
    });
    // The newest lines are at the BOTTOM of a syslog, and they are the ones anyone opening this
    // screen came for. Jumping after the frame that laid the text out, so the extent is known.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
    if (error != null && mounted) await AppErrors.system(context, _c, 'Could not read the router log: $error');
  }

  @override
  Widget build(BuildContext context) {
    final log = _log;
    return Column(
      children: [
        Expanded(
          child: Container(
            color: kBg,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: log == null
                ? Center(
                    child: _loading
                        ? const CircularProgressIndicator(color: kHighlight)
                        : const Text('No log read yet.', style: TextStyle(color: kMuted, fontSize: 13)),
                  )
                // Its own scroll view, not AppScaffold's: this one has to be driven to the bottom
                // after every refresh, which needs a controller on the scrollable holding the text.
                : Scrollbar(
                    controller: _scroll,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: SelectableText(
                        log.isEmpty ? '(the router log is empty)' : log,
                        key: const Key('router_log_text'),
                        style: const TextStyle(color: kText, fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('router_log_refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kHighlight,
                  side: const BorderSide(color: kHighlight),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _loading ? null : () => _load(prompt: true),
                child: _loading
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kHighlight))
                    : const Text('REFRESH'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                key: const Key('router_log_home'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kHighlight,
                  side: const BorderSide(color: kHighlight),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => navigateToDestination(context, _c, AppDestination.menu),
                child: const Text('HOME'),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
