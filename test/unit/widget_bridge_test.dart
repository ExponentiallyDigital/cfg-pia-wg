// test/unit/widget_bridge_test.dart - buildWidgetData as pure data, no plugin, no device (ID-376).
//
// The keys asserted here must match android/.../widget/WidgetKeys.kt exactly - that file has no
// Dart equivalent to import, so each one is checked by its literal string, with a comment back to
// the Kotlin constant it stands in for.
import 'package:cfg_pia_wg/widget_bridge.dart';
import 'package:cfg_pia_wg/widget_status.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime kNow = DateTime.utc(2026, 10, 12, 12, 0, 0);

WidgetTunnelInfo tunnel({
  required int slot,
  required String region,
  bool up = true,
  int? handshakeAgeSeconds = 0,
  List<String> pinned = const [],
}) =>
    WidgetTunnelInfo(slot: slot, region: region, up: up, handshakeAgeSeconds: handshakeAgeSeconds, pinnedDeviceNames: pinned);

void main() {
  group('buildWidgetData', () {
    test('every tunnel answering: protected, both rows filled, nobody held offline', () {
      final status = WidgetStatus(
        tunnels: [
          tunnel(slot: 5, region: 'Melbourne, Australia', pinned: ['TABLET']),
          tunnel(slot: 1, region: 'Auckland, New Zealand', pinned: ['LAPTOP', 'PHONE']),
        ],
        checkedAt: kNow,
      );
      final data = buildWidgetData(status, now: kNow);

      expect(data['badge'], 'protected'); // WidgetKeys.BADGE
      expect(data['down_count'], 0); // WidgetKeys.DOWN_COUNT
      expect(data['tunnel_count'], 2); // WidgetKeys.TUNNEL_COUNT
      expect(data['overflow_text'], ''); // WidgetKeys.OVERFLOW_TEXT

      expect(data['tunnel1_region'], 'Melbourne, Australia'); // WidgetKeys.T1_REGION
      expect(data['tunnel1_detail'], 'wgc5 · up · 1 pinned'); // WidgetKeys.T1_DETAIL
      expect(data['tunnel1_guard'], ''); // WidgetKeys.T1_GUARD - answering, nobody held back
      expect(data['tunnel1_state'], 'answering'); // WidgetKeys.T1_STATE

      expect(data['tunnel2_region'], 'Auckland, New Zealand');
      expect(data['tunnel2_detail'], 'wgc1 · up · 2 pinned');
      expect(data['tunnel2_state'], 'answering');

      expect(data['compact_badge_text'], 'Protected'); // WidgetKeys.COMPACT_BADGE_TEXT
      expect(data['compact_detail_text'], '2 tunnels up · 3 pinned'); // WidgetKeys.COMPACT_DETAIL_TEXT
    });

    test('one tunnel down: names who it is holding offline, in both rows and the compact line', () {
      final status = WidgetStatus(
        tunnels: [
          tunnel(slot: 5, region: 'Melbourne, Australia', pinned: ['TABLET']),
          tunnel(slot: 1, region: 'Auckland, New Zealand', up: false, handshakeAgeSeconds: null, pinned: ['DESKTOP']),
        ],
        guardedOfflineDeviceNames: const ['DESKTOP'],
        checkedAt: kNow,
      );
      final data = buildWidgetData(status, now: kNow);

      expect(data['badge'], 'down');
      expect(data['down_count'], 1);
      expect(data['tunnel2_detail'], 'wgc1 · down · 1 pinned');
      expect(data['tunnel2_guard'], 'DESKTOP kept offline by the guard');
      expect(data['tunnel2_state'], 'down');
      expect(data['tunnel1_guard'], ''); // tunnel 1 is answering - nobody named against it

      expect(data['compact_badge_text'], '1 tunnel down');
      expect(data['compact_detail_text'], 'wgc1 down · guard holding 1 device offline');
    });

    test('two devices held offline by the same tunnel are both named, joined', () {
      final status = WidgetStatus(
        tunnels: [
          tunnel(slot: 1, region: 'Auckland, New Zealand', up: false, handshakeAgeSeconds: null, pinned: ['DESKTOP', 'LAPTOP'])
        ],
        guardedOfflineDeviceNames: const ['DESKTOP', 'LAPTOP'],
        checkedAt: kNow,
      );
      final data = buildWidgetData(status, now: kNow);

      expect(data['tunnel1_guard'], 'DESKTOP, LAPTOP kept offline by the guard');
      expect(data['compact_detail_text'], 'wgc1 down · guard holding 2 devices offline');
    });

    test('nothing configured: not checked, both rows empty, no credit given to a non-existent tunnel', () {
      final status = WidgetStatus(tunnels: const [], checkedAt: kNow);
      final data = buildWidgetData(status, now: kNow);

      expect(data['badge'], 'unchecked');
      expect(data['tunnel_count'], 0);
      expect(data['tunnel1_region'], '');
      expect(data['tunnel1_state'], 'unchecked');
      expect(data['tunnel2_state'], 'unchecked');
      expect(data['compact_badge_text'], 'Not checked');
      expect(data['compact_detail_text'], 'No tunnel configured yet');
    });

    test('a third configured tunnel is folded into the overflow line, not a third row', () {
      final status = WidgetStatus(
        tunnels: [
          tunnel(slot: 1, region: 'A'),
          tunnel(slot: 2, region: 'B'),
          tunnel(slot: 3, region: 'C'),
        ],
        checkedAt: kNow,
      );
      final data = buildWidgetData(status, now: kNow);

      expect(data['tunnel_count'], 3);
      expect(data['overflow_text'], '+1 more tunnel');
    });

    test('four configured tunnels pluralise the overflow line', () {
      final status = WidgetStatus(
        tunnels: [for (var s = 1; s <= 4; s++) tunnel(slot: s, region: 'Region $s')],
        checkedAt: kNow,
      );
      final data = buildWidgetData(status, now: kNow);

      expect(data['overflow_text'], '+2 more tunnels');
    });

    // The footer is a CLOCK TIME, not an age. It is baked in when the data is pushed and nothing
    // redraws it until the next push, so an age would go on saying "just now" for ever once the
    // refresh stopped - seen on a real phone, 2026-10-12, beside a reading ten minutes stale.
    group('last_checked_text', () {
      test('a fresh reading gives the time it was taken, which cannot go stale', () {
        final data = buildWidgetData(WidgetStatus(tunnels: const [], checkedAt: kNow), now: kNow);
        expect(data['last_checked_text'], 'Router checked 12:00');
      });

      test('minutes old is still just the time - no "N min ago" to rot', () {
        final data = buildWidgetData(
          WidgetStatus(tunnels: const [], checkedAt: kNow.subtract(const Duration(minutes: 5))),
          now: kNow,
        );
        expect(data['last_checked_text'], 'Router checked 11:55');
      });

      test('single-digit hours and minutes are padded', () {
        final data = buildWidgetData(
          WidgetStatus(tunnels: const [], checkedAt: DateTime.utc(2026, 10, 12, 9, 5)),
          now: DateTime.utc(2026, 10, 12, 9, 5),
        );
        expect(data['last_checked_text'], 'Router checked 09:05');
      });

      test('already an hour old when pushed says so, and that sentence stays true', () {
        final data = buildWidgetData(
          WidgetStatus(tunnels: const [], checkedAt: kNow.subtract(const Duration(hours: 3))),
          now: kNow,
        );
        expect(data['last_checked_text'], 'Not reached since 09:00 · tap to check');
      });

      test('days ago', () {
        final data = buildWidgetData(
          WidgetStatus(tunnels: const [], checkedAt: kNow.subtract(const Duration(days: 2))),
          now: kNow,
        );
        expect(data['last_checked_text'], 'Not reached for 2 d · tap to check');
      });
    });

    group('lastAttemptText', () {
      test('names the time the attempt failed, so "tried and failed" is not "never tried"', () {
        expect(lastAttemptText(DateTime.utc(2026, 10, 12, 19, 45)), 'Could not reach the router at 19:45');
      });

      test('padded the same way as the checked line', () {
        expect(lastAttemptText(DateTime.utc(2026, 10, 12, 7, 4)), 'Could not reach the router at 07:04');
      });

      test('a refresh that needs the app says so - it will not fix itself by waiting', () {
        expect(
            lastAttemptText(DateTime.utc(2026, 10, 12, 20, 1), WidgetAttemptFailure.needsApp), 'Could not refresh at 20:01: open the app');
      });

      test('a fault is not dressed up as being away from home', () {
        expect(lastAttemptText(DateTime.utc(2026, 10, 12, 20, 1), WidgetAttemptFailure.error), 'Refresh failed at 20:01');
      });
    });

    group('attemptFailedFooter', () {
      final at = DateTime.utc(2026, 10, 12, 20, 1);

      test('keeps what the footer said about the last good reading, then the attempt', () {
        expect(attemptFailedFooter('Router checked 19:54', at), 'Router checked 19:54 · could not reach the router at 20:01');
      });

      test('a second failure replaces the first rather than piling up', () {
        final once = attemptFailedFooter('Router checked 19:54', at);
        expect(
          attemptFailedFooter(once, DateTime.utc(2026, 10, 12, 20, 16), WidgetAttemptFailure.needsApp),
          'Router checked 19:54 · could not refresh at 20:16: open the app',
        );
      });

      test('drops the old "tap to check" hint, which the attempt has just answered', () {
        expect(
          attemptFailedFooter('Not reached since 18:00 · tap to check', at),
          'Not reached since 18:00 · could not reach the router at 20:01',
        );
      });

      test('with nothing to keep, the attempt stands alone and keeps its capital', () {
        expect(attemptFailedFooter('', at, WidgetAttemptFailure.error), 'Refresh failed at 20:01');
      });
    });

    test('can_refresh defaults to false - no key exists until a later slice', () {
      final data = buildWidgetData(WidgetStatus(tunnels: const [], checkedAt: kNow), now: kNow);
      expect(data['can_refresh'], false); // WidgetKeys.CAN_REFRESH
    });

    test('can_refresh true is passed straight through', () {
      final data = buildWidgetData(WidgetStatus(tunnels: const [], checkedAt: kNow), now: kNow, canRefresh: true);
      expect(data['can_refresh'], true);
    });
  });
}
