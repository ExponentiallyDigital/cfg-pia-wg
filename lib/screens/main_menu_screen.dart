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
import '../session_controller.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_scaffold.dart';

/// Deep link to the README section that walks through each screen.
const kHelpUrl = 'https://github.com/ExponentiallyDigital/cfg-pia-wg/blob/main/README.md#5-using-the-app';
const _paypalDonationUrl = 'https://www.paypal.com/donate/?hosted_button_id=QJYPGRLG2RPBS';
const _patreonDonationUrl = 'https://www.patreon.com/cw/ExponentiallyDigital';
const _scaffoldBodyPadding = 20.0;

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
    final targetBottomGap = MediaQuery.sizeOf(context).height * 0.05;
    final donationBottomGap = targetBottomGap > _scaffoldBodyPadding ? targetBottomGap - _scaffoldBodyPadding : 0.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await confirmAndExit(context, controller); // confirm before the back key exits (round-2)
      },
      child: AppScaffold(
        showClose: false,
        fillViewport: true,
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
            const Text('* requires SSH connectivity to an ASUS router',
                textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 12),
            const _HelpLink(),
            const Spacer(),
            const _DonationBlock(),
            SizedBox(height: donationBottomGap),
          ],
        ),
      ),
    );
  }
}

class _DonationBlock extends StatelessWidget {
  const _DonationBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: const [
        Text(
          'Support development:',
          textAlign: TextAlign.center,
          style: TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _DonationButton(
              keyValue: 'donate_paypal',
              label: 'PAYPAL',
              url: _paypalDonationUrl,
            ),
            SizedBox(width: 12),
            _DonationButton(
              keyValue: 'donate_patreon',
              label: 'PATREON',
              url: _patreonDonationUrl,
            ),
          ],
        ),
      ],
    );
  }
}

class _DonationButton extends StatelessWidget {
  final String keyValue;
  final String label;
  final String url;
  const _DonationButton({required this.keyValue, required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 104),
      child: OutlinedButton(
        key: Key(keyValue),
        style: OutlinedButton.styleFrom(
          foregroundColor: kHighlight,
          side: const BorderSide(color: kHighlight),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        onPressed: () async => _launchExternalUrl(url),
        child: Text(label, textAlign: TextAlign.center),
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

/// Tappable "(?) How to use this app" line under the SSH footnote, opening the README section of
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
      textAlign: TextAlign.center,
      TextSpan(
        style: const TextStyle(color: kHighlight, fontSize: 12),
        children: [
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(Icons.help_outline, size: 16, color: kHighlight),
          ),
          TextSpan(
            text: ' How to use this app',
            style: const TextStyle(decoration: TextDecoration.underline, decorationColor: kHighlight),
            recognizer: _recogniser,
          ),
        ],
      ),
    );
  }
}
