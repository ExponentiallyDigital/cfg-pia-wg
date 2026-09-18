// widgets/app_button.dart - the house button, and the one place a button's colour is decided.
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
// HOUSE STYLE (CONTEXT.md): every button is bordered and unfilled, with its border and label in
// one colour, and that colour says what the button does. The paywall is the one exemption. The main
// menu follows the same colours in a row layout of its own (ID-031), so it does not use this widget.
//
// The app had drifted into four looks - filled teal, bare text links, bordered teal and bordered
// grey - chosen screen by screen. A reader cannot learn what a colour means when the same action
// is teal-filled on one screen and a grey link on the next, so the choice now lives here.
//
// Controls with a layout of their own - HOME, the log button row, the settings rows - keep that
// layout but take their colour from [AppButton.tint], so the meaning cannot drift either.

import 'package:flutter/material.dart';

import '../app_colors.dart';

/// What a button does. This, and nothing about the screen it sits on, decides its colour.
enum ButtonRole {
  /// Does something. Teal.
  action,

  /// Destroys, removes, discards, reboots or exits. Red.
  destructive,

  /// A way out that changes nothing - CANCEL, CLOSE, NOT NOW. Grey.
  dismiss,
}

/// A bordered, unfilled button whose border and label share the colour of its [role].
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.keyValue,
    this.role = ButtonRole.action,
    this.icon,
    this.fullWidth = false,
    this.busy = false,
    this.fontSize,
    this.colour,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// Applied to the inner button, so `find.byKey` lands on the ButtonStyleButton tests inspect.
  final String? keyValue;

  final ButtonRole role;
  final IconData? icon;

  /// For actions on a screen. Dialog actions keep their label's width.
  final bool fullWidth;

  /// Replaces the label with a spinner. Pass a null [onPressed] alongside it.
  final bool busy;

  final double? fontSize;

  /// Overrides [role]'s colour for a button whose VERB carries a colour of its own (ID-118); the
  /// slot actions are the only users. A disabled button ignores it and greys out as usual, so a
  /// dead button never reads as live.
  final Color? colour;

  /// The colour for [role]. Disabled is DARKER than the dismiss grey, so a greyed-out action never
  /// reads as a live CANCEL.
  static Color tint(ButtonRole role, {required bool enabled}) {
    if (!enabled) return kHint;
    return switch (role) {
      ButtonRole.action => kHighlight,
      ButtonRole.destructive => kError,
      ButtonRole.dismiss => kMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final tone = enabled ? (colour ?? tint(role, enabled: true)) : kHint;
    final style = OutlinedButton.styleFrom(
      foregroundColor: tone,
      disabledForegroundColor: kHint,
      side: BorderSide(color: tone),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      textStyle: fontSize == null ? null : TextStyle(fontSize: fontSize),
    );
    final key = keyValue == null ? null : Key(keyValue!);
    final Widget child = busy
        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kHighlight))
        : Text(label);
    final Widget button = icon == null || busy
        ? OutlinedButton(key: key, style: style, onPressed: onPressed, child: child)
        : OutlinedButton.icon(
            key: key, style: style, onPressed: onPressed, icon: Icon(icon, size: 16), label: child);
    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
