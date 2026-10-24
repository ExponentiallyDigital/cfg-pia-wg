// test/unit/widget_ios_test.dart - the iOS widget (ID-438) against the Dart side and Android's.
//
// The Swift can't be imported, any more than the Kotlin can, so both are read as text. A key, a kind or
// an app group that drifts on one side draws a blank widget rather than failing, so each is held here.
import 'dart:io';

import 'package:cfg_pia_wg/widget_bridge.dart';
import 'package:cfg_pia_wg/widget_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final swift = File('ios/CfgPiaWgWidget/CfgPiaWgWidget.swift').readAsStringSync();
  final kotlin =
      File('android/app/src/main/kotlin/com/exponentiallydigital/pia_wireguard_cfga/widget/WidgetKeys.kt').readAsStringSync();
  final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

  Set<String> all(RegExp pattern, String text) => {for (final m in pattern.allMatches(text)) m.group(1)!};

  test('the Swift reads every key the Dart side writes, as Android does, and no other', () {
    final swiftKeys = all(RegExp(r'^\s+static let \w+ = "(\w+)"', multiLine: true), swift);
    final kotlinKeys = all(RegExp(r'const val \w+ = "(\w+)"'), kotlin);
    final written = buildWidgetData(WidgetStatus(tunnels: const [], checkedAt: DateTime(2026, 10, 21)), now: DateTime(2026, 10, 21)).keys.toSet();
    expect(swiftKeys, hasLength(16));
    expect(swiftKeys, kotlinKeys);
    expect(swiftKeys, written);
  });

  test("each widget's kind is the one the Dart side asks iOS to redraw", () {
    expect(all(RegExp(r'StaticConfiguration\(kind: "(\w+)"'), swift), {kTunnelsWidgetIosKind, kCompactWidgetIosKind});
  });

  test('the app, the widget and the Dart side name the same app group', () {
    expect(swift, contains('let appGroup = "$kWidgetAppGroup"'));
    for (final f in ['ios/Runner/Runner.entitlements', 'ios/CfgPiaWgWidget/CfgPiaWgWidget.entitlements']) {
      final ent = File(f).readAsStringSync();
      expect(RegExp(r'<key>com.apple.security.application-groups</key>\s*<array>\s*<string>([^<]+)</string>\s*</array>').firstMatch(ent)?.group(1),
          kWidgetAppGroup,
          reason: f);
    }
  });

  test("the colours are Android's, colour for colour", () {
    final android = {
      for (final m in RegExp(r'<color name="(widget_\w+)">#([0-9A-Fa-f]{6})</color>')
          .allMatches(File('android/app/src/main/res/values/colors.xml').readAsStringSync()))
        m.group(1)!: m.group(2)!.toUpperCase()
    };
    final ios = {for (final m in RegExp(r'Color\(hex: 0x([0-9A-F]{6})\) // (widget_\w+)').allMatches(swift)) m.group(2)!: m.group(1)!};
    // The card border has no iOS counterpart: iOS draws a widget's edge itself.
    expect(ios, {...android}..remove('widget_card_border'));
  });

  test('the widget is an extension inside the app, embedded before Thin Binary', () {
    expect(pbxproj, contains('productType = "com.apple.product-type.app-extension";'));
    expect(pbxproj, contains('dstSubfolderSpec = 13;'));
    expect(pbxproj, contains('CfgPiaWgWidget.appex in Embed Foundation Extensions'));
    // After Thin Binary, Xcode reports a dependency cycle in a Flutter app.
    final runner = pbxproj.substring(pbxproj.indexOf('97C146ED1CF9000F007C117D /* Runner */ = {'));
    expect(runner.indexOf('/* Embed Foundation Extensions */'), lessThan(runner.indexOf('/* Thin Binary */')));
    expect(runner.substring(0, runner.indexOf('};')), contains('/* PBXTargetDependency */'));
    expect(RegExp(r'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;').allMatches(pbxproj), hasLength(3));
    expect(RegExp(r'CODE_SIGN_ENTITLEMENTS = CfgPiaWgWidget/CfgPiaWgWidget.entitlements;').allMatches(pbxproj), hasLength(3));
    expect(RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = com.exponentiallydigital.cfgpiawg.widget;').allMatches(pbxproj), hasLength(3));
  });

  test("the widget carries the app's version and build number, as App Store Connect requires", () {
    final plist = File('ios/CfgPiaWgWidget/Info.plist').readAsStringSync();
    expect(plist, contains('<string>com.apple.widgetkit-extension</string>'));
    expect(RegExp(r'<key>CFBundleShortVersionString</key>\s*<string>\$\(FLUTTER_BUILD_NAME\)</string>').hasMatch(plist), isTrue);
    expect(RegExp(r'<key>CFBundleVersion</key>\s*<string>\$\(FLUTTER_BUILD_NUMBER\)</string>').hasMatch(plist), isTrue);
    // From the same Flutter settings as the app's, so the two can't differ.
    final widgetConfigs = RegExp(r'baseConfigurationReference = (\w+) /\* (Debug|Release)\.xcconfig \*/;\s*buildSettings = \{\s*CODE_SIGN_ENTITLEMENTS = CfgPiaWgWidget')
        .allMatches(pbxproj);
    expect(widgetConfigs, hasLength(3));
  });
}
