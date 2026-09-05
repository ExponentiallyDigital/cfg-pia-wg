// screens/about_screen.dart - Build provenance, project links, and the GPL v3 licence.
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
// Exists so a bug report can identify exactly which binary the reporter is running: the commit,
// branch/tag, CI run, build type and install source are otherwise invisible once the APK ships.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_colors.dart';
import '../build_info_service.dart';
import '../firmware.dart';
import '../license_text.dart';
import '../router_slot_service.dart';
import '../router_watchdog.dart';
import '../session_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common_fields.dart';
import '../widgets/error_presenter.dart';

const String _kRepoUrl = 'https://github.com/ExponentiallyDigital/cfg-pia-wg';
const String _kRepoBlobUrl = '$_kRepoUrl/blob/main';
const String _kPrivacyUrl = 'https://www.exponentiallydigital.com/cfg-pia-wg/privacy.html';

/// Label/URL pairs, rendered in this order.
const List<(String, String)> _kLinks = [
  ('ReadMe', '$_kRepoBlobUrl/README.md'),
  ('Change log', '$_kRepoBlobUrl/CHANGELOG.md'),
  ('Security policy', '$_kRepoBlobUrl/SECURITY.md'),
  ('Privacy policy', _kPrivacyUrl),
];

// Shown in place of every metadata value until the platform channel answers, so the layout does
// not jump once it does.
const String _kPending = '...';

void _showOpenSourceLicences(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const _LicensesDialog(),
  );
}

class AboutScreen extends StatefulWidget {
  /// Injected by tests so DEL CACHED PIA CERT can run without a router.
  final Future<SSHClient> Function(String ip, String user, String pass)? testClientFactory;
  const AboutScreen({super.key, this.testClientFactory});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  // Held in state rather than created inline in the FutureBuilder, which would re-invoke the
  // channel on every rebuild.
  late final Future<BuildInfo> _buildInfo;

  // True while the SSH round trip for DEL CACHED PIA CERT is in flight.
  bool _deletingCert = false;

  // One recogniser per link, owned by this State so they can be disposed. A tappable TextSpan
  // (rather than an InkWell around the whole row) is what lets a long GitHub URL wrap mid-line
  // on a narrow phone while keeping the tap target on the URL itself.
  final List<TapGestureRecognizer> _recognisers = [];

  // Separate recogniser for the "Open source: licenses" link, so it shows the license page
  // instead of launching a GitHub URL.
  late final TapGestureRecognizer _licencesRecognizer;

  @override
  void initState() {
    super.initState();
    _buildInfo = loadBuildInfo();
    for (final (_, url) in _kLinks) {
      _recognisers.add(TapGestureRecognizer()..onTap = () => _launch(url));
    }
    // A dedicated recogniser for the licences link, which is not one of the _kLinks entries.
    _licencesRecognizer = TapGestureRecognizer()..onTap = () => _showOpenSourceLicences(context);
  }

  @override
  void dispose() {
    for (final recogniser in _recognisers) {
      recogniser.dispose();
    }
    super.dispose();
  }

