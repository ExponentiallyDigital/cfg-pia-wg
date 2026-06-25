// screens/slot_params_editor.dart - WireGuard slot parameter editor (spec 2.1.2 EDIT + 3.3).
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
// Shown as a modal on top of the slot modal. Editable fields (spec 3.3): addr, alive, desc, dns,
// enforce, ep_addr, ep_port, fw, mtu, nat, ppub, priv (obscured), aips. Read-only: enable,
// ep_addr_r, psk, rip. SAVE is disabled until every editable text field is non-empty.

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../widgets/common_fields.dart';

// Default values for editable fields that have one (spec 3.3), pre-filled when NVRAM is blank.
const Map<String, String> _kEditableDefaults = {
  'alive': '25',
  'dns': '9.9.9.9, 149.112.112.112',
  'ep_port': '1337',
  'mtu': '1420',
  'aips': '0.0.0.0/0',
};

class SlotParamsEditor extends StatefulWidget {
  final int slot;
  final Map<String, String> initial; // bare-keyed nvram values (addr, alive, ...)
  final Future<void> Function(Map<String, String> editableParams) onSave;
  const SlotParamsEditor({super.key, required this.slot, required this.initial, required this.onSave});

  @override
  State<SlotParamsEditor> createState() => _SlotParamsEditorState();
}

class _SlotParamsEditorState extends State<SlotParamsEditor> {
  // Editable text fields (key -> controller).
  static const _textKeys = ['addr', 'alive', 'desc', 'dns', 'ep_addr', 'ep_port', 'mtu', 'ppub', 'priv', 'aips'];
  final _ctrls = <String, TextEditingController>{};

  // Editable boolean (1/0) fields.
  late bool _enforce, _fw, _nat;
  bool _privVisible = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final k in _textKeys) {
      final v = (widget.initial[k] ?? '').isNotEmpty ? widget.initial[k]! : (_kEditableDefaults[k] ?? '');
      _ctrls[k] = TextEditingController(text: v)..addListener(() => setState(() {}));
    }
    _enforce = widget.initial['enforce'] == '1';
    _fw = widget.initial['fw'] == '1';
    _nat = widget.initial['nat'] == '1';
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSave => _textKeys.every((k) => _ctrls[k]!.text.trim().isNotEmpty);

  Future<void> _save() async {
    final params = <String, String>{
      for (final k in _textKeys) k: _ctrls[k]!.text.trim(),
      'enforce': _enforce ? '1' : '0',
      'fw': _fw ? '1' : '0',
      'nat': _nat ? '1' : '0',
    };
    setState(() => _saving = true);
    try {
      await widget.onSave(params);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('EDIT wgc${widget.slot}',
                    style: const TextStyle(color: kHighlight, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                const SizedBox(height: 16),
                _text('addr', 'Local tunnel IP (CIDR)', hint: 'e.g. 10.x.x.x/32'),
                _text('desc', 'Region name', hint: 'must match the PIA region for the watchdog'),
                _text('ep_addr', 'Endpoint (FQDN or IP)'),
                _text('ep_port', 'Endpoint port', keyboard: TextInputType.number),
                _text('ppub', 'Server public key'),
                _privField(),
                _text('dns', 'DNS servers'),
                _text('mtu', 'MTU', keyboard: TextInputType.number),
                _text('alive', 'Persistent keepalive (s)', keyboard: TextInputType.number),
                _text('aips', 'Allowed IPs'),
                const SizedBox(height: 4),
                _switch('Kill switch', _enforce, (v) => setState(() => _enforce = v), const Key('slot_enforce')),
                _switch('Inbound firewall', _fw, (v) => setState(() => _fw = v), const Key('slot_fw')),
                _switch('NAT', _nat, (v) => setState(() => _nat = v), const Key('slot_nat')),
                const SizedBox(height: 8),
                _readOnly('Enabled (enable)', widget.initial['enable'] ?? ''),
                _readOnly('Resolved endpoint IP (ep_addr_r)', widget.initial['ep_addr_r'] ?? ''),
                _readOnly('Preshared key (psk, unused by PIA)', widget.initial['psk'] ?? ''),
                _readOnly('Router public IP (rip)', widget.initial['rip'] ?? ''),
                const SizedBox(height: 16),
                ElevatedButton(
                  key: const Key('slot_params_save'),
                  onPressed: (_saving || !_canSave) ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kOnPrimary))
                      : const Text('SAVE'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('CANCEL', style: TextStyle(color: kMuted)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _text(String key, String label, {String? hint, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextField(
        key: Key('slot_$key'),
        controller: _ctrls[key],
        keyboardType: keyboard,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(color: kText, fontFamily: 'monospace', fontSize: 13),
        decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
      ),
    );
  }

  Widget _privField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ObscuredField(
        key: const Key('slot_priv'),
        controller: _ctrls['priv']!,
        label: 'Client private key',
        prefixIcon: Icons.key,
        visible: _privVisible,
        onToggle: () => setState(() => _privVisible = !_privVisible),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged, Key key) {
    return SwitchListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(color: kText, fontSize: 13)),
      value: value,
      onChanged: _saving ? null : onChanged,
    );
  }

  Widget _readOnly(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(label, style: const TextStyle(color: kMuted, fontSize: 11))),
          Expanded(
            flex: 5,
            child: Text(value.isEmpty ? '(unset)' : value,
                style: const TextStyle(color: kText, fontFamily: 'monospace', fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
