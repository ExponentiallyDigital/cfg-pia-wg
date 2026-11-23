// What the redesigned pipeline must keep doing, read from the YAML (ID-630).
//
// A release builds and signs beside the quality and security checks instead of after them, which is what
// makes it fast, and is only as safe as before while nothing is published until every check has passed.
// So these are the protections to hold in place: each release job waits for the checks before its first
// publishing step; a release run leaves out only the builds the signed builds replace; the iOS simulator
// build runs only when the iOS side changed; and the watcher re-runs a job that never got a runner once, and
// nothing else. Each check is also run against the workflow with the protection taken out, to show the test
// can tell. The real evidence is a run: see CHANGELOG's ID-630 for the throwaway-branch runs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The text of top-level job [name] in [yml], from its two-space header to the next job's.
String jobBlock(String yml, String name) {
  final start = yml.indexOf(RegExp('^  $name:\$', multiLine: true));
  if (start < 0) return '';
  final rest = yml.substring(start + 1);
  final next = RegExp(r'^  [a-z][a-z0-9-]*:$', multiLine: true).firstMatch(rest);
  return next == null ? rest : rest.substring(0, next.start);
}

/// Whether the job at [name] runs `scripts/wait-for-checks.sh` before every one of [publishing], each a
/// fragment of the step that publishes (an `uses:` line, a command). A missing step fails it, so a step that is
/// renamed is noticed rather than skipped.
bool waitsBeforePublishing(String yml, String name, List<String> publishing) {
  final job = jobBlock(yml, name);
  final wait = job.indexOf('sh scripts/wait-for-checks.sh');
  if (wait < 0) return false;
  for (final step in publishing) {
    final at = job.indexOf(step);
    if (at < 0 || at < wait) return false;
  }
  return true;
}

/// Whether the release jobs no longer need the checks job, which would put the checks back in front of the builds.
bool buildsBesideTheChecks(String yml) =>
    jobBlock(yml, 'release').contains('needs: [version-check, find-verified]') &&
    jobBlock(yml, 'ios-release').contains('needs: [version-check, find-verified]') &&
    !jobBlock(yml, 'release').contains('needs: quality-and-security') &&
    !jobBlock(yml, 'ios-release').contains('needs: quality-and-security');

/// What leaves the Android job: the Play upload and the GitHub release.
const List<String> androidPublishes = ['uses: r0adkll/upload-google-play@', 'uses: softprops/action-gh-release@'];

/// What leaves the iOS job: the check of what Apple has, the upload, the notes and testers, the SBOM on the release.
const List<String> iosPublishes = [
  'scripts/app_store_connect.py has-build',
  '- name: Upload to App Store Connect for TestFlight',
  '- name: TestFlight notes and testers',
  'gh release upload',
];

