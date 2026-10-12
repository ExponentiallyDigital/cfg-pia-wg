// widget_key.dart - the widget's own restricted SSH key: made, encoded, kept, removed (ID-376).
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
// The first credential this app has ever kept on the phone - see router_prefs.dart's header for
// why nothing else does. It earns the exception the same way the router address did: it is not a
// login. Measured on stock, 2026-10-12 (BACKLOG ID-376): a key carrying `command="…"`,
// `no-port-forwarding`, `no-agent-forwarding`, `no-X11-forwarding` and `no-pty` can run only its
// own command, can't reach another host through the router, and - per Andrew's own measurement,
// since Claude was not able to build the test that settles it on hardware - can't make the router
// listen for a forwarded connection either. A stolen phone can read the router's status and do
// nothing else.
//
// This file does not connect anywhere. [generateWidgetKeyPair] and [openSshPublicKeyLine] are
// pure - no I/O, no randomness in the second one - so the format can be tested without a device.
// [WidgetKeyStore] is the one piece of I/O, and it is narrow by construction: one key, in Android's
// Keystore-backed secure storage, nothing else ever written there (see widget_key_test.dart's "no
// other key" test, the same discipline no_secret_prefs_test.dart applies to router_prefs.dart).
//
// Installing the key on the router - the `command="…"` restriction's actual value, and how it
// survives a reboot - is ID-376's next slice. Nothing here assumes what that command will be.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/ed25519.dart';

/// An Ed25519 key pair, held only in memory - encode it with [openSshPublicKeyLine] or hand the
/// seed to [WidgetKeyStore.save] before letting it go out of scope.
class WidgetKeyPair {
  const WidgetKeyPair({required this.seed, required this.publicKeyBytes});

  /// The 32-byte private seed - the only secret here. Ed25519's public key is derived from it,
  /// so nothing else needs to be stored.
  final Uint8List seed;

  /// The 32-byte public key, SSH wire format's raw payload for `ssh-ed25519`.
  final Uint8List publicKeyBytes;
}

/// A fresh key pair, from the platform's random source via `pinenacl` (already in this app's
/// dependency tree through `dartssh2`, which authenticates with keys but cannot generate one).
WidgetKeyPair generateWidgetKeyPair() {
  final signing = SigningKey.generate();
  return WidgetKeyPair(
    seed: Uint8List.fromList(signing.seed.asTypedList),
    publicKeyBytes: Uint8List.fromList(signing.verifyKey.asTypedList),
  );
}

/// The pair a stored [seed] belongs to. Only the seed is kept ([WidgetKeyStore]); Ed25519 derives
/// the public half from it, so this is how the background refresh rebuilds what it needs to sign
/// with without a second thing to store or keep in step.
WidgetKeyPair widgetKeyPairFromSeed(Uint8List seed) {
  if (seed.length != 32) {
    throw ArgumentError.value(seed.length, 'seed.length', 'ed25519 seeds are exactly 32 bytes');
  }
  final signing = SigningKey(seed: seed);
  return WidgetKeyPair(
    seed: Uint8List.fromList(signing.seed.asTypedList),
    publicKeyBytes: Uint8List.fromList(signing.verifyKey.asTypedList),
  );
}

/// SSH's own length-prefixed string encoding (RFC 4253 section 5) - `ssh-ed25519`'s wire format is
/// exactly two of these, the algorithm name then the raw public key, nothing else.
Uint8List _sshString(List<int> bytes) {
  final out = BytesBuilder();
  final len = ByteData(4)..setUint32(0, bytes.length);
  out.add(len.buffer.asUint8List());
  out.add(bytes);
  return out.toBytes();
}

