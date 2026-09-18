// widgets/common_fields.dart - Reusable input fields, buttons, badges and the log panel.
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
// These widgets are lifted from main.dart / router_push.dart so the new screens reuse a single
// set of consistently-styled controls (spec §3: "be consistent across all UI elements").

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;

import '../app_colors.dart';
import '../router_slot_service.dart' show dnsSharedWithRouter;
import '../session_controller.dart';

const _kMono = TextStyle(color: kText, fontFamily: 'monospace');

/// PIA region id field plus a "browse regions" icon button (from main.dart `_buildRegionRow`).
class RegionRow extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onBrowse;
  const RegionRow({super.key, required this.controller, required this.loading, required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            style: _kMono,
            decoration: const InputDecoration(
                labelText: 'Region ID',
                hintText: 'e.g. aus_melbourne',
                prefixIcon: Icon(Icons.language, color: kMuted, size: 18)),
          ),
        ),
        const SizedBox(width: 10),
        IconActionButton(icon: Icons.list_alt, loading: loading, tooltip: 'Browse regions', onTap: onBrowse),
      ],
    );
  }
}

/// PIA username field (from main.dart `_buildUsernameField`).
class PiaUsernameField extends StatelessWidget {
  final TextEditingController controller;
  const PiaUsernameField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        style: _kMono,
        decoration: const InputDecoration(
            labelText: 'PIA username',
            hintText: 'e.g. p1234567',
            prefixIcon: Icon(Icons.person_outline, color: kMuted, size: 18)),
        autofillHints: const [AutofillHints.username],
        autocorrect: false,
        enableSuggestions: false,
      );
}

/// Under the DNS field wherever the servers become a stock slot's. Measured 2026-09-13: the firmware
/// redirects a device assigned to the VPN to the FIRST server (`VPN_FUSION` DNAT) and never tries the
/// second, so a first server that stops answering through that tunnel leaves the device reaching IP
/// addresses but not names.
const String kDnsFirstServerNote =
    'Devices assigned to this VPN use only the first server. If they reach IP addresses but not names, '
    'try a different first server.';

const String _kDnsExamples = 'Quad9: 9.9.9.9, 149.112.112.112 | Cloudflare: 1.1.1.1, 1.0.0.1';

/// DNS servers field (from main.dart `_buildDnsField`).
/// Said when a slot's DNS address is one the router uses for its OWN encrypted lookups (ID-005).
///
/// Information, not a warning: sharing the address is a reasonable thing to do deliberately, and
/// the app never changes either setting. What it costs is stated plainly, because the failure is
/// invisible from the app - a tunnel that looks connected and answers nothing takes name resolution
/// away from every device that has not been pinned to a slot.
const String kDnsMatchesRouterNote =
    'Your router uses this address for its own encrypted DNS. While this slot is running, the '
    "router's lookups, and those of every device you have not pinned, travel through it - and stop "
    'if it stops answering.';

class DnsField extends StatelessWidget {
  final TextEditingController controller;

  /// Adds [kDnsFirstServerNote] under the examples. Only where the servers become a stock slot's:
  /// STANDALONE's `.conf` goes to another client, which uses both servers.
  final bool firstServerNote;

  /// The router's own encrypted-DNS servers, from `RouterSlots.routerDotServers` (ID-005). Empty
  /// off stock, with DNS Privacy off, or wherever the caller has no router to ask - STANDALONE's
  /// config goes to another client entirely, so none of this applies there.
  final Set<String> routerDotServers;

  const DnsField({
    super.key,
    required this.controller,
    this.firstServerNote = false,
    this.routerDotServers = const {},
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        // Rebuilt as the field is typed into, so the note appears on the address that caused it
        // rather than after a save.
        valueListenable: controller,
        builder: (context, value, _) => _field(dnsSharedWithRouter(value.text, routerDotServers)),
      );

  Widget _field(Set<String> shared) => TextFormField(
        controller: controller,
        style: const TextStyle(color: kText, fontFamily: 'monospace', fontSize: 13),
        decoration: InputDecoration(
          labelText: 'DNS servers',
          hintText: kDefaultDns,
          prefixIcon: const Icon(Icons.dns_outlined, color: kMuted, size: 18),
          helperText: firstServerNote ? null : _kDnsExamples,
          helperStyle: const TextStyle(color: kHighlight, fontSize: 11),
          helperMaxLines: 6,
          // The notes in grey under the teal examples, so they read as a suggestion and then a
          // caution. The overlap note is amber: it is the one that can cost the whole house its DNS.
          helper: firstServerNote || shared.isNotEmpty
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(_kDnsExamples, style: TextStyle(color: kHighlight, fontSize: 11)),
                  if (firstServerNote) ...[
                    const SizedBox(height: 2),
                    const Text(kDnsFirstServerNote,
                        key: Key('dns_first_server_note'), style: TextStyle(color: kMuted, fontSize: 11)),
                  ],
                  if (shared.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('${shared.join(' and ')}: $kDnsMatchesRouterNote',
                        key: const Key('dns_matches_router_note'),
                        style: const TextStyle(color: kWarn, fontSize: 11)),
                  ],
                ])
              : null,
        ),
      );
}

