// ID-441: iOS offers to save a login only for an app that names its website as an Associated Domain
// (`webcredentials:`), and that website names the app back in its apple-app-site-association file.
// Both halves must agree on the host, the team and the bundle ID, or iOS silently offers nothing.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const host = 'www.exponentiallydigital.com';
  final entitlements = File('ios/Runner/Runner.entitlements').readAsStringSync();
  final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
  final aasa = jsonDecode(File('app-store/apple-app-site-association').readAsStringSync()) as Map<String, dynamic>;

  String setting(String name) => RegExp('$name = ([^;]+);').firstMatch(pbxproj)!.group(1)!.trim();

  test('the app names its website for saved passwords', () {
    expect(entitlements, contains('<key>com.apple.developer.associated-domains</key>'));
    expect(entitlements, contains('<string>webcredentials:$host</string>'));
  });

  test("the website's file names this app: team and bundle ID", () {
    final app = '${setting('DEVELOPMENT_TEAM')}.com.exponentiallydigital.cfgpiawg';
    expect(pbxproj, contains('PRODUCT_BUNDLE_IDENTIFIER = com.exponentiallydigital.cfgpiawg;'));
    expect((aasa['webcredentials'] as Map)['apps'], [app]);
  });
}
