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

import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_colors.dart';
import '../firmware.dart';
import '../pia_service.dart';
import '../router_slot_service.dart';
import '../router_watchdog.dart';
import '../binary_installer.dart';
import '../session_controller.dart';
import 'install_binaries_dialog.dart';
import 'app_scaffold.dart';
import 'common_fields.dart';
import 'error_presenter.dart';
import 'firmware_notice.dart';
import 'slot_modal.dart';

/// What came of offering to install the missing helper binaries. Distinguishes a fresh refusal
/// from one made earlier in the session: the first has just been told everything the follow-up
/// notice would say, the second has not been told anything this time round.
enum _InstallOutcome { installed, justDeclined, previouslyDeclined, failed }

/// Outcome of the firmware gate. Carries what to show rather than showing it, so the connect
/// spinner can be cleared before any dialog is awaited.
class _FirmwareGate {
  final bool passed;
  final String? errorMessage; // system error (detection failed)
  final List<String> missingBinaries; // stock helper binaries that are absent

  const _FirmwareGate.ok()
      : passed = true,
        errorMessage = null,
        missingBinaries = const [];
  const _FirmwareGate.error(this.errorMessage)
      : passed = false,
        missingBinaries = const [];
  const _FirmwareGate.unsupported()
      : passed = false,
        errorMessage = null,
        missingBinaries = const [];
  const _FirmwareGate.missingBinaries(this.missingBinaries)
      : passed = false,
        errorMessage = null;

