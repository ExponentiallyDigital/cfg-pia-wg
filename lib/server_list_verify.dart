// server_list_verify.dart - PIA's server list key, and the check of a list's signature against a key
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
// The part of server_list_signature.dart that needs nothing from Flutter, so a plain `dart run` tool
// can use it too: tool/check_pia_server_list.dart compares this key with the one PIA publishes and
// checks PIA's live list with it every day (ID-409). The app reaches it through
// server_list_signature.dart, which adds the key a test can swap and the stored fallback list.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/api.dart' show PublicKeyParameter;
import 'package:pointycastle/asymmetric/api.dart' show RSAPublicKey, RSASignature;
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/signers/rsa_signer.dart';

/// PIA's public key for its server list, copied byte for byte from PIA's own desktop client:
/// `Environment::defaultRegionsListPublicKey` in `daemon/src/environment.cpp` of `pia-foss/desktop`
/// (GPL-3.0), which checks serverlist.piaservers.net with it. 2048-bit RSA; the list is signed with
/// SHA-256, PKCS#1 v1.5 (`verifySignature` in `common/src/openssl.cpp`). The watchdog carries the
/// same text.
const String kPiaServerListKeyPem = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzLYHwX5Ug/oUObZ5eH5P
rEwmfj4E/YEfSKLgFSsyRGGsVmmjiXBmSbX2s3xbj/ofuvYtkMkP/VPFHy9E/8ox
Y+cRjPzydxz46LPY7jpEw1NHZjOyTeUero5e1nkLhiQqO/cMVYmUnuVcuFfZyZvc
8Apx5fBrIp2oWpF/G9tpUZfUUJaaHiXDtuYP8o8VhYtyjuUu3h7rkQFoMxvuoOFH
6nkc0VQmBsHvCfq4T9v8gyiBtQRy543leapTBMT34mxVIQ4ReGLPVit/6sNLoGLb
gSnGe9Bk/a5V/5vlqeemWF0hgoRtUxMtU1hFbe7e8tSq1j+mu0SHMyKHiHd+OsmU
IQIDAQAB
-----END PUBLIC KEY-----''';

/// The JSON of a server list download, or null when the download doesn't carry a valid signature
/// by [keyPem]. See verifiedServerListJson in server_list_signature.dart for how the download is
/// split.
Uint8List? verifySignedServerList(List<int> body, String keyPem) {
  if (body.isEmpty || body.first != 0x7b) return null; // '{'
  final end = body.lastIndexOf(0x7d); // '}'
  if (end < 0) return null;
  final json = Uint8List.fromList(body.sublist(0, end + 1));
  final Uint8List signature;
  try {
    signature = base64Decode(ascii.decode(body.sublist(end + 1)).replaceAll(RegExp(r'\s'), ''));
  } on FormatException {
    return null;
  }
  if (signature.isEmpty) return null;
  try {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(false, PublicKeyParameter<RSAPublicKey>(rsaPublicKeyFromPem(keyPem)));
    return signer.verifySignature(json, RSASignature(signature)) ? json : null;
  } catch (_) {
    // A signature of the wrong length, or one that doesn't decode to a PKCS#1 block, is a failed
    // check, not an error to report.
    return null;
  }
}

/// The RSA key in a PEM `PUBLIC KEY` block (an X.509 SubjectPublicKeyInfo). Throws [FormatException]
/// for anything else.
RSAPublicKey rsaPublicKeyFromPem(String pem) {
  final b64 = pem.split('\n').where((l) => !l.startsWith('-----')).join().trim();
  final spki = _Der(base64Decode(b64))..enter(0x30);
  final algorithm = spki.take(0x30);
  // 1.2.840.113549.1.1.1, rsaEncryption, then NULL.
  const rsa = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00];
  if (!_sameBytes(algorithm, rsa)) throw const FormatException('not an RSA public key');
  final bits = spki.take(0x03);
  if (bits.isEmpty || bits.first != 0) throw const FormatException('bad key bit string');
  final key = _Der(bits.sublist(1))..enter(0x30);
  final modulus = _unsigned(key.take(0x02)), exponent = _unsigned(key.take(0x02));
  return RSAPublicKey(modulus, exponent);
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

BigInt _unsigned(List<int> bytes) =>
    bytes.fold(BigInt.zero, (n, b) => (n << 8) | BigInt.from(b));

/// Just enough DER to read a public key: a tag, a length, the contents.
class _Der {
  _Der(this._b);
  final List<int> _b;
  int _p = 0;

  int _header(int tag) {
    if (_p + 2 > _b.length || _b[_p++] != tag) throw const FormatException('unexpected DER');
    var len = _b[_p++];
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      if (n == 0 || n > 3 || _p + n > _b.length) throw const FormatException('bad DER length');
      len = 0;
      for (var i = 0; i < n; i++) {
        len = (len << 8) | _b[_p++];
      }
    }
    if (_p + len > _b.length) throw const FormatException('DER runs past its end');
    return len;
  }

  /// Steps into a constructed element, leaving the position at its first child.
  void enter(int tag) => _header(tag);

  /// Reads a whole element and returns its contents.
  List<int> take(int tag) {
    final len = _header(tag);
    final v = _b.sublist(_p, _p + len);
    _p += len;
    return v;
  }
}
