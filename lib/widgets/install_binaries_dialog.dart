// widgets/install_binaries_dialog.dart - offers to install the stock helper binaries.
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
// Offered as a convenience, never imposed. Two things follow from that and both are load-bearing:
//
//   - The user is told exactly what will be downloaded, from where, at which version, and where it
//     lands - before agreeing. Putting an executable on someone's router is not a detail to hide
//     behind a spinner, and anyone who would rather do it themselves keeps that option.
//
//   - The consequence of declining is stated UP FRONT. MANAGE and WATCHDOG genuinely cannot run
//     without these on stock, so "no" means the screen stays unavailable. Saying so before the
//     choice is the difference between an informed decision and a discovery.
//
// A refusal is remembered for the session by the caller, so this does not reappear on every screen
// entry. See .claude/plans/plan_install-helper-binaries.md.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_colors.dart';
import '../firmware.dart';
import '../binary_installer.dart';
import '../session_controller.dart';

/// What the user chose.
enum InstallChoice {
  /// Go ahead and install.
  install,

  /// Leave it; the caller falls back to the manual-instructions notice.
  decline,
}

/// Asks whether to install [missing] (destination paths, as `missingStockBinaries` reports them).
///
/// Returns [InstallChoice.decline] if the dialog is dismissed, so a stray back-gesture is never
/// read as consent to write to the router.
Future<InstallChoice> showInstallBinariesDialog(
  BuildContext context,
  SessionController controller,
  List<String> missing,
) async {
  final binaries = missing.map((p) => kHelperBinaries[p]).whereType<HelperBinary>().toList();
  if (binaries.isEmpty) return InstallChoice.decline;

  controller.enterModal();
  final choice = await showDialog<InstallChoice>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => _InstallBinariesDialog(binaries: binaries),
  );
  controller.exitModal();
  return choice ?? InstallChoice.decline;
}

class _InstallBinariesDialog extends StatefulWidget {
  const _InstallBinariesDialog({required this.binaries});
  final List<HelperBinary> binaries;

  @override
  State<_InstallBinariesDialog> createState() => _InstallBinariesDialogState();
}

class _InstallBinariesDialogState extends State<_InstallBinariesDialog> {
  // The README reference was plain text and users tried to tap it, which is fair - the same
  // words are a working link on the notice that follows. Same guard-then-launch shape as
  // firmware_notice.dart and the About screen.
  late final TapGestureRecognizer _recogniser = TapGestureRecognizer()..onTap = _launch;

  @override
  void dispose() {
    _recogniser.dispose();
    super.dispose();
  }

  Future<void> _launch() async {
    final url = Uri.parse(kReadmePrereqUrl);
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.platformDefault);
  }

  @override
  Widget build(BuildContext context) {
    final binaries = widget.binaries;
    final plural = binaries.length > 1;
    return AlertDialog(
      key: const Key('install_binaries'),
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          const Icon(Icons.download_outlined, color: kHighlight, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(plural ? 'Install helper programs?' : 'Install ${binaries.single.name}?',
                style: const TextStyle(color: kHighlight, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your router is missing ${plural ? 'these programs' : 'this program'}, which this screen '
              'cannot work without. I can download ${plural ? 'them' : 'it'} for you.',
              style: const TextStyle(color: kText, fontSize: 13),
            ),
            const SizedBox(height: 12),
            // Provenance in full: what, which version, from where, to where. The user is agreeing
            // to run an executable on their router and is entitled to see all of it.
            for (final b in binaries) ...[
              Text('${b.name} ${b.version}', style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w700)),
              Text('from ${b.assets.values.first.sourceLabel}', style: const TextStyle(color: kMuted, fontSize: 11)),
              Text('to ${b.destination}', style: const TextStyle(color: kMuted, fontSize: 11)),
              // The expected hash, shown so it can be checked against the project's own published
              // checksums rather than taken on trust. Saying "we verify a checksum" without saying
              // which one asks the user to believe us about the very thing being verified.
              Text('sha256 ${b.assets.values.first.sha256}',
                  style: const TextStyle(color: kMuted, fontSize: 9, fontFamily: 'monospace')),
              const SizedBox(height: 8),
            ],
            const Text(
              'Each download must match the checksum above before it is installed, and is discarded '
              'if it does not. You can compare these against the checksums the projects publish with '
              'their releases.',
              style: TextStyle(color: kMuted, fontSize: 11),
            ),
            const SizedBox(height: 12),
            Text.rich(
              key: const Key('install_binaries_readme_link'),
              TextSpan(children: [
                const TextSpan(
                  text: 'If you would rather install them yourself, see ',
                  style: TextStyle(color: kMuted, fontSize: 11),
                ),
                TextSpan(
                  text: 'Prerequisites in README.md',
                  style: const TextStyle(
                    color: kHighlight,
                    fontSize: 11,
                    decoration: TextDecoration.underline,
                    decorationColor: kHighlight,
                  ),
                  recognizer: _recogniser,
                ),
                const TextSpan(
                  text: ' - but this screen stays unavailable until they are on the router.',
                  style: TextStyle(color: kMuted, fontSize: 11),
                ),
              ]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('install_binaries_decline'),
          onPressed: () => Navigator.pop(context, InstallChoice.decline),
          child: const Text('NOT NOW', style: TextStyle(color: kMuted)),
        ),
        TextButton(
          key: const Key('install_binaries_confirm'),
          onPressed: () => Navigator.pop(context, InstallChoice.install),
          child: const Text('INSTALL', style: TextStyle(color: kHighlight, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
