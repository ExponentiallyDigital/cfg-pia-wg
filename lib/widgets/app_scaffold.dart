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
import 'package:flutter/services.dart';
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

/// System bar appearance for the whole app.
///
/// From Android 15 (SDK 35) the system draws the app edge-to-edge and ignores `statusBarColor` /
/// `navigationBarColor`; at SDK 36 - what `flutter.targetSdkVersion` resolves to - there is no
/// opt-out, and Flutter enables edge-to-edge on every Android version anyway.
///
/// The ICON colour is already right without this: `MaterialApp` calls
/// `SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light)` whenever the theme is dark
/// (material/app.dart `_themeBuilder`), and this app is unconditionally dark. What that default
/// does NOT give is transparent bars - it sets an opaque black `systemNavigationBarColor` and
/// leaves `statusBarColor` at whatever the Activity theme says. On Android 14 and below, where
/// those colours are still honoured, that paints a black navigation bar against kBg (#12141A).
/// This region makes both bars transparent so the app's own background shows through, and it is
/// re-applied every frame, unlike MaterialApp's one-shot call, so a dialog carrying an AppBar
/// cannot leave a different style behind.
///
/// `systemNavigationBarContrastEnforced` is deliberately left at its default: the system's own
/// scrim behind a 3-button navigation bar is cheap insurance and we cannot verify its absence in
/// a widget test.
const SystemUiOverlayStyle kSystemOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light, // Android: icon colour (same as MaterialApp's default here)
  statusBarBrightness: Brightness.dark, // iOS: brightness of what is BEHIND the bar
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
);

class _AppChromeState extends State<AppChrome> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final controller = SessionScope.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kSystemOverlayStyle,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: kBg,
        drawer: AppDrawer(
          navigatorKey: widget.navigatorKey,
          controller: controller,
          onCloseDrawer: () => _scaffoldKey.currentState?.closeDrawer(),
        ),
        // Deliberately NOT one SafeArea around the whole body: under edge-to-edge the header's
        // kSurface has to reach the top of the window, so the header insets its own content and
        // the navigator below takes the remaining edges (bottom + landscape cutouts).
        body: Column(
          children: [
            AppHeaderBar(onMenu: () => _scaffoldKey.currentState?.openDrawer()),
            Expanded(
              // The Builder is load-bearing: it puts the context BELOW the Scaffold, so
              // removePadding copies the body's MediaQueryData - the one whose bottom viewInsets
              // the Scaffold has already removed because it resized for the keyboard. Using the
              // AppChrome context here re-injected the outer data, and every dialog then padded
              // itself by the keyboard height a second time inside an already-shrunken box,
              // collapsing to a sliver.
              //
              // removeTop because the header has ALREADY cleared the status bar; leaving it makes
              // anything below inset for it twice - showDialog wraps its child in a SafeArea
              // (useSafeArea defaults to true), which pushed the full-screen licences dialog down
              // by the status bar height and left the screen behind showing through the gap.
              child: Builder(
                builder: (bodyContext) => MediaQuery.removePadding(
                  context: bodyContext,
                  removeTop: true,
                  child: SafeArea(top: false, child: widget.child),
                ),
              ),
            ),
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
      // Edge-to-edge: the bar's colour runs behind the status bar while its content is padded
      // clear of it (and of a landscape cutout). bottom: false - the navigator owns that edge.
      child: SafeArea(
        bottom: false,
        child: Padding(
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
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: kHighlight, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'cfg-pia-wg',
                      style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
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
                              child: Text(
                                'Exponentially Digital',
                                style: TextStyle(color: kMuted, fontSize: 10, decoration: TextDecoration.underline),
                              ),
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
        ),
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
                final minHeight =
                    constraints.maxHeight > bodyPadding.vertical ? constraints.maxHeight - bodyPadding.vertical : 0.0;

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
                    foregroundColor: kHighlight,
                    side: const BorderSide(color: kHighlight),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
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
