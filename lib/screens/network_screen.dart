// screens/network_screen.dart - NETWORK: the public address, place and provider of this phone and of
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
// Nothing is sent until LOOK UP is tapped, and the notice above it says where the lookups go and who sees
// them, so it is read before every lookup, not only the first (Andrew, 2026-10-25). Free: it only reads.
// The phone's row needs no router; the tunnels' need the session's router login, asked for as ABOUT asks.

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_colors.dart';
import '../firmware.dart';
import '../network_lookup.dart';
import '../plain_error.dart';
import '../router_slot_service.dart';
import '../session_controller.dart';
import '../widgets/app_button.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/ssh_creds_dialog.dart';

/// What the tunnels' part of the screen says when there's no router to ask.
const String kNetworkLoginPrompt = 'login to router to include the tunnels';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key, this.testClientFactory, this.phoneLookup, this.addressLookup});

  // Test seams: the router, the phone's own lookup and the service's address.
  final Future<SSHClient> Function(String ip, String user, String pass)? testClientFactory;
  final Future<NetworkFacts> Function()? phoneLookup;
  final Future<String?> Function()? addressLookup;

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

/// One tunnel's row: the slot, PIA's region for it, and what the lookup found.
class _TunnelRow {
  const _TunnelRow(this.slot, this.region, this.result);
  final int slot;
  final String region;
  final TunnelLookup result;
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
  late final TapGestureRecognizer _loginRecogniser = TapGestureRecognizer()..onTap = _logInThenLookUp;
  late final TapGestureRecognizer _privacyRecogniser = TapGestureRecognizer()..onTap = _openPrivacy;

  @override
  void dispose() {
    _loginRecogniser.dispose();
    _privacyRecogniser.dispose();
    super.dispose();
  }

  Future<void> _openPrivacy() async {
    final url = Uri.parse(_service.privacyUrl);
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _lookUp() async {
    final controller = SessionScope.of(context);
    setState(() {
      _busy = true;
      _looked = true;
    });
    controller.logEntry('NETWORK: asking ${_service.name} for the public address of this phone'
        '${controller.canReuseRouterSession ? ' and of each tunnel that is up' : ''}.');
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
      if (mounted) {
        setState(() => _setTunnels([for (final s in up) _TunnelRow(s, slots.slots[s]?.desc ?? '', results[s]!)]));
      }
    } catch (e) {
      controller.logEntry('NETWORK: the tunnels could not be looked up: $e', isWarning: true);
      if (mounted) setState(() => _setTunnels(null, plainError(e)));
    }
  }

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
    return AppScaffold(
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            destinationHeading(AppDestination.network, key: const Key('network_heading')),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: 'LOOK UP asks ${_service.name} for the public address of this phone, and of each tunnel that is '
                        'up, sent through the router. ${_service.notice} '),
                TextSpan(text: '${_service.name}\'s privacy policy', style: const TextStyle(color: kHighlight), recognizer: _privacyRecogniser),
                const TextSpan(text: '. Nothing is sent until you tap LOOK UP.'),
              ]),
              key: const Key('network_notice'),
              style: const TextStyle(color: kMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            AppButton(
              keyValue: 'network_look_up',
              label: 'LOOK UP',
              colour: kNetworkColour,
              onPressed: _busy ? null : _lookUp,
            ),
            const SizedBox(height: 16),
            if (_busy) const Center(child: CircularProgressIndicator(color: kHighlight)),
            if (_looked && !_busy) ..._results(controller),
          ],
        ),
      ),
    );
  }

  List<Widget> _results(SessionController controller) => [
        _card(
          key: const Key('network_phone'),
          title: 'This phone',
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
              TunnelLookupOutcome.noRoute => "Couldn't be aimed through this tunnel, so nothing was sent.",
              TunnelLookupOutcome.failed => 'No answer through this tunnel.',
            },
          ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text('Address data from ${_service.name}.', style: const TextStyle(color: kMuted, fontSize: 11)),
        ),
      ];

  Widget _card({required Key key, required String title, NetworkFacts? facts, String? problem, String region = ''}) {
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$label  ', style: const TextStyle(color: kMuted)),
            TextSpan(text: value.isEmpty ? 'not given' : value, style: const TextStyle(color: kText)),
          ])),
        );
    return Container(
      key: key,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kField, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: kHighlight, fontWeight: FontWeight.bold)),
          if (problem != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(problem, style: const TextStyle(color: kWarn))),
          if (facts != null) ...[
            line('Address', facts.ip),
            line('Place', facts.place),
            line('Provider', facts.provider),
            // PIA's own name beside the database's estimate; they can disagree, and neither is chosen.
            if (region.isNotEmpty) line('PIA region', region),
          ],
        ],
      ),
    );
  }
}
