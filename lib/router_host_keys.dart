// router_host_keys.dart - the router's SSH host key, recorded at first connect and checked after.
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
// Until build 478 the app accepted any host key: dartssh2 accepts every key when no
// `onVerifyHostKey` is given, so anything that answered on the router's address - an evil-twin
// Wi-Fi, a spoofed ARP entry - was sent the router's admin password (ID-308, claims audit #2).
// Now the first successful login records the key's SHA256 fingerprint, the way `ssh` fills
// known_hosts, and every connection after that is refused before any password is sent if the key
// is different. A reset or reflashed router has a new key; FORGET ROUTER IP clears the record.
//
// What is stored is a fingerprint - public, and the same line `ssh` prints - keyed by address and
// port. It is kept apart from router_prefs.dart, whose one-value rule is enforced by a test.
import 'dart:io';

import 'package:path_provider/path_provider.dart';

const String kRouterHostKeysFile = 'router_host_keys.txt';

/// A fingerprint as dartssh2 gives it: `SHA256:` and unpadded base64.
final RegExp _fingerprint = RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$');

/// An address:port as `splitHostPort` gives it, the same strictness as router_prefs.
final RegExp _target = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.\-]{0,62}:[0-9]{1,5}$');

/// The router answered with a different SSH key from the one recorded at first connect.
class RouterHostKeyChanged implements Exception {
  RouterHostKeyChanged(this.target, this.recorded, this.presented);

  final String target;
  final String recorded;
  final String presented;

  @override
  String toString() => 'The router at $target presented a different SSH key ($presented) from the one recorded when '
      'you first connected ($recorded). No password was sent. If you reset, reflashed or replaced the router, '
      'that is expected: tap FORGET ROUTER IP on the SETTINGS screen, then connect again. If you did none of '
      'those, something on your network may be posing as the router - do not connect until you know which.';
}

class RouterHostKeys {
  /// [directory] is a test seam, as in RouterPrefs: under `flutter test` the store is inert unless
  /// a test passes a directory, because the path_provider channel never answers there.
  RouterHostKeys({Future<Directory> Function()? directory})
      : _directory = directory ?? (Platform.environment.containsKey('FLUTTER_TEST') ? _inert : getApplicationSupportDirectory);

  static Future<Directory> _inert() async =>
      throw const FileSystemException('RouterHostKeys stores nothing under flutter test - pass `directory` to test it');

  final Future<Directory> Function() _directory;

  Future<File> _file() async => File('${(await _directory()).path}/$kRouterHostKeysFile');

  Future<Map<String, String>> _all() async {
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      return {
        for (final line in await f.readAsLines())
          if (line.split(' ').length == 2 && _target.hasMatch(line.split(' ')[0]) && _fingerprint.hasMatch(line.split(' ')[1]))
            line.split(' ')[0]: line.split(' ')[1],
      };
    } catch (_) {
      return {};
    }
  }

  /// The fingerprint recorded for [target] (`host:port`), or null if none is.
  Future<String?> recorded(String target) async => (await _all())[target];

  /// Records [fingerprint] for [target]. Returns false if it could not be stored.
  Future<bool> record(String target, String fingerprint) async {
    if (!_target.hasMatch(target) || !_fingerprint.hasMatch(fingerprint)) return false;
    try {
      final all = await _all()..[target] = fingerprint;
      await (await _file()).writeAsString(all.entries.map((e) => '${e.key} ${e.value}\n').join(), flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Forgets every recorded key. Wired to FORGET ROUTER IP.
  Future<void> forgetAll() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// The store the app uses. A global because `openSshClient` is called from several screens.
final RouterHostKeys routerHostKeys = RouterHostKeys();

/// Where `openSshClient` says a key could not be recorded: the app log, once the session controller
/// has set it. Global for the same reason as [routerHostKeys].
void Function(String message)? routerHostKeyWarning;
