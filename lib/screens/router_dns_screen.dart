// router_dns_screen.dart - SETTINGS' ROUTER RESOLVER STATUS and ROUTER DNS ROUTING windows (ID-194).
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
// One screen draws both reports from lib/router_dns.dart's blocks, laid out like ROUTER LOG: a
// heading, one scrolling area, and COPY, REFRESH and HOME fixed below. Agreed from mockups on
// 2026-09-27: the heading, notes and labels in teal, anything read from the router in white, and
// every word selectable, with COPY still copying the whole window.
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../router_dns.dart';
import '../router_session.dart' show routerConnectMessage;
import '../session_controller.dart';
import '../widgets/app_drawer.dart' show navigateToDestination;
import '../widgets/app_scaffold.dart';
import '../widgets/common_fields.dart' show SlotBadge;
import '../widgets/log_buttons.dart';

class DnsReportScreen extends StatefulWidget {
  const DnsReportScreen({
    super.key,
    required this.title,
    required this.keyPrefix,
    required this.client,
    required this.load,
    this.onLoaded,
  });

  /// ROUTER RESOLVER STATUS: is the router's DNS working, and the files behind it.
  factory DnsReportScreen.resolver({Key? key, required SSHClient client, VoidCallback? onLoaded}) => DnsReportScreen(
        key: key,
        title: 'ROUTER RESOLVER STATUS',
        keyPrefix: 'resolver',
        client: client,
        load: loadResolverStatus,
        onLoaded: onLoaded,
      );

  /// ROUTER DNS ROUTING: where each lookup goes, and whether anyone can read it.
  factory DnsReportScreen.routing({Key? key, required SSHClient client, VoidCallback? onLoaded}) => DnsReportScreen(
        key: key,
        title: 'ROUTER DNS ROUTING',
        keyPrefix: 'dns_routing',
        client: client,
        load: loadDnsRouting,
        onLoaded: onLoaded,
      );

  final String title, keyPrefix;
  final SSHClient client;
  final Future<List<DnsBlock>> Function(SSHClient client) load;

  /// Called after the first read that reached the router, so SETTINGS can count the session as connected.
  final VoidCallback? onLoaded;

  @override
  State<DnsReportScreen> createState() => _DnsReportScreenState();
}

