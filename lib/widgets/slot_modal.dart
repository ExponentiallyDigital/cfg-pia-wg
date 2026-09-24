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
// Every action runs on the session's shared SSH connection (router_session.dart) - it is never
// closed here; that would pull it out from under the next action. The slot list is refreshed after
// every action, and a processing overlay covers the modal while busy.

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import 'app_button.dart';

import '../app_colors.dart';
import '../device_assignment.dart' show joinNames;
import '../firmware.dart';
import '../pia_service.dart';
import '../router_log_paging.dart' show readsAsError;
import '../router_slot_service.dart';
import '../router_watchdog.dart';
import '../screens/slot_params_editor.dart';
import '../session_controller.dart';
import '../watchdog_dialog.dart';
import 'app_scaffold.dart';
import 'common_fields.dart';
import 'error_presenter.dart';
import 'log_buttons.dart';
import 'paywall.dart';
import 'region_picker_sheet.dart';

/// Shown in the DIALOG when an ENABLE fails, and deliberately not written to the app log: an
/// explanation that helps at the moment of failure is noise in a log read later, and the log
/// already carries the error itself. Nearly every failed enable is this.
const String kStaleConfigHint = "PIA configurations expire on PIA's own rotation interval, so one that was created and then left "
    'unused can go stale.';

/// True for the enable failures that mean "this configuration is no longer registered with PIA",
/// which is the one failure the app can fix from here by building the slot again (ID-094).
///
/// Matched on the three messages `enableSlot` raises for a tunnel that would not carry traffic -
/// the interface never came up, it came up with no handshake, or nothing answered through it -
/// rather than on a type, so a rewording has to come here too. A write that failed, a missing
/// binary or a refused service call is a different kind of problem and keeps the plain dialog.
bool looksLikeStaleConfig(String message) =>
    message.contains('did not come up') || message.contains('never answered it') || message.contains('Connectivity check failed');

enum SlotModalMode { manage, watchdog }

