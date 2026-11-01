// router_script_integrity.dart - the scripts the app puts on the router are whole, and a broken one
// is never silent (ID-482 to ID-487).
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
// On 2026-10-29 an update from ABOUT left watchdog_wgc5.sh at 7,940 of its 49 KB: the write sent
// the file in pieces straight over the live one, the connection dropped after the second, and the
// size check that caught it could only throw, with the damaged file already in place. Cron ran it
// every five minutes; it stopped at a syntax error before its first log line, its output went to
// /dev/null, and its header still read build 553. Nothing said anything for a day.
//
// So: a file is written beside the live one and renamed over it only once it is whole (ID-482);
// every script that checks itself ends with a known last line (ID-484); and the app reads those last
// lines, with the cron entries and the faults the scripts recorded, whenever it first reaches a
// router (ID-486), replacing what is damaged or older in paid versions (ID-487).
// Plan: .claude/plans/plan_script-integrity.md

import 'dart:async';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';

import 'firmware.dart';
import 'router_watchdog.dart' show heredocWriteCommands, writtenByteCount, parseScriptVersion, RouterWatchdog;

/// The last line of a script that checks itself (ID-484): the watchdog scripts and guard.sh. The
/// script compares its own last line with this before it does anything else, and the app reads it
/// to tell a whole script from one cut short.
String scriptEndLine(String fileName) => '# end of $fileName';

/// The first build whose watchdog scripts and guard.sh end with [scriptEndLine]. A script from an
/// earlier build has no such line and is out of date, not damaged.
const int kFirstBuildWithEndLine = 554;

/// Shell printing each slot that has a device pinned to its WireGuard tunnel, once: the slots the
/// fail-closed guard protects, whose watchdogs email about the guard's faults (ID-484, Andrew's
/// decision 2026-10-31). The same reading of `vpnc_clientlist` the guard itself makes: a record is
/// desc>protocol>slot>...>table, the table 7th, and a pin names that table in its 4th field.
const String kGuardedSlotsShell = r'''CL="$(nvram get vpnc_clientlist)"; export CL; '''
    r'''nvram get vpnc_dev_policy_list | tr '<' '\n' | awk -F'>' 'BEGIN { n = split(ENVIRON["CL"], r, "<"); '''
    r'''for (i = 1; i <= n; i++) { split(r[i], f, ">"); if (f[2] == "WireGuard" && f[3] != "" && f[7] != "") s[f[7]] = f[3] } } '''
    r'''$1 == "1" && $2 != "" && ($4 in s) && !(s[$4] in seen) { seen[s[$4]] = 1; print s[$4] }' ''';

/// The build number in a version label, `v0.8.183 build 553` -> 553, or null.
int? scriptBuild(String? version) {
  final m = RegExp(r'build (\d+)').firstMatch(version ?? '');
  return m == null ? null : int.parse(m.group(1)!);
}

/// Where a write goes before it replaces [path] (ID-482). Unique per write, so two phones writing
/// the same file at once can't add their pieces to one another's.
String tempWritePath(String path, [Random? random]) {
  final r = random ?? Random.secure();
  return '$path.new.${List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join()}';
}

/// The line `tail -n 1` reports for [body] once written: the heredoc ends every file with a newline.
String lastLineOf(String body) {
  final b = body.endsWith('\n') ? body.substring(0, body.length - 1) : body;
  return b.split('\n').last;
}

