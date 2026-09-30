import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/main.dart' as app;
import 'package:cfg_pia_wg/pia_service.dart';
import 'package:cfg_pia_wg/session_controller.dart' show kDefaultDns;

import 'http_test_helpers.dart';

class TestPiaService extends PiaService {
  final List<Region> regions;
  final List<ProbeResult> probeResults;
  final String token;
  final RegResponse regResponse;
  final (String, String) keypair;

  TestPiaService({
    required this.regions,
    required this.probeResults,
    required this.token,
    required this.regResponse,
    required this.keypair,
  });

  /// How many times `generateConfig` went back for the server list. A caller that already holds
  /// the record it chose should leave this at zero - resolving twice is what produced a "not found"
  /// on a region the picker had just offered.
  int fetchCount = 0;

  @override
  Future<List<Region>> fetchRegions({void Function(String)? onProgress}) async {
    fetchCount++;
    onProgress?.call('fetching');
    return regions;
  }

  @override
  Future<List<ProbeResult>> probeLatency(
    List<WgServer> servers, {
    void Function(String)? onProgress,
    required String regionId,
  }) async {
    onProgress?.call('probing');
    return probeResults;
  }

  @override
  Future<String> getToken(String username, String password, {void Function(String)? onProgress}) async {
    onProgress?.call('token');
    return token;
  }

  @override
  (String, String) generateWgKeypair() => keypair;

  @override
  Future<RegResponse> registerKey(WgServer server, String token, String publicKeyB64, {void Function(String)? onProgress}) async {
    onProgress?.call('register');
    return regResponse;
  }
}

