// screens/router_log_screen.dart - the router's own syslog, read over the shared SSH session.
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
// Every alert email and half the failure messages in this app end with "check your router log",
// which until now meant leaving the app for an SSH client or the web interface. The watchdog's own
// lines are in here alongside the firmware's, so a reconfigure can be read in the context of
// whatever the router was doing at the time.
//
// Opens on the newest lines and pages BACKWARDS on demand - see router_log_paging.dart for why,
// and for which bytes each page covers.

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../router_command.dart';
import '../router_log_paging.dart';
import '../router_slot_service.dart' show openSshClient;
import '../session_controller.dart';
import '../widgets/app_drawer.dart' show navigateToDestination;
import '../widgets/error_presenter.dart';
import '../widgets/log_buttons.dart';
import '../widgets/ssh_creds_dialog.dart';

class RouterLogScreen extends StatefulWidget {
  /// Injected by tests so the screen can be driven without a router.
  final Future<SSHClient> Function(String ip, String user, String pass)? testClientFactory;
  const RouterLogScreen({super.key, this.testClientFactory});

  @override
  State<RouterLogScreen> createState() => _RouterLogScreenState();
}

class _RouterLogScreenState extends State<RouterLogScreen> {
  late SessionController _c;
  final _scroll = ScrollController();

  /// Loaded pages, OLDEST first, so the column renders in reading order top to bottom.
  final List<String> _pages = [];

  /// Bytes already read from each file in [kRouterLogFiles], and how big each of those is.
  List<int> _consumed = [0, 0];
  List<int> _sizes = [0, 0];

  bool _loading = false, _started = false, _exhausted = false;
  bool get _hasContent => _pages.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c = SessionScope.of(context);
    if (_started) return;
    _started = true;
    // Fetch on entry rather than making the user press REFRESH to see anything at all. Prompts for
    // credentials when the session has none, because this screen has no other purpose - unlike
    // ABOUT, where arriving is not a statement of intent to touch the router.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh(prompt: true);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Fetches the next older page when the reader gets near the top of what is loaded.
  ///
  /// 200 pixels of warning rather than waiting for offset zero, so the page usually arrives before
  /// the reader reaches the end of the text.
  void _onScroll() {
    if (_loading || _exhausted || !_scroll.hasClients) return;
    if (_scroll.offset <= 200) _loadOlder();
  }

  /// The credentials to use, asking for them when the session has none.
  Future<(String, String, String)?> _credentials({required bool prompt}) async {
    if (_c.canReuseRouterSession) return (_c.routerIp.trim(), _c.sshUsername.trim(), _c.sshPassword);
    if (!prompt) return null;
    final entered = await showDialog<(String, String, String)?>(
      context: context,
      builder: (_) => SshCredsDialog(
        initialIp: _c.routerIpPrefill,
        initialUser: _c.sshUsername.trim(),
        initialPass: _c.sshPassword,
      ),
    );
    if (entered == null || !mounted) return null;
    _c
      ..routerIp = entered.$1
      ..sshUsername = entered.$2
      ..sshPassword = entered.$3;
    return entered;
  }