/// Writes [body] to [path] on the router so that [path] only ever holds the old file, whole, or the
/// new one, whole (ID-482). Returns the size written.
///
/// The pieces go to a uniquely named file beside it ([tempWritePath]); its size and last line are
/// checked; then it is given [mode] and renamed over [path], which on one filesystem is a single
/// step. A run of the old script in progress keeps reading the file it opened, so replacing a
/// watchdog part-way through a rebuild no longer changes the script under it either. Any failure
/// leaves [path] as it was and throws, saying so; the temporary file is removed when the router can
/// still be reached, and otherwise by the next write to [path].
///
/// [run] throws on a non-zero exit; [read] never throws. [chunkTimeout] bounds each piece, and
/// [tidyTimeout] the removal of the temporary file after a failure.
Future<int> writeRouterFile({
  required String path,
  required String body,
  required String what,
  required String mode,
  required Future<String> Function(String cmd) run,
  required Future<String> Function(String cmd) read,
  Duration chunkTimeout = const Duration(seconds: 30),
  Duration tidyTimeout = const Duration(seconds: 10),
  Random? random,
}) async {
  final tmp = tempWritePath(path, random);
  final expected = writtenByteCount(body);
  final last = lastLineOf(body).trim();
  final kept = 'The router kept the $what it had, so nothing changed there';
  Future<Never> fail(String why) async {
    // Tidying up is worth trying, not worth losing the reason for, or waiting on: when the connection
    // has gone this fails too, or hangs on a socket nobody answers, and the next write to this path
    // removes the pieces instead.
    try {
      await read("rm -f '$tmp'").timeout(tidyTimeout);
    } catch (_) {}
    throw Exception('Writing $path failed: $why. $kept.');
  }

  try {
    for (final cmd in heredocWriteCommands(tmp, body)) {
      await run(cmd).timeout(chunkTimeout);
    }
  } on TimeoutException {
    await fail('a piece took longer than ${chunkTimeout.inSeconds}s to send. Check the connection to the router and '
        'that its filesystem (JFFS) is writable');
  } catch (e) {
    await fail('the connection failed part-way through (${e.toString().replaceFirst(RegExp(r'^Exception: '), '')})');
  }
  final size = int.tryParse((await read("wc -c < '$tmp' 2>/dev/null | tr -d ' '")).trim()) ?? 0;
  if (size != expected) {
    // Short and long are different faults (ID-136).
    await fail(size < expected
        ? 'the router has $size of the $expected bytes sent, so the file was cut short. The connection most likely '
            'dropped part-way through; try again, and if it happens again check that the router has space left on /jffs'
        : 'the router has $size bytes where $expected were sent, so part of the file arrived twice. That happens when '
            'the connection drops and a piece is sent again; try again');
  }
  if ((await read("tail -n 1 '$tmp' 2>/dev/null")).trim() != last) {
    await fail('the file arrived with a different last line from the one sent, so it is not the file the app wrote');
  }
  try {
    await run("chmod $mode '$tmp' && mv -f '$tmp' '$path'");
  } catch (e) {
    await fail('it could not be put in place (${e.toString().replaceFirst(RegExp(r'^Exception: '), '')})');
  }
  final placed = int.tryParse((await read("wc -c < '$path' 2>/dev/null | tr -d ' '")).trim()) ?? 0;
  if (placed != expected) {
    throw Exception('Writing $path failed: after it was put in place the router reports $placed bytes where '
        '$expected were sent. Try again.');
  }
  // Pieces a failed write left behind, here or from another phone, go now that this one is in place.
  await read("rm -f '$path'.new.*");
  return placed;
}

// ─── What is on the router (ID-486) ──────────────────────────────────────────────────────────────

/// One script the app put on the router, as [kScriptHealthCommand] read it.
class DeployedScript {
  const DeployedScript({
    required this.fileName,
    this.slot,
    this.scheduled = false,
    required this.exists,
    this.size = 0,
    this.version,
    this.lastLine = '',
  });

  /// `watchdog_wgc5.sh`, or `guard.sh`.
  final String fileName;

  /// The watchdog's slot; null for guard.sh.
  final int? slot;

  /// A watchdog cron entry names it.
  final bool scheduled;
  final bool exists;
  final int size;

  /// From its header, or null when it carries none.
  final String? version;
  final String lastLine;

  int? get build => scriptBuild(version);

  /// Scheduled, but not on the router at all.
  bool get missing => !exists && scheduled;

  /// Missing, or from a build that ends its scripts with [scriptEndLine] and not ending with it.
  bool get damaged =>
      missing || (exists && (build ?? 0) >= kFirstBuildWithEndLine && lastLine.trim() != scriptEndLine(fileName));

  /// From an earlier build than this app, or carrying no version at all. Unknown when the app's own
  /// version is (tests), so never claimed then.
  bool get olderThanApp {
    final app = scriptBuild(appVersionLabel);
    if (!exists || app == null) return false;
    final b = build;
    return b == null || b < app;
  }

  bool get newerThanApp {
    final app = scriptBuild(appVersionLabel);
    final b = build;
    return exists && app != null && b != null && b > app;
  }

  /// Whether the app should replace it: damaged, or older than the app. Never only for being
  /// newer: two phones on different builds would otherwise rewrite each other's scripts at every
  /// connection. A damaged one is replaced even then, since a script that can't run protects
  /// nothing.
  bool get needsUpdate => damaged || olderThanApp;