class _DnsReportScreenState extends State<DnsReportScreen> {
  late SessionController _c;
  List<DnsBlock>? _blocks;
  String? _error;
  bool _loading = false, _started = false, _reported = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c = SessionScope.of(context);
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final blocks = await widget.load(widget.client);
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _error = null;
      });
      if (!_reported) {
        _reported = true;
        widget.onLoaded?.call();
      }
    } catch (e) {
      // Plain English on screen, the raw exception in the log (ID-108).
      _c.logEntry('${widget.title}: $e', isError: true);
      if (mounted) setState(() => _error = routerConnectMessage(e, _c.routerIp.trim()) ?? 'Could not read the router: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy() async {
    final blocks = _blocks;
    if (blocks == null) return;
    // Not a secret: copying must not arm the 60s auto-clear, which would wipe what was just copied.
    await _c.copyToClipboard(dnsReportText(widget.title, blocks), armAutoClear: false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${widget.title} copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _blocks;
    return Material(
      color: kBg,
      child: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ScreenHeading(widget.title, colour: kHighlight, key: Key('${widget.keyPrefix}_heading')),
              const SizedBox(height: 8),
              Expanded(
                child: blocks == null
                    ? Center(
                        child: _loading
                            ? const CircularProgressIndicator(color: kHighlight)
                            : Text(_error ?? '', style: const TextStyle(color: kError, fontSize: 13)),
                      )
                    // One selection region over the whole report, so "select all" spans all of it. A
                    // lazily built list would leave what is off screen out of the selection.
                    : SelectionArea(
                        child: SingleChildScrollView(
                          key: Key('${widget.keyPrefix}_body'),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(_error!, style: const TextStyle(color: kError, fontSize: 12)),
                              ),
                            for (final b in blocks) Padding(padding: const EdgeInsets.only(bottom: 12), child: _block(b)),
                          ]),
                        ),
                      ),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: LogButtonRow(children: [
            LogButton(keyValue: '${widget.keyPrefix}_copy', label: 'COPY', onPressed: blocks == null ? null : _copy),
            LogButton(
              keyValue: '${widget.keyPrefix}_refresh',
              label: 'REFRESH',
              busy: _loading,
              onPressed: _loading ? null : _refresh,
            ),
            LogButton(
              keyValue: '${widget.keyPrefix}_home',
              label: 'HOME',
              onPressed: () => navigateToDestination(context, _c, AppDestination.menu),
            ),
          ]),
        ),
      ]),
    );
  }

  static const _note = TextStyle(color: kHighlight, fontSize: 11, height: 1.45);
  static const _data = TextStyle(color: kText, fontSize: 11, height: 1.6);

  // Separators that are part of the text, so a selection copies as lines rather than one run.
  // Selecting across separate pieces of text joins them with nothing between: "dnsmasqOK172.66..."
  // (found 2026-09-27). The line break is one pixel high, and the space as wide as a character,
  // so the screen looks the same.
  static const _br = TextSpan(text: '\n', style: TextStyle(fontSize: 1, height: 1));
  static const _space = Text(' ', style: TextStyle(fontSize: 12));

  /// [text] as its own line when selected.
  static Widget _t(String text, TextStyle style) => Text.rich(TextSpan(style: style, children: [TextSpan(text: text), _br]));

  Widget _block(DnsBlock b) => switch (b) {
        DnsGroup(:final title) => Container(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder))),
            child: _t(title,
                const TextStyle(color: kHighlight, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          ),
        DnsVerdict(:final text, :final lead) => Container(
            padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: kHighlight, width: lead ? 3 : 2))),
            child: _t(
                text,
                lead
                    ? const TextStyle(color: kText, fontSize: 13, height: 1.45)
                    : const TextStyle(color: kHighlight, fontSize: 12, height: 1.45)),
          ),
        DnsStamp(:final text) => _t(text, _note),
        DnsFile() => _file(b),
        DnsCheck() => _check(b),
        DnsFlow(:final lines) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: _line(l)),
            ],
          ),
      };

  Widget _file(DnsFile f) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text('${f.name} ', style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w700))),
          if (f.written != null) Text('written ${f.written}', style: const TextStyle(color: kHighlight, fontSize: 10)),
          const Text.rich(_br),
        ]),
        const SizedBox(height: 4),
        _t(f.role, _note),
        if (f.caution != null) _t(f.caution!, const TextStyle(color: kWarn, fontSize: 11, height: 1.45)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: kConfigBg, borderRadius: BorderRadius.circular(6)),
          // Long lines scroll sideways rather than wrap: a wrapped config line reads as two settings.
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: _t(f.content, _data)),
        ),
      ]);

  static SlotBadge _pill(DnsCheckState s) => switch (s) {
        DnsCheckState.ok => const SlotBadge(label: 'OK', text: kHighlight, border: kHighlight, bg: kTagTunnelBg),
        DnsCheckState.failed => const SlotBadge(label: 'FAILED', text: kError, border: kError, bg: kTagFailedBg),
        DnsCheckState.notUsed => const SlotBadge(label: 'NOT USED', text: kMuted, border: kMuted, bg: kTagNeutralBg),
      };

  Widget _check(DnsCheck c) => Container(
        padding: const EdgeInsets.all(12),
        decoration:
            BoxDecoration(color: kField, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text.rich(TextSpan(style: TextStyle(color: kHighlight, fontSize: 12, height: 1.5), children: [
            TextSpan(text: 'Live check: looks up '),
            TextSpan(text: 'example.com', style: TextStyle(color: kText)),
            TextSpan(text: " through the router's own resolvers, the way your devices do."),
            _br,
          ])),
          for (final r in c.rows) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 64, child: Text('${r.who} ', style: const TextStyle(color: kText, fontSize: 12))),
              _pill(r.state),
              _space,
              // One text per row: the addresses, why it failed, and the running line, each on its own
              // line when copied.
              Expanded(
                child: Text.rich(TextSpan(style: const TextStyle(color: kText, fontSize: 12, height: 1.5), children: [
                  if (r.addresses.isNotEmpty) TextSpan(text: '${r.addresses.join('\n')}\n'),
                  if (r.detail.isNotEmpty) TextSpan(text: '${r.detail}\n'),
                  if (r.running != null || r.ms != null)
                    TextSpan(
                      text: [
                        if (r.running != null) r.running! ? 'running' : 'not running',
                        if (r.ms != null) '${r.ms} ms',
                      ].join(' · '),
                      style: TextStyle(color: r.running == false ? kError : kHighlight, fontSize: 11),
                    ),
                  _br,
                ])),
              ),
            ]),
          ],
          if (c.advice != null) ...[
            const SizedBox(height: 8),
            _t(c.advice!, const TextStyle(color: kWarn, fontSize: 12, height: 1.5)),
          ],
          const SizedBox(height: 8),
          _t(c.checkedAt, _note),
        ]),
      );

  static SlotBadge _tag(DnsTag t) => switch (t.kind) {
        DnsTagKind.tunnel || DnsTagKind.encrypted =>
          SlotBadge(label: t.label, text: kHighlight, border: kHighlight, bg: kTagTunnelBg),
        DnsTagKind.internet => SlotBadge(label: t.label, text: kTagInternet, border: kTagInternet, bg: kTagInternetBg),
        DnsTagKind.plain => SlotBadge(label: t.label, text: kWarn, border: kWarn, bg: kTagPlainBg),
        DnsTagKind.neutral => SlotBadge(label: t.label, text: kMuted, border: kMuted, bg: kTagNeutralBg),
      };

  Widget _line(DnsFlowLine l) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration:
            BoxDecoration(color: kField, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(6)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(style: const TextStyle(color: kText, fontSize: 12, height: 1.5), children: [
                TextSpan(text: l.head, style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: l.rest),
                _br,
              ])),
              if (l.note.isNotEmpty) _t(l.note, _note),
            ]),
          ),
          _space,
          // The tags copy as "Internet, encrypted (DoT)" and the line ends there.
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _tag(l.where),
            if (l.encryption != null) ...[
              const Text(', ', style: TextStyle(fontSize: 3, height: 1)),
              _tag(l.encryption!),
            ],
            const Text.rich(_br),
          ]),
        ]),
      );
}
