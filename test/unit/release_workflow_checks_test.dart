// What the release and check workflows must keep doing, read from their YAML (ID-623, ID-625).
//
// These are the two protections that only CI can run, so the test reads what the files say. Each was
// also seen working in CI on a throwaway branch, as CHANGELOG records, and each check here is run
// against the workflow with the protection taken out, to show the test can tell.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The text of top-level job [name] in [yml]: from its two-space header to the next job's.
String jobBlock(String yml, String name) {
  final start = yml.indexOf(RegExp('^  $name:\$', multiLine: true));
  if (start < 0) return '';
  final rest = yml.substring(start + 1);
  final next = RegExp(r'^  [a-z][a-z0-9-]*:$', multiLine: true).firstMatch(rest);
  return next == null ? rest : rest.substring(0, next.start);
}

/// Whether the iOS job queues behind other iOS jobs on the Apple account and never cancels one that is running.
bool iosJobQueues(String releaseYml) {
  final ios = jobBlock(releaseYml, 'ios-release');
  return RegExp(r'concurrency:\s*\n\s+group: apple-account\s*\n\s+cancel-in-progress: false').hasMatch(ios);
}

/// Whether the checks build a release bundle, which is the only build that runs R8.
bool checksBuildRelease(String checksYml) {
  final job = jobBlock(checksYml, 'build-release');
  return job.contains('flutter build appbundle --release') && job.contains('android/key.properties');
}

void main() {
  final release = File('.github/workflows/release.yml').readAsStringSync();
  final checks = File('.github/workflows/quality_and_security.yml').readAsStringSync();

  group('ID-625: one iOS job at a time on the Apple account', () {
    test('the iOS job queues on the apple-account group and never cancels the one running', () {
      expect(iosJobQueues(release), isTrue);
    });

    test('nothing else shares the group, so only the iOS jobs queue behind each other', () {
      expect(RegExp('group: apple-account').allMatches(release).length, 1);
      expect(jobBlock(release, 'release'), isNot(contains('apple-account')));
    });

    test('control: the same workflow without the group, or with cancel-in-progress true, fails the check', () {
      expect(iosJobQueues(release.replaceFirst('group: apple-account', 'group: other')), isFalse);
      expect(iosJobQueues(release.replaceFirst('cancel-in-progress: false\n    permissions', 'cancel-in-progress: true\n    permissions')),
          isFalse);
    });
  });

  group('ID-623: the checks run R8', () {
    test('a job builds a release bundle with a key it makes for the run', () {
      expect(checksBuildRelease(checks), isTrue);
    });

    test('the release signing config would fail without the key, which is why the job makes one', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('signingConfig = signingConfigs.getByName("release")'));
      expect(gradle, contains('isMinifyEnabled = true'), reason: 'a release build is what runs R8');
    });

    test('control: without the job, or with a debug build only, the check fails', () {
      expect(checksBuildRelease(checks.replaceFirst('  build-release:', '  build-other:')), isFalse);
      expect(checksBuildRelease(checks.replaceFirst('flutter build appbundle --release', 'flutter build apk --debug')), isFalse);
    });

    test('the job does not publish or use a secret', () {
      final job = jobBlock(checks, 'build-release');
      expect(job, isNot(contains('secrets.')));
      expect(job, isNot(contains('upload-google-play')));
    });
  });
}
