// session_controller.dart - App-wide volatile session state shared across screens.
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
// Holds the credentials, generated config, application log, and the inactivity/clipboard
// timers that must persist while the user moves between the five workflow screens. NOTHING
// here is ever written to device storage — it lives only in memory and is wiped on a 10-minute
// idle timeout, on "Close app", and when the app is backed out of from the main menu.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// Default DNS servers (Quad9), matching the value the standalone form pre-fills.
const String kDefaultDns = '9.9.9.9, 149.112.112.112';

/// The navigable destinations. [routeName] doubles as the [RouteSettings] name used by the
/// destination observer to track which screen is on top (for the drawer's no-op-on-current).
enum AppDestination {
  menu('main_menu', 'Main menu'),
  standalone('standalone', 'Generate standalone PIA WireGuard configuration'),
  manageRouter('manage_router', 'Manage router PIA WireGuard configuration'),
  watchdog('watchdog', 'VPN watchdog management'),
  log('log', 'View app log');

  const AppDestination(this.routeName, this.title);
  final String routeName, title;
}

/// A single timestamped line in the in-memory application log.
class LogEntry {
  final String message;
  final bool isError, isSuccess;
  LogEntry(this.message, {this.isError = false, this.isSuccess = false});
}

/// The shared, volatile session state. Exposed to the widget tree via [SessionScope].
///
/// A single periodic tick drives both the inactivity countdown and the clipboard
/// auto-clear countdown so there is only ever one [Timer] running.
class SessionController extends ChangeNotifier {
  SessionController({
    Duration inactivityTimeout = const Duration(minutes: 10),
    Duration clipboardTimeout = const Duration(seconds: 60),
    Duration tickInterval = const Duration(seconds: 1),
    Future<void> Function(String text)? clipboardWriter,
  })  : _inactivityTimeout = inactivityTimeout,
        _clipboardTimeout = clipboardTimeout,
        _tickInterval = tickInterval,
        _clipboardWriter = clipboardWriter ?? _defaultClipboardWriter;

