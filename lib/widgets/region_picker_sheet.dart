// widgets/region_picker_sheet.dart - Scrollable, filterable PIA region picker bottom sheet.
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
// Extracted verbatim from main.dart's _RegionPickerSheet so every screen that needs region
// selection (standalone generate, router CREATE, watchdog EDIT) reuses one implementation.

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../pia_service.dart';

/// Bottom sheet listing [regions] with a live filter. Calls [onSelected] with the chosen
/// region id and pops itself.
class RegionPickerSheet extends StatefulWidget {
  final List<Region> regions;
  final void Function(String) onSelected;
  const RegionPickerSheet({super.key, required this.regions, required this.onSelected});

  /// Convenience launcher that brackets the sheet so its dismissal is awaitable by callers.
  static Future<void> show(
    BuildContext context, {
    required List<Region> regions,
    required void Function(String) onSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (ctx) => RegionPickerSheet(regions: regions, onSelected: onSelected),
    );
  }

  @override
  State<RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<RegionPickerSheet> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.regions.where((r) => r.id.toLowerCase().contains(_filter.toLowerCase())).toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              style: const TextStyle(color: kText, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                  hintText: 'Filter regions...', prefixIcon: Icon(Icons.search, color: kMuted, size: 18)),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final r = filtered[i];
                return InkWell(
                  onTap: () {
                    widget.onSelected(r.id);
                    Navigator.pop(ctx);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.chevron_right, color: kHighlight, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(r.id, style: const TextStyle(color: kText, fontFamily: 'monospace', fontSize: 13))),
                        Text('${r.wgServers.length} server${r.wgServers.length == 1 ? '' : 's'}',
                            style: const TextStyle(color: kHint, fontSize: 11)),
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
