// router_command.dart - one router command, its output, and whether it actually worked.
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
// Until build 413 every router command went through `utf8.decode(await client.run(cmd)).trim()`,
// which has two problems that only look small:
//
//   1. `SSHClient.run` MERGES stderr into stdout. A command that failed returned its error message
//      where its answer should have been - so `nvram get wgcN_desc` failing could hand back
//      "nvram: can't open /dev/nvram" and the app would carry on with that as a region name. An
//      error mistaken for a value is a data-integrity bug, not a logging gap, and no amount of
//      parsing fixes it once the two are indistinguishable.
//
//   2. `run` DISCARDS the exit code. Of 125 router commands the app issues, ten encoded success in
//      their own output (`&& echo OK || echo FAIL`); the other 115 could fail in silence.
//
// `runWithResult` gives stdout, stderr and the exit code separately, so both are answerable. The
// policy on top of it is deliberately asymmetric, because reads and writes fail differently:
//
//   - **Writes throw.** `nvram set`, `cru a`, `service`, `mv`, `chmod` - a silent failure here
//     leaves the router in a state the app then reports as success. That is the case worth being
//     noisy about.
//   - **Reads do not.** A failed `nvram get` or `cat` returns empty, which every caller already
//     handles, and non-zero is routine: `cru d` on an absent job, `grep -c` finding nothing,
//     `which jq` as a probe. Throwing on those would produce a flood of false alarms, and an alarm
//     that cries wolf gets dismissed along with the one that mattered.
//
// Either way the failure is LOGGED with its exit code and stderr, so it is diagnosable from the app
// log and the router syslog even when it is not worth interrupting anyone over.

import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

/// A router command's separated output and exit status.
class RouterResult {
  const RouterResult({required this.stdout, required this.stderr, required this.exitCode});

  /// Standard output only - never contaminated with an error message.
  final String stdout;

  /// Standard error only. Empty on success for almost every BusyBox tool.
  final String stderr;

  /// Null when the remote end reported none, which is not the same as zero.
  final int? exitCode;

  /// A null exit code is treated as success: some `service` calls return without one, and
  /// inventing a failure from missing metadata would be worse than assuming it worked.
  bool get ok => exitCode == null || exitCode == 0;

  /// The most useful one-line description of a failure: the code, then whatever the command said.
  String get failureDetail {
    final err = stderr.trim().split('\n').first.trim();
    final code = exitCode == null ? 'no exit code' : 'exit $exitCode';
    return err.isEmpty ? code : '$code: ${err.length > 160 ? '${err.substring(0, 160)}...' : err}';
  }
}

/// Secrets that must never reach a log line, matched against the KEY of a `name=value` pair.
///
/// The app log is shown on screen and copied into bug reports, so a failed
/// `nvram set wgc1_wd_smtp_pass=hunter2` must not be reported verbatim. Redacting by key rather
/// than by looking for secret-shaped values is the only version that cannot miss one.
const List<String> kSecretKeyFragments = ['pass', 'password', 'priv', 'psk', 'token', 'key', 'user'];

/// [command] with the value of any secret-looking assignment replaced, and trimmed to [maxLength].
///
/// Deliberately conservative: it redacts the value of anything whose key contains a fragment
/// above, including `cfg_pia_wg_user`, because a PIA username identifies an account.
String redactCommand(String command, {int maxLength = 120}) {
  final redacted = command.replaceAllMapped(
    // key=value, where value is either quoted or runs to the next space.
    RegExp(r"""([A-Za-z0-9_./-]+)=('[^']*'|"[^"]*"|\S*)"""),
    (m) {
      final key = m.group(1)!.toLowerCase();
      return kSecretKeyFragments.any(key.contains) ? '${m.group(1)}=<redacted>' : m.group(0)!;
    },
  );
  return redacted.length <= maxLength ? redacted : '${redacted.substring(0, maxLength)}...';
}

/// Thrown when a command that was expected to succeed did not.
///
/// Carries the redacted command so a report is actionable without leaking credentials.
class RouterCommandException implements Exception {
  RouterCommandException(this.command, this.result);

  final String command;
  final RouterResult result;

  @override
  String toString() => 'Router command failed (${result.failureDetail}): ${redactCommand(command)}';
}

/// Runs [cmd] and separates stdout, stderr and the exit code.
///
/// Shared by [RouterSlotService] and `RouterWatchdog` so the failure policy lives in one place.
/// [allowFailure] tolerates a non-zero exit; the failure is logged either way.
Future<RouterResult> runRouterCommand(
  SSHClient client,
  String cmd, {
  bool allowFailure = false,
  void Function(String message, {bool isError, bool isSuccess})? onLog,
}) async {
  final raw = await client.runWithResult(cmd);
  final result = RouterResult(
    stdout: utf8.decode(raw.stdout, allowMalformed: true).trim(),
    stderr: utf8.decode(raw.stderr, allowMalformed: true).trim(),
    exitCode: raw.exitCode,
  );
  if (result.ok) return result;

  // Logged whether or not it is fatal. The command is redacted: the app log is shown on screen and
  // pasted into bug reports, and plenty of these carry a PIA or SMTP password.
  onLog?.call(
    'Router command failed (${result.failureDetail}): ${redactCommand(cmd)}',
    isError: !allowFailure,
  );
  if (allowFailure) return result;
  throw RouterCommandException(cmd, result);
}
