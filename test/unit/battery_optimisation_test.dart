// test/unit/battery_optimisation_test.dart - asking Android whether it optimises the app (ID-521).
//
// With battery optimisation on, a Galaxy Tab S10 FE refreshed the widget only while the app was open.
// HOME SCREEN WIDGET KEY says so on Android, and nowhere else.
import 'dart:io';

import 'package:cfg_pia_wg/battery_optimisation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers the host channel and records what was asked. A null [reply] leaves no handler, which
  /// is what a build without the native side looks like.
  List<String> mockHost({Future<Object?> Function(MethodCall call)? reply}) {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(
        batteryChannel,
        reply == null
            ? null
            : (call) async {
                calls.add(call.method);
                return reply(call);
              });
    addTearDown(() => messenger.setMockMethodCallHandler(batteryChannel, null));
    return calls;
  }

  void onPlatform(TargetPlatform p) {
    debugDefaultTargetPlatformOverride = p;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  group('batteryOptimised', () {
    test('on Android, it is what Android says', () async {
      onPlatform(TargetPlatform.android);
      mockHost(reply: (_) async => true);
      expect(await batteryOptimised(), isTrue);
      mockHost(reply: (_) async => false);
      expect(await batteryOptimised(), isFalse);
    });

    test('off Android, the host is not asked and the answer is no', () async {
      onPlatform(TargetPlatform.iOS);
      final calls = mockHost(reply: (_) async => true);
      expect(await batteryOptimised(), isFalse);
      expect(calls, isEmpty);
    });

    test('an error or a missing handler reads as no warning, not a crash', () async {
      onPlatform(TargetPlatform.android);
      mockHost(reply: (_) async => throw PlatformException(code: 'unavailable'));
      expect(await batteryOptimised(), isFalse);
      mockHost();
      expect(await batteryOptimised(), isFalse);
    });
  });

  group('openAppSettings', () {
    test('on Android, asks the host to open the app page', () async {
      onPlatform(TargetPlatform.android);
      final calls = mockHost(reply: (_) async => null);
      await openAppSettings();
      expect(calls, [kOpenAppSettingsMethod]);
    });

    test('an error is swallowed: the page simply did not open', () async {
      onPlatform(TargetPlatform.android);
      mockHost(reply: (_) async => throw PlatformException(code: 'unavailable'));
      await openAppSettings();
      mockHost();
      await openAppSettings();
    });

    test('off Android, nothing is asked', () async {
      onPlatform(TargetPlatform.iOS);
      final calls = mockHost(reply: (_) async => null);
      await openAppSettings();
      expect(calls, isEmpty);
    });
  });

  // The channel name and methods live in two languages; nothing but this catches a rename.
  test('MainActivity.kt registers the same channel and methods as Dart calls', () {
    final kotlin =
        File('android/app/src/main/kotlin/com/exponentiallydigital/pia_wireguard_cfga/MainActivity.kt').readAsStringSync();
    expect(kotlin, contains('"${batteryChannel.name}"'));
    expect(kotlin, contains('"$kIsBatteryOptimisedMethod"'));
    expect(kotlin, contains('"$kOpenAppSettingsMethod"'));
    expect(kotlin, contains('isIgnoringBatteryOptimizations(packageName)'));
    expect(kotlin, contains('Settings.ACTION_APPLICATION_DETAILS_SETTINGS'));
  });
}
