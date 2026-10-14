// A key of the tests' own for signing PIA server lists (ID-325).
//
// The app only uses a list that carries PIA's signature, and PIA's private key is PIA's, so a test
// that wants a list of its own making signs it with this key and points the app's check at it. A
// test that wants PIA's real key uses test/fixtures/pia_servers_v6_2026-10-14.txt, a list exactly as
// PIA sent it. This key protects nothing: it was made for these tests and is used nowhere else.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cfg_pia_wg/server_list_signature.dart';
import 'package:pointycastle/api.dart' show PrivateKeyParameter;
import 'package:pointycastle/asymmetric/api.dart' show RSAPrivateKey;
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/signers/rsa_signer.dart';

/// The real list, as PIA signed it on 2026-10-14.
const String kRealServerListFixture = 'test/fixtures/pia_servers_v6_2026-10-14.txt';

const String kTestServerListKeyPem = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzXzQahtot5SeR/cmTkEW
Zl+/E5bVshwoXM6avaMSuwQTBJNkDXrR0DgjkPVsFu80q6B7xSV6VwnhlTrNUAGf
iyg4zmPL5RCwRUSnHvvew2vw8cKLAm5druoxRGH3c0IG3X0h6XRfmfE5EL+u9P2A
kXsZ3Kp7q+Hmq0q8Opt99r8A5BFxzBhPmsTqq/7cXzOFuJxPQEyemKZY+lwdNYI6
VWJJk7/GIVPAD3y8clNvB6wk1FkfX9HZ8CkkAd7/7uIHFhjnOja9G+4cz+fiH+iE
rhDPHm2cVWgyR/GgZrO9VtQE85LMf4abV55bR62YdDiizTu6pZ6FcAglGYTtwok9
8QIDAQAB
-----END PUBLIC KEY-----''';

final _n = BigInt.parse(
    'cd7cd06a1b68b7949e47f7264e4116665fbf1396d5b21c285cce9abda312bb04130493640d7ad1d0382390f56c16ef34aba07bc5257a5709'
    'e1953acd50019f8b2838ce63cbe510b04544a71efbdec36bf0f1c28b026e5daeea314461f7734206dd7d21e9745f99f13910bfaef4fd8091'
    '7b19dcaa7babe1e6ab4abc3a9b7df6bf00e41171cc184f9ac4eaabfedc5f3385b89c4f404c9e98a658fa5c1d35823a55624993bfc62153c0'
    '0f7cbc72536f07ac24d4591f5fd1d9f0292401deffeee2071618e73a36bd1bee1ccfe7e21fe884ae10cf1e6d9c55683247f1a066b3bd56d4'
    '04f392cc7f869b579e5b47ad987438a2cd3bbaa59e857008251984edc2893df1',
    radix: 16);
final _d = BigInt.parse(
    '6cea7849958796aeb68aac8c6834059c73a982c7933319cba70d776586b719db59fd35e67562a12d3d6454a4510b82f4a6f7a442e5cf87ac'
    'dc1dce121f130d2ea43e1fdf33a69186ece02bb8b785e68d2323f19adeca02ec0083e69c0a9dd3e471a7aebee009003ea4a1a5082620ebf1'
    'b08f0fb06966bc91183fbfaf4cd5a25fbd64b882278790f310ce6f0e7825a04d20cfc44e1cce4168b1c9547b4ef3680c399aadaf04487b05'
    '0749a5848226c10e3929c28364763aa391c82945097756702dae93572815a4bba456e4e2b31ef0e577aca08cfd82844f8d66b96dfbb48f44'
    '1472ff1bcfe1f488aa5bcb8d84583ad0e0fbbfbb52026cc2dc530416af0fae1',
    radix: 16);
final _p = BigInt.parse(
    'f663e00fa8e73ddccea911fc8398b86088e0a86b9f7702fff20bffd55990fd1a1d14c8c906377abb622f396c299cab81f0d3d6469f354ad1'
    '618991b73a46fd0352813281d021836b375e5ecdbf948e5cc4ddce5d6ff6f6d44c56ababe3dfb7a166160d892c87a6cf9c8181a21a355192'
    '55606dd63103479756be7ef87710bae1',
    radix: 16);
final _q = BigInt.parse(
    'd5808a3d846fbae2ca39e89f40b670fbfb59a80a4fdde10519ceb0e8c200d376ff24bf3807c75ce32489f955e40d1a2201a70f7edf45ab84'
    '5c2b9915c338994031c3759f8c139e930eb1e683e2f8ff90406101760ef7b424a44029b842d5f8ed115a3bb7145ec7a53c7187c6bc2537d7'
    'a82cc615be5ec907e7d91f5ef9847511',
    radix: 16);

/// [json] as PIA sends a list - the JSON, a blank line, the signature in base64 lines of 60 - signed
/// with the tests' key. Also points the app's check at that key, so the list passes; call
/// [usePiaServerListKey] to put PIA's back.
String signedServerList(Object json) {
  serverListKeyPem = kTestServerListKeyPem;
  final text = jsonEncode(json);
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(RSAPrivateKey(_n, _d, _p, _q)));
  final sig = base64Encode(signer.generateSignature(Uint8List.fromList(utf8.encode(text))).bytes);
  final lines = [for (var i = 0; i < sig.length; i += 60) sig.substring(i, i + 60 > sig.length ? sig.length : i + 60)];
  return '$text\n\n${lines.join('\n')}\n';
}

/// One region with WireGuard servers, signed: what most tests want from the list.
String signedRegionList(List<({String id, List<({String ip, String cn})> wg})> regions) => signedServerList({
      'regions': [
        for (final r in regions)
          {
            'id': r.id,
            'servers': {
              'wg': [
                for (final s in r.wg) {'ip': s.ip, 'cn': s.cn}
              ]
            }
          }
      ]
    });

void usePiaServerListKey() => serverListKeyPem = kPiaServerListKeyPem;

/// Points the app's check at the tests' key, for a test that checks lists signed with it.
void useTestServerListKey() => serverListKeyPem = kTestServerListKeyPem;
