import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wireguard/pia_service.dart';

void main() {
  test('buildConfig builds expected config', () {
    final service = PiaService();

    final config = service.buildConfig(
      privateKey: 'PRIVATE',
      peerIP: '10.0.0.1/32',
      dns: '1.1.1.1',
      serverKey: 'SERVERKEY',
      serverIP: '1.2.3.4',
      serverPort: 1337,
    );

    expect(config.contains('[Interface]'), true);
    expect(config.contains('PrivateKey = PRIVATE'), true);
    expect(config.contains('Address = 10.0.0.1/32'), true);
    expect(config.contains('DNS = 1.1.1.1'), true);
    expect(config.contains('[Peer]'), true);
    expect(config.contains('PublicKey = SERVERKEY'), true);
    expect(config.contains('Endpoint = 1.2.3.4:1337'), true);
  });
}