/// An `authorized_keys` line for [publicKeyBytes], with [restriction] (the `command="…",no-...`
/// prefix that makes this a status-only key, not yet decided - see this file's header) and
/// [comment] (the trailing field `ssh-keygen` also writes, purely informational to anything
/// reading the file by eye).
///
/// No randomness, no platform call - [publicKeyBytes] must be exactly 32 bytes, Ed25519's public
/// key length; anything else is almost certainly a caller passing the seed by mistake, which this
/// refuses rather than silently writing a line nothing can ever use to authenticate.
String openSshPublicKeyLine(Uint8List publicKeyBytes, {required String restriction, required String comment}) {
  if (publicKeyBytes.length != 32) {
    throw ArgumentError.value(publicKeyBytes.length, 'publicKeyBytes.length', 'ed25519 public keys are exactly 32 bytes');
  }
  final wire = _sshString(utf8.encode('ssh-ed25519')) + _sshString(publicKeyBytes);
  final b64 = base64.encode(wire);
  final head = restriction.isEmpty ? '' : '$restriction ';
  final tail = comment.isEmpty ? '' : ' $comment';
  return '$head' 'ssh-ed25519 $b64$tail';
}

/// A 32-bit big-endian integer, the other primitive OpenSSH's own key format is built from.
Uint8List _u32(int value) => (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

/// [seed] and [publicKeyBytes] as an unencrypted `OPENSSH PRIVATE KEY` PEM - the one format
/// `dartssh2` can authenticate from (`SSHKeyPair.fromPem`), which is why this exists: the seed is
/// what gets stored, and this is what turns it back into something that can log in.
///
/// `openssh-key-v1` plainly: the magic, cipher and KDF both `none`, one key, the public blob, then
/// a private section carrying the same public key again and the 64-byte `seed || public` pair
/// Ed25519 implementations expect, padded to a multiple of 8. No passphrase: the seed was already
/// behind Android's Keystore, and a passphrase the app would have to keep beside it protects
/// nothing.
String openSshPrivateKeyPem(Uint8List seed, Uint8List publicKeyBytes, {String comment = ''}) {
  if (seed.length != 32) {
    throw ArgumentError.value(seed.length, 'seed.length', 'ed25519 seeds are exactly 32 bytes');
  }
  if (publicKeyBytes.length != 32) {
    throw ArgumentError.value(publicKeyBytes.length, 'publicKeyBytes.length', 'ed25519 public keys are exactly 32 bytes');
  }
  final algorithm = utf8.encode('ssh-ed25519');
  final publicBlob = Uint8List.fromList(_sshString(algorithm) + _sshString(publicKeyBytes));

  // The two check integers are compared after decryption to tell a wrong passphrase from a right
  // one. Nothing here is encrypted, so any value does, as long as it is written twice.
  const check = 0x63666777;
  final private = BytesBuilder()
    ..add(_u32(check))
    ..add(_u32(check))
    ..add(_sshString(algorithm))
    ..add(_sshString(publicKeyBytes))
    ..add(_sshString([...seed, ...publicKeyBytes]))
    ..add(_sshString(utf8.encode(comment)));
  final body = private.toBytes();
  // Padded 1, 2, 3 … to the "none" cipher's block size of 8, as OpenSSH writes it.
  final padding = [for (var i = 1; i <= (8 - body.length % 8) % 8; i++) i];

  final out = BytesBuilder()
    ..add(utf8.encode('openssh-key-v1'))
    ..addByte(0)
    ..add(_sshString(utf8.encode('none')))
    ..add(_sshString(utf8.encode('none')))
    ..add(_sshString(const []))
    ..add(_u32(1))
    ..add(_sshString(publicBlob))
    ..add(_sshString([...body, ...padding]));

  final base64Text = base64.encode(out.toBytes());
  final wrapped = [
    for (var i = 0; i < base64Text.length; i += 70)
      base64Text.substring(i, i + 70 > base64Text.length ? base64Text.length : i + 70),
  ];
  return '-----BEGIN OPENSSH PRIVATE KEY-----\n${wrapped.join('\n')}\n-----END OPENSSH PRIVATE KEY-----\n';
}

/// The full `authorized_keys` restriction for the widget's key around [statusCommand] (expected to
/// be [kWidgetStatusCommand] from widget_status_service.dart, not imported here so this file stays
/// router-agnostic): `command="…"`, quotes and backslashes escaped per the file's own format, plus
/// the four flags measured to hold on stock, 2026-10-12 (BACKLOG ID-376) - another command refused,
/// reaching another host through the router refused, and (per Andrew's own measurement, since
/// Claude could not build the check that settles it on hardware) making the router listen for a
/// forwarded connection refused too.
String widgetKeyRestriction(String statusCommand) {
  final escaped = statusCommand.replaceAll('\\', r'\\').replaceAll('"', r'\"');
  return 'command="$escaped",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty';
}

/// The comment every widget key line ends with - how [replaceWidgetKeyLine] and
/// [removeWidgetKeyLine] find a previous entry of ours among lines that may carry options or
/// comments this file never wrote and must not try to parse. Pass this, not a free-form comment,
/// as [openSshPublicKeyLine]'s `comment` for the line that is actually installed.
const String kWidgetKeyComment = 'cfg-pia-wg-widget';

/// `sshd_authkeys`'s existing value (or the live file's - they matched line for line when
/// measured, 2026-10-12, BACKLOG ID-376) with any previous widget key line removed and [newLine]
/// appended, so installing twice replaces rather than duplicates. Every other line - anything not
/// ending in [kWidgetKeyComment] - is carried through untouched, in its original order: this is
/// not an allow list the app owns, it is the router's whole account, the user's own real key (if
/// any) among it.
///
/// Measured newline-joined, not the `>` this project's other NVRAM lists use - a different ASUS
/// subsystem, not assumed to share a convention with filter_lwlist or vpnc_clientlist.
String replaceWidgetKeyLine(String current, String newLine) =>
    [..._linesWithoutOurs(current), newLine].join('\n');

/// As [replaceWidgetKeyLine], but takes the widget's line out and puts nothing back - used when
/// the key is turned off. Harmless, and a no-op, if none is present.
String removeWidgetKeyLine(String current) => _linesWithoutOurs(current).join('\n');

List<String> _linesWithoutOurs(String current) =>
    current.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty && !l.endsWith(kWidgetKeyComment)).toList();

