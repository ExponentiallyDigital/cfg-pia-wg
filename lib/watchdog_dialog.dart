// watchdog_dialog.dart - UI for configuring, enabling and monitoring the router watchdog.
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

import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';

import 'router_watchdog.dart';

const _kAccent = Color(0xFF00D4AA);
const _kSurface = Color(0xFF1A1D23);
const _kField = Color(0xFF1E2128);
const _kText = Color(0xFFE8EAF0);
const _kMuted = Color(0xFF8892A4);
const _kError = Color(0xFFFF5C5C);

class WatchdogDialog extends StatefulWidget {
  final int slotIndex;
  final String regionDesc; // wgcN_desc (read-only display)
  final String piaUsername, piaPassword; // pre-fill from the main-screen login
  final void Function(String, {bool isError, bool isSuccess}) onLog;
  final VoidCallback? onActivity;
  final Future<SSHClient> Function() connect; // captures router ip/user/pass
  final RouterWatchdog Function(SSHClient)? serviceFactory; // test seam

  const WatchdogDialog({
    super.key,
    required this.slotIndex,
    required this.regionDesc,
    required this.onLog,
    required this.connect,
    this.piaUsername = '',
    this.piaPassword = '',
    this.onActivity,
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
  final _subjectCtrl = TextEditingController(text: 'pia-wireguard-cfga alert');
  final _smtpServerCtrl = TextEditingController();
  final _smtpUserCtrl = TextEditingController();
  final _smtpPassCtrl = TextEditingController();

  bool _emailEnabled = false;
  bool _loading = false;
  bool _jqMissing = false;
  bool _piaPassVisible = false;
  bool _smtpPassVisible = false;
  WatchdogStatus? _status;
  String? _logText;

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
    widget.onActivity?.call();
    setState(() => _loading = true);
    SSHClient? client;
    try {
      client = await widget.connect();
      final svc = (widget.serviceFactory ?? (c) => RouterWatchdog(c, onLog: widget.onLog))(client);
      return await op(svc);
    } catch (e) {
      widget.onLog('Watchdog error: $e', isError: true);
      return null;
    } finally {
      client?.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  // Re-fetch everything from NVRAM each time the dialog opens (spec §5.3).
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
    if (_jqMissing) {
      widget.onLog('jq is not installed on the router; watchdog cannot be configured.', isError: true);
    }
  }

  void _applyConfig(WatchdogConfig c) {
    _intervalCtrl.text = '${c.cronIntervalMinutes}';
    if (c.primaryIp.isNotEmpty) _primaryCtrl.text = c.primaryIp;
    if (c.secondaryIp.isNotEmpty) _secondaryCtrl.text = c.secondaryIp;
    // Prefer the freshly-entered main-screen login; fall back to whatever is in NVRAM.
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

  Future<void> _save() async {
    if (_jqMissing) {
      widget.onLog('Cannot save: jq is not installed on the router.', isError: true);
      return;
    }
    final cfg = _currentConfig();
    final errors = cfg.validate();
    if (errors.isNotEmpty) {
      for (final e in errors) {
        widget.onLog(e, isError: true);
      }
      return;
    }
    await _withService((svc) async {
      final p = await svc.pingHostViaWan(cfg.primaryIp.trim());
      final s = await svc.pingHostViaWan(cfg.secondaryIp.trim());
      if (!p) widget.onLog('Warning: primary IP ${cfg.primaryIp.trim()} is not reachable from the router.', isError: true);
      if (!s) {
        widget.onLog('Warning: secondary IP ${cfg.secondaryIp.trim()} is not reachable from the router.', isError: true);
      }
      await svc.startWatchdog(cfg);
      final status = await svc.getWatchdogStatus(widget.slotIndex);
      if (mounted) setState(() => _status = status);
    });
  }

  Future<void> _disable() async {
    await _withService((svc) async {
      await svc.stopWatchdog(widget.slotIndex);
      final status = await svc.getWatchdogStatus(widget.slotIndex);
      if (mounted) setState(() => _status = status);
    });
  }

  Future<void> _testEmail() async {
    final cfg = _currentConfig().copyWith(emailAlertsEnabled: true);
    final errors = cfg.validate().where((e) => e.toLowerCase().contains('email') || e.toLowerCase().contains('smtp')).toList();
    if (errors.isNotEmpty) {
      for (final e in errors) {
        widget.onLog(e, isError: true);
      }
      return;
    }
    await _withService((svc) => svc.testEmail(_currentConfig()));
  }

  Future<void> _viewLog() async {
    final text = await _withService((svc) => svc.getWatchdogLog(widget.slotIndex));
    if (!mounted) return;
    setState(() => _logText = (text == null || text.isEmpty) ? '(watchdog log is empty)' : text);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final enabled = status?.isEnabled == true;
    return Dialog(
      backgroundColor: _kSurface,
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
                    const Icon(Icons.shield_outlined, color: _kAccent, size: 18),
                    const SizedBox(width: 8),
                    Text('WATCHDOG · wgc${widget.slotIndex}',
                        style: const TextStyle(color: _kAccent, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(widget.regionDesc.isEmpty ? '(no region set)' : widget.regionDesc,
                    style: const TextStyle(color: _kMuted, fontSize: 12)),
                const SizedBox(height: 16),

                // ── Status ─────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _kField, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Icon(enabled ? Icons.check_circle : Icons.cancel, color: enabled ? _kAccent : _kMuted, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(status == null ? 'Loading...' : (enabled ? 'Enabled' : 'Disabled'),
                                style: const TextStyle(color: _kText, fontWeight: FontWeight.bold)),
                            Text(
                              status?.lastSuccessfulPing == null
                                  ? 'Last successful ping: never'
                                  : 'Last successful ping: ${status!.lastSuccessfulPing}',
                              style: const TextStyle(color: _kMuted, fontSize: 12),
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
                      style: TextStyle(color: _kError, fontSize: 12)),
                ],
                const SizedBox(height: 16),

                // ── Configuration ──────────────────────────────────────
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
                  title: const Text('Enable email alerts', style: TextStyle(color: _kText, fontSize: 14)),
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

                // ── Actions ────────────────────────────────────────────
                ElevatedButton(
                  key: const Key('wd_save'),
                  onPressed: (_loading || _jqMissing) ? null : _save,
                  child: _loading
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF12141A)))
                      : const Text('SAVE & ENABLE'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('wd_disable'),
                        onPressed: (_loading || !enabled) ? null : _disable,
                        child: const Text('DISABLE'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('wd_view_log'),
                        onPressed: _loading ? null : _viewLog,
                        child: const Text('VIEW LOG'),
                      ),
                    ),
                  ],
                ),
                if (_logText != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFF12141A), borderRadius: BorderRadius.circular(8)),
                    child: SingleChildScrollView(
                      child: Text(_logText!,
                          key: const Key('wd_log_text'),
                          style: const TextStyle(color: _kText, fontSize: 11, fontFamily: 'monospace')),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('CLOSE', style: TextStyle(color: _kMuted)),
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
        style: const TextStyle(color: _kText, fontFamily: 'monospace', fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _kMuted, fontSize: 13),
          filled: true,
          fillColor: _kField,
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2E3240))),
          suffixIcon: onToggle == null
              ? null
              : GestureDetector(
                  onTap: onToggle,
                  child: Icon(visible ? Icons.visibility_off : Icons.visibility, color: _kMuted, size: 18),
                ),
        ),
      ),
    );
  }
}
