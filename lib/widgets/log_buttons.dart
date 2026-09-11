// widgets/log_buttons.dart - the three-button row both log screens carry.
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
// COPY REFRESH HOME on the router log, COPY CLEAR CLOSE on the watchdog log. Shared so the two
// cannot drift apart, which they had: one carried bare TextButtons that read as three unrelated
// links while every other button in the app is bordered.
//
// House style says HOME is full width on every screen. These two are the deliberate exception -
// a row of three cannot also be one full-width button - and that is recorded in CONTEXT.md so it
// does not get "fixed" later.

import 'package:flutter/material.dart';

import '../app_colors.dart';

/// Equal-width buttons across one row, so the set reads as one control rather than three.
class LogButtonRow extends StatelessWidget {
  const LogButtonRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: children[i]),
          ],
        ],
      );
}

/// One button in a [LogButtonRow]: bordered and teal, or red where it destroys something.
class LogButton extends StatelessWidget {
  const LogButton({
    super.key,
    required this.keyValue,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.busy = false,
  });

  final String keyValue, label;
  final VoidCallback? onPressed;
  final bool destructive, busy;

  @override
  Widget build(BuildContext context) {
    final tint = onPressed == null
        ? kMuted
        : destructive
            ? kError
            : kHighlight;
    return OutlinedButton(
      key: Key(keyValue),
      style: OutlinedButton.styleFrom(
        foregroundColor: tint,
        side: BorderSide(color: tint),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: onPressed,
      child: busy
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kHighlight))
          : Text(label),
    );
  }
}
