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
// Holds the credentials, generated config, application log, and the 60-second clipboard
// auto-clear timer that must persist while the user moves between the workflow screens. NOTHING
// here is ever written to device storage — it lives only in memory and is wiped on "Exit app"
// and when the app is backed out via the main menu.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// Default DNS servers (Quad9), matching the value the standalone form pre-fills.
const String kDefaultDns = '9.9.9.9, 149.112.112.112';

/// The navigable destinations. [routeName] doubles as the [RouteSettings] name used by the
/// destination observer to track which screen is on top (for the drawer's no-op-on-current).
enum AppDestination {
  menu('main_menu', 'Main menu'),
  standalone('standalone', 'Generate PIA WireGuard configuration'),
  manageRouter('manage_router', 'Manage router PIA WireGuard configuration'),
  watchdog('watchdog', 'Watchdog WireGuard management'),
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
/// A single periodic tick drives the 60-second clipboard auto-clear countdown.
class SessionController extends ChangeNotifier {
  SessionController({
    Duration clipboardTimeout = const Duration(seconds: 60),
    Duration tickInterval = const Duration(seconds: 1),
    Future<void> Function(String text)? clipboardWriter,
  })  : _clipboardTimeout = clipboardTimeout,
        _tickInterval = tickInterval,
        _clipboardWriter = clipboardWriter ?? _defaultClipboardWriter;

  static Future<void> _defaultClipboardWriter(String text) => Clipboard.setData(ClipboardData(text: text));

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

  // ── Clipboard timer ──────────────────────────────────────────────────────────
  final Duration _clipboardTimeout, _tickInterval;
  final Future<void> Function(String text) _clipboardWriter;

  Timer? _tickTimer;
  DateTime? _clipboardDeadline;
  int clipboardSeconds = 0;

  // ── Modal depth (tracked for the error presenter) ─────────────────────────────
  int modalDepth = 0;
  bool get modalsOpen => modalDepth > 0;

  // The screen currently on top, maintained by the DestinationObserver. Used by the drawer to
  // no-op when the current destination is re-selected. Plain field (no notify needed).
  AppDestination currentDestination = AppDestination.menu;

  // True once a router SSH connect has succeeded this session (drives auto-reconnect on entry).
  bool routerConnected = false;

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
  void onLog(String msg, {bool isError = false, bool isSuccess = false}) => logEntry(msg, isError: isError, isSuccess: isSuccess);

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

  // ── Clipboard countdown timer ──────────────────────────────────────────────────
  void _ensureTicking() {
    _tickTimer ??= Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _tick() {
    if (_clipboardDeadline == null) return;
    final remaining = _clipboardDeadline!.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      clearClipboard();
      return;
    }
    if (remaining != clipboardSeconds) {
      clipboardSeconds = remaining;
      notifyListeners();
    }
  }

  // Re-evaluate the clipboard deadline after the app returns from the background.
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
  // Clears all volatile credentials + config + clipboard. Used by "Exit app" and
  // back-exit from the main menu.
  Future<void> wipeAll({String? reason}) async {
    piaUsername = '';
    piaPassword = '';
    dns = kDefaultDns;
    routerIp = '';
    sshUsername = '';
    sshPassword = '';
    generatedConfig = null;
    generatedRegionId = '';
    routerConnected = false;
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
