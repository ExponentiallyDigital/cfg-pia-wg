// test/unit/build_script_test.dart - what scripts/build.ps1 promises about the iOS app (ID-475).
// Read, not run: the script needs flutter, Xcode and a signing account, and the real proof is a run on
// the Mac. These hold the rules a later edit could quietly drop.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('scripts/build.ps1').readAsStringSync();

  test('ipa is a mode, and only a Mac builds one', () {
    expect(script, contains(r'"^(debug|release|aab|ipa|all)$"'));
    expect(script, contains(r'if ($MODE -eq "ipa" -and -not $IsMacOS) { Stop-Build'));
  });

  test('all builds the .ipa on a Mac, and Windows is unchanged', () {
    expect(script, contains(r'$BUILD_IPA = $MODE -eq "ipa" -or ($MODE -eq "all" -and $IsMacOS)'));
  });

  test('the .ipa is exported as release.yml exports it', () {
    expect(script, contains("'--export-options-plist', 'ios/ExportOptions.plist'"));
    expect(File('.github/workflows/release.yml').readAsStringSync(), contains('-exportOptionsPlist ios/ExportOptions.plist'));
  });

  test('an .ipa built here is in the artefact check, so a stale one is caught', () {
    expect(script, contains(r'if ($BUILD_IPA) { $expected += @{ Label = "iOS IPA"; Path = $IPA_RELEASE'));
  });
}
