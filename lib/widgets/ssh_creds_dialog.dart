// widgets/ssh_creds_dialog.dart - the router login prompt used away from the router screens.
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
// ABOUT, SETTINGS and the router log are all reachable without ever visiting a router screen, so
// each needs a way to ask for credentials rather than sending the user away to fetch them. This is
// that ask, shared so the three cannot drift apart. Returns (ip, user, password), or null if
// dismissed; the caller writes them back to the session before connecting.

import 'package:flutter/material.dart';

import '../app_colors.dart';
import 'common_fields.dart';

class SshCredsDialog extends StatefulWidget {
  final String initialIp, initialUser, initialPass;
  const SshCredsDialog({super.key, required this.initialIp, required this.initialUser, required this.initialPass});

  @override
  State<SshCredsDialog> createState() => SshCredsDialogState();
}

class SshCredsDialogState extends State<SshCredsDialog> {
  // Same starting points as the router screens: session value if there is one, else the defaults.
  // initialIp already carries the precedence (session, then remembered, then factory default),
  // resolved by SessionController.routerIpPrefill at the call site.
  late final TextEditingController _ipCtrl = TextEditingController(text: widget.initialIp);
  // Username is left BLANK rather than defaulted to 'admin', for the reason the router screens
  // give: a password manager will not overwrite a field that already has content.
  late final TextEditingController _userCtrl = TextEditingController(text: widget.initialUser);
  late final TextEditingController _passCtrl = TextEditingController(text: widget.initialPass);
  bool _visible = false;
  String? _error;

  @override
  void dispose() {
    _ipCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _onContinue() {
    final ip = _ipCtrl.text.trim(), user = _userCtrl.text.trim(), pass = _passCtrl.text;
    if (ip.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Router IP, SSH username and SSH password are all required.');
      return;
    }
    Navigator.of(context).pop((ip, user, pass));
  }

  @override
  Widget build(BuildContext context) {
    // A Dialog with its own scroll view, not an AlertDialog: an AlertDialog puts its content in a
    // Flexible, and inside the app chrome (where the Scaffold has already taken the keyboard's
    // height off the body) that Flexible collapses to zero and the fields spill out of the card.
    // This is the same structure SlotParamsEditor uses.
    return Dialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        // Width only. The height must come from the incoming constraints - inside the app chrome
        // the Scaffold has already taken the keyboard off the body, so any cap computed from the
        // screen height is too large and the card spills down behind the keyboard. Unbounded here
        // lets SingleChildScrollView shrink-wrap to the space it is given and scroll past that.
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Router SSH details', style: TextStyle(color: kHighlight, fontSize: 14)),
                const SizedBox(height: 16),
                RouterIpField(controller: _ipCtrl),
                const SizedBox(height: 10),
                // Its own group, and the router IP is deliberately outside it - see
                // plan_autofill-credentials.md. cancel: dismissing the dialog asks nothing.
                AutofillGroup(
                  onDisposeAction: AutofillContextAction.cancel,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SshUsernameField(controller: _userCtrl),
                      const SizedBox(height: 10),
                      SshPasswordField(
                          controller: _passCtrl, visible: _visible, onToggle: () => setState(() => _visible = !_visible)),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: const TextStyle(color: kError, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('about_ssh_cancel'),
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text('CANCEL', style: TextStyle(color: kMuted)),
                    ),
                    TextButton(key: const Key('about_ssh_continue'), onPressed: _onContinue, child: const Text('CONTINUE')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
