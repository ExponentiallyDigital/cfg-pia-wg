// test/pia_generate_harness.dart - shared scaffolding to drive PiaService.generateConfig in tests.
//
// generateConfig needs: a real loopback socket on 127.0.0.1:1337 (probeLatency), a real cert PEM
// (registerKey parses it), and FakeHttpClient for the four HTTP calls.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'http_test_helpers.dart';

const String kTestRegion = 'us_test';
const String kTestCn = 'server-cn';

const String kTestCertPem = '''-----BEGIN CERTIFICATE-----
MIIDDTCCAfWgAwIBAgIULc36dwyl3c58/o2Cbi+MC1pqvp0wDQYJKoZIhvcNAQEL
BQAwFjEUMBIGA1UEAwwLUElBLVRlc3QtQ0EwHhcNMjYwNjA5MTgzOTA1WhcNMzYw
NjA2MTgzOTA1WjAWMRQwEgYDVQQDDAtQSUEtVGVzdC1DQTCCASIwDQYJKoZIhvcN
AQEBBQADggEPADCCAQoCggEBAOerejlSVzdHVHyM2Lz+Z2Zw7n06iMIs2Bv6cBCZ
bOyIMubdn7gHioWn0DMDedYlKHJbDFTAWYRtovcown2rVhTILYHyrBkRHjOwjtwu
6S0fSI4Obt/ZmdIGhci+JrdjqRCJYYul9X9cWKo3q269Uq5E7nhLgIO/N4DdB3UL
a6zW9xX0JX+adNHqs31mFdhcjIDfoHbg/WTTbwb1yj562GDKcKxXt4j3JxCa7QJA
fWPqEPKfrgMBxR8JITedhtDgIoUXbOEJWLxII5hAFtTYAcs2k/9IpE+zbcRMtgNB
ljt/lw6a1YI3Zw+mcyAr/3HmfPbNp4DM496sQHMF3UAW/6UCAwEAAaNTMFEwHQYD
VR0OBBYEFHpsZ/WOyV8vozOW4JiaNxFhzfcXMB8GA1UdIwQYMBaAFHpsZ/WOyV8v
ozOW4JiaNxFhzfcXMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEB
AFkIETEtEBbRzur2IDXwptrk8nogS0QJwGzKMMlMyl+GH2/o77BewK3MzdzwgPUO
2aYvjd5zfCQ9MHldj4H+yG+Qa92FuzihcZhGBiuDcuL84T6Q+FDgeTWCej5BkzYg
HS+jUBJxOVwt83DEaBgYqn7k2je6kyB/Q9/g6Y/FsDdKEllTSdRgpOGOxRDB+j8J
x0xpEworH0XBzRKwwIwzbGUH9sA4BuFTFUIloFFjsN1X/wDxxtF9vueZsCeXP1QL
MQRWTK4MMjOHQQ4tGnOJ0pThj2Au4XwOnU6S1nrcMJ9jb5srad2TH6BQFLe4uwrC
1JXQGhGiJI6sr78U1FRmSV0=
-----END CERTIFICATE-----''';

String _serverListBody() => '${jsonEncode({
      'regions': [
        {
          'id': kTestRegion,
          'servers': {
            'wg': [
              {'ip': '127.0.0.1', 'cn': kTestCn}
            ]
          }
        }
      ]
    })}\n';

FakeHttpClientResponse fakeGenerateResponses(Uri url, String method) {
  final u = url.toString();
  if (u.contains('vpninfo/servers/v6')) return FakeHttpClientResponse(200, _serverListBody());
  if (u.contains('generateToken')) return FakeHttpClientResponse(200, '{"token":"test-token"}');
  if (u.contains('ca.rsa.4096.crt')) return FakeHttpClientResponse(200, kTestCertPem);
  if (u.contains('addKey')) {
    return FakeHttpClientResponse(
        200, '{"status":"OK","server_key":"c2VydmVycHVia2V5","peer_ip":"10.7.7.2/32","server_port":1337}');
  }
  return FakeHttpClientResponse(404, 'not found');
}

/// Pumps frames while giving the real event loop time so the real Socket.connect + the fake-async
/// HTTP inside generateConfig can complete.
Future<void> driveUntil(WidgetTester tester, bool Function() done, {int maxIterations = 150}) async {
  for (var i = 0; i < maxIterations; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump();
    if (done()) return;
  }
}
