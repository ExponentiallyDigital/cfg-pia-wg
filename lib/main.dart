// main.dart
// PIA WireGuard Config Generator -- Flutter Android APK
// GUI equivalent of https://github.com/ExponentiallyDigital/pia-wireguard-cfg

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'pia_service.dart';

void main() {
  runApp(const PiaWgApp());
}

class PiaWgApp extends StatelessWidget {
  const PiaWgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PIA WireGuard Config',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D4AA),
          secondary: Color(0xFF00A882),
          surface: Color(0xFF1A1D23),
          error: Color(0xFFFF5C5C),
          onPrimary: Color(0xFF12141A),
          onSurface: Color(0xFFE8EAF0),
        ),
        useMaterial3: true,
        fontFamily: 'monospace',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E2128),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF2E3240)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF2E3240)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF00D4AA), width: 1.5),
          ),
          labelStyle: const TextStyle(color: Color(0xFF8892A4)),
          hintStyle: const TextStyle(color: Color(0xFF4A5268)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00D4AA),
            foregroundColor: const Color(0xFF12141A),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Log entry model
// ---------------------------------------------------------------------------
class _LogEntry {
  final String message;
  final bool isError;
  _LogEntry(this.message, {this.isError = false});
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final _service = PiaService();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _regionCtrl = TextEditingController();
  final _dnsCtrl = TextEditingController(text: '9.9.9.9, 149.112.112.112');

  // The ScrollController drives the ONE outer SingleChildScrollView.
  // The log panel is just a Column inside it -- no nested scroll views.
  final _scrollCtrl = ScrollController();

  bool _passwordVisible = false;
  bool _loading = false;
  bool _loadingRegions = false;
  String? _generatedConfig;
  List<Region> _regions = [];

  // Log entries -- rendered as a plain Column, never a nested ListView
  final List<_LogEntry> _log = [];