/// Keeps exactly two things, both Keystore-backed: the widget key's seed, and the router login
/// name that key was installed under. Nothing else may ever be written through this - see
/// widget_key_test.dart's "nothing but" test, which names both and would fail on a third.
///
/// **Why the login name is here at all** (ID-376, 2026-10-12): SSH cannot connect without a
/// username, so a key with no name beside it can never be used - storing one is implied by the
/// decision to have a background refresh at all. It is NOT a credential on its own: it cannot log
/// in without the key, and the key cannot log in without it. It deliberately does not go in
/// `router_prefs.dart`, which stays the router address and nothing else, for the reasons its own
/// header gives. README, SECURITY.md and the privacy policy have to say both are kept.
class WidgetKeyStore {
  WidgetKeyStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// The private seed. Deliberately the only secret here - Ed25519 derives the public half.
  static const String kStorageKey = 'cfg_pia_wg_widget_key_seed';

  /// The router login the key was installed under, so the background refresh can use it. Not a
  /// secret by itself; see this class's header.
  static const String kLoginKey = 'cfg_pia_wg_widget_key_login';

  Future<void> save(Uint8List seed) async => _storage.write(key: kStorageKey, value: base64.encode(seed));

  /// The stored seed, or null if none has been generated (or it was removed).
  Future<Uint8List?> read() async {
    final encoded = await _storage.read(key: kStorageKey);
    if (encoded == null) return null;
    return base64.decode(encoded);
  }

  Future<bool> exists() async => (await _storage.containsKey(key: kStorageKey));

  Future<void> saveLogin(String user) async => _storage.write(key: kLoginKey, value: user);

  Future<String?> readLogin() async => _storage.read(key: kLoginKey);

  /// Takes the key AND the login off the phone - never one without the other, since neither is
  /// any use alone. The router side - removing the matching line from `sshd_authkeys` - is not
  /// this file's job; it needs a router connection, which this file deliberately never makes.
  Future<void> remove() async {
    await _storage.delete(key: kStorageKey);
    await _storage.delete(key: kLoginKey);
  }
}