// Binds an ephemeral port (0) rather than PiaService.defaultProbePort, so parallel test workers
// never contend for one fixed port. Pass `server.port` to PiaService(probePort:).
Future<ServerSocket> _bindLatencyServer() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) => socket.destroy());
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PiaService behavior', () {
    test('fetchRegions parses and sorts regions', () async {
      final regions = await withFakeHttpClient(
        () {
          final service = PiaService();
          return service.fetchRegions();
        },
        (url, method) {
          expect(method, 'GET');
          return FakeHttpClientResponse(
            200,
            '${jsonEncode({
                  'regions': [
                    {
                      'id': 'b_region',
                      'servers': {
                        'wg': [
                          {'ip': '2.2.2.2', 'cn': 'b-server'},
                        ],
                      },
                    },
                    {
                      'id': 'a_region',
                      'servers': {
                        'wg': [
                          {'ip': '1.1.1.1', 'cn': 'a-server'},
                        ],
                      },
                    },
                  ],
                })}\n',
          );
        },
      );

      expect(regions.map((r) => r.id).toList(), ['a_region', 'b_region']);
      expect(regions[0].wgServers.first.cn, 'a-server');
    });

    test('fetchRegions throws for malformed server list', () async {
      await expectLater(
        withFakeHttpClient(() {
          final service = PiaService();
          return service.fetchRegions();
        }, (url, method) => FakeHttpClientResponse(200, 'no newline here')),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Server list error'))),
      );
    });

    test('fetchRegions wraps non-200 responses and reports progress', () async {
      final progress = <String>[];

      await expectLater(
        withFakeHttpClient(() {
          final service = PiaService();
          return service.fetchRegions(onProgress: progress.add);
        }, (url, method) => FakeHttpClientResponse(503, 'unavailable')),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('HTTP 503'))),
      );

      expect(progress, ['Fetching PIA server list...']);
    });

    test('fetchRegions ignores regions without WireGuard servers', () async {
      final regions = await withFakeHttpClient(
        () {
          final service = PiaService();
          return service.fetchRegions();
        },
        (url, method) => FakeHttpClientResponse(
          200,
          '${jsonEncode({
                'regions': [
                  {'id': 'missing_servers'},
                  {
                    'id': 'empty_wg',
                    'servers': {'wg': []},
                  },
                  {
                    'id': 'usable',
                    'servers': {
                      'wg': [
                        {'ip': '10.0.0.1', 'cn': 'usable-cn'},
                      ],
                    },
                  },
                ],
              })}\n',
        ),
      );

      expect(regions, hasLength(1));
      expect(regions.single.id, 'usable');
      expect(regions.single.wgServers.single.ip, '10.0.0.1');
    });

    test('getToken returns token on successful authentication', () async {
      final progress = <String>[];
      final token = await withFakeHttpClient(() {
        final service = PiaService();
        return service.getToken('p123', 'password', onProgress: progress.add);
      }, (url, method) => FakeHttpClientResponse(200, jsonEncode({'token': 'abc123'})));

      expect(token, 'abc123');
      expect(progress, ['Authenticating with PIA...', 'Authentication successful.']);
    });

    // ID-253: STANDALONE showed "Auth error: HTTP 403 - authentication failed." for a wrong password.
    test('getToken says a refused login plainly, the same words on every screen', () async {
      await expectLater(
        withFakeHttpClient(() {
          final service = PiaService();
          return service.getToken('p123', 'wrong');
        }, (url, method) => FakeHttpClientResponse(401, jsonEncode({'message': 'Bad credentials'}))),
        throwsA(predicate((e) => e == '$kPiaCredentialsRejected (HTTP 401)' && isPiaAuthRejection(e!))),
      );
    });

    test('a 403 refusal reads the same as a 401', () async {
      await expectLater(
        withFakeHttpClient(() {
          final service = PiaService();
          return service.getToken('p123', 'wrong');
        }, (url, method) => FakeHttpClientResponse(403, jsonEncode({'error': 'Forbidden'}))),
        throwsA(predicate((e) => e == '$kPiaCredentialsRejected (HTTP 403)' && isPiaAuthRejection(e!))),
      );
    });

    // ID-245, 2026-09-28: PIA's login service was down. Every login waited 60 s for Cloudflare's 504
    // and then showed "Auth error: HTTP 504 - error code: 504", which read as the app failing.
    test('getToken says plainly when PIA answers with a server error, and logs what it sent', () async {
      final progress = <String>[];
      Object? error;
      try {
        await withFakeHttpClient(() => PiaService().getToken('p123', 'pw', onProgress: progress.add),
            (url, method) => FakeHttpClientResponse(504, 'error code: 504'));
      } catch (e) {
        error = e;
      }
      expect(error, piaLoginUnavailable('HTTP 504'));
      expect('$error', contains("This is at PIA's end"));
      expect(isPiaAuthRejection(error!), isFalse, reason: 'not a wrong password');
      expect(progress, contains('PIA login answered HTTP 504: error code: 504'));
    });

    test('getToken gives up on a PIA that never answers, rather than waiting a minute', () async {
      final started = DateTime.now();
      Object? error;
      try {
        await withFakeHttpClient(
            () => PiaService(tokenTimeout: const Duration(milliseconds: 50)).getToken('p123', 'pw'),
            (url, method) => _SilentResponse());
      } catch (e) {
        error = e;
      }
      expect(error, piaLoginUnavailable('no answer in 0 s'));
      expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 5)));
    });

    test('the default wait is well short of the 60 s PIA took to fail', () {
      expect(kPiaTokenTimeout, const Duration(seconds: 20));
      expect(PiaService().tokenTimeout, kPiaTokenTimeout);
    });

    test('getToken keeps plain text body when rejected response is not JSON', () async {
      await expectLater(
        withFakeHttpClient(() {
          final service = PiaService();
          return service.getToken('p123', 'wrong');
        }, (url, method) => FakeHttpClientResponse(429, 'Too many attempts')),
        throwsA(predicate((e) => e is String && e.contains('Auth error: HTTP 429 - Too many attempts'))),
      );
    });

    test('getToken throws when success response has no token', () async {
      await expectLater(
        withFakeHttpClient(() {
          final service = PiaService();
          return service.getToken('p123', 'password');
        }, (url, method) => FakeHttpClientResponse(200, jsonEncode({}))),
        throwsA(predicate((e) => e is String && e.contains('Auth error: Empty token received'))),
      );
    });

    test('generateConfig throws when region is missing', () async {
      final service = TestPiaService(
        regions: [
          Region(
            id: 'us',
            wgServers: [const WgServer(ip: '1.1.1.1', cn: 'server')],
          ),
        ],
        probeResults: [
          const ProbeResult(
            server: WgServer(ip: '1.1.1.1', cn: 'server'),
            latency: Duration(milliseconds: 10),
          ),
        ],
        token: 'token',
        regResponse: const RegResponse(status: 'OK', serverKey: 'serverkey', peerIP: '10.0.0.1', serverPort: 1337),
        keypair: ('private', 'public'),
      );

      await expectLater(
        service.generateConfig(region: 'aus_melbourne', username: 'p123456', password: 'secret', dns: '1.1.1.1'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Region "aus_melbourne" not found.'))),
      );
    });

    test('a region handed in is used as-is, and the server list is NOT fetched again', () async {
      // The list this service would return no longer holds the region - exactly the case that broke
      // a CREATE on hardware, where the picker offered ca_ontario and a fetch six seconds later did
      // not list it. Handing the record in has to be enough.
      const server = WgServer(ip: '1.1.1.1', cn: 'server');
      final service = TestPiaService(
        regions: const [],
        probeResults: const [ProbeResult(server: server, latency: Duration(milliseconds: 10))],
        token: 'token',
        regResponse: const RegResponse(status: 'OK', serverKey: 'serverkey', peerIP: '10.0.0.1', serverPort: 1337),
        keypair: ('private', 'public'),
      );

      final config = await service.generateConfig(
        region: 'ca_ontario',
        selected: const Region(id: 'ca_ontario', wgServers: [server]),
        username: 'p123456',
        password: 'secret',
        dns: '1.1.1.1',
      );

      expect(config, contains('Endpoint = 1.1.1.1:1337'));
      expect(service.fetchCount, 0, reason: 'the caller already had the region; asking again is the bug');
    });

    test('a handed-in region for a DIFFERENT id is ignored and the id is resolved by fetching', () async {
      // The region field is free text, so a typed id must still resolve normally. A stale record
      // left over from an earlier pick must never be used for it.
      final service = TestPiaService(
        regions: const [],
        probeResults: const [],
        token: 'token',
        regResponse: const RegResponse(status: 'OK', serverKey: 'serverkey', peerIP: '10.0.0.1', serverPort: 1337),
        keypair: ('private', 'public'),
      );

      await expectLater(
        service.generateConfig(
          region: 'aus_perth',
          selected: const Region(id: 'ca_ontario', wgServers: [WgServer(ip: '1.1.1.1', cn: 'server')]),
          username: 'p123456',
          password: 'secret',
          dns: '1.1.1.1',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Region "aus_perth" not found.'))),
      );
      expect(service.fetchCount, 1);
    });

    test('generateConfig throws when selected region has no servers', () async {
      final service = TestPiaService(
        regions: [Region(id: 'aus_melbourne', wgServers: [])],
        probeResults: const [],
        token: 'token',
        regResponse: const RegResponse(status: 'OK', serverKey: 'serverkey', peerIP: '10.0.0.1', serverPort: 1337),
        keypair: ('private', 'public'),
      );

      await expectLater(
        service.generateConfig(region: 'aus_melbourne', username: 'p123456', password: 'secret', dns: '1.1.1.1'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('No WG servers in region.'))),
      );
    });

    test('generateConfig throws when all latency probes fail', () async {
      final service = TestPiaService(
        regions: [
          Region(
            id: 'aus_melbourne',
            wgServers: const [WgServer(ip: '1.1.1.1', cn: 'server')],
          ),
        ],
        probeResults: const [
          ProbeResult(
            server: WgServer(ip: '1.1.1.1', cn: 'server'),
          ),
        ],
        token: 'token',
        regResponse: const RegResponse(status: 'OK', serverKey: 'serverkey', peerIP: '10.0.0.1', serverPort: 1337),
        keypair: ('private', 'public'),
      );

      await expectLater(
        service.generateConfig(region: 'aus_melbourne', username: 'p123456', password: 'secret', dns: '1.1.1.1'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('All latency probes failed.'))),
      );
    });

    test('generateConfig returns expected WireGuard config when pipeline succeeds', () async {
      final service = TestPiaService(
        regions: [
          Region(
            id: 'aus_melbourne',
            wgServers: const [WgServer(ip: '1.1.1.1', cn: 'server')],
          ),
        ],
        probeResults: const [
          ProbeResult(
            server: WgServer(ip: '1.1.1.1', cn: 'server'),
            latency: Duration(milliseconds: 3),
          ),
        ],
        token: 'token',
        regResponse: const RegResponse(status: 'OK', serverKey: 'serverkey', peerIP: '10.0.0.1', serverPort: 1337),
        keypair: ('private', 'public'),
      );

      final config = await service.generateConfig(
        region: 'aus_melbourne',
        username: 'p123456',
        password: 'secret',
        dns: '1.1.1.1',
      );

      expect(config, contains('PrivateKey = private'));
      expect(config, contains('Address = 10.0.0.1/32'));
      expect(config, contains('PublicKey = serverkey'));
    });

    test('generateConfig uses default DNS and reports pipeline progress', () async {
      final progress = <String>[];
      final service = TestPiaService(
        regions: [
          Region(
            id: 'aus_melbourne',
            wgServers: const [WgServer(ip: '1.1.1.1', cn: 'MELBOURNE')],
          ),
        ],
        probeResults: const [
          ProbeResult(
            server: WgServer(ip: '1.1.1.1', cn: 'MELBOURNE'),
            latency: Duration(milliseconds: 7),
          ),
        ],
        token: 'token',
        regResponse: const RegResponse(status: 'OK', serverKey: 'serverkey', peerIP: '10.0.0.1/24', serverPort: 1337),
        keypair: ('private', 'public'),
      );

      final config = await service.generateConfig(
        region: 'aus_melbourne',
        username: 'p123456',
        password: 'secret',
        dns: '',
        onProgress: progress.add,
      );

      // The service's own fallback must match the default the UI shows, or a blank field
      // silently generates with different servers than the screen claims.
      expect(config, contains('DNS = $kDefaultDns'));
      expect(config, contains('Address = 10.0.0.1/32'));
      expect(progress, contains('fetching'));
      expect(progress, contains('probing'));
      expect(progress, contains('Selected 1.1.1.1 melbourne 7ms'));
      expect(progress, contains('Generating WireGuard keypair...'));
      expect(progress, contains('token'));
      expect(progress, contains('register'));
    });

    test('generateWgKeypair returns clamped base64-encoded keys', () {
      final service = PiaService();

      final (privateKey, publicKey) = service.generateWgKeypair();
      final privateBytes = base64Decode(privateKey);
      final publicBytes = base64Decode(publicKey);

      expect(privateBytes, hasLength(32));
      expect(publicBytes, hasLength(32));
      expect(privateBytes.first & 7, 0);
      expect(privateBytes.last & 128, 0);
      expect(privateBytes.last & 64, 64);
    });

    test('probeLatency sorts responding servers ahead of failing servers', () async {
      const responding = WgServer(ip: '127.0.0.1', cn: 'local');
      const failing = WgServer(ip: '192.0.2.1', cn: 'dead');
      final progress = <String>[];

      final server = await _bindLatencyServer();
      final service = PiaService(probePort: server.port);
      try {
        final results = await service.probeLatency([responding, failing], onProgress: progress.add, regionId: 'test_region');
        expect(results.first.server.ip, '127.0.0.1');
        expect(results.last.failed, true);
        expect(progress.any((msg) => msg.contains('192.0.2.1 failed')), true);
      } finally {
        await server.close();
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('probeLatency sorts responding servers by latency', () async {
      const first = WgServer(ip: '127.0.0.1', cn: 'local-a');
      const second = WgServer(ip: '127.0.0.1', cn: 'local-b');
      final progress = <String>[];

      final server = await _bindLatencyServer();
      final service = PiaService(probePort: server.port);
      try {
        final results = await service.probeLatency([first, second], onProgress: progress.add, regionId: 'test_region');

        expect(results, hasLength(2));
        expect(results.every((r) => !r.failed), true);
        expect(results[0].latency!.compareTo(results[1].latency!) <= 0, true);
        expect(progress.first, 'Probing test_region latency...');
        expect(progress.where((msg) => msg.contains('responded')), hasLength(2));
      } finally {
        await server.close();
      }
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  group('MainScreen targeted generated-config behavior', () {
    testWidgets('main entry point runs the app widget', (tester) async {
      app.main();
      await tester.pump();

      expect(find.byType(app.PiaWgApp), findsOneWidget);
    });

    // Coverage for specific uncovered code paths through unit tests
    // Widget integration tests can cause timeouts due to complex async socket interactions

    test('probeLatency reports failed probe with progress callback', () async {
      const responding = WgServer(ip: '127.0.0.1', cn: 'local');
      const failing = WgServer(ip: '192.0.2.99', cn: 'unreachable');
      final progress = <String>[];

      final server = await _bindLatencyServer();
      final service = PiaService(probePort: server.port);
      try {
        final results = await service.probeLatency([responding, failing], onProgress: progress.add, regionId: 'test_region');

        // Verify the progress callback was called for failed probe
        // This covers: onProgress?.call('  ${server.ip} failed: $e');
        expect(results.any((r) => r.failed), true);
        expect(progress.any((msg) => msg.contains('192.0.2.99 failed')), true);
      } finally {
        await server.close();
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('getToken calls onProgress with Authenticating and successful messages', () async {
      final progress = <String>[];
      await withFakeHttpClient(() {
        final service = PiaService();
        return service.getToken('user', 'pass', onProgress: progress.add);
      }, (url, method) => FakeHttpClientResponse(200, jsonEncode({'token': 'token123'})));

      // Covers: onProgress?.call('Authenticating with PIA...');
      expect(progress, contains('Authenticating with PIA...'));
      // Covers: onProgress?.call('Authentication successful.');
      expect(progress, contains('Authentication successful.'));
    });
  });
}

/// A response that never sends anything: a server that accepted the connection and went quiet.
class _SilentResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      StreamController<List<int>>().stream.listen(onData, onError: onError, onDone: onDone);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
