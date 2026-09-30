// The router's SSH host key, recorded at first connect and checked after (ID-308).
//
// These test the store and FORGET. The refusal itself - a changed key stopping the connection
// before any password is sent - happens inside dartssh2's key exchange, which needs a real SSH
// server; it was proved against the maintainer's router on 2026-09-30 (CHANGELOG ID-308), and
// scripts/check-claims.sh's app half repeats it.
import 'dart:io';

import 'package:cfg_pia_wg/router_host_keys.dart';
import 'package:cfg_pia_wg/router_prefs.dart';
import 'package:cfg_pia_wg/router_session.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const fpA = 'SHA256:StPU/egv83uSyL1i4btJa72Etm9uxOcS77H+/trtjyo';
const fpB = 'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

void main() {
  late Directory dir;
  late RouterHostKeys keys;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('host_keys_');
    keys = RouterHostKeys(directory: () async => dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('nothing is recorded until a key is', () async {
    expect(await keys.recorded('192.168.1.1:22'), isNull);
  });

  test('a key is recorded per address and port, and read back', () async {
    expect(await keys.record('192.168.1.1:22', fpA), isTrue);
    expect(await keys.record('192.168.1.1:2222', fpB), isTrue);
    expect(await keys.recorded('192.168.1.1:22'), fpA);
    expect(await keys.recorded('192.168.1.1:2222'), fpB);
    expect(await keys.recorded('192.168.1.2:22'), isNull);
  });

  test('anything that is not an address:port and a SHA256 fingerprint is refused', () async {
    for (final (t, f) in [
      ('192.168.1.1', fpA),
      ('192.168.1.1:22', 'MD5:aa:bb'),
      ('192.168.1.1:22', 'SHA256:short'),
      (r'$(reboot):22', fpA),
    ]) {
      expect(await keys.record(t, f), isFalse, reason: '$t $f');
    }
    expect(File('${dir.path}/$kRouterHostKeysFile').existsSync(), isFalse);
  });

  test('a hand-edited line that is not a fingerprint is ignored, not trusted', () async {
    File('${dir.path}/$kRouterHostKeysFile').writeAsStringSync('192.168.1.1:22 anything\n192.168.1.2:22 $fpA\n');
    expect(await keys.recorded('192.168.1.1:22'), isNull);
    expect(await keys.recorded('192.168.1.2:22'), fpA);
  });

  test('FORGET ROUTER IP forgets the key with the address', () async {
    await keys.record('192.168.1.1:22', fpA);
    final c = SessionController(routerPrefs: RouterPrefs(directory: () async => dir), hostKeys: keys);
    await c.forgetRouterIp();
    expect(await keys.recorded('192.168.1.1:22'), isNull);
    expect(c.log.last.message, contains('Remembered router address and its SSH key deleted'));
    c.dispose();
  });

  // ID-338: forget() never throws, so "deleted" was logged whether or not it was.
  test('FORGET that could not delete the address says so', () async {
    final c = SessionController(routerPrefs: _StuckPrefs(), hostKeys: keys);
    await c.forgetRouterIp();
    expect(c.log.last.message, contains('could not be deleted'));
    c.dispose();
  });

  test('a changed key is explained on screen, not reported as an unreachable router', () {
    final e = RouterHostKeyChanged('192.168.1.1:22', fpA, fpB);
    final m = routerConnectMessage(e, '192.168.1.1')!;
    expect(m, contains('different SSH key'));
    expect(m, contains('No password was sent'));
    expect(m, contains('FORGET ROUTER IP'));
    expect(m, contains(fpA));
    expect(m, contains(fpB));
  });

  test('under flutter test with no directory, the store is inert and records nothing', () async {
    final inert = RouterHostKeys();
    expect(await inert.record('192.168.1.1:22', fpA), isFalse);
    expect(await inert.recorded('192.168.1.1:22'), isNull);
  });
}

/// A store whose delete does nothing, as a read-only or failing storage would leave it.
class _StuckPrefs extends RouterPrefs {
  _StuckPrefs() : super(directory: () async => Directory.systemTemp);
  @override
  Future<String> load() async => '192.168.1.1';
  @override
  Future<void> forget() async {}
}
