// addKey trusts only PIA's CA, for the server's NAME (ID-309).
//
// Until build 478 registerKey set a badCertificateCallback that returned true for any certificate
// whose subject named the server. Dart calls that callback for EVERY certificate that fails, an
// untrusted chain included, so a self-signed certificate naming the server was accepted: the pin
// pinned nothing (claims audit #3). The tests that covered it handed a fake client a fake
// certificate and expected success, so nothing could have failed.
//
// These run a real TLS server on loopback with real certificates (test/pia_tls_fixtures.dart): one
// signed by the test CA for the right name, a self-signed impostor with the same name, and one
// signed by the CA for the wrong name. The two bad ones must fail, and the server must never
// receive the request - the token travels in it.
import 'dart:convert';
import 'dart:io';

import 'package:cfg_pia_wg/pia_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../pia_tls_fixtures.dart';

class _Server {
  _Server._(this.server);
  final HttpServer server;
  final requests = <Uri>[];
  int status = 200;
  String body = jsonEncode({'status': 'OK', 'server_key': 'server-key', 'peer_ip': '10.10.0.2', 'server_port': 1337});

  static Future<_Server> start(String cert, String key) async {
    final ctx = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(cert))
      ..usePrivateKeyBytes(utf8.encode(key));
    final s = _Server._(await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx));
    s.server.listen((req) async {
      s.requests.add(req.uri);
      req.response
        ..statusCode = s.status
        ..write(s.body);
      await req.response.close();
    }, onError: (_) {});
    return s;
  }

  PiaService service() => PiaService(registerPort: server.port, caCertLoader: () async => kCaCrt);
  Future<void> close() => server.close(force: true);
}

const _server = WgServer(ip: '127.0.0.1', cn: 'server-cn');

void main() {
  test('a certificate PIA\'s CA signed for the server\'s name is accepted, and the key is registered', () async {
    final s = await _Server.start(kGoodCrt, kGoodKey);
    try {
      final progress = <String>[];
      final r = await s.service().registerKey(_server, 'token value', 'public/key=', onProgress: progress.add);
      expect(r.status, 'OK');
      expect(r.serverKey, 'server-key');
      expect(r.peerIP, '10.10.0.2');
      expect(s.requests.single.path, '/addKey');
      expect(s.requests.single.queryParameters['pt'], 'token value');
      expect(s.requests.single.queryParameters['pubkey'], 'public/key=');
      expect(progress, ['Registering key with 127.0.0.1...', 'Key registered. Peer IP: 10.10.0.2']);
    } finally {
      await s.close();
    }
  });

  test('a self-signed certificate that names the server is refused, and the token is never sent', () async {
    final s = await _Server.start(kRogueCrt, kRogueKey);
    try {
      await expectLater(s.service().registerKey(_server, 'token value', 'public'), throwsA(isA<HandshakeException>()));
      expect(s.requests, isEmpty);
    } finally {
      await s.close();
    }
  });

  test('a certificate PIA\'s CA signed for a different name is refused, and the token is never sent', () async {
    final s = await _Server.start(kWrongnameCrt, kWrongnameKey);
    try {
      await expectLater(s.service().registerKey(_server, 'token value', 'public'), throwsA(isA<HandshakeException>()));
      expect(s.requests, isEmpty);
    } finally {
      await s.close();
    }
  });

  test('a status other than OK is an error', () async {
    final s = await _Server.start(kGoodCrt, kGoodKey)
      ..body = jsonEncode({'status': 'FAILED', 'server_key': 'k', 'peer_ip': '10.10.0.2', 'server_port': 1337});
    try {
      await expectLater(s.service().registerKey(_server, 't', 'p'),
          throwsA(isA<Exception>().having((e) => '$e', 'message', contains('Status: "FAILED"'))));
    } finally {
      await s.close();
    }
  });

  test('an HTTP error carries the body', () async {
    final s = await _Server.start(kGoodCrt, kGoodKey)
      ..status = 500
      ..body = 'registration failed';
    try {
      await expectLater(s.service().registerKey(_server, 't', 'p'),
          throwsA(isA<Exception>().having((e) => '$e', 'message', contains('HTTP 500\nregistration failed'))));
    } finally {
      await s.close();
    }
  });
}
