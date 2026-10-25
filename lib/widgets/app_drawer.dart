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

// Navigating via the hamburger intentionally GROWS the route stack (spec 2.1 / 3.1) so the
// Android back button can retrace steps and return to a modal that was left open. Selecting the
// current destination is a no-op.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_button.dart';
import 'package:flutter/services.dart';

import '../app_colors.dart';
import '../screens/about_screen.dart';
import '../screens/log_screen.dart';
import '../screens/main_menu_screen.dart';
import '../screens/router_log_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/manage_router_screen.dart';
import '../screens/network_screen.dart';
import '../screens/standalone_config_screen.dart';
import '../screens/watchdog_management_screen.dart';
import '../session_controller.dart';
import 'device_assignment_screen.dart';

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
    case AppDestination.deviceAssignment:
      return const DeviceAssignmentScreen();
    case AppDestination.network:
      return const NetworkScreen();
    case AppDestination.routerLog:
      return const RouterLogScreen();
    case AppDestination.log:
      return const LogScreen();
    case AppDestination.settings:
      return const SettingsScreen();
    case AppDestination.about:
      return const AboutScreen();
  }
}

/// The icon for each destination (ID-031). The main menu and the drawer both take theirs from here, so the same
/// screen never carries two different icons. `menu` is HOME, which only the drawer shows.
IconData destinationIcon(AppDestination dest) => switch (dest) {
      AppDestination.menu => Icons.home_outlined,
      AppDestination.standalone => Icons.note_add_outlined,
      AppDestination.manageRouter => Icons.app_registration_outlined,
      AppDestination.watchdog => Icons.monitor_heart_outlined,
      AppDestination.deviceAssignment => Icons.hub_outlined,
      AppDestination.network => Icons.public,
      AppDestination.routerLog => Icons.router_outlined,
      AppDestination.log => Icons.list_alt_outlined,
      AppDestination.settings => Icons.settings_outlined,
      AppDestination.about => Icons.info_outline,
    };

/// EXIT's icon, on the main menu and in the drawer.
const IconData kExitIcon = Icons.power_settings_new;

/// True on iOS, where an app can't close itself: Apple's guidelines say an app doesn't quit, and Flutter
/// ignores `SystemNavigator.pop` there (ID-394). Read through [defaultTargetPlatform], so a test can run as iOS.
bool get _appCannotClose => defaultTargetPlatform == TargetPlatform.iOS;

/// EXIT's label: CLEAR on iOS, where it wipes the same things but leaves the app open (ID-394, Andrew's
/// decision 2026-10-16), and EXIT everywhere else.
String exitLabel() => _appCannotClose ? 'CLEAR' : 'EXIT';

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

/// CLEAR on iOS (ID-394): the same wipe as [closeApp], then every screen and dialog above the main menu is
/// closed, so nothing a screen still showed - a config, a log, a form - is left behind it.
Future<void> clearAndReturnHome(BuildContext context, SessionController controller) async {
  final navigator = Navigator.of(context);
  await controller.wipeAll(reason: 'cleared');
  navigator.popUntil((route) => route.isFirst);
}

/// Confirms before wiping + exiting, or on iOS wiping and returning to the main menu. Wired to every exit
/// path (back key, menu + drawer EXIT).
Future<void> confirmAndExit(BuildContext context, SessionController controller) async {
  final clearOnly = _appCannotClose;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSurface,
      title: Text(clearOnly ? 'Clear cfg-pia-wg?' : 'Exit cfg-pia-wg?', style: const TextStyle(color: kText, fontSize: 15)),
      content: Text(
          clearOnly
              ? 'All credentials and configuration will be wiped from memory, and the app returns to the main menu.'
              : 'All credentials and configuration will be wiped from memory.',
          style: const TextStyle(color: kMuted, fontSize: 13)),
      actions: [
        AppButton(label: 'CANCEL', role: ButtonRole.dismiss, onPressed: () => Navigator.pop(ctx, false)),
        AppButton(label: exitLabel(), role: ButtonRole.destructive, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  if (ok != true) return;
  if (!clearOnly) return closeApp(controller);
  if (context.mounted) await clearAndReturnHome(context, controller);
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

  /// Every destination, in order. The main menu builds its buttons from this same list, so the two
  /// always offer the same screens with the same names in the same order.
  static const destinations = [
    AppDestination.standalone,
    AppDestination.manageRouter,
    AppDestination.watchdog,
    AppDestination.deviceAssignment,
    AppDestination.network,
    AppDestination.routerLog,
    AppDestination.log,
    AppDestination.settings,
    AppDestination.about,
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
              leading: Icon(destinationIcon(AppDestination.menu), size: 20),
              title: const Text('HOME', style: TextStyle(fontSize: 13)),
              textColor: kMuted,
              iconColor: kMuted,
              selectedColor: kHighlight,
              // The same fill as every other entry. HOME had none, so on HOME nothing looked current (ID-156).
              selectedTileColor: kBorder,
              selected: controller.currentDestination == AppDestination.menu,
              onTap: () {
                onCloseDrawer();
                final navContext = navigatorKey.currentContext;
                if (navContext != null) navigateToDestination(navContext, controller, AppDestination.menu);
              },
            ),
            const Divider(color: kBorder, height: 1),
            for (final d in destinations)
              ListTile(
                key: Key('drawer_${d.routeName}'),
                // Icon and label take the destination's own colour, from the same map the main menu
                // reads (ID-112) - no outline here, the drawer is a list. The current screen is
                // marked by the tile's fill instead, since its colour is already spoken for.
                leading: Icon(destinationIcon(d), size: 20),
                title: Text(d.title, style: const TextStyle(fontSize: 13)),
                textColor: destinationColour(d),
                iconColor: destinationColour(d),
                selectedColor: destinationColour(d),
                // kBorder, not kField: kField is four shades off the drawer and did not read as a fill (ID-156).
                selectedTileColor: kBorder,
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
              leading: const Icon(kExitIcon, color: kError, size: 20),
              title: Text(exitLabel(), style: const TextStyle(color: kError, fontSize: 13)),
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
