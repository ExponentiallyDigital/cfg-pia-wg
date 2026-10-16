// test/unit/flutter_pin_test.dart - reading and moving the Flutter pin in pubspec.yaml, and finding the
// current stable in Flutter's release list (ID-410).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/flutter_pin.dart';

const String _pubspec = '''
name: cfg_pia_wg
version: 0.8.131+501
environment:
  sdk: ">=3.0.0 <4.0.0"
  flutter: 3.47.7
dependencies:
  flutter:
    sdk: flutter
''';

void main() {
  test('reads the pin under environment, not the flutter dependency', () {
    expect(pinnedFlutter(_pubspec), '3.47.7');
    expect(pinnedFlutter(_pubspec.replaceFirst('  flutter: 3.47.7', '  flutter: ">=3.10.0"')), isNull);
  });

  test("the real pubspec.yaml has a pin, so CI's flutter-version-file can read it", () {
    expect(pinnedFlutter(File('pubspec.yaml').readAsStringSync()), matches(RegExp(r'^\d+\.\d+\.\d+$')));
  });

  test('moves the pin and nothing else', () {
    final moved = withFlutterPin(_pubspec, '3.48.0');
    expect(pinnedFlutter(moved), '3.48.0');
    expect(moved, _pubspec.replaceFirst('  flutter: 3.47.7', '  flutter: 3.48.0'));
    expect(() => withFlutterPin('name: x\n', '3.48.0'), throwsStateError);
  });

  test("finds the current stable in Flutter's release list, ignoring beta", () {
    final releases = {
      'current_release': {'stable': 'bbb', 'beta': 'aaa'},
      'releases': [
        {'hash': 'aaa', 'channel': 'beta', 'version': '3.50.0-0.1.pre'},
        {'hash': 'bbb', 'channel': 'stable', 'version': '3.47.7'},
        {'hash': 'ccc', 'channel': 'stable', 'version': '3.47.6'},
      ],
    };
    expect(stableVersion(releases), '3.47.7');
    expect(stableVersion({'releases': []}), isNull);
  });

  test('compares versions as numbers', () {
    expect(isNewer('3.48.0', '3.47.7'), isTrue);
    expect(isNewer('3.47.10', '3.47.9'), isTrue);
    expect(isNewer('4.0.0', '3.99.99'), isTrue);
    expect(isNewer('3.47.7', '3.47.7'), isFalse);
    expect(isNewer('3.47.6', '3.47.7'), isFalse);
  });
}
