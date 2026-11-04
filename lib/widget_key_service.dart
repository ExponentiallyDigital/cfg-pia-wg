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
// pure and tested there. Each device touches only its own line, found by its key (ID-398). This file only reads the router's current value and writes the result.

import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'firmware.dart' show kRouterAppDir;
import 'router_command.dart';
import 'router_watchdog.dart' show heredocWriteCommands;
import 'widget_key.dart';
import 'widget_status_service.dart' show kWidgetKeyCommand, kWidgetReadScript, kWidgetReadScriptPath;

/// A failure this service found by reading the router back, already in plain English (ID-407).
class WidgetKeyRouterException implements Exception {
  const WidgetKeyRouterException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WidgetKeyRouterService {
  WidgetKeyRouterService(this.client, {this.onLog});

  final SSHClient client;
  final void Function(String message, {bool isError, bool isSuccess, bool isWarning})? onLog;

  Future<String> _read(String cmd) async => (await runRouterCommand(client, cmd, allowFailure: true, onLog: onLog)).stdout;
  Future<void> _run(String cmd) async => runRouterCommand(client, cmd, onLog: onLog);

  /// Installs [publicKeyLine] (from `widgetKeyRestriction` and `openSshPublicKeyLine`, with
  /// [kWidgetKeyComment] as its comment), replacing an earlier copy of the same key, and this
  /// phone's previous key, [replacing], if it had one. Other devices' widget keys stay (ID-398).
  /// Throws a plain-English reason if the router doesn't hold the new key afterwards (ID-407).
  Future<void> install(String publicKeyLine, {Uint8List? replacing}) async {
    // The script first, so the key never points at a read that isn't there (ID-467).
    await writeScript();
    final current = await _read(_kReadAuthKeys);
    var next = replaceWidgetKeyLine(current, publicKeyLine);
    if (replacing != null) next = removeWidgetKeyLine(next, widgetKeyBlob(replacing));
    await _write(next);
    final blob = sshKeyBlob(publicKeyLine)!;
    final (nv, live) = await _readBack();
    if (!nv.contains(blob) || !live.contains(blob)) {
      throw const WidgetKeyRouterException("The router didn't keep the new key, so nothing was saved on this phone. "
          'Try again; if it fails again, use REMOVE first.');
    }
  }

  /// Takes every widget key off the router - this phone's and every other phone's or tablet's,
  /// leftovers from a cleared or reinstalled app among them, which the router can't tell from a key
  /// still in use (ID-407). The user's own keys stay. Returns how many were taken off; throws a
  /// plain-English reason if any is still there afterwards.
  Future<int> removeAll() async {
    final current = await _read(_kReadAuthKeys);
    final next = removeAllWidgetKeyLines(current);
    final count = widgetKeyLineCount(current);
    if (count > 0) await _write(next);
    final (nv, live) = await _readBack();
    if (widgetKeyLineCount(nv) > 0 || widgetKeyLineCount(live) > 0) {
      throw const WidgetKeyRouterException("The router still holds a widget key after REMOVE, so this phone's key was kept. Try again.");
    }
    return count;
  }

  /// The widget's read script, as this app version has it, in the app's folder (ID-467). Throws a
  /// plain-English reason if the router doesn't hold it afterwards.
  Future<void> writeScript() async {
    await _run('mkdir -p $kRouterAppDir');
    for (final cmd in heredocWriteCommands(kWidgetReadScriptPath, kWidgetReadScript)) {
      await _run(cmd);
    }
    await _run('chmod 755 $kWidgetReadScriptPath');
    if (!await _scriptCurrent()) {
      throw const WidgetKeyRouterException("The router didn't keep the widget's read script, so nothing was saved on this phone. Try again.");
    }
  }

  Future<bool> _scriptCurrent() async => (await _read('cat $kWidgetReadScriptPath 2>/dev/null')) == kWidgetReadScript.trim();

  /// Run on every connection, paid or not (ID-467): [ownKey]'s line, this phone's, moves to the short
  /// form if it's still the long one, and the read script is put back as this version has it wherever
  /// a widget key uses it. Other phones' lines are left as they are: each moves when its own phone
  /// next connects. Returns what changed, for the app log; empty when nothing needed doing.
  Future<List<String>> keepCurrent({Uint8List? ownKey}) async {
    final current = await _read(_kReadAuthKeys);
    var next = current;
    if (ownKey != null) {
      final blob = widgetKeyBlob(ownKey);
      final own = current.split('\n').where((l) => sshKeyBlob(l) == blob);
      if (own.isNotEmpty && !own.first.contains(kWidgetReadScriptPath)) next = replaceWidgetKeyLine(current, widgetKeyLine(ownKey));
    }
    final changed = <String>[];
    if (next.contains(kWidgetReadScriptPath) && !await _scriptCurrent()) {
      await writeScript();
      changed.add("the home screen widget's read script");
    }
    if (next != current) {
      await _write(next);
      changed.add("this phone's home screen widget key, now its short form");
    }
    return changed;
  }

  /// `sshd_authkeys` and the live file, as the router has them now.
  Future<(String, String)> _readBack() async {
    final nv = await _read(_kReadAuthKeys);
    final live = await _read('cat ~/.ssh/authorized_keys 2>/dev/null');
    return (nv, live);
  }

  /// `nvram set` so it survives a reboot, `nvram commit` so it survives a power loss before the
  /// next one, and the live file so Dropbear has it immediately - see this file's header.
  ///
  /// In pieces (ID-407): the value goes to a file in the app's own heredoc writes, each well under
  /// Dropbear's 9000-byte limit on one command, then into NVRAM and the live file from there. Sent
  /// as one command, holding the value twice, it failed with 5 widget keys on the router (9870
  /// bytes; each line is 749) and Dropbear dropped the connection. A heredoc with a quoted
  /// delimiter carries the `command="…"`'s quotes as they are.
  Future<void> _write(String value) async {
    for (final cmd in heredocWriteCommands(kAuthKeysUploadPath, value)) {
      await _run('umask 077; $cmd');
    }
    await _run('nvram set sshd_authkeys="\$(cat $kAuthKeysUploadPath)"; nvram commit; '
        'mkdir -p ~/.ssh; chmod 700 ~/.ssh; '
        // A final newline, so a key added after ours the usual way (`echo key >> ...`) starts a line
        // of its own rather than landing in our line's comment (ID-389).
        "printf '%s\\n' \"\$(cat $kAuthKeysUploadPath)\" > ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; "
        'rm -f $kAuthKeysUploadPath');
  }
}

/// This phone's widget key line for [publicKeyBytes]: the read script as its only command (ID-467),
/// with the four flags measured to hold, and the comment every widget line shares.
String widgetKeyLine(Uint8List publicKeyBytes) =>
    openSshPublicKeyLine(publicKeyBytes, restriction: widgetKeyRestriction(kWidgetKeyCommand), comment: kWidgetKeyComment);

/// The router's key list, as NVRAM keeps it.
const String _kReadAuthKeys = 'nvram get sshd_authkeys';

/// Where the key list is put together on the router before it goes into NVRAM (ID-407). In /tmp,
/// RAM, gone at the next reboot; removed straight after the write anyway.
const String kAuthKeysUploadPath = '/tmp/cfg-pia-wg-authkeys';
