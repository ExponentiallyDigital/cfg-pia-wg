// test/unit/widget_key_test.dart - the widget's restricted key, no device, no router (ID-376).
import 'dart:convert';

import 'package:cfg_pia_wg/widget_key.dart';
import 'package:dartssh2/dartssh2.dart' show SSHKeyPair;
import 'package:cfg_pia_wg/widget_status_service.dart' show kWidgetStatusCommand;
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart';

void main() {
  group('generateWidgetKeyPair', () {
    test('a 32-byte seed and a 32-byte public key', () {
      final pair = generateWidgetKeyPair();
      expect(pair.seed.length, 32);
      expect(pair.publicKeyBytes.length, 32);
    });

    test('the public key really is derived from the seed, not generated separately', () {
      final pair = generateWidgetKeyPair();
      final rebuilt = SigningKey(seed: pair.seed);
      expect(rebuilt.verifyKey.asTypedList, pair.publicKeyBytes);
    });

    test('two calls give two different keys', () {
      final a = generateWidgetKeyPair();
      final b = generateWidgetKeyPair();
      expect(a.seed, isNot(b.seed));
    });
  });

  group('openSshPublicKeyLine', () {
    // A fixed seed, so the encoded line is checked against a value computed by hand, not just
    // round-tripped through the same code that built it.
    final Uint8List fixedSeed = Uint8List.fromList(List.generate(32, (i) => i));
    final Uint8List fixedPublicKey = SigningKey(seed: fixedSeed).verifyKey.asTypedList;

    test('decodes back to exactly "ssh-ed25519" and the 32 public key bytes', () {
      final line = openSshPublicKeyLine(fixedPublicKey, restriction: '', comment: '');
      final b64 = line.trim().split(' ').firstWhere((p) => p != 'ssh-ed25519' && p.isNotEmpty);
      final wire = base64.decode(b64);

      // RFC 4253 5: a 4-byte big-endian length, then that many bytes - twice.
      final typeLen = ByteData.sublistView(wire, 0, 4).getUint32(0);
      final type = utf8.decode(wire.sublist(4, 4 + typeLen));
      final rest = wire.sublist(4 + typeLen);
      final keyLen = ByteData.sublistView(Uint8List.fromList(rest), 0, 4).getUint32(0);
      final key = rest.sublist(4, 4 + keyLen);

      expect(type, 'ssh-ed25519');
      expect(key, fixedPublicKey);
    });

    test('with no restriction and no comment, it is exactly "ssh-ed25519 <base64>"', () {
      final line = openSshPublicKeyLine(fixedPublicKey, restriction: '', comment: '');
      expect(line.split(' '), hasLength(2));
      expect(line.startsWith('ssh-ed25519 '), isTrue);
    });

    test('the restriction comes first, the comment last, exactly as authorized_keys expects', () {
      final line = openSshPublicKeyLine(fixedPublicKey, restriction: 'command="echo hi"', comment: 'cfg-pia-wg widget');
      expect(line, startsWith('command="echo hi" ssh-ed25519 '));
      expect(line, endsWith(' cfg-pia-wg widget'));
    });

    test('a key that is not 32 bytes is refused, not silently truncated or padded', () {
      expect(
        () => openSshPublicKeyLine(Uint8List(31), restriction: '', comment: ''),
        throwsArgumentError,
      );
      expect(
        () => openSshPublicKeyLine(Uint8List(33), restriction: '', comment: ''),
        throwsArgumentError,
      );
    });
  });

  group('openSshPrivateKeyPem', () {
    test('dartssh2 - the only reason this format exists - parses it back', () {
      final pair = generateWidgetKeyPair();
      final pem = openSshPrivateKeyPem(pair.seed, pair.publicKeyBytes, comment: kWidgetKeyComment);

      final parsed = SSHKeyPair.fromPem(pem);
      expect(parsed, hasLength(1));
      expect(parsed.single.type, 'ssh-ed25519');
    });

    test('the key it parses back is the same key, not just a valid one', () {
      final pair = generateWidgetKeyPair();
      final pem = openSshPrivateKeyPem(pair.seed, pair.publicKeyBytes);

      // The parsed pair's own public blob must equal the one we encode into authorized_keys, or
      // the router would be trusting a different key than the phone signs with.
      final encoded = SSHKeyPair.fromPem(pem).single.toPublicKey().encode();
      final expected = base64.decode(openSshPublicKeyLine(pair.publicKeyBytes, restriction: '', comment: '').split(' ')[1]);
      expect(encoded, expected);
    });

    test('it is a PEM: armoured, wrapped, and newline-terminated', () {
      final pair = generateWidgetKeyPair();
      final pem = openSshPrivateKeyPem(pair.seed, pair.publicKeyBytes);

      expect(pem, startsWith('-----BEGIN OPENSSH PRIVATE KEY-----\n'));
      expect(pem, endsWith('-----END OPENSSH PRIVATE KEY-----\n'));
      for (final line in pem.trim().split('\n').skip(1).take(1)) {
        expect(line.length, lessThanOrEqualTo(70));
      }
    });

    test('a seed or public key of the wrong length is refused', () {
      final pair = generateWidgetKeyPair();
      expect(() => openSshPrivateKeyPem(Uint8List(31), pair.publicKeyBytes), throwsArgumentError);
      expect(() => openSshPrivateKeyPem(pair.seed, Uint8List(31)), throwsArgumentError);
    });
  });

  group('widgetKeyRestriction', () {
    test('no special characters: the command passes straight through', () {
      expect(
        widgetKeyRestriction('echo hi'),
        'command="echo hi",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty',
      );
    });

    test('a double quote in the command is escaped, not left to break the field', () {
      expect(widgetKeyRestriction('echo "hi"'), contains(r'command="echo \"hi\""'));
    });

    test('a backslash is escaped before the quotes around it are, not after', () {
      // Escaping quotes first would turn \" into \\" wrongly; backslashes must go first.
      expect(widgetKeyRestriction(r'echo \"'), contains(r'echo \\\"'));
    });

    test('the real status command round-trips through the escaping with nothing left unescaped', () {
      final line = widgetKeyRestriction(kWidgetStatusCommand);
      // Between the opening command=" and its matching closing ", every quote must be \-escaped -
      // so there is no UNESCAPED quote before the restriction's own closing one.
      final body = line.substring('command="'.length, line.indexOf('",no-port-forwarding'));
      expect(RegExp(r'(?<!\\)"').hasMatch(body), isFalse);
    });
  });

  group('replaceWidgetKeyLine and removeWidgetKeyLine', () {
    const ours = 'command="echo hi",no-pty ssh-ed25519 AAAAOURS cfg-pia-wg-widget';
    const tablet = 'command="echo hi",no-pty ssh-ed25519 AAAATABLET cfg-pia-wg-widget';
    const theirs = 'ssh-ed25519 AAAAOTHER andrew@laptop';

    test('an empty sshd_authkeys gets just the one line', () {
      expect(replaceWidgetKeyLine('', ours), ours);
    });

    test("the user's own key, if any, is carried through untouched", () {
      expect(replaceWidgetKeyLine(theirs, ours), '$theirs\n$ours');
    });

    test('installing the same key twice leaves one copy, not two', () {
      final twice = replaceWidgetKeyLine(replaceWidgetKeyLine(theirs, ours), ours);
      expect(twice, '$theirs\n$ours');
    });

    // ID-398: one widget key per phone or tablet. Until build 498 a second device's GENERATE took
    // the first device's line out, because both end in the same comment.
    test("another device's widget key stays when this one installs", () {
      expect(replaceWidgetKeyLine('$theirs\n$tablet', ours), '$theirs\n$tablet\n$ours');
    });

    test("removeWidgetKeyLine takes only this device's line out, leaving the rest", () {
      expect(removeWidgetKeyLine('$theirs\n$tablet\n$ours', 'AAAAOURS'), '$theirs\n$tablet');
    });

    test('removing when there is nothing of ours is a harmless no-op', () {
      expect(removeWidgetKeyLine('$theirs\n$tablet', 'AAAAOURS'), '$theirs\n$tablet');
    });

    test('sshKeyBlob reads the key with or without options before it, and widgetKeyBlob matches the line', () {
      expect(sshKeyBlob(ours), 'AAAAOURS');
      expect(sshKeyBlob(theirs), 'AAAAOTHER');
      expect(sshKeyBlob('ssh-rsa AAAAB3Nza andrew'), isNull, reason: 'only ed25519 lines are ours to read');
      final pair = generateWidgetKeyPair();
      final line = openSshPublicKeyLine(pair.publicKeyBytes, restriction: 'command="x",no-pty', comment: kWidgetKeyComment);
      expect(sshKeyBlob(line), widgetKeyBlob(pair.publicKeyBytes));
    });

    test('blank lines in the existing value are dropped, not carried through as empty entries', () {
      expect(replaceWidgetKeyLine('\n$theirs\n\n', ours), '$theirs\n$ours');
    });
  });

  group('WidgetKeyStore', () {
    late Map<String, String> backing;

    setUp(() {
      backing = {};
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(backing);
    });

    test('nothing stored yet reads as null and "does not exist"', () async {
      final store = WidgetKeyStore();
      expect(await store.read(), isNull);
      expect(await store.exists(), isFalse);
    });

    test('a saved seed reads back exactly, and exists() agrees', () async {
      final store = WidgetKeyStore();
      final seed = Uint8List.fromList(List.generate(32, (i) => 31 - i));
      await store.save(seed);

      expect(await store.exists(), isTrue);
      expect(await store.read(), seed);
    });

    test('remove() clears it, and read() goes back to null', () async {
      final store = WidgetKeyStore();
      await store.save(Uint8List(32));
      await store.remove();

      expect(await store.exists(), isFalse);
      expect(await store.read(), isNull);
    });

    test('saving a second time replaces the first, not appends', () async {
      final store = WidgetKeyStore();
      await store.save(Uint8List.fromList(List.filled(32, 1)));
      await store.save(Uint8List.fromList(List.filled(32, 2)));

      expect(await store.read(), Uint8List.fromList(List.filled(32, 2)));
      expect(backing.length, 1);
    });

    test('nothing but the widget key seed and its login is ever written to secure storage', () async {
      final store = WidgetKeyStore();
      await store.save(Uint8List(32));
      await store.saveLogin('admin');

      // Named one by one on purpose: a third key appearing here is a new thing kept on the user's
      // phone, which is a decision, not a detail - see WidgetKeyStore's header.
      expect(backing.keys.toSet(), {WidgetKeyStore.kStorageKey, WidgetKeyStore.kLoginKey});
    });

    test('the login reads back, and remove() takes it with the key rather than orphaning it', () async {
      final store = WidgetKeyStore();
      await store.save(Uint8List(32));
      await store.saveLogin('root-admin');
      expect(await store.readLogin(), 'root-admin');

      await store.remove();
      expect(await store.readLogin(), isNull);
      expect(await store.read(), isNull);
      expect(backing, isEmpty);
    });
  });
}
