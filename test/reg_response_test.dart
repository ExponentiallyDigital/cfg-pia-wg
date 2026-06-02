import 'package:flutter_test/flutter_test.dart';
import 'package:pia_wireguard_cfga/pia_service.dart';

void main() {
  test('RegResponse parses json', () {
    final response = RegResponse.fromJson({
      'status': 'OK',
      'server_key': 'abc',
      'peer_ip': '10.0.0.1',
      'server_port': 1337,
    });

    expect(response.status, 'OK');
    expect(response.serverKey, 'abc');
    expect(response.peerIP, '10.0.0.1');
    expect(response.serverPort, 1337);
  });

  test('RegResponse uses safe defaults for missing json fields', () {
    final response = RegResponse.fromJson({});

    expect(response.status, '');
    expect(response.serverKey, '');
    expect(response.peerIP, '');
    expect(response.serverPort, 0);
  });
}
