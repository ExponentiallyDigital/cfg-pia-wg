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
const kHelpUrl = 'https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md#4-prerequisites--requirements';

/// How wide the menu grows before it stops and centres (ID-031). A phone is narrower than this, so there the rows
/// use the full width; on a tablet they would otherwise stretch into bars with a long gap between label and chevron.
const double kMenuMaxWidth = 520;

/// Indents the two footer links so their 16px icons sit in the same column as the 20px icons in the
/// menu rows above (ID-109): the rows pad by 18, and the extra 2 accounts for the smaller glyph.
const double kMenuIconIndent = 20;

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
            // Spare height is SHARED above and below the block, so on a tall screen the menu sits
            // optically centred rather than pinned to the top (ID-107). The split is weighted, not
            // even: a block centred by measurement reads slightly low, so the smaller share goes
            // above. `AppScaffold(fillViewport: true)` is what makes this safe - the spacers take
            // only height that is genuinely spare, and on a phone they collapse to nothing and the
            // screen scrolls exactly as it did.
            const Spacer(flex: 10),
            // Every destination the drawer offers, in the drawer's order, built from the drawer's own list so
            // the two cannot drift. The keys are unchanged: each is `menu_` plus the route name.
            for (final d in AppDrawer.destinations) ...[
              _MenuRow(
                keyValue: 'menu_${d.routeName}',
                icon: destinationIcon(d),
                label: d.title,
                // Icon and label take the screen's own colour from the one map; the outline stays
                // teal so the nine rows still read as one control set (ID-112).
                colour: destinationColour(d),
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
              outline: kError,
              opensScreen: false,
              onTap: () => confirmAndExit(context, controller),
            ),
            SizedBox(height: spacer),
            // The two links sit together, directly under the rows and indented so their icons sit in
            // the same column as the nine menu icons (ID-109).
            const _HelpLink(),
            const _ReviewLink(),
            const Spacer(flex: 12),
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
    this.outline = kHighlight,
    this.opensScreen = true,
  });

  final String keyValue;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The icon and the label: the destination's own colour (ID-112).
  final Color colour;

  /// The border. Teal for every row that opens a screen, so nine different colours do not make
  /// nine different-looking buttons; EXIT passes red, as it always has.
  final Color outline;

  final bool opensScreen;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: Key(keyValue),
      style: OutlinedButton.styleFrom(
        // The screen's own colour, so the row reads as bordered rather than filled, like every other button.
        backgroundColor: kBg,
        foregroundColor: colour,
        side: BorderSide(color: outline),
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
          // EXIT keeps the chevron's width, so every label starts at the same place. The chevron
          // stays teal whatever colour the row's icon and label take: it means "this opens a
          // screen", which is the same statement on every row (ID-128).
          opensScreen ? const Icon(Icons.chevron_right, size: 18, color: kHighlight) : const SizedBox(width: 18),
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
    return Padding(
      // kMenuIconIndent lines this icon up with the nine above it (ID-109).
      padding: const EdgeInsets.only(left: kMenuIconIndent),
      child: Text.rich(
        key: const Key('menu_help'),
        textAlign: TextAlign.start,
        TextSpan(
          style: const TextStyle(color: kHighlight, fontSize: 12),
          children: [
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(Icons.help_outline, size: 16, color: kLinkIconColour),
            ),
            TextSpan(text: ' how to use this app', recognizer: _recogniser),
          ],
        ),
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
        padding: EdgeInsets.fromLTRB(kMenuIconIndent, 8, 0, 8),
        child: Text.rich(
          textAlign: TextAlign.start,
          TextSpan(
            style: TextStyle(color: kHighlight, fontSize: 12),
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.star_outline, size: 16, color: kLinkIconColour),
              ),
              TextSpan(text: ' add a Play Store app review'),
            ],
          ),
        ),
      ),
    );
  }
}
