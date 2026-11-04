// test/widgets/slot_text_test.dart - a slot's label in its own colour, and nothing else coloured (ID-515).
import 'dart:io';

import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/slot_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each coloured run in [text], as (text, colour), dropping the runs left in the base colour.
List<(String, Color?)> coloured(String text, {Color base = kText}) => [
      for (final s in slotSpans(text, TextStyle(color: base)).cast<TextSpan>())
        if (s.style?.color != base) (s.text!, s.style?.color),
    ];

const melbourne = 'wgc5:pia-aus_melbourne';

void main() {
  test('the whole label takes its slot colour, region included', () {
    expect(coloured(melbourne), [(melbourne, kSlotColours[5])]);
    expect(coloured('default - $melbourne'), [(melbourne, kSlotColours[5])]);
    expect(coloured('wgc3:pia-au_brisbane-pf.'), [('wgc3:pia-au_brisbane-pf', kSlotColours[3])]);
  });

  // Andrew, 2026-11-04: ROUTER LOG showed only `wgc5` coloured in the watchdog's own lines.
  test("the watchdog's `wgcN pia-region` is the whole label too, and a word after a bare wgcN is not", () {
    expect(coloured('cfg-pia-wg: Checking wgc5 pia-aus_melbourne connectivity'), [('wgc5 pia-aus_melbourne', kSlotColours[5])]);
    expect(coloured('wgc5 is up and handshaking'), [('wgc5', kSlotColours[5])]);
  });

  test('a bare wgcN is coloured on its own, and each label in a line by its own slot', () {
    expect(coloured('Fail-closed guard on for Box 192.168.1.20 (wgc5)'), [('wgc5', kSlotColours[5])]);
    expect(coloured('TV-Lounge Internet -> wgc3:pia-sg, StudyPC default -> wgc2:pia-italy.'),
        [('wgc3:pia-sg', kSlotColours[3]), ('wgc2:pia-italy', kSlotColours[2])]);
  });

  test('file, cron and NVRAM names, and slots that do not exist, are left alone', () {
    for (final t in ['watchdog_wgc5.sh', '#watchdog_wgc5#', 'nvram get wgc5_enable', 'wgc6:pia-uk', 'xwgc1', 'wgc12']) {
      expect(coloured(t), isEmpty, reason: t);
    }
  });

  test('the rest of the line keeps the style it was given, so an error line stays red', () {
    final spans = slotSpans('wgc1:pia-uk did not come up', const TextStyle(color: kError, fontSize: 11)).cast<TextSpan>();
    expect(spans.map((s) => s.text).join(), 'wgc1:pia-uk did not come up');
    expect(spans.first.style?.color, kSlotColours[1]);
    expect(spans.last.style?.color, kError);
    expect(spans.every((s) => s.style?.fontSize == 11), isTrue);
  });

  test('text with no label is one span, as it was', () {
    final spans = slotSpans('Connected to the router.', const TextStyle(color: kHighlight));
    expect(spans, hasLength(1));
    expect(slotOf('Internet'), isNull);
    expect(slotOf('default - wgc4:pia-in'), 4);
  });

  test('every slot has its own colour, none of them the colours that mean OK, error or warning', () {
    expect(kSlotColours.keys.toSet(), {1, 2, 3, 4, 5});
    expect(kSlotColours.values.toSet(), hasLength(5));
    for (final c in kSlotColours.values) {
      expect([kHighlight, kError, kWarn], isNot(contains(c)));
    }
  });

  // ID-478: a screen's heading is its menu row's colour. A heading is drawn either by
  // destinationHeading() or with a destination's own colour constant; any other colour fails here.
  test("every screen heading is drawn in its destination's colour", () {
    final allowed = kDestinationColours.values.toSet();
    const names = {
      'kHighlight': kHighlight,
      'kManageColour': kManageColour,
      'kWatchdogColour': kWatchdogColour,
      'kAssignColour': kAssignColour,
      'kNetworkColour': kNetworkColour,
      'kRouterLogColour': kRouterLogColour,
      'kAppLogColour': kAppLogColour,
      'kSettingsColour': kSettingsColour,
      'kAboutColour': kAboutColour,
    };
    final calls = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in RegExp(r'ScreenHeading\([^;]*?colour: ([\w.]+)').allMatches(f.readAsStringSync())) {
        calls.add('${f.path}: ${m.group(1)}');
        final c = m.group(1)!;
        if (c == 'destinationColour' || c == 'colour') continue; // the helper, and ScreenHeading's own field
        expect(names.containsKey(c), isTrue, reason: '${f.path} draws a heading in $c');
        expect(allowed, contains(names[c]), reason: '${f.path}: $c is no destination colour');
      }
    }
    expect(calls, isNotEmpty, reason: 'the scan found no headings at all');
  });

  test('every destination maps to a colour the menu draws', () {
    for (final d in AppDestination.values) {
      expect(destinationColour(d), kDestinationColours[d] ?? kHighlight);
    }
  });
}
