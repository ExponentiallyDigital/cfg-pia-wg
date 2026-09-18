// widgets/error_presenter.dart - Consistent, single-at-a-time error modals.
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
// Spec §3: input errors (missing required fields) are shown together in ONE dialog; system
// errors are shown one at a time, dismissing any previously-open error dialog first. Every
// error is also appended to the application log.

import 'package:flutter/material.dart';

import 'app_button.dart';

import '../app_colors.dart';
import '../session_controller.dart';

class AppErrors {
  // Tracks the single open error dialog so a newer error can dismiss an older one. The token
  // guards the stale dialog's continuation from clobbering newer state.
  static int _token = 0;
  static NavigatorState? _openErrorNav;

  /// One system/SSH error at a time.
  /// [detail] is shown in the dialog but NOT logged: an explanation that helps at the moment of
  /// failure is noise in a log the user scrolls through later, and the log already carries the
  /// error itself.
  ///
  /// [logDetail] is the opposite, and the pair is the point: the dialog says the plain thing while
  /// the log keeps the raw text that says which thing it was (ID-108).
  static Future<void> system(BuildContext context, SessionController controller, String message,
          {String? detail, String? logDetail}) =>
      _present(context, controller, [message], detail: detail, logDetail: logDetail);

  /// An error that has something the app can DO about it, beside OK.
  ///
  /// Returns true when the user chose [actionLabel]. Used where the fix is one the app can carry
  /// out itself - a stale configuration that needs rebuilding (ID-094) - so the dialog offers it
  /// rather than describing it and leaving the user to find the button.
  static Future<bool> systemWithAction(BuildContext context, SessionController controller, String message,
          {required String actionLabel, String? detail, String? logDetail}) async =>
      await _present(context, controller, [message], detail: detail, logDetail: logDetail, actionLabel: actionLabel) ??
      false;

  /// All input-validation errors batched into a single dialog. No-op for an empty list.
  static Future<void> inputs(BuildContext context, SessionController controller, List<String> errors) =>
      errors.isEmpty ? Future<void>.value() : _present(context, controller, errors);

  static Future<bool?> _present(BuildContext context, SessionController controller, List<String> messages,
      {String? detail, String? logDetail, String? actionLabel}) async {
    for (final m in messages) {
      controller.logEntry(m, isError: true);
    }
    if (logDetail != null) controller.logEntry(logDetail, isError: true);
    final shown = detail == null ? messages : [...messages, detail];

    // Dismiss any error dialog already on screen (spec §3: one at a time).
    if (_openErrorNav?.canPop() ?? false) _openErrorNav!.pop();

    final myToken = ++_token;
    _openErrorNav = Navigator.of(context, rootNavigator: true);
    controller.enterModal();
    final chose = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _ErrorDialog(
        title: messages.length > 1 ? 'Please correct the following' : 'Error',
        messages: shown,
        actionLabel: actionLabel,
      ),
    );
    if (_token == myToken) _openErrorNav = null;
    controller.exitModal();
    return chose;
  }
}

class _ErrorDialog extends StatelessWidget {
  final String title;
  final List<String> messages;

  /// An action the app can take about this error, shown beside OK. Null for the usual case, where
  /// there is nothing to offer.
  final String? actionLabel;
  const _ErrorDialog({required this.title, required this.messages, this.actionLabel});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          const Icon(Icons.error_outline, color: kError, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(color: kError, fontSize: 14, fontWeight: FontWeight.w700))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: messages
            .map((m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (messages.length > 1) const Text('• ', style: TextStyle(color: kText)),
                      Expanded(child: Text(m, style: const TextStyle(color: kText, fontSize: 13))),
                    ],
                  ),
                ))
            .toList(),
      ),
      actions: [
        AppButton(
          keyValue: 'error_ok',
          label: actionLabel == null ? 'OK' : 'NOT NOW',
          role: actionLabel == null ? ButtonRole.action : ButtonRole.dismiss,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        if (actionLabel != null)
          AppButton(
            keyValue: 'error_action',
            label: actionLabel!,
            onPressed: () => Navigator.of(context).pop(true),
          ),
      ],
    );
  }
}
