// router_watchdog.dart - Self-healing VPN watchdog deployment & control for ASUS Merlin routers.
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

import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';

import 'firmware.dart';
import 'router_slot_service.dart' show RouterSlotService, fetchSlotLabel, slotDescFor;
import 's50_template.dart';

// ─── PIA negotiation endpoints (mirrored from pia_service.dart) ─────────────────
// Kept in one place so the Bash re-negotiation and the Dart app stay in sync.
const String kPiaServerListUrl = 'https://serverlist.piaservers.net/vpninfo/servers/v6';
const String kPiaTokenUrl = 'https://www.privateinternetaccess.com/gtoken/generateToken';

/// Where the router caches the PIA CA. Under the app's own directory so a stale copy can be
/// deleted from the ABOUT screen without touching anything else in /jffs.
const String kPiaCaCertPath = '$kRouterAppDir/pia_ca.rsa.4096.crt';

const String kPiaCaCertUrl = 'https://raw.githubusercontent.com/pia-foss/manual-connections/master/ca.rsa.4096.crt';

// Syslog tag used by every router-side log line (Bash scripts + Dart deploy/delete).
const String kWatchdogLogTag = 'cfg-pia-wg';

/// The most a single `logger` call should carry. BusyBox syslogd truncates a long message - the
/// SMTP probe output was cut mid-word in the router log - and the limit is not worth discovering
/// per-firmware, so keep each line comfortably short and let [splitForSyslog] number the parts.
const int kSyslogChunkChars = 200;

/// Splits [message] into pieces small enough for syslog to keep whole.
///
/// One piece comes back unchanged; several come back prefixed `(n/total)` so the router log can be
/// reassembled by eye. Breaks at the last `|` or space near the limit: `|` is what the diagnostics
/// use to join the lines of a command's output, so parts land on line boundaries where they can.
List<String> splitForSyslog(String message, {int max = kSyslogChunkChars}) {
  if (message.length <= max) return [message];
  final pieces = <String>[];
  var rest = message;
  while (rest.isNotEmpty) {
    if (rest.length <= max) {
      pieces.add(rest);
      break;
    }
    // Prefer a line boundary, then a word boundary.
    var cut = rest.lastIndexOf('|', max);
    if (cut > 0) cut += 1; // keep the separator with the part it ends
    if (cut < max - (max ~/ 4)) cut = rest.lastIndexOf(' ', max);
    // Neither near the limit: a solid run (a URL, base64), so cut it square.
    if (cut < max - (max ~/ 4)) cut = max;
    pieces.add(rest.substring(0, cut).trimRight());
    rest = rest.substring(cut).trimLeft();
  }
  final total = pieces.length;
  return [for (var i = 0; i < total; i++) '(${i + 1}/$total) ${pieces[i]}'];
}

/// The `logger` invocation(s) for [message], joined so a split message still costs one SSH call.
String buildLoggerCommand(String message) =>
    splitForSyslog(message).map((p) => 'logger -t $kWatchdogLogTag ${shellSingleQuote(p)}').join('; ');

// ─── Validation helpers (pure) ──────────────────────────────────────────────────

// Validates a dotted-quad IPv4 address (0-255 per octet).
bool isValidIpv4(String ip) {
  final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(ip.trim());
  if (m == null) return false;
  for (var i = 1; i <= 4; i++) {
    if (int.parse(m.group(i)!) > 255) return false;
  }
  return true;
}

// Loose RFC-5322 email check for UI validation.
bool isValidEmail(String email) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());

// Parses the router status file timestamp ("YYYY-MM-DD HH:MM:SS") to a DateTime.
DateTime? parseLastPing(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return null;
  // The status file leads with an epoch so the script can compute an outage duration; the
  // human-readable stamp follows it. Older files hold the stamp alone, so the prefix is optional.
  final epoch = RegExp(r'^\d{9,}\s+').firstMatch(t);
  if (epoch != null) t = t.substring(epoch.end);
  return DateTime.tryParse(t);
}

// POSIX single-quote shell escaping: wraps in '...' and escapes embedded quotes.
String shellSingleQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

// ─── Models ─────────────────────────────────────────────────────────────────────

class WatchdogConfig {
  final int slotIndex; // WireGuard slot (1-5)
  final int cronIntervalMinutes; // how often the check runs
  final String primaryIp, secondaryIp; // ping targets (both required)
  final String piaUsername, piaPassword; // stored in GLOBAL nvram, reused from main-screen login
  final bool emailAlertsEnabled;
  final String emailFrom, emailTo, emailSubject;
  final String smtpServer; // host:port
  final String smtpUsername, smtpPassword;

  const WatchdogConfig({
    required this.slotIndex,
    this.cronIntervalMinutes = 5,
    required this.primaryIp,
    required this.secondaryIp,
    this.piaUsername = '',
    this.piaPassword = '',
    this.emailAlertsEnabled = false,
    this.emailFrom = '',
    this.emailTo = '',
    this.emailSubject = '',
    this.smtpServer = '',
    this.smtpUsername = '',
    this.smtpPassword = '',
  });

  // Human-readable validation errors; an empty list means the config is valid.
  List<String> validate() {
    final errors = <String>[];
    if (cronIntervalMinutes <= 0) {
      errors.add('Check interval must be a positive number of minutes.');
    }
    if (primaryIp.trim().isEmpty) {
      errors.add('Primary ping IP is required.');
    } else if (!isValidIpv4(primaryIp)) {
      errors.add('Primary ping IP is not a valid IPv4 address.');
    }
    if (secondaryIp.trim().isEmpty) {
      errors.add('Secondary ping IP is required.');
    } else if (!isValidIpv4(secondaryIp)) {
      errors.add('Secondary ping IP is not a valid IPv4 address.');
    }
    if (piaUsername.trim().isEmpty) {
      errors.add('PIA username is required.');
    }
    if (piaPassword.isEmpty) {
      errors.add('PIA password is required.');
    }
    if (emailAlertsEnabled) {
      if (emailFrom.trim().isEmpty) {
        errors.add('Email "From" is required when email alerts are enabled.');
      } else if (!isValidEmail(emailFrom)) {
        errors.add('Email "From" is not a valid address.');
      }
      if (emailTo.trim().isEmpty) {
        errors.add('Email "To" is required when email alerts are enabled.');
      } else if (!isValidEmail(emailTo)) {
        errors.add('Email "To" is not a valid address.');
      }
      if (emailSubject.trim().isEmpty) {
        errors.add('Email subject is required when email alerts are enabled.');
      }
      if (smtpServer.trim().isEmpty) {
        errors.add('SMTP server (host:port) is required when email alerts are enabled.');
      } else if (!smtpServer.contains(':')) {
        errors.add('SMTP server must be in host:port format.');
      }
      if (smtpUsername.trim().isEmpty) {
        errors.add('SMTP username is required when email alerts are enabled.');
      }
      if (smtpPassword.isEmpty) {
        errors.add('SMTP password is required when email alerts are enabled.');
      }
    }
    return errors;
  }

  // Per-slot watchdog nvram keys (wgcN_wd_*). PIA creds are global and written separately.
  Map<String, String> toNvram() => {
        'wgc${slotIndex}_wd_check_interval': '$cronIntervalMinutes',
        'wgc${slotIndex}_wd_primary_ip': primaryIp.trim(),
        'wgc${slotIndex}_wd_secondary_ip': secondaryIp.trim(),
        'wgc${slotIndex}_wd_email_enabled': emailAlertsEnabled ? '1' : '0',
        'wgc${slotIndex}_wd_email_from': emailFrom.trim(),
        'wgc${slotIndex}_wd_email_to': emailTo.trim(),
        'wgc${slotIndex}_wd_email_subject': emailSubject.trim(),
        'wgc${slotIndex}_wd_smtp_server': smtpServer.trim(),
        'wgc${slotIndex}_wd_smtp_user': smtpUsername.trim(),
        'wgc${slotIndex}_wd_smtp_pass': smtpPassword,
      };

  // Rebuilds a config from a map of nvram values (per-slot wgcN_wd_* + global PIA keys).
  static WatchdogConfig fromNvram(int slot, Map<String, String> nv) {
    String g(String k) => nv['wgc${slot}_wd_$k'] ?? '';
    final interval = int.tryParse(g('check_interval'));
    return WatchdogConfig(
      slotIndex: slot,
      cronIntervalMinutes: (interval == null || interval <= 0) ? 5 : interval,
      primaryIp: g('primary_ip'),
      secondaryIp: g('secondary_ip'),
      piaUsername: nv['cfg_pia_wg_user'] ?? '',
      piaPassword: nv['cfg_pia_wg_password'] ?? '',
      emailAlertsEnabled: g('email_enabled') == '1',
      emailFrom: g('email_from'),
      emailTo: g('email_to'),
      emailSubject: g('email_subject'),
      smtpServer: g('smtp_server'),
      smtpUsername: g('smtp_user'),
      smtpPassword: g('smtp_pass'),
    );
  }