  // armAutoClear: false - build info is not a secret, so the 60s auto-clear meant for credentials
  // must not be armed for it. Going through the controller rather than Clipboard directly also
  // stands down a countdown left by an earlier config copy, which would otherwise wipe the build
  // info the user has just copied.
  Future<void> _copyBuildInfo(BuildContext context, BuildInfo? info) async {
    await SessionScope.of(context).copyToClipboard(_BuildInfoBlock.asPlainText(info), armAutoClear: false);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Build info copied.')));
    }
  }

  // The cached PIA CA lives on the router, so this needs the SSH details the router screens
  // collect. They are session state, not stored, so the button says so rather than failing.
  Future<void> _deletePiaCert(BuildContext context) async {
    final controller = SessionScope.of(context);
    var ip = controller.routerIp.trim(), user = controller.sshUsername.trim(), pass = controller.sshPassword;
    if (ip.isEmpty || user.isEmpty || pass.isEmpty) {
      // ABOUT is reachable without ever visiting a router screen, so ask here rather than sending
      // the user away. Anything already in the session prefills the form.
      final entered = await showDialog<(String, String, String)?>(
        context: context,
        builder: (_) => _SshCredsDialog(initialIp: ip, initialUser: user, initialPass: pass),
      );
      if (entered == null || !context.mounted) return;
      (ip, user, pass) = entered;
      controller
        ..routerIp = ip
        ..sshUsername = user
        ..sshPassword = pass;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kSurface,
            title: const Text('Delete cached PIA certificate?', style: TextStyle(color: kHighlight, fontSize: 14)),
            content: const Text(
              'Removes $kPiaCaCertPath from the router. The watchdog downloads a fresh copy on its '
              'next run. Nothing else is changed.',
              style: TextStyle(color: kText, fontSize: 12),
            ),
            actions: [
              TextButton(
                key: const Key('about_del_cert_cancel'),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCEL'),
              ),
              TextButton(
                key: const Key('about_del_cert_confirm'),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('DELETE', style: TextStyle(color: kError)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _deletingCert = true);
    String? error;
    var deleted = false;
    try {
      // The shared session, like every other router action. The credentials above were written
      // back to the controller first, so this either reuses the open connection or opens one
      // against exactly what the user just typed.
      final client = controller
          .routerSession(() => widget.testClientFactory?.call(ip, user, pass) ?? openSshClient(ip, user, pass));
      deleted = await RouterWatchdog(client, onLog: controller.onLog).deleteCachedPiaCert();
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (mounted) setState(() => _deletingCert = false);
    }
    if (!context.mounted) return;
    if (error != null) {
      await AppErrors.system(context, controller, 'Could not delete the cached certificate: $error');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(deleted ? 'Cached PIA certificate deleted.' : 'No cached PIA certificate on the router.'),
    ));
  }

  /// Same pattern as the header bar's author/repo links: guard, launch, silently no-op.
  Future<void> _launch(String urlStr) async {
    final url = Uri.parse(urlStr);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      // One selection region for the whole screen, so a drag - or the long-press "Select all" -
      // spans the build info, the links and the licence text, and copies to the system clipboard.
      // Children below are plain Text on purpose: a SelectableText nested in a SelectionArea keeps
      // its own private selection and the region skips over it.
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FutureBuilder<BuildInfo>(
              future: _buildInfo,
              builder: (context, snap) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BuildInfoBlock(info: snap.data),
                  const SizedBox(height: 8),
                  // Wrap, not Row: the two labels together overflow a narrow phone, so they sit
                  // side by side when there is room and fall to a second line when there is not.
                  Wrap(
                    spacing: 4,
                    children: [
                      // A copy path that does not depend on the Android selection toolbar, which is
                      // awkward to reach for a selection this close to the top of the screen.
                      TextButton.icon(
                        key: const Key('about_copy_build_info'),
                        onPressed: () => _copyBuildInfo(context, snap.data),
                        icon: const Icon(Icons.copy, size: 16, color: kHighlight),
                        label: const Text('COPY BUILD INFO', style: TextStyle(color: kHighlight, fontSize: 12)),
                      ),
                      TextButton.icon(
                        key: const Key('about_create_issue'),
                        onPressed: () => _launch(bugReportUrl(snap.data)),
                        icon: const Icon(Icons.bug_report_outlined, size: 16, color: kHighlight),
                        label: const Text('CREATE GITHUB ISSUE', style: TextStyle(color: kHighlight, fontSize: 12)),
                      ),
                      TextButton.icon(
                        key: const Key('about_del_pia_cert'),
                        onPressed: _deletingCert ? null : () => _deletePiaCert(context),
                        icon: _deletingCert
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: kHighlight),
                              )
                            : const Icon(Icons.gpp_bad_outlined, size: 16, color: kHighlight),
                        label: const Text('DEL PIA CERT', style: TextStyle(color: kHighlight, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // url links display
            const SizedBox(height: 20),
            for (var i = 0; i < _kLinks.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${_kLinks[i].$1}: ', style: _labelStyle),
                    TextSpan(
                      text: _kLinks[i].$2,
                      style: const TextStyle(
                        color: kHighlight,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        decorationColor: kHighlight,
                      ),
                      recognizer: _recognisers[i],
                    ),
                  ]),
                ),
              ),
            // "Open source: licenses" display
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  key: const Key('about_licenses_link'),
                  TextSpan(children: [
                    TextSpan(text: 'Open source: ', style: _labelStyle),
                    TextSpan(
                      text: 'licenses',
                      style: const TextStyle(
                        color: kHighlight,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        decorationColor: kHighlight,
                      ),
                      recognizer: _licencesRecognizer,
                    ),
                  ]),
                ),
              ),
            ),
            // "GNU GPL license" display:
            const SizedBox(height: 20),
            const Text(
              kLicenseText,
              style: TextStyle(color: Colors.white70, fontSize: 10, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

const TextStyle _labelStyle = TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600);
const TextStyle _valueStyle = TextStyle(color: kText, fontSize: 12);

/// The metadata block. [info] is null while the channel call is in flight.
///
/// Rendered as ONE Text.rich rather than a widget per row. SelectionArea joins the text of separate
/// widgets with no separator, so a row-per-widget layout copied as one run-on line; keeping the
/// newlines inside a single Text is what carries them to the clipboard.
class _BuildInfoBlock extends StatelessWidget {
  final BuildInfo? info;
  const _BuildInfoBlock({required this.info});

  /// `label: value` pairs in display order. [i] is null while the channel call is in flight.
  static List<(String, String)> rows(BuildInfo? i) {
    String v(String Function(BuildInfo) field) => i == null ? _kPending : field(i);
    return [
      ('Built by', '${v((b) => b.installer)} at ${v((b) => b.buildTimestamp)}'),
      ('Build type', v((b) => b.buildType)),
      ('Commit hash', v((b) => b.commitHash)),
      ('Git branch/tag', v((b) => b.gitBranch)),
      ('Build runner ID', v((b) => b.runnerId)),
      ('CPU Architecture (ABI)', v((b) => b.cpuAbi)),
      ('Target Android version', v((b) => b.osVersion)),
      ('Compile SDK', v((b) => b.compileSdk)),
      ('Kotlin', v((b) => b.kotlinVersion)),
    ];
  }

  static String headline(BuildInfo? i) {
    String v(String Function(BuildInfo) field) => i == null ? _kPending : field(i);
    return 'cfg-pia-wg v${v((b) => b.versionName)} build ${v((b) => b.buildNumber)}';
  }

  /// Exactly what selecting this block yields, and what the COPY button writes to the clipboard.
  static String asPlainText(BuildInfo? i) => '${headline(i)}\n\n${rows(i).map((r) => '${r.$1}: ${r.$2}').join('\n')}';

  @override
  Widget build(BuildContext context) {
    final data = rows(info);
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: headline(info),
          style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const TextSpan(text: '\n\n'),
        for (var n = 0; n < data.length; n++) ...[
          TextSpan(text: '${data[n].$1}: ', style: _labelStyle),
          TextSpan(text: data[n].$2, style: _valueStyle),
          if (n < data.length - 1) const TextSpan(text: '\n'),
        ],
      ]),
      // Stands in for the old per-row 4px padding, now that the rows share one paragraph.
      style: const TextStyle(height: 1.45),
    );
  }
}

