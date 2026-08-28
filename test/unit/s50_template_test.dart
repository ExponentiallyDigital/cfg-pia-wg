// test/unit/s50_template_test.dart - the embedded S50downloadmaster copy and its cru-block editor.
import 'dart:io';

import 'package:cfg_pia_wg/s50_template.dart';
import 'package:flutter_test/flutter_test.dart';

const _check = 'cru a watchdog_wgc1 "*/5 * * * *" /jffs/scripts/watchdog_wgc1.sh';
const _rotate = 'cru a watchdog_log_rotate_wgc1 "0 0 * * *" "mv /tmp/watchdog_wgc1.log /tmp/watchdog_wgc1.log.old"';

void main() {
  group('embedded copy', () {
    // The app must ship the script; the repo file is the source of truth for its content.
    test('matches ./scripts/S50downloadmaster-TEMPLATE.sh', () {
      final repo = File('scripts/S50downloadmaster-TEMPLATE.sh').readAsStringSync();
      // The repo copy is CRLF. What ships (and what is deployed) must be LF, or the router's
      // kernel cannot exec the shebang.
      expect(kS50DownloadmasterTemplate, repo.replaceAll('\r\n', '\n'),
          reason: 'lib/s50_template.dart has drifted from scripts/S50downloadmaster-TEMPLATE.sh');
    });

    test('ships LF-only, whatever the repo copy uses', () {
      expect(kS50DownloadmasterTemplate.contains('\r'), isFalse);
    });

    test('carries the shebang and both replacement markers', () {
      expect(kS50DownloadmasterTemplate, startsWith('#!/bin/sh\n'));
      expect(kS50DownloadmasterTemplate, contains('# ********** REPLACEMENT START **********'));
      expect(kS50DownloadmasterTemplate, contains('# ********** REPLACEMENT END **********'));
    });
  });

  group('buildS50Script', () {
    test('inserts the cru lines between the markers, matching the case-arm indent', () {
      final out = buildS50Script([_check, _rotate]);
      expect(out, contains('    # ********** REPLACEMENT START **********\n'
          '    $_check\n'
          '    $_rotate\n'
          '    # ********** REPLACEMENT END **********'));
    });

    test('drops the placeholder comments', () {
      final out = buildS50Script([_check]);
      expect(out, isNot(contains('1 to N cruCheckLine entries')));
      expect(out, isNot(contains('1 to N cruRotateLine entries')));
    });

    test('an empty list leaves the block empty but keeps the markers', () {
      final out = buildS50Script(const []);
      expect(out, contains('    # ********** REPLACEMENT START **********\n'
          '    # ********** REPLACEMENT END **********'));
    });

    // Everything outside the markers belongs to the stock script and must survive untouched.
    test('preserves every line outside the block', () {
      final out = buildS50Script([_check, _rotate]);
      for (final line in [
        '#!/bin/sh',
        'set -u',
        'sleep 10',
        'unset LD_LIBRARY_PATH',
        'PATH=/bin:/sbin:/usr/sbin:/usr/bin:/opt/bin',
        r'APPS_INSTALL_PATH="$APPS_MOUNTED_PATH/$APPS_INSTALL_FOLDER"',
        '  restart|force-reload|stop|firewall-start|firewall-restart|lighttpd-restart|dir-change)',
        'esac',
        'exit 0',
      ]) {
        expect(out, contains(line), reason: 'lost: $line');
      }
    });
  });

  group('extractS50CruLines', () {
    test('a pristine template yields nothing (its block is only comments)', () {
      expect(extractS50CruLines(kS50DownloadmasterTemplate), isEmpty);
    });

    test('round-trips what buildS50Script wrote', () {
      expect(extractS50CruLines(buildS50Script([_check, _rotate])), [_check, _rotate]);
    });

    test('a missing file (empty string) yields nothing rather than throwing', () {
      expect(extractS50CruLines(''), isEmpty);
      expect(extractS50CruLines('some unrelated script\nexit 0\n'), isEmpty);
    });

    test('ignores blank lines and comments inside the block', () {
      final script = buildS50Script([_check]).replaceFirst('    $_check', '    $_check\n\n    # a note');
      expect(extractS50CruLines(script), [_check]);
    });

    // Several watchdogs will share this block in a later release; entries must accumulate.
    test('keeps other slots\' entries when rebuilding', () {
      const otherSlot = 'cru a watchdog_wgc3 "*/5 * * * *" /jffs/scripts/watchdog_wgc3.sh';
      final existing = buildS50Script([otherSlot, _check]);
      final kept = [
        for (final l in extractS50CruLines(existing))
          if (!l.contains('watchdog_wgc1 ')) l,
      ];
      expect(kept, [otherSlot]);
      expect(extractS50CruLines(buildS50Script(kept)), [otherSlot]);
    });
  });
}
