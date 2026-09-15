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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_colors.dart';
import '../review_service.dart';
import '../session_controller.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_scaffold.dart';

/// Deep link to the README section that walks through each screen.
const kHelpUrl = 'https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md#5-using-the-app';

/// How wide the menu grows before it stops and centres (ID-031). A phone is narrower than this, so there the rows
/// use the full width; on a tablet they would otherwise stretch into bars with a long gap between label and chevron.
const double kMenuMaxWidth = 520;

Future<void> _launchExternalUrl(String urlStr) async {
  final url = Uri.parse(urlStr);
  if (await canLaunchUrl(url)) {
    await launchUrl(url, mode: LaunchMode.platformDefault);
  }
}

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
        fillViewport: true,
        maxContentWidth: kMenuMaxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Every destination the drawer offers, in the drawer's order, built from the drawer's own list so
            // the two cannot drift. The keys are unchanged: each is `menu_` plus the route name.
            for (final d in AppDrawer.destinations) ...[
              _MenuRow(
                keyValue: 'menu_${d.routeName}',
                icon: destinationIcon(d),
                label: d.title,
                onTap: () => navigateToDestination(context, controller, d),
              ),
              const SizedBox(height: 12),
            ],
            // EXIT sits a little apart: it is the one row that does not open a screen.
            const SizedBox(height: 8),
            _MenuRow(
              keyValue: 'menu_close_app',
              icon: kExitIcon,
              label: 'EXIT',
              colour: kError,
              opensScreen: false,
              onTap: () => confirmAndExit(context, controller),
            ),
            SizedBox(height: spacer),
            // The two links sit together, directly under the rows and lined up with them, with nothing between
            // them. Any spare height goes BELOW them, so a tall screen does not push them apart or down to the foot.
            const _HelpLink(),
            const _ReviewLink(),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// One menu entry, laid out like a drawer row (ID-031): its icon, its label, and a chevron when it opens a screen.
///
/// Icon and label used to be centred together, so each row's icon started wherever its label's length put it and
/// the screen read as nine separate bundles. Left-aligned, the icons form one column and the labels a second, as
/// they do in the drawer.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.keyValue,
    required this.icon,
    required this.label,
    required this.onTap,
    this.colour = kHighlight,
    this.opensScreen = true,
  });

  final String keyValue;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color colour;
  final bool opensScreen;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: Key(keyValue),
      style: OutlinedButton.styleFrom(
        // The screen's own colour, so the row reads as bordered rather than filled, like every other button.
        backgroundColor: kBg,
        foregroundColor: colour,
        side: BorderSide(color: colour),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        alignment: Alignment.centerLeft,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 16),
          Expanded(child: Text(label)),
          // EXIT keeps the chevron's width, so every label starts at the same place.
          opensScreen ? const Icon(Icons.chevron_right, size: 18) : const SizedBox(width: 18),
        ],
      ),
    );
  }
}

/// Tappable "(?) how to use this app" line directly under the menu rows, opening the README section of
/// the same name. The recogniser is owned by a State so it can be disposed; the same pattern as
/// the About screen's links.
class _HelpLink extends StatefulWidget {
  const _HelpLink();

  @override
  State<_HelpLink> createState() => _HelpLinkState();
}

class _HelpLinkState extends State<_HelpLink> {
  late final TapGestureRecognizer _recogniser;

  @override
  void initState() {
    super.initState();
    _recogniser = TapGestureRecognizer()..onTap = () => _launchExternalUrl(kHelpUrl);
  }

  @override
  void dispose() {
    _recogniser.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      key: const Key('menu_help'),
      textAlign: TextAlign.start,
      TextSpan(
        style: const TextStyle(color: kHighlight, fontSize: 12),
        children: [
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(Icons.help_outline, size: 16, color: kHighlight),
          ),
          TextSpan(
            text: ' how to use this app',
            style: const TextStyle(decoration: TextDecoration.underline, decorationColor: kHighlight),
            recognizer: _recogniser,
          ),
        ],
      ),
    );
  }
}

/// Tappable "(*) add a Play Store app review" line directly under the help line.
///
/// The whole line is the target, not just the glyphs: this is a 12px row, and a `TextSpan`
/// recogniser only fires on the text itself, which is a small thing to hit accurately. A plain
/// GestureDetector rather than an InkWell so it still looks identical to the help link above.
class _ReviewLink extends StatelessWidget {
  const _ReviewLink();

  Future<void> _open(BuildContext context) async {
    final controller = SessionScope.of(context);
    if (!await openPlayStoreReview()) {
      controller.logEntry('Could not open the Play Store listing on this device.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('menu_review'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text.rich(
          textAlign: TextAlign.start,
          TextSpan(
            style: TextStyle(color: kHighlight, fontSize: 12),
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.star_outline, size: 16, color: kHighlight),
              ),
              TextSpan(
                text: ' add a Play Store app review',
                style: TextStyle(decoration: TextDecoration.underline, decorationColor: kHighlight),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