/// Generic obscured (password-style) field with a show/hide toggle. State for [visible]
/// lives in the parent — matches the obscure pattern used everywhere in the app.
class ObscuredField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData prefixIcon;
  final bool visible;
  final VoidCallback onToggle;

  /// Passed through to the platform so a password manager can offer to fill this field. Empty
  /// means "no autofill" - on Android that is what an absent hint list already means.
  final List<String> autofillHints;
//  final bool enableInteractiveSelection; // disable copy if password field is revealed
  const ObscuredField({
    super.key,
    required this.controller,
    required this.label,
    required this.prefixIcon,
    required this.visible,
    required this.onToggle,
    this.autofillHints = const <String>[],
//    this.enableInteractiveSelection = true, // disable copy if password field is revealed
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        obscureText: !visible,
        autofillHints: autofillHints,
        style: _kMono,
//        enableInteractiveSelection: enableInteractiveSelection, // disable copy if password field is revealed
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(prefixIcon, color: kMuted, size: 18),
          suffixIcon: GestureDetector(
            onTap: onToggle,
            child: Icon(visible ? Icons.visibility_off : Icons.visibility, color: kMuted, size: 18),
          ),
        ),
        autocorrect: false,
        enableSuggestions: false,
      );
}

/// PIA password field (from main.dart `_buildPasswordField`).
class PiaPasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool visible;
  final VoidCallback onToggle;
  const PiaPasswordField({super.key, required this.controller, required this.visible, required this.onToggle});

  @override
  Widget build(BuildContext context) => ObscuredField(
        controller: controller,
        label: 'PIA password',
        prefixIcon: Icons.lock_outline,
        visible: visible,
        autofillHints: const [AutofillHints.password],
//        enableInteractiveSelection: false, // disable copy if password field is revealed
        onToggle: onToggle,
      );
}

/// Router IP field (from router_push.dart step 0).
class RouterIpField extends StatelessWidget {
  final TextEditingController controller;
  const RouterIpField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        style: _kMono,
        decoration: const InputDecoration(
          labelText: 'Router IP',
          // The SSH daemon does not have to be on 22, and the router's own WebUI encourages moving
          // it. Accepting host:port here keeps that on one line rather than adding a field that is
          // blank for almost everyone.
          hintText: '192.168.50.1  or  192.168.50.1:2222',
          prefixIcon: Icon(Icons.router, color: kMuted, size: 18),
        ),
      );
}

/// SSH username field (from router_push.dart step 0).
class SshUsernameField extends StatelessWidget {
  final TextEditingController controller;
  const SshUsernameField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        style: _kMono,
        decoration: const InputDecoration(labelText: 'SSH Username', prefixIcon: Icon(Icons.person, color: kMuted, size: 18)),
        autofillHints: const [AutofillHints.username],
      );
}

/// SSH password field (obscured, from router_push.dart step 0).
class SshPasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool visible;
  final VoidCallback onToggle;
  const SshPasswordField({super.key, required this.controller, required this.visible, required this.onToggle});

  @override
  Widget build(BuildContext context) => ObscuredField(
        controller: controller,
        label: 'SSH Password',
        prefixIcon: Icons.lock,
        visible: visible,
        autofillHints: const [AutofillHints.password],
//        enableInteractiveSelection: false, // disable copy if password field is revealed
        onToggle: onToggle,
      );
}

/// Small red destructive pill button (from main.dart `_ClearButton`).
class ClearButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const ClearButton({super.key, required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: const Color(0xFF2A1515),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: kError.withAlpha(128))),
        child: Row(
          children: [
            Icon(icon, size: 12, color: kError),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: kError, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          ],
        ),
      ),
    );
  }
}

