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
// This is the slot modal's CREATE/EDIT action for the watchdog screen. SAVE & DEPLOY writes the
// watchdog parameters - and, when the watchdog is not yet active or the region has changed, the region
// chosen on the form as wgcN_desc - to NVRAM and then deploys the script + cron via
// RouterWatchdog.deployWatchdog — this is the only
// path that brings a watchdog up, so there is no separate ENABLE action.

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import 'widgets/app_button.dart';

import 'app_colors.dart';
import 'firmware.dart';
import 'pia_service.dart';
import 'router_slot_service.dart' show dnsAddressesIn, kSlotDescPrefix, slotDescFor, slotLabel;
import 'router_watchdog.dart';
import 'session_controller.dart';
import 'watchdog_email.dart';
import 'widgets/app_scaffold.dart';
import 'widgets/common_fields.dart';
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

  /// The router's own encrypted-DNS servers, so the DNS field can say when the two overlap (ID-005).
  final Set<String> routerDotServers;
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
    this.routerDotServers = const {},
  });

  @override
  State<WatchdogDialog> createState() => _WatchdogDialogState();
}

class _WatchdogDialogState extends State<WatchdogDialog> {
  /// The PIA region, chosen on the form. Pre-filled with the slot's own, so saving an active watchdog
  /// without touching it keeps the tunnel it has.
  late final _regionCtrl = TextEditingController(text: _regionIdOf(widget.regionDesc));
  final _intervalCtrl = TextEditingController(text: '5');
  final _primaryCtrl = TextEditingController(text: '8.8.8.8');
  final _secondaryCtrl = TextEditingController(text: '1.1.1.1');

  /// Where the watchdog's own lookups go (ID-076). Prefilled with the default and overridable,
  /// because the right answer depends on what the rest of the router is doing: the one thing that
  /// must not happen is picking an address a slot uses, which would route the watchdog's lookups
  /// into the tunnel it exists to repair.
  late final _dohUrlCtrl = TextEditingController(text: kDefaultDohResolver.url);
  late final _dohIpCtrl = TextEditingController(text: kDefaultDohResolver.ip);