  WatchdogConfig copyWith({
    int? slotIndex,
    int? cronIntervalMinutes,
    String? primaryIp,
    String? secondaryIp,
    String? piaUsername,
    String? piaPassword,
    bool? emailAlertsEnabled,
    String? emailFrom,
    String? emailTo,
    String? emailSubject,
    String? smtpServer,
    String? smtpUsername,
    String? smtpPassword,
  }) =>
      WatchdogConfig(
        slotIndex: slotIndex ?? this.slotIndex,
        cronIntervalMinutes: cronIntervalMinutes ?? this.cronIntervalMinutes,
        primaryIp: primaryIp ?? this.primaryIp,
        secondaryIp: secondaryIp ?? this.secondaryIp,
        piaUsername: piaUsername ?? this.piaUsername,
        piaPassword: piaPassword ?? this.piaPassword,
        emailAlertsEnabled: emailAlertsEnabled ?? this.emailAlertsEnabled,
        emailFrom: emailFrom ?? this.emailFrom,
        emailTo: emailTo ?? this.emailTo,
        emailSubject: emailSubject ?? this.emailSubject,
        smtpServer: smtpServer ?? this.smtpServer,
        smtpUsername: smtpUsername ?? this.smtpUsername,
        smtpPassword: smtpPassword ?? this.smtpPassword,
      );

  // Splits "host:port" on the LAST colon; defaults the port to 465 (implicit TLS).
  (String host, int port) get smtpHostPort {
    final idx = smtpServer.lastIndexOf(':');
    if (idx < 0) return (smtpServer.trim(), 465);
    final host = smtpServer.substring(0, idx).trim();
    final port = int.tryParse(smtpServer.substring(idx + 1).trim()) ?? 465;
    return (host, port);
  }
}

class WatchdogStatus {
  final bool isEnabled; // derived from `cru l`, never stored
  final DateTime? lastSuccessfulPing; // null if none recorded yet

  const WatchdogStatus({required this.isEnabled, this.lastSuccessfulPing});
}

// ─── Pure Bash-template generators ───────────────────────────────────────────────

// `cat > '<path>' <<'EOF'` heredoc write. The single-quoted tag prevents the router
// shell from expanding anything in the body during deployment.
/// Dropbear's `MAX_CMD_LEN`. A single exec request longer than this is refused outright and the
/// connection closes - the watchdog script crossed it at 9055 bytes and every deploy died with
/// "SSH connection closed" after the slot had already been enabled.
const int kMaxSshCommandBytes = 9000;

/// Splits a file write into heredoc commands that each stay well clear of [kMaxSshCommandBytes].
///
/// The first truncates (`>`), the rest append (`>>`), so the script can grow without ever
/// approaching the limit again. Splitting only ever happens at a line boundary.
List<String> heredocWriteCommands(String path, String body, {int maxBytes = 4000}) {
  final b = body.endsWith('\n') ? body : '$body\n';
  final lines = b.split('\n')..removeLast(); // trailing '' from the final newline
  final commands = <String>[];
  final buf = StringBuffer();
  var first = true;

  void flush() {
    if (buf.isEmpty) return;
    commands.add("cat ${first ? '>' : '>>'} '$path' <<'WATCHDOG_EOF'\n${buf}WATCHDOG_EOF\n");
    first = false;
    buf.clear();
  }

  for (final line in lines) {
    if (buf.length + line.length + 1 > maxBytes) flush();
    buf.writeln(line);
  }
  flush();
  return commands.isEmpty ? ["cat > '$path' <<'WATCHDOG_EOF'\nWATCHDOG_EOF\n"] : commands;
}

String heredocWrite(String path, String body) {
  final b = body.endsWith('\n') ? body : '$body\n';
  // The delimiter needs its own newline-terminated line. Without the trailing newline BusyBox
  // ash reaches EOF before it recognises the delimiter and writes WATCHDOG_EOF into the file -
  // which is how it ended up as the last line of S50downloadmaster and inside the test email.
  return "cat > '$path' <<'WATCHDOG_EOF'\n${b}WATCHDOG_EOF\n";
}

// The watchdog check cron job line (added via `cru a`).
String buildCronCheckLine(int slot, int intervalMin) =>
    'cru a watchdog_wgc$slot "*/$intervalMin * * * *" ${watchdogScriptPath(slot)}';

// The daily log-rotation cron job line.
String buildCronRotateLine(int slot) => 'cru a watchdog_log_rotate_wgc$slot "0 0 * * *" '
    '"mv /tmp/watchdog_wgc$slot.log /tmp/watchdog_wgc$slot.log.old && touch /tmp/watchdog_wgc$slot.log"';

// The two cru lines appended to /jffs/scripts/services-start for reboot persistence.
String buildServicesStartBlock(int slot, int intervalMin) =>
    '${buildCronCheckLine(slot, intervalMin)}\n${buildCronRotateLine(slot)}\n';

// RFC-822 date for the one-off "Test Email"
String _rfc2822Date(DateTime dt) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final utc = dt.toUtc();
  return '${days[utc.weekday - 1]}, '
      '${utc.day.toString().padLeft(2, '0')} '
      '${months[utc.month - 1]} '
      '${utc.year} '
      '${utc.hour.toString().padLeft(2, '0')}:'
      '${utc.minute.toString().padLeft(2, '0')}:'
      '${utc.second.toString().padLeft(2, '0')} +0000';
}

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

const List<String> kEmailWhatToDo = [
  '1. Check your PIA username and password in the app, under WATCHDOG then CONFIGURE.',
  '2. Open VIEW WATCHDOG LOG in the app for the full history.',
  '3. PIA rate-limits repeated token requests; if the code above is 403, wait 30 minutes before intervening.',
  '4. Is your PIA billing account active?',
];

const String kEmailReviewLine = 'If cfg-pia-wg is useful to you, please consider submitting a review '
    'by tapping on the home screen link or via $kPlayStoreUrl';

const List<String> kEmailSignOff = ['Thank you,', 'cfg-pia-wg by Exponentially Digital'];

/// The sentence used when a watchdog has never been saved, so no interval is actually scheduled.
const String kIntervalNotSet = 'Interval: not set, watchdog has yet to be saved and deployed.';

