// test/unit/ios_info_plist_test.dart - what ios/Runner/Info.plist must carry for the iOS app to work (ID-402),
// and the bundle ID the App Store record will be tied to (ID-420).
//
// The app reaches the router over the home network by SSH. Since iOS 14 that asks the user for local
// network access, and the prompt shows the app's NSLocalNetworkUsageDescription; without one, iOS words
// the prompt itself and the user is asked to allow something nobody has explained.
import 'dart:io';

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

  // Andrew's choice, 2026-10-19: Android's name with spaces for dashes. Flutter's default was "Cfg Pia Wg".
  test('the name under the icon is cfg pia wg', () {
    expect(plistString(plist, 'CFBundleDisplayName'), 'cfg pia wg');
  });

  // ID-420. Apple treats bundle IDs as case sensitive, so Andrew chose all lower case, and the App Store
  // record is tied to it for good.
  test('the bundle IDs are all lower case, and the app is com.exponentiallydigital.cfgpiawg', () {
    final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final ids = [for (final m in RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);').allMatches(pbxproj)) m.group(1)!];
    expect(ids, hasLength(6));
    for (final id in ids) {
      expect(id, id.toLowerCase());
    }
    expect(ids.where((id) => id == 'com.exponentiallydigital.cfgpiawg'), hasLength(3), reason: 'Debug, Profile and Release');
  });
}
