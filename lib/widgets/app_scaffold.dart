// widgets/app_scaffold.dart - Global app chrome (static header + hamburger + countdown) and the
// per-screen body wrapper used by every workflow screen.
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
// The chrome is rendered ABOVE the navigator (via MaterialApp.builder) so the header is static and
// the hamburger + countdown stay visible and tappable even while a dialog (slot modal, EDIT, error)
// is shown below it (spec 3.1). The countdown is hidden whenever a modal is open.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_colors.dart';
import '../session_controller.dart';
import 'app_drawer.dart';

/// Wraps the whole navigator with the static header bar, the hamburger drawer, and a global
/// activity listener that resets the inactivity countdown on any interaction.
class AppChrome extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child; // the app's Navigator
  const AppChrome({super.key, required this.navigatorKey, required this.child});

  @override
  State<AppChrome> createState() => _AppChromeState();
}

class _AppChromeState extends State<AppChrome> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final controller = SessionScope.of(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => controller.resetActivity(),
      onPointerMove: (_) => controller.resetActivity(),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: kBg,
        drawer: AppDrawer(
          navigatorKey: widget.navigatorKey,
          controller: controller,
          onCloseDrawer: () => _scaffoldKey.currentState?.closeDrawer(),
        ),
        body: SafeArea(
          child: Column(
            children: [
              AppHeaderBar(controller: controller, onMenu: () => _scaffoldKey.currentState?.openDrawer()),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

/// The static two-line header (migrated from main.dart `_buildAppBar`) plus the hamburger button
/// and the inactivity countdown.
class AppHeaderBar extends StatelessWidget {
  final SessionController controller;
  final VoidCallback onMenu;
  const AppHeaderBar({super.key, required this.controller, required this.onMenu});

  Future<void> _launch(String urlStr) async {
    final url = Uri.parse(urlStr);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // NB: no Tooltip here — the chrome sits beside the Navigator's Overlay, so an
          // Overlay-dependent Tooltip would assert. The hamburger icon is self-explanatory.
          IconButton(
            icon: const Icon(Icons.menu, color: kText),
            onPressed: onMenu,
          ),
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: kHighlight, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Configure PIA WireGuard', style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w600)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('by ', style: TextStyle(color: kMuted, fontSize: 10)),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: InkWell(
                        onTap: () => _launch('https://www.exponentiallydigital.com'),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 2),
                          child: Text('Exponentially Digital',
                              style: TextStyle(color: kMuted, fontSize: 10, decoration: TextDecoration.underline)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _countdown(controller),
          ),
          const SizedBox(width: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: InkWell(
              onTap: () => _launch('https://github.com/ExponentiallyDigital/cfg-pia-wg'),
              child: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snap) => Text(
                  snap.hasData ? 'v${snap.data!.version}' : 'v...',
                  style: const TextStyle(color: kMuted, fontSize: 11, decoration: TextDecoration.underline),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // Inactivity countdown (mm:ss). Hidden while a modal is open (spec §3).
  Widget _countdown(SessionController c) {
    if (c.modalsOpen || c.inactivitySeconds <= 0) return const SizedBox.shrink();
    final urgent = c.inactivitySeconds <= 60;
    final color = urgent ? kError : kHighlight;
    final m = (c.inactivitySeconds ~/ 60).toString();
    final s = (c.inactivitySeconds % 60).toString().padLeft(2, '0');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 12, color: color),
        const SizedBox(width: 4),
        Text('$m:$s', key: const Key('inactivity_countdown'), style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}

/// Per-screen body wrapper: a scrollable padded content area plus an optional HOME button that
/// returns to a fresh main menu (spec 2.1; stack-growth is intentional).
class AppScaffold extends StatelessWidget {
  final Widget child;
  final bool showClose;
  const AppScaffold({super.key, required this.child, this.showClose = true});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kBg,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: child,
            ),
          ),
          if (showClose)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('screen_close'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: kMuted,
                      side: const BorderSide(color: kBorder),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => navigateToDestination(context, SessionScope.of(context), AppDestination.menu),
                  child: const Text('HOME'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
