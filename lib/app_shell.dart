// app_shell.dart - Application root: owns the SessionController, the global chrome, navigation,
// and lifecycle resync.
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

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'screens/main_menu_screen.dart';
import 'session_controller.dart';
import 'widgets/app_scaffold.dart';

/// Keeps [SessionController.currentDestination] in sync with the route on top so the drawer can
/// no-op when the current screen is re-selected.
class DestinationObserver extends NavigatorObserver {
  final SessionController controller;
  DestinationObserver(this.controller);

  void _update(Route<dynamic>? route) {
    // Only page routes change the current destination; dialogs / bottom sheets (the slot modal,
    // EDIT, error, region picker) must NOT, so the active drawer item stays highlighted while a
    // modal is open.
    if (route is! PageRoute) return;
    final name = route.settings.name;
    controller.currentDestination = AppDestination.values.firstWhere(
      (d) => d.routeName == name,
      orElse: () => AppDestination.menu,
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _update(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _update(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _update(newRoute);
}

ThemeData buildAppTheme() => ThemeData(
      colorScheme: const ColorScheme.dark(
        primary: kHighlight,
        secondary: kSecondary,
        surface: kSurface,
        error: kError,
        onPrimary: kOnPrimary,
        onSurface: kText,
      ),
      useMaterial3: true,
      fontFamily: 'monospace',
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kField,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBorder)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBorder)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kHighlight, width: 1.5)),
        labelStyle: const TextStyle(color: kMuted),
        hintStyle: const TextStyle(color: kHint),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kHighlight,
          foregroundColor: kOnPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),
    );

class PiaWgApp extends StatefulWidget {
  // Injectable for tests so timers can run on short intervals.
  final SessionController? controller;
  const PiaWgApp({super.key, this.controller});

  @override
  State<PiaWgApp> createState() => _PiaWgAppState();
}

class _PiaWgAppState extends State<PiaWgApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final SessionController _controller = widget.controller ?? SessionController();
  late final DestinationObserver _observer = DestinationObserver(_controller);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Only dispose a controller we created ourselves.
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.resyncOnResume();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      controller: _controller,
      child: MaterialApp(
        title: 'Configure PIA WireGuard',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        navigatorKey: _navigatorKey,
        navigatorObservers: [_observer],
        home: const MainMenuScreen(),
        builder: (context, child) => AppChrome(navigatorKey: _navigatorKey, child: child!),
      ),
    );
  }
}
