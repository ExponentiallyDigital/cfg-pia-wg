// widgets/slot_modal.dart - Parameterised wgc1-5 slot management modal (spec 2.1.2 / 2.1.3 / 3.2).
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
// One modal serves both router screens (spec 3.2). The button set + actions vary by [mode]:
//   manage   -> CREATE, ENABLE, EDIT, DISABLE, DELETE
//   watchdog -> CREATE/EDIT, DELETE, VIEW ROUTER WATCHDOG LOG
// A short-lived SSH client is opened for each action (so a dropped connection self-heals), the
// slot list is refreshed after every action, and a processing overlay covers the modal while busy.

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../pia_service.dart';
import '../router_slot_service.dart';
import '../router_watchdog.dart';
import '../screens/slot_params_editor.dart';
import '../session_controller.dart';
import '../watchdog_dialog.dart';
import 'common_fields.dart';
import 'error_presenter.dart';
import 'region_picker_sheet.dart';

enum SlotModalMode { manage, watchdog }

class SlotModal extends StatefulWidget {
  final SlotModalMode mode;
  final SessionController controller;
  final Future<SSHClient> Function() connect;
  final RouterSlots initialSlots;
  final PiaService piaService;
  // Test seams.
  final RouterSlotService Function(SSHClient)? slotServiceFactory;
  final RouterWatchdog Function(SSHClient)? watchdogServiceFactory;

  const SlotModal({
    super.key,
    required this.mode,
    required this.controller,
    required this.connect,
    required this.initialSlots,
    required this.piaService,
    this.slotServiceFactory,
    this.watchdogServiceFactory,
  });

  @override
  State<SlotModal> createState() => _SlotModalState();
}

class _SlotModalState extends State<SlotModal> {
  late RouterSlots _slots = widget.initialSlots;
  int _selected = -1;
  bool _processing = false;

  SessionController get _c => widget.controller;
  SlotInfo? get _selectedInfo => _selected == -1 ? null : _slots.slots[_selected];

  RouterSlotService _slotSvc(SSHClient c) => widget.slotServiceFactory?.call(c) ?? RouterSlotService(c, onLog: _c.onLog);
  RouterWatchdog _wdSvc(SSHClient c) => widget.watchdogServiceFactory?.call(c) ?? RouterWatchdog(c, onLog: _c.onLog);

  // ── Connection helpers ──────────────────────────────────────────────────────────
  Future<void> _refresh() async {
    SSHClient? client;
    try {
      client = await widget.connect();
      final s = await _slotSvc(client).fetchSlots();
      if (mounted) setState(() => _slots = s);
    } catch (_) {
      // Non-fatal: keep the previous list.
    } finally {
      client?.close();
    }
  }

  // Runs [op] with a fresh slot service, refreshes the slot list, then (with the processing overlay
  // already cleared) surfaces any error — the spinner must not animate under an awaited modal.
  Future<void> _runSlot(Future<void> Function(RouterSlotService) op) async {
    setState(() => _processing = true);
    SSHClient? client;
    Object? error;
    try {
      client = await widget.connect();
      await op(_slotSvc(client));
    } catch (e) {
      error = e;
    } finally {
      client?.close();
    }
    await _refresh();
    if (mounted) setState(() => _processing = false);
    if (error != null && mounted) await AppErrors.system(context, _c, error.toString().replaceAll('Exception: ', ''));
  }

