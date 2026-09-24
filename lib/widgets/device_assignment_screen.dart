// widgets/device_assignment_screen.dart - which LAN device goes through which tunnel.
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
// Design in `.claude/plans/plan_vpn_device_assignments.md` section 2.5. Two things about it are
// not obvious and both come from measurement rather than taste:
//
//   - The DEFAULT CONNECTION sits at the top with an explanation, because ARCHITECTURE.md "vpnc_dev_policy_list - the assignment"
//     makes it the setting that decides whether a dropped tunnel leaks or fails closed, and no
//     user would guess that from a list of devices.
//   - Changes are STAGED and applied together. One service call for N changes, and one
//     confirmation can carry every consequence rather than repeating it per row.
import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import 'app_button.dart';

import '../app_colors.dart';
import '../device_assignment.dart';
import '../device_assignment_service.dart';
import '../firmware.dart';
import '../router_slot_service.dart';
import '../router_session.dart' show routerConnectMessage;
import '../session_controller.dart';
import 'paywall.dart';
import 'app_scaffold.dart';
import 'common_fields.dart';
import 'error_presenter.dart';

class DeviceAssignmentScreen extends StatefulWidget {
  const DeviceAssignmentScreen({
    super.key,
    this.testClientFactory,
    this.serviceFactory,
    this.slotServiceFactory,
    this.quietCheckInterval = const Duration(seconds: 15),
  });

  /// How often, while the screen is on top, it checks quietly which tunnels are running (ID-218).
  final Duration quietCheckInterval;

  final Future<SSHClient> Function(String ip, String user, String pass)? testClientFactory;
  final DeviceAssignmentService Function(SSHClient)? serviceFactory;
  final RouterSlotService Function(SSHClient)? slotServiceFactory;

  @override
  State<DeviceAssignmentScreen> createState() => _DeviceAssignmentScreenState();
}

class _DeviceAssignmentScreenState extends State<DeviceAssignmentScreen> {
  final _ipCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _sshVisible = false, _busy = false, _prefilled = false;

  late SessionController _c;
  DeviceAssignmentService? _service;
  RouterSlotService? _slotSvc;
  AssignmentState? _state;

  /// True from the first frame of a re-entry that will reconnect on its own, false once that
  /// attempt has either produced a device list or failed and left the form to be used.
  bool _autoConnecting = false;

  /// Staged, not yet written: device IP to the profile index it should use, null for the default.
  /// Staged, unwritten changes. These live on the SESSION, not on this State: the screen is built
  /// from scratch every time it is entered, so a glance at the log used to discard everything the
  /// user had staged. Aliases rather than copies, so there is no sync step to forget.
  Map<String, int?> get _staged => _c.stagedAssignments;
  int? get _stagedDefault => _c.stagedDefaultIndex;
  set _stagedDefault(int? v) => _c.stagedDefaultIndex = v;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c = SessionScope.of(context);
    if (_prefilled) return;
    _prefilled = true;
    _ipCtrl.text = _c.routerIpPrefill;
    // Left BLANK when the session has no username yet, rather than defaulted to 'admin': a
    // password manager will not overwrite a field that already has content, so the default was
    // costing a manual clear before every autofill (B3 feedback 2026-09-08).
    _userCtrl.text = _c.sshUsername;
    _passCtrl.text = _c.sshPassword;
    // Without these the CONNECT button never re-evaluates: editing a field rebuilds the field, not
    // this widget, so `_canConnect` would stay at whatever it was when the screen was first built.
    for (final ctrl in [_ipCtrl, _userCtrl, _passCtrl]) {
      ctrl.addListener(() {
        if (mounted) setState(() {});
      });
    }

