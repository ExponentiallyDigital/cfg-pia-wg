// test/unit/ios_build_info_test.dart - ABOUT's build info on iOS (ID-395) is three files that must agree:
// ios/Runner/AppDelegate.swift answers the channel, lib/build_info_service.dart reads its map, and
// ios/stamp_build_info.sh writes the build's facts into the Info.plist the Swift side reads them from.
// None of them can see the others, so a renamed key would only show as "unknown" on an iPhone. These are
// shape tests; the evidence is the iOS job in quality_and_security.yml, which reads the stamped values
// back out of the built app, and ABOUT on a real iPhone.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/build_info_service.dart';

void main() {
  final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
  final dart = File('lib/build_info_service.dart').readAsStringSync();
  final stamp = File('ios/stamp_build_info.sh').readAsStringSync();
  final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

  Set<String> all(RegExp pattern, String text) => {for (final m in pattern.allMatches(text)) m.group(1)!};

  test('the Swift side answers the channel and method the Dart side calls', () {
    expect(swift, contains('static let channelName = "${buildInfoChannel.name}"'));
    expect(swift, contains('static let getBuildInfo = "$kGetBuildInfoMethod"'));
  });

  test('every key the Dart side reads is in the map the Swift side answers, except Android-only Kotlin', () {
    final read = all(RegExp(r"value\('(\w+)'\)"), dart);
    final answered = all(RegExp(r'^\s+"(\w+)": ', multiLine: true), swift);
    expect(read, isNotEmpty);
    expect(answered, isNotEmpty);
    expect(read.difference(answered), {'kotlinVersion'});
    expect(answered.difference(read), isEmpty, reason: 'a key nobody reads');
  });

  test('every build fact the Swift side reads from Info.plist is one the stamp script writes', () {
    final wanted = all(RegExp(r'value\("(Cfg\w+)"\)'), swift);
    final written = all(RegExp(r'^stamp (Cfg\w+) ', multiLine: true), stamp);
    expect(wanted, hasLength(6));
    expect(written, wanted);
  });

  test("the stamp runs as the Runner target's last build phase", () {
    final phases = RegExp(r'97C146ED1CF9000F007C117D /\* Runner \*/ = \{.*?buildPhases = \((.*?)\);', dotAll: true)
        .firstMatch(pbxproj)!
        .group(1)!;
    final names = all(RegExp(r'/\* ([^*]+) \*/'), phases).toList();
    expect(names.last, 'Stamp build info', reason: 'after Thin Binary, so it writes the processed Info.plist');
    expect(pbxproj, contains(r'shellScript = "/bin/sh \"$SRCROOT/stamp_build_info.sh\"";'));
  });
}
