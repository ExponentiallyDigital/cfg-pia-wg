import 'package:flutter_test/flutter_test.dart';
import 'package:pia_wireguard_cfga/pia_service.dart';

void main() {
  test('Region stores values', () {
    final region = Region(
      id: 'aus_melbourne',
      wgServers: [
        const WgServer(ip: '1.1.1.1', cn: 'server'),
      ],
    );

    expect(region.id, 'aus_melbourne');
    expect(region.wgServers.length, 1);
  });
}