    // Already connected this session? Go straight to the list, as MANAGE and WATCHDOG do. Without
    // this the user had to press CONNECT every time they opened the screen while the other two
    // walked straight in (B8n feedback 2026-09-08).
    if (_c.routerConnected && _canConnect) {
      // Set synchronously, so the FIRST frame shows the reconnect placeholder instead of a login
      // form asking for credentials the app already has and is already using.
      _autoConnecting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _connect();
      });
    }
  }

  // ── Keeping "which tunnels are running" current (ID-218) ──────────────────────────
  //
  // Read once at connect, the notes under the pickers went stale: straight after a reboot every
  // device read "not running - no internet" while MANAGE showed every tunnel up, and going to MANAGE
  // and back changed nothing, because back returns to this same State. So the state is re-read
  // when the screen comes back into view, and every [quietCheckInterval] while it stays there -
  // one round trip, `tunnelHealth`, which writes nothing to the app log. A local one-second tick
  // decides when; it costs nothing until it asks the router.
  Timer? _ticker;
  bool _wasVisible = true;
  bool _checking = false;
  int _sinceCheck = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  bool get _visible {
    final life = WidgetsBinding.instance.lifecycleState;
    return (ModalRoute.of(context)?.isCurrent ?? true) && (life == null || life == AppLifecycleState.resumed);
  }

  void _tick() {
    if (!mounted) return;
    final visible = _visible;
    final cameBack = visible && !_wasVisible;
    _wasVisible = visible;
    _sinceCheck++;
    if (!visible || _state == null || _service == null || _busy || _checking) return;
    if (cameBack || _sinceCheck >= widget.quietCheckInterval.inSeconds) unawaited(_checkRunning());
  }

  /// Which WireGuard tunnels are up, into the notes and the sort order. A failure changes nothing:
  /// the next tick tries again, and the list must not flicker or complain on a dropped read.
  Future<void> _checkRunning() async {
    final svc = _service;
    if (svc == null || _state == null) return;
    final slots = {for (final p in _wireguardProfiles) if (p.slot != null) p.slot!};
    if (slots.isEmpty) return;
    _checking = true;
    _sinceCheck = 0;
    try {
      final health = await svc.tunnelHealth(slots);
      if (!mounted) return;
      final up = {for (final e in health.entries) if (e.value.up) e.key};
      final changed = !(_activeSlots != null &&
          _activeSlots!.where(slots.contains).toSet().length == up.length &&
          up.every(_activeSlots!.contains));
      if (changed) {
        setState(() => _activeSlots = {...?_activeSlots?.where((s) => !slots.contains(s)), ...up});
      }
    } catch (_) {
      // left as it was on purpose
    } finally {
      _checking = false;
    }
  }

  /// Pull-to-refresh: the device list and the tunnels, read again. Staged changes are kept.
  Future<void> _pullRefresh() async {
    final svc = _service;
    if (svc == null || _busy) return;
    try {
      final fresh = await svc.read();
      if (mounted) setState(() => _state = fresh);
    } catch (e) {
      if (mounted) await AppErrors.system(context, _c, 'Could not read the device list: $e');
      return;
    }
    await _checkRunning();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ipCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  bool get _canConnect =>
      _ipCtrl.text.trim().isNotEmpty && _userCtrl.text.trim().isNotEmpty && _passCtrl.text.isNotEmpty;

  Future<void> _connect() async {
    setState(() => _busy = true);
    // The work is a closure returning the failure text, if any, rather than presenting it inline.
    // Two reasons, and both bit: the CONNECT spinner animates for as long as _busy holds, so a
    // dialog raised from inside leaves it spinning behind (and pumpAndSettle never settles); and
    // an early `return` from a try/finally exits the METHOD, so anything after the block is
    // skipped. A closure makes the early exits return a value instead of jumping past the code
    // that shows it.
    Future<String?> attempt() async {
      final ip = _ipCtrl.text.trim(), user = _userCtrl.text.trim(), pass = _passCtrl.text;
      // The credentials have to be on the controller before asking for the session: it keys the
      // shared connection on them, and a stale key would hand back a session pointed at the
      // previous router.
      _c.routerIp = ip;
      _c.sshUsername = user;
      _c.sshPassword = pass;

      // The SHARED session, not a fresh SSHClient. Holding a raw client meant the screen kept a
      // connection that had already gone: six minutes elapsed between connect and APPLY on
      // 2026-09-08 and the write failed with `errno 103, software caused connection abort`. The app
      // drops the connection after kBackgroundSessionGrace in the background, and the router can
      // drop it at any time. RouterSession reopens and retries; a raw client cannot.
      final SSHClient client = _c.routerSession(
          () => widget.testClientFactory != null ? widget.testClientFactory!(ip, user, pass) : openSshClient(ip, user, pass));
      // Force the connection before anything else, so a wrong address or a refused login reports
      // as itself rather than as whatever the next command happens to be doing (build 413).
      await client.authenticated;

      final slotSvc = widget.slotServiceFactory?.call(client) ?? RouterSlotService(client);

      // Detect the firmware HERE. `routerFirmware` defaults to Merlin until something probes it,
      // so a user who opens this screen first - rather than passing through MANAGE - was told
      // their stock router was Merlin. Reported from B1 on 2026-09-08.
      if (!firmwareDetected) {
        final detected = classifyFirmwareTag(await slotSvc.readFirmwareTag());
        if (detected == null) {
          return 'This router reports a firmware this app does not support.';
        }
        setRouterFirmware(detected);
        _c.logEntry('Router firmware detected: ${detected.name}.');
      }

      if (!isStockFirmware) {
        return 'Device assignment is a stock-firmware feature. This router runs Asuswrt-Merlin, '
            'which has no VPN Fusion device policy to write.';
      }

      final svc = widget.serviceFactory?.call(client) ??
          DeviceAssignmentService(client, onLog: (m, {isError = false, isSuccess = false, isWarning = false}) => _c.logEntry(m, isError: isError, isSuccess: isSuccess));
      final state = await svc.read();
      // Watchdog state for the picker. A tolerated failure: the notes go blank rather than the
      // whole screen failing, because assignment does not depend on knowing them.
      Map<int, SlotInfo> slots = const {};
      Set<int>? active;
      try {
        final fetched = await slotSvc.fetchSlots();
        slots = fetched.slots;
        active = fetched.activeSlots;
      } catch (_) {
        // left blank on purpose
      }
      if (!mounted) return null;
      _c.routerConnected = true;
      setState(() {
        _service = svc;
        _slotSvc = slotSvc;
        _state = state;
        _slotInfo = slots;
        _activeSlots = active;
        _sinceCheck = 0;
        // Staged changes survive leaving the screen and coming back - they live on the session,
        // not on this State, which is rebuilt from scratch on every entry. Losing a dozen staged
        // assignments to a glance at the log was the reported bug.
        // Deliberately NOT cleared here: the staged changes are the user's, and a reconnect is
        // not a decision to throw them away. apply() re-reads and refuses on a conflict, so
        // carrying them across a reconnect cannot write anything based on a stale view.
      });
      return null;
    }

    String? failure, failureDetail;
    try {
      failure = await attempt();
    } catch (e) {
      // Plain English on screen, the raw exception in the log (ID-108).
      failure = routerConnectMessage(e, _ipCtrl.text) ?? 'Could not read the device list: $e';
      failureDetail = routerConnectMessage(e, _ipCtrl.text) == null ? null : e.toString();
    } finally {
      // Both flags together: past this point a failure leaves the user needing the form, so it
      // stops being a lie to show it.
      if (mounted) {
        setState(() {
          _busy = false;
          _autoConnecting = false;
        });
      }
    }
    if (failure != null && mounted) await AppErrors.system(context, _c, failure, logDetail: failureDetail);
  }

  // ── Staging ──────────────────────────────────────────────────────────────────────

  /// The profile index a device will be on once APPLY runs - staged value if any, else current.
  int? _effectiveIndex(LanDevice d) {
    final ip = d.ip;
    if (ip == null) return null;
    if (_staged.containsKey(ip)) return _staged[ip];
    return assignedIndexFor(_state!.policies, ip);
  }

  int get _pendingCount => _staged.length + (_stagedDefault != null ? 1 : 0);

  /// WireGuard slots only. A record naming an OpenVPN or PPTP profile is never offered - the app
  /// manages WireGuard, and writing to another VPN's profile is not ours to do.
  /// Active tunnels first, then disabled ones, each group in wgcN order.
  ///
  /// The list came back in `vpnc_clientlist` order, which is creation order - so a user who built
  /// wgc1 then wgc5 then wgc2 saw wgc4 above wgc3 and had to read every line to find one. Slot
  /// number is the only order anyone thinks in, highest first: wgc5 down to wgc1, the order the
  /// router's own web interface creates them in and the order MANAGE and WATCHDOG list them
  /// (ID-101). A running tunnel still sorts above a stopped one - that is what someone picking a
  /// connection needs to see first.
  List<VpncRecord> get _wireguardProfiles {
    final out = _state!.profiles.where((p) => p.protocol == 'WireGuard' && p.vpncStateIndex != null).toList();
    out.sort((a, b) {
      final aUp = _slotActive(a) ?? false, bUp = _slotActive(b) ?? false;
      if (aUp != bUp) return aUp ? -1 : 1;
      return (b.slot ?? 0).compareTo(a.slot ?? 0);
    });
    return out;
  }

  bool _isForeign(LanDevice d) => _isForeignIndex(_effectiveIndex(d));

  /// What the DEFAULT CONNECTION panel shows. An unset `vpnc_default_wan` means the plain
  /// internet, the same as an explicit 0 - without this it read 'default', which says nothing.
  String get _defaultLabel => _labelForIndex((_stagedDefault ?? _state!.defaultIndex) ?? 0);

  /// What a DEVICE row shows. A device with no pin of its own follows the default, so the row
  /// names it: "default - Internet", "default - wgc1 - pia-aus_melbourne". Reading just "default"
  /// meant knowing what the default was and holding it in your head while you read the list.
  ///
  /// Uses the STAGED default when one is pending, so the list says where these devices will be
  /// after APPLY rather than where they are now - which is what the panel above it also says.
  String _labelForDevice(int? idx) => idx == null ? 'default - $_defaultLabel' : _labelForIndex(idx);

  String _labelForIndex(int? idx) {
    if (idx == null) return 'default';
    // Index 0 is the WAN, and no vpnc_clientlist record carries it - so without this the default
    // connection read 'profile 0' whenever it was set to the plain internet, which is what B8 saw
    // on 2026-09-08. The picker has always OFFERED this as 'Internet'; only the label lagged.
    if (idx == 0) return 'Internet';
    for (final p in _state!.profiles) {
      if (p.vpncStateIndex != idx) continue;
      if (p.protocol != 'WireGuard') {
        // Named, never offered, never rewritten. Showing it as "default" would be a lie that
        // destroys the user's assignment on the next apply.
        return '${p.protocol.isEmpty ? 'Another VPN' : p.protocol}, not app managed';
      }
      final slot = p.slot;
      // `wgc1:pia-aus_melbourne`, the same shape slotLabel() produces and every log line in the app
      // already uses. It read `wgc1 - pia-aus_melbourne` here, which made the same tunnel look like
      // two different things depending on which screen you were on.
      return slot == null ? p.desc : slotLabel(slot, p.desc);
    }
    // No profile carries this index any more. It happens when a VPN is deleted from somewhere
    // else while the default connection still names it. Kept SHORT: this renders inside a device
    // row on a phone, where anything longer wraps or clips.
    return 'profile $idx (deleted)';
  }

  Future<void> _pick(LanDevice d) async {
    // A centred dialog rather than a bottom sheet. On a tall phone the sheet opened hard against
    // the bottom edge, far from the row that was tapped, and the row itself was hidden behind it
    // (B2 feedback 2026-09-08). The title carries the device name, since a centred dialog loses
    // the positional context a sheet anchored to the row would have had.
    final chosen = await showDialog<Object?>(
      context: context,
      builder: (ctx) => _PickerDialog(
        title: d.displayName,
        children: [
          _pickerTile(ctx,
              key: 'pick_default',
              label: 'default - $_defaultLabel',
              note: 'follows the default connection, whatever you set it to',
              value: 'default'),
          // Pinning to the plain internet is a DIFFERENT choice from following a default that
          // happens to be the internet: a pinned device ignores the default from then on. The
          // router models both (`1>IP>>0>` versus `0>IP>>0>`), the app only offered one, and with
          // a single tunnel configured the picker read as the same profile listed twice.
          _pickerTile(ctx,
              key: 'pick_internet',
              label: 'Internet',
              note: 'no VPN, and ignores the default connection',
              value: 0),
          for (final p in _wireguardProfiles)
            _pickerTile(ctx,
                key: 'pick_${p.vpncStateIndex}',
                label: _labelForIndex(p.vpncStateIndex),
                // The watchdog state belongs here rather than in a warning: the user sees it while
                // choosing, which is when it can still change the decision.
                note: _watchdogNote(p),
                active: _slotActive(p),
                value: p.vpncStateIndex),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      final ip = d.ip!;
      final next = chosen == 'default' ? null : chosen as int;
      if (next == assignedIndexFor(_state!.policies, ip)) {
        _staged.remove(ip); // back to where it started - not a change any more
      } else {
        _staged[ip] = next;
      }
    });
  }

  // One entry in a picker: the choice, and a note under it. Built here rather than inline so the
  // device picker and the default picker cannot drift apart.
  /// Whether the profile's tunnel is UP, or null when the slot state could not be read.
  ///
  /// A tunnel that is down accepts an assignment perfectly happily and then carries no traffic,
  /// which is a slow thing to work out from the outside. Reported after assigning a device to a
  /// disabled wgc5 and finding it still on wgc1.
  bool? _slotActive(VpncRecord p) {
    final slot = p.slot;
    if (slot == null) return null;
    return _activeSlots?.contains(slot);
  }

  Set<int>? _activeSlots;

  /// Whether the tunnel behind a profile index is up: null for a VPN this app does not manage, or a
  /// slot state that could not be read.
  bool? _isUpIndex(int index) {
    for (final p in _wireguardProfiles) {
      if (p.vpncStateIndex == index) return _slotActive(p);
    }
    return null;
  }

  /// The note under a picker whose tunnel is not running: where the traffic really goes. Null when it
  /// goes where the picker says, or that cannot be told. [pinned] is the device's own assignment, null
  /// when it follows the default; the default connection panel passes null with [forDefault].
  String? _exitNote(int? pinned, {bool forDefault = false}) {
    final def = _stagedDefault ?? _state!.defaultIndex;
    final exit = actualExitIndex(pinned: pinned, defaultIndex: def, isUp: _isUpIndex);
    if (exit == null) return null;
    final tunnel = _labelForIndex(pinned ?? def ?? 0);
    // Pinned: the fail-closed guard holds it (ID-213). It used to read "traffic uses Internet, with
    // no VPN", which was true before the guard and is exactly the leak the guard closes.
    if (exit == kExitBlocked) return '$tunnel is not running - no internet until it is enabled';
    final where = exit == 0 ? 'Internet, with no VPN' : _labelForIndex(exit);
    return '$tunnel is not running - ${forDefault ? 'unassigned devices use' : 'traffic uses'} $where';
  }

  Widget _pickerTile(BuildContext ctx,
          {required String key, required String label, required String note, required Object? value, bool? active}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        // A bordered, filled tile rather than a bare ListTile. Three plain rows of text read as a
        // paragraph, not as three things you could tap (B3 feedback 2026-09-08).
        child: OutlinedButton(
          key: Key(key),
          style: OutlinedButton.styleFrom(
            backgroundColor: kField,
            foregroundColor: kText,
            side: const BorderSide(color: kBorder),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            alignment: Alignment.centerLeft,
          ),
          onPressed: () => Navigator.pop(ctx, value),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: const TextStyle(color: kText, fontSize: 14)),
                // Teal ACTIVE / amber DISABLED, the colours the slot modal uses for the same
                // facts - amber being the app's "configured but not doing anything" colour, as on
                // a paused watchdog and on a staged-but-unapplied change.
                if (active != null || note.isNotEmpty)
                  Row(children: [
                    if (active != null) ...[
                      Text(active ? 'Active' : 'Disabled',
                          style: TextStyle(
                              color: active ? kHighlight : kWarn, fontSize: 12, fontWeight: FontWeight.w700)),
                      if (note.isNotEmpty) const Text(' - ', style: TextStyle(color: kMuted, fontSize: 12)),
                    ],
                    if (note.isNotEmpty)
                      Flexible(
                        child: Text(note,
                            style: TextStyle(
                                color: note == kWatchdogActiveNote ? kHighlight : kMuted, fontSize: 12)),
                      ),
                  ]),
              ]),
            ),
            const Icon(Icons.chevron_right, size: 18, color: kMuted),
          ]),
        ),
      );

  String _watchdogNote(VpncRecord p) {
    final slot = p.slot;
    if (slot == null) return '';
    final info = _slotInfo[slot];
    if (info == null) return '';
    if (info.watchdogActive) return kWatchdogActiveNote;
    if (info.watchdogConfigured) return 'watchdog paused';
    return 'no watchdog';
  }

  // Read alongside the assignment state so the picker can show watchdog state. Blank if that read
  // fails - the note disappears, the screen still works.
  Map<int, SlotInfo> _slotInfo = const {};

  // ── Apply ────────────────────────────────────────────────────────────────────────

  Future<void> _apply() async {
    // The gate for this screen. Reading the device list, tapping through the pickers and staging
    // changes are all free - seeing your own devices is the most persuasive thing this screen can
    // do. APPLY is the moment something changes on the router, so it is the moment that is gated.
    if (!_c.isUnlocked) {
      if (!await Paywall.show(context, _c, pitch: Pitch.assign) || !mounted) return;
    }
    final state = _state!;
    // A device gains a reservation when it has none: the policy record is keyed by IP, and an
    // address that is not pinned will eventually move to another device.
    final reservations = <String, String>{};
    for (final d in state.devices) {
      final ip = d.ip;
      if (ip == null || !_staged.containsKey(ip)) continue;
      if (_staged[ip] != null && !d.reserved) reservations[d.mac] = ip;
    }

    // The tunnels this apply moves devices onto, read now rather than trusted from connect time.
    final tunnelWarnings = await _tunnelWarnings(state);
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ApplyDialog(
        tunnelWarnings: tunnelWarnings,
        lines: [
          for (final entry in _staged.entries)
            _ChangeLine(
              name: state.devices.firstWhere((d) => d.ip == entry.key, orElse: () => LanDevice(mac: entry.key)).displayName,
              from: _labelForDevice(assignedIndexFor(state.policies, entry.key)),
              to: _labelForDevice(entry.value),
            ),
          if (_stagedDefault != null)
            _ChangeLine(
              name: 'Default connection',
              from: _labelForIndex(state.defaultIndex ?? 0),
              to: _labelForIndex(_stagedDefault ?? 0),
            ),
        ],
        reservationNames: [
          for (final mac in reservations.keys)
            state.devices.firstWhere((d) => d.mac == mac, orElse: () => LanDevice(mac: mac)).displayName
        ],
        restartsTunnels: _stagedDefault != null,
        foreignNames: [
          for (final entry in _staged.entries)
            if (_isForeignIndex(assignedIndexFor(state.policies, entry.key)))
              state.devices.firstWhere((d) => d.ip == entry.key, orElse: () => LanDevice(mac: entry.key)).displayName
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    // A centred modal, not a spinner inside the button. Putting it in the button left a grey blob
    // at the bottom of the screen where the label had been, which read as the button having broken
    // rather than as work in progress (B8n feedback 2026-09-08). This also blocks input, which is
    // right: changing the default connection stops the tunnels and must not be interrupted.
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ProgressDialog(),
    ));
    var progressShown = true;
    void dismissProgress() {
      if (!progressShown || !mounted) return;
      progressShown = false;
      Navigator.of(context, rootNavigator: true).pop();
    }

    String? failure;
    try {
      await _service!.apply(
        base: state,
        changes: Map.of(_staged),
        reservationsToCreate: reservations,
        newDefaultIndex: _stagedDefault,
        // The service knows IP addresses and profile indexes; only the screen knows what the user
        // calls them. Naming the change here is what makes the app log readable a week later.
        changeDescriptions: [
          for (final entry in _staged.entries)
            '${state.devices.firstWhere((d) => d.ip == entry.key, orElse: () => LanDevice(mac: entry.key)).displayName}: '
                '${_labelForDevice(assignedIndexFor(state.policies, entry.key))} -> ${_labelForDevice(entry.value)}',
        ],
        defaultFrom: _labelForIndex(state.defaultIndex ?? 0),
        defaultTo: _labelForIndex(_stagedDefault ?? 0),
      );
    } on AssignmentConflictException catch (e) {
      failure = e.toString();
    } catch (e) {
      failure = 'Could not apply the changes: $e';
    }

    // Re-read either way. On success it shows what was written; after a conflict it replaces the
    // base that caused the refusal, which otherwise made every later APPLY refuse as well and left
    // leaving the screen as the only way out.
    try {
      final fresh = await _service!.read();
      if (mounted) {
        setState(() {
          _state = fresh;
          _c.clearStagedAssignments();
        });
      }
    } catch (e) {
      failure ??= 'Applied, but could not re-read the router: $e';
    }
    // Tunnel state too: a default-connection change stops and restarts the tunnels, and the notes
    // under the pickers are only as current as this.
    try {
      final fetched = await _slotSvc?.fetchSlots();
      if (fetched != null && mounted) {
        setState(() {
          _slotInfo = fetched.slots;
          _activeSlots = fetched.activeSlots;
        });
      }
    } catch (_) {
      // The notes keep what they had; the assignment itself is unaffected.
    }

    dismissProgress();
    if (mounted) setState(() => _busy = false);
    if (failure != null && mounted) await AppErrors.system(context, _c, failure);
  }

  /// What APPLY's confirmation says about the tunnels this apply moves devices onto.
  ///
  /// Warnings, never a block: assigning a device to a disabled slot is legitimate. The device has no
  /// internet until the slot is enabled - the fail-closed guard holds it (ID-213). The same read
  /// refreshes the row notes.
  Future<List<String>> _tunnelWarnings(AssignmentState state) async {
    String nameOf(String ip) =>
        state.devices.firstWhere((d) => d.ip == ip, orElse: () => LanDevice(mac: ip)).displayName;
    final slotOf = <int, int>{
      for (final p in _wireguardProfiles)
        if (p.slot != null) p.vpncStateIndex!: p.slot!,
    };
    final defaultAfter = _stagedDefault ?? state.defaultIndex ?? 0;
    // Devices pinned onto each tunnel, by profile index, in the order they were staged.
    final onto = <int, List<String>>{};
    for (final e in _staged.entries) {
      final idx = e.value;
      if (idx != null && slotOf.containsKey(idx)) onto.putIfAbsent(idx, () => []).add(nameOf(e.key));
    }
    // The default connection's tunnel, when this apply changes the default or sends a device to it.
    final checkDefault = slotOf.containsKey(defaultAfter) && (_stagedDefault != null || _staged.containsValue(null));
    final slots = {for (final idx in onto.keys) slotOf[idx]!, if (checkDefault) slotOf[defaultAfter]!};
    if (slots.isEmpty) return const [];

    setState(() => _busy = true);
    try {
      final health = await _service!.tunnelHealth(slots);
      if (mounted) {
        setState(() => _activeSlots = {
              ...?_activeSlots?.where((s) => !health.containsKey(s)),
              for (final e in health.entries)
                if (e.value.up) e.key,
            });
      }
      final warnings = <String>[];
      for (final e in onto.entries) {
        final h = health[slotOf[e.key]];
        if (h == null) continue;
        // Pinned devices wait for their own tunnel; they no longer fall through to the default.
        final w = tunnelWarning(h, tunnel: _labelForIndex(e.key), who: joinNames(e.value), blocked: true);
        if (w != null) warnings.add(w);
      }
      if (checkDefault) {
        final h = health[slotOf[defaultAfter]];
        final w = h == null
            ? null
            : tunnelWarning(h, tunnel: _labelForIndex(defaultAfter), who: 'devices on the default connection');
        if (w != null) warnings.add(w);
      }
      return warnings;
    } catch (e) {
      return ['The tunnels could not be checked before applying, so whether they are running is not known: $e'];
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isForeignIndex(int? idx) =>
      idx != null && idx != 0 && !_wireguardProfiles.any((p) => p.vpncStateIndex == idx);

  // ── Build ────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_state == null && _autoConnecting) {
      return const AppScaffold(fillViewport: true, child: ReconnectingBody());
    }
    return AppScaffold(
      onRefresh: _state == null ? null : _pullRefresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Named after the menu item that opened it, in that item's colour (ID-112). Above both
          // the login form and the device list, so the screen is named before it is connected.
          destinationHeading(AppDestination.deviceAssignment, key: const Key('device_assignment_heading')),
          const SizedBox(height: 16),
          _state == null ? _buildConnect() : _buildList(),
        ],
      ),
    );
  }

  Widget _buildConnect() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RouterIpField(controller: _ipCtrl),
        const SizedBox(height: 12),
        // Both fields in ONE group, as the other router screens do. Separately, a manager fills the
        // username and never offers the password - which is what B3 saw.
        AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SshUsernameField(controller: _userCtrl),
            const SizedBox(height: 12),
            SshPasswordField(
                controller: _passCtrl, visible: _sshVisible, onToggle: () => setState(() => _sshVisible = !_sshVisible)),
          ]),
        ),
        const SizedBox(height: 24),
        // Same widget, label and spinner as RouterSlotsScreen. This screen had a FilledButton
        // reading 'CONNECT', so it sat differently and read differently from the two router
        // screens beside it in the menu (B8n feedback 2026-09-08).
        SizedBox(
          width: double.infinity,
          child: AppButton(
            keyValue: 'device_connect',
            label: 'CONNECT TO ROUTER',
            busy: _busy,
            onPressed: _busy || !_canConnect ? null : _connect,
          ),
        ),
      ]);

  Widget _buildList() {
    final state = _state!;
    final defaultNote = _exitNote(null, forDefault: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Two panels on different grounds. The default connection is a router-wide setting and the
      // list below it is per-device; read as one continuous column they were indistinguishable,
      // which is what B1 reported on 2026-09-08.
      _Panel(
        // Same ground as the device list with a teal border on both, so the two panels read as
        // one family rather than two unrelated boxes. Not kSurface - that is the header colour,
        // and the panel disappeared into it (B2 and B3 feedback 2026-09-08).
        background: kConfigBg,
        borderColour: kHighlight,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Default connection', style: TextStyle(color: kHighlight, fontSize: 12)),
          const SizedBox(height: 4),
          _PickerButton(
            keyValue: 'default_picker',
            label: _defaultLabel,
            changed: _stagedDefault != null,
            muted: defaultNote != null,
            onTap: _busy ? null : _pickDefault,
          ),
          if (defaultNote != null) ...[
            const SizedBox(height: 4),
            Text(defaultNote, key: const Key('default_exit'), style: const TextStyle(color: kWarn, fontSize: 12)),
          ],
          const SizedBox(height: 6),
          const Text(
            'Devices set to "default" use this. Assigned devices fall back to it if their tunnel drops.',
            style: TextStyle(color: kMuted, fontSize: 12),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      _Panel(
        background: kConfigBg,
        borderColour: kHighlight,
        // Built into a Column rather than an inner ListView: AppScaffold already wraps the body in
        // a SingleChildScrollView, and a scrollable inside a scrollable has no bounded height.
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final d in state.devices) ...[
            if (d != state.devices.first) const Divider(color: kBorder, height: 20),
            _DeviceRow(
              device: d,
              label: _labelForDevice(_effectiveIndex(d)),
              changed: _staged.containsKey(d.ip),
              foreign: _isForeign(d),
              note: d.assignable ? _exitNote(_effectiveIndex(d)) : null,
              onTap: _busy || !d.assignable ? null : () => _pick(d),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 8),
      const Text("Names come from your router's client list.",
          textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 11)),
      const SizedBox(height: 8),
      // One row, two equal halves, both buttons at HOME's height so the three read as one set
      // rather than three sizes stacked up the screen.
      //
      // Both are always shown and follow the pending state: with changes staged, DISCARD is red and
      // APPLY teal; with none, both are grey and disabled. It was a Wrap, which put them side by
      // side once a change was staged and stacked them before that - the widest label the screen
      // ever shows is the idle APPLY 0 CHANGES, so the pair reflowed exactly when nothing was
      // happening (ID-090). Expanded halves at the smaller label size hold the row at every width.
      Row(children: [
        Expanded(
          child: AppButton(
            keyValue: 'device_discard',
            label: 'DISCARD CHANGES',
            role: ButtonRole.destructive,
            fullWidth: true,
            fontSize: 12,
            onPressed: _busy || _pendingCount == 0 ? null : () => setState(_c.clearStagedAssignments),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppButton(
            keyValue: 'device_apply',
            // 'APPLY 1' read as a step number rather than a count (B3 feedback).
            label: _pendingCount == 1 ? 'APPLY 1 CHANGE' : 'APPLY $_pendingCount CHANGES',
            fullWidth: true,
            fontSize: 12,
            onPressed: _busy || _pendingCount == 0 ? null : _apply,
          ),
        ),
      ]),
      // AppScaffold pins HOME to the bottom over the scroll view, which clipped APPLY when the
      // list was scrolled fully down (B1 screenshot 2026-09-08).
      const SizedBox(height: 16),
    ]);
  }

  Future<void> _pickDefault() async {
    final chosen = await showDialog<Object?>(
      context: context,
      builder: (ctx) => _PickerDialog(
        title: 'Default connection',
        children: [
          _pickerTile(ctx, key: 'default_pick_internet', label: 'Internet', note: 'no VPN', value: 0),
          for (final p in _wireguardProfiles)
            _pickerTile(ctx,
                key: 'default_pick_${p.vpncStateIndex}',
                label: _labelForIndex(p.vpncStateIndex),
                note: _watchdogNote(p),
                active: _slotActive(p),
                value: p.vpncStateIndex),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _stagedDefault = chosen == _state!.defaultIndex ? null : chosen as int);
  }
}

/// The one picker note worth spotting in a list, so it is the one that is not grey.
const String kWatchdogActiveNote = 'watchdog active';

/// One device: `Name - IP` over the picker. The MAC stands in for a missing name rather than
/// occupying a line of its own, and only exceptional states earn a tag.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.label,
    required this.changed,
    required this.foreign,
    required this.onTap,
    this.note,
  });

  final LanDevice device;
  final String label;
  final bool changed, foreign;
  final VoidCallback? onTap;

  /// Where the traffic really goes when the tunnel is not running; null when it goes where the picker
  /// says.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final tags = <String>[
      if (!device.reserved && device.assignable) 'DHCP',
      if (!device.online) 'offline',
      if (device.hasRandomisedMac) 'random MAC',
    ];
    // The name and its exceptions on the first line, the address and MAC on the second (ID-032). The MAC is what
    // tells apart two devices the router gives the same name, and what matches the router's own client list.
    final head = tags.isEmpty ? device.displayName : '${device.displayName} - ${tags.join(' | ')}';
    final address = [if (device.ip != null) device.ip!, device.mac].join(' ');
    return Opacity(
      opacity: device.online ? 1 : 0.55,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Teal, not the body grey: on a phone the whole screen read as one undifferentiated block
        // and the device names are what the eye needs to land on first (B1 feedback 2026-09-08).
        Text(head, style: const TextStyle(color: kHighlight, fontSize: 13)),
        Text(
          address,
          key: Key('addr_${device.mac}'),
          style: const TextStyle(color: kMuted, fontSize: 12, fontFamily: 'monospace'),
        ),
        const SizedBox(height: 4),
        if (device.assignable)
          _PickerButton(keyValue: 'row_${device.mac}', label: label, changed: changed, muted: note != null, onTap: onTap)
        else
          const Text('connect this device once to assign it', style: TextStyle(color: kHint, fontSize: 12)),
        // Where the traffic really goes. The picker keeps naming the assignment - the pin is intact, and
        // enabling the tunnel restores it - so this is a note, never a change of value.
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note!, key: Key('exit_${device.mac}'), style: const TextStyle(color: kWarn, fontSize: 12)),
        ],
      ]),
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton(
      {required this.keyValue, required this.label, required this.changed, required this.onTap, this.muted = false});

  final String keyValue, label;

  /// [muted] greys a label whose tunnel is not running, so the note beneath it reads first.
  final bool changed, muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        key: Key(keyValue),
        style: OutlinedButton.styleFrom(
          // Amber for a staged change, never teal. The device name above is already teal, so a
          // teal picker made the whole row one colour and the pending state disappeared into it
          // (B2 feedback 2026-09-08). Amber also carries the right meaning: not yet written.
          foregroundColor: changed ? kWarn : (muted ? kMuted : kText),
          // Grey, not kBorder: at kBorder the outline all but vanished and the picker read as text.
          side: BorderSide(color: changed ? kWarn : kMuted),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          alignment: Alignment.centerLeft,
        ),
        onPressed: onTap,
        child: Row(children: [
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down, size: 18),
        ]),
      );
}

