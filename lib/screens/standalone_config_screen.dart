// screens/standalone_config_screen.dart - "Generate standalone PIA WireGuard configuration" (2.1.1).
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
// Reuses PiaService for generation; PIA credentials/DNS are read from and written back to the shared
// SessionController so they pre-fill the router and watchdog screens (spec 2.1.1). The old 180s
// session timer is gone (replaced by the global 10-minute idle wipe); the 60s clipboard auto-clear
// lives in the controller and keeps running after leaving the screen.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_colors.dart';
import '../pia_service.dart';
import '../session_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common_fields.dart';
import '../widgets/error_presenter.dart';
import '../widgets/region_picker_sheet.dart';

class StandaloneConfigScreen extends StatefulWidget {
  final PiaService? service;
  const StandaloneConfigScreen({super.key, this.service});

  @override
  State<StandaloneConfigScreen> createState() => _StandaloneConfigScreenState();
}

class _StandaloneConfigScreenState extends State<StandaloneConfigScreen> {
  late final PiaService _service = widget.service ?? PiaService();
  final _regionCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _dnsCtrl = TextEditingController();

  bool _passwordVisible = false, _loading = false, _loadingRegions = false, _prefilled = false;
  late SessionController _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = SessionScope.of(context);
    if (!_prefilled) {
      _prefilled = true;
      _usernameCtrl.text = _controller.piaUsername;
      _passwordCtrl.text = _controller.piaPassword;
      _dnsCtrl.text = _controller.dns;
      _usernameCtrl.addListener(_onCredChanged);
      _passwordCtrl.addListener(_onCredChanged);
      _dnsCtrl.addListener(() => _controller.dns = _dnsCtrl.text);
      _regionCtrl.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_regionCtrl, _usernameCtrl, _passwordCtrl, _dnsCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // Mirror PIA credentials into the shared session so other screens pre-fill them.
  void _onCredChanged() {
    _controller.piaUsername = _usernameCtrl.text;
    _controller.piaPassword = _passwordCtrl.text;
    setState(() {});
  }

  bool get _canGenerate =>
      _regionCtrl.text.trim().isNotEmpty &&
      _usernameCtrl.text.trim().isNotEmpty &&
      _passwordCtrl.text.trim().isNotEmpty;

  Future<void> _loadRegions() async {
    setState(() => _loadingRegions = true);
    _controller.logEntry('Loading regions...');
    try {
      final regions = await _service.fetchRegions(onProgress: _controller.onLog);
      if (!mounted) return;
      final total = regions.fold<int>(0, (s, r) => s + r.wgServers.length);
      _controller.logEntry('Loaded ${regions.length} regions ($total servers).');
      // Launch the sheet but do NOT await it here, otherwise the browse-button spinner would keep
      // animating until the sheet closes. enterModal/exitModal bracket the sheet's lifetime.
      _controller.enterModal();
      RegionPickerSheet.show(context, regions: regions, onSelected: (id) => setState(() => _regionCtrl.text = id))
          .whenComplete(() {
        if (mounted) _controller.exitModal();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingRegions = false); // stop the spinner before the (awaited) error modal
        await AppErrors.system(context, _controller, 'Failed to load regions: ${e.toString().replaceAll('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _loadingRegions = false);
    }
  }

  Future<void> _generate() async {
    final region = _regionCtrl.text.trim(),
        username = _usernameCtrl.text.trim(),
        password = _passwordCtrl.text.trim(),
        dns = _dnsCtrl.text.trim();

    final errors = <String>[];
    if (region.isEmpty) errors.add('Region is required.');
    if (username.isEmpty) errors.add('PIA username is required.');
    if (password.isEmpty) errors.add('PIA password is required.');
    if (errors.isNotEmpty) {
      await AppErrors.inputs(context, _controller, errors);
      return;
    }

    setState(() => _loading = true);
    _controller.setGeneratedConfig(null, region);
    _controller.logEntry('Starting...');
    try {
      final config =
          await _service.generateConfig(region: region, username: username, password: password, dns: dns, onProgress: _controller.onLog);
      if (!mounted) return;
      _controller.setGeneratedConfig(config, region);
      _controller.logEntry('Config generated successfully.', isSuccess: true);
    } catch (e) {
      if (mounted) await AppErrors.system(context, _controller, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy(String config) async {
    await _controller.copyToClipboard(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Config copied'), backgroundColor: kHighlight));
    }
  }

  Future<void> _share(String config) async {
    final region = _controller.generatedRegionId.isEmpty ? _regionCtrl.text.trim() : _controller.generatedRegionId;
    final filename = 'pia-$region.conf';
    final dir = await getTemporaryDirectory();
    final tempFile = File('${dir.path}/$filename');
    try {
      await tempFile.writeAsString(config, flush: true);
      await SharePlus.instance.share(
          ShareParams(files: [XFile(tempFile.path, mimeType: 'text/plain')], subject: filename, text: 'PIA Config: $region'));
    } catch (e) {
      if (mounted) await AppErrors.system(context, _controller, 'Could not share file: $e');
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RegionRow(controller: _regionCtrl, loading: _loadingRegions, onBrowse: _loadRegions),
          const SizedBox(height: 16),
          PiaUsernameField(controller: _usernameCtrl),
          const SizedBox(height: 12),
          PiaPasswordField(
            controller: _passwordCtrl,
            visible: _passwordVisible,
            onToggle: () => setState(() => _passwordVisible = !_passwordVisible),
          ),
          const SizedBox(height: 16),
          DnsField(controller: _dnsCtrl),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('generate_config'),
              onPressed: (_loading || !_canGenerate) ? null : _generate,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kOnPrimary))
                  : const Text('GENERATE CONFIG'),
            ),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final config = _controller.generatedConfig;
              if (config == null) return const SizedBox.shrink();
              return _GeneratedConfigSection(
                config: config,
                clipboardSeconds: _controller.clipboardSeconds,
                onCopy: () => _copy(config),
                onShare: () => _share(config),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GeneratedConfigSection extends StatelessWidget {
  final String config;
  final int clipboardSeconds;
  final VoidCallback onCopy, onShare;
  const _GeneratedConfigSection({
    required this.config,
    required this.clipboardSeconds,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text('GENERATED CONFIG',
            style: TextStyle(color: kHighlight, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration:
              BoxDecoration(color: kConfigBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kHighlight)),
          child: SelectableText(config,
              key: const Key('generated_config_text'),
              style: const TextStyle(color: kHighlight, fontFamily: 'monospace', fontSize: 11, height: 1.6)),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('COPY'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: kHighlight,
                        side: const BorderSide(color: kHighlight),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                  if (clipboardSeconds > 0) ...[
                    const SizedBox(height: 6),
                    Text('Clearing clipboard in $clipboardSeconds seconds',
                        style: const TextStyle(color: kError, fontSize: 10, fontFamily: 'monospace'), textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.share, size: 16),
                label: const Text('SHARE / SAVE'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: kHighlight,
                    side: const BorderSide(color: kHighlight),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
