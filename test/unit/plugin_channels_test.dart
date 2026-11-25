// test/unit/plugin_channels_test.dart - code that only calls a plugin, run against a stand-in for the plugin's
// platform channel (ID-717).
//
// SonarCloud showed these files under 90% line coverage, and what was uncovered was the plugin call itself: the
// home screen widget's writes, the clipboard's fallback copy, the app's version stamp. A plugin's channel can be
// answered in a test, so each call runs and is checked for what it sent.
import 'package:cfg_pia_wg/clipboard_service.dart';
import 'package:cfg_pia_wg/firmware.dart' show appVersionLabel;
import 'package:cfg_pia_wg/main.dart' show stampAppVersion;
import 'package:cfg_pia_wg/widget_bridge.dart';
import 'package:cfg_pia_wg/widget_status.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Every call a channel got, answering each from [answer] (null when it has nothing to say).
List<MethodCall> _listen(MethodChannel channel, {Object? Function(MethodCall call)? answer}) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    return answer?.call(call);
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('copySensitive', () {
    // Android and iOS answer the app's own channel; anywhere else, or when it fails, it is a plain copy.
    for (final (name, error) in [
      ('a PlatformException', PlatformException(code: 'unavailable')),
      ('no plugin at all', MissingPluginException('none')),
    ]) {
      test('falls back to a plain copy on $name', () async {
        _listen(clipboardChannel, answer: (_) => throw error);
        final plain = _listen(SystemChannels.platform);
        await copySensitive('secret');
        final set = plain.where((c) => c.method == 'Clipboard.setData').toList();
        expect(set, hasLength(1));
        expect((set.single.arguments as Map)['text'], 'secret');
      });
    }
  });

  group('stampAppVersion', () {
    test('writes the version and build the platform reports', () async {
      PackageInfo.setMockInitialValues(
          appName: 'x', packageName: 'x', version: '1.2.3', buildNumber: '45', buildSignature: '');
      addTearDown(() => appVersionLabel = '');
      await stampAppVersion();
      expect(appVersionLabel, 'v1.2.3 build 45');
    });
  });

  // The home screen widget: Android's and iOS's own code reads what is written here, so the order and the
  // types matter (the Kotlin and the Swift read the typed values).
  group('the widget bridge', () {
    const channel = MethodChannel('home_widget');
    final now = DateTime.utc(2026, 10, 12, 12);
    final status = WidgetStatus(
      tunnels: [const WidgetTunnelInfo(slot: 5, region: 'Region', up: true, handshakeAgeSeconds: 40)],
      checkedAt: now,
    );

    test('pushWidgetStatus names the app group, saves each value with its type, then redraws both widgets', () async {
      final calls = _listen(channel);
      await pushWidgetStatus(status, now: now, canRefresh: true);

      expect(calls.first.method, 'setAppGroupId');
      expect(calls.first.arguments, {'groupId': kWidgetAppGroup});
      final saved = {for (final c in calls.where((c) => c.method == 'saveWidgetData')) (c.arguments as Map)['id']: (c.arguments as Map)['data']};
      final data = buildWidgetData(status, now: now, canRefresh: true);
      for (final e in data.entries) {
        expect(saved[e.key], e.value, reason: e.key);
      }
      expect(saved.length, data.length);
      final redraws = calls.where((c) => c.method == 'updateWidget').toList();
      expect(redraws, hasLength(2), reason: 'the tunnels widget and the compact one');
      expect(redraws.map((c) => (c.arguments as Map)['qualifiedAndroidName']), [kTunnelsWidgetQualifiedName, kCompactWidgetQualifiedName]);
      expect(calls.last.method, 'updateWidget', reason: 'redrawn only after everything is written');
    });

    test('pushWidgetAttemptFailed keeps what the footer said and adds the failed attempt, touching nothing else', () async {
      final calls = _listen(channel, answer: (c) => c.method == 'getWidgetData' ? 'Checked 11:58' : null);
      await pushWidgetAttemptFailed(now);

      final saves = calls.where((c) => c.method == 'saveWidgetData').toList();
      expect(saves, hasLength(1), reason: 'the tunnel rows keep the last good reading');
      expect((saves.single.arguments as Map)['id'], 'last_checked_text');
      expect((saves.single.arguments as Map)['data'], attemptFailedFooter('Checked 11:58', now));
      expect(calls.where((c) => c.method == 'updateWidget'), hasLength(2));
    });

    test('with nothing saved before, the footer is the attempt alone', () async {
      final calls = _listen(channel);
      await pushWidgetAttemptFailed(now, WidgetAttemptFailure.unreachable);
      final saved = calls.singleWhere((c) => c.method == 'saveWidgetData').arguments as Map;
      expect(saved['data'], attemptFailedFooter('', now));
    });
  });
}
