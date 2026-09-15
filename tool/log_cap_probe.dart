// tool/log_cap_probe.dart - measures the two limits behind the app log cap (ID-004).
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
// The app log is never written to storage, so it is capped at the most a user can both see and copy: the
// lower of how long a log the LOG screen can draw smoothly and how long a log survives a copy to the
// clipboard. This measures both on a device or emulator; kLogCapChars records the results it was set from.
//
//   flutter build apk --profile --target-platform android-x64 -t tool/log_cap_probe.dart
//   adb install -r build/app/outputs/flutter-apk/app-profile.apk
//   adb shell am start -n com.exponentiallydigital.pia_wireguard_cfga/.MainActivity
//   adb logcat -s flutter | grep LOGCAP
//
// (android-arm64 for a phone; uninstall the store build first, since the signatures differ.) For each log
// size it opens the real LOG screen, then adds lines one at a time with it open, taking each frame's build
// and raster time from the engine. Then it copies ever larger text through the same clipboard path COPY uses
// and reads it back. A frame over 16 ms is a dropped frame at 60 Hz.

import 'dart:async';
import 'dart:math';

import 'package:cfg_pia_wg/screens/log_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

const List<int> _sizes = [500, 1000, 2000, 4000, 8000, 16000];
const List<int> _clipboardChars = [250000, 500000, 1000000, 2000000, 4000000];

// Lines shaped like the app's own: short status lines, longer explanations, the odd long error.
const List<String> _samples = [
  'Connecting to router at 192.168.50.1:22 via SSH...',
  'Router firmware detected: stock.',
  'Successfully retrieved router config.',
  'wgc2: tunnel is up; latest handshake 42 seconds ago.',
  'Deploying watchdog to wgc3 (pia-aus_melbourne): uploading the script in 4 stages.',
  'Watchdog deployed on wgc3. It checks the tunnel every 5 minutes and emails when it cannot recover it.',
  'Clipboard auto cleared.',
  'Device assignment applied: 3 devices moved, 1 left on the default connection.',
  'SSH connection dropped while reading the router log; reconnecting before the next command.',
  'wgc4 did not come up within 30 seconds. Check the region is reachable, then ENABLE it again from MANAGE.',
  'Could not reach smtp.example.com:587 from the router: name lookup failed. The alert was not sent.',
  'Config generated successfully for pia-aus_perth.',
];

final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
final List<FrameTiming> _frames = [];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
  runApp(MaterialApp(
    navigatorKey: _navigator,
    home: const Scaffold(body: Center(child: Text('log cap probe - results in logcat'))),
  ));
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
}

// Frame timings arrive in batches, so give each phase time to report.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 1200));

int _worstMs(List<FrameTiming> frames) =>
    frames.isEmpty ? -1 : frames.map((t) => t.totalSpan.inMilliseconds).reduce(max);

int _medianMs(List<FrameTiming> frames) {
  if (frames.isEmpty) return -1;
  final ms = frames.map((t) => t.totalSpan.inMilliseconds).toList()..sort();
  return ms[ms.length ~/ 2];
}

Future<void> _run() async {
  for (final lines in _sizes) {
    // No cap here: the point is to find where the screen stops keeping up.
    final c = SessionController(tickInterval: const Duration(hours: 1), logCapChars: 1 << 30);
    for (var i = 0; i < lines; i++) {
      c.log.add(LogEntry(
        '[12:${(i ~/ 60 % 60).toString().padLeft(2, '0')}:${(i % 60).toString().padLeft(2, '0')}] '
        '${_samples[i % _samples.length]}',
        isError: i % 17 == 0,
        isWarning: i % 11 == 0,
        isSuccess: i % 7 == 0,
      ));
    }
    final chars = c.log.fold<int>(0, (n, e) => n + e.message.length + 1);

    _frames.clear();
    unawaited(_navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => SessionScope(controller: c, child: const Scaffold(body: LogScreen())),
    )));
    await _settle();
    final openWorst = _worstMs(_frames);

    _frames.clear();
    for (var i = 0; i < 20; i++) {
      c.logEntry('appended line $i while the LOG screen is open');
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await _settle();

    debugPrint('LOGCAP lines=${c.log.length} chars=$chars open_worst_ms=$openWorst '
        'append_median_ms=${_medianMs(_frames)} append_worst_ms=${_worstMs(_frames)}');
    _navigator.currentState!.pop();
    await _settle();
    c.dispose();
    if (_worstMs(_frames) > 1000 || openWorst > 3000) break;
  }

  final c = SessionController(tickInterval: const Duration(hours: 1));
  for (final target in _clipboardChars) {
    final line = _samples.join(' ');
    final text = List.filled(target ~/ (line.length + 1) + 1, line).join('\n').substring(0, target);
    String copy;
    try {
      await c.copyToClipboard(text, armAutoClear: false);
      final back = await Clipboard.getData(Clipboard.kTextPlain);
      copy = back?.text == text ? 'ok' : 'MISMATCH (read back ${back?.text?.length ?? 0})';
    } catch (e) {
      copy = 'FAILED (${e.toString().split('\n').first})';
    }
    debugPrint('LOGCAP clipboard chars=$target copy=$copy');
    if (copy != 'ok') break;
  }
  c.dispose();
  debugPrint('LOGCAP DONE');
}