  SSHClient _client(String ip, String user, String pass) =>
      _c.routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));

  /// Starts again from the newest page. Also what REFRESH does.
  Future<void> _refresh({bool prompt = false}) async {
    final creds = await _credentials(prompt: prompt);
    if (creds == null || !mounted) return;
    final (ip, user, pass) = creds;

    setState(() => _loading = true);
    String? error;
    List<int>? sizes;
    String? first;
    LogPage? page;
    try {
      final client = _client(ip, user, pass);
      sizes = parseLogSizes((await runRouterCommand(client, buildLogSizesCommand(), allowFailure: true)).stdout);
      page = nextLogPage(sizes: sizes, consumed: [0, 0]);
      if (page != null) {
        first = (await runRouterCommand(client, page.command, allowFailure: true)).stdout;
      }
      _c.routerConnected = true;
      await _c.rememberRouterIp(ip);
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
    }
    if (!mounted) return;
    final loaded = page;
    setState(() {
      _loading = false;
      if (error != null) return;
      _sizes = sizes ?? [0, 0];
      _consumed = [0, 0];
      _pages.clear();
      _exhausted = loaded == null;
      if (loaded != null && first != null) {
        _pages.add(trimPartialFirstLine(first, reachesStart: loaded.reachesStart));
        _consumed[kRouterLogFiles.indexOf(loaded.file)] = loaded.length;
        _exhausted = nextLogPage(sizes: _sizes, consumed: _consumed) == null;
      }
    });
    // The newest lines are at the BOTTOM of a syslog, and they are what anyone opening this screen
    // came for. Jumping after the frame that laid the text out, so the extent is known.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
    if (error != null && mounted) await AppErrors.system(context, _c, 'Could not read the router log: $error');
  }

  /// Fetches one page older than everything loaded, and inserts it ABOVE without moving the view.
  Future<void> _loadOlder() async {
    final page = nextLogPage(sizes: _sizes, consumed: _consumed);
    if (page == null) {
      setState(() => _exhausted = true);
      return;
    }
    final creds = await _credentials(prompt: false);
    if (creds == null || !mounted) return;
    final (ip, user, pass) = creds;

    setState(() => _loading = true);
    // Everything below the insertion point shifts down by the height of what we add, so the scroll
    // offset has to move with it or the reader is thrown backwards mid-sentence. maxScrollExtent
    // grows by exactly that height, which is why the difference is the right correction.
    final before = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    String? text;
    String? error;
    try {
      text = (await runRouterCommand(_client(ip, user, pass), page.command, allowFailure: true)).stdout;
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (error != null || text == null) return;
      _pages.insert(0, trimPartialFirstLine(text, reachesStart: page.reachesStart));
      _consumed[kRouterLogFiles.indexOf(page.file)] += page.length;
      _exhausted = nextLogPage(sizes: _sizes, consumed: _consumed) == null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final delta = _scroll.position.maxScrollExtent - before;
      if (delta > 0) _scroll.jumpTo(_scroll.offset + delta);
    });
    if (error != null && mounted) await AppErrors.system(context, _c, 'Could not read more of the router log: $error');
  }

  /// Copies everything loaded so far.
  ///
  /// Android puts its own Copy/Share toolbar wherever the selection is, which on a full-height
  /// selection lands on top of these buttons - reported 2026-09-10, when a tap meant for Copy
  /// cleared the watchdog log instead. An in-app copy removes the need for the system toolbar in
  /// the one case where it gets in the way. armAutoClear: false - a log is not a credential, and
  /// the 60-second wipe would take back what was just copied.
  Future<void> _copy() async {
    await _c.copyToClipboard(_pages.join(), armAutoClear: false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Router log copied.')));
    }
  }

  /// One page, with the app's own lines picked out by colour.
  ///
  /// A syslog page is a wall of identical grey, and the lines anyone opens this screen for are a
  /// handful among hundreds. Built as ONE `Text.rich` per page rather than a widget per line, so
  /// the whole page stays a single selectable run and COPY still yields the text as it reads.
  static Widget _colourise(String page) {
    const base = TextStyle(color: kText, fontSize: 11, fontFamily: 'monospace');
    final lines = page.split('\n');
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < lines.length; i++)
          TextSpan(
            text: i == lines.length - 1 ? lines[i] : '${lines[i]}\n',
            style: switch (classifyLogLine(lines[i])) {
              RouterLogSource.app => const TextStyle(color: kHighlight),
              RouterLogSource.watchdog => const TextStyle(color: kWarn),
              RouterLogSource.other => null,
            },
          ),
      ]),
      style: base,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kBg,
      child: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: !_hasContent
                ? Center(
                    child: _loading
                        ? const CircularProgressIndicator(color: kHighlight)
                        : const Text('No log read yet.', style: TextStyle(color: kMuted, fontSize: 13)),
                  )
                // One selection region over every loaded page, so "select all" spans the lot. A
                // lazily-built list would page more cheaply and would not do that.
                : SelectionArea(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: kHighlight),
                              ),
                            ),
                          )
                        else if (_exhausted)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('- start of the router log -',
                                textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 11)),
                          ),
                        for (final page in _pages) _colourise(page),
                      ]),
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: LogButtonRow(children: [
            LogButton(keyValue: 'router_log_copy', label: 'COPY', onPressed: _hasContent ? _copy : null),
            LogButton(
              keyValue: 'router_log_refresh',
              label: 'REFRESH',
              busy: _loading,
              onPressed: _loading ? null : () => _refresh(prompt: true),
            ),
            LogButton(
              keyValue: 'router_log_home',
              label: 'HOME',
              onPressed: () => navigateToDestination(context, _c, AppDestination.menu),
            ),
          ]),
        ),
      ]),
    );
  }
}