class _ChangeLine {
  const _ChangeLine({required this.name, required this.from, required this.to});
  final String name, from, to;
}

/// The single confirmation. Every consequence appears here rather than being repeated per row, and
/// only the paragraphs that actually apply are shown.
class _ApplyDialog extends StatelessWidget {
  const _ApplyDialog({
    required this.lines,
    required this.reservationNames,
    required this.foreignNames,
    required this.restartsTunnels,
    this.tunnelWarnings = const [],
  });

  final List<_ChangeLine> lines;
  final List<String> reservationNames, foreignNames;

  /// What the tunnel check found about the tunnels this apply moves devices onto.
  final List<String> tunnelWarnings;

  /// True when the default connection is being changed. That is the one operation on this screen
  /// with a real cost - see DeviceAssignmentService._setDefaultConnection.
  final bool restartsTunnels;

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Apply ${lines.length} change${lines.length == 1 ? '' : 's'}',
            style: const TextStyle(color: kText, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            for (final l in lines) ...[
              Text(l.name, style: const TextStyle(color: kText, fontSize: 13)),
              Text('${l.from} -> ${l.to}', style: const TextStyle(color: kMuted, fontSize: 12)),
              const SizedBox(height: 6),
            ],
            for (final w in tunnelWarnings) ...[
              const SizedBox(height: 8),
              Text(w, style: const TextStyle(color: kWarn, fontSize: 12)),
            ],
            if (reservationNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${reservationNames.join(', ')} will also be given a fixed address, because an '
                'assignment follows the address rather than the device. That reservation stays on '
                'your router afterwards, including if you unassign later.',
                style: const TextStyle(color: kWarn, fontSize: 12),
              ),
            ],
            if (restartsTunnels) ...[
              const SizedBox(height: 8),
              const Text(
                'Changing the default connection stops and restarts your VPN tunnels, so anything '
                'using them loses its connection for about a minute. Assigning a device on its own '
                'does not do this.',
                style: TextStyle(color: kWarn, fontSize: 12),
              ),
            ],
            if (foreignNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${foreignNames.join(', ')} is currently on a VPN this app does not manage. '
                'Continuing replaces that assignment.',
                style: const TextStyle(color: kWarn, fontSize: 12),
              ),
            ],
          ]),
        ),
        actions: [
          AppButton(label: 'CANCEL', role: ButtonRole.dismiss, onPressed: () => Navigator.pop(context, false)),
          AppButton(keyValue: 'apply_confirm', label: 'APPLY', onPressed: () => Navigator.pop(context, true)),
        ],
      );
}

/// A grouped block on its own ground, so the router-wide setting and the per-device list read as
/// two things rather than one long column of text.
class _Panel extends StatelessWidget {
  const _Panel({required this.background, required this.child, this.borderColour = kBorder});

  final Color background, borderColour;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: borderColour),
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      );
}

/// A centred picker. Scrolls internally and is capped, so a router with five slots and a long
/// region name still fits on a small screen with a large system font.
class _PickerDialog extends StatelessWidget {
  const _PickerDialog({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(title, style: const TextStyle(color: kHighlight, fontSize: 15)),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: children),
        ),
        actions: [AppButton(label: 'CANCEL', role: ButtonRole.dismiss, onPressed: () => Navigator.pop(context))],
      );
}

/// Shown for the duration of an apply. Centred and non-dismissible, because changing the default
/// connection stops the tunnels and takes several seconds - long enough that a static screen
/// reads as nothing having happened.
class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog();

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: kSurface,
          content: Row(mainAxisSize: MainAxisSize.min, children: const [
            SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kHighlight)),
            SizedBox(width: 16),
            Flexible(
              child: Text('Applying - do not leave this screen.', style: TextStyle(color: kText, fontSize: 14)),
            ),
          ]),
        ),
      );
}
