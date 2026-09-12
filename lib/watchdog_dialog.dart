// watchdog_dialog.dart - EDIT form for a slot's watchdog parameters (spec 2.1.3).
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
// This is the slot modal's CREATE/EDIT action for the watchdog screen. SAVE writes the watchdog
// parameters (and, when the watchdog is not yet active, selects/overwrites the region as wgcN_desc)
// to NVRAM and then deploys the script + cron via RouterWatchdog.deployWatchdog — this is the only
// path that brings a watchdog up, so there is no separate ENABLE action.

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'firmware.dart';
import 'pia_service.dart';
import 'router_slot_service.dart' show slotLabel;
import 'router_watchdog.dart';
import 'session_controller.dart';
import 'widgets/app_scaffold.dart';
import 'widgets/error_presenter.dart';
import 'widgets/region_picker_sheet.dart';

class WatchdogDialog extends StatefulWidget {
  final int slotIndex;
  final String regionDesc; // wgcN_desc (read-only display)
  final bool slotIsEmpty; // drives the region-selection / overwrite-warning flow
  final SessionController controller; // app-wide log + error presentation
  final String piaUsername, piaPassword; // pre-fill from the session login
  final Future<SSHClient> Function() connect; // captures router ip/user/pass
  final PiaService? piaService; // region listing (defaults to a real PiaService)
  final RouterWatchdog Function(SSHClient)? serviceFactory; // test seam

  const WatchdogDialog({
    super.key,
    required this.slotIndex,
    required this.regionDesc,
    required this.slotIsEmpty,
    required this.controller,
    required this.connect,
    this.piaUsername = '',
    this.piaPassword = '',
    this.piaService,
    this.serviceFactory,
  });

  @override
  State<WatchdogDialog> createState() => _WatchdogDialogState();
}

class _WatchdogDialogState extends State<WatchdogDialog> {
  final _intervalCtrl = TextEditingController(text: '5');
  final _primaryCtrl = TextEditingController(text: '8.8.8.8');
  final _secondaryCtrl = TextEditingController(text: '1.1.1.1');
  final _piaUserCtrl = TextEditingController();
  final _piaPassCtrl = TextEditingController();
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController(text: 'cfg-pia-wg alert');
  final _smtpServerCtrl = TextEditingController();
  final _smtpUserCtrl = TextEditingController();
  final _smtpPassCtrl = TextEditingController();

  bool _emailEnabled = false;
  bool _loading = false;

  /// The SAVE button, so a save can scroll its own spinner into view. The dialog scrolls, and with
  /// the keyboard up the button sits below the fold - which is what made a save look inert.
  bool _jqMissing = false;

  /// Stock only: the init directory Download Master provides. Without it a watchdog deploys and
  /// then loses its cron entries at the next reboot, so it is a precondition, not a warning.
  bool _bootDirMissing = false;
  bool _piaPassVisible = false;
  bool _smtpPassVisible = false;
  WatchdogStatus? _status;