/// Assembles the plain-text body from already-rendered `Label: value` rows.
String buildEmailBody({
  required String opening,
  required List<String> whatHappened,
  required List<String> router,
  required String history,
  List<String> whatToDo = const [],
  String? routerLog,
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
  b
    ..writeln(kEmailReviewLine)
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
    final f = raw
        .split('\n')
        .map((l) => l.startsWith('|') ? l.substring(1).trim() : l.trim())
        .toList();
    String at(int i) => i < f.length ? f[i] : '';
    final ddns = at(0), lanHost = at(1), lanIp = at(2);
    return RouterEmailFacts(
      name: ddns.isNotEmpty ? ddns : (lanHost.isNotEmpty ? lanHost : lanIp),
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

  List<String> routerRows(int slot) => [
        'Name: $name${lanIp.isEmpty || lanIp == name ? '' : ' ($lanIp)'}',
        if (model.isNotEmpty || firmware.isNotEmpty) 'Model: $model, firmware $firmware',
        if (time.isNotEmpty) 'Time: $time',
        if (uptime.isNotEmpty) 'Uptime: $uptime',
        'Watchdog: ${desc.isEmpty ? 'region not yet set, configuration pending deployment' : 'wgc$slot:$desc'}',
      ];

  String get historyLine => 'Since ${sinceDate.isEmpty ? 'today' : sinceDate} this router has recorded '
      '$okCount successful and $failCount failed reconfigurations.';

  /// Read from NVRAM, never from the unsaved dialog, so an email can never state a schedule that is
  /// not actually running.
  String get intervalRow => interval.isEmpty ? kIntervalNotSet : 'Interval: $interval minutes';
}

/// Seconds to wait before the next reconfigure attempt, indexed by how many consecutive attempts
/// have already failed: the 1st failure waits 2 minutes, the 2nd 4, then 8, 16, 30, 60, and every
/// one after that the 90-minute cap.
///
/// PIA answers HTTP 403 after sustained re-registration and clears on its own after tens of
/// minutes. Retrying every 120 s indefinitely is what provokes and prolongs that - with two
/// watchdogs it was a request a minute between them. A single failure, which is the common case,
/// is exactly as responsive as it was.
const List<int> kBackoffLadder = [120, 240, 480, 960, 1800, 3600, 5400];

/// The wait after [failures] consecutive failed attempts. The last rung is the cap, and 0 failures
/// answers the first rung so a caller never has to special-case it.
int backoffSeconds(int failures) => kBackoffLadder[failures.clamp(1, kBackoffLadder.length) - 1];

/// The ladder as a POSIX `case`, so the script and [backoffSeconds] cannot drift apart. Kept as a
/// lookup rather than arithmetic: the rungs are not a clean doubling past 16 minutes, and a table
/// is the one form that stays obvious in `sh`.
String buildBackoffCase() {
  final arms = <String>[];
  for (var i = 0; i < kBackoffLadder.length - 1; i++) {
    arms.add('    ${i == 0 ? '0|1' : '${i + 1}'}) echo ${kBackoffLadder[i]} ;;');
  }
  arms.add('    *) echo ${kBackoffLadder.last} ;;');
  return 'backoff_for() {\n  case "\$1" in\n${arms.join('\n')}\n  esac\n}';
}

/// Seeds the lifetime counters the moment the app first touches a router, so `Since <date>` is the
/// date the user actually started rather than the date of their first reconfigure.
const String kSeedCountersCommand = '[ -n "\$(nvram get cfg_pia_wg_sdate)" ] || { '
    "nvram set cfg_pia_wg_sdate=\"\$(date '+%Y-%m-%d')\"; "
    'nvram set cfg_pia_wg_reconfig_ok=0; nvram set cfg_pia_wg_reconfig_fail=0; nvram commit; }';

/// One round trip for every router fact an email needs. Each field is marker-prefixed so an empty
/// one survives the trim that [RouterWatchdog._run] applies.
String kEmailFactsCommand(int slot) => "printf '|%s\\n' "
    '"\$(nvram get ddns_hostname_x)" "\$(nvram get lan_hostname)" "\$(nvram get lan_ipaddr)" '
    '"\$(nvram get productid)" "\$(nvram get buildno)_\$(nvram get extendno)" '
    '"\$(date \'+%Y-%m-%d %H:%M:%S %Z\')" "\$(uptime | sed \'s/^ *//\')" '
    '"\$(nvram get cfg_pia_wg_sdate)" "\$(nvram get cfg_pia_wg_reconfig_ok)" '
    '"\$(nvram get cfg_pia_wg_reconfig_fail)" '
    '"\$(nvram get wgc${slot}_desc)" "\$(nvram get wgc${slot}_wd_check_interval)"';

/// `<your subject>: STATUS - wgcN:region`. The subject field stays the user's, so anyone who
/// changed it from the `cfg-pia-wg alert` default keeps their own prefix and their mail rules.
String buildMailSubject(WatchdogConfig c, {required String status, String desc = ''}) {
  final prefix = c.emailSubject.trim().isEmpty ? 'cfg-pia-wg alert' : c.emailSubject.trim();
  final slot = desc.isEmpty ? 'wgc${c.slotIndex}' : 'wgc${c.slotIndex}:$desc';
  return '$prefix: $status - $slot';
}

/// The RFC-822 headers BusyBox sendmail needs inline. mailsend-go builds its own from flags.
String buildMailHeaders(WatchdogConfig c, {required String subject, DateTime? now}) {
  final t = now ?? DateTime.now();
  final (host, _) = c.smtpHostPort;
  return 'From: ${c.emailFrom}\n'
      'To: ${c.emailTo}\n'
      'Subject: $subject\n'
      'Date: ${_rfc2822Date(t)}\n'
      'Message-ID: <${t.millisecondsSinceEpoch ~/ 1000}.${c.slotIndex}@$host>\n'
      'MIME-Version: 1.0\n'
      'Content-Type: text/plain; charset=utf-8\n'
      '\n';
}

// The mailsend-go implicit-TLS command used on stock, where BusyBox sendmail is not viable.
// Credentials on the command line are an accepted risk here (see .claude/CONTEXT.md 4.12).
// No -debug: it writes the whole argument parse to stderr, which buried the actual error in the
// captured output. Nothing else here differs from scripts/mailsend-go_test.sh.
String buildMailsendGoCommand(String host, int port, WatchdogConfig c, {required String subject}) =>
    '$kStockMailsendPath -ssl -verifyCert '
    '-smtp ${shellSingleQuote(host)} -port $port -sub ${shellSingleQuote(subject)} '
    '-f ${shellSingleQuote(c.emailFrom)} -t ${shellSingleQuote(c.emailTo)} '
    'auth -user ${shellSingleQuote(c.smtpUsername)} -pass ${shellSingleQuote(c.smtpPassword)} '
    'body -file /tmp/mail.txt';

// The BusyBox sendmail implicit-TLS command for the one-off test email (concrete values).
String buildSendmailCommand(String host, int port, WatchdogConfig c) => '/usr/sbin/sendmail '
    '-H "exec openssl s_client -quiet -tls1_3 '
    '-CAfile /etc/ssl/certs/ca-certificates.crt '
    '-verify_return_error '
    '-connect $host:$port" '
    '-au${shellSingleQuote(c.smtpUsername)} '
    '-ap${shellSingleQuote(c.smtpPassword)} '
    '-f${shellSingleQuote(c.emailFrom)} '
    '${shellSingleQuote(c.emailTo)} '
    '< /tmp/mail.txt';

// The router-side mail blocks, substituted into the template at build time. Conditional logic
// inside the script itself is not an option: the firmware is already known here.
//
// mailsend-go builds its own headers from flags, so on stock the body file starts empty.
const String _kMailHdrStock = r'''  : > "$TMPMAIL"
''';

const String _kMailHdrMerlin = r'''  {
    echo "From: $EMAIL_FROM"
    echo "To: $EMAIL_TO"
    echo "Subject: $EMAIL_SUBJECT: $STATUS - $IFACE:$DESC"
    echo "Date: $(date -R 2>/dev/null || date)"
    echo "Message-ID: <$(date +%s).$SLOT@$(uname -n)>"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/plain; charset=utf-8"
    echo ""
  } > "$TMPMAIL"
''';

// The kill switch has three states, not two: on, available-but-disabled (Merlin), and absent
// (stock, which has none - revisit that wording once in-app device assignment lands, after which a
// device assigned to a downed wgcN simply loses connectivity).
//
// Each also needs three tenses, because the same fact reads wrong in the wrong one: UP for a deploy
// run where the tunnel is fine, FIXED for a recovery that is over, DOWN for a failure that is not.
const String _kKillSwitchStock =
    r'''KILLSW_UP="not supported on this firmware - if the tunnel drops, traffic reaches the internet without the VPN"
KILLSW_FIXED="not supported on this firmware - traffic reached the internet without the VPN"
KILLSW_DOWN="not supported on this firmware - traffic is reaching the internet without the VPN"''';

const String _kKillSwitchMerlin = r'''if [ "$ENFORCE" = "1" ]; then
  KILLSW_UP="ON - traffic is blocked if the tunnel drops"
  KILLSW_FIXED="ON - no traffic left the router while it was down"
  KILLSW_DOWN="ON - traffic is blocked while the tunnel is down"
else
  KILLSW_UP="OFF - the kill switch is available but is not enabled"
  KILLSW_FIXED="$KILLSW_UP"
  KILLSW_DOWN="$KILLSW_UP"
fi''';

const String _kMailCmdMerlin = r'''  /usr/sbin/sendmail \
    -H "exec openssl s_client -quiet -tls1_3 -CAfile /etc/ssl/certs/ca-certificates.crt \
    -verify_return_error -connect $SMTP_HOST:$SMTP_PORT" \
    -au"$SMTP_USER" \
    -ap"$SMTP_PASS" \
    -f"$EMAIL_FROM" \
    "$EMAIL_TO" < "$TMPMAIL" 2>"$TMPERR"''';

// No -debug: it writes the whole argument parse to stderr, burying the actual error in the
// captured output - the same reason it came off buildMailsendGoCommand.
const String _kMailCmdStock = '''  $kStockMailsendPath -ssl -verifyCert \\
    -smtp "\$SMTP_HOST" -port "\$SMTP_PORT" -sub "\$EMAIL_SUBJECT: \$STATUS - \$IFACE:\$DESC" \\
    -f "\$EMAIL_FROM" -t "\$EMAIL_TO" \\
    auth -user "\$SMTP_USER" -pass "\$SMTP_PASS" \\
    body -file "\$TMPMAIL" 2>"\$TMPERR"''';

// Shell appending a fixed block of lines. Generated from the same constants [buildEmailBody] uses,
// so the script's wording and the app's cannot drift apart.
String _echoBlock(Iterable<String> lines) =>
    lines.map((l) => '  echo ${shellSingleQuote(l)} >> "\$TMPMAIL"').join('\n');

// The full watchdog_wgcN.sh body (see watchdogScriptPath). Slot-parameterised via __SLOT__; the jq path and
// the two mail blocks are resolved from [firmware] (the detected one by default).
String buildWatchdogScript(WatchdogConfig c, {RouterFirmware? firmware}) {
  final fw = firmware ?? routerFirmware;
  final stock = fw == RouterFirmware.stock;
  return _kWatchdogScriptTemplate
      .replaceAll('__SLOT__', '${c.slotIndex}')
      .replaceAll('__JQ__', jqCommand(fw))
      .replaceAll('__CACERT__', kPiaCaCertPath)
      // enforce / fw / rip / ep_addr_r are Merlin-only (kMerlinOnlySlotKeys). Writing them on
      // stock creates keys nothing reads and DELETE does not clean up.
      .replaceAll('__MERLINONLY__', stock ? '' : _kMerlinOnlyNvsets)
      .replaceAll('__BACKOFF__', buildBackoffCase())
      .replaceAll('__APPVER__', appVersionLabel)
      .replaceAll('__KILLSW__', stock ? _kKillSwitchStock : _kKillSwitchMerlin)
      .replaceAll('__MAILHDR__', stock ? _kMailHdrStock : _kMailHdrMerlin)
      .replaceAll('__WHATTODO__', _echoBlock(['', kSectionWhatToDo, ...kEmailWhatToDo]))
      .replaceAll('__SIGNOFF__', _echoBlock(['', kEmailReviewLine, '', ...kEmailSignOff]))
      .replaceAll('__MAILCMD__', stock ? _kMailCmdStock : _kMailCmdMerlin);
}

// ─── Service ─────────────────────────────────────────────────────────────────────

class RouterWatchdog {
  final SSHClient client;
  final void Function(String, {bool isError, bool isSuccess})? onLog;

  RouterWatchdog(this.client, {this.onLog});

  // Run a command and return trimmed stdout (mirrors router_push.dart `_run`).
  Future<String> _run(String cmd) async => utf8.decode(await client.run(cmd)).trim();

  // Heredoc writes can stall if the SSH channel hangs; bound them at 30s and
  // surface a troubleshooting message on timeout.
  /// Writes the watchdog script and proves it landed.
  ///
  /// Deploy used to carry on regardless: a failed or truncated write left cru entries pointing at
  /// a script that was not there, and the app reported the watchdog as active.
  /// The one way to put a file on the router: chunked heredoc, then prove it landed.
  ///
  /// Chunked because dropbear refuses an exec request over [kMaxSshCommandBytes] and drops the
  /// connection. Verified because a write that fails silently is worse than one that fails loudly:
  /// a missing watchdog script still left cru entries pointing at it, and the app called that
  /// ACTIVE. [what] names the file in the message the user sees.
  Future<void> _writeFile(String path, String body, {required String what, String mode = '+x'}) async {
    final expected = body.endsWith('\n') ? body.length : body.length + 1;
    for (final cmd in heredocWriteCommands(path, body)) {
      await _runHeredoc(cmd, path);
    }
    await _run("chmod $mode '$path'");
    final size = int.tryParse(await _run("wc -c < '$path' 2>/dev/null | tr -d ' '")) ?? 0;
    if (size != expected) {
      throw Exception('Writing $path failed: the router has $size bytes of a $expected byte file. '
          'The $what was NOT deployed - check free space on the router filesystem.');
    }
    onLog?.call('$what written to $path ($size bytes).', isSuccess: true);
  }

  Future<void> _writeScript(int slot, String body) async {
    await _run("mkdir -p '$kRouterAppDir'");
    await _writeFile(watchdogScriptPath(slot), body, what: 'Watchdog script');
  }

  Future<String> _runHeredoc(String cmd, String path) async {
    try {
      return await _run(cmd).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw Exception(
        'Timed out after 30s writing to "$path" via SSH heredoc. '
        'Check SSH connectivity and that the router filesystem (JFFS and/or /tmp) is writable.',
      );
    }
  }

  // The slot's stored description, used to keep the stock clientlist row named.
  Future<String?> _descFor(int slot) async {
    final desc = (await _run('nvram get wgc${slot}_desc')).trim();
    return desc.isEmpty ? null : desc;
  }

  // 'wgcN:<description>' for log lines; cached, since a service instance serves one action.
  final Map<int, String> _labelCache = {};
  Future<String> _label(int slot) async => _labelCache[slot] ??= await fetchSlotLabel(slot, _run);

  // Best-effort native syslog entry on the router.
  Future<void> _logRouter(String msg) async => _run(buildLoggerCommand(msg));

  // Wraps a mutating action so failures are surfaced to the app log AND the router syslog.
  Future<T> _guard<T>(String action, Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      onLog?.call('Watchdog $action failed: $e', isError: true);
      try {
        await _logRouter('ERROR during $action: $e');
      } catch (_) {
        // syslog itself is unreachable (e.g. SSH dropped) — nothing more we can do.
      }
      rethrow;
    }
  }

  Future<bool> isMerlinRouter() async => (await _run('nvram get 3rd-party')) == 'merlin';

  /// Deletes the cached PIA CA certificate, so the next watchdog run downloads a fresh one.
  ///
  /// Returns true if a file was there to delete. The test is done on the router in one command:
  /// two round trips could disagree, and `rm -f` alone cannot tell "removed" from "never there".
  Future<bool> deleteCachedPiaCert() async {
    final out = await _run("[ -f '$kPiaCaCertPath' ] && rm -f '$kPiaCaCertPath' && echo DELETED || echo ABSENT");
    final deleted = out.contains('DELETED');
    onLog?.call(deleted ? 'Deleted cached PIA certificate ($kPiaCaCertPath).' : 'No cached PIA certificate to delete.',
        isSuccess: deleted);
    return deleted;
  }

  // Merlin ships jq on $PATH; on stock the user installs it under /jffs/cfg-pia-wg (README §4).
  Future<bool> isJqInstalled() async =>
      isStockFirmware ? (await _run("[ -x '$kStockJqPath' ] && echo 1 || echo 0")) == '1' : (await _run('which jq')).isNotEmpty;

  // Ensures the watchdog script has somewhere to live. jffs2_scripts / jffs2_on are a Merlin
  // custom-scripts feature; on stock only the directory matters.
  Future<void> enableJffsScripts() async {
    if (isStockFirmware) {
      // The app's own directory holds the watchdog script; /jffs/scripts is Merlin's hook
      // directory and stock has no use for it.
      await _run("mkdir -p '$kRouterAppDir'");
      return;
    }
    final scripts = await _run('nvram get jffs2_scripts');
    final on = await _run('nvram get jffs2_on');
    if (scripts == '1' && on == '1') return;
    await _run('nvram set jffs2_scripts=1');
    await _run('nvram set jffs2_on=1');
    await _run('nvram commit');
  }

  // Writes the per-slot watchdog NVRAM + global PIA creds (and optionally wgcN_desc), then commits.
  // Called only by deployWatchdog, the single create-or-update path.
  Future<void> _writeWatchdogNvram(WatchdogConfig config, {String? desc}) async {
    for (final e in config.toNvram().entries) {
      await _run('nvram set ${e.key}=${shellSingleQuote(e.value)}');
    }
    await _run('nvram set cfg_pia_wg_user=${shellSingleQuote(config.piaUsername.trim())}');
    await _run('nvram set cfg_pia_wg_password=${shellSingleQuote(config.piaPassword)}');
    if (desc != null && desc.isNotEmpty) {
      await _run('nvram set wgc${config.slotIndex}_desc=${shellSingleQuote(slotDescFor(desc))}');
      // Stock reads the region name from vpnc_clientlist, not wgcN_desc. Without this row a
      // watchdog-created slot reads as unconfigured, and the slot modal greys out everything
      // except CREATE - including VIEW ROUTER WATCHDOG LOG.
      await RouterSlotService(client).writeVpncProfile(config.slotIndex, desc: slotDescFor(desc));
    }
    await _run('nvram commit');
  }

  // The single CREATE/EDIT path: persist the watchdog params, enable the VPN slot, then deploy
  // every runtime artifact (script, both cron jobs, services-start persistence) and run the script
  // once so the watchdog is live immediately rather than at its next scheduled interval.
  //
  // Concurrent watchdogs are allowed, so this no longer tears down the other slots. How many may
  // run at once is a firmware limit (vpnc_max_conn on stock), enforced by the caller before it
  // gets here - the same gate the MANAGE ENABLE path applies.
  Future<void> deployWatchdog(WatchdogConfig config, {String? desc}) => _guard('deploy', () async {
        await enableJffsScripts();
        await _writeWatchdogNvram(config, desc: desc);
        await enableVpnSlot(config.slotIndex);
        await _writeScript(config.slotIndex, buildWatchdogScript(config));
        await _run(buildCronCheckLine(config.slotIndex, config.cronIntervalMinutes));
        await _run(buildCronRotateLine(config.slotIndex));
        await _ensureServicesStart(config.slotIndex, config.cronIntervalMinutes);
        onLog?.call('Watchdog settings saved for ${await _label(config.slotIndex)}.', isSuccess: true);
        await _run(kSeedCountersCommand);
        await _logRouter('Running ${watchdogScriptPath(config.slotIndex)} deploy');
        // `deploy` makes this run report itself as a deployment rather than a re-configuration,
        // and makes it email even when it finds the tunnel already healthy.
        await _run('${watchdogScriptPath(config.slotIndex)} deploy');
        onLog?.call('Ran ${watchdogScriptPath(config.slotIndex)}', isSuccess: true);
        await _logRouter(
            'Watchdog deployed for ${await _label(config.slotIndex)} (check interval is ${config.cronIntervalMinutes}m)');
        onLog?.call('Watchdog deployed for ${await _label(config.slotIndex)}.', isSuccess: true);
      });

  // Enables the underlying WireGuard slot
  Future<void> enableVpnSlot(int slot) => _guard('enable VPN slot', () async {
        final slots = RouterSlotService(client, onLog: onLog);
        await _run('nvram set wgc${slot}_enable=1');
        // Stock shows a profile as connected from its clientlist flag, not wgcN_enable - and the
        // row has to exist before the service call, since vpnc_unit is that row's index.
        await slots.writeVpncProfile(slot, desc: await _descFor(slot), active: true);
        await _run('nvram commit');
        // Stock drives WireGuard through VPN Fusion; start_wgc is Merlin's. Same calls MANAGE
        // makes, so a watchdog-managed tunnel comes up the same way as a hand-enabled one.
        if (isStockFirmware) {
          await slots.runVpncService(slot, 'restart_vpnc', required: true);
        } else {
          await _run('service "start_wgc $slot"; service restart_vpnrouting0');
        }
        await _logRouter('Enabled ${await _label(slot)} via watchdog interface');
        onLog?.call('${await _label(slot)} enabled.', isSuccess: true);
      });

  // Disables the underlying WireGuard slot (mirrors RouterSlotService.disableSlot). Clearing
  // the enable flag matters as much as stopping the service: without it the slot comes back on
  // the next start_vpnrouting0 or reboot.
  Future<void> disableVpnSlot(int slot) => _guard('disable VPN slot', () => _disableVpnSlot(slot));

  // Unguarded body, so stopWatchdog can reuse it without nesting _guard (which would log the
  // same failure twice).
  Future<void> _disableVpnSlot(int slot) async {
    final slots = RouterSlotService(client, onLog: onLog);
    await _run('nvram set wgc${slot}_enable=0');
    await slots.writeVpncProfile(slot, active: false);
    await _run('nvram commit');
    // There is no start_vpnc on stock; stop_vpnc is what actually tears the interface down
    // (ARCHITECTURE.md 4.2.3). restart_vpnc would leave it up.
    if (isStockFirmware) {
      await slots.runVpncService(slot, 'stop_vpnc');
    } else {
      await _run('service "stop_wgc $slot"; service start_vpnrouting0');
    }
    await _logRouter('Disabled ${await _label(slot)}');
    onLog?.call('${await _label(slot)} disabled.', isSuccess: true);
  }

  // True for any cru line belonging to [slot], on either firmware.
  static bool _cruLineForSlot(String line, int slot) =>
      line.contains('watchdog_wgc$slot ') || line.contains('watchdog_log_rotate_wgc$slot ');

  // Makes the two cron entries survive a reboot. Merlin appends them to services-start; stock has
  // no equivalent, so the app owns the replacement block of an init script the firmware already
  // runs at boot and on a firewall restart.
  Future<void> _ensureServicesStart(int slot, int intervalMin) async {
    if (isStockFirmware) {
      await _writeS50(slot, extra: [buildCronCheckLine(slot, intervalMin), buildCronRotateLine(slot)]);
      // Install the entries now rather than waiting for the next boot.
      await _run("'$kS50Path' start");
      return;
    }
    const path = kServicesStartPath;
    await _run("[ -f '$path' ] || { echo '#!/bin/sh' > '$path'; chmod +x '$path'; }");
    await _run(
      "grep -v -e 'watchdog_wgc$slot ' -e 'watchdog_log_rotate_wgc$slot ' '$path' > '$path.tmp' 2>/dev/null; "
      "mv '$path.tmp' '$path'",
    );
    await _run("printf '%s\\n' ${shellSingleQuote(buildCronCheckLine(slot, intervalMin))} >> '$path'");
    await _run("printf '%s\\n' ${shellSingleQuote(buildCronRotateLine(slot))} >> '$path'");
    await _run("chmod +x '$path'");
  }

  // Rebuilds S50downloadmaster from the embedded template: drops [slot]'s existing cru lines,
  // keeps every other slot's (a later release runs several watchdogs at once), then appends
  // [extra]. Rebuilding rather than grep -v is what keeps the template scaffolding intact.
  Future<void> _writeS50(int slot, {List<String> extra = const []}) async {
    final existing = await _run("cat '$kS50Path' 2>/dev/null");
    final lines = [
      for (final line in extractS50CruLines(existing))
        if (!_cruLineForSlot(line, slot)) line,
      ...extra,
    ];
    await _writeFile(kS50Path, buildS50Script(lines), what: 'Boot persistence script');
  }

  // Cron entries only: removes this slot's two cru jobs and its boot-persistence lines, and
  // leaves everything else alone - the script, the NVRAM settings and the tunnel itself.
  //
  // This is the difference between DISABLE and DELETE. DELETE (stopWatchdog) tears the whole
  // thing down; DISABLE stops the supervision and keeps the configuration, so ENABLE can put the
  // schedule back without asking the user for the settings again.
  Future<void> disableWatchdog(int slot) => _guard('disable watchdog', () async {
        final label = await _label(slot);
        await _run('cru d watchdog_wgc$slot');
        await _run('cru d watchdog_log_rotate_wgc$slot');
        await _removeCronPersistence(slot);
        await _logRouter('Watchdog schedule removed for $label (settings kept)');
        onLog?.call('Watchdog disabled for $label; its settings are kept.', isSuccess: true);
      });

  // Puts the schedule back from the settings already in NVRAM. The interval is read from the
  // router rather than passed in, so ENABLE cannot silently reschedule at a different interval
  // from the one the user configured.
  Future<void> enableWatchdog(int slot) => _guard('enable watchdog', () async {
        final label = await _label(slot);
        final stored = await _run('nvram get wgc${slot}_wd_check_interval');
        final interval = int.tryParse(stored);
        if (interval == null || interval <= 0) {
          throw Exception('wgc$slot has no stored watchdog settings - use CREATE/EDIT first.');
        }
        await enableJffsScripts();
        await _run(buildCronCheckLine(slot, interval));
        await _run(buildCronRotateLine(slot));
        await _ensureServicesStart(slot, interval);
        await _logRouter('Watchdog schedule restored for $label (check interval is ${interval}m)');
        onLog?.call('Watchdog enabled for $label (checks every ${interval}m).', isSuccess: true);
      });

  // Drops [slot]'s cron lines from whichever boot-persistence file this firmware uses.
  Future<void> _removeCronPersistence(int slot) async {
    if (isStockFirmware) {
      await _writeS50(slot);
      await _run("chmod 700 '$kS50Path'");
      return;
    }
    const path = kServicesStartPath;
    await _run(
      "[ -f '$path' ] && grep -v -e 'watchdog_wgc$slot ' -e 'watchdog_log_rotate_wgc$slot ' '$path' "
      "> '$path.tmp' && mv '$path.tmp' '$path' && chmod 700 '$path'",
    );
  }

  /// True if any slot other than [slot] still has a watchdog cron entry.
  ///
  /// cfg_pia_wg_user / cfg_pia_wg_password are GLOBAL keys shared by every watchdog script, so a
  /// teardown may only unset them once it is the last one standing. Getting this wrong leaves a
  /// surviving watchdog unable to authenticate with PIA at its next renegotiation.
  Future<bool> _otherWatchdogsRemain(int slot) async {
    for (var other = 1; other <= 5; other++) {
      if (other == slot) continue;
      if ((await _run('cru l | grep -qw watchdog_wgc$other && echo 1 || echo 0')) == '1') return true;
    }
    return false;
  }

  // Full disable: unset NVRAM, remove cron jobs and service-start script
  // JFFS is intentionally left enabled.
  Future<void> stopWatchdog(int slot) => _guard('disable', () async {
        // Read before the nvram unsets below wipe the description.
        final label = await _label(slot);
        await _run('cru d watchdog_wgc$slot');
        await _run('cru d watchdog_log_rotate_wgc$slot');
        await _run('rm -f ${watchdogScriptPath(slot)}');
        // strip out cron jobs added when watchdog installed, reinstate 700 permission. On stock
        // the file itself stays: it is a hijacked init script, so removing it is worse than
        // leaving an empty replacement block.
        await _removeCronPersistence(slot);
        await _run(
          'rm -f /tmp/watchdog_wgc$slot.log /tmp/watchdog_wgc$slot.log.old '
          '/tmp/watchdog_last_ping_success_wgc$slot /tmp/watchdog_backoff_wgc$slot',
        );
        // nvram command doesn't allow multiple values in one command
        await _run('nvram unset wgc${slot}_wd_check_interval');
        await _run('nvram unset wgc${slot}_wd_email_enabled');
        await _run('nvram unset wgc${slot}_wd_email_from');
        await _run('nvram unset wgc${slot}_wd_email_subject');
        await _run('nvram unset wgc${slot}_wd_email_to');
        await _run('nvram unset wgc${slot}_wd_primary_ip');
        await _run('nvram unset wgc${slot}_wd_secondary_ip');
        await _run('nvram unset wgc${slot}_wd_smtp_pass');
        await _run('nvram unset wgc${slot}_wd_smtp_server');
        await _run('nvram unset wgc${slot}_wd_smtp_user');
        // GLOBAL keys, shared by every watchdog script. With concurrent watchdogs allowed, only
        // the last one out may clear them - otherwise the survivor cannot authenticate with PIA
        // at its next renegotiation. The cru entries for this slot are already gone above, so
        // this sees the state after the removal.
        if (await _otherWatchdogsRemain(slot)) {
          onLog?.call('Another watchdog is still configured; keeping the shared PIA credentials.');
        } else {
          await _run('nvram unset cfg_pia_wg_password');
          await _run('nvram unset cfg_pia_wg_user');
        }
        await _run('nvram commit');
        onLog?.call('NVRAM committed.', isSuccess: true);
        // Bring the tunnel down too, otherwise disabling the watchdog leaves an unsupervised VPN
        // running. This previously issued `service "stop_wgc wgc$slot"` — the service expects the
        // bare slot index (see ARCHITECTURE.md), so the interface was never actually stopped.
        await _disableVpnSlot(slot);
        await _logRouter('Watchdog disabled for $label');
        onLog?.call('Watchdog disabled for $label.', isSuccess: true);
      });

  Future<bool> waitForWatchdogReady(int slot, {Duration pollInterval = const Duration(seconds: 1), int maxAttempts = 10}) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final status = await getWatchdogStatus(slot);
      if (status.isEnabled) return true;
      await Future.delayed(pollInterval);
    }
    return false;
  }

  // Enabled state requires both the watchdog cron entry and the actual WireGuard interface.
  Future<WatchdogStatus> getWatchdogStatus(int slot) async {
    // The script has to exist too: a deploy that failed to write it still left the cron entries,
    // and reporting that as enabled is how a broken watchdog looked healthy.
    final cronEnabled = (await _run("cru l | grep -qw watchdog_wgc$slot && [ -s '${watchdogScriptPath(slot)}' ] "
            '&& echo 1 || echo 0')) ==
        '1';
    final interfaceEnabled = (await _run('nvram get wgc${slot}_enable')) == '1';
    final interfacePresent = (await _run('wg show interfaces')).contains('wgc$slot');
    final enabled = cronEnabled && interfaceEnabled && interfacePresent;
    final ping = await _run('cat /tmp/watchdog_last_ping_success_wgc$slot 2>/dev/null');
    return WatchdogStatus(isEnabled: enabled, lastSuccessfulPing: parseLastPing(ping));
  }

  Future<String> getWatchdogLog(int slot) => _run('cat /tmp/watchdog_wgc$slot.log 2>/dev/null');

  // Reads the full watchdog config (per-slot + global PIA) back from NVRAM for the dialog.
  Future<WatchdogConfig> loadConfig(int slot) async {
    const keys = [
      'check_interval',
      'primary_ip',
      'secondary_ip',
      'email_enabled',
      'email_from',
      'email_to',
      'email_subject',
      'smtp_server',
      'smtp_user',
      'smtp_pass',
    ];
    final nv = <String, String>{};
    for (final k in keys) {
      nv['wgc${slot}_wd_$k'] = await _run('nvram get wgc${slot}_wd_$k');
    }
    nv['cfg_pia_wg_user'] = await _run('nvram get cfg_pia_wg_user');
    nv['cfg_pia_wg_password'] = await _run('nvram get cfg_pia_wg_password');
    return WatchdogConfig.fromNvram(slot, nv);
  }

  // Sends a one-off test email (subject "config test") using the supplied SMTP settings.
  /// Sends the one-off test email. Returns true if the mailer exited 0.
  ///
  /// Every diagnostic goes to BOTH logs. It used to write only to the router syslog and tell the
  /// user to go and read it there, which is a poor thing to ask of someone holding a phone - and
  /// the one line it did put in the app log was styled as a success.
  /// Reads every router fact an email carries, seeding the lifetime counters first so the
  /// `Since ...` date is the day the user started, not the day of their first reconfigure.
  Future<RouterEmailFacts> emailFacts(int slot) async {
    await _run(kSeedCountersCommand);
    return RouterEmailFacts.parse(await _run(kEmailFactsCommand(slot)));
  }

  Future<bool> testEmail(WatchdogConfig config) => _guard('test email', () async {
        final (host, port) = config.smtpHostPort;
        final stock = isStockFirmware;
        final facts = await emailFacts(config.slotIndex);
        final subject = buildMailSubject(config, status: 'TEST email', desc: facts.desc);

        final body = buildEmailBody(
          opening: 'This is a test email from cfg-pia-wg. Your SMTP settings work; watchdog alerts '
              'will reach this address.',
          whatHappened: [
            'Event: test email sent by hand from the watchdog configuration screen',
            facts.intervalRow,
          ],
          router: facts.routerRows(config.slotIndex),
          history: facts.historyLine,
        );
        // sendmail wants the RFC-822 headers inline; mailsend-go takes them as flags.
        final file = stock ? body : '${buildMailHeaders(config, subject: subject)}$body';
        for (final cmd in heredocWriteCommands('/tmp/mail.txt', file)) {
          await _runHeredoc(cmd, '/tmp/mail.txt');
        }

        final sendCmd = stock
            ? buildMailsendGoCommand(host, port, config, subject: subject)
            : buildSendmailCommand(host, port, config);

        // Redirect stderr to file; echo exit code into stdout so _run can return it.
        final result = await _run('$sendCmd 2>/tmp/wd_smtp_err; echo "EXITCODE:\$?"');

        final exitCode = _parseExitCode(result);

        if (exitCode == 0) {
          await _run('rm -f /tmp/mail.txt /tmp/wd_smtp_err');
          await _logRouter('Test email sent to ${config.emailTo}');
          onLog?.call('Test email sent to ${config.emailTo}.', isSuccess: true);
          return true;
        }

        onLog?.call('Test email FAILED (exit $exitCode) sending to ${config.emailTo} via $host:$port.', isError: true);

        // Layer 1: mailer stderr
        final stderrRaw = await _run('cat /tmp/wd_smtp_err 2>/dev/null | tail -20 | tr "\\n" "|"');
        await _logRouter('Email FAILED (exit=$exitCode) stderr=[${stderrRaw.trim()}]');
        if (stderrRaw.trim().isNotEmpty) onLog?.call('  mailer: ${stderrRaw.trim()}', isError: true);

        // Layer 2: connect and hand-shake in one probe.
        //
        // There is no `nc` layer any more. BusyBox on stock builds nc as `nc IPADDR PORT` with no
        // options at all, so `nc -w 5` failed on a usage error and reported UNREACHABLE for every
        // host - including ones that were demonstrably delivering mail seconds later. openssl is
        // already needed for the handshake, tells us the same thing about reachability, and says
        // considerably more when it does fail.
        final tlsOut = await _run(
          'printf "QUIT\\r\\n" | openssl s_client '
          '-connect $host:$port '
          '-CAfile /etc/ssl/certs/ca-certificates.crt '
          '2>&1 | tail -20 | tr "\\n" "|"',
        );
        final probe = tlsOut.trim();
        await _logRouter('SMTP probe $host:$port: ${probe.isEmpty ? 'no output' : probe}');
        if (probe.isNotEmpty) onLog?.call('  probe $host:$port: $probe', isError: true);

        await _run('rm -f /tmp/mail.txt /tmp/wd_smtp_err');
        return false;
      });

  int _parseExitCode(String output) {
    final match = RegExp(r'EXITCODE:(\d+)').firstMatch(output);
    return match != null ? int.tryParse(match.group(1)!) ?? -1 : -1;
  }

  // Reachability probe over the WAN (no interface binding) — used during pre-save validation.
  Future<bool> pingHostViaWan(String ip) async {
    try {
      final out = await _run('ping -c 1 -W 2 ${shellSingleQuote(ip)} >/dev/null 2>&1 && echo OK || echo FAIL');
      return out == 'OK';
    } catch (_) {
      return false;
    }
  }

  // Reachability probe bound to the VPN interface — used by any test-from-app functionality.
  Future<bool> pingHostViaVpn(String ip, int slot) async {
    try {
      final out = await _run('ping -I wgc$slot -c 1 -W 2 ${shellSingleQuote(ip)} >/dev/null 2>&1 && echo OK || echo FAIL');
      return out == 'OK';
    } catch (_) {
      return false;
    }
  }
}

