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

// ─── PIA negotiation endpoints (mirrored from pia_service.dart) ─────────────────
// Kept in one place so the Bash re-negotiation and the Dart app stay in sync.
const String kPiaServerListUrl = 'https://serverlist.piaservers.net/vpninfo/servers/v6';
const String kPiaTokenUrl = 'https://www.privateinternetaccess.com/gtoken/generateToken';
const String kPiaCaCertUrl = 'https://raw.githubusercontent.com/pia-foss/manual-connections/master/ca.rsa.4096.crt';

// Syslog tag used by every router-side log line (Bash scripts + Dart deploy/delete).
const String kWatchdogLogTag = 'cfg-pia-wg';

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
  final t = raw.trim();
  if (t.isEmpty) return null;
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
String heredocWrite(String path, String body) {
  final b = body.endsWith('\n') ? body : '$body\n';
  return "cat > '$path' <<'WATCHDOG_EOF'\n${b}WATCHDOG_EOF";
}

// The watchdog check cron job line (added via `cru a`).
String buildCronCheckLine(int slot, int intervalMin) =>
    'cru a watchdog_wgc$slot "*/$intervalMin * * * *" /jffs/scripts/watchdog_wgc$slot.sh';

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

// RFC-822 message body for the one-off "Test Email" (and the success/failure model).
String buildMailBody(WatchdogConfig c, {required bool success, bool testMode = false}) {
  final subject = testMode ? 'watchdog config test' : '${c.emailSubject} - ${success ? 'SUCCESS' : 'FAILED'}';
  final line = testMode
      ? 'This is a test email from the cfg-pia-wg watchdog (slot wgc${c.slotIndex}).'
      : 'Watchdog wgc${c.slotIndex} reconfiguration ${success ? 'succeeded' : 'failed'}.';
  final now = DateTime.now();
  final epochSecs = now.millisecondsSinceEpoch ~/ 1000;
  final (host, _) = c.smtpHostPort;
  return 'From: ${c.emailFrom}\r\n'
      'To: ${c.emailTo}\r\n'
      'Subject: $subject\r\n'
      'Date: ${_rfc2822Date(now)}\r\n'
      'Message-ID: <$epochSecs.${c.slotIndex}@$host>\r\n'
      'MIME-Version: 1.0\r\n'
      'Content-Type: text/plain; charset=utf-8\r\n'
      '\r\n'
      '$line\r\n';
}

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

// The full /jffs/scripts/watchdog_wgcN.sh body. Slot-parameterised via __SLOT__.
String buildWatchdogScript(WatchdogConfig c) => _kWatchdogScriptTemplate.replaceAll('__SLOT__', '${c.slotIndex}');

// ─── Service ─────────────────────────────────────────────────────────────────────

class RouterWatchdog {
  final SSHClient client;
  final void Function(String, {bool isError, bool isSuccess})? onLog;

  RouterWatchdog(this.client, {this.onLog});

  // Run a command and return trimmed stdout (mirrors router_push.dart `_run`).
  Future<String> _run(String cmd) async => utf8.decode(await client.run(cmd)).trim();

  // Heredoc writes can stall if the SSH channel hangs; bound them at 30s (spec §3) and
  // surface a troubleshooting message on timeout.
  Future<String> _runHeredoc(String cmd, String path) async {
    try {
      return await _run(cmd).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw Exception(
        'Timed out after 30s writing to "$path" via SSH heredoc. '
        'Check SSH connectivity and that the router filesystem (JFFS / /tmp) is writable.',
      );
    }
  }

  // Best-effort native syslog entry on the router.
  Future<void> _logRouter(String msg) async => _run('logger -t $kWatchdogLogTag ${shellSingleQuote(msg)}');

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

  Future<bool> isJqInstalled() async => (await _run('which jq')).isNotEmpty;

