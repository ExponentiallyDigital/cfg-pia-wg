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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_colors.dart';
import '../build_info_service.dart';
import '../license_text.dart';
import '../widgets/app_scaffold.dart';

const String _kRepoUrl = 'https://github.com/ExponentiallyDigital/cfg-pia-wg';
const String _kRepoBlobUrl = '$_kRepoUrl/blob/main';
const String _kPrivacyUrl = 'https://www.exponentiallydigital.com/cfg-pia-wg/privacy.html';

/// Label/URL pairs, rendered in this order.
const List<(String, String)> _kLinks = [
  ('GitHub source code repository', _kRepoUrl),
  ('ReadMe', '$_kRepoBlobUrl/README.md'),
  ('Change log', '$_kRepoBlobUrl/CHANGELOG.md'),
  ('Architecture', '$_kRepoBlobUrl/ARCHITECTURE.md'),
  ('Security policy', '$_kRepoBlobUrl/SECURITY.md'),
  ('Privacy policy', _kPrivacyUrl),
];

// Shown in place of every metadata value until the platform channel answers, so the layout does
// not jump once it does.
const String _kPending = '...';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  // Held in state rather than created inline in the FutureBuilder, which would re-invoke the
  // channel on every rebuild.
  late final Future<BuildInfo> _buildInfo;

  // One recogniser per link, owned by this State so they can be disposed. A tappable TextSpan
  // (rather than an InkWell around the whole row) is what lets a long GitHub URL wrap mid-line
  // on a narrow phone while keeping the tap target on the URL itself.
  final List<TapGestureRecognizer> _recognisers = [];

  @override
  void initState() {
    super.initState();
    _buildInfo = loadBuildInfo();
    for (final (_, url) in _kLinks) {
      _recognisers.add(TapGestureRecognizer()..onTap = () => _launch(url));
    }
  }

  @override
  void dispose() {
    for (final recogniser in _recognisers) {
      recogniser.dispose();
    }
    super.dispose();
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FutureBuilder<BuildInfo>(
            future: _buildInfo,
            builder: (context, snap) => _BuildInfoBlock(info: snap.data),
          ),
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
          const SizedBox(height: 20),
          const Text(
            kLicenseText,
            style: TextStyle(color: Colors.white70, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }
}

const TextStyle _labelStyle = TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600);
const TextStyle _valueStyle = TextStyle(color: kText, fontSize: 12);

/// The metadata block. [info] is null while the channel call is in flight.
class _BuildInfoBlock extends StatelessWidget {
  final BuildInfo? info;
  const _BuildInfoBlock({required this.info});

  @override
  Widget build(BuildContext context) {
    final i = info;
    String v(String Function(BuildInfo) field) => i == null ? _kPending : field(i);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'cfg-pia-wg v${v((b) => b.versionName)} build ${v((b) => b.buildNumber)}',
          style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _MetaRow('Built by', '${v((b) => b.installer)} at ${v((b) => b.buildTimestamp)}'),
        _MetaRow('Build type', v((b) => b.buildType)),
        _MetaRow('Commit hash', v((b) => b.commitHash)),
        _MetaRow('Git branch/tag', v((b) => b.gitBranch)),
        _MetaRow('Build runner ID', v((b) => b.runnerId)),
        _MetaRow('CPU Architecture (ABI)', v((b) => b.cpuAbi)),
        _MetaRow('Target Android version', v((b) => b.osVersion)),
        _MetaRow('Compile SDK', v((b) => b.compileSdk)),
        _MetaRow('Kotlin', v((b) => b.kotlinVersion)),
      ],
    );
  }
}

/// A `Label: value` line. Text.rich rather than a fixed-width label column so a long value wraps
/// instead of being clipped on a narrow screen.
class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetaRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label: ', style: _labelStyle),
          TextSpan(text: value, style: _valueStyle),
        ]),
      ),
    );
  }
}