  SessionController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _piaUserCtrl.text = widget.piaUsername;
    _piaPassCtrl.text = widget.piaPassword;
    _load();
  }

  // Mirrors the PIA credentials back into the session so every other screen and dialog that needs
  // them pre-fills, the same way the SSH credentials are retained (see session_controller.dart).
  // Non-empty guards only: closing this dialog with a blank field must not discard a credential we
  // already know. Volatile like the rest of the session — SessionController.wipeAll clears it.
  void _rememberPiaCreds() {
    final user = _piaUserCtrl.text.trim();
    final pass = _piaPassCtrl.text;
    if (user.isNotEmpty) _c.piaUsername = user;
    if (pass.isNotEmpty) _c.piaPassword = pass;
  }

  @override
  void dispose() {
    // Runs on every exit path (SAVE, CLOSE, barrier dismiss), so whatever was typed is retained.
    _rememberPiaCreds();
    for (final c in [
      _intervalCtrl,
      _primaryCtrl,
      _secondaryCtrl,
      _piaUserCtrl,
      _piaPassCtrl,
      _fromCtrl,
      _toCtrl,
      _subjectCtrl,
      _smtpServerCtrl,
      _smtpUserCtrl,
      _smtpPassCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // Runs the operation on the session's shared SSH connection. Nothing is closed here: the
  // connection outlives this dialog, and closing it would break the next action.
  Future<T?> _withService<T>(Future<T> Function(RouterWatchdog) op) async {
    setState(() => _loading = true);
    try {
      final client = await widget.connect();
      final svc = (widget.serviceFactory ?? (c) => RouterWatchdog(c, onLog: _c.onLog))(client);
      return await op(svc);
    } catch (e) {
      if (mounted) await AppErrors.system(context, _c, 'Watchdog error: ${e.toString().replaceAll('Exception: ', '')}');
      return null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _load() async {
    await _withService((svc) async {
      final jq = await svc.isJqInstalled();
      final bootReady = await svc.isBootPersistenceReady();
      final status = await svc.getWatchdogStatus(widget.slotIndex);
      final cfg = await svc.loadConfig(widget.slotIndex);
      if (!mounted) return;
      setState(() {
        _jqMissing = !jq;
        _bootDirMissing = !bootReady;
        _status = status;
        _applyConfig(cfg);
      });
    });
    if (!mounted) return;
    if (_jqMissing) {
      await AppErrors.system(context, _c, '$_jqLabel is not installed on the router; the watchdog cannot be configured.');
    } else if (_bootDirMissing) {
      await AppErrors.system(context, _c, kBootDirMissingMessage);
    }
  }

  // Names the actual path on stock, where jq lives outside $PATH and the user installs it by hand.
  String get _jqLabel => isStockFirmware ? kStockJqPath : 'jq';

  /// Blocked, not warned about: a watchdog with no boot persistence stops at the next power cut
  /// and says nothing, which is worse than never having deployed one.
  bool get _blocked => _jqMissing || _bootDirMissing;

  void _applyConfig(WatchdogConfig c) {
    _intervalCtrl.text = '${c.cronIntervalMinutes}';
    if (c.primaryIp.isNotEmpty) _primaryCtrl.text = c.primaryIp;
    if (c.secondaryIp.isNotEmpty) _secondaryCtrl.text = c.secondaryIp;
    if (widget.piaUsername.isEmpty && c.piaUsername.isNotEmpty) _piaUserCtrl.text = c.piaUsername;
    if (widget.piaPassword.isEmpty && c.piaPassword.isNotEmpty) _piaPassCtrl.text = c.piaPassword;
    _emailEnabled = c.emailAlertsEnabled;
    _fromCtrl.text = c.emailFrom;
    _toCtrl.text = c.emailTo;
    if (c.emailSubject.isNotEmpty) _subjectCtrl.text = c.emailSubject;
    _smtpServerCtrl.text = c.smtpServer;
    _smtpUserCtrl.text = c.smtpUsername;
    _smtpPassCtrl.text = c.smtpPassword;
    // Credentials recovered from NVRAM count as session-known too, so a user who never typed them
    // still gets them pre-filled elsewhere.
    _rememberPiaCreds();
  }

  WatchdogConfig _currentConfig() => WatchdogConfig(
        slotIndex: widget.slotIndex,
        cronIntervalMinutes: int.tryParse(_intervalCtrl.text.trim()) ?? 0,
        primaryIp: _primaryCtrl.text,
        secondaryIp: _secondaryCtrl.text,
        piaUsername: _piaUserCtrl.text,
        piaPassword: _piaPassCtrl.text,
        emailAlertsEnabled: _emailEnabled,
        emailFrom: _fromCtrl.text,
        emailTo: _toCtrl.text,
        emailSubject: _subjectCtrl.text,
        smtpServer: _smtpServerCtrl.text,
        smtpUsername: _smtpUserCtrl.text,
        smtpPassword: _smtpPassCtrl.text,
      );

  Future<String?> _pickRegion() async {
    String? chosen;
    try {
      final regions = await (widget.piaService ?? PiaService()).fetchRegions(onProgress: _c.onLog);
      if (!mounted) return null;
      await RegionPickerSheet.show(context, regions: regions, onSelected: (id) => chosen = id);
    } catch (e) {
      if (mounted) await AppErrors.system(context, _c, 'Failed to load regions: ${e.toString().replaceAll('Exception: ', '')}');
    }
    return chosen;
  }

  Future<bool> _confirmOverwrite() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        // Names what is being overwritten, the same shape the delete prompts use.
        title: Text('Overwrite ${slotLabel(widget.slotIndex, widget.regionDesc)}?',
            style: const TextStyle(color: kText, fontSize: 15)),
        content: const Text('This will reset both this watchdog and any underlying VPN region.',
            style: TextStyle(color: kMuted, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL', style: TextStyle(color: kMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CONTINUE')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _save() async {
    if (_jqMissing) {
      await AppErrors.system(context, _c, 'Cannot save: $_jqLabel is not installed on the router.');
      return;
    }
    if (_bootDirMissing) {
      await AppErrors.system(context, _c, kBootDirMissingMessage);
      return;
    }
    // Drop focus so the keyboard retracts and the last-edited field loses its green border; a
    // field still looking editable while a save runs is the other half of what made this read as
    // nothing having happened. Nothing waits on it - the progress overlay is not in the scroll
    // view, so where the keyboard leaves the viewport cannot matter.
    FocusScope.of(context).unfocus();
    final cfg = _currentConfig();
    final errors = cfg.validate();
    if (errors.isNotEmpty) {
      await AppErrors.inputs(context, _c, errors);
      return;
    }

    // When the watchdog is not yet active, a region must be (re)selected; a configured slot is
    // overwritten only after a warning.
    String? newDesc;
    final enabled = _status?.isEnabled == true;
    if (!enabled) {
      if (!widget.slotIsEmpty) {
        if (!await _confirmOverwrite()) return;
      }
      newDesc = await _pickRegion();
      if (newDesc == null) return;
    }

    final saved = await _withService((svc) async {
      // Pre-save reachability check over the WAN; warns but still allows saving (spec 2.1.3).
      final p = await svc.pingHostViaWan(cfg.primaryIp.trim());
      final s = await svc.pingHostViaWan(cfg.secondaryIp.trim());
      final warnings = <String>[];
      if (!p) warnings.add('Primary IP ${cfg.primaryIp.trim()} is not reachable from the router.');
      if (!s) warnings.add('Secondary IP ${cfg.secondaryIp.trim()} is not reachable from the router.');
      if (warnings.isNotEmpty && mounted) {
        await AppErrors.inputs(context, _c, [...warnings, 'The settings will still be saved.']);
      }
      await svc.deployWatchdog(cfg, desc: newDesc);
      return true;
    });
    if (saved != true || !mounted) return;
    // No enable here: deployWatchdog brings the slot up itself. This used to call enableVpnSlot
    // again for a slot that started empty, which bounced the tunnel the deploy's immediate script
    // run had just established - two `service restart_vpnc` calls on stock for one deploy.
    Navigator.of(context).pop();
  }

  Future<void> _testEmail() async {
    final cfg = _currentConfig().copyWith(emailAlertsEnabled: true);
    final errors = cfg.validate().where((e) => e.toLowerCase().contains('email') || e.toLowerCase().contains('smtp')).toList();
    if (errors.isNotEmpty) {
      await AppErrors.inputs(context, _c, errors);
      return;
    }
    final sent = await _withService((svc) => svc.testEmail(_currentConfig()));
    if (!mounted) return;
    // A failed send used to say nothing on screen and one teal line in the app log telling the
    // user to go and read the ROUTER log. Every diagnostic now lands in the app log, and this
    // says so - a phone is a poor place from which to go SSH into a router.
    if (sent == false) {
      await AppErrors.system(context, _c, 'The test email could not be sent. Open View app log for what the router reported.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final enabled = status?.isEnabled == true;
    // A full screen, not a dialog (418). This is a long form - ping targets, a schedule, five
    // email fields - and as a card it had a height nobody could get right. Twice it shipped with
    // the SAVE row and its spinner below the fold and the content refusing to scroll (409, then
    // again in 412), because a shrink-wrapping SingleChildScrollView inside an unbounded card has
    // no overflow to scroll. AppScaffold gives it a BOUNDED viewport - the scroll view sits in an
    // Expanded - so the same content scrolls by construction rather than by arithmetic.
    // The progress overlay sits OUTSIDE the scroll view, covering the whole screen.
    //
    // This bug has been fixed four times - 409, 412, 425 and 435 - and every fix was the same
    // shape: dismiss the keyboard, wait for something, then scroll the SAVE button into view. It
    // kept coming back because it was a race against two animations, and a scroll arriving one
    // frame early is indistinguishable from no fix at all. A spinner that is not in the scroll
    // view has no fold to be below, so there is nothing left to race. Same pattern as the slot
    // list and the device assignment screen.
    return Stack(
      children: [
        AppScaffold(
          showClose: false, // this screen has its own SAVE/CLOSE pair
          maxContentWidth: kFormMaxWidth, // the width this form had as a card
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_outlined, color: kHighlight, size: 18),
                  const SizedBox(width: 8),
                  // slotLabel, so the heading reads "wgc5:pia-aus_perth" - the same shape the
                  // EDIT modal and every log line use.
                  Expanded(
                    child: Text('WATCHDOG · ${slotLabel(widget.slotIndex, widget.regionDesc)}',
                        style: const TextStyle(color: kHighlight, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(widget.regionDesc.isEmpty ? '(no region set)' : widget.regionDesc,
                  style: const TextStyle(color: kMuted, fontSize: 12)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kField, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Icon(enabled ? Icons.check_circle : Icons.cancel, color: enabled ? kHighlight : kMuted, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(status == null ? 'Loading...' : (enabled ? 'Enabled' : 'Disabled'),
                              style: const TextStyle(color: kText, fontWeight: FontWeight.bold)),
                          Text(
                            status?.lastSuccessfulPing == null
                                ? 'Last successful ping: never'
                                : 'Last successful ping: ${status!.lastSuccessfulPing}',
                            style: const TextStyle(color: kMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_jqMissing) ...[
                const SizedBox(height: 12),
                Text('$_jqLabel is not installed on the router — install jq before enabling.',
                    style: const TextStyle(color: kError, fontSize: 12)),
              ],
              if (_bootDirMissing) ...[
                const SizedBox(height: 12),
                const Text(kBootDirMissingMessage,
                    key: Key('wd_boot_dir_missing'), style: TextStyle(color: kError, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              _field(_intervalCtrl, 'Check interval (minutes)', const Key('wd_interval'), keyboard: TextInputType.number),
              _field(_primaryCtrl, 'Primary ping IP', const Key('wd_primary')),
              _field(_secondaryCtrl, 'Secondary ping IP', const Key('wd_secondary')),
              // PIA and SMTP credentials get a group each: two different logins on one form, and
              // a provider that could not tell them apart would offer the wrong one for both.
              AutofillGroup(
                onDisposeAction: AutofillContextAction.cancel,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _field(_piaUserCtrl, 'PIA username', const Key('wd_pia_user'), autofillHints: const [AutofillHints.username]),
                    _field(_piaPassCtrl, 'PIA password', const Key('wd_pia_pass'),
                        obscure: !_piaPassVisible,
                        onToggle: () => setState(() => _piaPassVisible = !_piaPassVisible),
                        visible: _piaPassVisible,
                        autofillHints: const [AutofillHints.password]),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                key: const Key('wd_email_switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable email alerts', style: TextStyle(color: kText, fontSize: 14)),
                value: _emailEnabled,
                onChanged: _loading ? null : (v) => setState(() => _emailEnabled = v),
              ),
              if (_emailEnabled) ...[
                _field(_fromCtrl, 'From', const Key('wd_from')),
                _field(_toCtrl, 'To', const Key('wd_to')),
                _field(_subjectCtrl, 'Subject', const Key('wd_subject')),
                _field(_smtpServerCtrl, 'SMTP server (host:port)', const Key('wd_smtp_server')),
                AutofillGroup(
                  onDisposeAction: AutofillContextAction.cancel,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field(_smtpUserCtrl, 'SMTP username', const Key('wd_smtp_user'),
                          autofillHints: const [AutofillHints.username]),
                      _field(_smtpPassCtrl, 'SMTP password', const Key('wd_smtp_pass'),
                          obscure: !_smtpPassVisible,
                          onToggle: () => setState(() => _smtpPassVisible = !_smtpPassVisible),
                          visible: _smtpPassVisible,
                          autofillHints: const [AutofillHints.password]),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  key: const Key('wd_test_email'),
                  onPressed: _loading ? null : _testEmail,
                  icon: const Icon(Icons.mail_outline, size: 16),
                  label: const Text('TEST EMAIL'),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                key: const Key('wd_save'),
                onPressed: (_loading || _blocked) ? null : _save,
                // SAVE is not the end of the flow - a region picker follows it. Saying so on the
                // button stops the picker arriving as a surprise. The label STAYS during a save:
                // the spinner is the overlay, not the button. A spinner in the button put the one
                // thing the user needed to see inside the scroll view, where it could be below
                // the fold - which it was, in 409, 412, 425 and again in 435.
                child: const Text('SAVE & SELECT REGION'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  child: const Text('CLOSE', style: TextStyle(color: kMuted)),
                ),
              ),
            ],
          ),
        ),
        if (_loading)
          const Positioned.fill(
            key: Key('wd_saving_overlay'),
            child: ColoredBox(
              color: Color(0x99000000),
              child: Center(child: CircularProgressIndicator(color: kHighlight)),
            ),
          ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    Key key, {
    bool obscure = false,
    TextInputType? keyboard,
    VoidCallback? onToggle,
//    bool enableInteractiveSelection = true, // disable copy if password field is revealed
    bool visible = false,
    // Only the credentials carry hints. Ping targets, mail addresses and the SMTP host are not
    // secrets and a password manager has no business filling them.
    List<String> autofillHints = const <String>[],
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        key: key,
        controller: ctrl,
        obscureText: obscure,
        autofillHints: autofillHints,
//        enableInteractiveSelection: enableInteractiveSelection, // disable copy if password field is revealed
        keyboardType: keyboard,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(color: kText, fontFamily: 'monospace', fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: kMuted, fontSize: 13),
          filled: true,
          fillColor: kField,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBorder)),
          suffixIcon: onToggle == null
              ? null
              : GestureDetector(
                  onTap: onToggle,
                  child: Icon(visible ? Icons.visibility_off : Icons.visibility, color: kMuted, size: 18),
                ),
        ),
      ),
    );
  }
}
