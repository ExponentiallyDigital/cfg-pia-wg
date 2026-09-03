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
    LogEntry('[10:19:34] Connecting to router at 192.168.0.254 via SSH...'),
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
}
