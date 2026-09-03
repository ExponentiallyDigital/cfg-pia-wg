// test/widgets/edge_to_edge_test.dart - the app draws under the system bars but never beneath them.
//
// From Android 15 (SDK 35) the system forces edge-to-edge, and at SDK 36 (what
// flutter.targetSdkVersion resolves to) there is no opt-out. Flutter enables it on every Android
// version, so the layout - not the manifest - is what keeps content clear of the status and
// navigation bars. These tests pin that: simulated bar insets must push the header's CONTENT and
// the screen body inward while the header's background still reaches the top of the window.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/widgets/app_scaffold.dart';

import '../app_test_harness.dart';

void main() {
  const double statusBar = 48, navBar = 24;

  /// Gives the test view the padding a phone reports for its status and navigation bars.
  void withSystemBars(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: statusBar, bottom: navBar);
    tester.view.viewPadding = const FakeViewPadding(top: statusBar, bottom: navBar);
    addTearDown(tester.view.reset);
  }

  testWidgets('the header background reaches the top of the window', (tester) async {
    withSystemBars(tester);
    final c = quietController();
    await pumpApp(tester, c);

    // The kSurface bar runs behind the status bar: no strip of scaffold background above it.
    expect(tester.getTopLeft(find.byType(AppHeaderBar)).dy, 0);

    await disposeApp(tester, c);
  });

  testWidgets('header content is pushed below the status bar', (tester) async {
    withSystemBars(tester);
    final c = quietController();
    await pumpApp(tester, c);

    // The hamburger is the topmost thing a user can hit; under the status bar it is unreachable.
    expect(tester.getTopLeft(find.byKey(const Key('app_hamburger'))).dy, greaterThanOrEqualTo(statusBar));
    expect(tester.getTopLeft(find.text('cfg-pia-wg')).dy, greaterThanOrEqualTo(statusBar));

    await disposeApp(tester, c);
  });

  testWidgets('screen content clears the navigation bar', (tester) async {
    withSystemBars(tester);
    final c = quietController();
    await pumpApp(tester, c);

    await tester.tap(find.byKey(const Key('menu_log')));
    await tester.pumpAndSettle();

    // The HOME button sits at the very bottom of a screen, so it is the one that a navigation bar
    // would swallow first.
    final limit = tester.view.physicalSize.height / tester.view.devicePixelRatio - navBar;
    expect(tester.getBottomLeft(find.byKey(const Key('screen_close'))).dy, lessThanOrEqualTo(limit));

    await disposeApp(tester, c);
  });

  testWidgets('the drawer keeps its items clear of both bars', (tester) async {
    withSystemBars(tester);
    final c = quietController();
    await pumpApp(tester, c);

    await tester.tap(find.byKey(const Key('app_hamburger')));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byKey(const Key('drawer_menu'))).dy, greaterThanOrEqualTo(statusBar));

    await disposeApp(tester, c);
  });

  // Reported on device: the licences screen opened with a band of the About screen showing
  // between the app header and its back arrow. showDialog wraps its child in a SafeArea
  // (useSafeArea defaults to true), so a status bar inset still present in the navigator's
  // MediaQuery is applied a SECOND time, below a header that has already cleared it.
  testWidgets('the navigator subtree does not inset for the status bar again', (tester) async {
    withSystemBars(tester);
    final c = quietController();
    await pumpApp(tester, c);

    // Both edges are the chrome's job, so a screen sees no padding of its own to apply: the
    // header cleared the top and the navigator's SafeArea cleared the bottom.
    final context = tester.element(find.byKey(const Key('menu_log')));
    expect(MediaQuery.paddingOf(context).top, 0);
    expect(MediaQuery.paddingOf(context).bottom, 0);

    await disposeApp(tester, c);
  });

  testWidgets('a full-screen dialog starts flush under the header', (tester) async {
    withSystemBars(tester);
    final c = quietController();
    await pumpApp(tester, c);

    await tester.tap(find.byKey(const Key('app_hamburger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer_about')));
    await tester.pumpAndSettle();

    final headerBottom = tester.getBottomLeft(find.byType(AppHeaderBar)).dy;
    // The link is a TextSpan recogniser, not a tappable widget - drive it the way the About
    // screen's own tests do.
    final span = tester.widget<Text>(find.byKey(const Key('about_licenses_link'))).textSpan! as TextSpan;
    ((span.children!.last as TextSpan).recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget, reason: 'the licences dialog should be open');
    expect(tester.getTopLeft(find.byType(AppBar)).dy, headerBottom,
        reason: 'no band of the screen behind showing above the dialog');

    await disposeApp(tester, c);
  });

  testWidgets('the system bars are transparent with light icons', (tester) async {
    final c = quietController();
    await pumpApp(tester, c);

    // RenderView samples the annotation at the centre of each bar, so this is the style the
    // platform actually receives. The light icons also come free from MaterialApp (a dark theme
    // makes it push SystemUiOverlayStyle.light); the transparency does not, and that is what
    // stops an opaque black navigation bar sitting against kBg on Android 14 and below.
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
    expect(SystemChrome.latestStyle?.systemNavigationBarIconBrightness, Brightness.light);
    expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
    expect(SystemChrome.latestStyle?.systemNavigationBarColor, Colors.transparent);

    await disposeApp(tester, c);
  });

  testWidgets('with no system bars nothing is inset', (tester) async {
    final c = quietController();
    await pumpApp(tester, c);

    expect(tester.getTopLeft(find.byType(AppHeaderBar)).dy, 0);
    expect(tester.getTopLeft(find.byKey(const Key('app_hamburger'))).dy, lessThan(16));

    await disposeApp(tester, c);
  });
}
