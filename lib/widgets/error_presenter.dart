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

import '../app_colors.dart';
import '../session_controller.dart';

class AppErrors {
  // Tracks the single open error dialog so a newer error can dismiss an older one. The token
  // guards the stale dialog's continuation from clobbering newer state.
  static int _token = 0;
  static NavigatorState? _openErrorNav;

  /// One system/SSH error at a time.
  static Future<void> system(BuildContext context, SessionController controller, String message) =>
      _present(context, controller, [message]);

  /// All input-validation errors batched into a single dialog. No-op for an empty list.
  static Future<void> inputs(BuildContext context, SessionController controller, List<String> errors) =>
      errors.isEmpty ? Future<void>.value() : _present(context, controller, errors);

  static Future<void> _present(BuildContext context, SessionController controller, List<String> messages) async {
    for (final m in messages) {
      controller.logEntry(m, isError: true);
    }

    // Dismiss any error dialog already on screen (spec §3: one at a time).
    if (_openErrorNav?.canPop() ?? false) _openErrorNav!.pop();

    final myToken = ++_token;
    _openErrorNav = Navigator.of(context, rootNavigator: true);
    controller.enterModal();
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _ErrorDialog(
        title: messages.length > 1 ? 'Please correct the following' : 'Error',
        messages: messages,
      ),
    );
    if (_token == myToken) _openErrorNav = null;
    controller.exitModal();
  }
}

class _ErrorDialog extends StatelessWidget {
  final String title;
  final List<String> messages;
  const _ErrorDialog({required this.title, required this.messages});

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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK', style: TextStyle(color: kHighlight, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
