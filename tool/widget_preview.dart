// tool/widget_preview.dart - pushes fixture data to the home-screen widgets, so they can be seen
// and screenshotted before ID-376's key exists (slice 2 of .claude/plans/plan_widget-id-376.md).
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
// Not part of the app - a separate entry point, run on a device or emulator with:
//   flutter run -t tool/widget_preview.dart
// Add the "cfg-pia-wg" widget to the home screen first (long-press an empty spot, Widgets, drag
// either size on), then run this. Each button below pushes one of the mock-up's states; both
// widgets redraw within a second or two. Nothing here touches a router, the SSH key, or any
// router credential - it writes only the same data buildWidgetData would, by hand.
import 'package:cfg_pia_wg/widget_bridge.dart';
import 'package:cfg_pia_wg/widget_status.dart';
import 'package:flutter/material.dart';

void main() => runApp(const _PreviewApp());

WidgetTunnelInfo _tunnel({
  required int slot,
  required String region,
  bool up = true,
  int? handshakeAgeSeconds = 0,
  List<String> pinned = const [],
}) =>
    WidgetTunnelInfo(slot: slot, region: region, up: up, handshakeAgeSeconds: handshakeAgeSeconds, pinnedDeviceNames: pinned);

/// The four states the mock-up shows (Main, Protected, TunnelDown, NotChecked boards at
/// https://claude.ai/artifact/SU6ha7UoqcczLr1d2f6oLn), as fixtures rather than a router read.
final Map<String, WidgetStatus Function(DateTime now)> _fixtures = {
  'Protected, two tunnels': (now) => WidgetStatus(
        tunnels: [
          _tunnel(slot: 5, region: 'Melbourne, Australia', pinned: ['TABLET', 'DESKTOP']),
          _tunnel(slot: 1, region: 'Auckland, New Zealand', pinned: ['LAPTOP']),
        ],
        checkedAt: now,
      ),
  'One tunnel down, held by the guard': (now) => WidgetStatus(
        tunnels: [
          _tunnel(slot: 5, region: 'Melbourne, Australia', pinned: ['TABLET']),
          _tunnel(slot: 1, region: 'Auckland, New Zealand', up: false, handshakeAgeSeconds: null, pinned: ['DESKTOP']),
        ],
        guardedOfflineDeviceNames: const ['DESKTOP'],
        checkedAt: now,
      ),
  'Not checked for a while': (now) => WidgetStatus(
        tunnels: [
          _tunnel(slot: 5, region: 'Melbourne, Australia', handshakeAgeSeconds: 310, pinned: ['TABLET']),
          _tunnel(slot: 1, region: 'Auckland, New Zealand', handshakeAgeSeconds: 305, pinned: ['LAPTOP']),
        ],
        checkedAt: now.subtract(const Duration(hours: 3)),
      ),
  'Three tunnels, overflow': (now) => WidgetStatus(
        tunnels: [
          _tunnel(slot: 5, region: 'Melbourne, Australia'),
          _tunnel(slot: 1, region: 'Auckland, New Zealand'),
          _tunnel(slot: 2, region: 'Toronto, Canada'),
        ],
        checkedAt: now,
      ),
};

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'cfg-pia-wg widget preview',
        theme: ThemeData.dark(),
        home: _PreviewScreen(),
      );
}

class _PreviewScreen extends StatefulWidget {
  @override
  State<_PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<_PreviewScreen> {
  String _status = 'Add the widget to your home screen, then tap a state below.';

  Future<void> _push(String label, WidgetStatus Function(DateTime) build) async {
    final now = DateTime.now();
    await pushWidgetStatus(build(now), now: now);
    setState(() => _status = 'Pushed "$label" - check your home screen.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Widget preview (ID-376, not shipped)')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status),
              const SizedBox(height: 16),
              for (final entry in _fixtures.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ElevatedButton(
                    onPressed: () => _push(entry.key, entry.value),
                    child: Text(entry.key),
                  ),
                ),
            ],
          ),
        ),
      );
}