  // ---------------------------------------------------------------------------
  // Safety auto-wipe timer (wall-clock deadline based)
  // ---------------------------------------------------------------------------
  static const _timeoutSeconds = 180;
  Timer? _wipeTimer;
  DateTime? _wipeDeadline;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wipeTimer?.cancel();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _regionCtrl.dispose();
    _dnsCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle -- correct countdown when returning from background
  // ---------------------------------------------------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _wipeDeadline != null &&
        _generatedConfig != null) {
      final remaining = _wipeDeadline!.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        _clearSession();
      } else {
        if (mounted) setState(() => _secondsRemaining = remaining);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Log helpers -- append to list and scroll to bottom after frame
  // ---------------------------------------------------------------------------
  void _logEntry(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() => _log.add(_LogEntry(message, isError: isError)));
    // Scroll the outer SingleChildScrollView to the bottom so the new
    // log line is visible without the user needing to scroll manually.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _logInfo(String msg) => _logEntry(msg);
  void _logError(String msg) => _logEntry(msg, isError: true);

  // Passed as onProgress callback to PiaService
  void _onProgress(String msg) => _logInfo(msg);

  // ---------------------------------------------------------------------------
  // Clear session
  // ---------------------------------------------------------------------------
  void _clearSession() {
    _wipeTimer?.cancel();
    _wipeTimer = null;
    _wipeDeadline = null;
    _usernameCtrl.text = '';
    _passwordCtrl.text = '';
    setState(() {
      _generatedConfig = null;
      _secondsRemaining = 0;
      _passwordVisible = false;
    });
    _logInfo('Session cleared.');
  }

  // ---------------------------------------------------------------------------
  // Wall-clock wipe timer
  // ---------------------------------------------------------------------------
  void _startOrResetTimer() {
    _wipeTimer?.cancel();
    _wipeDeadline = DateTime.now().add(const Duration(seconds: _timeoutSeconds));
    _secondsRemaining = _timeoutSeconds;

    _wipeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = _wipeDeadline!.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        timer.cancel();
        _clearSession();
      } else {
        setState(() => _secondsRemaining = remaining);
      }
    });
  }

  void _onUserInteraction(PointerEvent _) {
    if (_generatedConfig != null && _wipeTimer != null) {
      _startOrResetTimer();
    }
  }

  // ---------------------------------------------------------------------------
  // Load regions
  // ---------------------------------------------------------------------------
  Future<void> _loadRegions() async {
    setState(() => _loadingRegions = true);
    _logInfo('Loading regions...');
    try {
      final regions = await _service.fetchRegions(onProgress: _onProgress);
      if (!mounted) return;
      setState(() => _regions = regions);
      _logInfo('Loaded ${regions.length} regions.');
      _showRegionPicker();
    } on TimeoutException {
      if (!mounted) return;
      _logError('Region list request timed out. Check your connection.');
    } catch (e) {
      if (!mounted) return;
      _logError('Failed to load regions: $e');
    } finally {
      if (mounted) setState(() => _loadingRegions = false);
    }
  }

  void _showRegionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1D23),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) => _RegionPickerSheet(
        regions: _regions,
        onSelected: (id) {
          _regionCtrl.text = id;
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Generate config
  // ---------------------------------------------------------------------------
  Future<void> _generate() async {
    final region = _regionCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final dns = _dnsCtrl.text.trim();

    if (region.isEmpty || username.isEmpty || password.isEmpty) {
      _logError('Region, username, and password are all required.');
      return;
    }

    setState(() {
      _loading = true;
      _generatedConfig = null;
    });
    _logInfo('Starting...');

    try {
      final config = await _service.generateConfig(
        region: region,
        username: username,
        password: password,
        dns: dns.isEmpty ? '9.9.9.9, 149.112.112.112' : dns,
        onProgress: _onProgress,
      );
      if (!mounted) return;
      setState(() => _generatedConfig = config);
      _logInfo('Config generated successfully.');
      _startOrResetTimer();
    } on TimeoutException catch (e) {
      if (!mounted) return;
      _logError('Request timed out: $e');
    } catch (e) {
      if (!mounted) return;
      _logError('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Share via system share sheet
  // ---------------------------------------------------------------------------
  Future<void> _shareConfig() async {
    if (_generatedConfig == null) return;
    final region = _regionCtrl.text.trim();
    final filename = 'pia-$region.conf';
    final dir = await getTemporaryDirectory();
    final tempFile = File('${dir.path}/$filename');
    try {
      await tempFile.writeAsString(_generatedConfig!, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path, mimeType: 'text/plain')],
          subject: filename,
          text: 'PIA WireGuard config for region: $region',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _logError('Could not share file: $e');
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  Future<void> _copyToClipboard() async {
    if (_generatedConfig == null) return;
    await Clipboard.setData(ClipboardData(text: _generatedConfig!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Config copied to clipboard'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF00D4AA),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onUserInteraction,
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor: const Color(0xFF12141A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1D23),
          elevation: 0,
          title: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF00D4AA),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'PIA WireGuard Config',
                style: TextStyle(
                  color: Color(0xFFE8EAF0),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final label =
                        snapshot.hasData ? 'v${snapshot.data!.version}' : 'v...';
                    return Text(label,
                        style: const TextStyle(
                            color: Color(0xFF8892A4), fontSize: 11));
                  },
                ),
              ),
            ),
          ],
        ),
        // The entire page is ONE SingleChildScrollView.
        // The log panel is a plain Column at the bottom -- no nested scrolling.
        body: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- REGION ----
                const _SectionLabel('REGION'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _regionCtrl,
                        style: const TextStyle(
                          color: Color(0xFFE8EAF0),
                          fontFamily: 'monospace',
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Region ID',
                          hintText: 'e.g. aus_melbourne',
                          prefixIcon: Icon(Icons.language,
                              color: Color(0xFF8892A4), size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _IconButton(
                      icon: Icons.list_alt,
                      loading: _loadingRegions,
                      tooltip: 'Browse regions',
                      onTap: _loadRegions,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ---- CREDENTIALS ----
                const _SectionLabel('CREDENTIALS'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _usernameCtrl,
                  style: const TextStyle(
                    color: Color(0xFFE8EAF0),
                    fontFamily: 'monospace',
                  ),
                  decoration: const InputDecoration(
                    labelText: 'PIA Username',
                    hintText: 'e.g. p1234567',
                    prefixIcon: Icon(Icons.person_outline,
                        color: Color(0xFF8892A4), size: 18),
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: !_passwordVisible,
                  style: const TextStyle(
                    color: Color(0xFFE8EAF0),
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    labelText: 'PIA Password',
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: Color(0xFF8892A4), size: 18),
                    suffixIcon: GestureDetector(
                      onTap: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                      child: Icon(
                        _passwordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: const Color(0xFF8892A4),
                        size: 18,
                      ),
                    ),
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 20),

                // ---- DNS ----
                const _SectionLabel('DNS SERVERS'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _dnsCtrl,
                  style: const TextStyle(
                    color: Color(0xFFE8EAF0),
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'DNS',
                    hintText: '9.9.9.9, 149.112.112.112',
                    prefixIcon: Icon(Icons.dns_outlined,
                        color: Color(0xFF8892A4), size: 18),
                    helperText:
                        'Quad9 default  |  Cloudflare: 1.1.1.1, 1.0.0.1',
                    helperStyle:
                        TextStyle(color: Color(0xFF4A5268), fontSize: 11),
                  ),
                ),
                const SizedBox(height: 28),

                // ---- GENERATE BUTTON ----
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _generate,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF12141A),
                            ),
                          )
                        : const Text('GENERATE CONFIG'),
                  ),
                ),

                // ---- GENERATED CONFIG ----
                if (_generatedConfig != null) ...[
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const _SectionLabel('GENERATED CONFIG'),
                      const Spacer(),
                      if (_secondsRemaining > 0) ...[
                        Icon(
                          Icons.timer_outlined,
                          size: 12,
                          color: _secondsRemaining <= 30
                              ? const Color(0xFFFF5C5C)
                              : const Color(0xFF4A5268),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_secondsRemaining}s',
                          style: TextStyle(
                            color: _secondsRemaining <= 30
                                ? const Color(0xFFFF5C5C)
                                : const Color(0xFF4A5268),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      GestureDetector(
                        onTap: _clearSession,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A1515),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFFF5C5C)
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 12, color: Color(0xFFFF5C5C)),
                              SizedBox(width: 4),
                              Text(
                                'CLEAR',
                                style: TextStyle(
                                  color: Color(0xFFFF5C5C),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1016),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: const Color(0xFF00D4AA), width: 1),
                    ),
                    child: SelectableText(
                      _generatedConfig!,
                      style: const TextStyle(
                        color: Color(0xFF00D4AA),
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyToClipboard,
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('COPY'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00D4AA),
                            side: const BorderSide(color: Color(0xFF00D4AA)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _shareConfig,
                          icon: const Icon(Icons.share, size: 16),
                          label: const Text('SHARE / SAVE'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00D4AA),
                            side: const BorderSide(color: Color(0xFF00D4AA)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // ---- LOG PANEL ----
                // Always present regardless of app state.
                // Rendered as a plain Column -- no nested ListView or
                // ConstrainedBox. The outer SingleChildScrollView handles
                // all scrolling so log lines always appear inline and are
                // never clipped or rendered out of position.
                const SizedBox(height: 32),
                _LogPanel(entries: _log, onClearLog: () {
                  setState(() => _log.clear());
                }),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Region picker bottom sheet
// ---------------------------------------------------------------------------
class _RegionPickerSheet extends StatefulWidget {
  final List<Region> regions;
  final void Function(String) onSelected;
  const _RegionPickerSheet(
      {required this.regions, required this.onSelected});

  @override
  State<_RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<_RegionPickerSheet> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.regions
        .where((r) => r.id.toLowerCase().contains(_filter.toLowerCase()))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2E3240),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              style: const TextStyle(
                  color: Color(0xFFE8EAF0), fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Filter regions...',
                prefixIcon: const Icon(Icons.search,
                    color: Color(0xFF8892A4), size: 18),
                filled: true,
                fillColor: const Color(0xFF1E2128),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2E3240)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2E3240)),
                ),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final region = filtered[i];
                return InkWell(
                  onTap: () => widget.onSelected(region.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.chevron_right,
                            color: Color(0xFF00D4AA), size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            region.id,
                            style: const TextStyle(
                              color: Color(0xFFE8EAF0),
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          '${region.wgServers.length} server'
                          '${region.wgServers.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                              color: Color(0xFF4A5268), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small helper widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFF4A5268),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      );
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final bool loading;
  final String tooltip;
  final VoidCallback onTap;
  const _IconButton(
      {required this.icon,
      required this.loading,
      required this.tooltip,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF1E2128),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2E3240)),
            ),
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF00D4AA)),
                  )
                : Icon(icon, color: const Color(0xFF00D4AA), size: 20),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Log panel
//
// Key design decision: log entries are rendered as a plain Column, NOT a
// ListView. This avoids the shrinkWrap+ConstrainedBox trap that caused log
// lines to escape their container and float over the top of the screen.
// The outer SingleChildScrollView handles all page scrolling including the
// log area, so the panel simply grows downward with each new entry.
//
// A "CLEAR LOG" button appears in the header once entries exist.
// ---------------------------------------------------------------------------
class _LogPanel extends StatelessWidget {
  final List<_LogEntry> entries;
  final VoidCallback onClearLog;

  const _LogPanel({required this.entries, required this.onClearLog});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D23),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2E3240)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Text(
                'LOG',
                style: TextStyle(
                  color: Color(0xFF4A5268),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              if (entries.isNotEmpty)
                GestureDetector(
                  onTap: onClearLog,
                  child: const Text(
                    'CLEAR LOG',
                    style: TextStyle(
                      color: Color(0xFF4A5268),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Log body -- plain Column, grows with content
          if (entries.isEmpty)
            const Text(
              'Ready.',
              style: TextStyle(
                color: Color(0xFF4A5268),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            )
          else
            // Each entry is its own Row with icon + text, separated by 4dp
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        entry.isError
                            ? Icons.error_outline
                            : Icons.info_outline,
                        size: 12,
                        color: entry.isError
                            ? const Color(0xFFFF5C5C)
                            : const Color(0xFF00D4AA),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.message,
                          style: TextStyle(
                            color: entry.isError
                                ? const Color(0xFFFF5C5C)
                                : const Color(0xFF00D4AA),
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
