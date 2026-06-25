// screens/main_menu_screen.dart - The opening menu screen (spec 2.1).
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

import '../app_colors.dart';
import '../session_controller.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_scaffold.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = SessionScope.of(context);
    final spacer = 2 * (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await confirmAndExit(context, controller); // confirm before the back key exits (round-2)
      },
      child: AppScaffold(
        showClose: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MenuButton(
              keyValue: 'menu_standalone',
              label: AppDestination.standalone.title,
              onTap: () => navigateToDestination(context, controller, AppDestination.standalone),
            ),
            const SizedBox(height: 12),
            _MenuButton(
              keyValue: 'menu_manage_router',
              label: '${AppDestination.manageRouter.title}*',
              onTap: () => navigateToDestination(context, controller, AppDestination.manageRouter),
            ),
            const SizedBox(height: 12),
            _MenuButton(
              keyValue: 'menu_watchdog',
              label: '${AppDestination.watchdog.title}*',
              onTap: () => navigateToDestination(context, controller, AppDestination.watchdog),
            ),
            const SizedBox(height: 12),
            _MenuButton(
              keyValue: 'menu_log',
              label: AppDestination.log.title,
              onTap: () => navigateToDestination(context, controller, AppDestination.log),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('menu_close_app'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: kError,
                    side: const BorderSide(color: kError),
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: () => confirmAndExit(context, controller),
                child: const Text('Exit app'),
              ),
            ),
            SizedBox(height: spacer),
            const Text('* requires SSH connectivity to an Asus router.', style: TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                style: const TextStyle(color: kHighlight, fontSize: 12),
                children: const [
                  TextSpan(text: 'Select from the above and/or use the top left '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.menu, size: 16, color: kHighlight),
                  ),
                  TextSpan(text: ' menu.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String keyValue;
  final String label;
  final VoidCallback onTap;
  const _MenuButton({required this.keyValue, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        key: Key(keyValue),
        style: ElevatedButton.styleFrom(
          backgroundColor: kHighlight,
          foregroundColor: kOnPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        onPressed: onTap,
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
