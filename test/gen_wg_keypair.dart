import 'package:flutter_test/flutter_test.dart';
import 'package:pia_wireguard_cfga/pia_service.dart';

void main() {
  test('generateWgKeypair returns valid keys', () {
    final service = PiaService();

    final (privateKey, publicKey) = service.generateWgKeypair();

    expect(privateKey.isNotEmpty, true);
    expect(publicKey.isNotEmpty, true);
    expect(privateKey.length, greaterThan(40));
    expect(publicKey.length, greaterThan(40));
  });
}
