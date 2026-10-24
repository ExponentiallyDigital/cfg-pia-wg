// test/unit/ios_info_plist_test.dart - what ios/Runner/Info.plist must carry for the iOS app to work (ID-402),
// and the bundle ID the App Store record will be tied to (ID-420).
//
// The app reaches the router over the home network by SSH. Since iOS 14 that asks the user for local
// network access, and the prompt shows the app's NSLocalNetworkUsageDescription; without one, iOS words
// the prompt itself and the user is asked to allow something nobody has explained.
import 'dart:io';

import 'package:cfg_pia_wg/widget_refresh.dart' show kIosWidgetRefreshTask;
import 'package:flutter_test/flutter_test.dart';

/// The string value of [key] in [plist], or null when the key is absent.
String? plistString(String plist, String key) =>
    RegExp('<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>').firstMatch(plist)?.group(1);

void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();

  test('the reader finds a key and its string, and nothing for an absent key', () {
    const sample = '<dict>\n<key>A</key>\n<string>one</string>\n</dict>';
    expect(plistString(sample, 'A'), 'one');
    expect(plistString(sample, 'B'), isNull);
  });

  test('the local network prompt says why the app wants the home network', () {
    final why = plistString(plist, 'NSLocalNetworkUsageDescription');
    expect(why, isNotNull, reason: 'iOS would word the prompt itself');
    expect(why, contains('router'));
  });

  // Andrew's choice, 2026-10-20: the same name as Android, hyphens and all. From 2026-10-19 it was
  // "cfg pia wg"; Flutter's default was "Cfg Pia Wg".
  test('the name under the icon is cfg-pia-wg', () {
    expect(plistString(plist, 'CFBundleDisplayName'), 'cfg-pia-wg');
  });

  // ID-420. Andrew chose all lower case, and the App Store record is tied to it for good. Apple's
  // registration ignores case: the lower-case ID registered only once the old cfgPiaWg was removed (ID-427).
  test('the bundle IDs are all lower case, and the app is com.exponentiallydigital.cfgpiawg', () {
    final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final ids = [for (final m in RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);').allMatches(pbxproj)) m.group(1)!];
    expect(ids, hasLength(9), reason: 'the app, RunnerTests and the widget (ID-438), Debug, Profile and Release');
    for (final id in ids) {
      expect(id, id.toLowerCase());
    }
    expect(ids.where((id) => id == 'com.exponentiallydigital.cfgpiawg'), hasLength(3), reason: 'Debug, Profile and Release');
    // Apple requires an extension's ID to start with its app's.
    for (final id in ids) {
      expect(id, startsWith('com.exponentiallydigital.cfgpiawg'));
    }
  });

  // ID-430. Standard encryption not provided by Apple's operating system: Apple's table asks for a
  // document only for France, the French encryption declaration, and the key is NO for an app needing
  // none (app-store/export_compliance.md). France is left out of the first release, Andrew's decision,
  // 2026-10-20, so NO; selling there is ID-462, which sets it to YES with Apple's code.
  test('the app declares only encryption needing no documents', () {
    expect(RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>').hasMatch(plist), isTrue);
  });

  // ID-429. Andrew's decision, 2026-10-20: iPhone and iPad, iPad tried on the simulator only. An iPad app
  // must allow all four orientations, or App Review's iPad multitasking check refuses it.
  test('the app is built for iPhone and iPad, with every iPad orientation', () {
    final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(RegExp(r'TARGETED_DEVICE_FAMILY = "1,2";').allMatches(pbxproj), hasLength(6), reason: 'the app and the widget, Debug, Profile and Release');
    final ipad = RegExp(r'<key>UISupportedInterfaceOrientations~ipad</key>\s*<array>(.*?)</array>', dotAll: true).firstMatch(plist)!.group(1)!;
    for (final o in ['Portrait', 'PortraitUpsideDown', 'LandscapeLeft', 'LandscapeRight']) {
      expect(ipad, contains('<string>UIInterfaceOrientation$o</string>'), reason: o);
    }
  });

  // ID-422. Andrew's individual membership, 2026-10-20. The Team ID, not the enrolment ID
  // (5N82LGHKZ2), which was briefly taken for it.
  test('every target signs with team RL4UB6WKMV', () {
    final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final teams = [for (final m in RegExp(r'DEVELOPMENT_TEAM = ([^;]+);').allMatches(pbxproj)) m.group(1)!];
    expect(teams, List.filled(9, 'RL4UB6WKMV'), reason: 'Runner, RunnerTests and the widget, Debug, Profile and Release');
  });

  // ID-424. iOS runs a background task only if Info.plist permits its identifier and the app asked for
  // background fetch, and a scene-based app must register the handler before didFinishLaunching
  // returns. One name in three places: Info.plist, AppDelegate.swift and widget_refresh.dart.
  test('the widget refresh is a permitted background task, registered at launch, under one name', () {
    final permitted = RegExp(r'<key>BGTaskSchedulerPermittedIdentifiers</key>\s*<array>(.*?)</array>', dotAll: true).firstMatch(plist);
    expect(permitted, isNotNull);
    expect(permitted!.group(1), contains('<string>$kIosWidgetRefreshTask</string>'));
    expect(RegExp(r'<key>UIBackgroundModes</key>\s*<array>\s*<string>fetch</string>').hasMatch(plist), isTrue);

    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(delegate, contains('static let identifier = "$kIosWidgetRefreshTask"'));
    final launch = RegExp(r'didFinishLaunchingWithOptions.*?return super', dotAll: true).firstMatch(delegate)!.group(0)!;
    expect(launch, contains('WidgetRefresh.register()'), reason: 'after didFinishLaunching iOS no longer hands the task over');
    expect(delegate, contains('GeneratedPluginRegistrant.register(with: registry)'), reason: 'the background engine needs the key store and the widget storage');
  });
}
