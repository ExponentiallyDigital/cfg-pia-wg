// widget_key_service.dart - installs and removes the widget's key on the router (ID-376).
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
// Measured on stock, 2026-10-12 (BACKLOG ID-376): `sshd_authkeys` (NVRAM) and `~/.ssh/
// authorized_keys` (the live file Dropbear reads) matched line for line, newline-joined, both
// before and after the router's own web interface added two keys through Authorized Keys. So this
// writes both, rather than one and hoping something else pushes it to the other - the same
// discipline the guard applies to its own two layers (lib/fail_closed_guard.dart): nothing here is
// left for some other code path to finish.
//
// All the deciding - what the new value should be, whether a previous widget line gets replaced
// or just removed - is in widget_key.dart's [replaceWidgetKeyLine] and [removeWidgetKeyLine],
// pure and tested there. This file only reads the router's current value and writes the result.

import 'package:dartssh2/dartssh2.dart';

import 'router_command.dart';
import 'router_watchdog.dart' show shellSingleQuote;
import 'widget_key.dart';

class WidgetKeyRouterService {
  WidgetKeyRouterService(this.client, {this.onLog});

  final SSHClient client;
  final void Function(String message, {bool isError, bool isSuccess, bool isWarning})? onLog;

  Future<String> _read(String cmd) async => (await runRouterCommand(client, cmd, allowFailure: true, onLog: onLog)).stdout;
  Future<void> _run(String cmd) async => runRouterCommand(client, cmd, onLog: onLog);

  /// Installs [publicKeyLine] (from `widgetKeyRestriction` and `openSshPublicKeyLine`, with
  /// [kWidgetKeyComment] as its comment), replacing a previous widget key line if there is one.
  Future<void> install(String publicKeyLine) async {
    final current = await _read('nvram get sshd_authkeys');
    await _write(replaceWidgetKeyLine(current, publicKeyLine));
  }

  /// Takes the widget's key off the router. A no-op, not an error, if none is installed -
  /// SETTINGS calls this both when the user asks and whenever the feature is turned off.
  Future<void> remove() async {
    final current = await _read('nvram get sshd_authkeys');
    final next = removeWidgetKeyLine(current);
    if (next == current) return;
    await _write(next);
  }

  /// `nvram set` so it survives a reboot, `nvram commit` so it survives a power loss before the
  /// next one, and the live file so Dropbear has it immediately - see this file's header.
  /// [shellSingleQuote] handles [value]'s embedded newlines and any quote inside the widget's own
  /// `command="…"` the same way it already handles everything else sent over this app's SSH
  /// connections; a literal newline inside single quotes is ordinary shell text, not a command
  /// separator.
  Future<void> _write(String value) async {
    final quoted = shellSingleQuote(value);
    await _run('nvram set sshd_authkeys=$quoted; nvram commit; '
        'mkdir -p ~/.ssh; chmod 700 ~/.ssh; '
        // A final newline, so a key added after ours the usual way (`echo key >> ...`) starts a line
        // of its own rather than landing in our line's comment (ID-389).
        "printf '%s\\n' $quoted > ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys");
  }
}
