import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pia_wireguard_cfga/main.dart';
import 'package:pia_wireguard_cfga/pia_service.dart';

void main() {
  test('ProbeResult failed property works', () {
    final server = WgServer(ip: '1.1.1.1', cn: 'test');

    expect(
      ProbeResult(server: server).failed,
      true,
    );

    expect(
      ProbeResult(
        server: server,
        latency: const Duration(milliseconds: 10),
      ).failed,
      false,
    );
  });
}