/// Square 48×48 icon button with a loading spinner (from main.dart `_IconButton`).
class IconActionButton extends StatelessWidget {
  final IconData icon;
  final bool loading;
  final String tooltip;
  final VoidCallback onTap;
  const IconActionButton({super.key, required this.icon, required this.loading, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: kField, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
            child: loading
                ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2, color: kHighlight))
                : Icon(icon, color: kHighlight, size: 20),
          ),
        ),
      );
}

/// Slot status pill (from router_push.dart `_badge`).
class SlotBadge extends StatelessWidget {
  final String label;
  final Color text, border, bg;
  const SlotBadge({super.key, required this.label, required this.text, required this.border, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border, width: 0.5), borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: TextStyle(color: text, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.w600, letterSpacing: 0.5)),
    );
  }
}

/// Renders the in-memory application log (from main.dart `_LogPanel`).
///
/// The log is laid out in blocks of [LogPanel.blockSize] lines, each ONE `Text.rich`, and a block whose lines
/// have not changed is reused as it is (ID-004). Laying out the whole log as a single paragraph made every new
/// line cost the length of the log: measured with `tool/log_cap_probe.dart` on an emulator, one paragraph missed
/// a 16 ms frame at about 20,000 characters, blocks of 100 lines not until about 200,000.
///
/// Within a block the entries share one span tree, so a selection carries their line breaks: `SelectionArea`
/// joins the text of separate widgets with no separator, which is why this was never a widget per entry. The
/// blocks ARE separate widgets, so [_BlockJoiningDelegate] puts the line break back between them. The per-entry
/// icons are `WidgetSpan`s: a placeholder splits the paragraph into selectable fragments but contributes no
/// character of its own, so the copy stays clean.
class LogPanel extends StatefulWidget {
  final List<LogEntry> entries;
  const LogPanel({super.key, required this.entries});

  /// Lines per block: small enough that a new line is cheap, large enough that the blocks stay few.
  static const int blockSize = 100;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  static const TextStyle _style = TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.7);

  final _selection = _BlockJoiningDelegate();

  /// Block index to the first and last entry it was built from, and the widget. Entries are only ever appended
  /// or dropped from the front, so a block whose first and last entry are unchanged is unchanged.
  final Map<int, (LogEntry, LogEntry, Widget)> _blocks = {};

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  static Color _colour(LogEntry e) {
    if (e.isSuccess) return Colors.white;
    if (e.isError) return kError;
    if (e.isWarning) return kWarn;
    return kHighlight;
  }

  static IconData _icon(LogEntry e) {
    if (e.isSuccess) return Icons.check_circle_outline;
    if (e.isError) return Icons.error_outline;
    if (e.isWarning) return Icons.warning_amber_outlined;
    return Icons.info_outline;
  }

  static Widget _block(List<LogEntry> entries) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final colour = _colour(e);
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Icon(_icon(e), size: 12, color: colour),
        ),
      ));
      spans.add(TextSpan(text: e.message, style: _style.copyWith(color: colour)));
      if (i < entries.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return Text.rich(TextSpan(children: spans), style: _style);
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    if (entries.isEmpty) {
      _blocks.clear();
      return const SelectionArea(
        child: Text('Ready.', style: TextStyle(color: kHighlight, fontSize: 11, fontFamily: 'monospace')),
      );
    }
    final blocks = <Widget>[];
    for (var k = 0; k * LogPanel.blockSize < entries.length; k++) {
      final start = k * LogPanel.blockSize;
      final end = start + LogPanel.blockSize < entries.length ? start + LogPanel.blockSize : entries.length;
      final cached = _blocks[k];
      if (cached != null && identical(cached.$1, entries[start]) && identical(cached.$2, entries[end - 1])) {
        blocks.add(cached.$3);
        continue;
      }
      final block = _block(entries.sublist(start, end));
      _blocks[k] = (entries[start], entries[end - 1], block);
      blocks.add(block);
    }
    _blocks.removeWhere((k, _) => k >= blocks.length);
    return SelectionArea(
      child: SelectionContainer(
        delegate: _selection,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks),
      ),
    );
  }
}

/// Copies a selection that spans several blocks with a line break between them, as one paragraph would.
class _BlockJoiningDelegate extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final parts = [
      for (final selectable in selectables)
        if (selectable.getSelectedContent() case final SelectedContent content) content.plainText,
    ];
    return parts.isEmpty ? null : SelectedContent(plainText: parts.join('\n'));
  }
}