  // Ensures JFFS custom scripts are enabled
  Future<void> enableJffsScripts() async {
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
      await _run('nvram set wgc${config.slotIndex}_desc=${shellSingleQuote(desc)}');
    }
    await _run('nvram commit');
  }

  // The single CREATE/EDIT path: persist the watchdog params, enable the VPN slot, then deploy
  // every runtime artifact (script, both cron jobs, services-start persistence) and run the script
  // once so the watchdog is live immediately rather than at its next scheduled interval.
  //
  // deactivateOtherSlots MUST run before _writeWatchdogNvram: stopWatchdog unsets the GLOBAL
  // cfg_pia_wg_user / cfg_pia_wg_password keys, so sweeping afterwards would wipe the PIA
  // credentials this deploy just wrote.
  Future<void> deployWatchdog(WatchdogConfig config, {String? desc}) => _guard('deploy', () async {
        await enableJffsScripts();
        await deactivateOtherSlots(config.slotIndex);
        await _writeWatchdogNvram(config, desc: desc);
        await enableVpnSlot(config.slotIndex);
        await _runHeredoc(
          heredocWrite('/jffs/scripts/watchdog_wgc${config.slotIndex}.sh', buildWatchdogScript(config)),
          '/jffs/scripts/watchdog_wgc${config.slotIndex}.sh',
        );
        await _run('chmod +x /jffs/scripts/watchdog_wgc${config.slotIndex}.sh');
        await _run(buildCronCheckLine(config.slotIndex, config.cronIntervalMinutes));
        await _run(buildCronRotateLine(config.slotIndex));
        await _ensureServicesStart(config.slotIndex, config.cronIntervalMinutes);
        onLog?.call('Watchdog settings saved for wgc${config.slotIndex}.', isSuccess: true);
        await _logRouter('Running /jffs/scripts/watchdog_wgc${config.slotIndex}.sh');
        await _run('/jffs/scripts/watchdog_wgc${config.slotIndex}.sh');
        onLog?.call('Ran /jffs/scripts/watchdog_wgc${config.slotIndex}.sh', isSuccess: true);
        await _logRouter('Watchdog deployed for wgc${config.slotIndex} (check interval is ${config.cronIntervalMinutes}m)');
        onLog?.call('Watchdog deployed for wgc${config.slotIndex}.', isSuccess: true);
      });

  // Enables the underlying WireGuard slot
  Future<void> enableVpnSlot(int slot) => _guard('enable VPN slot', () async {
        await _run('nvram set wgc${slot}_enable=1');
        await _run('nvram commit');
        await _run('service "start_wgc $slot"; service restart_vpnrouting0');
        await _logRouter('Enabled wgc$slot via watchdog interface');
        onLog?.call('wgc$slot enabled.', isSuccess: true);
      });

  // Disables the underlying WireGuard slot (mirrors RouterSlotService.disableSlot). Clearing
  // the enable flag matters as much as stopping the service: without it the slot comes back on
  // the next start_vpnrouting0 or reboot.
  Future<void> disableVpnSlot(int slot) => _guard('disable VPN slot', () => _disableVpnSlot(slot));

  // Unguarded body, so stopWatchdog can reuse it without nesting _guard (which would log the
  // same failure twice).
  Future<void> _disableVpnSlot(int slot) async {
    await _run('nvram set wgc${slot}_enable=0');
    await _run('nvram commit');
    await _run('service "stop_wgc $slot"; service start_vpnrouting0');
    await _logRouter('Disabled wgc$slot');
    onLog?.call('wgc$slot disabled.', isSuccess: true);
  }

  // Only one watchdog / WireGuard interface may ever be active at a time (same rule the manage
  // ENABLE path applies in slot_modal.dart). Scans wgc1..5 and tears down every slot except
  // [keepSlot]: its watchdog first (cron + script + tmp files), then the interface itself.
  //
  // Deliberately not wrapped in _guard: stopWatchdog and disableVpnSlot are guarded already and
  // every caller is too, so an extra layer would log the same failure three times.
  Future<void> deactivateOtherSlots(int keepSlot) async {
    final iface = await _run('wg show interfaces');
    for (var slot = 1; slot <= 5; slot++) {
      if (slot == keepSlot) continue;
      final hasWatchdog = (await _run('cru l | grep -qw watchdog_wgc$slot && echo 1 || echo 0')) == '1';
      final enabled = (await _run('nvram get wgc${slot}_enable')) == '1';
      // The interface check is a superset of the nvram flag: it also catches a tunnel that is
      // still up while wgcN_enable already reads 0.
      if (!hasWatchdog && !enabled && !iface.contains('wgc$slot')) continue;
      onLog?.call('Only one watchdog may be active - deactivating wgc$slot...');
      // stopWatchdog tears the interface down as part of its own teardown; a bare slot only
      // needs the interface disabling.
      if (hasWatchdog) {
        await stopWatchdog(slot);
      } else {
        await disableVpnSlot(slot);
      }
    }
  }

  // Creates services-start if absent, strips any prior entries for this slot, appends fresh ones.
  Future<void> _ensureServicesStart(int slot, int intervalMin) async {
    const path = '/jffs/scripts/services-start';
    await _run("[ -f '$path' ] || { echo '#!/bin/sh' > '$path'; chmod +x '$path'; }");
    await _run(
      "grep -v -e 'watchdog_wgc$slot ' -e 'watchdog_log_rotate_wgc$slot ' '$path' > '$path.tmp' 2>/dev/null; "
      "mv '$path.tmp' '$path'",
    );
    await _run("printf '%s\\n' ${shellSingleQuote(buildCronCheckLine(slot, intervalMin))} >> '$path'");
    await _run("printf '%s\\n' ${shellSingleQuote(buildCronRotateLine(slot))} >> '$path'");
    await _run("chmod +x '$path'");
  }

  // Full disable: unset NVRAM, remove cron jobs and service-start script
  // JFFS is intentionally left enabled.
  Future<void> stopWatchdog(int slot) => _guard('disable', () async {
        await _run('cru d watchdog_wgc$slot');
        await _run('cru d watchdog_log_rotate_wgc$slot');
        await _run('rm -f /jffs/scripts/watchdog_wgc$slot.sh');
        const path = '/jffs/scripts/services-start';
        // strip out cron jobs added when watchdog installed, reinstate 700 permission
        await _run(
          "[ -f '$path' ] && grep -v -e 'watchdog_wgc$slot ' -e 'watchdog_log_rotate_wgc$slot ' '$path' "
          "> '$path.tmp' && mv '$path.tmp' '$path' && chmod 700 '$path'",
        );
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
        await _run('nvram unset cfg_pia_wg_password');
        await _run('nvram unset cfg_pia_wg_user');
        await _run('nvram commit');
        onLog?.call('NVRAM committed.', isSuccess: true);
        // Bring the tunnel down too, otherwise disabling the watchdog leaves an unsupervised VPN
        // running. This previously issued `service "stop_wgc wgc$slot"` — the service expects the
        // bare slot index (see ARCHITECTURE.md), so the interface was never actually stopped.
        await _disableVpnSlot(slot);
        await _logRouter('Watchdog disabled for wgc$slot');
        onLog?.call('Watchdog disabled for wgc$slot.', isSuccess: true);
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
    final cronEnabled = (await _run('cru l | grep -qw watchdog_wgc$slot && echo 1 || echo 0')) == '1';
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
  Future<void> testEmail(WatchdogConfig config) => _guard('test email', () async {
        final (host, port) = config.smtpHostPort;

        await _runHeredoc(heredocWrite('/tmp/mail.txt', buildMailBody(config, success: true, testMode: true)), '/tmp/mail.txt');

        // Redirect stderr to file; echo exit code into stdout so _run can return it.
        final result = await _run('${buildSendmailCommand(host, port, config)} 2>/tmp/wd_smtp_err; echo "EXITCODE:\$?"');

        final exitCode = _parseExitCode(result);

        if (exitCode == 0) {
          await _run('rm -f /tmp/mail.txt /tmp/wd_smtp_err');
          await _logRouter('Test email sent to ${config.emailTo}');
          onLog?.call('Test email sent.', isSuccess: true);
          return;
        }

        // Layer 1: sendmail stderr
        final stderrRaw = await _run('cat /tmp/wd_smtp_err 2>/dev/null | head -20 | tr "\\n" "|"');
        await _logRouter('Email FAILED (exit=$exitCode) stderr=[${stderrRaw.trim()}]');

        // Layer 2: TCP reachability
        final ncResult = await _run('nc -w 5 $host $port </dev/null >/dev/null 2>&1; echo "EXITCODE:\$?"');
        final tcpOk = _parseExitCode(ncResult) == 0;
        await _logRouter(
            tcpOk ? 'TCP diag: $host:$port is reachable' : 'TCP diag: $host:$port is UNREACHABLE - check host and port');

        // Layer 3: TLS handshake probe (only worth running if TCP is up)
        if (tcpOk) {
          final tlsOut = await _run(
            'printf "QUIT\\r\\n" | openssl s_client '
            '-connect $host:$port '
            '-tls1_3 '
            '-CAfile /etc/ssl/certs/ca-certificates.crt '
            '-timeout 10 '
            '2>&1 | head -40 | tr "\\n" "|"',
          );
          await _logRouter('TLS probe: ${tlsOut.trim()}');
        }

        await _run('rm -f /tmp/mail.txt /tmp/wd_smtp_err');
        onLog?.call('Test email failed - see router log for details.', isSuccess: false);
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

SLOT=__SLOT__
IFACE="wgc__SLOT__"
K="${IFACE}_"
LOGTAG="cfg-pia-wg"
LOGFILE="/tmp/watchdog_${IFACE}.log"
STATUSFILE="/tmp/watchdog_last_ping_success_${IFACE}"
BACKOFFFILE="/tmp/watchdog_backoff_${IFACE}"
COOLDOWN=120
CACERT="/jffs/pia_ca.rsa.4096.crt"
CURL="curl -s --max-time 15 --connect-timeout 8 --tlsv1.3 --fail"
TMPMAIL="/tmp/mail_${IFACE}.txt"
TMPSRV="/tmp/${IFACE}_servers.txt"
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
PIA_USER="$(nvram get cfg_pia_wg_user)"
PIA_PASS="$(nvram get cfg_pia_wg_password)"

log "Watchdog started for $IFACE"

# Email alert
send_alert() {
  [ "$EMAIL_ON" = "1" ] || return 0
  [ -n "$SMTP_HOST" ] || { log "Email enabled but SMTP server is not configured"; return 0; }

  {
    echo "From: $EMAIL_FROM"
    echo "To: $EMAIL_TO"
    echo "Subject: $EMAIL_SUBJECT - $1"
    echo "Date: $(date -R 2>/dev/null || date)"
    echo "Message-ID: $(date +%s)@$(hostname)"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/plain; charset=utf-8"
    echo ""
    echo "Watchdog $IFACE reconfiguration: $1"
    echo "Region: $DESC"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  } > "$TMPMAIL"

  TMPERR="/tmp/wd_smtp_err_$$"
  /usr/sbin/sendmail \
    -H "exec openssl s_client -quiet -tls1_3 -CAfile /etc/ssl/certs/ca-certificates.crt \
    -verify_return_error -connect $SMTP_HOST:$SMTP_PORT" \
    -au"$SMTP_USER" \
    -ap"$SMTP_PASS" \
    -f"$EMAIL_FROM" \
    "$EMAIL_TO" < "$TMPMAIL" 2>"$TMPERR"

  MAIL_EXIT=$?
  rm -f "$TMPMAIL"

  if [ "$MAIL_EXIT" -ne 0 ]; then
    SMTP_ERR=$(cat "$TMPERR" 2>/dev/null | head -20 | tr '\n' '|')
    log "Email FAILED (sendmail exit=$MAIL_EXIT) stderr=[${SMTP_ERR:-none}]"

    nc -w 5 "$SMTP_HOST" "$SMTP_PORT" </dev/null >/dev/null 2>&1 \
      && log "Email diag: TCP $SMTP_HOST:$SMTP_PORT reachable" \
      || log "Email diag: TCP $SMTP_HOST:$SMTP_PORT UNREACHABLE"

    TMPDIAG="/tmp/wd_smtp_diag_$$"
    printf 'QUIT\r\n' | openssl s_client \
      -connect "$SMTP_HOST:$SMTP_PORT" \
      -tls1_3 \
      -CAfile /etc/ssl/certs/ca-certificates.crt \
      -timeout 10 \
      2>&1 | head -40 > "$TMPDIAG"
    TLS_EXIT=$?
    TLS_OUT=$(cat "$TMPDIAG" 2>/dev/null | tr '\n' '|')
    log "Email diag: TLS probe (exit=$TLS_EXIT) detail=[${TLS_OUT:-none}]"
    rm -f "$TMPDIAG"
  else
    log "Alert email sent ($1)"
  fi

  rm -f "$TMPERR"
}

abort() {
  log "ERROR: $1"
  send_alert "FAILED ($1)"
  rm -f "$TMPSRV"
  exit 1
}

# Connectivity check
FAIL=1
log "Checking $IFACE $DESC connectivity"

if ! ifconfig "$IFACE" >/dev/null 2>&1; then
  log "Interface $IFACE is down or absent"
else
  if ping -I "$IFACE" -c 3 -W 2 "$PRIMARY_IP" >/dev/null 2>&1; then
    log "Primary ping OK ($PRIMARY_IP)"
    FAIL=0
  elif ping -I "$IFACE" -c 3 -W 2 "$SECONDARY_IP" >/dev/null 2>&1; then
    log "Secondary ping OK ($SECONDARY_IP)"
    FAIL=0
  else
    log "Primary and Secondary pings FAILED ($PRIMARY_IP, $SECONDARY_IP)"
    log "Both ping targets unreachable via $IFACE"
  fi
fi

# Success: update status
if [ "$FAIL" = "0" ]; then
  date '+%Y-%m-%d %H:%M:%S' > "$STATUSFILE"
  printf '0\n0\n' > "$BACKOFFFILE"
  exit 0
fi

# Backoff handling
CNT=0
LAST=0
if [ -f "$BACKOFFFILE" ]; then
  { read -r CNT; read -r LAST; } < "$BACKOFFFILE"
  [ -n "$CNT" ] || CNT=0
  [ -n "$LAST" ] || LAST=0
fi
NOW="$(date +%s)"
CNT=$((CNT + 1))
ELAPSED=$((NOW - LAST))
if [ "$LAST" -ne 0 ] && [ "$ELAPSED" -lt "$COOLDOWN" ]; then
  printf '%s\n%s\n' "$CNT" "$LAST" > "$BACKOFFFILE"
  log "Cooldown ${ELAPSED}s < ${COOLDOWN}s; skipping"
  exit 0
fi
printf '%s\n%s\n' "$CNT" "$NOW" > "$BACKOFFFILE"
log "Connectivity lost; reconfiguring (attempt #$CNT)"

# Preflight checks
[ -n "$DESC" ] || abort "${K}desc is empty"
which jq >/dev/null 2>&1 || abort "jq is not installed"
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
  $CURL "$CACERT_URL" -o "$CACERT" || abort "failed to download CA cert"
  echo -n > /jffs/curllst
  openssl x509 -noout -in "$CACERT" >/dev/null 2>&1 || abort "CA cert is not valid PEM"
  log "CA cert cached at $CACERT"
else
  log "Using cached CA cert"
fi

log "Requesting PIA token for user $PIA_USER"
TOKEN="$($CURL -u "$PIA_USER:$PIA_PASS" "$TOKEN_URL" | jq -r '.token // empty')"
[ -n "$TOKEN" ] || abort "failed to obtain PIA token"
echo -n > /jffs/curllst
log "PIA token obtained (len=$(echo -n "$TOKEN" | wc -c))"

log "Fetching server list for region $DESC"
SERVERS="$($CURL "$SERVERLIST_URL" | head -1 | jq -r --arg id "$DESC" '.regions[] | select(.id==$id) | .servers.wg[] | "\(.ip) \(.cn)"')"
[ -n "$SERVERS" ] || abort "no servers found for region $DESC"
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
[ -n "$BEST_IP" ] || abort "could not select a server for region $DESC"
log "Selected server $BEST_IP ($BEST_CN) for region $DESC"

log "Generating WireGuard keypair"
PRIV="$(wg genkey)"
PUB="$(echo "$PRIV" | wg pubkey)"
log "Registering public key with $BEST_IP ($BEST_CN)"

REG="$($CURL --cacert "$CACERT" --resolve "$BEST_CN:1337:$BEST_IP" -G --data-urlencode "pt=$TOKEN" --data-urlencode "pubkey=$PUB" "https://$BEST_CN:1337/addKey")" || abort "curl addKey request failed"
echo -n > /jffs/curllst
log "addKey response received"
RSTATUS="$(echo "$REG" | jq -r '.status // empty')"
[ "$RSTATUS" = "OK" ] || abort "addKey failed (status: $RSTATUS)"
read -r PEER_IP SERVER_KEY SERVER_PORT <<EOF
$(echo "$REG" | jq -r '[(.peer_ip // "" | split("/")[0]), (.server_key // ""), (.server_port // "")] | @tsv')
EOF
[ -n "$PEER_IP" ] && [ -n "$SERVER_KEY" ] && [ -n "$SERVER_PORT" ] || abort "incomplete addKey response"

# Write new config to NVRAM
log "Writing config to NVRAM"
nvset "addr=$PEER_IP/32"
nvset "alive=25"
nvset "desc=$DESC"
nvset "enable=1"
nvset "enforce=1"
nvset "ep_addr=$BEST_IP"
nvset "ep_addr_r="
nvset "ep_port=$SERVER_PORT"
nvset "fw=1"
nvset "mtu=1420"
nvset "nat=1"
nvset "ppub=$SERVER_KEY"
nvset "priv=$PRIV"
nvset "psk="
nvset "rip="
nvset "aips=0.0.0.0/0"
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
send_alert "SUCCESS"
exit 0
''';
