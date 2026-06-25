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

/// Confirms before wiping + exiting. Wired to every exit path (back key, menu + drawer "Exit app").
Future<void> confirmAndExit(BuildContext context, SessionController controller) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSurface,
      title: const Text('Exit application?', style: TextStyle(color: kText, fontSize: 15)),
      content: const Text('All credentials and configuration will be wiped from memory.',
          style: TextStyle(color: kMuted, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL', style: TextStyle(color: kMuted))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('EXIT', style: TextStyle(color: kError, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  if (ok == true) await closeApp(controller);
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
            const SizedBox(height: 12),
            // HOME: grey normally, house-green when the main menu is the current screen.
            ListTile(
              key: const Key('drawer_menu'),
              title: const Text('HOME', style: TextStyle(fontSize: 13)),
              textColor: kMuted,
              selectedColor: kHighlight,
              selected: controller.currentDestination == AppDestination.menu,
              onTap: () {
                onCloseDrawer();
                final navContext = navigatorKey.currentContext;
                if (navContext != null) navigateToDestination(navContext, controller, AppDestination.menu);
              },
            ),
            const Divider(color: kBorder, height: 1),
            for (final d in _destinations)
              ListTile(
                key: Key('drawer_${d.routeName}'),
                // No explicit text colour here so selectedColor (active = green) takes effect.
                title: Text(d.title, style: const TextStyle(fontSize: 13)),
                textColor: kText,
                selectedColor: kHighlight,
                selected: controller.currentDestination == d,
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
                final navContext = navigatorKey.currentContext;
                if (navContext != null) confirmAndExit(navContext, controller);
              },
            ),
          ],
        ),
      ),
    );
  }
}
