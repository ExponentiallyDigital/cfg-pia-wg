// test/widgets/install_binaries_dialog_test.dart - consent to put an executable on a router.
//
// The dialog's job is not to look right, it is to make the choice an informed one. So the tests
// are about what it discloses and what it treats as consent: the user must see what is being
// downloaded and where it lands, must be told that declining leaves the screen unusable, and a
// dismissal must never be read as agreement.
import 'package:cfg_pia_wg/binary_installer.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/install_binaries_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SessionController controller;
  setUp(() => controller = SessionController(clipboardWriter: (_) async {}));
  tearDown(() => controller.dispose());

  /// The choice the dialog will report, completed once the user acts on it.
  late Future<InstallChoice> pending;

  /// Opens the dialog. The result is read from [pending] after acting on it - returning it from
  /// here would mean awaiting a future that only completes once the test has tapped something.
  Future<void> open(WidgetTester tester, List<String> missing) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => pending = showInstallBinariesDialog(context, controller, missing),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('names each binary, its version and where it will be written', (tester) async {
    await open(tester, [kStockJqPath, kStockMailsendPath]);
    await tester.pumpAndSettle();

    // Provenance in full - the user is agreeing to run an executable on their own hardware.
    expect(find.textContaining('jq ${kJqBinary.version}'), findsOneWidget);
    expect(find.textContaining('mailsend-go ${kMailsendBinary.version}'), findsOneWidget);
    expect(find.textContaining(kStockJqPath), findsOneWidget);
    expect(find.textContaining(kStockMailsendPath), findsOneWidget);
    expect(find.textContaining('github.com'), findsWidgets);

    await tester.tap(find.byKey(const Key('install_binaries_decline')));
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('shows the checksum it will hold the download to', (tester) async {
    // Asked for on hardware: "where can I find what our known checksum is?" Saying a checksum is
    // verified without showing which one asks the user to take on trust the very thing being
    // verified. Shown in full so it can be compared against the project's published checksums.
    await open(tester, [kStockJqPath]);
    await tester.pumpAndSettle();
    expect(find.textContaining(kJqBinary.assets['aarch64']!.sha256), findsOneWidget);

    await tester.tap(find.byKey(const Key('install_binaries_decline')));
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('says the download is checksum-checked', (tester) async {
    await open(tester, [kStockJqPath]);
    await tester.pumpAndSettle();
    expect(find.textContaining('checksum'), findsOneWidget);
    await tester.tap(find.byKey(const Key('install_binaries_decline')));
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('the README reference is a real link, not just words', (tester) async {
    // Reported on hardware: users tap it, because the same words ARE a link on the notice that
    // follows this dialog. Plain text there and a link there is the kind of inconsistency that
    // reads as a broken link rather than a deliberate difference.
    await open(tester, [kStockJqPath]);
    await tester.pumpAndSettle();

    final rich = tester.widget<Text>(find.byKey(const Key('install_binaries_readme_link')));
    final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
    final link = spans.firstWhere((s) => s.text == 'Prerequisites in README.md');
    expect(link.recognizer, isNotNull, reason: 'the link text must be tappable');

    await tester.tap(find.byKey(const Key('install_binaries_decline')));
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('states up front that declining leaves the screen unusable', (tester) async {
    // The whole point of saying this before the choice rather than after it.
    await open(tester, [kStockJqPath]);
    await tester.pumpAndSettle();
    expect(find.textContaining('stays unavailable'), findsOneWidget);
    await tester.tap(find.byKey(const Key('install_binaries_decline')));
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('INSTALL returns install, NOT NOW returns decline', (tester) async {
    await open(tester, [kStockJqPath]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('install_binaries_confirm')));
    await tester.pumpAndSettle();
    expect(await pending, InstallChoice.install);

    await open(tester, [kStockJqPath]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('install_binaries_decline')));
    await tester.pumpAndSettle();
    expect(await pending, InstallChoice.decline);
  });

  testWidgets('DISMISSING the dialog is a decline, never consent', (tester) async {
    // A stray back gesture must not be read as permission to write to someone's router.
    await open(tester, [kStockJqPath]);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byKey(const Key('install_binaries')))).pop();
    await tester.pumpAndSettle();
    expect(await pending, InstallChoice.decline);
  });

  testWidgets('modal depth is balanced, so the error presenter is not left confused', (tester) async {
    expect(controller.modalsOpen, isFalse);
    await open(tester, [kStockJqPath]);
    await tester.pumpAndSettle();
    expect(controller.modalsOpen, isTrue);
    await tester.tap(find.byKey(const Key('install_binaries_decline')));
    await tester.pumpAndSettle();
    await pending;
    expect(controller.modalsOpen, isFalse);
  });

  testWidgets('a path with no known binary declines instead of showing an empty dialog', (tester) async {
    await open(tester, ['/jffs/cfg-pia-wg/something-else']);
    expect(await pending, InstallChoice.decline);
    expect(find.byKey(const Key('install_binaries')), findsNothing);
    expect(controller.modalsOpen, isFalse, reason: 'no dialog was opened, so none may be counted');
  });

  testWidgets('the offer is phrased in the first person', (tester) async {
    // "The app can download them for you" reads like a product describing itself; "I can" reads
    // like the thing you are talking to offering to help. Small, and it is the sentence the user
    // is deciding against.
    await open(tester, [kStockJqPath]);
    await tester.pumpAndSettle();
    expect(find.textContaining('I can download it for you'), findsOneWidget);

    await tester.tap(find.byKey(const Key('install_binaries_decline')));
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('the singular case does not read as plural', (tester) async {
    await open(tester, [kStockJqPath]);
    await tester.pumpAndSettle();
    expect(find.text('Install jq?'), findsOneWidget);
    expect(find.textContaining('this program'), findsOneWidget);
    await tester.tap(find.byKey(const Key('install_binaries_decline')));
    await tester.pumpAndSettle();
    await pending;
  });
}
