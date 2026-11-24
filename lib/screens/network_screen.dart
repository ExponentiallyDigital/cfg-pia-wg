// screens/network_screen.dart - NETWORK: the public address, place and provider of this device and of
// each tunnel that is up (ID-458).
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
// It looks up as it opens and again on REFRESH, with no text above the results; the footer names the
// source and opens its page (Andrew, 2026-10-25). PIA already knows every address it is asked about, so
// no notice is needed before asking. Free: it only reads. The device's row needs no router; the tunnels'
// need the session's router login, asked for as ABOUT asks.

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_colors.dart';
import '../firmware.dart';
import '../network_lookup.dart';
import '../plain_error.dart';
import '../router_facts.dart';
import '../router_slot_service.dart';
import '../session_controller.dart';
import '../widgets/app_drawer.dart' show navigateToDestination;
import '../tunnel_status.dart';
import '../widgets/app_button.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/log_buttons.dart';
import '../widgets/ssh_creds_dialog.dart';
import '../widgets/slot_text.dart';

/// What the tunnels' part of the screen says when there's no router to ask.
const String kNetworkLoginPrompt = 'login to router for tunnel details';

/// A tunnel the router had no route through when it was asked (TunnelLookupOutcome.noRoute): most likely
/// it was going down or restarting, perhaps by its watchdog. Nothing was sent, rather than risk an answer
/// by the WAN showing the home address as the tunnel's.
const String kNetworkNoRoute = 'Not checked: the router has no route through this tunnel right now. It may be restarting; '
    'try REFRESH.';

/// What a tunnel's speed line says when the test found no route, or no figure.
const String kSpeedNoRoute = 'Not tested: the router has no route through this tunnel right now. It may be restarting.';
const String kSpeedFailed = 'The test gave no figure through this tunnel.';

/// The confirmation TEST SPEED asks first (ID-604): who is asked, what they see and how much it uses.
String speedConfirmation(String tunnel, SpeedService s) =>
    'This runs ${s.name}\'s speed test through $tunnel, down and then up, and takes about 45 seconds. It uses ${speedTestDataUse()}. '
    '${s.name} sees only this tunnel\'s PIA address, never your home address. It measures the router, not your Wi-Fi.';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({
    super.key,
    this.testClientFactory,
    this.phoneLookup,
    this.addressLookup,
    this.speedAddressLookup,
    this.openUrl,
    this.clock,
  });

  // Test seams: the router, the device's own lookup, the service's address, the speed server's address,
  // opening a page, and the time of day.
  final Future<SSHClient> Function(String ip, String user, String pass)? testClientFactory;
  final Future<NetworkFacts> Function()? phoneLookup;
  final Future<String?> Function()? addressLookup;
  final Future<String?> Function()? speedAddressLookup;
  final Future<void> Function(Uri url)? openUrl;
  final DateTime Function()? clock;

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

/// One tunnel's row: the slot, PIA's region for it, what the lookup found, and its `wg show` status.
class _TunnelRow {
  const _TunnelRow(this.slot, this.region, this.result, this.status);
  final int slot;
  final String region;
  final TunnelLookup result;
  final TunnelStatus status;
}

class _NetworkScreenState extends State<NetworkScreen> {
  final IpLookupService _service = kIpLookupService;
  bool _busy = false;
  bool _looked = false;
  NetworkFacts? _phone;
  String? _phoneError;

  /// Null until the tunnels were asked; empty when none was up.
  List<_TunnelRow>? _tunnels;
  String? _tunnelError;
  RouterFirmware _firmware = RouterFirmware.merlin;

  /// The router's own identity, for the box above "This device" (ID-706); null when not logged in or unread.
  RouterFacts? _router;

  /// The latest speed test of each tunnel, when it finished, and the slot being tested (one at a time).
  final Map<int, SpeedResult> _speed = {};
  final Map<int, DateTime> _speedAt = {};
  int? _speedBusy;
  late final TapGestureRecognizer _loginRecogniser = TapGestureRecognizer()..onTap = _logInThenLookUp;

