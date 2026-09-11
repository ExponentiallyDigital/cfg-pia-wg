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
//
// The third log screen, and built like the other two: the log fills the body and COPY / CLEAR /
// HOME sit in one pinned row at the bottom. It opens at the newest entry, because the reason
// anyone comes here is to see what just happened.

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../session_controller.dart';
import '../widgets/app_drawer.dart';
import '../widgets/common_fields.dart';
import '../widgets/log_buttons.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // After the first layout, so maxScrollExtent is real. Opening at the top means scrolling past
    // a session's worth of history to reach the line that brought the user here.
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _copy(SessionController c) async {
    // The rendered panel is one run of text; COPY hands over the same thing, so what is pasted
    // matches what was on screen. Not a secret, so it arms no clipboard countdown.
    await c.copyToClipboard(c.log.map((e) => e.message).join('\n'), armAutoClear: false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('App log copied.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SessionScope.of(context);
    return Material(
      color: kBg,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) => Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SingleChildScrollView(
                controller: _scroll,
                child: SizedBox(width: double.infinity, child: LogPanel(entries: c.log)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: LogButtonRow(children: [
              LogButton(keyValue: 'app_log_copy', label: 'COPY', onPressed: c.log.isEmpty ? null : () => _copy(c)),
              LogButton(
                keyValue: 'app_log_clear',
                label: 'CLEAR',
                destructive: true,
                onPressed: c.log.isEmpty ? null : c.clearLog,
              ),
              LogButton(
                keyValue: 'app_log_home',
                label: 'HOME',
                onPressed: () => navigateToDestination(context, c, AppDestination.menu),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
