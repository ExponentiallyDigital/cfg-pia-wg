// test/main_screen_widget_test.dart - standalone screen reached through the full app.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test_harness.dart';
import 'http_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('standalone screen shows the form fields and generate button', (tester) async {
    final c = quietController();
    await pumpAppAtStandalone(tester, c);

    expect(find.widgetWithText(TextFormField, 'Region ID'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'PIA username'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'PIA password'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'DNS servers'), findsOneWidget);
    expect(find.text('GENERATE CONFIG'), findsOneWidget);

    await disposeApp(tester, c);
  });

  testWidgets('region picker loads, filters and selects a region', (tester) async {
    final c = quietController();
    await withFakeHttpClient(
      () async {
        await pumpAppAtStandalone(tester, c);

        await tester.tap(find.byIcon(Icons.list_alt));
        await tester.pumpAndSettle();

        expect(find.text('aus_melbourne'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, 'melbourne');
        await tester.pumpAndSettle();
        expect(find.text('aus_melbourne'), findsOneWidget);

        await tester.tap(find.text('aus_melbourne'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextFormField, 'aus_melbourne'), findsOneWidget);

        await disposeApp(tester, c);
      },
      (url, method) {
        if (url.toString().contains('vpninfo/servers/v6')) {
          return FakeHttpClientResponse(
              200,
              '${jsonEncode({
                    'regions': [
                      {
                        'id': 'aus_melbourne',
                        'servers': {
                          'wg': [
                            {'ip': '1.2.3.4', 'cn': 'aus'}
                          ]
                        }
                      }
                    ]
                  })}\n');
        }
        return FakeHttpClientResponse(404, 'not found');
      },
    );
  });

  testWidgets('region picker failure surfaces an error dialog', (tester) async {
    final c = quietController();
    await withFakeHttpClient(
      () async {
        await pumpAppAtStandalone(tester, c);

        await tester.tap(find.byIcon(Icons.list_alt));
        await tester.pumpAndSettle();

        expect(find.textContaining('Failed to load regions'), findsWidgets);

        await disposeApp(tester, c);
      },
      (url, method) => FakeHttpClientResponse(500, 'server unavailable'),
    );
  });
}
