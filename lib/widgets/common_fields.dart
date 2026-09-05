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

import '../app_colors.dart';
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

/// DNS servers field (from main.dart `_buildDnsField`).
class DnsField extends StatelessWidget {
  final TextEditingController controller;
  const DnsField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        style: const TextStyle(color: kText, fontFamily: 'monospace', fontSize: 13),
        decoration: const InputDecoration(
          labelText: 'DNS servers',
          hintText: kDefaultDns,
          prefixIcon: Icon(Icons.dns_outlined, color: kMuted, size: 18),
          helperText: 'Quad9: 9.9.9.9, 149.112.112.112 | Cloudflare: 1.1.1.1, 1.0.0.1',
          helperStyle: TextStyle(color: kHighlight, fontSize: 11),
          helperMaxLines: 2, // <-- allows wrapping on small screens
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
        decoration: const InputDecoration(labelText: 'Router IP', prefixIcon: Icon(Icons.router, color: kMuted, size: 18)),
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
/// The whole log is ONE `Text.rich` rather than a widget per entry. `SelectionArea` joins the text
/// of separate widgets with no separator, so a widget-per-entry layout copies as one run-on line
/// ("...via SSH...[10:19:34] Router firmware..."). Keeping the entries in a single span tree puts
/// the line breaks inside the text, where a selection carries them. Same fix as the About screen's
/// build info block. The per-entry icons are `WidgetSpan`s: a placeholder splits the paragraph into
/// selectable fragments but contributes no character of its own, so the copy stays clean.
class LogPanel extends StatelessWidget {
  final List<LogEntry> entries;
  const LogPanel({super.key, required this.entries});

  static const TextStyle _style = TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.7);

  static Color _colour(LogEntry e) {
    if (e.isSuccess) return Colors.white;
    if (e.isError) return kError;
    return kHighlight;
  }

  static IconData _icon(LogEntry e) {
    if (e.isSuccess) return Icons.check_circle_outline;
    if (e.isError) return Icons.error_outline;
    return Icons.info_outline;
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SelectionArea(
        child: Text('Ready.', style: TextStyle(color: kHighlight, fontSize: 11, fontFamily: 'monospace')),
      );
    }
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
    return SelectionArea(child: Text.rich(TextSpan(children: spans), style: _style));
  }
}