  /// The red line for both logs, or null when nothing is wrong with it.
  String? get problem {
    if (missing) return "ERROR: wgc$slot's watchdog is scheduled, but its script $fileName is missing from the router, so it is not running.";
    if (!damaged) return null;
    final runs = slot == null ? 'the fail-closed guard is not running' : 'that watchdog is not running';
    return 'ERROR: $fileName on the router is damaged ($size bytes, and its last line is missing), so $runs.';
  }
}

/// A fault a watchdog recorded on the router (ID-484, ID-485): when, and what it logged.
class ScriptFault {
  const ScriptFault({required this.slot, required this.at, required this.message});
  final int slot;
  final DateTime at;
  final String message;
}

class RouterScriptHealth {
  const RouterScriptHealth({this.watchdogs = const [], this.guard, this.faults = const []});
  final List<DeployedScript> watchdogs;
  final DeployedScript? guard;
  final List<ScriptFault> faults;

  List<DeployedScript> get all => [...watchdogs, if (guard != null) guard!];
  List<DeployedScript> get damaged => [for (final s in all) if (s.damaged) s];
}

/// Every watchdog script and guard.sh with its size, header and last line, every watchdog cron entry
/// with no script, and the last fault each watchdog recorded: one round trip, one line each.
final String kScriptHealthCommand = r'''C="$(cru l 2>/dev/null)"; for S in 1 2 3 4 5; do F=__DIR__/watchdog_wgc$S.sh; P=0; '''
        r'''echo "$C" | grep -qw "watchdog_wgc$S" && P=1; if [ -f "$F" ]; then '''
        r'''echo "wgc$S|$P|1|$(wc -c < "$F" | tr -d ' ')|$(sed -n 2p "$F")|$(tail -n 1 "$F")"; '''
        r'''elif [ "$P" = 1 ]; then echo "wgc$S|1|0|0||"; fi; done; G=__DIR__/guard.sh; [ -f "$G" ] && '''
        r'''echo "guard|0|1|$(wc -c < "$G" | tr -d ' ')|$(sed -n 2p "$G")|$(tail -n 1 "$G")"; '''
        r'''for S in 1 2 3 4 5; do L=/tmp/watchdog_lastfault_wgc$S; [ -f "$L" ] && '''
        r'''echo "fault|$S|$(sed -n 1p "$L")|$(sed -n 2p "$L")"; done; true'''
    .replaceAll('__DIR__', kRouterAppDir);

RouterScriptHealth parseScriptHealth(String out) {
  final watchdogs = <DeployedScript>[];
  DeployedScript? guard;
  final faults = <ScriptFault>[];
  for (final raw in out.split('\n')) {
    final f = raw.trimRight().split('|');
    if (f.length >= 4 && f[0] == 'fault') {
      final slot = int.tryParse(f[1]);
      final epoch = int.tryParse(f[2].trim());
      if (slot != null && epoch != null) {
        faults.add(ScriptFault(
            slot: slot, at: DateTime.fromMillisecondsSinceEpoch(epoch * 1000), message: f.sublist(3).join('|').trim()));
      }
      continue;
    }
    if (f.length < 6) continue;
    final m = RegExp(r'^wgc([1-5])$').firstMatch(f[0]);
    if (m == null && f[0] != 'guard') continue;
    final script = DeployedScript(
      fileName: m == null ? 'guard.sh' : 'watchdog_wgc${m.group(1)}.sh',
      slot: m == null ? null : int.parse(m.group(1)!),
      scheduled: f[1] == '1',
      exists: f[2] == '1',
      size: int.tryParse(f[3].trim()) ?? 0,
      version: parseScriptVersion(f[4]),
      lastLine: f.sublist(5).join('|'),
    );
    if (m == null) {
      guard = script;
    } else {
      watchdogs.add(script);
    }
  }
  return RouterScriptHealth(watchdogs: watchdogs, guard: guard, faults: faults);
}

// ─── The widget (ID-488) ─────────────────────────────────────────────────────────────────────────

/// For the home screen widget's read, which is also its key's `command="…"` restriction: each
/// watchdog script's header line and last line, one after the other. No double quotes, which that
/// restriction would have to escape.
const String kWatchdogHeadsAndTailsCommand =
    'for f in $kRouterAppDir' r'/watchdog_wgc?.sh; do sed -n 2p $f; tail -n 1 $f; done 2>/dev/null';

