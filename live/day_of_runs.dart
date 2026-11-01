// live/day_of_runs.dart - the pure half of live/day_of_runs_live_test.dart (TESTING LOG-9, ID-494):
// what a watchdog's own log says about a day of its runs. Nothing here touches a router, so
// test/unit/day_of_runs_test.dart covers all of it.
import 'package:cfg_pia_wg/router_script_integrity.dart' show kFirstBuildWithEndLine, scriptBuild;

/// The errors the tests make on purpose, which are not what LOG-9 looks for.
bool deliberate(String line) =>
    line.contains('[LOG-8 test error]') || line.contains('[check-claims test error') || line.contains('cfgpia_test_fail_');

/// One watchdog log line's time, `2026-11-02 16:00:00 ...`, or null.
DateTime? lineTime(String line) => line.length < 19 ? null : DateTime.tryParse(line.substring(0, 19).replaceFirst(' ', 'T'));

/// What [log] (yesterday's then today's) says about runs of build [minBuild] or later: when the first
/// and last were, how many there were, and the script-error lines since the first that no test left.
/// A run reports the error of the run before it ahead of its own "Watchdog started" line, so an error
/// counts by where it falls after the first such run, not by which run's lines it sits among.
({DateTime? first, DateTime? last, int runs, List<String> errors}) dayOfRuns(String log, {int minBuild = kFirstBuildWithEndLine}) {
  DateTime? first, last;
  var runs = 0;
  final errors = <String>[];
  for (final line in log.split('\n')) {
    final m = RegExp(r'Watchdog started for wgc\d \[script (v[^\]]+)\]').firstMatch(line);
    if (m != null) {
      if ((scriptBuild(m.group(1)) ?? 0) >= minBuild) {
        final t = lineTime(line);
        if (t != null) {
          first ??= t;
          last = t;
        }
        runs++;
      }
      continue;
    }
    if (first != null && line.contains('reported a script error') && !deliberate(line)) errors.add(line);
  }
  return (first: first, last: last, runs: runs, errors: errors);
}
