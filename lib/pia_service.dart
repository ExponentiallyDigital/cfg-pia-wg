// pia_service.dart
// Direct translation of the PIA WireGuard provisioning logic from main.go
// Source: https://github.com/ExponentiallyDigital/pia-wireguard-cfg
//
// Implements the same flow:
//   1. Fetch server list from serverlist.piaservers.net
//   2. Measure TCP latency to port 1337 on each candidate server
//   3. Authenticate against PIA token API with HTTP Basic Auth
//   4. Generate WireGuard keypair using X25519 with RFC 7748 scalar clamping
//   5. Fetch PIA CA certificate dynamically from pia-foss/manual-connections
//   6. Register public key via HTTPS to port 1337 using PIA CA cert pool
//   7. Assemble and return the complete .conf file content

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:x25519/x25519.dart' as x25519;

class WgServer {
  final String ip;
  final String cn;
  const WgServer({required this.ip, required this.cn});
}

class Region {
  final String id;
  final List<WgServer> wgServers;
  const Region({required this.id, required this.wgServers});
}

class ProbeResult {
  final WgServer server;
  final Duration? latency; // null = probe failed
  const ProbeResult({required this.server, this.latency});
  bool get failed => latency == null;
}

class RegResponse {
  final String status;
  final String serverKey;
  final String peerIP;
  final int serverPort;
  const RegResponse({
    required this.status,
    required this.serverKey,
    required this.peerIP,
    required this.serverPort,
  });
  factory RegResponse.fromJson(Map<String, dynamic> json) => RegResponse(
        status: json['status'] as String? ?? '',
        serverKey: json['server_key'] as String? ?? '',
        peerIP: json['peer_ip'] as String? ?? '',
        serverPort: json['server_port'] as int? ?? 0,
      );
}

class PiaService {
  static const String _serverListUrl =
      'https://serverlist.piaservers.net/vpninfo/servers/v6';
  static const String _tokenUrl =
      'https://www.privateinternetaccess.com/gtoken/generateToken';
  static const String _caCertUrl =
      'https://raw.githubusercontent.com/pia-foss/manual-connections/master/ca.rsa.4096.crt';

  // ---------------------------------------------------------------------------
  // Fetch and parse the PIA server list
  // ---------------------------------------------------------------------------
  Future<List<Region>> fetchRegions({void Function(String)? onProgress}) async {
    onProgress?.call('Fetching PIA server list...');
    final http.Response response;
    try {
      response = await http
          .get(Uri.parse(_serverListUrl))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw Exception('Server list request timed out after 10 seconds.');
    }

    if (response.statusCode != 200) {
      throw Exception('Server list returned HTTP ${response.statusCode}');
    }

    final body = response.body;
    final newlineIdx = body.indexOf('\n');
    if (newlineIdx == -1) {
      throw Exception('Server list format error: missing newline after JSON');
    }
    final jsonPart = body.substring(0, newlineIdx);

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(jsonPart) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Server list JSON parse error: $e');
    }