  /// The slot's DNS servers (ID-126). Pre-filled with the slot's own when it has them, and with
  /// the session default when it does not - which is what MANAGE CREATE does, and what a slot built
  /// from this form never got.
  late final _dnsCtrl = TextEditingController(text: _c.dns);
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
  bool _loadingRegions = false;

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
    // The DoH note depends on both fields, and it only changed on some unrelated rebuild (ID-144).
    _dnsCtrl.addListener(_onDnsChanged);
    _dohIpCtrl.addListener(_onDnsChanged);
    _load();
  }

  void _onDnsChanged() {
    if (mounted) setState(() {});
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

  EmailSettings get _emailOnForm => EmailSettings(
        from: _fromCtrl.text.trim(),
        to: _toCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        smtpServer: _smtpServerCtrl.text.trim(),
        smtpUser: _smtpUserCtrl.text.trim(),
        smtpPass: _smtpPassCtrl.text,
      );

  // Every email field, the SMTP server and port included, from one source (ID-050).
  void _applyEmail(EmailSettings e) {
    _fromCtrl.text = e.from;
    _toCtrl.text = e.to;
    if (e.subject.isNotEmpty) _subjectCtrl.text = e.subject;
    _smtpServerCtrl.text = e.smtpServer;
    _smtpUserCtrl.text = e.smtpUser;
    _smtpPassCtrl.text = e.smtpPass;
  }

  // Kept for the next watchdog's form, like the PIA credentials. A form with no server and no recipient
  // leaves what the session already knows alone.
  void _rememberEmail() {
    final e = _emailOnForm;
    if (!e.isEmpty) _c.watchdogEmail = e;
  }

  @override
  void dispose() {
    // Runs on every exit path (SAVE, CLOSE, barrier dismiss), so whatever was typed is retained.
    _rememberPiaCreds();
    _rememberEmail();
    for (final c in [
      _regionCtrl,
      _intervalCtrl,
      _primaryCtrl,
      _secondaryCtrl,
      _dnsCtrl,
      _dohUrlCtrl,
      _dohIpCtrl,
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
      // ID-050: the slot's own email settings, else the session's, else the lowest-numbered other slot's. The
      // other slots cost a round trip, so they are read only when the first two have nothing.
      final own = EmailSettings(
        from: cfg.emailFrom,
        to: cfg.emailTo,
        subject: cfg.emailSubject,
        smtpServer: cfg.smtpServer,
        smtpUser: cfg.smtpUsername,
        smtpPass: cfg.smtpPassword,
      );
      final prefill = firstEmailSettings(slot: widget.slotIndex, own: own, session: _c.watchdogEmail) ??
          firstEmailSettings(slot: widget.slotIndex, others: await svc.readEmailSettings());
      if (!mounted) return;
      setState(() {
        _jqMissing = !jq;
        _bootDirMissing = !bootReady;
        _status = status;
        _applyConfig(cfg);
        if (own.isEmpty && prefill != null) _applyEmail(prefill);
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
    if (c.slotDns.trim().isNotEmpty) _dnsCtrl.text = c.slotDns;
    // A watchdog deployed before build 454 has neither, and gets the default rather than nothing.
    if (c.dohUrl.trim().isNotEmpty) _dohUrlCtrl.text = c.dohUrl;
    if (c.dohIp.trim().isNotEmpty) _dohIpCtrl.text = c.dohIp;
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

  /// Where the WATCHDOG's own lookups go - not the slot's DNS, which is the field above it, and
  /// the two are easy to confuse. This one is the router asking "where is PIA"; that one is a
  /// pinned device asking "where is anything" (ID-076).
  Widget _dohPicker() {
    final known = kDohResolvers.firstWhere(
      (r) => r.url == _dohUrlCtrl.text.trim() && r.ip == _dohIpCtrl.text.trim(),
      orElse: () => const DohResolver('Something else', '', ''),
    );
    // The clash that matters: an address this slot also uses for its DNS is routed into this
    // slot's tunnel, so a broken tunnel would take the watchdog's own lookups with it.
    final dohIp = _dohIpCtrl.text.trim();
    final clashSlot = dohIp.isNotEmpty && dnsAddressesIn(_dnsCtrl.text).contains(dohIp);
    final clashRouter = dohIp.isNotEmpty && widget.routerDotServers.contains(dohIp);
    final clash = clashSlot || clashRouter;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text("The watchdog's own encrypted DNS", style: TextStyle(color: kHighlight, fontSize: 12)),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        key: const Key('wd_doh_choice'),
        initialValue: known.url.isEmpty ? '' : known.url,
        // Without this the menu sizes to its longest label and overflows a narrow phone.
        isExpanded: true,
        dropdownColor: kSurface,
        style: const TextStyle(color: kText, fontSize: 13),
        decoration: const InputDecoration(isDense: true),
        items: [
          for (final r in kDohResolvers) DropdownMenuItem(value: r.url, child: Text(r.label, overflow: TextOverflow.ellipsis)),
          const DropdownMenuItem(value: '', child: Text('Something else')),
        ],
        onChanged: (value) => setState(() {
          final chosen = kDohResolvers.where((r) => r.url == value);
          if (chosen.isEmpty) {
            // "Something else": empty, for the user to fill in. Left holding the last resolver, the
            // fields read as that resolver still being chosen (ID-170).
            _dohUrlCtrl.clear();
            _dohIpCtrl.clear();
            return;
          }
          _dohUrlCtrl.text = chosen.first.url;
          _dohIpCtrl.text = chosen.first.ip;
        }),
      ),
      _field(_dohUrlCtrl, 'DoH URL', const Key('wd_doh_url')),
      _field(_dohIpCtrl, 'DoH server address', const Key('wd_doh_ip')),
      Text(
        // Two causes, named apart. The note said "used for DNS on this router" for both, and the
        // common one is neither the router nor another tunnel: it is this tunnel's own DNS (ID-144).
        clashSlot
            ? "This address is also this tunnel's DNS server, so the router sends its own lookups to it "
                "through this tunnel - the watchdog's included. If the tunnel breaks, the watchdog cannot look "
                'up PIA to repair it. Choose an address this tunnel does not use for DNS.'
            : clashRouter
                ? "The router already uses this address for its own encrypted DNS. If a tunnel uses it for DNS "
                    "too, the router's lookups to it go through that tunnel, and the watchdog's go with them. "
                    'Choose an address nothing else uses.'
                : 'The watchdog resolves PIA over an encrypted connection to this address. The DoH URL must be a '
                'name, not an IP address. The DoH server address is how that name is reached. Leave both '
                'empty to look names up in the clear.',
        key: const Key('wd_doh_note'),
        style: TextStyle(color: clash ? kWarn : kMuted, fontSize: 11),
      ),
    ]);
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
        slotDns: _dnsCtrl.text,
        dohUrl: _dohUrlCtrl.text,
        dohIp: _dohIpCtrl.text,
      );

  /// The PIA region id a slot description names: the description without the app's prefix.
  static String _regionIdOf(String desc) {
    final d = desc.trim();
    return d.startsWith(kSlotDescPrefix) ? d.substring(kSlotDescPrefix.length) : d;
  }

  // The same picker STANDALONE uses, on the form itself. It used to arrive after SAVE, as a surprise at
  // the end of a long form. The field can be typed into as well.
  Future<void> _browseRegions() async {
    setState(() => _loadingRegions = true);
    try {
      final regions = await (widget.piaService ?? PiaService()).fetchRegions(onProgress: _c.onLog);
      if (!mounted) return;
      setState(() => _loadingRegions = false);
      await RegionPickerSheet.show(context, regions: regions, onSelected: (id) => setState(() => _regionCtrl.text = id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingRegions = false);
      await AppErrors.system(context, _c, 'Failed to load regions: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  /// Null when [region] is a PIA WireGuard region, otherwise what to tell the user. Checked against the
  /// live list because the field can be typed into, and a watchdog deployed against a region PIA does
  /// not have would only fail later, on the router, at its first reconfigure.
  Future<String?> _regionProblem(String region) async {
    try {
      final regions = await (widget.piaService ?? PiaService()).fetchRegions(onProgress: _c.onLog);
      return regions.any((r) => r.id == region) ? null : '"$region" is not a PIA WireGuard region. Choose one from the list.';
    } catch (e) {
      return 'Could not check the region with PIA: ${e.toString().replaceAll('Exception: ', '')}';
    }
  }

  /// Asks PIA whether these credentials work, BEFORE they are written to the router (ID-120).
  ///
  /// Returns the sentence to show, or null to carry on. Only a refusal stops a save: PIA being
  /// unreachable from this phone says nothing about the credentials, and the watchdog does its own
  /// asking from the router, over the router's connection.
  ///
  /// Worth the round trip because the alternative is finding out minutes later, in a FAILED alert
  /// email, from a router that has already half-built a slot (ID-096).
  Future<String?> _piaRejection(WatchdogConfig cfg) async {
    if (cfg.piaUsername.trim().isEmpty || cfg.piaPassword.isEmpty) return null;
    try {
      await (widget.piaService ?? PiaService()).getToken(cfg.piaUsername.trim(), cfg.piaPassword, onProgress: _c.onLog);
      return null;
    } catch (e) {
      if (isPiaAuthRejection(e)) return kPiaCredentialsRejected;
      _c.logEntry(
          'Could not check the PIA credentials before deploying: '
          '${e.toString().replaceAll('Exception: ', '')} Saving anyway; the router will try for itself.',
          isWarning: true);
      return null;
    }
  }

  Future<bool> _confirmOverwrite(String region) async {
    // A changed region is a rebuild (RouterWatchdog._clearForRebuild), and the tunnel is down while it
    // happens. Saying so is the difference between an informed tap and a surprise outage.
    final rebuild = region != _regionIdOf(widget.regionDesc);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        // Names what is being overwritten, the same shape the delete prompts use.
        title: Text('Overwrite ${slotLabel(widget.slotIndex, widget.regionDesc)}?',
            style: const TextStyle(color: kText, fontSize: 15)),
        content: Text(
            rebuild
                ? 'This rebuilds the tunnel on $region. If it is running, it goes down while that happens, and '
                    'devices assigned to it use the default connection until it is back. This watchdog\'s settings '
                    'are replaced too.'
                : 'This will reset both this watchdog and any underlying VPN region.',
            style: const TextStyle(color: kMuted, fontSize: 13)),
        actions: [
          AppButton(label: 'CANCEL', role: ButtonRole.dismiss, onPressed: () => Navigator.pop(ctx, false)),
          AppButton(label: 'CONTINUE', onPressed: () => Navigator.pop(ctx, true)),
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

    // The region comes from the form. It is written - and a configured slot overwritten, only after the
    // warning - when the watchdog is not yet active or the region has been changed. An active watchdog
    // saved with its region untouched keeps the tunnel it has.
    final region = _regionCtrl.text.trim();
    final enabled = _status?.isEnabled == true;
    final regionChanges = !enabled || region != _regionIdOf(widget.regionDesc);
    // Every problem at once, in the order the fields appear: the region is at the top of the form, so
    // it comes first. A made-up region used to be reported only once the SMTP fields below it were
    // right, one dialog at a time (ID-202).
    final regionProblem = region.isEmpty
        ? 'Choose a region first.'
        : regionChanges
            ? await _regionProblem(region)
            : null;
    if (!mounted) return;
    final errors = [if (regionProblem != null) regionProblem, ...cfg.validate()];
    if (errors.isNotEmpty) {
      await AppErrors.inputs(context, _c, errors);
      return;
    }

    String? newDesc;
    if (regionChanges) {
      if (!widget.slotIsEmpty && !await _confirmOverwrite(region)) return;
      newDesc = region;
    }

    // Before a single NVRAM key is written (ID-120).
    final rejected = await _piaRejection(cfg);
    if (!mounted) return;
    if (rejected != null) {
      await AppErrors.inputs(context, _c, [rejected]);
      return;
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
    // The region on the form, which the router does not carry until the first deploy (ID-049).
    final sent = await _withService((svc) => svc.testEmail(_currentConfig(), desc: slotDescFor(_regionCtrl.text)));
    if (!mounted) return;
    // A failed send used to say nothing on screen and one teal line in the app log telling the
    // user to go and read the ROUTER log. Every diagnostic now lands in the app log, and this
    // says so - a phone is a poor place from which to go SSH into a router.
    if (sent == false) {
      await AppErrors.system(context, _c, 'The test email could not be sent. See APP LOG for what the router reported.');
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
                  const Icon(Icons.shield_outlined, color: kWatchdogColour, size: 18),
                  const SizedBox(width: 8),
                  // slotLabel, so the heading reads "wgc5:pia-aus_perth" - the same shape the
                  // EDIT modal and every log line use.
                  Expanded(
                    child: ScreenHeading('WATCHDOG · ${slotLabel(widget.slotIndex, widget.regionDesc)}', colour: kWatchdogColour),
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
              // The region, chosen here with everything else - the same row STANDALONE has.
              RegionRow(controller: _regionCtrl, loading: _loadingRegions, onBrowse: _browseRegions),
              const SizedBox(height: 12),
              _field(_intervalCtrl, 'Check interval (minutes)', const Key('wd_interval'), keyboard: TextInputType.number),
              _field(_primaryCtrl, 'Primary ping IP', const Key('wd_primary')),
              _field(_secondaryCtrl, 'Secondary ping IP', const Key('wd_secondary')),
              // The slot's own DNS, not a watchdog setting - but this form builds slots, and one
              // built without it leaves its pinned devices resolving over the WAN (ID-126).
              DnsField(controller: _dnsCtrl, firstServerNote: isStockFirmware, routerDotServers: widget.routerDotServers),
              const SizedBox(height: 12),
              _dohPicker(),
              const SizedBox(height: 12),
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
                AppButton(
                  keyValue: 'wd_test_email',
                  label: 'TEST EMAIL',
                  icon: Icons.mail_outline,
                  onPressed: _loading ? null : _testEmail,
                ),
              ],
              const SizedBox(height: 16),
              AppButton(
                keyValue: 'wd_save',
                fullWidth: true,
                onPressed: (_loading || _blocked) ? null : _save,
                // The region is chosen on the form now, so SAVE is the deploy and says so. The label
                // STAYS during a save: the spinner is the overlay, not the button. A spinner in the
                // button put the one thing the user needed to see inside the scroll view, where it
                // could be below the fold - which it was, in 409, 412, 425 and again in 435.
                label: 'SAVE & DEPLOY',
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  label: 'CLOSE',
                  role: ButtonRole.dismiss,
                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
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
