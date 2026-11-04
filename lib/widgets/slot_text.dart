// widgets/slot_text.dart - a VPN slot's label in its own colour, wherever it appears (ID-515).
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
// One place finds and colours slot labels, so MANAGE, WATCHDOG, DEVICES, NETWORK, ROUTER DNS ROUTING
// and both logs can't drift apart. The whole `wgc5:pia-aus_melbourne` takes wgc5's colour, region
// included; a bare `wgc5` is coloured on its own. Everything else in the text keeps the style it
// was given, so a red error line stays red around the label.

import 'package:flutter/material.dart';

import '../app_colors.dart';

/// `wgcN`, with its region if it has one: `wgc5:pia-aus_melbourne` as the app writes it, or
/// `wgc5 pia-aus_melbourne` as the watchdog script logs it ("Checking $IFACE $DESC connectivity"),
/// where only a `pia-` name counts, so the word after a bare `wgc5` isn't taken for a region. Not
/// part of a longer word: `watchdog_wgc5.sh`, `#watchdog_wgc5#` and `wgc5_enable` are file, cron and
/// NVRAM names, not labels.
final RegExp kSlotLabelPattern = RegExp(r'(?<![\w])wgc([1-5])(?::[A-Za-z0-9_-]+| pia-[A-Za-z0-9_-]+)?(?![\w])');

/// The slot the first label in [text] names, or null if it names none.
int? slotOf(String text) {
  final m = kSlotLabelPattern.firstMatch(text);
  return m == null ? null : int.parse(m.group(1)!);
}

/// [text] as spans in [base], each slot label in its slot's colour.
List<InlineSpan> slotSpans(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in kSlotLabelPattern.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start), style: base));
    spans.add(TextSpan(text: m.group(0), style: base.copyWith(color: slotColour(int.parse(m.group(1)!)))));
    at = m.end;
  }
  if (at < text.length || spans.isEmpty) spans.add(TextSpan(text: text.substring(at), style: base));
  return spans;
}

/// A [Text] whose slot labels are in their slots' colours, the rest in [style].
class SlotText extends StatelessWidget {
  const SlotText(this.text, {super.key, this.style = const TextStyle(), this.overflow, this.maxLines});

  final String text;
  final TextStyle style;
  final TextOverflow? overflow;
  final int? maxLines;

  @override
  // [style] on the Text itself, so it reads as any other Text's; the spans only change a label's colour.
  Widget build(BuildContext context) =>
      Text.rich(TextSpan(children: slotSpans(text, const TextStyle())), style: style, overflow: overflow, maxLines: maxLines);
}