    final rawRegions = decoded['regions'] as List<dynamic>? ?? [];
    final regions = <Region>[];
    for (final r in rawRegions) {
      final id = r['id'] as String? ?? '';
      final servers = r['servers'] as Map<String, dynamic>? ?? {};
      final wgList = servers['wg'] as List<dynamic>? ?? [];
      final wgServers = wgList
          .map((s) => WgServer(
                ip: s['ip'] as String? ?? '',
                cn: s['cn'] as String? ?? '',
              ))
          .toList();
      if (wgServers.isNotEmpty) {
        regions.add(Region(id: id, wgServers: wgServers));
      }
    }
    regions.sort((a, b) => a.id.compareTo(b.id));
    return regions;
  }

  // ---------------------------------------------------------------------------
  // Measure TCP latency to port 1337 for each server in a region.
  // Each probe result -- success or failure -- is reported via onProgress so
  // the user can see all servers and their individual latencies in the log.
  // ---------------------------------------------------------------------------
  Future<List<ProbeResult>> probeLatency(
    List<WgServer> servers, {
    void Function(String)? onProgress,
  }) async {
    final results = <ProbeResult>[];
    for (final server in servers) {
      onProgress?.call('Probing ${server.ip} (${server.cn})...');
      try {
        final start = DateTime.now();
        final socket = await Socket.connect(
          server.ip,
          1337,
          timeout: const Duration(seconds: 2),
        );
        final latency = DateTime.now().difference(start);
        await socket.close();
        results.add(ProbeResult(server: server, latency: latency));
        // Report per-server latency so the user can see all candidates
        onProgress?.call(
            '  ${server.ip} responded in ${latency.inMilliseconds}ms');
      } catch (e) {
        // Report probe failures rather than silently dropping them
        onProgress?.call('  ${server.ip} probe failed: $e');
        results.add(ProbeResult(server: server));
      }
    }
    results.sort((a, b) {
      if (a.failed) return 1;
      if (b.failed) return -1;
      return a.latency!.compareTo(b.latency!);
    });
    return results;
  }

  // ---------------------------------------------------------------------------
  // Authenticate and obtain a PIA token
  // ---------------------------------------------------------------------------
  Future<String> getToken(
    String username,
    String password, {
    void Function(String)? onProgress,
  }) async {
    onProgress?.call('Authenticating with PIA...');
    final credentials = base64Encode(utf8.encode('$username:$password'));
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {'Authorization': 'Basic $credentials'},
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw Exception('Authentication request timed out after 10 seconds.');
    }

    if (response.statusCode != 200) {
      throw Exception(
          'Authentication failed: HTTP ${response.statusCode}. Check your credentials.');
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Unexpected authentication response format: $e');
    }

    final token = decoded['token'] as String? ?? '';
    if (token.isEmpty) {
      throw Exception('Authentication failed: empty token received from PIA');
    }
    onProgress?.call('Authentication successful.');
    return token;
  }

  // ---------------------------------------------------------------------------
  // Generate a WireGuard keypair
  // Applies RFC 7748 scalar clamping: k[0] &= 248, k[31] &= 127, k[31] |= 64
  // ---------------------------------------------------------------------------
  (String privateKeyB64, String publicKeyB64) generateWgKeypair() {
    final priv = Uint8List(32);
    final rng = Random.secure();
    for (var i = 0; i < 32; i++) {
      priv[i] = rng.nextInt(256);
    }
    priv[0] &= 248;
    priv[31] &= 127;
    priv[31] |= 64;
    final pub = x25519.X25519(priv, x25519.basePoint);
    return (base64Encode(priv), base64Encode(pub));
  }

  // ---------------------------------------------------------------------------
  // Fetch PIA CA certificate dynamically
  // ---------------------------------------------------------------------------
  Future<String> _fetchCaCert({void Function(String)? onProgress}) async {
    onProgress?.call('Fetching PIA CA certificate...');
    final http.Response response;
    try {
      response = await http
          .get(Uri.parse(_caCertUrl))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw Exception('CA certificate fetch timed out after 10 seconds.');
    }
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to fetch PIA CA certificate: HTTP ${response.statusCode}');
    }
    return response.body;
  }

  // ---------------------------------------------------------------------------
  // Register WireGuard public key with PIA server (GET, mirrors main.go)
  // ---------------------------------------------------------------------------
  Future<RegResponse> registerKey(
    WgServer server,
    String token,
    String publicKeyB64, {
    void Function(String)? onProgress,
  }) async {
    final caCertPem = await _fetchCaCert(onProgress: onProgress);
    onProgress?.call('Registering key with ${server.ip}...');

    final secCtx = SecurityContext(withTrustedRoots: false);
    secCtx.setTrustedCertificatesBytes(utf8.encode(caCertPem));
    final httpClient = HttpClient(context: secCtx);
    httpClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    httpClient.findProxy = (uri) => 'DIRECT';

    final encodedPubkey = Uri.encodeQueryComponent(publicKeyB64);
    final encodedToken = Uri.encodeQueryComponent(token);
    final uri = Uri.parse(
      'https://${server.ip}:1337/addKey?pt=$encodedToken&pubkey=$encodedPubkey',
    );

    try {
      // GET, not POST -- mirrors main.go line 480
      final request = await httpClient.getUrl(uri);
      request.headers.host = server.cn;

      final rawResponse =
          await request.close().timeout(const Duration(seconds: 10));
      final body = await rawResponse.transform(utf8.decoder).join();

      if (rawResponse.statusCode != 200) {
        throw Exception(
            'Registration failed: HTTP ${rawResponse.statusCode}\n$body');
      }

      final Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception(
            'Unexpected registration response format: $e\nRaw: $body');
      }

      final reg = RegResponse.fromJson(decoded);
      if (reg.status != 'OK') {
        throw Exception(
            'Registration failed: status "${reg.status}" from PIA server');
      }

      onProgress?.call(
          'Key registered. Peer IP: ${reg.peerIP}, port: ${reg.serverPort}');
      return reg;
    } on TimeoutException {
      throw Exception('Key registration timed out after 10 seconds.');
    } finally {
      httpClient.close(force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Assemble the WireGuard config file
  // ---------------------------------------------------------------------------
  String buildConfig({
    required String privateKey,
    required String peerIP,
    required String dns,
    required String serverKey,
    required String serverIP,
    required int serverPort,
  }) {
    var cleanIP = peerIP;
    final slashIdx = cleanIP.indexOf('/');
    if (slashIdx != -1) cleanIP = cleanIP.substring(0, slashIdx);

    final config = '[Interface]\n'
        'PrivateKey = $privateKey\n'
        'Address = $cleanIP/32\n'
        'DNS = $dns\n'
        'MTU = 1420\n'
        '\n'
        '[Peer]\n'
        'PublicKey = $serverKey\n'
        'Endpoint = $serverIP:$serverPort\n'
        'PersistentKeepalive = 25\n'
        'AllowedIPs = 0.0.0.0/0\n';
    return config.replaceAll('\r', '');
  }

  // ---------------------------------------------------------------------------
  // Full provisioning flow
  // ---------------------------------------------------------------------------
  Future<String> generateConfig({
    required String region,
    required String username,
    required String password,
    required String dns,
    void Function(String status)? onProgress,
  }) async {
    // 1. Fetch server list
    final regions = await fetchRegions(onProgress: onProgress);
    final matched = regions.where((r) => r.id == region).toList();
    if (matched.isEmpty) {
      throw Exception(
          'Region "$region" not found. Use the region picker to see available regions.');
    }
    final selectedRegion = matched.first;
    if (selectedRegion.wgServers.isEmpty) {
      throw Exception('No WireGuard servers found for region "$region"');
    }

    // 2. Probe latency -- each server result is logged individually
    onProgress?.call(
        'Measuring latency for ${selectedRegion.wgServers.length} server(s) in $region...');
    final probeResults =
        await probeLatency(selectedRegion.wgServers, onProgress: onProgress);
    final responding = probeResults.where((r) => !r.failed).toList();
    if (responding.isEmpty) {
      throw Exception(
          'All latency probes failed for region "$region". Check your network connection.');
    }
    final bestServer = responding.first.server;
    final bestMs = responding.first.latency!.inMilliseconds;
    onProgress?.call(
        'Selected ${bestServer.ip} -- '
        '${responding.length}/${probeResults.length} servers responded, '
        'best latency ${bestMs}ms');

    // 3. Get auth token
    final token = await getToken(username, password, onProgress: onProgress);

    // 4. Generate keypair
    onProgress?.call('Generating WireGuard keypair...');
    final (privateKey, publicKey) = generateWgKeypair();

    // 5 & 6. Register key
    final reg =
        await registerKey(bestServer, token, publicKey, onProgress: onProgress);

    // 7. Build config
    onProgress?.call('Building config file...');
    return buildConfig(
      privateKey: privateKey,
      peerIP: reg.peerIP,
      dns: dns,
      serverKey: reg.serverKey,
      serverIP: bestServer.ip,
      serverPort: reg.serverPort,
    );
  }
}