/// What DISABLE's confirmation says about the devices pinned to the slot: [names] when they could be
/// read, null when they could not, and nothing at all when there are none.
String? pinnedDeviceWarning(List<String>? names) {
  const until = 'will have no internet until you ENABLE this VPN again or move';
  if (names == null) return 'Any device pinned to this VPN $until it to another VPN in DEVICE ASSIGNMENT.';
  if (names.isEmpty) return null;
  final one = names.length == 1;
  return '${joinNames(names)} ${one ? 'is' : 'are'} pinned to this VPN, and $until ${one ? 'it' : 'them'} '
      'to another VPN in DEVICE ASSIGNMENT.';
}

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
    try {
      final client = await widget.connect();
      final s = await _slotSvc(client).fetchSlots();
      if (mounted) setState(() => _slots = s);
    } catch (_) {
      // Non-fatal: keep the previous list.
    }
  }

  // Runs [op] with a new slot service over the shared connection, refreshes the slot list, then
  // (with the processing overlay already cleared) surfaces any error — the spinner must not
  // animate under an awaited modal.
  /// Returns true when [op] completed. The caller needs to know: this reports the error itself,
  /// so a caller that went on to announce success was announcing it after a failure.
  Future<bool> _runSlot(Future<void> Function(RouterSlotService) op) async {
    setState(() => _processing = true);
    Object? error;
    try {
      final client = await widget.connect();
      await op(_slotSvc(client));
    } catch (e) {
      error = e;
    }
    await _refresh();
    if (mounted) setState(() => _processing = false);
    if (error != null && mounted) await AppErrors.system(context, _c, error.toString().replaceAll('Exception: ', ''));
    return error == null;
  }

  // ── Generic dialog helpers ────────────────────────────────────────────────────────
  Future<bool> _confirm(String title,
      {String? message, String? warning, String confirmLabel = 'CONFIRM', bool destructive = false}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(title, style: const TextStyle(color: kText, fontSize: 15)),
        // A question that already names the slot and its region needs no explanatory body. A
        // [warning] is what the action does to something other than the slot, so it stands apart.
        content: message == null && warning == null
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message != null) Text(message, style: const TextStyle(color: kMuted, fontSize: 13)),
                  if (message != null && warning != null) const SizedBox(height: 10),
                  if (warning != null)
                    Text(warning, key: const Key('confirm_warning'), style: const TextStyle(color: kWarn, fontSize: 13)),
                ],
              ),
        actions: [
          AppButton(label: 'CANCEL', role: ButtonRole.dismiss, onPressed: () => Navigator.pop(ctx, false)),
          AppButton(
            label: confirmLabel,
            role: destructive ? ButtonRole.destructive : ButtonRole.action,
            onPressed: () => Navigator.pop(ctx, true),
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
          actions: [AppButton(label: 'OK', onPressed: () => Navigator.pop(ctx))],
        ),
      );

  // Region picker that returns the chosen id (or null if dismissed).
  /// Returns the region RECORD, not just its id. `generateConfig` would otherwise fetch the server
  /// list a second time and resolve the id against that - and a region with no WireGuard servers in
  /// the second snapshot is dropped, which failed a CREATE on a region the picker had just offered.
  Future<Region?> _pickRegion() async {
    Region? chosen;
    try {
      final regions = await widget.piaService.fetchRegions(onProgress: _c.onLog);
      if (!mounted) return null;
      await RegionPickerSheet.show(context, regions: regions, onSelected: (id) => chosen = regions.firstWhere((r) => r.id == id));
    } catch (e) {
      if (mounted) await AppErrors.system(context, _c, 'Failed to load regions: ${e.toString().replaceAll('Exception: ', '')}');
    }
    return chosen;
  }

  // ── Manage-mode actions ──────────────────────────────────────────────────────────
  Future<void> _create() async {
    final slot = _selected;
    final info = _slots.slots[slot]!;
    // The service stops a running tunnel before it writes (createConfigToSlot); say so up front.
    final running = info.enabled || _slots.activeSlots.contains(slot);
    if (!info.isEmpty) {
      // The title names what is being overwritten - wgcN:region - so the body does not have to
      // say it a second time (ID-113). The same shape the watchdog and the delete prompts use.
      final ok = await _confirm('Overwrite ${slotLabel(slot, info.desc)}?',
          message: 'Creating a new configuration will overwrite this slot.'
              '${running ? '\n\nIts tunnel is running, so it will be stopped first. The new configuration stays disabled '
                  'until you ENABLE it.' : ''}'
              // The profile survives an overwrite, so its index 6 does too, and so does every pin
              // naming it. Those devices follow the new region without being asked.
              '${isStockFirmware ? '\n\nAny device assigned to this slot stays assigned, and will use the new region'
                  '${running ? ' once the slot is enabled. Until then it uses the default connection.' : '.'}' : ''}');
      if (!ok) return;
    }
    final region = await _pickRegion();
    if (region == null) return;
    final regionId = region.id;
    final creds = await _piaCredsDialog();
    if (creds == null) return;

    var stopped = false;
    final created = await _runSlot((svc) async {
      _c.logEntry('Generating configuration for $regionId...');
      final config = await widget.piaService.generateConfig(
          region: regionId, selected: region, username: creds.$1, password: creds.$2, dns: creds.$3, onProgress: _c.onLog);
      stopped = await svc.createConfigToSlot(slot: slot, config: config, regionId: regionId);
    });
    // Only on success. This used to fire whatever happened, so a failed generate was followed by
    // "wgc5 has been created" over the top of the error saying it had not been.
    if (created && mounted) {
      await _info(
          'Slot created',
          stopped
              ? 'wgc$slot has been created. Its old tunnel was stopped, so the slot is disabled. Remember to ENABLE it via '
                  'the ENABLE button.'
              : 'wgc$slot has been created. Remember to ENABLE it via the ENABLE button.');
    }
  }

  Future<void> _enableManage() async {
    final slot = _selected;
    // Settings but no schedule is the paused state DISABLE leaves behind, so ENABLE puts the
    // schedule back with the tunnel (ID-095). A slot with no watchdog settings has nothing to
    // resume, and neither has one whose watchdog is already scheduled.
    final resumeWatchdog = (_selectedInfo?.watchdogConfigured ?? false) && !(_selectedInfo?.watchdogActive ?? false);

    // 1) Concurrency gate FIRST. It needs no router round trip, so refusing here spares the user
    //    a ping-target prompt for an enable that was never going to happen.
    if (!await _withinVpnLimit(slot)) return;
    if (!mounted) return;

    // 2) Read stored ping targets (brief processing window).
    var primary = '', secondary = '';
    var haveTargets = false;
    setState(() => _processing = true);
    Object? readError;
    try {
      final client = await widget.connect();
      final t = await _slotSvc(client).readWatchdogPingTargets(slot);
      primary = t.$1;
      secondary = t.$2;
      haveTargets = primary.isNotEmpty && secondary.isNotEmpty;
    } catch (e) {
      readError = e;
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
    Object? error;
    try {
      final client = await widget.connect();
      final svc = _slotSvc(client);
      if (!haveTargets) await svc.writeWatchdogPingTargets(slot, primary, secondary);
      await svc.enableSlot(slot, primaryIp: primary, secondaryIp: secondary);
      // After the tunnel is up: a schedule put back on a tunnel that failed its check would start
      // by rebuilding what the app has just reverted.
      if (resumeWatchdog) await _wdSvc(client).enableWatchdog(slot);
    } catch (e) {
      error = e;
    }
    await _refresh();
    if (mounted) setState(() => _processing = false);
    if (error != null && mounted) {
      final message = error.toString().replaceAll('Exception: ', '');
      // A tunnel that came up and was never answered, or one that never came up at all, is almost
      // always a PIA registration that has gone stale - and rebuilding it is the fix. Offer it here
      // rather than describing it and leaving the user to work out which button that is (ID-094).
      if (looksLikeStaleConfig(message)) {
        final rebuild = await AppErrors.systemWithAction(context, _c, message, actionLabel: 'RECREATE', detail: kStaleConfigHint);
        if (rebuild && mounted) await _create();
        return;
      }
      await AppErrors.system(context, _c, message, detail: kStaleConfigHint);
    }
  }

  // Asks first, as DELETE does and as the watchdog screen's DISABLE does. It used to take a tunnel down,
  // and any watchdog running on it, on a single tap - the one action in either set that did not ask.
  Future<void> _disableManage() async {
    final slot = _selected;
    final info = _selectedInfo;
    final wdActive = info?.watchdogActive ?? false;
    // Named before asking, because this is the one effect of a DISABLE on something other than the
    // slot: a device pinned here keeps no internet at all while it is off (ID-213).
    List<String>? pinned = const [];
    if (isStockFirmware) {
      try {
        pinned = await _slotSvc(await widget.connect()).pinnedDeviceNames(slot);
      } catch (_) {
        pinned = null;
      }
    }
    final ok = await _confirm(
      'Disable VPN ${slotLabel(slot, info?.desc ?? '')}?',
      message: wdActive
          ? 'Takes the tunnel down and PAUSES its watchdog - a watchdog left running would rebuild the '
              'tunnel you just stopped. The script and both sets of settings stay on the router, so ENABLE '
              'brings the tunnel and the watchdog back together.'
          : 'Takes the tunnel down. The settings stay on the router, so ENABLE brings it back.',
      warning: pinnedDeviceWarning(pinned),
      confirmLabel: 'DISABLE',
    );
    if (!ok) return;
    var wentDown = true;
    await _runSlot((svc) async {
      // PAUSE, not remove (ID-095). `stopWatchdog` tears down the schedule, the script and the
      // settings, which is DELETE's job - and on the last watchdog it takes the PIA credentials
      // with it, leaving nothing for an ENABLE to restore.
      if (wdActive) await _wdSvc(svc.client).disableWatchdog(slot);
      wentDown = await svc.disableSlot(slot);
    });
    // The router took the setting and the interface stayed up, so the refresh behind this dialog
    // badges the slot as still running. Saying nothing would leave that reading as a tap that did
    // not work, rather than as what it is (ID-124).
    if (!wentDown && mounted) {
      await AppErrors.system(
        context,
        _c,
        'wgc$slot was disabled, but its tunnel is still up on the router.',
        detail: "The router accepted the change - its own web interface will show the profile "
            'disconnected - but the interface has not gone. Reboot the router if it stays this way; '
            'the app log has every command that was run.',
      );
    }
  }

  Future<void> _editManage() async {
    final slot = _selected;
    Map<String, String>? params;
    setState(() => _processing = true);
    Object? error;
    try {
      final client = await widget.connect();
      params = await _slotSvc(client).readSlotParams(slot);
    } catch (e) {
      error = e;
    } finally {
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
        routerDotServers: _slots.routerDotServers,
        onSave: (editable) async {
          // A running tunnel keeps its old settings until it is restarted, which MAN-11 found the hard
          // way on 2026-09-19. So SAVE restarts it, and says so first (ID-203).
          final running = _slots.activeSlots.contains(slot);
          if (running &&
              !await _confirm(
                'Save and restart ${slotLabel(slot, _slots.slots[slot]?.desc ?? '')}?',
                message: 'Saving restarts wgc$slot. Anything using it drops for a few seconds.',
                confirmLabel: 'SAVE',
              )) {
            return false;
          }
          if (!await _runSlot((svc) => svc.writeSlotParams(slot, editable))) return false;
          // Saved either way from here: a restart that fails is reported, and the editor closes.
          if (running) await _runSlot((svc) => svc.restartSlot(slot));
          return true;
        },
      ),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _deleteManage() async {
    final slot = _selected;
    final info = _selectedInfo;
    final wdActive = info?.watchdogActive ?? false;
    // Names both, because it removes both: the watchdog's script, schedule and settings go with
    // the slot, and neither comes back from an ENABLE afterwards (ID-095).
    final hasWatchdog = wdActive || (info?.watchdogConfigured ?? false);
    final ok = await _confirm(
      'Delete VPN ${slotLabel(slot, info?.desc ?? '')}?',
      message: hasWatchdog
          ? 'Removes the VPN and its watchdog: the schedule, the script on the router and the watchdog '
              'settings. Nothing is left to ENABLE afterwards.'
          : 'Removes the VPN configuration from the router.',
      confirmLabel: 'DELETE',
      destructive: true,
    );
    if (!ok) return;
    await _runSlot((svc) async {
      // stopWatchdog, not disableWatchdog: DELETE is the path that takes the script and the
      // settings away too. Run for a PAUSED watchdog as well, or MANAGE DELETE leaves the script
      // and the SMTP password on the router (ID-066).
      if (hasWatchdog) await _wdSvc(svc.client).stopWatchdog(slot);
      await svc.deleteSlot(slot);
    });
  }

  // Slots run side by side, but stock caps how many (vpnc_max_conn); Merlin reports no limit.
  // Counted from interfaces that are actually up, since that is what the router's cap applies to.
  // Shared by MANAGE ENABLE and by the watchdog paths, which bring a tunnel up as a side effect.
  Future<bool> _withinVpnLimit(int slot) async {
    var maxActive = _slots.maxActiveSlots;
    // Read again now, not taken from when the list was loaded: SETTINGS changes it, and coming back
    // from there kept the old limit until the screen was left and entered again (ID-147).
    if (maxActive != null) {
      try {
        maxActive = await _slotSvc(await widget.connect()).readMaxActiveVpns();
      } catch (_) {
        // keep the value from the last read
      }
    }
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
    // Pushed as a page for the same reason the slot list is (418), and with more at stake: it is a
    // long form, and as a card its height was wrong twice over, leaving SAVE and its spinner below
    // a fold that would not scroll. The route name matches the screen underneath so the drawer
    // keeps highlighting WATCHDOG.
    await Navigator.of(context).push<void>(MaterialPageRoute(
      settings: RouteSettings(name: AppDestination.watchdog.routeName),
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
        routerDotServers: _slots.routerDotServers,
      ),
    ));
    await _refresh();
  }

  // DISABLE: stop supervising, keep the settings. Only the cron entries go, so ENABLE can put
  // the schedule straight back without asking for the configuration again.
  Future<void> _disableWatchdog() async {
    final slot = _selected;
    final ok = await _confirm(
      'Disable watchdog wgc$slot?',
      message: 'Removes its scheduled checks. The settings stay on the router and the VPN keeps running, '
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
    // "and VPN": DELETE here tears down the underlying slot too, which the old wording buried.
    final ok = await _confirm('Delete watchdog and VPN ${slotLabel(slot, _selectedInfo?.desc ?? '')}?',
        confirmLabel: 'DELETE', destructive: true);
    if (!ok) return;
    setState(() => _processing = true);
    Object? error;
    try {
      final client = await widget.connect();
      await _wdSvc(client).stopWatchdog(slot);
      await _slotSvc(client).deleteSlot(slot);
    } catch (e) {
      error = e;
    }
    await _refresh();
    if (mounted) setState(() => _processing = false);
    if (error != null && mounted) await AppErrors.system(context, _c, error.toString().replaceAll('Exception: ', ''));
  }

  Future<void> _viewWatchdogLog() async {
    final slot = _selected;
    String? log;
    setState(() => _processing = true);
    Object? error;
    try {
      final client = await widget.connect();
      log = await _wdSvc(client).getWatchdogLog(slot);
    } catch (e) {
      error = e;
    } finally {
      if (mounted) setState(() => _processing = false);
    }
    if (error != null && mounted) await AppErrors.system(context, _c, error.toString().replaceAll('Exception: ', ''));
    if (log == null || !mounted) return;
    final logText = log.isEmpty ? '(watchdog log is empty)' : log;
    // A PAGE, not a dialog. Reported 2026-09-10: selecting the whole log put Android's own
    // "Copy / Share" toolbar directly over the action row at the bottom of the card, and a tap
    // meant for Copy landed on CLEAR. A full screen gives the text room to be selected without
    // the selection's toolbar and the app's buttons competing for the same 48 pixels.
    await Navigator.of(context).push<void>(MaterialPageRoute(
      settings: RouteSettings(name: AppDestination.watchdog.routeName),
      builder: (ctx) => _WatchdogLogScreen(
        slot: slot,
        desc: _slots.slots[slot]?.desc ?? '',
        text: logText,
        // Not a secret: copying a log must not arm the 60s auto-clear, which would count down on
        // the config screen and then wipe the log the user has just copied.
        onCopy: () => _c.copyToClipboard(logText, armAutoClear: false),
        onClear: () => _clearWatchdogLog(slot),
      ),
    ));
  }

  Future<void> _clearWatchdogLog(int slot) async {
    setState(() => _processing = true);
    Object? error;
    try {
      await _wdSvc(await widget.connect()).clearWatchdogLog(slot);
    } catch (e) {
      error = e;
    } finally {
      if (mounted) setState(() => _processing = false);
    }
    if (error != null && mounted) {
      await AppErrors.system(context, _c, error.toString().replaceAll('Exception: ', ''));
    } else {
      _c.logEntry('Watchdog log cleared for wgc$slot.', isSuccess: true);
    }
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
        routerDotServers: _slots.routerDotServers,
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
    // A full screen, not a dialog. Until 418 this was a `Dialog` sitting on top of the connect
    // form it had finished with - a modal says "this is a detour, you will come back", and MANAGE
    // and WATCHDOG are destinations. It also cost the whole viewport: the slot list, the buttons
    // and the spinner shared a card while a spent form filled the space behind it.
    //
    // AppScaffold is what every other destination uses, which is also the fix for the HOME button
    // being inconsistent here - it now sits pinned at the bottom, full width, outside the scroll
    // view, exactly as it does on the device assignment screen.
    return Stack(
      children: [
        AppScaffold(
          // 480 is the width the card had. Full width leaves a slot row stranded at the far left of
          // a tablet line; a phone is narrower than the cap, so nothing changes there.
          maxContentWidth: kFormMaxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The heading carries the colour of the menu item that opened this screen (ID-112).
              ScreenHeading(
                widget.mode == SlotModalMode.manage ? 'MANAGE CONFIGURATION' : 'WATCHDOG CONFIGURATION',
                colour: destinationColour(
                    widget.mode == SlotModalMode.manage ? AppDestination.manageRouter : AppDestination.watchdog),
              ),
              const SizedBox(height: 16),
              _slotList(),
              const SizedBox(height: 20),
              ..._buttons(),
            ],
          ),
        ),
        // Covers the HOME button too, which the old overlay did not - it was inside the card.
        if (_processing)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x99000000),
              child: Center(child: CircularProgressIndicator(color: kHighlight)),
            ),
          ),
      ],
    );
  }

  Widget _slotList() {
    return Container(
      decoration: BoxDecoration(color: kField, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
      child: Column(
        // Highest slot first, wgc5 down to wgc1 (ID-101). Display order only - nothing reads the
        // list's order. It matches the router's own web interface, which creates wgc5 first, and
        // the advice to make the highest slot the one carrying the router's own DNS: among slots
        // sharing a DNS address the lowest routing table wins, and that is the highest slot.
        children: (_slots.slots.entries.toList()..sort((a, b) => b.key.compareTo(a.key))).map((entry) {
          final slotNum = entry.key;
          final info = entry.value;
          final desc = info.isEmpty ? '<empty slot>' : info.desc;
          // Up AND answered recently is ACTIVE; up with nothing coming back gets said out loud
          // rather than badged the same way (ID-123). An expired PIA registration looks exactly
          // like a healthy tunnel from the link flag alone.
          final isActive = _slots.activeSlots.contains(slotNum);
          final isAnswering = _slots.answeringSlots.contains(slotNum);
          final badgeLabel = !isActive
              ? null
              : isAnswering
                  ? '● ACTIVE'
                  : '● UP, NO ANSWER';
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
                        // One line, `wgc1:pia-region_name`, the way every log line and dialog names a slot (ID-035).
                        // The slot stays teal and the region white; an empty slot says so in grey.
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: 'wgc$slotNum',
                              style: const TextStyle(color: kHighlight, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                            ),
                            info.isEmpty
                                ? TextSpan(text: ' $desc', style: const TextStyle(color: kMuted, fontSize: 12))
                                : TextSpan(text: ':${desc.trim()}', style: const TextStyle(color: Colors.white)),
                          ]),
                        ),
                        // A watchdog whose schedule has been removed still has its settings on
                        // the router, so it gets a badge of its own rather than disappearing.
                        if (isActive || info.killSwitch || info.watchdogActive || (info.watchdogConfigured && !info.isEmpty)) ...[
                          const SizedBox(height: 5),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            if (badgeLabel != null)
                              // Amber for "up, no answer": it is not a healthy tunnel and it is not
                              // a stopped one either, and calling it ACTIVE was the old lie (ID-123).
                              SlotBadge(
                                label: badgeLabel,
                                text: isAnswering ? kHighlight : kWarn,
                                border: isAnswering ? kHighlight : kWarn,
                                bg: isAnswering ? const Color(0xFF0F3D2E) : const Color(0xFF2A1F0E),
                              ),
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

    // Gated is CREATE or CHANGE; free is REMOVE. A locked user can always undo, never build.
    //
    // An action that is ALREADY null stays null: it is greyed for a reason of its own - nothing to
    // stop, no slot selected - and turning that into a sales pitch would be answering a question
    // the user did not ask. The paywall is only ever the answer to a deliberate tap.
    VoidCallback? gated(String pitch, VoidCallback? action) {
      if (action == null || _c.isUnlocked) return action;
      return () async {
        if (await Paywall.show(context, _c, pitch: pitch) && mounted) action();
      };
    }

    Widget btn(String key, String label, VoidCallback? onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            // DELETE is the one destructive action in either set; everything else here does something.
            // The verb's colour comes from the shared map (ID-118); a disabled button ignores it.
            child: AppButton(
              keyValue: key,
              label: label,
              role: key == 'slot_delete' ? ButtonRole.destructive : ButtonRole.action,
              colour: slotActionColour(label),
              onPressed: _processing ? null : onTap,
            ),
          ),
        );

    if (widget.mode == SlotModalMode.manage) {
      return [
        btn('slot_create', 'CREATE', gated(Pitch.create, info == null ? null : _create)),
        // ENABLE is greyed when the slot is already active (only one interface active at a time).
        btn('slot_enable', 'ENABLE', gated(Pitch.enable, (hasDesc && !enabled) ? _enableManage : null)),
        btn('slot_edit', 'EDIT', gated(Pitch.edit, hasDesc ? _editManage : null)),
        // DISABLE and DELETE are free even without the entitlement. Greyed once the slot is down -
        // nothing left to stop.
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
      btn('slot_edit', 'CREATE/EDIT', gated(Pitch.watchdog, info != null ? _editWatchdog : null)),
      btn('slot_wd_enable', 'ENABLE',
          gated(Pitch.watchdogEnable, (hasDesc && wdConfigured && !wdActive) ? _enableWatchdog : null)),
      // Stopping and removing stay free: never trap a script on someone's router behind a purchase.
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

  /// The router's own encrypted-DNS servers, so the DNS field can say when the two overlap (ID-005).
  final Set<String> routerDotServers;

  const _PiaCredsDialog({
    required this.initialUsername,
    required this.initialPassword,
    required this.initialDns,
    this.routerDotServers = const {},
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
        AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PiaUsernameField(controller: _userCtrl),
              const SizedBox(height: 10),
              PiaPasswordField(controller: _passCtrl, visible: _visible, onToggle: () => setState(() => _visible = !_visible)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // These servers become the slot's, and stock sends an assigned device to the first one only.
        DnsField(controller: _dnsCtrl, firstServerNote: isStockFirmware, routerDotServers: widget.routerDotServers),
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
                    AppButton(label: 'CANCEL', role: ButtonRole.dismiss, onPressed: () => Navigator.pop(context, null)),
                    const SizedBox(width: 8),
                    AppButton(label: confirmLabel, onPressed: onConfirm),
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

/// The colour of one line of the watchdog's own log (ID-117, ID-158).
///
/// The same scheme as ROUTER LOG, where these lines also appear: lavender for the watchdog, and red
/// for a fault by ROUTER LOG's own rule, so a line is red on both screens or on neither. One
/// addition, teal for a rebuild that worked, because that is what someone opens this screen to find.
///
/// It used to have a scheme of its own: amber for the steps of a rebuild, which everywhere else in
/// this app means a warning, and red for "Not connected yet", which is what a first deploy says
/// before its tunnel has come up.
Color watchdogLogLineColour(String line) {
  if (readsAsError(line)) return kError;
  if (_wdSuccessPattern.hasMatch(line)) return kHighlight;
  return kWatchdogText;
}

/// Teal: the tunnel is up and, for the email, the alert got out.
final RegExp _wdSuccessPattern = RegExp(r'Deploy SUCCESS|Reconfig SUCCESS|Alert email sent \(SUCCESS\)');

/// The watchdog log, full screen.
///
/// A dialog until 423. Selecting the whole log put Android's own "Copy / Share" toolbar directly
/// over the action row at the bottom of the card, and a tap meant for Copy landed on CLEAR
/// (reported 2026-09-10). A full screen gives the text room to be selected without the selection's
/// toolbar and the app's buttons competing for the same 48 pixels.
class _WatchdogLogScreen extends StatefulWidget {
  const _WatchdogLogScreen({
    required this.slot,
    required this.desc,
    required this.text,
    required this.onCopy,
    required this.onClear,
  });

  final int slot;

  /// The slot's region, so the heading reads wgc1:aus_melbourne rather than a bare wgc1.
  final String desc;
  final String text;
  final Future<void> Function() onCopy;
  final Future<void> Function() onClear;

  @override
  State<_WatchdogLogScreen> createState() => _WatchdogLogScreenState();
}

class _WatchdogLogScreenState extends State<_WatchdogLogScreen> {
  final _scroll = ScrollController();

  int get slot => widget.slot;
  String get label => slotLabel(widget.slot, widget.desc);
  String get text => widget.text;
  Future<void> Function() get onCopy => widget.onCopy;
  Future<void> Function() get onClear => widget.onClear;

  @override
  void initState() {
    super.initState();
    // The newest entry is the reason this screen was opened. After the first layout, so the extent
    // is real; the log is a single text block, so one jump is enough.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kSurface,
            title: Text('Clear the watchdog log for $label?', style: const TextStyle(color: kText, fontSize: 15)),
            content: Text(
              "Empties /tmp/watchdog_wgc$slot.log on the router and deletes yesterday's rotated copy. The "
              'watchdog keeps writing to it from its next run. Nothing else changes.',
              style: const TextStyle(color: kMuted, fontSize: 13),
            ),
            actions: [
              AppButton(label: 'CANCEL', role: ButtonRole.dismiss, onPressed: () => Navigator.pop(ctx, false)),
              AppButton(
                keyValue: 'watchdog_log_clear_confirm',
                label: 'CLEAR',
                role: ButtonRole.destructive,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;
    Navigator.pop(context);
    await onClear();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kBg,
      child: Column(children: [
        // Laid out exactly as the app log and the router log are: padded like them, with the text
        // STRETCHED across the width. It was neither. A SelectableText in a plain Column is centred, so on a
        // tablet the lines sat in a narrow strip with a wide empty seam either side.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ScreenHeading('WATCHDOG LOG · $label', colour: kWatchdogColour),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  // Room below the last line for Android's selection toolbar to land on. It is placed
                  // relative to the selection rather than the layout, so this helps rather than fixes -
                  // the in-app COPY below is what makes the system toolbar unnecessary.
                  padding: const EdgeInsets.only(bottom: 72),
                  child: SizedBox(
                    width: double.infinity,
                    child: SelectableText.rich(
                      TextSpan(children: [
                        for (final (i, line) in text.split('\n').indexed)
                          TextSpan(
                            text: i == 0 ? line : '\n$line',
                            style: TextStyle(color: watchdogLogLineColour(line)),
                          ),
                      ]),
                      key: const Key('watchdog_log_text'),
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: LogButtonRow(children: [
            LogButton(keyValue: 'watchdog_log_copy', label: 'COPY', onPressed: onCopy),
            LogButton(
              keyValue: 'watchdog_log_clear',
              label: 'CLEAR',
              destructive: true,
              onPressed: () => _confirmClear(context),
            ),
            LogButton(keyValue: 'watchdog_log_close', label: 'CLOSE', onPressed: () => Navigator.pop(context)),
          ]),
        ),
      ]),
    );
  }
}
