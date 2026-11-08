// ID-543: Router features can be bought over and over in the simulator, against Xcode's local store
// rather than the App Store, where TestFlight lets each Apple Account buy it once with no reset.
//
// The local store is a StoreKit configuration file, used only by the "cfg-pia-wg StoreKit" scheme's Run
// action. The Runner scheme, which CI archives and `flutter` builds, must never use it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const storeKitPath = 'ios/StoreKit/cfg-pia-wg.storekit';
  const schemes = 'ios/Runner.xcodeproj/xcshareddata/xcschemes';
  final storeKitScheme = File('$schemes/cfg-pia-wg StoreKit.xcscheme');

  Map<String, dynamic> product() {
    final config = jsonDecode(File(storeKitPath).readAsStringSync()) as Map<String, dynamic>;
    final products = (config['products'] as List).cast<Map<String, dynamic>>();
    expect(products, hasLength(1), reason: 'one product, as in App Store Connect');
    return products.single;
  }

  test('the local store sells Router features, one-time, under the App Store product ID', () {
    final p = product();
    final script = File('scripts/app_store_connect.py').readAsStringSync();
    final iapProduct = RegExp(r"^IAP_PRODUCT = '([^']+)'", multiLine: true).firstMatch(script)!.group(1);
    expect(p['productID'], iapProduct, reason: 'RevenueCat knows the product only by this ID');
    expect(p['type'], 'NonConsumable');
    expect(p['displayPrice'], '9.99');
  });

  test('the StoreKit scheme runs against the local store, and the path resolves', () {
    final xml = storeKitScheme.readAsStringSync();
    final ref = RegExp(r'<StoreKitConfigurationFileReference\s+identifier = "([^"]+)"').firstMatch(xml)!.group(1)!;
    // Xcode reads the path from the workspace it has open, ios/Runner.xcworkspace, the one Flutter
    // projects are opened by: `../../` from there reaches past ios/, and showed red in Xcode (2026-11-08).
    final resolved = File('ios/Runner.xcworkspace/$ref').absolute.path;
    expect(File(resolved).existsSync(), isTrue, reason: '$ref must reach $storeKitPath');
    expect(File(resolved).resolveSymbolicLinksSync(), File(storeKitPath).absolute.resolveSymbolicLinksSync());
    expect(xml, contains('BlueprintName = "Runner"'), reason: 'it runs the same app target');
    expect(File('ios/Runner.xcworkspace/contents.xcworkspacedata').readAsStringSync(),
        contains('location = "group:StoreKit/cfg-pia-wg.storekit"'), reason: 'Xcode lists it in the workspace');
    expect(File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(), isNot(contains('cfg-pia-wg.storekit')),
        reason: 'the store file is never built into the app');
  });

  test('the Runner scheme, which CI archives, never uses the local store', () {
    expect(File('$schemes/Runner.xcscheme').readAsStringSync(), isNot(contains('StoreKitConfigurationFileReference')));
  });

  test("the key's file is one git ignores", () {
    final script = File('scripts/xcode-storekit.sh').readAsStringSync();
    expect(script, contains('secrets/revenuecat_ios_key'));
    expect(File('.gitignore').readAsLinesSync(), contains('secrets/'));
  });
}