  // ── Generic dialog helpers ────────────────────────────────────────────────────────
  Future<bool> _confirm(String title, String message, {String confirmLabel = 'CONFIRM', bool destructive = false}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(title, style: const TextStyle(color: kText, fontSize: 15)),
        content: Text(message, style: const TextStyle(color: kMuted, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL', style: TextStyle(color: kMuted))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel, style: TextStyle(color: destructive ? kError : kHighlight, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _info(String title, String message) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kSurface,
          title: Text(title, style: const TextStyle(color: kHighlight, fontSize: 15)),
          content: Text(message, style: const TextStyle(color: kText, fontSize: 13)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );

  // Region picker that returns the chosen id (or null if dismissed).
  Future<String?> _pickRegion() async {
    String? chosen;
    try {
      final regions = await widget.piaService.fetchRegions(onProgress: _c.onLog);
      if (!mounted) return null;
      await RegionPickerSheet.show(context, regions: regions, onSelected: (id) => chosen = id);
    } catch (e) {
      if (mounted) await AppErrors.system(context, _c, 'Failed to load regions: ${e.toString().replaceAll('Exception: ', '')}');
    }
    return chosen;
  }

  // ── Manage-mode actions ──────────────────────────────────────────────────────────
  Future<void> _create() async {
    final slot = _selected;
    final info = _slots.slots[slot]!;
    if (!info.isEmpty) {
      final ok = await _confirm(
          'Overwrite wgc$slot?', 'Slot wgc$slot currently holds "${info.desc}". Creating a new configuration will overwrite it.');
      if (!ok) return;
    }
    final regionId = await _pickRegion();
    if (regionId == null) return;
    final creds = await _piaCredsDialog();
    if (creds == null) return;

    await _runSlot((svc) async {
      _c.logEntry('Generating configuration for $regionId...');
      final config = await widget.piaService
          .generateConfig(region: regionId, username: creds.$1, password: creds.$2, dns: creds.$3, onProgress: _c.onLog);
      await svc.createConfigToSlot(slot: slot, config: config, regionId: regionId);
    });
    if (mounted) await _info('Slot created', 'wgc$slot has been created. Remember to ENABLE it via the ENABLE button.');
  }

  Future<void> _enableManage() async {
    final slot = _selected;

    // 1) Concurrency gate FIRST. It needs no router round trip, so refusing here spares the user
    //    a ping-target prompt for an enable that was never going to happen.
    if (!await _withinVpnLimit(slot)) return;
    if (!mounted) return;

    // 2) Read stored ping targets (brief processing window).
    var primary = '', secondary = '';
    var haveTargets = false;
    setState(() => _processing = true);
    SSHClient? client;
    Object? readError;
    try {
      client = await widget.connect();
      final t = await _slotSvc(client).readWatchdogPingTargets(slot);
      primary = t.$1;
      secondary = t.$2;
      haveTargets = primary.isNotEmpty && secondary.isNotEmpty;
    } catch (e) {
      readError = e;
    } finally {
      client?.close();
    }
    if (mounted) setState(() => _processing = false);
    if (readError != null) {
      if (mounted) await AppErrors.system(context, _c, readError.toString().replaceAll('Exception: ', ''));
      return;
    }

    // 3) Prompt for targets if none are stored (spinner is off while the prompt is open).
    if (!haveTargets) {
      final targets = await _promptPingTargets(primary.isEmpty ? '8.8.8.8' : primary, secondary.isEmpty ? '1.1.1.1' : secondary);
      if (targets == null) return;
      primary = targets.$1;
      secondary = targets.$2;
    }

    // 4) Write targets if prompted, then enable with the connectivity check. Other slots are left
    //    running - they no longer have to be torn down first.
    setState(() => _processing = true);
    client = null;
    Object? error;
    try {
      client = await widget.connect();
      final svc = _slotSvc(client);
      if (!haveTargets) await svc.writeWatchdogPingTargets(slot, primary, secondary);
      await svc.enableSlot(slot, primaryIp: primary, secondaryIp: secondary);
    } catch (e) {
      error = e;
    } finally {
      client?.close();
    }
    await _refresh();
    if (mounted) setState(() => _processing = false);
    if (error != null && mounted) await AppErrors.system(context, _c, error.toString().replaceAll('Exception: ', ''));
  }

  Future<void> _disableManage() {
    final slot = _selected;
    final wdActive = _selectedInfo?.watchdogActive ?? false;
    return _runSlot((svc) async {
      if (wdActive) await _wdSvc(svc.client).stopWatchdog(slot); // disabling also stops its watchdog
      await svc.disableSlot(slot);
    });
  }

  Future<void> _editManage() async {
    final slot = _selected;
    Map<String, String>? params;
    setState(() => _processing = true);
    SSHClient? client;
    Object? error;
    try {
      client = await widget.connect();
      params = await _slotSvc(client).readSlotParams(slot);
    } catch (e) {
      error = e;
    } finally {
      client?.close();
      if (mounted) setState(() => _processing = false);
    }
    if (error != null && mounted) await AppErrors.system(context, _c, error.toString().replaceAll('Exception: ', ''));
    if (params == null || !mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => SlotParamsEditor(
        slot: slot,
        initial: params!,
        desc: _slots.slots[slot]?.desc ?? '',
        onSave: (editable) => _runSlot((svc) => svc.writeSlotParams(slot, editable)),
      ),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _deleteManage() async {
    final slot = _selected;
    final info = _selectedInfo;
    final desc = (info != null && !info.isEmpty) ? ' ("${info.desc}")' : '';
    final wdActive = info?.watchdogActive ?? false;
    final ok = await _confirm('Delete wgc$slot?', 'This clears the wgc$slot$desc configuration on the router.',
        confirmLabel: 'DELETE', destructive: true);
    if (!ok) return;
    await _runSlot((svc) async {
      if (wdActive) await _wdSvc(svc.client).stopWatchdog(slot); // deleting also disables its watchdog
      await svc.deleteSlot(slot);
    });
  }

  // Slots run side by side, but stock caps how many (vpnc_max_conn); Merlin reports no limit.
  // Counted from interfaces that are actually up, since that is what the router's cap applies to.
  // Shared by MANAGE ENABLE and by the watchdog paths, which bring a tunnel up as a side effect.
  Future<bool> _withinVpnLimit(int slot) async {
    final maxActive = _slots.maxActiveSlots;
    final othersUp = _slots.activeSlots.where((i) => i != slot).length;
    if (maxActive == null || othersUp < maxActive) return true;
    await _info(
      'VPN limit reached',
      'Stock ASUS firmware allows at most $maxActive WireGuard VPNs to run at the same time, and '
          '$othersUp ${othersUp == 1 ? 'is' : 'are'} already active. '
          'Disable another slot, then enable wgc$slot.',
    );
    return false;
  }

  // ── Watchdog-mode actions ────────────────────────────────────────────────────────
  // CREATE/EDIT: the dialog both creates (region pick on an empty slot) and updates, and its SAVE
  // deploys via RouterWatchdog.deployWatchdog — there is no separate enable step.
  Future<void> _editWatchdog() async {
    final slot = _selected;
    // Deploying brings the slot's tunnel up, so it counts against the same limit ENABLE does.
    // Checked before the dialog, so the user is not made to fill it in for nothing.
    if (!(_slots.activeSlots.contains(slot)) && !await _withinVpnLimit(slot)) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => WatchdogDialog(
        slotIndex: slot,
        regionDesc: _slots.slots[slot]?.desc ?? '',
        slotIsEmpty: _slots.slots[slot]?.isEmpty ?? true,
        controller: _c,
        piaUsername: _c.piaUsername,
        piaPassword: _c.piaPassword,
        connect: widget.connect,
        piaService: widget.piaService,
        serviceFactory: widget.watchdogServiceFactory,
      ),
    );
    await _refresh();
  }

  // DISABLE: stop supervising, keep the settings. Only the cron entries go, so ENABLE can put
  // the schedule straight back without asking for the configuration again.
  Future<void> _disableWatchdog() async {
    final slot = _selected;
    final ok = await _confirm(
      'Disable watchdog wgc$slot?',
      'Removes its scheduled checks. The settings stay on the router and the VPN keeps running, '
          'just unsupervised - ENABLE puts the schedule back.',
      confirmLabel: 'DISABLE',
    );
    if (!ok) return;
    await _runSlot((svc) => _wdSvc(svc.client).disableWatchdog(slot));
  }

  // ENABLE: re-add the cron entries from the settings already in NVRAM.
  Future<void> _enableWatchdog() async {
    final slot = _selected;
    await _runSlot((svc) => _wdSvc(svc.client).enableWatchdog(slot));
  }

  Future<void> _deleteWatchdog() async {
    final slot = _selected;
    final ok = await _confirm('Delete watchdog wgc$slot?', 'This will also delete and disable the underlying region.',
        confirmLabel: 'DELETE', destructive: true);
    if (!ok) return;
    setState(() => _processing = true);
    SSHClient? client;
    Object? error;
    try {
      client = await widget.connect();
      await _wdSvc(client).stopWatchdog(slot);
      await _slotSvc(client).deleteSlot(slot);
    } catch (e) {
      error = e;
    } finally {
      client?.close();
    }
    await _refresh();
    if (mounted) setState(() => _processing = false);
    if (error != null && mounted) await AppErrors.system(context, _c, error.toString().replaceAll('Exception: ', ''));
  }

  Future<void> _viewWatchdogLog() async {
    final slot = _selected;
    String? log;
    setState(() => _processing = true);
    SSHClient? client;
    Object? error;
    try {
      client = await widget.connect();
      log = await _wdSvc(client).getWatchdogLog(slot);
    } catch (e) {
      error = e;
    } finally {
      client?.close();
      if (mounted) setState(() => _processing = false);
    }
    if (error != null && mounted) await AppErrors.system(context, _c, error.toString().replaceAll('Exception: ', ''));
    if (log == null || !mounted) return;
    final logText = log.isEmpty ? '(watchdog log is empty)' : log;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        actionsAlignment: MainAxisAlignment.spaceBetween,
        title: Text('WATCHDOG LOG · wgc$slot', style: const TextStyle(color: kHighlight, fontSize: 13)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: SelectableText(logText,
                key: const Key('watchdog_log_text'), style: const TextStyle(color: kText, fontSize: 11, fontFamily: 'monospace')),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('watchdog_log_copy'),
            onPressed: () async {
              // Not a secret: copying a log must not arm the 60s auto-clear (it would count down
              // on the conf screen and then wipe the log the user just copied).
              await _c.copyToClipboard(logText, armAutoClear: false);
            },
            child: const Text('COPY'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE')),
        ],
      ),
    );
  }

  // ── Sub-dialogs ─────────────────────────────────────────────────────────────────
  // PIA username/password/DNS form (prefilled from session) for CREATE.
  Future<(String, String, String)?> _piaCredsDialog() async {
    final result = await showDialog<(String, String, String)?>(
      context: context,
      builder: (ctx) => _PiaCredsDialog(
        initialUsername: _c.piaUsername,
        initialPassword: _c.piaPassword,
        initialDns: _c.dns,
      ),
    );
    if (result != null) {
      _c.piaUsername = result.$1;
      _c.piaPassword = result.$2;
      _c.dns = result.$3;
      return result;
    }
    return null;
  }

  // Editable primary/secondary ping targets for the manage ENABLE check.
  Future<(String, String)?> _promptPingTargets(String primary, String secondary) async {
    return await showDialog<(String, String)?>(
      context: context,
      builder: (ctx) => _PingTargetsDialog(primary: primary, secondary: secondary),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 1,
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.mode == SlotModalMode.manage ? 'WIREGUARD CONFIGURATION' : 'WATCHDOG CONFIGURATION',
                        style: const TextStyle(color: kHighlight, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                    const SizedBox(height: 16),
                    _slotList(),
                    const SizedBox(height: 20),
                    ..._buttons(),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        // HOME returns to the main menu (closes the modal + intermediate screens).
                        onPressed:
                            _processing ? null : () => Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst),
                        child: const Text('HOME', style: TextStyle(color: kHighlight)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_processing)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0x99000000),
                  child: const Center(child: CircularProgressIndicator(color: kHighlight)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _slotList() {
    return Container(
      decoration: BoxDecoration(color: kField, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
      child: Column(
        children: _slots.slots.entries.map((entry) {
          final slotNum = entry.key;
          final info = entry.value;
          final desc = info.isEmpty ? '<empty slot>' : info.desc;
          final isActive = _slots.activeSlots.contains(slotNum);
          final badgeLabel = isActive ? '● ACTIVE' : null;
          return InkWell(
            key: Key('slot_row_$slotNum'),
            onTap: _processing ? null : () => setState(() => _selected = slotNum),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  Icon(_selected == slotNum ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: kHighlight, size: 20),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('wgc$slotNum',
                            style: const TextStyle(color: kHighlight, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                        // configured region for this slot appears in white
                        Text(
                          desc,
                          style: TextStyle(
                            color: info.isEmpty ? kMuted : Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        // A watchdog whose schedule has been removed still has its settings on
                        // the router, so it gets a badge of its own rather than disappearing.
                        if (isActive || info.killSwitch || info.watchdogActive || (info.watchdogConfigured && !info.isEmpty)) ...[
                          const SizedBox(height: 5),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            if (badgeLabel != null)
                              const SlotBadge(label: '● ACTIVE', text: kHighlight, border: kHighlight, bg: Color(0xFF0F3D2E)),
                            if (info.killSwitch)
                              const SlotBadge(label: '⚑ KILL SWITCH', text: kWarn, border: kWarn, bg: Color(0xFF2A1F0E)),
                            if (info.watchdogActive)
                              const SlotBadge(
                                  label: '◆ WATCHDOG ACTIVE', text: kHighlight, border: kHighlight, bg: Color(0xFF0F2E3D)),
                            // Shown next to WATCHDOG ACTIVE when the watchdog will send email alerts.
                            if (info.watchdogActive && info.emailAlerting)
                              const SlotBadge(
                                  label: '✉ EMAIL ALERTING', text: kHighlight, border: kHighlight, bg: Color(0xFF0F2E3D)),
                            // Configured but unscheduled: DISABLE keeps the settings, so ENABLE can
                            // put the schedule straight back. Muted, not teal - nothing is running.
                            if (info.watchdogConfigured && !info.watchdogActive && !info.isEmpty)
                              const SlotBadge(label: '⏸ WATCHDOG PAUSED', text: kMuted, border: kMuted, bg: Color(0xFF1F242D)),
                          ]),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buttons() {
    final info = _selectedInfo;
    final hasDesc = info != null && !info.isEmpty;
    final enabled = info?.enabled ?? false;
    final wdActive = info?.watchdogActive ?? false;
    // There is something to stop if the flag says so OR the interface is up. The two can disagree,
    // and gating on the flag alone would strand a user with a running tunnel and a greyed DISABLE.
    final stoppable = enabled || (info != null && _slots.activeSlots.contains(info.index));

    Widget btn(String key, String label, VoidCallback? onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(key: Key(key), onPressed: _processing ? null : onTap, child: Text(label)),
          ),
        );

    if (widget.mode == SlotModalMode.manage) {
      return [
        btn('slot_create', 'CREATE', info == null ? null : _create),
        // ENABLE is greyed when the slot is already active (only one interface active at a time).
        btn('slot_enable', 'ENABLE', (hasDesc && !enabled) ? _enableManage : null),
        btn('slot_edit', 'EDIT', hasDesc ? _editManage : null),
        // Greyed once the slot is down - nothing left to stop.
        btn('slot_disable', 'DISABLE', (hasDesc && stoppable) ? _disableManage : null),
        btn('slot_delete', 'DELETE', hasDesc ? _deleteManage : null),
      ];
    }
    // Watchdog mode: CREATE/EDIT creates-or-updates and deploys, so it is live for an empty slot
    // too; DELETE and VIEW LOG still require a non-empty slot (spec round-2).
    //
    // ENABLE / DISABLE act on the SCHEDULE, not the tunnel: DISABLE drops the cron entries and
    // keeps the settings, so ENABLE only lights up for a slot that has settings but no schedule.
    final wdConfigured = info?.watchdogConfigured ?? false;
    return [
      btn('slot_edit', 'CREATE/EDIT', info != null ? _editWatchdog : null),
      btn('slot_wd_enable', 'ENABLE', (hasDesc && wdConfigured && !wdActive) ? _enableWatchdog : null),
      btn('slot_wd_disable', 'DISABLE', (hasDesc && wdActive) ? _disableWatchdog : null),
      btn('slot_delete', 'DELETE', hasDesc ? _deleteWatchdog : null),
      // Configured is enough: /tmp/watchdog_wgcN.log outlives the schedule, and the log of the
      // run that prompted a DISABLE is exactly what you want to read afterwards.
      btn('slot_view_log', 'VIEW ROUTER WATCHDOG LOG', (hasDesc && (wdActive || wdConfigured)) ? _viewWatchdogLog : null),
    ];
  }
}

class _PiaCredsDialog extends StatefulWidget {
  final String initialUsername;
  final String initialPassword;
  final String initialDns;

  const _PiaCredsDialog({
    required this.initialUsername,
    required this.initialPassword,
    required this.initialDns,
  });

  @override
  State<_PiaCredsDialog> createState() => _PiaCredsDialogState();
}

class _PiaCredsDialogState extends State<_PiaCredsDialog> {
  late final TextEditingController _userCtrl = TextEditingController(text: widget.initialUsername);
  late final TextEditingController _passCtrl = TextEditingController(text: widget.initialPassword);
  late final TextEditingController _dnsCtrl = TextEditingController(text: widget.initialDns);
  bool _visible = false;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _dnsCtrl.dispose();
    super.dispose();
  }

  void _onContinue() {
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text.trim();
    final dns = _dnsCtrl.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'PIA username and password are required.');
      return;
    }
    Navigator.of(context).pop((username, password, dns));
  }

  @override
  Widget build(BuildContext context) {
    // A Dialog with its own scroll view rather than an AlertDialog: an AlertDialog puts its content
    // in a Flexible, and inside the app chrome - where the Scaffold has already taken the
    // keyboard's height off the body - that Flexible collapses to zero and the fields spill out of
    // the card. Same structure as SlotParamsEditor, which lays out correctly there.
    return _FormDialog(
      title: 'PIA credentials',
      fields: [
        PiaUsernameField(controller: _userCtrl),
        const SizedBox(height: 10),
        PiaPasswordField(controller: _passCtrl, visible: _visible, onToggle: () => setState(() => _visible = !_visible)),
        const SizedBox(height: 10),
        DnsField(controller: _dnsCtrl),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: kError, fontSize: 12)),
        ],
      ],
      confirmLabel: 'CONTINUE',
      onConfirm: _onContinue,
    );
  }
}

class _PingTargetsDialog extends StatefulWidget {
  final String primary;
  final String secondary;

  const _PingTargetsDialog({required this.primary, required this.secondary});

  @override
  State<_PingTargetsDialog> createState() => _PingTargetsDialogState();
}

class _PingTargetsDialogState extends State<_PingTargetsDialog> {
  late final TextEditingController _primaryCtrl = TextEditingController(text: widget.primary);
  late final TextEditingController _secondaryCtrl = TextEditingController(text: widget.secondary);

  @override
  void dispose() {
    _primaryCtrl.dispose();
    _secondaryCtrl.dispose();
    super.dispose();
  }

  void _onEnable() {
    Navigator.of(context).pop((_primaryCtrl.text.trim(), _secondaryCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return _FormDialog(
      title: 'Connectivity check targets',
      fields: [
        TextField(
            key: const Key('enable_primary_ip'),
            controller: _primaryCtrl,
            style: const TextStyle(color: kText, fontFamily: 'monospace'),
            decoration: const InputDecoration(labelText: 'Primary ping IP')),
        const SizedBox(height: 10),
        TextField(
            key: const Key('enable_secondary_ip'),
            controller: _secondaryCtrl,
            style: const TextStyle(color: kText, fontFamily: 'monospace'),
            decoration: const InputDecoration(labelText: 'Secondary ping IP')),
      ],
      confirmLabel: 'ENABLE',
      onConfirm: _onEnable,
    );
  }
}

/// A dialog holding a form, laid out so the on-screen keyboard cannot squash it.
///
/// Deliberately NOT an `AlertDialog`: that puts its content in a `Flexible`, and inside the app
/// chrome - where the Scaffold has already taken the keyboard's height off the body - the Flexible
/// collapses to zero height and the fields spill out of the card, leaving only the buttons visible.
/// This is the structure `SlotParamsEditor` uses, which lays out correctly in both places.
class _FormDialog extends StatelessWidget {
  final String title;
  final List<Widget> fields;
  final String confirmLabel;
  final VoidCallback onConfirm;
  const _FormDialog({required this.title, required this.fields, required this.confirmLabel, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
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
                Text(title, style: const TextStyle(color: kHighlight, fontSize: 14)),
                const SizedBox(height: 16),
                ...fields,
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('CANCEL', style: TextStyle(color: kMuted))),
                    TextButton(onPressed: onConfirm, child: Text(confirmLabel)),
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
