// test/screens/standalone_config_screen_test.dart - widget tests for the standalone generate screen.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/pia_service.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/screens/standalone_config_screen.dart';
import 'package:cfg_pia_wg/widgets/common_fields.dart';

import '../http_test_helpers.dart';
import '../pia_generate_harness.dart';

SessionController _controller(List<String> clipWrites) =>
    SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (t) async => clipWrites.add(t));

// In the real app AppChrome's Scaffold provides the Material ancestor every route shares; in
// isolation we supply one here.
Widget _host(SessionController c, {PiaService? service}) => SessionScope(
      controller: c,
      child: MaterialApp(
        home: Scaffold(body: StandaloneConfigScreen(service: service)),
      ),
    );

// By type, not by text: kDefaultDns also appears in the DNS field's hint and helper, so a text
// finder matches three widgets.
Finder dnsField() => find.byType(DnsField);
String dnsText(WidgetTester tester) => tester.widget<DnsField>(dnsField()).controller.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('GENERATE is disabled until region + username + password are filled', (tester) async {
    final c = _controller([]);
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    ElevatedButton btn() => tester.widget<ElevatedButton>(find.byKey(const Key('generate_config')));
    expect(btn().onPressed, isNull); // grey

    await tester.enterText(find.widgetWithText(TextFormField, 'Region ID'), kTestRegion);
    await tester.enterText(find.widgetWithText(TextFormField, 'PIA username'), 'p1234567');
    await tester.enterText(find.widgetWithText(TextFormField, 'PIA password'), 'secret');
    await tester.pump();
    expect(btn().onPressed, isNotNull); // green

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  // A config restored from the session (navigating back to the screen) carries its region with it.
  testWidgets('the heading names the region of a config restored from the session', (tester) async {
    final c = _controller([])
      ..generatedConfig = '[Interface]'
      ..generatedRegionId = 'aus_melbourne';
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('generated_config_label'))).data, 'GENERATED CONFIG: pia-aus_melbourne');

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  // Defensive: a config with no region anywhere still gets a sensible heading rather than
  // "GENERATED CONFIG: pia-".
  testWidgets('the heading drops the suffix when no region is known', (tester) async {
    final c = _controller([])..generatedConfig = '[Interface]';
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('generated_config_label'))).data, 'GENERATED CONFIG');

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  // Reported: clear the DNS field, leave the screen, come back - the field is empty but a
  // generate still quietly used the Quad9 defaults, so what was shown was not what was used.
  group('DNS defaults', () {
    testWidgets('a blank DNS in the session is refilled with the Quad9 defaults on entry', (tester) async {
      final c = _controller([])..dns = '';
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();

      expect(dnsText(tester), kDefaultDns);
      expect(c.dns, kDefaultDns, reason: 'the session is corrected too, so other screens agree');

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('the field can still be cleared to retype it', (tester) async {
      final c = _controller([]);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();

      await tester.enterText(dnsField(), '');
      await tester.pump();
      expect(dnsText(tester), isEmpty, reason: 'not refilled mid-edit');

      await tester.enterText(dnsField(), '1.1.1.1');
      await tester.pump();
      expect(c.dns, '1.1.1.1');

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  testWidgets('PIA credentials pre-fill from the shared session', (tester) async {
    final c = _controller([])
      ..piaUsername = 'puser'
      ..piaPassword = 'ppass';
    await tester.pumpWidget(_host(c));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'puser'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  group('full generate path', () {
    ServerSocket? probeServer;
    StreamSubscription<Socket>? sub;

    // Ephemeral port (0) + PiaService(probePort:) — no fixed port, so nothing to contend with
    // when flutter test runs this file alongside the others in parallel workers.
    setUp(() async {
      probeServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      sub = probeServer!.listen((s) => s.destroy());
    });

    tearDown(() async {
      await sub?.cancel();
      sub = null;
      await probeServer?.close();
      probeServer = null;
    });

    testWidgets('generates a config and reveals COPY + SHARE/SAVE (no push button)', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final clip = <String>[];
      final c = _controller(clip);
      await withFakeHttpClient(() async {
        await tester.pumpWidget(_host(c, service: PiaService(probePort: probeServer!.port)));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextFormField, 'Region ID'), kTestRegion);
        await tester.enterText(find.widgetWithText(TextFormField, 'PIA username'), 'p1234567');
        await tester.enterText(find.widgetWithText(TextFormField, 'PIA password'), 'secret');
        await tester.pump();

        await tester.tap(find.byKey(const Key('generate_config')));
        await driveUntil(tester, () => find.byKey(const Key('generated_config_text')).evaluate().isNotEmpty);

        expect(find.byKey(const Key('generated_config_text')), findsOneWidget);
        // The heading names the region, in the same form as the pia-<region>.conf that
        // SHARE / SAVE writes, so it is obvious which region the config on screen is for.
        expect(tester.widget<Text>(find.byKey(const Key('generated_config_label'))).data, 'GENERATED CONFIG: pia-$kTestRegion');
        expect(find.text('COPY'), findsOneWidget);
        expect(find.text('SHARE / SAVE'), findsOneWidget);
        expect(find.text('PUSH CONFIG TO ROUTER...'), findsNothing);

        await tester.tap(find.text('COPY'));
        await tester.pump();
        expect(clip, isNotEmpty);
        expect(clip.last, contains('[Interface]'));
        expect(find.text('Config copied'), findsOneWidget);
      }, fakeGenerateResponses);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    // The whole point of the fix: with the field cleared, the config must use what the field ends
    // up showing, not a default hidden inside PiaService.
    testWidgets('a blank DNS field is filled in before generating, and that is what the config uses', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final c = _controller([]);
      await withFakeHttpClient(() async {
        await tester.pumpWidget(_host(c, service: PiaService(probePort: probeServer!.port)));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextFormField, 'Region ID'), kTestRegion);
        await tester.enterText(find.widgetWithText(TextFormField, 'PIA username'), 'p1234567');
        await tester.enterText(find.widgetWithText(TextFormField, 'PIA password'), 'secret');
        await tester.enterText(dnsField(), '');
        await tester.pump();
        expect(dnsText(tester), isEmpty);

        await tester.tap(find.byKey(const Key('generate_config')));
        await driveUntil(tester, () => find.byKey(const Key('generated_config_text')).evaluate().isNotEmpty);

        expect(dnsText(tester), kDefaultDns);
        expect(c.generatedConfig, contains('DNS = $kDefaultDns'));
      }, fakeGenerateResponses);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    // Each login gets its own AutofillGroup. Sharing one would let a provider offer the router's SSH
    // password for the PIA field and vice versa, and would save a single mixed-up vault entry.
    group('each set of credentials is its own AutofillGroup', () {
      /// The hint lists of every field inside [group], in order.
      List<List<String>> hintsIn(WidgetTester tester, Element group) {
        final hints = <List<String>>[];
        void visit(Element el) {
          final w = el.widget;
          if (w is EditableText && (w.autofillHints?.isNotEmpty ?? false)) {
            hints.add(w.autofillHints!.toList());
          }
          el.visitChildren(visit);
        }

        visit(group);
        return hints;
      }

      testWidgets('the generate screen groups only the PIA credentials', (tester) async {
        final c = _controller([]);
        await tester.pumpWidget(_host(c));
        await tester.pumpAndSettle();

        final groups = find.byType(AutofillGroup).evaluate().toList();
        expect(groups, hasLength(1));
        expect(
            hintsIn(tester, groups.single),
            [
              [AutofillHints.username],
              [AutofillHints.password],
            ],
            reason: 'username and password, and nothing else - not the DNS field');

        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      testWidgets('the group cancels on dispose, so leaving asks nothing', (tester) async {
        final c = _controller([]);
        await tester.pumpWidget(_host(c));
        await tester.pumpAndSettle();

        final group = tester.widget<AutofillGroup>(find.byType(AutofillGroup));
        expect(group.onDisposeAction, AutofillContextAction.cancel);

        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });
    });

    // A password manager only offers to save when the app finishes the autofill context. Doing that
    // on success alone means the prompt appears when the credentials are known good, and never after
    // a typo or a cancelled form.
    group('save prompt', () {
      /// Records `shouldSave` for every finishAutofillContext that reaches the platform. The
      /// method fires on both paths - a cancelled group sends `shouldSave: false` - so the
      /// argument is what decides whether the password manager offers to save anything.
      List<bool> savePrompts(WidgetTester tester) {
        final prompts = <bool>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          if (call.method == 'TextInput.finishAutofillContext') prompts.add(call.arguments as bool);
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, null));
        return prompts;
      }

      testWidgets('a successful generate offers to save the PIA credentials', (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prompts = savePrompts(tester);
        final c = _controller([]);
        await withFakeHttpClient(() async {
          await tester.pumpWidget(_host(c, service: PiaService(probePort: probeServer!.port)));
          await tester.pumpAndSettle();

          await tester.enterText(find.widgetWithText(TextFormField, 'Region ID'), kTestRegion);
          await tester.enterText(find.widgetWithText(TextFormField, 'PIA username'), 'p1234567');
          await tester.enterText(find.widgetWithText(TextFormField, 'PIA password'), 'secret');
          await tester.pump();

          await tester.tap(find.byKey(const Key('generate_config')));
          await driveUntil(tester, () => find.byKey(const Key('generated_config_text')).evaluate().isNotEmpty);

          expect(prompts, contains(true), reason: 'PIA accepted them, so offer to save');
        }, fakeGenerateResponses);

        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      // Leaving the screen with credentials typed in must NOT raise a save prompt - that is what
      // onDisposeAction.cancel buys, and without it a half-filled form would offer to save itself.
      testWidgets('typing credentials and leaving offers nothing', (tester) async {
        final prompts = savePrompts(tester);
        final c = _controller([]);
        await tester.pumpWidget(_host(c));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextFormField, 'PIA username'), 'p1234567');
        await tester.enterText(find.widgetWithText(TextFormField, 'PIA password'), 'secret');
        await tester.pump();

        await tester.pumpWidget(const SizedBox()); // leave the screen
        await tester.pumpAndSettle();

        expect(prompts, isNot(contains(true)), reason: 'nothing has been proven, so nothing is worth saving');
        c.dispose();
      });
    });
  });

  testWidgets('region picker loads and selects a region', (tester) async {
    final c = _controller([]);
    await withFakeHttpClient(() async {
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.list_alt));
      await tester.pumpAndSettle();
      expect(find.text(kTestRegion), findsOneWidget);

      await tester.tap(find.text(kTestRegion));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, kTestRegion), findsOneWidget);
    }, fakeGenerateResponses);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