  @override
  void initState() {
    super.initState();
    // Looked up as the screen opens (Andrew, 2026-10-25); REFRESH asks again. After the first frame,
    // because the lookup reads the session from the context.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lookUp();
    });
  }

  @override
  void dispose() {
    _loginRecogniser.dispose();
    super.dispose();
  }

  Future<void> _openSource() async {
    final url = Uri.parse(_service.sourceUrl);
    if (widget.openUrl != null) return widget.openUrl!(url);
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _openSpeedSource() async {
    final url = Uri.parse(kSpeedService.sourceUrl);
    if (widget.openUrl != null) return widget.openUrl!(url);
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _lookUp() async {
    final controller = SessionScope.of(context);
    setState(() {
      _busy = true;
      _looked = true;
    });
    controller.logEntry('NETWORK: asking ${_service.name} for the public address of this device'
        '${controller.canReuseRouterSession ? ' and of each tunnel that is up' : ''}.');
    if (!controller.canReuseRouterSession) _router = null;
    final phone = _lookUpPhone();
    final tunnels = controller.canReuseRouterSession ? _lookUpTunnels(controller) : Future<void>.value();
    await Future.wait([phone, tunnels]);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _lookUpPhone() async {
    try {
      final facts = await (widget.phoneLookup ?? () => lookUpThisPhone(service: _service))();
      if (mounted) {
        setState(() {
          _phone = facts;
          _phoneError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phone = null;
          _phoneError = plainError(e);
        });
      }
    }
  }

  Future<void> _lookUpTunnels(SessionController controller) async {
    final ip = controller.routerIp.trim(), user = controller.sshUsername.trim(), pass = controller.sshPassword;
    try {
      final client =
          controller.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      // Read afresh: NETWORK can be the first router screen of a session, and the cached default is Merlin.
      final firmware = classifyFirmwareTag(await _run(client, 'nvram get 3rd-party'));
      if (firmware == null) throw Exception('this router firmware is not supported.');
      setRouterFirmware(firmware);
      _firmware = firmware;
      _router = await _readRouterFacts(client, controller);
      final slots = await RouterSlotService(client).fetchSlots();
      final up = slots.activeSlots.toList()..sort((a, b) => b.compareTo(a));
      if (up.isEmpty) {
        if (mounted) setState(() => _setTunnels(const []));
        return;
      }
      final address = await (widget.addressLookup ?? () => tunnelLookupAddress(service: _service))();
      if (address == null) throw Exception("couldn't find an address for ${_service.name} that a tunnel carries.");
      final raw = await _run(client, tunnelLookupCommand(up, address, stock: firmware == RouterFirmware.stock, service: _service));
      final results = parseTunnelLookups(raw, up, service: _service);
      final statuses = await _readStatuses(client, up, controller);
      if (mounted) {
        setState(() => _setTunnels([for (final s in up) _TunnelRow(s, slots.slots[s]?.desc ?? '', results[s]!, statuses[s]!)]));
      }
    } catch (e) {
      controller.logEntry('NETWORK: the tunnels could not be looked up: $e', isWarning: true);
      if (mounted) setState(() => _setTunnels(null, plainError(e)));
    }
  }

  /// The router's identity (ID-706). A read that fails leaves the box out, and the tunnels are still looked up.
  Future<RouterFacts?> _readRouterFacts(SSHClient client, SessionController controller) async {
    try {
      return parseRouterFacts(await _run(client, kRouterFactsCommand));
    } catch (e) {
      controller.logEntry("NETWORK: the router's own details could not be read: $e", isWarning: true);
      return null;
    }
  }

  /// Each tunnel's `wg show` status (ID-600). A read that fails leaves empty statuses, so the lookup's
  /// own rows are still shown.
  Future<Map<int, TunnelStatus>> _readStatuses(SSHClient client, List<int> up, SessionController controller) async {
    try {
      return parseTunnelStatuses(await _run(client, tunnelStatusCommand(up)), up);
    } catch (e) {
      controller.logEntry("NETWORK: the tunnels' status could not be read: $e", isWarning: true);
      return parseTunnelStatuses('', up);
    }
  }

  /// TEST SPEED (ID-604): confirms, then runs the speed test through one tunnel and keeps its figures.
  Future<void> _testSpeed(_TunnelRow t) async {
    final controller = SessionScope.of(context);
    final label = 'wgc${t.slot}';
    if (!await _confirmSpeed(label) || !mounted) return;
    setState(() => _speedBusy = t.slot);
    controller.logEntry('NETWORK: testing the speed of $label against ${kSpeedService.name}.');
    try {
      final result = await _runSpeed(controller, t.slot);
      controller.logEntry(switch (result.outcome) {
        SpeedOutcome.done => 'NETWORK: $label ${_speedAndTimingText(result)}.',
        SpeedOutcome.noRoute => 'NETWORK: $label was not tested, the router has no route through it.',
        SpeedOutcome.failed => 'NETWORK: the speed test of $label gave no figure.',
        SpeedOutcome.refused => 'NETWORK: the speed test of $label was refused by ${kSpeedService.name}: ${speedRefusedText(result)}.',
      }, isWarning: result.outcome != SpeedOutcome.done);
      _keepSpeed(t.slot, result);
    } catch (e) {
      controller.logEntry('NETWORK: the speed test of $label could not be run: $e', isWarning: true);
      _keepSpeed(t.slot, const SpeedResult(SpeedOutcome.failed));
    } finally {
      if (mounted) setState(() => _speedBusy = null);
    }
  }

  /// TEST SPEED's confirmation (ID-604): who is asked, what they see and how much it uses.
  Future<bool> _confirmSpeed(String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Test the speed of $label?', style: const TextStyle(color: kHighlight, fontSize: 14)),
        content: Text(speedConfirmation(label, kSpeedService), style: const TextStyle(color: kText, fontSize: 12)),
        actions: [
          AppButton(
              keyValue: 'network_speed_cancel', label: 'CANCEL', role: ButtonRole.dismiss, onPressed: () => Navigator.pop(ctx, false)),
          AppButton(keyValue: 'network_speed_confirm', label: 'TEST', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Runs the speed test of slot [slot] on the router. Throws when the server has no address a tunnel
  /// carries, or the router can't be asked.
  Future<SpeedResult> _runSpeed(SessionController controller, int slot) async {
    const service = kSpeedService;
    final ip = controller.routerIp.trim(), user = controller.sshUsername.trim(), pass = controller.sshPassword;
    final client =
        controller.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
    final address = await (widget.speedAddressLookup ?? () => tunnelLookupAddress(host: service.host, fallback: service.fallbackAddress))();
    if (address == null) throw Exception("couldn't find an address for ${service.name} that a tunnel carries.");
    final raw = await _run(client, tunnelSpeedCommand(slot, address, stock: _firmware == RouterFirmware.stock))
        .timeout(const Duration(seconds: 120));
    return parseSpeedResult(raw);
  }

  void _keepSpeed(int slot, SpeedResult result) {
    if (!mounted) return;
    setState(() {
      _speed[slot] = result;
      _speedAt[slot] = (widget.clock ?? DateTime.now)();
    });
  }

  static String _speedAndTimingText(SpeedResult r) => '${_speedText(r)}'
      '${r.latencyMs == null ? '' : ', latency ${formatMs(r.latencyMs!)}'}'
      '${r.jitterMs == null ? '' : ', jitter ${formatMs(r.jitterMs!)}'}';

  static String _speedText(SpeedResult r) => '${formatMbit(r.downMbit!)} down, ${formatMbit(r.upMbit!)} up';

  static String _clockText(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _setTunnels(List<_TunnelRow>? rows, [String? error]) {
    _tunnels = rows;
    _tunnelError = error;
  }

  static Future<String> _run(SSHClient client, String command) async =>
      String.fromCharCodes(await client.run(command)).trim();

  /// The tunnels' login link: asks for the router login as ABOUT does, then looks the tunnels up.
  Future<void> _logInThenLookUp() async {
    final controller = SessionScope.of(context);
    final entered = await showDialog<(String, String, String)?>(
      context: context,
      builder: (_) => SshCredsDialog(
        initialIp: controller.routerIpPrefill,
        initialUser: controller.sshUsername.trim(),
        initialPass: controller.sshPassword,
        verify: (ip, user, pass) => verifyRouterLogin(controller, ip, user, pass, testClientFactory: widget.testClientFactory),
      ),
    );
    if (entered == null || !mounted) return;
    await _lookUp();
  }

  @override
  Widget build(BuildContext context) {
    final controller = SessionScope.of(context);
    // The first lookup has nothing to show yet; a REFRESH keeps the cards it is replacing.
    final firstLookup = !_looked || (_busy && _phone == null && _phoneError == null);
    // REFRESH and HOME side by side, ROUTER LOG's row, in place of the scaffold's own HOME.
    return Material(
      color: kBg,
      child: Column(
        children: [
          Expanded(
            child: AppScaffold(
              showClose: false,
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    destinationHeading(AppDestination.network, key: const Key('network_heading')),
                    if (firstLookup)
                      const Padding(
                        padding: EdgeInsets.only(top: 32),
                        child: Center(child: CircularProgressIndicator(color: kHighlight)),
                      )
                    else
                      ..._results(controller),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: LogButtonRow(children: [
              LogButton(keyValue: 'network_refresh', label: 'REFRESH', busy: _busy, onPressed: _busy ? null : _lookUp),
              LogButton(
                keyValue: 'network_home',
                label: 'HOME',
                onPressed: () => navigateToDestination(context, controller, AppDestination.menu),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// The router's box (ID-706): its WAN address, DDNS name and domain only when it has them, its name and its
  /// LAN address.
  Widget _routerCard(RouterFacts r) => _card(
        key: const Key('network_router'),
        title: 'Router',
        extra: [
          _line('WAN IP', r.wanIp),
          if (r.ddns.isNotEmpty) _line('DDNS', r.ddns),
          _line('Hostname', r.hostname),
          if (r.domain.isNotEmpty) _line('Domain name', r.domain),
          _line('LAN IP', r.lanIp),
        ],
      );

  List<Widget> _results(SessionController controller) => [
        if (_router != null) _routerCard(_router!),
        _card(
          key: const Key('network_phone'),
          title: 'This device',
          facts: _phone,
          problem: _phoneError == null ? null : 'No answer from ${_service.name}: $_phoneError',
        ),
        if (!controller.canReuseRouterSession && _tunnels == null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text.rich(
              TextSpan(text: kNetworkLoginPrompt, style: const TextStyle(color: kHighlight), recognizer: _loginRecogniser),
              key: const Key('network_login'),
            ),
          ),
        if (_tunnelError != null)
          _card(key: const Key('network_tunnels_error'), title: 'Tunnels', problem: 'Could not look them up: $_tunnelError'),
        if (_tunnels != null && _tunnels!.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('No tunnel is up.', key: Key('network_no_tunnels'), style: TextStyle(color: kMuted, fontSize: 13)),
          ),
        for (final t in _tunnels ?? const <_TunnelRow>[])
          _card(
            key: Key('network_wgc${t.slot}'),
            title: slotLabel(t.slot, t.region),
            facts: t.result.facts,
            region: t.region,
            problem: switch (t.result.outcome) {
              TunnelLookupOutcome.found => null,
              TunnelLookupOutcome.noRoute => kNetworkNoRoute,
              TunnelLookupOutcome.failed => 'No answer through this tunnel.',
            },
            extra: _statusLines(t),
          ),
        // The whole line opens the service's own page (Andrew, 2026-10-25).
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: InkWell(
            key: const Key('network_source'),
            onTap: _openSource,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Address data from ${_service.name}.', style: const TextStyle(color: kHighlight, fontSize: 13)),
            ),
          ),
        ),
        // Where the speed test's data comes from (ID-708), shown when a tunnel's card has TEST SPEED.
        if (_tunnels?.any((t) => t.result.outcome == TunnelLookupOutcome.found) ?? false)
          InkWell(
            key: const Key('network_speed_source'),
            onTap: _openSpeedSource,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Speed test data from ${kSpeedService.name}.', style: const TextStyle(color: kHighlight, fontSize: 13)),
            ),
          ),
      ];

  static Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$label: ', style: const TextStyle(color: kMuted)),
          TextSpan(text: value.isEmpty ? 'not given' : value, style: const TextStyle(color: kText)),
        ])),
      );

  /// A tunnel's `wg show` lines (ID-600), its last speed test and the TEST SPEED button (ID-604).
  List<Widget> _statusLines(_TunnelRow t) {
    final speed = _speed[t.slot];
    return [
      ..._wgLines(t.status),
      if (speed != null) ..._speedLines(speed, _speedAt[t.slot]),
      if (t.result.outcome == TunnelLookupOutcome.found) _speedButton(t),
    ];
  }

  /// `wg show`'s lines (ID-600); a line the router couldn't give is left out.
  static List<Widget> _wgLines(TunnelStatus s) => [
        if (s.handshakeAgeSeconds != null) _line('Handshake', formatAge(s.handshakeAgeSeconds!)),
        if (s.endpoint.isNotEmpty) _line('Server', s.endpoint),
        if (s.bytesIn != null && s.bytesOut != null)
          _line('Transferred', '${formatBytes(s.bytesIn!)} in, ${formatBytes(s.bytesOut!)} out'),
        if (s.restarts != null) _line('Watchdog restarts', '${s.restarts} since 12am'),
      ];

  /// A speed test's lines: its figures, then (ID-703) the latency and jitter when the timing gave them, or
  /// the reason there is no figure.
  List<Widget> _speedLines(SpeedResult speed, DateTime? at) => switch (speed.outcome) {
        SpeedOutcome.done => [
            _line('Speed', '${_speedText(speed)} (${_clockText(at!)})'),
            if (speed.latencyMs != null) _line('Latency', formatMs(speed.latencyMs!)),
            if (speed.jitterMs != null) _line('Jitter', formatMs(speed.jitterMs!)),
          ],
        SpeedOutcome.noRoute => [_warning(kSpeedNoRoute)],
        SpeedOutcome.failed => [_warning(kSpeedFailed)],
        SpeedOutcome.refused => [_warning(speedRefusedText(speed))],
      };

  static Widget _warning(String text) =>
      Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: const TextStyle(color: kWarn)));

  Widget _speedButton(_TunnelRow t) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: AppButton(
          keyValue: 'network_speed_wgc${t.slot}',
          label: 'TEST SPEED',
          busy: _speedBusy == t.slot,
          onPressed: _speedBusy == null ? () => _testSpeed(t) : null,
        ),
      );

  Widget _card({
    required Key key,
    required String title,
    NetworkFacts? facts,
    String? problem,
    String region = '',
    List<Widget> extra = const [],
  }) {
    Widget line(String label, String value) => _line(label, value);
    return Container(
      key: key,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kField, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SlotText(title, style: const TextStyle(color: kHighlight, fontWeight: FontWeight.bold)),
          if (problem != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(problem, style: const TextStyle(color: kWarn))),
          if (facts != null) ...[
            line('Address', facts.ip),
            line('Place', facts.place),
            line('Provider', facts.provider),
            // PIA's own name beside the database's estimate; they can disagree, and neither is chosen.
            if (region.isNotEmpty) line('PIA region', region),
          ],
          ...extra,
        ],
      ),
    );
  }
}
