// widget_bridge.dart - turns WidgetStatus into what the Android widgets read (ID-376).
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
// [buildWidgetData] is the pure half - a Map whose keys mirror WidgetKeys.kt in
// android/.../widget/WidgetKeys.kt line for line, so a drifted key fails a test rather than
// drawing a blank widget. [pushWidgetStatus] is the one line of this file with no test: it hands
// that map to the home_widget plugin, which has nothing to read without a real widget on a real
// home screen.
//
// Text here is deliberately plain about what is not yet read: a tunnel's row says it is "down",
// not how long or whether the watchdog is rebuilding it, because that is not part of
// WidgetTunnelInfo yet (ID-376's later slices). Saying more than the data supports would be the
// same mistake --doh-url's test made, see check-claims.sh's own header.

import 'package:home_widget/home_widget.dart';

import 'widget_status.dart';

/// Must match `TunnelsWidgetProvider` and `CompactWidgetProvider`'s actual Kotlin package in
/// android/.../widget/ - `home_widget`'s plain `androidName` resolves against the application id
/// alone (`<applicationId>.<androidName>`), which misses a provider in a subpackage; passing the
/// full name here, as `qualifiedAndroidName`, is what makes it find these two at all.
const String kTunnelsWidgetQualifiedName = 'com.exponentiallydigital.pia_wireguard_cfga.widget.TunnelsWidgetProvider';
const String kCompactWidgetQualifiedName = 'com.exponentiallydigital.pia_wireguard_cfga.widget.CompactWidgetProvider';

String _pluralTunnels(int n) => n == 1 ? '1 tunnel' : '$n tunnels';
String _pluralPinned(int n) => n == 1 ? '1 pinned' : '$n pinned';

/// `WidgetTunnelInfo.region · wgcN · up/down · N pinned`, the row's second line. No duration, no
/// watchdog state: [WidgetStatus] does not carry either yet.
String _tunnelDetail(WidgetTunnelInfo t) {
  final pinned = t.pinnedDeviceNames.length;
  final state = switch ((t.answering, t.up)) {
    (true, _) => 'up',
    (_, true) => 'not answering',
    _ => 'down',
  };
  return 'wgc${t.slot} · $state · ${_pluralPinned(pinned)}';
}

/// "DESKTOP kept offline by the guard", or "DESKTOP, TABLET kept offline by the guard" - empty
/// when the tunnel is answering, since nobody is being held back.
String _guardLine(WidgetTunnelInfo t) {
  if (t.answering || t.pinnedDeviceNames.isEmpty) return '';
  return '${t.pinnedDeviceNames.join(', ')} kept offline by the guard';
}

/// Two digits, for a clock time.
String _two(int v) => v < 10 ? '0$v' : '$v';

/// When the router was last read, as a **clock time, not an age**.
///
/// The mock-up said "Router checked 1 min ago", and that was wrong for a widget: this text is
/// baked in when the data is pushed and nothing redraws it until the next push, so a widget that
/// stops refreshing goes on saying "just now" for ever - which is precisely when the user most
/// needs to be told otherwise (seen on a real phone, 2026-10-12, reading "just now" beside a
/// reading that was by then 10 minutes stale and a tunnel out of date). A clock time cannot rot:
/// "Checked 19:29" is as true an hour later as it was when written, and the reader can judge it.
///
/// [now] is still taken, because when the reading was ALREADY old at push time that is worth
/// saying outright, and that sentence is true when it is written.
String _lastCheckedText(DateTime checkedAt, DateTime now) {
  final at = '${_two(checkedAt.hour)}:${_two(checkedAt.minute)}';
  final age = now.difference(checkedAt);
  if (age.inHours >= 24) return 'Not reached for ${age.inDays} d · tap to check';
  if (age.inHours >= 1) return 'Not reached since $at · tap to check';
  return 'Router checked $at';
}

String _compactBadgeText(WidgetStatus status) {
  switch (status.badge) {
    case WidgetBadge.protected:
      return 'Protected';
    case WidgetBadge.tunnelDown:
      final down = status.tunnels.where((t) => !t.answering).length;
      return down == 1 ? '1 tunnel down' : '$down tunnels down';
    case WidgetBadge.notChecked:
      return 'Not checked';
  }
}

String _compactDetailText(WidgetStatus status) {
  switch (status.badge) {
    case WidgetBadge.protected:
      final pinned = status.tunnels.fold<int>(0, (sum, t) => sum + t.pinnedDeviceNames.length);
      return '${_pluralTunnels(status.tunnels.length)} up · ${_pluralPinned(pinned)}';
    case WidgetBadge.tunnelDown:
      final down = status.tunnels.firstWhere((t) => !t.answering);
      final offline = status.guardedOfflineDeviceNames.length;
      return 'wgc${down.slot} down · guard holding ${offline == 1 ? '1 device' : '$offline devices'} offline';
    case WidgetBadge.notChecked:
      return 'No tunnel configured yet';
  }
}

/// Why a refresh left the tunnel rows as they were. Each has its own footer text, because each
/// asks something different of the person reading it: [unreachable] usually just means "not at
/// home", [needsApp] will not fix itself until the app is opened, and [error] is a fault.
enum WidgetAttemptFailure {
  /// Tried, and could not reach the router or get an answer from it.
  unreachable,

  /// Did not try: the app has to be opened first - no router address or login to use the key
  /// with, or no recorded host key to check the router against.
  needsApp,

  /// Something failed that is neither of those, such as the phone's key store.
  error,
}

