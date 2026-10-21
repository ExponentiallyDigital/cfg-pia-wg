// watchdog_email_layout.dart - the watchdog's alert and test emails: their sections, wording and order.
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see https://www.gnu.org/licenses/.
//
// Copyright (C) 2026 Andrew Newbury.
//
// Moved out of router_watchdog.dart in build 522 (ID-447), unchanged. router_watchdog.dart exports it,
// so everything that used these through that file still does.

import 'review_service.dart' show reviewListingUrl, reviewsGoToAppStore;

// ─── Email layout ────────────────────────────────────────────────────────────────
//
// One layout, two languages: the deployed script writes alert bodies in shell, the app writes the
// test email here in Dart. Everything both must agree on - the section headings and their order,
// the WHAT TO DO steps, the review ask, the sign-off - lives in these constants, and a test asserts
// the generated script reproduces them. Plain text throughout: mailsend-go sends the file verbatim
// and the Merlin path declares text/plain, so markup would render literally. Lines are left
// unwrapped for the reader's mail client to fold.

const String kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.exponentiallydigital.pia_wireguard_cfga&showAllReviews=true';

/// Section headings, in the order every email presents them: the answer first, the action second,
/// the evidence last. WHAT TO DO and ROUTER LOG appear on failures only.
const String kSectionWhatHappened = 'WHAT HAPPENED';
const String kSectionWhatToDo = 'WHAT TO DO';
const String kSectionRouter = 'ROUTER';
const String kSectionHistory = 'HISTORY';
const String kSectionRouterLog = 'ROUTER LOG (last 10 lines)';

/// Each button named here is one the WATCHDOG screen shows, word for word: the email named
/// "CONFIGURE" and "VIEW WATCHDOG LOG" long after both were renamed (ID-263).
const List<String> kEmailWhatToDo = [
  '1. Check your PIA username and password in the app, under WATCHDOG, CREATE/EDIT.',
  '2. Open VIEW ROUTER WATCHDOG LOG in the app for the full history.',
  '3. PIA rate-limits repeated token requests; if the code above is 403, wait 30 minutes before intervening.',
  '4. Review your router log.',
  '5. Is your PIA user account active?',
];

/// The footer on every ALERT email. Not on the test email: that one is sent from the very screen
/// this sentence points at, with the checkbox on it, so telling the reader where to find it would
/// be telling them where they already are.
///
/// Alerts are different. They arrive hours or days later, at an address that may not even be the
/// phone the app is on, and an alert nobody can see how to stop is one people silence at the mail
/// client instead - which loses the next one too.
const String kEmailHowToDisable =
    'Email alerting can be disabled in the app via WATCHDOG, CREATE/EDIT, then deselecting "Enable email alerts".';

/// The review ask near the foot of every email. It follows the phone that deploys the watchdog, since
/// the script is written then (ID-417): Play's listing from Android, the App Store's from iOS, and from
/// iOS before there is an App Store listing, the ask without a link.
String emailReviewLine() {
  const ask = 'If cfg-pia-wg is useful to you, please consider submitting a review';
  if (!reviewsGoToAppStore()) return '$ask by tapping on the home screen link or via $kPlayStoreUrl';
  final url = reviewListingUrl();
  return url == null ? '$ask on the App Store.' : '$ask by tapping on the home screen link or via $url';
}

const List<String> kEmailSignOff = ['Thank you,', 'cfg-pia-wg by Exponentially Digital'];

/// The sentence used when a watchdog has never been saved, so no interval is actually scheduled.
const String kIntervalNotSet = 'Interval: not set, watchdog has yet to be saved and deployed';

