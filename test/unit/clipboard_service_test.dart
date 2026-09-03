// test/unit/clipboard_service_test.dart - emptying the clipboard without a system popup.
//
// Android shows its clipboard preview for any copy, so the old "write an empty string" clear
// flashed a "copied" popup on app exit and when the 60s countdown expired. The host clears it
// silently instead, with the write kept as a fallback.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/clipboard_service.dart';
import 'package:cfg_pia_wg/session_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers the host channel, recording the methods asked of it. A null [reply] means the
  /// handler is absent, which is what a non-Android platform or a plain test looks like.
  List<String> mockHost({Future<Object?> Function(MethodCall call)? reply}) {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(clipboardChannel, reply == null
        ? null
        : (call) async {
            calls.add(call.method);
            return reply(call);
          });
    addTearDown(() => messenger.setMockMethodCallHandler(clipboardChannel, null));
    return calls;
  }

  /// Records what reaches the platform clipboard, so a fallback write is visible.
  List<String> mockSystemClipboard() {
    final writes = <String>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') writes.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    return writes;
  }

  group('clearSystemClipboard', () {
    test('asks the host to clear, and does not write to the clipboard', () async {
      final calls = mockHost(reply: (_) async => null);
      final writes = mockSystemClipboard();

      await clearSystemClipboard();

      expect(calls, [kClearClipboardMethod]);
      expect(writes, isEmpty, reason: 'a write is what shows the popup we are avoiding');
    });

    test('falls back to writing an empty string when the host has no handler', () async {
      mockHost(); // no handler -> MissingPluginException
      final writes = mockSystemClipboard();

      await clearSystemClipboard();

      expect(writes, [''], reason: 'the clipboard must still end up empty');
    });

    // API 24..27 has no clearPrimaryClip(), so MainActivity answers with an error.
    test('falls back to writing an empty string when the host reports an error', () async {
      mockHost(reply: (_) async => throw PlatformException(code: 'unsupported'));
      final writes = mockSystemClipboard();

      await clearSystemClipboard();

      expect(writes, ['']);
    });
  });

  test('SessionController.clearClipboard goes through the host, a copy does not', () async {
    final calls = mockHost(reply: (_) async => null);
    final writes = mockSystemClipboard();
    final c = SessionController(tickInterval: const Duration(hours: 1)); // real writer

    await c.copyToClipboard('secret');
    expect(calls, isEmpty);
    expect(writes, ['secret']);

    await c.clearClipboard();
    expect(calls, [kClearClipboardMethod]);
    expect(writes, ['secret'], reason: 'nothing was copied to clear it');

    c.dispose();
  });

  // The channel name and method live in two languages; nothing but this catches a rename.
  test('MainActivity.kt registers the same channel and method as Dart calls', () {
    final kotlin = File('android/app/src/main/kotlin/com/exponentiallydigital/pia_wireguard_cfga/MainActivity.kt')
        .readAsStringSync();

    expect(kotlin, contains('"${clipboardChannel.name}"'));
    expect(kotlin, contains('"$kClearClipboardMethod"'));
    expect(kotlin, contains('clearPrimaryClip()'));
  });

  // Screen capture is blocked in a release build. A debug build skips FLAG_SECURE so the app can
  // be captured on a device while testing; this fails if that ever widens to a release.
  test('MainActivity.kt keeps FLAG_SECURE for release builds', () {
    final kotlin = File('android/app/src/main/kotlin/com/exponentiallydigital/pia_wireguard_cfga/MainActivity.kt')
        .readAsStringSync();

    expect(kotlin, contains('FLAG_SECURE'));
    expect(kotlin, contains(r'if (!BuildConfig.DEBUG && !allowScreenCaptureInRelease) {'));
    expect(kotlin, contains('private val allowScreenCaptureInRelease = false'),
        reason: 'the release escape hatch was left switched on');
  });
}
