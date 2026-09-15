// watchdog_email.dart - a watchdog's email settings as one set, and where the form pre-fills them from (ID-050).
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
// Typing six email fields for every watchdog is tedious even with copy and paste, and some autofill
// providers, Google's included, will not fill several fields at once. So a new watchdog's form starts from
// settings the app already has: the slot's own, then those entered this session, then the lowest-numbered
// other slot that has some. They are held in the session like the router and PIA credentials, and wiped
// when the app exits. The router's NVRAM is only read after a router login, and the app's docs already say
// watchdog credentials are written to the router.

/// A watchdog's six email fields, which belong together: one SMTP account, one sender, one recipient.
class EmailSettings {
  final String from, to, subject, smtpServer, smtpUser, smtpPass;

  const EmailSettings({
    this.from = '',
    this.to = '',
    this.subject = '',
    this.smtpServer = '',
    this.smtpUser = '',
    this.smtpPass = '',
  });

  /// No SMTP server and no recipient: nothing worth pre-filling from.
  bool get isEmpty => smtpServer.trim().isEmpty && to.trim().isEmpty;
}

/// The keys under `wgcN_wd_`, in the order [kEmailSettingsCommand] prints them.
const List<String> kEmailSettingKeys = ['email_from', 'email_to', 'email_subject', 'smtp_server', 'smtp_user', 'smtp_pass'];

/// Every slot's email settings in one round trip, one `slot<TAB>key<TAB>value` line each. `loadConfig` reads
/// a slot key by key; doing that for four more slots would be two dozen more SSH round trips.
const String kEmailSettingsCommand = r'for s in 1 2 3 4 5; do '
    r'for k in email_from email_to email_subject smtp_server smtp_user smtp_pass; do '
    r'''printf '%s\t%s\t%s\n' "$s" "$k" "$(nvram get "wgc${s}_wd_$k")"; done; done''';

/// Parses [kEmailSettingsCommand]'s output. A value may itself contain a tab; everything after the second
/// tab is the value.
Map<int, EmailSettings> parseEmailSettings(String output) {
  final bySlot = <int, Map<String, String>>{};
  for (final raw in output.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    final first = line.indexOf('\t');
    final second = first < 0 ? -1 : line.indexOf('\t', first + 1);
    final slot = first < 0 ? null : int.tryParse(line.substring(0, first));
    if (second < 0 || slot == null) continue;
    (bySlot[slot] ??= {})[line.substring(first + 1, second)] = line.substring(second + 1);
  }
  return {
    for (final e in bySlot.entries)
      e.key: EmailSettings(
        from: e.value['email_from'] ?? '',
        to: e.value['email_to'] ?? '',
        subject: e.value['email_subject'] ?? '',
        smtpServer: e.value['smtp_server'] ?? '',
        smtpUser: e.value['smtp_user'] ?? '',
        smtpPass: e.value['smtp_pass'] ?? '',
      ),
  };
}

/// Where the watchdog form for [slot] pre-fills its email fields from: the slot's own settings, then those
/// entered this session, then the lowest-numbered other slot with some. Null when there are none anywhere,
/// and the user types them. A set is taken whole - never a server from one slot and a password from another.
EmailSettings? firstEmailSettings({
  required int slot,
  EmailSettings? own,
  EmailSettings? session,
  Map<int, EmailSettings> others = const {},
}) {
  if (own != null && !own.isEmpty) return own;
  if (session != null && !session.isEmpty) return session;
  for (final s in others.keys.where((s) => s != slot).toList()..sort()) {
    if (!others[s]!.isEmpty) return others[s];
  }
  return null;
}
