// widgets/app_drawer.dart - Hamburger navigation drawer + destination routing.
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
// Navigating via the hamburger intentionally GROWS the route stack (spec 2.1 / 3.1) so the
// Android back button can retrace steps and return to a modal that was left open. Selecting the
// current destination is a no-op.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_colors.dart';
import '../screens/log_screen.dart';
import '../screens/main_menu_screen.dart';
import '../screens/manage_router_screen.dart';
import '../screens/standalone_config_screen.dart';
import '../screens/watchdog_management_screen.dart';
import '../session_controller.dart';

/// Builds the screen widget for a destination (default constructors; tests pump screens directly).
Widget screenForDestination(AppDestination dest) {
  switch (dest) {
    case AppDestination.menu:
      return const MainMenuScreen();
    case AppDestination.standalone:
      return const StandaloneConfigScreen();
    case AppDestination.manageRouter:
      return const ManageRouterScreen();
    case AppDestination.watchdog:
      return const WatchdogManagementScreen();
    case AppDestination.log:
      return const LogScreen();
  }
}

/// Pushes [dest] onto the stack (no-op if already the current destination).
void navigateToDestination(BuildContext context, SessionController controller, AppDestination dest) {
  if (controller.currentDestination == dest) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => screenForDestination(dest),
    settings: RouteSettings(name: dest.routeName),
  ));
}

/// Wipes all volatile state and exits the application (spec 3.1 "Close app").
Future<void> closeApp(SessionController controller) async {
  await controller.wipeAll(reason: 'app closed');
  await SystemNavigator.pop();
}

class AppDrawer extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final SessionController controller;
  final VoidCallback onCloseDrawer;
  const AppDrawer({
    super.key,
    required this.navigatorKey,
    required this.controller,
    required this.onCloseDrawer,
  });

  static const _destinations = [
    AppDestination.standalone,
    AppDestination.manageRouter,
    AppDestination.watchdog,
    AppDestination.log,
  ];

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: kSurface,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Text('HOME',
                  style: TextStyle(color: kHighlight, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            ),
            const Divider(color: kBorder, height: 1),
            for (final d in _destinations)
              ListTile(
                key: Key('drawer_${d.routeName}'),
                title: Text(d.title, style: const TextStyle(color: kText, fontSize: 13)),
                selected: controller.currentDestination == d,
                selectedColor: kHighlight,
                onTap: () {
                  onCloseDrawer();
                  final navContext = navigatorKey.currentContext;
                  if (navContext != null) navigateToDestination(navContext, controller, d);
                },
              ),
            const Divider(color: kBorder, height: 1),
            ListTile(
              key: const Key('drawer_close_app'),
              leading: const Icon(Icons.power_settings_new, color: kError, size: 20),
              title: const Text('Exit app', style: TextStyle(color: kError, fontSize: 13)),
              onTap: () {
                onCloseDrawer();
                closeApp(controller);
              },
            ),
          ],
        ),
      ),
    );
  }
}