// The per-slot keys only Merlin uses; omitted from the stock script (kMerlinOnlySlotKeys).
const String _kMerlinOnlyNvsets = r'''nvset "enforce=$ENFORCE"
nvset "ep_addr_r="
nvset "fw=1"
nvset "rip="''';

// ─── Bash script template ────────────────────────────────────────────────────────
// POSIX sh. __SLOT__ is the only placeholder; everything else is literal shell.
// Logs to both /jffs/watchdog_wgcN.log and the router syslog (logger -t cfg-pia-wg).
//
// There is a ~7 KB heredoc size limitation for the following payload.
//
// NB /usr/sbin/curl creates /jffs/curllst with 666 permissions, this file contains every
// curl command line executed (!) and there is no way to diuable this, so after every
// curl invocation, the curllst log file is flushed with "echo -n > /jffs/curllst" :)
//
const String _kWatchdogScriptTemplate = r'''#!/bin/sh
# watchdog_wgc__SLOT__.sh - auto-generated; *do* *not* edit. re-negotiates PIA WireGuard on ping failure

# `deploy` only when the app runs the script by hand just after writing it; cron passes nothing.
# Read at the top, because send_alert() shadows $1 with its own argument.
RUNMODE="${1:-cron}"
APPVER="__APPVER__"
SLOT=__SLOT__
IFACE="wgc__SLOT__"
K="${IFACE}_"
LOGTAG="cfg-pia-wg"
LOGFILE="/tmp/watchdog_${IFACE}.log"
STATUSFILE="/tmp/watchdog_last_ping_success_${IFACE}"
BACKOFFFILE="/tmp/watchdog_backoff_${IFACE}"
CACERT="__CACERT__"
JQ="__JQ__"
# tlsv1.2 is a MINIMUM; requiring 1.3 failed addKey with curl 35 (handshake).
CURLB="curl -s --max-time 15 --connect-timeout 8 --tlsv1.2"
CURL="$CURLB --fail"
TMPMAIL="/tmp/mail_${IFACE}.txt"
TMPSRV="/tmp/${IFACE}_servers.txt"
TMPERR="/tmp/${IFACE}_curl.err"
TMPTOK="/tmp/${IFACE}_token.json"
SERVERLIST_URL="https://serverlist.piaservers.net/vpninfo/servers/v6"
TOKEN_URL="https://www.privateinternetaccess.com/gtoken/generateToken"
CACERT_URL="https://raw.githubusercontent.com/pia-foss/manual-connections/master/ca.rsa.4096.crt"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOGFILE"
  logger -t "$LOGTAG" "$IFACE: $1"
}

nvset() { nvram set "${K}$1"; }

# Read NVRAM config
PRIMARY_IP="$(nvram get ${K}wd_primary_ip)"
SECONDARY_IP="$(nvram get ${K}wd_secondary_ip)"
EMAIL_ON="$(nvram get ${K}wd_email_enabled)"
EMAIL_FROM="$(nvram get ${K}wd_email_from)"
EMAIL_TO="$(nvram get ${K}wd_email_to)"
EMAIL_SUBJECT="$(nvram get ${K}wd_email_subject)"
SMTP_SERVER="$(nvram get ${K}wd_smtp_server)"
SMTP_USER="$(nvram get ${K}wd_smtp_user)"
SMTP_PASS="$(nvram get ${K}wd_smtp_pass)"
SMTP_HOST="${SMTP_SERVER%:*}"
SMTP_PORT="${SMTP_SERVER##*:}"
DESC="$(nvram get ${K}desc)"
# PIA region ids carry no prefix; strip the app's for the lookup (tolerates older names).
REGION="${DESC#pia-}"
# Kill switch: put back what the user set. Empty (always, on stock) means off.
ENFORCE="$(nvram get ${K}enforce)"
[ -n "$ENFORCE" ] || ENFORCE=0
INTERVAL="$(nvram get ${K}wd_check_interval)"
__KILLSW__
PIA_USER="$(nvram get cfg_pia_wg_user)"
PIA_PASS="$(nvram get cfg_pia_wg_password)"

__BACKOFF__

log "Watchdog started for $IFACE"

# Lifetime counters. Reconfigures are rare, so one nvram commit per event is an acceptable flash
# cost; a broken tunnel retrying forever is what the token backoff is for.
bump() {
  [ -n "$(nvram get cfg_pia_wg_sdate)" ] || nvram set cfg_pia_wg_sdate="$(date '+%Y-%m-%d')"
  BN="$(nvram get $1)"
  case "$BN" in ''|*[!0-9]*) BN=0 ;; esac
  nvram set "$1=$((BN + 1))"
  nvram commit
}

# "6m 12s (last seen good ...)". The status file lives in /tmp and does not survive a reboot, and
# one written by an older build carries no epoch - say so rather than printing a made-up duration.
down_for() {
  if [ ! -f "$STATUSFILE" ]; then
    echo "unknown (no successful check since the router last rebooted)"
    return 0
  fi
  read -r LGE LGD < "$STATUSFILE"
  case "$LGE" in ''|*[!0-9]*)
    echo "unknown (no successful check since the router last rebooted)"
    return 0 ;;
  esac
  D=$(( $(date +%s) - LGE ))
  [ "$D" -ge 0 ] || D=0
  printf '%dm %02ds (last seen good %s %s)\n' $((D / 60)) $((D % 60)) "$LGD" "$(date '+%Z')"
}

# Email alert
send_alert() {
  STATUS="$1"
  DETAIL="$2"
  [ "$EMAIL_ON" = "1" ] || return 0
  [ -n "$SMTP_HOST" ] || { log "Email enabled but SMTP server is not configured"; return 0; }

  if [ "$STATUS" != "SUCCESS" ]; then
    KILLSW="$KILLSW_DOWN"
  elif [ "$RUNMODE" = "deploy" ]; then
    KILLSW="$KILLSW_UP"
  else
    KILLSW="$KILLSW_FIXED"
  fi

  if [ "$RUNMODE" = "deploy" ]; then
    if [ "$STATUS" = "SUCCESS" ]; then
      OPENING="Watchdog deployed and the tunnel is up."
    else
      OPENING="Watchdog deployed but the tunnel could NOT be brought up."
    fi
  else
    if [ "$STATUS" = "SUCCESS" ]; then
      OPENING="Connectivity was lost and the tunnel has been rebuilt."
    else
      OPENING="Connectivity was lost and the tunnel could NOT be rebuilt."
    fi
  fi

  RNAME="$(nvram get ddns_hostname_x)"
  LANIP="$(nvram get lan_ipaddr)"
  [ -n "$RNAME" ] || RNAME="$(nvram get lan_hostname)"
  [ -n "$RNAME" ] || RNAME="$LANIP"
  SDATE="$(nvram get cfg_pia_wg_sdate)"
  [ -n "$SDATE" ] || SDATE="$(date '+%Y-%m-%d')"
  OKN="$(nvram get cfg_pia_wg_reconfig_ok)"
  FAILN="$(nvram get cfg_pia_wg_reconfig_fail)"
  case "$OKN" in ''|*[!0-9]*) OKN=0 ;; esac
  case "$FAILN" in ''|*[!0-9]*) FAILN=0 ;; esac
  WDROW="$IFACE:$DESC"
  [ -n "$APPVER" ] && WDROW="$WDROW, deployed by cfg-pia-wg $APPVER"

__MAILHDR__
  # A row with no value is dropped rather than printed empty.
  row() { [ -n "$2" ] && printf '%s: %s\n' "$1" "$2" >> "$TMPMAIL"; return 0; }

  printf '%s\n\nWHAT HAPPENED\n' "$OPENING" >> "$TMPMAIL"
  row "Event" "$DETAIL"
  row "$CONNLABEL" "$CONNVALUE"
  row "$DOWNLABEL" "$DOWNFOR"
  row "Kill switch" "$KILLSW"
  row "Attempt" "$ATTEMPTV"
  row "Interval" "$INTERVALV"

  if [ "$STATUS" != "SUCCESS" ]; then
__WHATTODO__
  fi

  echo "" >> "$TMPMAIL"
  echo "ROUTER" >> "$TMPMAIL"
  row "Name" "$RNAME ($LANIP)"
  row "Model" "$(nvram get productid), firmware $(nvram get buildno)_$(nvram get extendno)"
  row "Time" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  row "Uptime" "$(uptime | sed 's/^ *//')"
  row "Watchdog" "$WDROW"

  printf '\nHISTORY\nSince %s this router has recorded %s successful and %s failed reconfigurations.\n' \
    "$SDATE" "$OKN" "$FAILN" >> "$TMPMAIL"

  if [ "$STATUS" != "SUCCESS" ]; then
    printf '\nROUTER LOG (last 10 lines)\n' >> "$TMPMAIL"
    tail -10 "$LOGFILE" >> "$TMPMAIL"
  fi

__SIGNOFF__

  TMPERR="/tmp/wd_smtp_err_$$"
__MAILCMD__

  MAIL_EXIT=$?
  rm -f "$TMPMAIL"

  if [ "$MAIL_EXIT" -ne 0 ]; then
    SMTP_ERR=$(cat "$TMPERR" 2>/dev/null | tail -20 | tr '\n' '|')
    log "Email FAILED (mailer exit=$MAIL_EXIT) stderr=[${SMTP_ERR:-none}]"

    # No nc probe: BusyBox here is `nc IPADDR PORT` with no options, so `nc -w 5` failed on a
    # usage error and called every host unreachable. openssl answers the same question honestly.
    TMPDIAG="/tmp/wd_smtp_diag_$$"
    printf 'QUIT\r\n' | openssl s_client \
      -connect "$SMTP_HOST:$SMTP_PORT" \
      -CAfile /etc/ssl/certs/ca-certificates.crt \
      2>&1 | tail -20 > "$TMPDIAG"
    TLS_OUT=$(cat "$TMPDIAG" 2>/dev/null | tr '\n' '|')
    log "Email diag: SMTP probe [${TLS_OUT:-none}]"
    rm -f "$TMPDIAG"
  else
    log "Alert email sent ($STATUS)"
  fi

  rm -f "$TMPERR"
}

abort() {
  log "ERROR: $1"
  bump cfg_pia_wg_reconfig_fail
  DOWNLABEL="Tunnel has been down for"
  DOWNFOR="$(down_for)"
  # The next attempt is whichever comes later: the backoff expiring, or the next cron tick.
  NEXTWAIT="$(backoff_for "${CNT:-1}")"
  case "$INTERVAL" in ''|*[!0-9]*) TICK=300 ;; *) TICK=$((INTERVAL * 60)) ;; esac
  [ "$NEXTWAIT" -ge "$TICK" ] || NEXTWAIT="$TICK"
  ATTEMPTV="${CNT:-1} since the last success, retrying per schedule, $((NEXTWAIT / 60)) minutes"
  send_alert FAILED "$1"
  rm -f "$TMPSRV"
  exit 1
}

# Connectivity check
FAIL=1
log "Checking $IFACE $DESC connectivity"

if ! ifconfig "$IFACE" >/dev/null 2>&1; then
  log "Interface $IFACE is down or absent"
else
  # A handshake is the peer answering; ping -I is not a liveness test on stock, where the
  # router's own traffic is not routed into wgcN. Ping kept as a fallback for Merlin.
  HS="$(wg show "$IFACE" latest-handshakes 2>/dev/null | awk '{if ($2 > m) m = $2} END {print m + 0}')"
  AGE=$(( $(date +%s) - HS ))
  if [ "$HS" -gt 0 ] && [ "$AGE" -lt 300 ]; then
    log "Handshake ${AGE}s ago"
    HSDESC=" (handshake ${AGE}s ago)"
    FAIL=0
  elif ping -I "$IFACE" -c 3 -W 2 "$PRIMARY_IP" >/dev/null 2>&1; then
    log "Primary ping OK ($PRIMARY_IP)"
    FAIL=0
  elif ping -I "$IFACE" -c 3 -W 2 "$SECONDARY_IP" >/dev/null 2>&1; then
    log "Secondary ping OK ($SECONDARY_IP)"
    FAIL=0
  else
    log "No handshake and both pings failed ($PRIMARY_IP, $SECONDARY_IP)"
  fi
fi

# Success: update status
if [ "$FAIL" = "0" ]; then
  date '+%s %Y-%m-%d %H:%M:%S' > "$STATUSFILE"
  printf '0\n0\n' > "$BACKOFFFILE"
  # A deploy run always emails, even with nothing to fix: it is the user's proof that alerting
  # works. No addKey happened on this path, so the endpoint comes from NVRAM and there is no
  # server name or latency to report.
  if [ "$RUNMODE" = "deploy" ]; then
    CONNLABEL="Connected to"
    CONNVALUE="$(nvram get ${K}ep_addr):$(nvram get ${K}ep_port)$HSDESC"
    INTERVALV="$INTERVAL minutes"
    send_alert SUCCESS "watchdog deployed"
  fi
  exit 0
fi

# Backoff handling. CNT counts attempts actually MADE, not checks that found a fault: a run the
# backoff turns away leaves it alone, so how fast the wait grows does not depend on the check
# interval. Reset to 0 by the success path above.
CNT=0
LAST=0
if [ -f "$BACKOFFFILE" ]; then
  { read -r CNT; read -r LAST; } < "$BACKOFFFILE"
  case "$CNT" in ''|*[!0-9]*) CNT=0 ;; esac
  case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
fi
NOW="$(date +%s)"
WAIT="$(backoff_for "$CNT")"
ELAPSED=$((NOW - LAST))
if [ "$LAST" -ne 0 ] && [ "$ELAPSED" -lt "$WAIT" ]; then
  # Say why nothing is happening; a long quiet gap otherwise reads as a stopped watchdog.
  log "Backing off after $CNT failed attempts: ${ELAPSED}s of ${WAIT}s elapsed"
  exit 0
fi
CNT=$((CNT + 1))
printf '%s\n%s\n' "$CNT" "$NOW" > "$BACKOFFFILE"
log "Connectivity lost; reconfiguring (attempt #$CNT)"

# Preflight checks
[ -n "$DESC" ] || abort "${K}desc is empty"
[ -x "$JQ" ] || command -v "$JQ" >/dev/null 2>&1 || abort "jq is not installed"
[ -n "$PIA_USER" ] || abort "PIA username is not set"

# Check connectivity
if ping -c 1 -W 2 "$PRIMARY_IP" >/dev/null 2>&1 || ping -c 1 -W 2 "$SECONDARY_IP" >/dev/null 2>&1; then
  log "WAN has internet connectivity"
else
  log "no Internet on WAN interface, exiting."
  exit 0
fi

# PIA re-negotiation
if [ ! -f "$CACERT" ]; then
  log "CA cert not cached; downloading"
  mkdir -p "${CACERT%/*}" || abort "failed to create ${CACERT%/*}"
  $CURL "$CACERT_URL" -o "$CACERT" || abort "failed to download CA cert"
  echo -n > /jffs/curllst
  openssl x509 -noout -in "$CACERT" >/dev/null 2>&1 || abort "CA cert is not valid PEM"
  log "CA cert cached at $CACERT"
else
  log "Using cached CA cert"
fi

log "Requesting PIA token for user $PIA_USER"
# Body to a file, status to stdout: a pipe into jq would discard curl's exit status.
HTTP="$($CURLB -S -o "$TMPTOK" -w '%{http_code}' -u "$PIA_USER:$PIA_PASS" "$TOKEN_URL" 2>"$TMPERR")"
RC=$?
TOKEN="$("$JQ" -r '.token // empty' < "$TMPTOK" 2>/dev/null)"
if [ -z "$TOKEN" ]; then
  # The body is the evidence when the status is not: seen once as exit 0 with no status at all.
  BSZ="$(wc -c < "$TMPTOK" 2>/dev/null | tr -d ' ')"
  BODY="$(head -n 1 "$TMPTOK" 2>/dev/null | cut -c1-60)"
  rm -f "$TMPTOK"
  abort "failed to obtain PIA token (exit $RC, HTTP ${HTTP:-none}, body ${BSZ:-0}B: ${BODY:-empty}) $(head -n 1 "$TMPERR" | cut -c1-80)"
fi
rm -f "$TMPTOK"
echo -n > /jffs/curllst
log "PIA token obtained (len=$(echo -n "$TOKEN" | wc -c))"

log "Fetching server list for region $REGION"
SERVERS="$($CURL "$SERVERLIST_URL" | head -1 | "$JQ" -r --arg id "$REGION" '.regions[] | select(.id==$id) | .servers.wg[] | "\(.ip) \(.cn)"')"
[ -n "$SERVERS" ] || abort "no servers found for region $REGION"
log "Servers: $(echo "$SERVERS" | wc -l | tr -d ' ') candidates"
echo -n > /jffs/curllst

# Latency sweep
echo "$SERVERS" > "$TMPSRV"
BEST_IP=""
BEST_CN=""
BEST_RTT=999999
while read -r SIP SCN; do
  [ -n "$SIP" ] || continue
  RTT="$(ping -c 1 -W 2 "$SIP" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -1)"
  RTT_INT="${RTT%.*}"; : "${RTT_INT:=999998}"
  log "Latency to $SIP ($SCN): ${RTT_INT}ms"
  if [ "$RTT_INT" -lt "$BEST_RTT" ]; then
    BEST_RTT="$RTT_INT"
    BEST_IP="$SIP"
    BEST_CN="$SCN"
  fi
done < "$TMPSRV"
rm -f "$TMPSRV"
if [ -z "$BEST_IP" ]; then
  BEST_IP="$(echo "$SERVERS" | head -1 | awk '{print $1}')"
  BEST_CN="$(echo "$SERVERS" | head -1 | awk '{print $2}')"
fi
[ -n "$BEST_IP" ] || abort "could not select a server for region $REGION"
log "Selected server $BEST_IP ($BEST_CN) for region $DESC"

log "Generating WireGuard keypair"
PRIV="$(wg genkey)"
PUB="$(echo "$PRIV" | wg pubkey)"
log "Registering public key with $BEST_IP ($BEST_CN)"

# exit 35 TLS, 60 CA, 22 HTTP, 7 connect. -S so -s does not swallow the reason.
REG="$($CURL -S --cacert "$CACERT" --resolve "$BEST_CN:1337:$BEST_IP" -G --data-urlencode "pt=$TOKEN" --data-urlencode "pubkey=$PUB" "https://$BEST_CN:1337/addKey" 2>"$TMPERR")"
RC=$?
[ $RC -eq 0 ] || abort "curl addKey failed (exit $RC: $(head -n 1 "$TMPERR" | cut -c1-160))"
echo -n > /jffs/curllst
log "addKey response received"
RSTATUS="$(echo "$REG" | "$JQ" -r '.status // empty')"
[ "$RSTATUS" = "OK" ] || abort "addKey failed (status: $RSTATUS)"
read -r PEER_IP SERVER_KEY SERVER_PORT <<EOF
$(echo "$REG" | "$JQ" -r '[(.peer_ip // "" | split("/")[0]), (.server_key // ""), (.server_port // "")] | @tsv')
EOF
[ -n "$PEER_IP" ] && [ -n "$SERVER_KEY" ] && [ -n "$SERVER_PORT" ] || abort "incomplete addKey response"

# Write new config to NVRAM
log "Writing config to NVRAM"
nvset "addr=$PEER_IP/32"
nvset "alive=25"
nvset "desc=$DESC"
nvset "enable=1"
nvset "ep_addr=$BEST_IP"
nvset "ep_port=$SERVER_PORT"
nvset "mtu=1420"
nvset "nat=1"
nvset "ppub=$SERVER_KEY"
nvset "priv=$PRIV"
nvset "psk="
nvset "aips=0.0.0.0/0"
__MERLINONLY__
nvram commit
log "NVRAM write complete"

# Restart interface
# Increase sleeps on slow routers
log "Stopping $IFACE"
service "stop_wgc $SLOT"
sleep 2
log "Starting $IFACE"
service "start_wgc $SLOT"
log "Restarting VPN routing"
service restart_vpnrouting0

log "Waiting for $IFACE to initialise"
sleep 3
if ! ifconfig "$IFACE" >/dev/null 2>&1; then
  abort "Interface $IFACE did not come up after reconfiguration"
fi
log "Interface $IFACE is up"

log "Reconfig SUCCESS: region $DESC via $BEST_IP:$SERVER_PORT"
bump cfg_pia_wg_reconfig_ok
CONNLABEL="Reconnected to"
CONNVALUE="$BEST_CN ($BEST_IP:$SERVER_PORT), ${BEST_RTT} ms"
DOWNLABEL="Tunnel was down for"
# Measure the outage before stamping the status file, or it always reads zero.
DOWNFOR="$(down_for)"
date '+%s %Y-%m-%d %H:%M:%S' > "$STATUSFILE"
INTERVALV="$INTERVAL minutes"
send_alert SUCCESS "reconfigured successfully on attempt $CNT"
exit 0
''';
