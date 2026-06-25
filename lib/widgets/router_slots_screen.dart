// widgets/router_slots_screen.dart - Shared SSH-credentials form + CONNECT for the two router screens.
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
// Both the "Manage router" (2.1.2) and "Watchdog WireGuard management" (2.1.3) screens reduce to: collect
// the router IP / SSH credentials (pre-filled from the shared session), connect, fetch the slots,
// then open the parameterised SlotModal in the appropriate mode.

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../pia_service.dart';
import '../router_slot_service.dart';
import '../router_watchdog.dart';
import '../session_controller.dart';
import 'app_scaffold.dart';
import 'common_fields.dart';
import 'error_presenter.dart';
import 'slot_modal.dart';

class RouterSlotsScreen extends StatefulWidget {
  final SlotModalMode mode;
  // Test seams.
  final Future<SSHClient> Function(String ip, String user, String pass)? testClientFactory;
  final PiaService? piaService;
  final RouterSlotService Function(SSHClient)? slotServiceFactory;
  final RouterWatchdog Function(SSHClient)? watchdogServiceFactory;

  const RouterSlotsScreen({
    super.key,
    required this.mode,
    this.testClientFactory,
    this.piaService,
    this.slotServiceFactory,
    this.watchdogServiceFactory,
  });

  @override
  State<RouterSlotsScreen> createState() => _RouterSlotsScreenState();
}

class _RouterSlotsScreenState extends State<RouterSlotsScreen> {
  final _ipCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _sshVisible = false, _connecting = false, _prefilled = false;
  late SessionController _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c = SessionScope.of(context);
    if (!_prefilled) {
      _prefilled = true;
      _ipCtrl.text = _c.routerIp;
      _userCtrl.text = _c.sshUsername;
      _passCtrl.text = _c.sshPassword;
      _ipCtrl.addListener(_sync);
      _userCtrl.addListener(_sync);
      _passCtrl.addListener(_sync);
    }
  }

  @override
  void dispose() {
    for (final c in [_ipCtrl, _userCtrl, _passCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // Mirror SSH credentials into the shared session so the other router screen pre-fills them.
  void _sync() {
    _c.routerIp = _ipCtrl.text;
    _c.sshUsername = _userCtrl.text;
    _c.sshPassword = _passCtrl.text;
    setState(() {});
  }

  bool get _canConnect => _ipCtrl.text.trim().isNotEmpty && _userCtrl.text.trim().isNotEmpty && _passCtrl.text.trim().isNotEmpty;

  // A fresh client each call (so a dropped connection self-heals on the next action).
  Future<SSHClient> _connect() {
    final ip = _ipCtrl.text.trim(), user = _userCtrl.text.trim(), pass = _passCtrl.text;
    if (widget.testClientFactory != null) return widget.testClientFactory!(ip, user, pass);
    return openSshClient(ip, user, pass);
  }

  RouterSlotService _slotSvc(SSHClient c) => widget.slotServiceFactory?.call(c) ?? RouterSlotService(c, onLog: _c.onLog);

  Future<void> _onConnect() async {
    setState(() => _connecting = true);
    _c.logEntry('Connecting to router at ${_ipCtrl.text.trim()} via SSH...');
    SSHClient? client;
    RouterSlots? slots;
    try {
      client = await _connect();
      slots = await _slotSvc(client).fetchSlots();
    } catch (e) {
      if (mounted) {
        await AppErrors.system(context, _c, 'Router SSH connection error: ${e.toString().replaceAll('Exception: ', '')}');
      }
    } finally {
      client?.close();
      if (mounted) setState(() => _connecting = false);
    }
    if (slots == null || !mounted) return;

    if (widget.mode == SlotModalMode.watchdog && !slots.isMerlin) {
      await AppErrors.system(context, _c, 'The VPN watchdog requires Asus-Merlin firmware on the router.');
      return;
    }

    _c.enterModal();
    await showDialog<void>(
      context: context,
      builder: (ctx) => SlotModal(
        mode: widget.mode,
        controller: _c,
        connect: _connect,
        initialSlots: slots!,
        piaService: widget.piaService ?? PiaService(),
        slotServiceFactory: widget.slotServiceFactory,
        watchdogServiceFactory: widget.watchdogServiceFactory,
      ),
    );
    if (mounted) _c.exitModal();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RouterIpField(controller: _ipCtrl),
          const SizedBox(height: 12),
          SshUsernameField(controller: _userCtrl),
          const SizedBox(height: 12),
          SshPasswordField(
            controller: _passCtrl,
            visible: _sshVisible,
            onToggle: () => setState(() => _sshVisible = !_sshVisible),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('connect_router'),
              onPressed: (_connecting || !_canConnect) ? null : _onConnect,
              child: _connecting
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF12141A)))
                  : const Text('CONNECT TO ROUTER'),
            ),
          ),
        ],
      ),
    );
  }
}
