// test/widgets/log_panel_test.dart - the app log must copy with its line breaks intact.
//
// Reported: a selection copied out of the LOG screen pasted as one run-on line,
// "...via SSH...[10:19:34] Router firmware detected: stock....". SelectionArea joins the text of
// separate widgets with NO separator, so the old widget-per-entry Column lost every line break.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/common_fields.dart';

void main() {
  final entries = [
    LogEntry('[10:19:34] Connecting to router at 192.168.1.1 via SSH...'),
    LogEntry('[10:19:34] Router firmware detected: stock.'),
    LogEntry('[10:19:35] All WireGuard slots are unconfigured.', isError: true),
    LogEntry('[10:19:35] Successfully retrieved router config.', isSuccess: true),
  ];

  Future<void> pumpPanel(WidgetTester tester, List<LogEntry> log) => tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: LogPanel(entries: log))),
      ));

  testWidgets('an empty log shows Ready.', (tester) async {
    await pumpPanel(tester, const []);
    expect(find.text('Ready.'), findsOneWidget);
  });

  testWidgets('the whole log is one Text carrying its own line breaks', (tester) async {
    await pumpPanel(tester, entries);

    // toPlainText keeps WidgetSpan placeholders; the icons are not part of the log text.
    final texts =
        tester.widgetList<Text>(find.byType(Text)).map((w) => (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll('￼', ''));
    final block = texts.firstWhere((t) => t.contains('Connecting to router'), orElse: () => '');

    expect(block, isNotEmpty, reason: 'the log should live in one Text widget');
    expect(block.split('\n'), entries.map((e) => e.message).toList());
    // The exact defect: the next entry glued onto the end of the previous one.
    expect(block, isNot(contains('SSH...[10:19:34]')));
  });

  // The real path: Flutter's own select-all + copy over the rendered widget, not our own idea of
  // what the text is. This is what fails against a widget-per-entry Column.
  testWidgets('select all then copy puts one entry per line on the clipboard', (tester) async {
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpPanel(tester, entries);

    // Tapping inside the region gives it focus so the selection shortcuts reach it.
    await tester.tapAt(tester.getCenter(find.textContaining('Connecting to router')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(copied, isNotNull, reason: 'select all + copy should reach the clipboard');
    expect(copied, contains('via SSH...\n[10:19:34] Router firmware'));
    expect(copied!.split('\n').length, entries.length);
    // WidgetSpan icons split the paragraph into fragments but must not leak their placeholder.
    expect(copied, isNot(contains('\uFFFC')));
  });

  testWidgets('each entry keeps its own severity colour and icon', (tester) async {
    await pumpPanel(tester, entries);

    expect(find.byIcon(Icons.info_outline), findsNWidgets(2));
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    final span = tester.widget<Text>(find.textContaining('Connecting to router')).textSpan!;
    final colours = <Color?>[];
    span.visitChildren((child) {
      if (child is TextSpan && (child.text ?? '').trim().isNotEmpty) colours.add(child.style?.color);
      return true;
    });
    expect(colours, [kHighlight, kHighlight, kError, Colors.white]);
  });

  // ID-004: laying out the whole log as one paragraph made every new line cost the length of the log. It is
  // drawn in blocks of 100 lines, and a new line redraws only the last block.
  group('a long log', () {
    List<LogEntry> lines(int n) => [for (var i = 0; i < n; i++) LogEntry('[10:00:00] entry ${i.toString().padLeft(3, '0')}')];

    Iterable<Text> blocks(WidgetTester tester) =>
        tester.widgetList<Text>(find.descendant(of: find.byType(LogPanel), matching: find.byType(Text)));

    testWidgets('is laid out in blocks of 100 lines', (tester) async {
      await pumpPanel(tester, lines(250));
      final texts = blocks(tester).map((t) => t.textSpan!.toPlainText().replaceAll('￼', '')).toList();
      expect(texts, hasLength(3));
      expect(texts[0].split('\n'), hasLength(100));
      expect(texts[2].split('\n'), hasLength(50));
      expect(texts[1], startsWith('[10:00:00] entry 100'));
    });

    // The blocks are separate widgets, and SelectionArea joins separate widgets with no separator - the bug
    // the one-paragraph layout was there to avoid. The line break goes back in between the blocks.
    testWidgets('select all then copy keeps every line break, across blocks too', (tester) async {
      String? copied;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final log = lines(250);
      await pumpPanel(tester, log);
      await tester.tapAt(tester.getTopLeft(find.byType(LogPanel)) + const Offset(40, 8));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(copied, isNotNull);
      expect(copied!.split('\n'), log.map((e) => e.message).toList());
      expect(copied, contains('entry 099\n[10:00:00] entry 100'), reason: 'the join between the first two blocks');
      expect(copied, isNot(contains('￼')));
    });

    testWidgets('a new line redraws only the last block', (tester) async {
      final log = lines(250);
      final revision = ValueNotifier<int>(0);
      addTearDown(revision.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<int>(
              valueListenable: revision,
              builder: (_, __, ___) => LogPanel(entries: log),
            ),
          ),
        ),
      ));
      final before = blocks(tester).toList();

      log.add(LogEntry('[10:00:01] one more'));
      revision.value++;
      await tester.pump();
      final after = blocks(tester).toList();

      expect(identical(after[0], before[0]), isTrue, reason: 'the first block was not rebuilt');
      expect(identical(after[1], before[1]), isTrue, reason: 'nor the second');
      expect(identical(after[2], before[2]), isFalse, reason: 'the last one carries the new line');
      expect(after[2].textSpan!.toPlainText(), endsWith('one more'));
    });

    // A trim drops lines from the front, which moves every block boundary; nothing stale may survive it.
    testWidgets('after lines are dropped from the front, every block is built again', (tester) async {
      final log = lines(250);
      final revision = ValueNotifier<int>(0);
      addTearDown(revision.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<int>(valueListenable: revision, builder: (_, __, ___) => LogPanel(entries: log)),
          ),
        ),
      ));

      log.removeRange(0, 30);
      revision.value++;
      await tester.pump();
      final texts = blocks(tester).map((t) => t.textSpan!.toPlainText().replaceAll('￼', '')).toList();
      expect(texts, hasLength(3));
      expect(texts[0], startsWith('[10:00:00] entry 030'));
      expect(texts[1], startsWith('[10:00:00] entry 130'));
      expect(texts.join('\n').split('\n'), hasLength(220));
    });
  });
}
