// test/unit/firmware_test.dart - firmware classification + the session-scoped detection flag.
import 'package:cfg_pia_wg/firmware.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(resetRouterFirmware);
  tearDown(resetRouterFirmware);

  group('classifyFirmwareTag', () {
    test('any casing or suffix containing "merlin" is Merlin', () {
      for (final tag in ['merlin', 'Merlin', 'MERLIN', 'merlin-386', 'asuswrt-merlin']) {
        expect(classifyFirmwareTag(tag), RouterFirmware.merlin, reason: tag);
      }
    });

    // The nvram key simply does not exist on stock, so `nvram get` succeeds with no output.
    test('empty output is stock', () {
      expect(classifyFirmwareTag(''), RouterFirmware.stock);
      expect(classifyFirmwareTag('   \n '), RouterFirmware.stock);
    });

    test('any other value is unsupported', () {
      for (final tag in ['tomato', 'dd-wrt', 'openwrt']) {
        expect(classifyFirmwareTag(tag), isNull, reason: tag);
      }
    });

    test('surrounding whitespace does not change the verdict', () {
      expect(classifyFirmwareTag('  merlin \n'), RouterFirmware.merlin);
    });
  });

  group('detection flag', () {
    test('defaults to Merlin and reports itself undetected', () {
      expect(firmwareDetected, isFalse);
      expect(routerFirmware, RouterFirmware.merlin);
      expect(isStockFirmware, isFalse);
    });

    test('setting it marks the session detected', () {
      setRouterFirmware(RouterFirmware.stock);
      expect(firmwareDetected, isTrue);
      expect(routerFirmware, RouterFirmware.stock);
      expect(isStockFirmware, isTrue);
    });

    test('reset returns to the undetected default', () {
      setRouterFirmware(RouterFirmware.stock);
      resetRouterFirmware();
      expect(firmwareDetected, isFalse);
      expect(routerFirmware, RouterFirmware.merlin);
    });
  });

  group('paths', () {
    test('jqCommand follows the firmware', () {
      expect(jqCommand(RouterFirmware.merlin), 'jq');
      expect(jqCommand(RouterFirmware.stock), kStockJqPath);
    });

    test('jqCommand defaults to the detected firmware', () {
      expect(jqCommand(), 'jq');
      setRouterFirmware(RouterFirmware.stock);
      expect(jqCommand(), kStockJqPath);
    });

    test('the stock binaries live under the documented directory', () {
      expect(kRouterAppDir, '/jffs/cfg-pia-wg');
      expect(kStockJqPath, '/jffs/cfg-pia-wg/jq');
      expect(kStockMailsendPath, '/jffs/cfg-pia-wg/mailsend-go');
    });

    test('cron persistence paths differ per firmware', () {
      expect(kServicesStartPath, '/jffs/scripts/services-start');
      expect(kS50Path, '/opt/etc/init.d/S50downloadmaster');
    });

    test('the README link targets the prerequisites anchor', () {
      expect(kReadmePrereqUrl, endsWith('README.md#4-prerequisites--requirements'));
    });
  });
}