void main() {
  final release = File('.github/workflows/release.yml').readAsStringSync();
  final checks = File('.github/workflows/quality_and_security.yml').readAsStringSync();
  final watcher = File('.github/workflows/rerun_unacquired.yml').readAsStringSync();

  group('ID-630: the release builds beside the checks and publishes only after them', () {
    test('neither release job waits for the checks job, so the builds start with the checks', () {
      expect(buildsBesideTheChecks(release), isTrue);
    });

    test('the Android job waits for the checks before the Play upload and the GitHub release', () {
      expect(waitsBeforePublishing(release, 'release', androidPublishes), isTrue);
    });

    test('the iOS job waits for the checks before anything goes to Apple or the release', () {
      expect(waitsBeforePublishing(release, 'ios-release', iosPublishes), isTrue);
    });

    test('the wait is a step of its own, and gives the script a token that can read the run', () {
      for (final name in ['release', 'ios-release']) {
        final job = jobBlock(release, name);
        expect(job, contains('- name: Wait for the quality and security checks'), reason: name);
        expect(job, contains('actions: read'), reason: '$name needs it to read the run\'s jobs');
      }
    });

    test('the checks still need the version check, and a release run asks for the lighter set', () {
      final call = jobBlock(release, 'quality-and-security');
      expect(call, contains('needs: [version-check, find-verified]'));
      expect(call, contains("release_run: \${{ inputs.build_apk != 'release-apk' }}"));
    });

    test('the debug APK a manual run asked for is fetched after the wait, since the checks build it beside the job', () {
      final job = jobBlock(release, 'release');
      expect(job.indexOf('sh scripts/wait-for-checks.sh'), lessThan(job.indexOf('- name: Download debug APK from quality checks')));
    });

    test('control: without the wait, with it after a publishing step, or with the old need, the checks fail', () {
      expect(waitsBeforePublishing(release.replaceAll('sh scripts/wait-for-checks.sh', 'true'), 'release', androidPublishes), isFalse);
      expect(waitsBeforePublishing(release.replaceAll('sh scripts/wait-for-checks.sh', 'true'), 'ios-release', iosPublishes), isFalse);
      // The wait taken out of its place and put after the Play upload is no gate.
      final moved = release
          .replaceFirst('run: sh scripts/wait-for-checks.sh', 'run: true')
          .replaceFirst('- name: Delete AAB file', '- name: Wait late\n        run: sh scripts/wait-for-checks.sh\n\n      - name: Delete AAB file');
      expect(waitsBeforePublishing(moved, 'release', androidPublishes), isFalse);
      expect(buildsBesideTheChecks(release.replaceFirst('needs: [version-check, find-verified]\n\n    concurrency', 'needs: quality-and-security\n\n    concurrency')), isFalse);
    });
  });

  group('ID-685: a tag run reuses what a release run on dev recorded for the same source tree', () {
    test('only a tag run looks for a recorded pass, and the checks are skipped only when one is found', () {
      final find = jobBlock(release, 'find-verified');
      expect(find, contains("IS_TAG: \${{ startsWith(github.ref, 'refs/tags/v') }}"));
      expect(find, contains('sh scripts/find-recorded-build.sh verified'));
      expect(jobBlock(release, 'quality-and-security'), contains("if: \${{ needs.find-verified.outputs.verified != 'true' }}"));
    });

    test('a pass is recorded only after the checks passed, and only from dev, main or a tag', () {
      final job = jobBlock(release, 'record-verified');
      expect(job, contains('needs: quality-and-security'));
      expect(job, contains("needs.quality-and-security.result == 'success'"));
      for (final ref in ['refs/heads/dev', 'refs/heads/main', 'refs/tags/v']) {
        expect(job, contains(ref), reason: ref);
      }
      expect(job, contains('name: \${{ env.RECORD_NAME }}'));
    });

    test('both release jobs tell the wait whether the checks were recorded as passed', () {
      for (final name in ['release', 'ios-release']) {
        expect(jobBlock(release, name), contains('VERIFIED: \${{ needs.find-verified.outputs.verified }}'), reason: name);
      }
    });

    test('Apple checks the recorded .ipa before anything is published, and any failure leaves the build to run', () {
      final job = jobBlock(release, 'ios-release');
      final reuse = job.substring(job.indexOf('- name: Check Apple accepts the recorded signed build'));
      expect(reuse.split('\n').take(5).join('\n'), allOf(contains('id: reuse'), contains('continue-on-error: true')));
      expect(reuse, contains('xcrun altool --validate-app'));
      expect(job.indexOf('--validate-app'), lessThan(job.indexOf('sh scripts/wait-for-checks.sh')));
    });

    test('the build steps run unless the recorded build was accepted', () {
      final job = jobBlock(release, 'ios-release');
      for (final step in [
        '- name: Prepare the Xcode project',
        "- name: Archive, signed with the team's own certificate",
        '- name: Generate the iOS SBOM',
        '- name: Export the .ipa for App Store Connect',
        '- name: Check the .ipa is signed for the App Store by the team',
      ]) {
        final at = job.indexOf(step);
        expect(at, greaterThan(0), reason: step);
        expect(job.substring(at).split('\n').take(3).join('\n'), contains("if: \${{ steps.reuse.outputs.ok != 'true' }}"), reason: step);
      }
    });

    test('the recorded .ipa is uploaded only after the wait, and only when it was accepted and Apple does not have the build', () {
      final job = jobBlock(release, 'ios-release');
      final upload = job.substring(job.indexOf('- name: Upload the recorded .ipa to App Store Connect for TestFlight'));
      final head = upload.split('\n').take(3).join('\n');
      expect(head, contains("steps.reuse.outputs.ok == 'true'"));
      expect(head, contains("steps.asc.outputs.uploaded == 'false'"));
      expect(upload, contains('xcrun altool --upload-app'));
      expect(job.indexOf('--upload-app'), greaterThan(job.indexOf('sh scripts/wait-for-checks.sh')));
    });

    test('a build is kept for the tree only when Apple accepted it, and its key copy is removed at the end', () {
      final job = jobBlock(release, 'ios-release');
      expect(job, contains("steps.validate.outcome == 'success'"));
      expect(job, contains('name: cfg-pia-wg-ios-signed-\${{ steps.recorded.outputs.tree }}'));
      expect(job, contains('rm -f "\$HOME"/.appstoreconnect/private_keys/AuthKey_*.p8'));
    });
  });

  group('ID-630: what a release run and a pull request leave out', () {
    test('the debug APK, the release bundle, MobSF and the iOS simulator build are left out of a release run', () {
      for (final name in ['build-debug', 'build-release', 'ios-build', 'security']) {
        expect(jobBlock(checks, name), contains('inputs.release_run != true'), reason: name);
      }
    });

    test('what decides is not left out: tests, analysis, Sonar, OSV and CodeQL take no release_run condition', () {
      for (final name in ['quality', 'osv-scan', 'codeql']) {
        expect(jobBlock(checks, name), isNot(contains('release_run')), reason: name);
      }
    });

    test('the iOS simulator build runs only when the iOS side changed, and never in the weekly scan', () {
      final job = jobBlock(checks, 'ios-build');
      expect(job, contains('needs: [osv-scan, changes]'));
      expect(job, contains("needs.changes.outputs.ios == 'true'"));
      expect(job, contains("github.event_name != 'schedule'"));
    });

    test('the filter says ios for anything but a pull request, and for ios/, the lockfiles and the workflow', () {
      final job = jobBlock(checks, 'changes');
      expect(job, contains('[ "\$EVENT" != "pull_request" ]'));
      for (final path in ['ios/', r'pubspec\.yaml$', r'pubspec\.lock$', r'\.github/workflows/quality_and_security\.yml$']) {
        expect(job, contains(path), reason: path);
      }
      expect(job, contains('git diff --name-only "\$BASE_SHA" HEAD'));
    });

    test('the weekly scan leaves out both big builds and keeps everything that looks for a new vulnerability', () {
      expect(jobBlock(checks, 'build-release'), contains("github.event_name != 'schedule'"));
      expect(jobBlock(checks, 'ios-build'), contains("github.event_name != 'schedule'"));
      expect(checks, contains('cron: "25 17 * * 1"'));
      expect(jobBlock(checks, 'codeql'), isNot(contains('schedule')));
      expect(jobBlock(checks, 'osv-scan'), isNot(contains('schedule')));
    });

    test('control: a job without its release_run condition, or an iOS build with no filter, fails the check', () {
      expect(jobBlock(checks.replaceFirst("if: \${{ inputs.release_run != true }}\n    runs-on: ubuntu-latest\n    steps:\n      - name: Checkout code\n        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n\n      - name: Set up Java", "runs-on: ubuntu-latest\n    steps:\n      - name: Checkout code\n        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n\n      - name: Set up Java"), 'build-debug'),
          isNot(contains('release_run')));
      expect(jobBlock(checks.replaceFirst("needs.changes.outputs.ios == 'true' && ", ''), 'ios-build'),
          isNot(contains("needs.changes.outputs.ios == 'true'")));
    });
  });

  group('ID-630: the watcher re-runs a job that never got a runner, once', () {
    test('it watches the two workflows that build for iOS, under the names they have', () {
      expect(release, contains('name: "Build and release"'));
      expect(checks, contains('name: "Quality & security"'));
      expect(watcher, contains('workflows: ["Build and release", "Quality & security"]'));
      expect(watcher, contains('types: [completed]'));
    });

    test('it acts only on a run that did not succeed, on its first attempt, so it cannot loop', () {
      expect(watcher, contains("github.event.workflow_run.conclusion != 'success'"));
      expect(watcher, contains('github.event.workflow_run.run_attempt == 1'));
    });

    test('it re-runs only the failed jobs, and only when one says it was not acquired by a runner', () {
      expect(watcher, contains("grep -q 'was not acquired by Runner'"));
      expect(watcher, contains('gh run rerun "\$RUN_ID" --failed'));
      expect(RegExp(r'gh run rerun').allMatches(watcher).length, 1);
    });

    test('its only secret is the run\'s own token, and it checks out nothing', () {
      final named = RegExp(r'secrets\.[A-Z_]+').allMatches(watcher).map((m) => m.group(0)).toSet();
      expect(named, {'secrets.GITHUB_TOKEN'});
      expect(watcher, isNot(contains('actions/checkout')));
      expect(watcher, contains('contents: read'));
      expect(watcher, contains('actions: write'));
    });

    test('control: without the attempt check, or re-running everything, the check fails', () {
      expect(watcher.replaceFirst('github.event.workflow_run.run_attempt == 1', 'true'), isNot(contains('run_attempt == 1')));
      expect(watcher.replaceFirst('--failed', ''), isNot(contains('--failed')));
    });
  });
}
