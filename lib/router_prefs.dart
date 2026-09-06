// router_prefs.dart - the one value this app keeps on device storage: the router's LAN address.
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
// Everything else the app holds is volatile and wiped on exit - see session_controller.dart. This
// is the deliberate exception, and it is narrow on purpose:
//
//   - The router's LAN address is not a credential. It is a private-range address that identifies
//     nothing outside the user's own network, and it is the single value that has to be retyped
//     every session because the shipped default (the ASUS factory 192.168.50.1) is rarely right.
//   - It is written only after a connect has SUCCEEDED, so a typo or a wrong guess never sticks.
//     Same rule the autofill save prompt follows.
//   - Nothing may be added to this file. A username or password here would turn a convenience into
//     a credential store, which is exactly what the app promises not to be. `no_secret_prefs_test`
//     fails the build if this file learns to write anything else.
//   - `android:allowBackup="false"` keeps it off Google Drive, so it never leaves the handset.
//
// The user can clear it at any time - "FORGET ROUTER IP" on the About screen.
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Filename under the app-support directory. Not the documents directory: this is app state the
/// user never opens, not a document, and on Android documents is the more exposed of the two.
const String kRouterPrefsFile = 'router.txt';

/// A LAN address or hostname the app is willing to remember. Deliberately strict - the file is
/// hand-editable on a rooted device, and a value read from it goes straight into a form field and
/// then into an SSH connect, so anything shell-unsafe or absurdly long is dropped rather than used.
final RegExp _acceptable = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.\-]{0,62}$');

/// Reads and writes the remembered router address. Construct once; [SessionController] owns it.
class RouterPrefs {
  /// [directory] is a test seam - tests that exercise storage pass a temp dir.
  ///
  /// Left null, the store resolves the real app-support directory - EXCEPT under `flutter test`,
  /// where it is inert. Two reasons, and the first is not cosmetic: the path_provider channel has
  /// no handler in a test binding and the reply never arrives, so an `await` on it hangs forever -
  /// which shows up as a connect spinner that never clears and a `pumpAndSettle timed out` with no
  /// exception to explain it. The second is that a test has no business writing to the developer
  /// machine real app data. A test that wants storage passes [directory] and gets it.
  RouterPrefs({Future<Directory> Function()? directory})
      : _directory = directory ?? (Platform.environment.containsKey('FLUTTER_TEST') ? _inert : getApplicationSupportDirectory);

  static Future<Directory> _inert() async =>
      throw const FileSystemException('RouterPrefs stores nothing under flutter test - pass `directory` to test it');

  final Future<Directory> Function() _directory;

  Future<File> _file() async => File('${(await _directory()).path}/$kRouterPrefsFile');

  /// The remembered address, or '' if there is none or the stored value is not acceptable.
  /// Never throws: a missing or unreadable file simply means "nothing remembered".
  Future<String> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return '';
      final value = (await f.readAsString()).trim();
      return _acceptable.hasMatch(value) ? value : '';
    } catch (_) {
      return '';
    }
  }

  /// Stores [ip] if it is acceptable. Call this ONLY after a connect has succeeded.
  /// Returns the value now remembered, or '' if the write was rejected or failed.
  Future<String> remember(String ip) async {
    final value = ip.trim();
    if (!_acceptable.hasMatch(value)) return '';
    try {
      await (await _file()).writeAsString(value, flush: true);
      return value;
    } catch (_) {
      return '';
    }
  }

  /// Deletes the file. Safe to call when there is nothing stored.
  Future<void> forget() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Nothing to report - the caller's contract is "it is not remembered any more", and a
      // delete that failed because the file was already gone satisfies that.
    }
  }
}
