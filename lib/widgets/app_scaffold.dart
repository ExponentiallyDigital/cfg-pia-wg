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
// the hamburger stays visible and tappable even while a dialog (slot modal, EDIT, error) is shown
// below it (spec 3.1).

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_colors.dart';
import '../session_controller.dart';
import 'app_drawer.dart';

/// Wraps the whole navigator with the static header bar and the hamburger drawer.
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
    return Scaffold(
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
            AppHeaderBar(onMenu: () => _scaffoldKey.currentState?.openDrawer()),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}

/// The static two-line header (migrated from main.dart `_buildAppBar`) plus the hamburger button.
class AppHeaderBar extends StatelessWidget {
  final VoidCallback onMenu;
  const AppHeaderBar({super.key, required this.onMenu});

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
            key: const Key('app_hamburger'),
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

}

/// Per-screen body wrapper: a scrollable padded content area plus an optional HOME button that
/// returns to a fresh main menu (spec 2.1; stack-growth is intentional).
class AppScaffold extends StatelessWidget {
  final Widget child;
  final bool showClose;
  final bool fillViewport;
  const AppScaffold({super.key, required this.child, this.showClose = true, this.fillViewport = false});

  @override
  Widget build(BuildContext context) {
    const bodyPadding = EdgeInsets.all(20);

    return ColoredBox(
      color: kBg,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final minHeight = constraints.maxHeight > bodyPadding.vertical
                    ? constraints.maxHeight - bodyPadding.vertical
                    : 0.0;

                return SingleChildScrollView(
                  padding: bodyPadding,
                  child: fillViewport
                      ? ConstrainedBox(
                          constraints: BoxConstraints(minHeight: minHeight),
                          child: IntrinsicHeight(child: child),
                        )
                      : child,
                );
              },
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
