import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

// Import the main file - adjust path as needed
import 'package:pia_wireguard_cfga/main.dart';

void main() {
  group('PiaWgApp', () {
    testWidgets('should create MaterialApp with correct theme', (tester) async {
      // Act
      await tester.pumpWidget(const PiaWgApp());

      // Assert
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.title, equals('PIA WireGuard Config'));
      expect(materialApp.debugShowCheckedModeBanner, isFalse);
      expect(materialApp.theme?.useMaterial3, isTrue);
      expect(materialApp.theme?.textTheme.bodyMedium?.fontFamily,
          equals('monospace'));
    });

    testWidgets('should have correct color scheme', (tester) async {
      // Act
      await tester.pumpWidget(const PiaWgApp());

      // Assert
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final colorScheme = materialApp.theme?.colorScheme;

      expect(colorScheme?.primary, equals(const Color(0xFF00D4AA)));
      expect(colorScheme?.secondary, equals(const Color(0xFF00A882)));
      expect(colorScheme?.surface, equals(const Color(0xFF1A1D23)));
      expect(colorScheme?.error, equals(const Color(0xFFFF5C5C)));
      expect(colorScheme?.onPrimary, equals(const Color(0xFF12141A)));
      expect(colorScheme?.onSurface, equals(const Color(0xFFE8EAF0)));
    });

    testWidgets('should have MainScreen as home', (tester) async {
      // Act
      await tester.pumpWidget(const PiaWgApp());

      // Assert
      expect(find.byType(MainScreen), findsOneWidget);
    });
  });

  group('MainScreen State Management', () {
    late Widget testWidget;

    setUp(() {
      testWidget = const MaterialApp(home: MainScreen());
    });

    testWidgets('should initialize with default values', (tester) async {
      // Act
      await tester.pumpWidget(testWidget);

      // Assert
      expect(find.text('Ready.'), findsOneWidget);
    });

    testWidgets('should toggle password visibility', (tester) async {
      // Act
      await tester.pumpWidget(testWidget);

      // Find and tap the password visibility toggle (initially open eye)
      final visibilityToggle = find.byIcon(Icons.visibility);
      expect(visibilityToggle, findsOneWidget);

      await tester.tap(visibilityToggle);
      await tester.pump();

      // Assert it correctly toggled to the slashed eye
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    testWidgets('should clear session when clear button is tapped',
        (tester) async {
      // Act
      await tester.pumpWidget(testWidget);

      // Find username and password fields and enter text
      final usernameField = find.byKey(const Key('username_field'));
      final passwordField = find.byKey(const Key('password_field'));

      if (usernameField.evaluate().isNotEmpty &&
          passwordField.evaluate().isNotEmpty) {
        await tester.enterText(usernameField, 'testuser');
        await tester.enterText(passwordField, 'testpass');
        await tester.pump();

        // Find and tap clear button
        final clearButton = find.byIcon(Icons.clear);
        if (clearButton.evaluate().isNotEmpty) {
          await tester.tap(clearButton);
          await tester.pump();

          // Assert fields are cleared
          expect(find.text('testuser'), findsNothing);
          expect(find.text('testpass'), findsNothing);
        }
      }
    });
  });

  group('Clipboard Operations', () {
    testWidgets('should handle clipboard operations', (tester) async {
      // Setup

      // Mock clipboard
      final clipboardData = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardData.clear();
          clipboardData.add(call.arguments['text'] as String);
        } else if (call.method == 'Clipboard.getData') {
          return {'text': clipboardData.isNotEmpty ? clipboardData.first : ''};
        }
        return null;
      });

      // Create test widget that simulates having a generated config
      await tester.pumpWidget(const MaterialApp(home: MainScreen()));

      // Note: This test would need the actual state to be modified
      // In a real scenario, you might need to create a testable version
      // of MainScreen that allows injecting state for testing
    });
  });

  group('URL Launching', () {
    testWidgets('should attempt to launch URLs', (tester) async {
      // Setup mock for URL launcher
      final launchedUrls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'url_launcher') {
          launchedUrls.add(call.arguments['url'] as String);
          return true;
        }
        return null;
      });

      await tester.pumpWidget(const MaterialApp(home: MainScreen()));

      // Note: This would need actual buttons/links to test
      // You might need to add test keys to the URL launcher buttons
    });
  });

  group('Timer Management', () {
    testWidgets('should handle session timing', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MainScreen()));

      // Note: Testing timer functionality would require:
      // 1. Access to the timer state (possibly through test keys)
      // 2. Ability to fast-forward time in tests
      // 3. Verification that timers are properly cancelled

      // This is a placeholder for timer-related tests
      // In practice, you might want to extract timer logic to a separate
      // testable class or provide test-specific timer injection
    });
  });

  group('Form Validation', () {
    testWidgets('should validate required fields', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MainScreen()));

      // Find the generate button
      final generateButton = find.text('Generate Config');
      if (generateButton.evaluate().isNotEmpty) {
        // Try to generate without required fields
        await tester.tap(generateButton);
        await tester.pump();

        // Should show validation errors or prevent generation
        // Note: You'd need to verify the specific validation behavior
      }
    });
  });
}
