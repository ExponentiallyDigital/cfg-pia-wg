// ID-527: nothing the app keeps on an Android phone leaves it. allowBackup="false" stops Google Drive
// backup; from Android 12 a device-to-device transfer ignores it, so data_extraction_rules.xml has to
// exclude every domain from both cloud backup and device transfer. The home screen widget key above all.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _manifest = 'android/app/src/main/AndroidManifest.xml';
const _rules = 'android/app/src/main/res/xml/data_extraction_rules.xml';

/// Every domain Android names for backup and transfer: the app's own storage, then its device-protected twin.
const _domains = [
  'root', 'file', 'database', 'sharedpref', 'external',
  'device_root', 'device_file', 'device_database', 'device_sharedpref',
];

void main() {
  final manifest = File(_manifest).readAsStringSync();

  test('the manifest turns backup off and names the extraction rules', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
  });

  for (final section in ['cloud-backup', 'device-transfer']) {
    test('$section excludes every domain, and includes nothing', () {
      final xml = File(_rules).readAsStringSync();
      final body = RegExp('<$section>(.*?)</$section>', dotAll: true).firstMatch(xml)?.group(1);
      expect(body, isNotNull, reason: '$_rules has no <$section>');
      for (final d in _domains) {
        expect(body, contains('<exclude domain="$d" path="." />'), reason: '$section lets $d through');
      }
      expect(body, isNot(contains('<include')));
    });
  }
}
