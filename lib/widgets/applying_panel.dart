// applying_panel.dart - "Applying - do not leave this screen." while the router is being changed.
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
import 'package:flutter/material.dart';

import '../app_colors.dart';

/// A spinner beside "Applying - do not leave this screen.", centred on the screen.
///
/// DEVICE ASSIGNMENT showed it for an apply, and MANAGE and WATCHDOG only a bare spinner, though a
/// deploy can take a minute (ID-246). One widget, so the three read the same. Whoever shows it also
/// stops the back button: this only says "do not leave", it cannot stop a leave by itself.
class ApplyingPanel extends StatelessWidget {
  const ApplyingPanel({super.key});

  static const String message = 'Applying - do not leave this screen.';

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('applying_panel'),
        backgroundColor: kSurface,
        content: Row(mainAxisSize: MainAxisSize.min, children: const [
          SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kHighlight)),
          SizedBox(width: 16),
          Flexible(child: Text(message, style: TextStyle(color: kText, fontSize: 14))),
        ]),
      );
}
