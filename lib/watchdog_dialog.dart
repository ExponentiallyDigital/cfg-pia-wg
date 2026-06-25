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
// This is the slot modal's EDIT action for the watchdog screen. Per decision #1 it SAVES the
// watchdog parameters (and, when the watchdog is not yet active, selects/overwrites the region as
// wgcN_desc) to NVRAM but does NOT deploy — the slot modal's ENABLE deploys the script + cron.

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'pia_service.dart';
import 'router_watchdog.dart';
import 'session_controller.dart';
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
  bool _jqMissing = false;
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

  @override
  void dispose() {
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

  // Opens a short-lived SSH client, runs the operation, always closes the client.
  Future<T?> _withService<T>(Future<T> Function(RouterWatchdog) op) async {
    setState(() => _loading = true);
    SSHClient? client;
    try {
      client = await widget.connect();
      final svc = (widget.serviceFactory ?? (c) => RouterWatchdog(c, onLog: _c.onLog))(client);
      return await op(svc);
    } catch (e) {
      if (mounted) await AppErrors.system(context, _c, 'Watchdog error: ${e.toString().replaceAll('Exception: ', '')}');
      return null;
    } finally {
      client?.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _load() async {
    await _withService((svc) async {
      final jq = await svc.isJqInstalled();
      final status = await svc.getWatchdogStatus(widget.slotIndex);
      final cfg = await svc.loadConfig(widget.slotIndex);
      if (!mounted) return;
      setState(() {
        _jqMissing = !jq;
        _status = status;
        _applyConfig(cfg);
      });
    });
    if (_jqMissing && mounted) {
      await AppErrors.system(context, _c, 'jq is not installed on the router; the watchdog cannot be configured.');
    }
  }

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
        title: Text('Overwrite wgc${widget.slotIndex}?', style: const TextStyle(color: kText, fontSize: 15)),
        content:
            const Text('This will set this watchdog to the newly chosen region', style: TextStyle(color: kMuted, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL', style: TextStyle(color: kMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CONTINUE')),
        ],
      ),
    );
    return ok ?? false;
  }

  // Spec 2.1.3: SAVE persists the parameters; ENABLE (in the slot modal) deploys.
  Future<void> _save() async {
    if (_jqMissing) {
      await AppErrors.system(context, _c, 'Cannot save: jq is not installed on the router.');
      return;
    }
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
      await svc.saveWatchdogConfig(cfg, desc: newDesc);
      return true;
    });
    if (saved != true || !mounted) return;
    // Configured a previously-empty slot: remind the user to ENABLE it (matches manage CREATE).
    if (widget.slotIsEmpty && !enabled) {
      await _remindToEnable();
      if (!mounted) return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _remindToEnable() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kSurface,
          title: const Text('Watchdog configured', style: TextStyle(color: kHighlight, fontSize: 15)),
          content: Text('wgc${widget.slotIndex} has been configured. Remember to ENABLE it via the ENABLE button.',
              style: const TextStyle(color: kText, fontSize: 13)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );

  Future<void> _testEmail() async {
    final cfg = _currentConfig().copyWith(emailAlertsEnabled: true);
    final errors = cfg.validate().where((e) => e.toLowerCase().contains('email') || e.toLowerCase().contains('smtp')).toList();
    if (errors.isNotEmpty) {
      await AppErrors.inputs(context, _c, errors);
      return;
    }
    await _withService((svc) => svc.testEmail(_currentConfig()));
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final enabled = status?.isEnabled == true;
    return Dialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: kHighlight, size: 18),
                    const SizedBox(width: 8),
                    Text('WATCHDOG · wgc${widget.slotIndex}',
                        style: const TextStyle(color: kHighlight, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
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
                  const Text('jq is not installed on the router — install Entware jq before enabling.',
                      style: TextStyle(color: kError, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                _field(_intervalCtrl, 'Check interval (minutes)', const Key('wd_interval'), keyboard: TextInputType.number),
                _field(_primaryCtrl, 'Primary ping IP', const Key('wd_primary')),
                _field(_secondaryCtrl, 'Secondary ping IP', const Key('wd_secondary')),
                _field(_piaUserCtrl, 'PIA username', const Key('wd_pia_user')),
                _field(_piaPassCtrl, 'PIA password', const Key('wd_pia_pass'),
                    obscure: !_piaPassVisible,
                    onToggle: () => setState(() => _piaPassVisible = !_piaPassVisible),
                    visible: _piaPassVisible),
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
                  _field(_smtpUserCtrl, 'SMTP username', const Key('wd_smtp_user')),
                  _field(_smtpPassCtrl, 'SMTP password', const Key('wd_smtp_pass'),
                      obscure: !_smtpPassVisible,
                      onToggle: () => setState(() => _smtpPassVisible = !_smtpPassVisible),
                      visible: _smtpPassVisible),
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
                  onPressed: (_loading || _jqMissing) ? null : _save,
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kOnPrimary))
                      : const Text('SAVE'),
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
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    Key key, {
    bool obscure = false,
    TextInputType? keyboard,
    VoidCallback? onToggle,
    bool visible = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        key: key,
        controller: ctrl,
        obscureText: obscure,
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