/// The slots whose watchdog is damaged or missing, from `cru l` and [kWatchdogHeadsAndTailsCommand].
Set<int> brokenWatchdogSlots({required String cronList, required String headsAndTails}) {
  final scheduled = {for (final m in RegExp(r'#watchdog_wgc([1-5])#').allMatches(cronList)) int.parse(m.group(1)!)};
  final lines = headsAndTails.split('\n');
  final scripts = <int, DeployedScript>{};
  for (var i = 0; i < lines.length; i++) {
    final m = RegExp(r'^# watchdog_wgc([1-5])\.sh - auto-generated').firstMatch(lines[i].trim());
    if (m == null) continue;
    final slot = int.parse(m.group(1)!);
    scripts[slot] = DeployedScript(
      fileName: 'watchdog_wgc$slot.sh',
      slot: slot,
      scheduled: scheduled.contains(slot),
      exists: true,
      version: parseScriptVersion(lines[i]),
      lastLine: i + 1 < lines.length ? lines[i + 1].trim() : '',
    );
  }
  return {
    for (final s in scripts.values)
      if (s.damaged) s.slot!,
    for (final slot in scheduled)
      if (!scripts.containsKey(slot)) slot,
  };
}

// ─── The check at the first connection (ID-486, ID-487) ─────────────────────────────────────────

/// What [checkRouterScripts] found and did.
class RouterScriptCheck {
  const RouterScriptCheck({this.updated = const [], this.unfixed = const []});

  /// File names replaced, `watchdog_wgc5.sh` or `guard.sh`.
  final List<String> updated;

  /// One sentence for each problem still on the router, for the main menu's banner.
  final List<String> unfixed;
}

typedef ScriptLog = void Function(String message, {bool isError, bool isSuccess, bool isWarning});

/// Reads what the app has put on the router and says what is wrong, in red in both logs. In a paid
/// version ([canUpdate]) it then replaces every watchdog script and guard.sh that is damaged or older
/// than this app, never one that is only newer (ID-487).
///
/// [seenFaults] holds the faults already shown this run of the app, so each is logged once. Only
/// faults from the last day are shown: the router's own log and the alert email carry older ones.
/// Never throws: a check that fails must not stop the action that opened the connection.
Future<RouterScriptCheck> checkRouterScripts(
  SSHClient client, {
  required bool canUpdate,
  ScriptLog? onLog,
  Set<String>? seenFaults,
  DateTime Function() clock = DateTime.now,
}) async {
  final w = RouterWatchdog(client, onLog: onLog);
  final RouterScriptHealth health;
  final RouterFirmware? firmware;
  try {
    firmware = classifyFirmwareTag((await w.read('nvram get 3rd-party')).trim());
    if (firmware == null) return const RouterScriptCheck();
    health = parseScriptHealth(await w.read(kScriptHealthCommand));
  } catch (e) {
    onLog?.call('Could not check the scripts on the router: $e', isWarning: true);
    return const RouterScriptCheck();
  }
  for (final s in health.damaged) {
    onLog?.call(s.problem!, isError: true);
    await w.logRouterQuietly(s.problem!);
  }
  final now = clock();
  for (final f in health.faults) {
    final key = '${f.slot}@${f.at.millisecondsSinceEpoch}';
    if (now.difference(f.at) > const Duration(days: 1) || !(seenFaults?.add(key) ?? true)) continue;
    final at = '${f.at.year}-${_two(f.at.month)}-${_two(f.at.day)} ${_two(f.at.hour)}:${_two(f.at.minute)}';
    onLog?.call("ERROR: wgc${f.slot}'s watchdog reported at $at: ${f.message}", isError: true);
  }

  final slots = <int>{
    for (final s in health.watchdogs)
      if (s.needsUpdate) s.slot!,
  };
  final guard = firmware == RouterFirmware.stock && (health.guard?.needsUpdate ?? false);
  final broken = [for (final s in health.damaged) s.problem!.replaceFirst('ERROR: ', '')];
  if (!canUpdate || (slots.isEmpty && !guard)) return RouterScriptCheck(unfixed: broken);
  try {
    final done = await w.redeployScripts(only: slots, refreshGuard: guard, automatic: true);
    return RouterScriptCheck(updated: [
      for (final s in done) 'watchdog_wgc$s.sh',
      if (guard) 'guard.sh',
    ]);
  } catch (e) {
    // redeployScripts has said what failed, in both logs.
    return RouterScriptCheck(unfixed: [
      ...broken,
      'The app could not bring the router\'s scripts up to date: ${e.toString().replaceFirst(RegExp(r'^Exception: '), '')}',
    ]);
  }
}

String _two(int v) => v.toString().padLeft(2, '0');