  static Future<void> _defaultClipboardWriter(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  // ── Credentials & config (volatile) ─────────────────────────────────────────
  String piaUsername = '';
  String piaPassword = '';
  String dns = kDefaultDns;
  String routerIp = '';
  String sshUsername = '';
  String sshPassword = '';
  String? generatedConfig;
  String generatedRegionId = '';

  // ── Application log ──────────────────────────────────────────────────────────
  final List<LogEntry> log = [];

  // ── Timers ───────────────────────────────────────────────────────────────────
  final Duration _inactivityTimeout, _clipboardTimeout, _tickInterval;
  final Future<void> Function(String text) _clipboardWriter;

  Timer? _tickTimer;
  DateTime? _inactivityDeadline;
  int inactivitySeconds = 0;
  DateTime? _clipboardDeadline;
  int clipboardSeconds = 0;

  // ── Modal depth (countdown is hidden while > 0) ───────────────────────────────
  int modalDepth = 0;
  bool get modalsOpen => modalDepth > 0;

  // The screen currently on top, maintained by the DestinationObserver. Used by the drawer to
  // no-op when the current destination is re-selected. Plain field (no notify needed).
  AppDestination currentDestination = AppDestination.menu;

  /// Invoked when the inactivity timeout elapses, AFTER the wipe runs. The app shell
  /// wires this to close any open modals and redirect to the main menu.
  VoidCallback? onInactivityExpire;

  // ── Logging ────────────────────────────────────────────────────────────────────
  void logEntry(String msg, {bool isError = false, bool isSuccess = false}) {
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    log.add(LogEntry('[$ts] $msg', isError: isError, isSuccess: isSuccess));
    notifyListeners();
  }

  // Adapter matching the `void Function(String, {bool isError, bool isSuccess})` callback
  // shape used throughout router_push / router_watchdog / watchdog_dialog.
  void onLog(String msg, {bool isError = false, bool isSuccess = false}) =>
      logEntry(msg, isError: isError, isSuccess: isSuccess);

  // Stores the generated standalone config (and its region) so it survives screen navigation
  // and is wiped with everything else on idle / close.
  void setGeneratedConfig(String? config, String regionId) {
    generatedConfig = config;
    generatedRegionId = regionId;
    notifyListeners();
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  // ── Inactivity timer ─────────────────────────────────────────────────────────
  // Called on app start and on every user interaction. Pushes the deadline forward
  // cheaply without recreating the timer (so a stream of pointer-move events is light).
  void resetActivity() {
    _inactivityDeadline = DateTime.now().add(_inactivityTimeout);
    _ensureTicking();
  }

  void _ensureTicking() {
    _tickTimer ??= Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _tick() {
    var changed = false;
    final now = DateTime.now();

    if (_inactivityDeadline != null) {
      final remaining = _inactivityDeadline!.difference(now).inSeconds;
      if (remaining <= 0) {
        _expireInactivity();
        return;
      }
      if (remaining != inactivitySeconds) {
        inactivitySeconds = remaining;
        changed = true;
      }
    }

    if (_clipboardDeadline != null) {
      final remaining = _clipboardDeadline!.difference(now).inSeconds;
      if (remaining <= 0) {
        clearClipboard();
        return;
      }
      if (remaining != clipboardSeconds) {
        clipboardSeconds = remaining;
        changed = true;
      }
    }

    if (changed) notifyListeners();
  }

  void _expireInactivity() {
    _inactivityDeadline = null;
    inactivitySeconds = 0;
    wipeAll(reason: '10 minutes of inactivity');
    onInactivityExpire?.call();
  }

  // Re-evaluate both deadlines after the app returns from the background.
  void resyncOnResume() {
    _tick();
  }

  // ── Clipboard ──────────────────────────────────────────────────────────────────
  Future<void> copyToClipboard(String text) async {
    await _clipboardWriter(text);
    _clipboardDeadline = DateTime.now().add(_clipboardTimeout);
    clipboardSeconds = _clipboardTimeout.inSeconds;
    _ensureTicking();
    notifyListeners();
  }

  // Clears the clipboard now and stops its countdown. Always logs, matching the old behaviour.
  Future<void> clearClipboard() async {
    final wasArmed = _clipboardDeadline != null;
    _clipboardDeadline = null;
    clipboardSeconds = 0;
    await _clipboardWriter('');
    if (wasArmed) logEntry('Clipboard auto cleared.');
    notifyListeners();
  }

  // ── Wipe ─────────────────────────────────────────────────────────────────────────
  // Clears all volatile credentials + config + clipboard. Used by the idle timeout,
  // "Close app", and back-exit from the main menu.
  Future<void> wipeAll({String? reason}) async {
    piaUsername = '';
    piaPassword = '';
    dns = kDefaultDns;
    routerIp = '';
    sshUsername = '';
    sshPassword = '';
    generatedConfig = null;
    generatedRegionId = '';
    await clearClipboard();
    logEntry(reason == null
        ? 'All credentials and WireGuard configuration wiped from memory.'
        : 'All credentials and WireGuard configuration wiped from memory ($reason).');
    notifyListeners();
  }

  // ── Modal tracking ─────────────────────────────────────────────────────────────
  void enterModal() {
    modalDepth++;
    notifyListeners();
  }

  void exitModal() {
    if (modalDepth > 0) modalDepth--;
    notifyListeners();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _tickTimer = null;
    super.dispose();
  }
}

/// Inherited access point for the [SessionController]. `updateShouldNotify` compares the
/// controller identity only, so dependents are NOT rebuilt on every 1 Hz tick — repainting
/// subtrees (countdown, log, generated-config) should wrap a [ListenableBuilder] instead.
class SessionScope extends InheritedWidget {
  final SessionController controller;
  const SessionScope({super.key, required this.controller, required super.child});

  static SessionController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'No SessionScope found in the widget tree.');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(SessionScope oldWidget) => oldWidget.controller != controller;
}
