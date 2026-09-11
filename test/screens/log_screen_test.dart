// test/screens/log_screen_test.dart - the app log screen: opens at the newest entry, three buttons.
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/screens/log_screen.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SessionController _controller() => SessionController(
      tickInterval: const Duration(hours: 1),
      clipboardWriter: (_) async {},
    );

Widget _host(SessionController c) => SessionScope(
      controller: c,
      // A Scaffold ancestor, because COPY reports through a snackbar. Production gets one from
      // AppChrome, which hosts every pushed screen.
      child: const MaterialApp(home: Scaffold(body: LogScreen())),
    );

void main() {
  testWidgets('opens scrolled to the newest entry, not the oldest', (tester) async {
    // The reason anyone opens this screen is to see what just happened. Opening at the top means
    // scrolling past a whole session to reach it.
    final c = _controller();
    for (var i = 0; i < 200; i++) {
      c.logEntry('entry number $i');
    }
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView)).controller!;
    expect(scroll.offset, scroll.position.maxScrollExtent);
    expect(scroll.offset, greaterThan(0), reason: 'the fixture has to be long enough to scroll');

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('carries COPY, CLEAR and HOME, and CLEAR empties the log', (tester) async {
    final c = _controller()..logEntry('something happened');
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app_log_copy')), findsOneWidget);
    expect(find.byKey(const Key('app_log_clear')), findsOneWidget);
    expect(find.byKey(const Key('app_log_home')), findsOneWidget);
    // The old screen carried a "LOG" field label above the panel; the screen is the log.
    expect(find.text('LOG'), findsNothing);

    await tester.tap(find.byKey(const Key('app_log_clear')));
    await tester.pumpAndSettle();
    expect(c.log, isEmpty);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('COPY takes the log verbatim and arms no clipboard countdown', (tester) async {
    String? copied;
    final c = SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (t) async => copied = t)
      ..logEntry('first')
      ..logEntry('second');
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('app_log_copy')));
    await tester.pumpAndSettle();

    expect(copied, contains('first'));
    expect(copied, contains('second'));
    expect(c.clipboardSeconds, 0, reason: 'a log is not a secret');

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('COPY and CLEAR are disabled while the log is empty', (tester) async {
    final c = _controller();
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    expect(tester.widget<OutlinedButton>(find.byKey(const Key('app_log_copy'))).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('app_log_clear'))).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('app_log_home'))).onPressed, isNotNull);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('a warning is amber, an error is red, and they are told apart', (tester) async {
    // Red was being spent on things needing no action - a dropped SSH connection the app is already
    // reconnecting. A log where most of the red is routine is a log nobody reads.
    final c = _controller()
      ..logEntry('reconnecting', isWarning: true)
      ..logEntry('it failed', isError: true);
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    final warn = tester.widget<Icon>(find.byIcon(Icons.warning_amber_outlined));
    final error = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(warn.color, kWarn);
    expect(error.color, kError);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