/// Assembles the plain-text body from already-rendered `Label: value` rows.
String buildEmailBody({
  required String opening,
  required List<String> whatHappened,
  required List<String> router,
  required String history,
  List<String> whatToDo = const [],
  String? routerLog,
  bool howToDisable = true,
}) {
  final b = StringBuffer()
    ..writeln(opening)
    ..writeln();
  void section(String heading, Iterable<String> rows) {
    b.writeln(heading);
    for (final r in rows) {
      b.writeln(r);
    }
    b.writeln();
  }

  section(kSectionWhatHappened, whatHappened.where((r) => r.isNotEmpty));
  if (whatToDo.isNotEmpty) section(kSectionWhatToDo, whatToDo);
  section(kSectionRouter, router.where((r) => r.isNotEmpty));
  section(kSectionHistory, [history]);
  if (routerLog != null) section(kSectionRouterLog, [routerLog.trimRight()]);
  if (howToDisable) {
    b
      ..writeln(kEmailHowToDisable)
      ..writeln();
  }
  b
    ..writeln(emailReviewLine())
    ..writeln();
  for (final l in kEmailSignOff) {
    b.writeln(l);
  }
  return b.toString();
}

/// Router-side facts every email carries, read in a single round trip by [RouterWatchdog].
/// The deployed script reads the same values for itself.
class RouterEmailFacts {
  final String name, lanIp, model, firmware, time, uptime, sinceDate, okCount, failCount, desc, interval;

  const RouterEmailFacts({
    this.name = '',
    this.lanIp = '',
    this.model = '',
    this.firmware = '',
    this.time = '',
    this.uptime = '',
    this.sinceDate = '',
    this.okCount = '0',
    this.failCount = '0',
    this.desc = '',
    this.interval = '',
  });

  /// Parses the marker-prefixed output of [kEmailFactsCommand]; a short reply leaves the rest empty
  /// rather than throwing, because a missing uptime is no reason to fail a test email.
  factory RouterEmailFacts.parse(String raw) {
    final f = raw.split('\n').map((l) => l.startsWith('|') ? l.substring(1).trim() : l.trim()).toList();
    String at(int i) => i < f.length ? f[i] : '';
    final ddns = at(0), lanHost = at(1), lanIp = at(2);
    return RouterEmailFacts(
      name: [ddns, lanHost].firstWhere((n) => n.isNotEmpty, orElse: () => lanIp),
      lanIp: lanIp,
      model: at(3),
      firmware: at(4),
      time: at(5),
      uptime: at(6),
      sinceDate: at(7),
      okCount: at(8).isEmpty ? '0' : at(8),
      failCount: at(9).isEmpty ? '0' : at(9),
      desc: at(10),
      interval: at(11),
    );
  }

  /// [desc] stands in for the router's own `wgcN_desc` when the caller knows better (ID-049).
  List<String> routerRows(int slot, {String? desc}) => [
        'Name: $name${lanIp.isEmpty || lanIp == name ? '' : ' ($lanIp)'}',
        if (model.isNotEmpty || firmware.isNotEmpty) 'Model: $model, firmware $firmware',
        if (time.isNotEmpty) 'Time: $time',
        if (uptime.isNotEmpty) 'Uptime: $uptime',
        'Watchdog: ${(desc ?? this.desc).isEmpty ? 'region not yet set, configuration pending deployment' : 'wgc$slot:${desc ?? this.desc}'}',
      ];

  /// The same three counters, short enough for the ABOUT screen's width.
  ///
  /// Null when the router has never recorded any, which is the state before a watchdog has ever
  /// run: the screen then shows nothing at all rather than an empty row.
  String? get shortHistoryLine =>
      sinceDate.isEmpty ? null : 'Since $sinceDate: $okCount successful & $failCount unsuccessful reconfigures';

  String get historyLine => 'Since ${sinceDate.isEmpty ? 'today' : sinceDate} this router has recorded '
      '$okCount successful and $failCount failed reconfigurations.';

  /// Read from NVRAM, never from the unsaved dialog, so an email can never state a schedule that is
  /// not actually running.
  String get intervalRow => interval.isEmpty ? kIntervalNotSet : 'Interval: $interval minutes';
}