  Future<void> present(BuildContext context, SessionController c) {
    if (errorMessage != null) return AppErrors.system(context, c, errorMessage!);
    if (missingBinaries.isNotEmpty) return showMissingBinariesNotice(context, c, missingBinaries);
    return showUnsupportedFirmwareNotice(context, c);
  }
}

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
      // Defaults for a fresh session; never overwrite values the user already entered.
      // routerIpPrefill is session value, then the address remembered from a previous session,
      // then the ASUS factory default.
      _ipCtrl.text = _c.routerIpPrefill;
      _userCtrl.text = _c.sshUsername.isNotEmpty ? _c.sshUsername : kDefaultSshUsername;
      _passCtrl.text = _c.sshPassword;
      _c.routerIp = _ipCtrl.text;
      _c.sshUsername = _userCtrl.text;
      _ipCtrl.addListener(_sync);
      _userCtrl.addListener(_sync);
      _passCtrl.addListener(_sync);

      // If we already connected this session, re-connect and jump straight to the slot modal.
      if (_c.routerConnected && _canConnect) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onConnect();
        });
      }
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

  // The shared session, not a fresh client: one handshake and one dropbear login line per app
  // session instead of per action. A dropped connection used to self-heal by virtue of the next
  // action reconnecting; RouterSession.run now does that explicitly, with one retry.
  Future<SSHClient> _connect() async {
    final ip = _ipCtrl.text.trim(), user = _userCtrl.text.trim(), pass = _passCtrl.text;
    return _c.routerSession(
        () => widget.testClientFactory != null ? widget.testClientFactory!(ip, user, pass) : openSshClient(ip, user, pass));
  }

  RouterSlotService _slotSvc(SSHClient c) => widget.slotServiceFactory?.call(c) ?? RouterSlotService(c, onLog: _c.onLog);

  // Firmware detection + the stock precondition checks. Pure SSH work: the outcome is reported
  // back so the caller can present it once the connect spinner has been cleared.
  //
  // Detection runs once per app session; any failure leaves the flag unset so the next navigation
  // to a router screen retries it.
  Future<_FirmwareGate> _checkFirmware(RouterSlotService svc) async {
    if (!firmwareDetected) {
      final String tag;
      try {
        tag = await svc.readFirmwareTag();
      } catch (e) {
        return _FirmwareGate.error('Unable to determine router firmware type: ${e.toString().replaceAll('Exception: ', '')}');
      }
      final detected = classifyFirmwareTag(tag);
      if (detected == null) return const _FirmwareGate.unsupported();
      setRouterFirmware(detected);
      _c.logEntry('Router firmware detected: ${detected.name}.');
    }

    if (!isStockFirmware) return const _FirmwareGate.ok();
    // The manage screen never sends email, so it does not need the mail binary.
    final missing = await svc.missingStockBinaries(needMailsend: widget.mode == SlotModalMode.watchdog);
    return missing.isEmpty ? const _FirmwareGate.ok() : _FirmwareGate.missingBinaries(missing);
  }

  Future<void> _onConnect() async {
    // Nothing here is typed into, and a dialog closing restores focus to whatever had it last -
    // so without this the keyboard reopens over the connect spinner on a field the user has
    // finished with.
    FocusScope.of(context).unfocus();
    setState(() => _connecting = true);
    _c.logEntry('Connecting to router at ${_ipCtrl.text.trim()} via SSH...');
    RouterSlots? slots;
    _FirmwareGate? gate;
    String? connectError;
    try {
      final client = await _connect();
      // Force the connection HERE, so a bad address or a refused login is reported as what it is.
      // RouterSession connects lazily, so `_connect()` does no I/O - the first command did, which
      // meant a connection failure surfaced inside _checkFirmware and was relabelled "Unable to
      // determine router firmware type". Only on the first connect of a session, since after that
      // the firmware is cached and the probe is skipped - which is why the same mistake reported
      // two different errors depending on what had happened earlier.
      await client.authenticated;
      final svc = _slotSvc(client);
      // Detection has to precede fetchSlots: on stock the slot list comes from vpnc_clientlist.
      gate = await _checkFirmware(svc);
      if (gate.passed) {
        slots = await svc.fetchSlots();
        _c.routerConnected = true; // remember the successful connect for auto-reconnect on re-entry
        // Only now, with the connect proven: a wrong address must never be stored.
        await _c.rememberRouterIp(_ipCtrl.text.trim());
        // The router accepted these credentials: offer to save them, and only here.
        TextInput.finishAutofillContext();
      }
    } catch (e) {
      connectError = 'Router SSH connection error: ${e.toString().replaceAll('Exception: ', '')}';
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
    if (!mounted) return;

    // Spinner is off, so it is safe to await a modal (see .claude/CONTEXT.md, "Async + UI").
    if (connectError != null) return AppErrors.system(context, _c, connectError);
    if (gate != null && !gate.passed) {
      // Missing binaries are the one gate failure the app can do something about, so offer
      // rather than just explaining. Everything else still just explains.
      if (gate.missingBinaries.isNotEmpty) {
        final outcome = await _offerInstall(gate.missingBinaries);
        if (!mounted) return;
        if (outcome == _InstallOutcome.installed) return _onConnect(); // retry the gate, do not assume
        // Declining is an informed choice - the dialog said what happens and where to read more -
        // so following it with the same information again is nagging. The notice still appears on
        // the NEXT visit, which is where it stops being a repeat and starts being a reminder.
        if (outcome == _InstallOutcome.justDeclined) return;
      }
      if (!mounted) return;
      return gate.present(context, _c);
    }
    if (slots == null) return;

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

  /// Offers to install [missing], and does it if the user agrees.
  Future<_InstallOutcome> _offerInstall(List<String> missing) async {
    final key = missing.join(',');
    // Already said no this session: fall straight through to the notice rather than re-asking.
    if (_c.declinedBinaryInstalls.contains(key)) return _InstallOutcome.previouslyDeclined;
    if (await showInstallBinariesDialog(context, _c, missing) != InstallChoice.install) {
      _c.declinedBinaryInstalls.add(key);
      return _InstallOutcome.justDeclined;
    }

    if (!mounted) return _InstallOutcome.failed;
    FocusScope.of(context).unfocus(); // the dialog just handed focus back to a field
    setState(() => _connecting = true);
    var allOk = true;
    String? failure;
    try {
      final client = await _connect();
      final installer = BinaryInstaller(
        (cmd) async => utf8.decode(await client.run(cmd)).trim(),
        onLog: _c.onLog,
      );
      for (final path in missing) {
        final binary = kHelperBinaries[path];
        if (binary == null) continue;
        final result = await installer.install(binary);
        if (!result.ok) {
          allOk = false;
          failure = '${binary.name}: ${result.error}';
          break; // no point installing the second one if the first failed for a shared reason
        }
      }
    } catch (e) {
      allOk = false;
      failure = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
    if (!mounted) return _InstallOutcome.failed;

    if (!allOk) {
      // Do not remember this as a refusal - the user said yes, the install failed, and trying
      // again after fixing the cause is a reasonable thing to want to do.
      // 'Could not install X: reason' - the reason is a phrase, so it needs the colon to read as
      // a sentence. Without it, build 412 produced 'Could not install the archive extracted to
      // nothing', which parses as nonsense on first reading.
      await AppErrors.system(context, _c, 'Could not install ${failure ?? 'the helper program: unknown error'}');
      return _InstallOutcome.failed;
    }
    return _InstallOutcome.installed;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RouterIpField(controller: _ipCtrl),
          const SizedBox(height: 12),
          // The router IP stays outside the group - it is not a secret, and a password manager
          // has no business filling it.
          AutofillGroup(
            onDisposeAction: AutofillContextAction.cancel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SshUsernameField(controller: _userCtrl),
                const SizedBox(height: 12),
                SshPasswordField(
                  controller: _passCtrl,
                  visible: _sshVisible,
                  onToggle: () => setState(() => _sshVisible = !_sshVisible),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('connect_router'),
              onPressed: (_connecting || !_canConnect) ? null : _onConnect,
              child: _connecting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kHighlight))
                  : const Text('CONNECT TO ROUTER'),
            ),
          ),
        ],
      ),
    );
  }
}