/// The footer for one refresh that left the tunnel rows as they were. Silent to the user in the
/// sense that matters - no notification, nothing to dismiss - but not invisible, which is
/// different and was the mistake: a refresh that failed left no trace anywhere, so "it tried and
/// could not reach the router" and "it never tried at all" looked identical on the phone and
/// neither could be told from the other (2026-10-12). The last good reading is kept and still
/// shown above this.
String lastAttemptText(DateTime attemptedAt, [WidgetAttemptFailure why = WidgetAttemptFailure.unreachable]) {
  final at = '${_two(attemptedAt.hour)}:${_two(attemptedAt.minute)}';
  switch (why) {
    case WidgetAttemptFailure.unreachable:
      return 'Could not reach the router at $at';
    case WidgetAttemptFailure.needsApp:
      return 'Could not refresh at $at: open the app';
    case WidgetAttemptFailure.error:
      return 'Refresh failed at $at';
  }
}

/// The whole footer after a failed attempt: whatever [previous] said about the last good reading,
/// then the attempt. Only the part before the first ' · ' is kept, so a run of failures replaces
/// the attempt rather than piling them up.
String attemptFailedFooter(String previous, DateTime attemptedAt, [WidgetAttemptFailure why = WidgetAttemptFailure.unreachable]) {
  final kept = previous.split(' · ').first.trim();
  final attempt = lastAttemptText(attemptedAt, why);
  return kept.isEmpty ? attempt : '$kept · ${attempt[0].toLowerCase()}${attempt.substring(1)}';
}

/// The keys and values both widgets read, from [status] and [now] (the device clock, passed in
/// for the same reason [buildWidgetStatus] takes [WidgetStatus.checkedAt] rather than reading it
/// itself). [canRefresh] is false until ID-376's key exists (a later slice) - until then the
/// refresh button is shown, but plain, matching the mock-up's two footer styles.
///
/// Keys are written as plain strings here, deliberately not read from WidgetKeys.kt - that file
/// is Kotlin, out of reach from Dart, and is the thing this function's keys are tested against.
Map<String, Object> buildWidgetData(WidgetStatus status, {required DateTime now, bool canRefresh = false}) {
  String badgeName() {
    switch (status.badge) {
      case WidgetBadge.protected:
        return 'protected';
      case WidgetBadge.tunnelDown:
        return 'down';
      case WidgetBadge.notChecked:
        return 'unchecked';
    }
  }

  // Only "answering" and "down" ever come from here - "unchecked" (the dim dot) is Kotlin's own
  // default for a row with no data at all, below [WidgetStatus.tunnels]'s actual length.
  String stateOf(WidgetTunnelInfo t) => t.answering ? 'answering' : 'down';

  final more = status.tunnels.length - 2;
  final data = <String, Object>{
    'badge': badgeName(),
    'down_count': status.tunnels.where((t) => !t.answering).length,
    'tunnel_count': status.tunnels.length,
    'overflow_text': more > 0 ? '+$more more tunnel${more == 1 ? '' : 's'}' : '',
    'last_checked_text': _lastCheckedText(status.checkedAt, now),
    'can_refresh': canRefresh,
    'compact_badge_text': _compactBadgeText(status),
    'compact_detail_text': _compactDetailText(status),
  };

  void writeRow(int n, WidgetTunnelInfo? t) {
    data['tunnel${n}_region'] = t?.region ?? '';
    data['tunnel${n}_detail'] = t == null ? '' : _tunnelDetail(t);
    data['tunnel${n}_guard'] = t == null ? '' : _guardLine(t);
    data['tunnel${n}_state'] = t == null ? 'unchecked' : stateOf(t);
  }

  writeRow(1, status.tunnels.isNotEmpty ? status.tunnels[0] : null);
  writeRow(2, status.tunnels.length > 1 ? status.tunnels[1] : null);

  return data;
}

/// Writes [data] to both widgets' SharedPreferences and asks Android to redraw them. Nothing here
/// is tested - there is no widget to read it without a real home screen - see [buildWidgetData]
/// for the half that is.
Future<void> pushWidgetStatus(WidgetStatus status, {required DateTime now, bool canRefresh = false}) async {
  final data = buildWidgetData(status, now: now, canRefresh: canRefresh);
  for (final entry in data.entries) {
    final value = entry.value;
    if (value is String) {
      await HomeWidget.saveWidgetData<String>(entry.key, value);
    } else if (value is int) {
      await HomeWidget.saveWidgetData<int>(entry.key, value);
    } else if (value is bool) {
      await HomeWidget.saveWidgetData<bool>(entry.key, value);
    }
  }
  await HomeWidget.updateWidget(qualifiedAndroidName: kTunnelsWidgetQualifiedName);
  await HomeWidget.updateWidget(qualifiedAndroidName: kCompactWidgetQualifiedName);
}

/// Records that a refresh ran at [attemptedAt] and could not reach the router, **without touching
/// the tunnel rows**: the last good reading is still the best thing to show, it is simply not new.
/// The footer keeps whatever it said about that reading and gains the failed attempt after it, so
/// the two can be told apart at a glance.
///
/// Untested for the same reason as [pushWidgetStatus] - there is no widget to read it without a
/// real home screen. The text it composes is [attemptFailedFooter], which is tested.
Future<void> pushWidgetAttemptFailed(DateTime attemptedAt, [WidgetAttemptFailure why = WidgetAttemptFailure.unreachable]) async {
  final previous = (await HomeWidget.getWidgetData<String>('last_checked_text')) ?? '';
  await HomeWidget.saveWidgetData<String>('last_checked_text', attemptFailedFooter(previous, attemptedAt, why));
  await HomeWidget.updateWidget(qualifiedAndroidName: kTunnelsWidgetQualifiedName);
  await HomeWidget.updateWidget(qualifiedAndroidName: kCompactWidgetQualifiedName);
}
