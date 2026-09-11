// router_service_queue.dart - the router's own service queue, and how to survive it.
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
// ASUS runs every `service <name>` call through `notify_rc`, which records what it is doing in the
// `rc_service` NVRAM key and clears it when the action finishes. A later call finding that key set
// waits for it - `rc_service: waitting "<name>" via ...` - and after 15 seconds gives up and
// DISCARDS itself: `rc_service: skip the event: <name>`.
//
// A brief wait is ordinary. What is not ordinary is a service that never finishes, because the key
// is then never cleared and EVERY later event is discarded for as long as the router is up.
//
// Measured on hardware 2026-09-10. `service restart_vpnc` hung at 17:40:25 and the router spent the
// next ninety minutes discarding everything sent to it: four watchdog reconfigures wrote a perfect
// tunnel config that nothing acted on, and the app reported "router command failed (exit 1)" with
// no hint as to why. It discarded a `reboot` request too - the web interface said it was rebooting
// and it was not - so a POWER CYCLE was the only way out. Afterwards the key read empty at boot and
// cleared itself normally, so this is a wedge rather than how the firmware behaves.
//
// The key carries the pid alongside it in `rc_service_pid`, and that is what makes the state
// recoverable: a key naming a process that no longer exists is a ghost, and clearing it by hand
// restores normal service. See .claude/testing/2026-09-10_rc-service-stuck-runsheet.md.

/// Reads the marker, its pid, and whether that pid still exists, in one round trip.
///
/// `kill -0` tests for a process without signalling it. An empty pid makes it fail, which reads as
/// dead - correct, since a marker with no pid cannot be waited on by anything.
const String kRcServiceCommand = r'''printf '%s@@%s@@%s' "$(nvram get rc_service)" '''
    r'''"$(nvram get rc_service_pid)" '''
    r'''"$(kill -0 "$(nvram get rc_service_pid)" 2>/dev/null && echo alive || echo dead)"''';

/// Clears the marker. Only ever sent for a marker whose pid is gone.
const String kClearRcServiceCommand = 'nvram set rc_service=""';

/// What the router says it is doing.
class RcServiceState {
  const RcServiceState({required this.service, required this.pid, required this.pidAlive});

  /// The service being run, or empty when the router is idle.
  final String service;

  /// The pid that was running it, or null when the router did not report one.
  final int? pid;

  /// Whether that pid still exists.
  final bool pidAlive;

  bool get idle => service.isEmpty;

  /// A marker naming a service whose process has gone. Nothing will ever clear this on its own,
  /// and every service call made from now on is discarded after a 15-second wait.
  bool get stale => service.isNotEmpty && !pidAlive;

  /// Set, and its process still alive. Ordinary while an action runs; if it persists for minutes
  /// the action has hung, and only a power cycle recovers it.
  bool get busy => service.isNotEmpty && pidAlive;

  @override
  String toString() => idle ? 'idle' : '$service (pid ${pid ?? '?'}, ${pidAlive ? 'alive' : 'gone'})';
}

/// Parses [kRcServiceCommand]'s output: `service@@pid@@alive|dead`.
///
/// Anything unrecognisable reads as idle. That is the safe default: it means the caller carries on
/// and lets the router sort itself out, rather than refusing to work because a probe did not parse.
RcServiceState parseRcService(String raw) {
  final parts = raw.trim().split('@@');
  if (parts.length < 3) return const RcServiceState(service: '', pid: null, pidAlive: false);
  return RcServiceState(
    service: parts[0].trim(),
    pid: int.tryParse(parts[1].trim()),
    pidAlive: parts[2].trim() == 'alive',
  );
}

/// Thrown when the router's service queue is wedged and the app cannot fix it.
///
/// Distinct from an ordinary command failure because the remedy is completely different: nothing
/// the app or the user can send will be acted on, so the message has to say that plainly rather
/// than leaving them to retry into a queue that discards.
class RouterServiceWedgedException implements Exception {
  const RouterServiceWedgedException(this.state);
  final RcServiceState state;

  @override
  String toString() => 'The router has stopped accepting service commands. It is still waiting on '
      '"${state.service}", which has not finished, so everything sent to it is being discarded '
      'after a 15 second wait - including a reboot request. Power cycle the router to recover it. '
      'Nothing on the router has been changed by this app in the meantime.';
}

/// Guards a router service call against the queue described at the top of this file.
class RouterServiceQueue {
  RouterServiceQueue({
    required this.read,
    required this.run,
    this.onLog,
    this.logRouter,
    this.pollInterval = const Duration(seconds: 2),
    this.maxPolls = 20,
  });

  /// A tolerant read - a probe that fails is not a reason to fail the action it guards.
  final Future<String> Function(String cmd) read;

  /// A strict write, used only to clear a ghost marker.
  final Future<String> Function(String cmd) run;

  final void Function(String message, {bool isError, bool isSuccess, bool isWarning})? onLog;

  /// Writes one line to the ROUTER's own syslog. The app log gets a sentence for the user; this
  /// gets the detail, because whoever reads a syslog later is asking a different question.
  final Future<void> Function(String message)? logRouter;
  final Duration pollInterval;
  final int maxPolls;

  Future<RcServiceState> state() async => parseRcService(await read(kRcServiceCommand));

  /// Clears a ghost marker so the next service call is honoured. Returns what it found.
  ///
  /// Call this BEFORE issuing a service call. A ghost costs the caller a 15-second wait and then
  /// silently discards the work, which is indistinguishable from the command having run.
  Future<RcServiceState> clearIfStale() async {
    final s = await state();
    if (!s.stale) return s;
    onLog?.call(
        'The router was stuck on an earlier command and would have ignored this one. Cleared it and '
        'carried on - nothing for you to do (full details in router log).',
        isWarning: true);
    await logRouter?.call('INFO: cleared stale rc_service marker "${s.service}" (pid ${s.pid ?? '?'})');
    await run(kClearRcServiceCommand);
    return const RcServiceState(service: '', pid: null, pidAlive: false);
  }

  /// Waits for the router to finish whatever it is doing.
  ///
  /// Returns normally once the marker is empty. A ghost appearing while we wait is cleared, which
  /// is the same recovery as [clearIfStale] and the state a hung service leaves behind. Throws
  /// [RouterServiceWedgedException] only for a marker whose process is STILL ALIVE after the whole
  /// timeout - that one the app cannot fix, and saying so beats another opaque failure.
  Future<void> awaitIdle() async {
    for (var i = 0; i < maxPolls; i++) {
      final s = await state();
      if (s.idle) return;
      if (s.stale) {
        await clearIfStale();
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
    final s = await state();
    if (s.idle) return;
    if (s.stale) {
      await clearIfStale();
      return;
    }
    throw RouterServiceWedgedException(s);
  }
}