/// A prefilled "new bug report" URL for the running build.
///
/// Mirrors the section headings of `.github/ISSUE_TEMPLATE/bug_report.md`: GitHub applies a
/// template OR a `body` parameter, never both, so passing the build info means reproducing the
/// headings here. test/screens/about_screen_test.dart fails if the two drift apart.
///
/// The template's own Environment bullets are not reproduced - they still ask for an addon and a
/// game version - so that section carries the build info plus the router fields instead.
String bugReportUrl(BuildInfo? info) {
  final firmware = firmwareDetected ? routerFirmware.name : 'not detected this session';
  final body = '''
**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:

1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Expected behavior**
A clear and concise description of what you expected to happen.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Environment (please complete the following information):**

```text
${_BuildInfoBlock.asPlainText(info)}
Router firmware: $firmware
```

- Router model: [e.g. RT-AX86U]
- Router firmware version: [e.g. 3.0.0.4.388_24762]

**Additional context**
Add any other context about the problem here.
''';
  return Uri.parse('$_kRepoUrl/issues/new')
      .replace(queryParameters: {'title': '[BUG] ...insert a short title...', 'body': body}).toString();
}

/// Licence notices grouped by package, sorted by package name. Each notice is one entry's
/// paragraphs, kept intact so [LicenseParagraph.indent] survives to the renderer.
///
/// LicenseRegistry yields one entry per licence TEXT, each naming every package that text covers.
/// Rendering entries directly therefore repeats a package once per distinct notice -
/// `accessibility` appeared 16 times, once per Chromium copyright year. Grouping the other way
/// round lists each package once, which is what Flutter's own licence page does.
///
/// Identical notices within a package collapse to one; ones differing only by year do not, since
/// they are genuinely different notices.
List<(String, List<List<LicenseParagraph>>)> groupLicensesByPackage(List<LicenseEntry> entries) {
  final byPackage = <String, List<List<LicenseParagraph>>>{};
  final seen = <String, Set<String>>{};
  for (final entry in entries) {
    // paragraphs is documented as expensive, so resolve it once per entry, not once per package.
    final paragraphs = entry.paragraphs.toList();
    final key = paragraphs.map((p) => '${p.indent}:${p.text}').join('\n');
    for (final package in entry.packages) {
      final notices = byPackage.putIfAbsent(package, () => <List<LicenseParagraph>>[]);
      if (seen.putIfAbsent(package, () => <String>{}).add(key)) notices.add(paragraphs);
    }
  }
  final packages = byPackage.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [for (final p in packages) (p, byPackage[p]!)];
}

