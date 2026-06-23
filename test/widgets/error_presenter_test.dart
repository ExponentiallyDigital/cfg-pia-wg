// test/widgets/error_presenter_test.dart - input-batch vs system-one + single-modal-at-a-time.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pia_wireguard_cfga/session_controller.dart';
import 'package:pia_wireguard_cfga/widgets/error_presenter.dart';

SessionController _controller() => SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

Widget _host(SessionController c, void Function(BuildContext) onReady) => SessionScope(
      controller: c,
      child: MaterialApp(home: Scaffold(body: Builder(builder: (ctx) {
        return ElevatedButton(onPressed: () => onReady(ctx), child: const Text('go'));
      }))),
    );

void main() {
  testWidgets('input errors are batched into a single dialog and logged', (tester) async {
    final c = _controller();
    await tester.pumpWidget(_host(c, (ctx) => AppErrors.inputs(ctx, c, ['First problem.', 'Second problem.'])));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Please correct the following'), findsOneWidget);
    expect(find.text('First problem.'), findsOneWidget);
    expect(find.text('Second problem.'), findsOneWidget);
    expect(c.log.where((e) => e.isError).length, 2);

    c.dispose();
  });

  testWidgets('a new system error dismisses the previous one (single modal at a time)', (tester) async {
    final c = _controller();
    late BuildContext ctx;
    await tester.pumpWidget(_host(c, (context) => ctx = context));
    await tester.tap(find.text('go'));
    await tester.pump();

    AppErrors.system(ctx, c, 'First error');
    await tester.pumpAndSettle();
    expect(find.text('First error'), findsOneWidget);

    AppErrors.system(ctx, c, 'Second error');
    await tester.pumpAndSettle();
    expect(find.text('First error'), findsNothing);
    expect(find.text('Second error'), findsOneWidget);

    // The modal enters/exits the session's modal tracking.
    expect(c.modalsOpen, isTrue);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(c.modalsOpen, isFalse);

    c.dispose();
  });

  testWidgets('empty input list shows no dialog', (tester) async {
    final c = _controller();
    await tester.pumpWidget(_host(c, (ctx) => AppErrors.inputs(ctx, c, const [])));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);

    c.dispose();
  });
}
