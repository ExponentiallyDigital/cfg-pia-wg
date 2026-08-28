// test/widgets/firmware_notice_test.dart - the two dismissible firmware warnings + their links.
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/firmware_notice.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

SessionController _controller() => SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

/// Records what url_launcher was asked to do, so a tap can be verified without a platform.
class _LaunchRecorder {
  final List<String> canLaunch = [];
  final List<String> launched = [];

  void install() {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final url = (call.arguments as Map?)?['url'] as String? ?? '';
      switch (call.method) {
        case 'canLaunch':
          canLaunch.add(url);
          return true;
        case 'launch':
          launched.add(url);
          return true;
      }
      return null;
    });
    addTearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
  }
}

/// Pumps a host whose button opens [open], so the dialog is shown the way production shows it.
Future<void> _pumpNotice(
  WidgetTester tester,
  SessionController c,
  Future<void> Function(BuildContext, SessionController) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            key: const Key('open_notice'),
            onPressed: () => open(context, c),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open_notice')));
  await tester.pumpAndSettle();
}

/// Taps the link span inside the notice by driving its recognizer directly — a plain tester.tap
/// would hit the RichText, not the span.
void _tapLink(WidgetTester tester) {
  final text = tester.widget<Text>(find.byKey(const Key('firmware_notice_link')));
  final span = text.textSpan! as TextSpan;
  final link = span.children!.last as TextSpan;
  (link.recognizer! as TapGestureRecognizer).onTap!();
}

void main() {
  group('missing binaries', () {
    testWidgets('names a single missing binary', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await _pumpNotice(tester, c, (ctx, ctrl) => showMissingBinariesNotice(ctx, ctrl, [kStockJqPath]));

      expect(find.byKey(const Key('firmware_notice')), findsOneWidget);
      expect(find.textContaining('Unable to locate: $kStockJqPath'), findsOneWidget);
      expect(find.textContaining('Prerequisites in README.md'), findsOneWidget);
    });

    testWidgets('comma-joins both missing binaries', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await _pumpNotice(
          tester, c, (ctx, ctrl) => showMissingBinariesNotice(ctx, ctrl, [kStockJqPath, kStockMailsendPath]));

      expect(find.textContaining('Unable to locate: $kStockJqPath, $kStockMailsendPath'), findsOneWidget);
    });

    testWidgets('is dismissible via OK', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await _pumpNotice(tester, c, (ctx, ctrl) => showMissingBinariesNotice(ctx, ctrl, [kStockJqPath]));

      await tester.tap(find.byKey(const Key('firmware_notice_ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('firmware_notice')), findsNothing);
    });

    testWidgets('the README link is tappable and launches the prerequisites anchor', (tester) async {
      final recorder = _LaunchRecorder()..install();
      final c = _controller();
      addTearDown(c.dispose);
      await _pumpNotice(tester, c, (ctx, ctrl) => showMissingBinariesNotice(ctx, ctrl, [kStockJqPath]));

      _tapLink(tester);
      await tester.pumpAndSettle();

      expect(recorder.canLaunch, [kReadmePrereqUrl]);
      expect(recorder.launched, [kReadmePrereqUrl]);
    });
  });

  group('unsupported firmware', () {
    testWidgets('shows the exact copy with a link', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await _pumpNotice(tester, c, showUnsupportedFirmwareNotice);

      expect(find.textContaining('Your firmware type is not supported, see '), findsOneWidget);
      expect(find.textContaining('README.md'), findsOneWidget);
    });

    testWidgets('is dismissible via OK', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await _pumpNotice(tester, c, showUnsupportedFirmwareNotice);

      await tester.tap(find.byKey(const Key('firmware_notice_ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('firmware_notice')), findsNothing);
    });

    testWidgets('the README link is tappable', (tester) async {
      final recorder = _LaunchRecorder()..install();
      final c = _controller();
      addTearDown(c.dispose);
      await _pumpNotice(tester, c, showUnsupportedFirmwareNotice);

      _tapLink(tester);
      await tester.pumpAndSettle();

      expect(recorder.launched, [kReadmePrereqUrl]);
    });

    // Matches AppErrors: an unlaunchable URL is a silent no-op, never a crash.
    testWidgets('a platform that cannot launch the URL is a silent no-op', (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => call.method == 'canLaunch' ? false : null);
      addTearDown(() =>
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      final c = _controller();
      addTearDown(c.dispose);
      await _pumpNotice(tester, c, showUnsupportedFirmwareNotice);

      _tapLink(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('firmware_notice')), findsOneWidget);
    });
  });

  group('session bookkeeping', () {
    testWidgets('the warning is appended to the app log as an error', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await _pumpNotice(tester, c, (ctx, ctrl) => showMissingBinariesNotice(ctx, ctrl, [kStockJqPath]));

      expect(c.log.last.isError, isTrue);
      expect(c.log.last.message, contains('Unable to locate: $kStockJqPath'));
      expect(c.log.last.message, contains(kReadmePrereqUrl));
    });

    testWidgets('modal depth is balanced across open and dismiss', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await _pumpNotice(tester, c, showUnsupportedFirmwareNotice);
      expect(c.modalsOpen, isTrue);

      await tester.tap(find.byKey(const Key('firmware_notice_ok')));
      await tester.pumpAndSettle();
      expect(c.modalsOpen, isFalse);
    });
  });
}