// ── Open-source license dialog ─────────────────────────────────────────────────
// Replaces Flutter's built-in showLicensePage so the page inherits the app's
// dark palette, has a teal back arrow, no app-name title, and no
// "Powered by Flutter" footer.

class _LicensesDialog extends StatefulWidget {
  const _LicensesDialog();

  @override
  State<_LicensesDialog> createState() => _LicensesDialogState();
}

class _LicensesDialogState extends State<_LicensesDialog> {
  late final Future<List<LicenseEntry>> _licenses;

  @override
  void initState() {
    super.initState();
    _licenses = LicenseRegistry.licenses.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        title: const SizedBox.shrink(),
        iconTheme: const IconThemeData(color: kHighlight, size: 24),
      ),
      body: FutureBuilder<List<LicenseEntry>>(
        future: _licenses,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: kHighlight),
              ),
            );
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Unable to load license information.',
                style: TextStyle(color: kMuted, fontSize: 12),
              ),
            );
          }

          final grouped = groupLicensesByPackage(snapshot.data!);
          // Its own selection region: the About screen's does not extend into this dialog.
          return SelectionArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final (package, notices) in grouped) ...[
                  Text(
                    package,
                    style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  for (var n = 0; n < notices.length; n++) ...[
                    if (n > 0) const SizedBox(height: 12),
                    // Paragraph by paragraph, honouring indent and the centred-header marker, the
                    // way the framework's own licence page does. Text is never altered: hard line
                    // breaks inside a paragraph are already lost upstream, where
                    // LicenseEntryWithLineBreaks joins a paragraph's lines with spaces.
                    for (final paragraph in notices[n]) _LicenceParagraph(paragraph),
                  ],
                  const Divider(color: kBorder, height: 24),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One licence paragraph, indented or centred per [LicenseParagraph.indent].
class _LicenceParagraph extends StatelessWidget {
  final LicenseParagraph paragraph;
  const _LicenceParagraph(this.paragraph);

  @override
  Widget build(BuildContext context) {
    final centered = paragraph.indent == LicenseParagraph.centeredIndent;
    return Padding(
      padding: EdgeInsets.only(top: 8, left: centered ? 0 : 16.0 * paragraph.indent),
      child: Text(
        paragraph.text,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          color: kMuted,
          fontSize: 10,
          height: 1.4,
          fontWeight: centered ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

/// Router SSH details, asked for inline when the session has none.
///
/// The router screens normally collect these, but ABOUT is reachable without visiting one and its
/// DEL PIA CERT button needs them. Whatever the session already holds is prefilled; what the user
/// enters goes back into the session, so a later router screen starts connected.
class _SshCredsDialog extends StatefulWidget {
  final String initialIp, initialUser, initialPass;
  const _SshCredsDialog({required this.initialIp, required this.initialUser, required this.initialPass});

  @override
  State<_SshCredsDialog> createState() => _SshCredsDialogState();
}

class _SshCredsDialogState extends State<_SshCredsDialog> {
  // Same starting points as the router screens: session value if there is one, else the defaults.
  late final TextEditingController _ipCtrl =
      TextEditingController(text: widget.initialIp.isNotEmpty ? widget.initialIp : kDefaultRouterIp);
  late final TextEditingController _userCtrl =
      TextEditingController(text: widget.initialUser.isNotEmpty ? widget.initialUser : kDefaultSshUsername);
  late final TextEditingController _passCtrl = TextEditingController(text: widget.initialPass);
  bool _visible = false;
  String? _error;

  @override
  void dispose() {
    _ipCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _onContinue() {
    final ip = _ipCtrl.text.trim(), user = _userCtrl.text.trim(), pass = _passCtrl.text;
    if (ip.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Router IP, SSH username and SSH password are all required.');
      return;
    }
    Navigator.of(context).pop((ip, user, pass));
  }

  @override
  Widget build(BuildContext context) {
    // A Dialog with its own scroll view, not an AlertDialog: an AlertDialog puts its content in a
    // Flexible, and inside the app chrome (where the Scaffold has already taken the keyboard's
    // height off the body) that Flexible collapses to zero and the fields spill out of the card.
    // This is the same structure SlotParamsEditor uses.
    return Dialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        // Width only. The height must come from the incoming constraints - inside the app chrome
        // the Scaffold has already taken the keyboard off the body, so any cap computed from the
        // screen height is too large and the card spills down behind the keyboard. Unbounded here
        // lets SingleChildScrollView shrink-wrap to the space it is given and scroll past that.
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Router SSH details', style: TextStyle(color: kHighlight, fontSize: 14)),
                const SizedBox(height: 16),
                RouterIpField(controller: _ipCtrl),
                const SizedBox(height: 10),
                // Its own group, and the router IP is deliberately outside it - see
                // plan_autofill-credentials.md. cancel: dismissing the dialog asks nothing.
                AutofillGroup(
                  onDisposeAction: AutofillContextAction.cancel,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SshUsernameField(controller: _userCtrl),
                      const SizedBox(height: 10),
                      SshPasswordField(
                          controller: _passCtrl, visible: _visible, onToggle: () => setState(() => _visible = !_visible)),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: const TextStyle(color: kError, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('about_ssh_cancel'),
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text('CANCEL', style: TextStyle(color: kMuted)),
                    ),
                    TextButton(key: const Key('about_ssh_continue'), onPressed: _onContinue, child: const Text('CONTINUE')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
