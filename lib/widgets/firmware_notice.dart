// widgets/firmware_notice.dart - Dismissible warnings with a tappable README link.
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
// Two firmware preconditions can turn a user away at the router-connect screen: an unsupported
// firmware, and stock firmware missing the helper binaries it needs. Both need to point the user
// at the README, so both share this dialog. AppErrors is deliberately not reused — it renders
// plain Text and has no way to carry a link.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_colors.dart';
import '../firmware.dart';
import '../session_controller.dart';

/// Warns that stock firmware is missing one or both helper binaries. [missing] holds the absent
/// paths in probe order.
/// Returns true when the user asked to install the missing binaries instead of dismissing.
///
/// The paths go on their OWN LINES. As prose they ran together with the sentence around them and a
/// reader had to pick them out of it; as a block they are a list of files that are not there, which
/// is what the reader is being told.
Future<bool> showMissingBinariesNotice(BuildContext context, SessionController controller, List<String> missing) async =>
    await showFirmwareNotice(
      context,
      controller,
      message: 'Unable to locate:\n\n${missing.join('\n')}\n\nSee ',
      linkText: 'Prerequisites in README.md',
      offerInstall: true,
    ) ==
    FirmwareNoticeChoice.install;

/// Warns that `nvram get 3rd-party` named a firmware this app does not support.
Future<void> showUnsupportedFirmwareNotice(BuildContext context, SessionController controller) => showFirmwareNotice(
      context,
      controller,
      message: 'Your firmware type is not supported, see ',
      linkText: 'README.md',
    );

/// What the user did with a notice.
enum FirmwareNoticeChoice { dismissed, install }

/// [message] is plain prose (newlines honoured) followed by [linkText], which opens [url].
Future<FirmwareNoticeChoice> showFirmwareNotice(
  BuildContext context,
  SessionController controller, {
  required String message,
  required String linkText,
  String url = kReadmePrereqUrl,
  bool offerInstall = false,
}) async {
  controller.logEntry('$message$linkText ($url)', isError: true);
  controller.enterModal();
  final choice = await showDialog<FirmwareNoticeChoice>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => _FirmwareNoticeDialog(message: message, linkText: linkText, url: url, offerInstall: offerInstall),
  );
  controller.exitModal();
  return choice ?? FirmwareNoticeChoice.dismissed;
}

class _FirmwareNoticeDialog extends StatefulWidget {
  final String message, linkText, url;

  /// Whether the thing this notice complains about is something the app can fix.
  final bool offerInstall;
  const _FirmwareNoticeDialog({
    required this.message,
    required this.linkText,
    required this.url,
    this.offerInstall = false,
  });

  @override
  State<_FirmwareNoticeDialog> createState() => _FirmwareNoticeDialogState();
}

class _FirmwareNoticeDialogState extends State<_FirmwareNoticeDialog> {
  late final TapGestureRecognizer _recogniser = TapGestureRecognizer()..onTap = _launch;

  @override
  void dispose() {
    _recogniser.dispose();
    super.dispose();
  }

  // Same guard-then-launch shape as the header bar and About screen links: silently no-op when the
  // platform cannot handle the URL.
  Future<void> _launch() async {
    final url = Uri.parse(widget.url);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('firmware_notice'),
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: kWarn, size: 20),
          SizedBox(width: 8),
          Expanded(child: Text('Warning', style: TextStyle(color: kWarn, fontSize: 14, fontWeight: FontWeight.w700))),
        ],
      ),
      content: Text.rich(
        TextSpan(children: [
          TextSpan(text: widget.message, style: const TextStyle(color: kText, fontSize: 13)),
          TextSpan(
            text: widget.linkText,
            style: const TextStyle(
              color: kHighlight,
              fontSize: 13,
              decoration: TextDecoration.underline,
              decorationColor: kHighlight,
            ),
            recognizer: _recogniser,
          ),
        ]),
        key: const Key('firmware_notice_link'),
      ),
      // OK and INSTALL on the same row. Telling a user what is missing and then leaving them to
      // find the install elsewhere is a dead end when the app can do it from here.
      actions: [
        TextButton(
          key: const Key('firmware_notice_ok'),
          onPressed: () => Navigator.of(context).pop(FirmwareNoticeChoice.dismissed),
          child: const Text('OK', style: TextStyle(color: kHighlight, fontWeight: FontWeight.w700)),
        ),
        if (widget.offerInstall)
          TextButton(
            key: const Key('firmware_notice_install'),
            onPressed: () => Navigator.of(context).pop(FirmwareNoticeChoice.install),
            child: const Text('INSTALL', style: TextStyle(color: kHighlight, fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}
