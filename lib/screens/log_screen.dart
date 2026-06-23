// screens/log_screen.dart - Scrollable application log viewer (spec 2.1.4).
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

import '../session_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common_fields.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = SessionScope.of(context);
    return AppScaffold(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ClearButton(label: 'CLEAR LOG', icon: Icons.delete_outline, onTap: controller.clearLog),
              ],
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'LOG'),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: LogPanel(entries: controller.log),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
