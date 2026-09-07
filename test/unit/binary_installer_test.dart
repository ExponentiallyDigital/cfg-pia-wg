// test/unit/binary_installer_test.dart - downloading an executable onto someone's router.
//
// The risky parts are not "does the happy path work". They are the refusals: a checksum that does
// not match must be fatal rather than a warning, a binary that will not execute must be removed
// rather than left where the missing-binary check would find it and pass, and nothing may be
// deleted to make room. Each of those is tested by making it happen.
//
// No SSH: BinaryInstaller takes the same `Future<String> Function(String)` seam the rest of the
// router code uses, so a fake router is a map from command to canned output.
import 'package:cfg_pia_wg/binary_installer.dart';
import 'package:cfg_pia_wg/firmware.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake router. [reply] decides what each command returns; every command is recorded.
///
/// It remembers the last URL handed to `wget`, so [shaOfLastDownload] can answer a checksum query
/// with the hash of the file that was actually fetched. A real router does exactly that, and
/// without it the architecture-fallback path cannot be tested - the second attempt would be scored
/// against the first attempt's expected hash and fail for the wrong reason.
class _FakeRouter {
  _FakeRouter(this.reply);
  final String Function(String cmd) reply;
  final List<String> commands = [];
  String lastUrl = '';

  Future<String> run(String cmd) async {
    commands.add(cmd);
    final url = RegExp(r"https://[^']+").firstMatch(cmd);
    if (cmd.contains('wget') && url != null) lastUrl = url.group(0)!;
    return reply(cmd);
  }

  /// The pinned hash of whichever asset was last downloaded.
  String shaOfLastDownload() {
    for (final binary in kHelperBinaries.values) {
      for (final asset in binary.assets.values) {
        if (asset.url == lastUrl) return asset.sha256;
      }
    }
    return '0' * 64;
  }

  bool ran(String fragment) => commands.any((c) => c.contains(fragment));
  int count(String fragment) => commands.where((c) => c.contains(fragment)).length;
}

const _jqSha = '8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309';

/// Default responder: everything succeeds, on aarch64, with plenty of space.
String _happy(String cmd) {
  if (cmd.startsWith('uname')) return 'aarch64';
  if (cmd.startsWith('df')) return 'Filesystem  1K-blocks  Used Available Use% Mounted on\n/dev/mtd  50000 10000 40000 20% /jffs';
  if (cmd.contains('wget')) return 'OK';
  if (cmd.contains('dgst')) return 'SHA256(/tmp/cfg_pia_wg_dl/jq.download)= $_jqSha';
  if (cmd.contains('mv ')) return 'OK';
  if (cmd.contains('-x ')) return 'OK'; // execute test
  return '';
}

void main() {
  group('archCandidates', () {
    test('the reported architecture leads', () {
      expect(archCandidates('aarch64').first, 'aarch64');
      expect(archCandidates('armv7l').first, 'armv7l');
    });

    test('the other one always follows, so a wrong report can be recovered from', () {
      // The whole point: a 64-bit kernel over a 32-bit userspace reports aarch64 and cannot run
      // an aarch64 binary. Without a second candidate that router is simply unsupported.
      expect(archCandidates('aarch64'), ['aarch64', 'armv7l']);
      expect(archCandidates('armv7l'), ['armv7l', 'aarch64']);
    });

    test('known aliases map to the right asset', () {
      expect(archCandidates('arm64').first, 'aarch64');
      expect(archCandidates('armv8l').first, 'aarch64');
      expect(archCandidates('armhf').first, 'armv7l');
      expect(archCandidates('armv6l').first, 'armv7l');
    });

    test('an unrecognised architecture still tries everything rather than giving up', () {
      expect(archCandidates('mips'), kSupportedArches);
      expect(archCandidates(''), kSupportedArches);
    });

    test('surrounding whitespace is ignored', () => expect(archCandidates('  aarch64\n').first, 'aarch64'));
  });

  group('parseAvailableKb', () {
    test('reads the available column from a BusyBox df', () {
      expect(
        parseAvailableKb('Filesystem  1K-blocks  Used Available Use% Mounted on\n/dev/mtd9  49152  8192  40960  17% /jffs'),
        40960,
      );
    });

    test('handles a device name that wrapped onto its own line', () {
      // BusyBox wraps a long device name, leaving the numbers on the following line. Counting
      // columns from the left would read the wrong field or skip the line entirely.
      expect(
          parseAvailableKb(
              'Filesystem  1K-blocks Used Available Use% Mounted on\n/dev/very/long/name\n  49152 8192 40960 17% /jffs'),
          40960);
    });

    test('returns null rather than guessing when df said nothing useful', () {
      expect(parseAvailableKb(''), isNull);
      expect(parseAvailableKb('df: /nope: No such file or directory'), isNull);
    });
  });

  group('parseSha256', () {
    test('reads openssl output', () => expect(parseSha256('SHA256(/tmp/x)= $_jqSha'), _jqSha));
    test('reads sha256sum output', () => expect(parseSha256('$_jqSha  /tmp/x'), _jqSha));
    test('is case insensitive', () => expect(parseSha256('SHA256(x)= ${_jqSha.toUpperCase()}'), _jqSha));
    test('empty when nothing hash-shaped is present', () {
      expect(parseSha256(''), '');
      expect(parseSha256('sha256sum: not found'), '');
      expect(parseSha256('deadbeef'), '', reason: 'too short to be a SHA-256');
    });
  });

  group('the pinned assets', () {
    test('every checksum is a well-formed lower-case SHA-256', () {
      // Guards against a placeholder shipping. A malformed pin would fail every install with a
      // mismatch, which looks like an attack rather than a typo.
      for (final binary in kHelperBinaries.values) {
        for (final entry in binary.assets.entries) {
          expect(entry.value.sha256, matches(RegExp(r'^[0-9a-f]{64}$')),
              reason: '${binary.name} ${entry.key} checksum is malformed');
        }
      }
    });

    test('every architecture we claim to support has an asset for both binaries', () {
      for (final binary in kHelperBinaries.values) {
        for (final arch in kSupportedArches) {
          expect(binary.assets[arch], isNotNull, reason: '${binary.name} has no $arch asset');
        }
      }
    });

    test('urls are pinned to an exact version, never "latest"', () {
      for (final binary in kHelperBinaries.values) {
        for (final asset in binary.assets.values) {
          expect(asset.url, startsWith('https://'), reason: 'must not download over plain HTTP');
          expect(asset.url.contains('/latest/'), isFalse, reason: '"latest" is not a pin');
          expect(asset.url, contains(binary.version.replaceAll('v', '')));
        }
      }
    });

    test('jq is a raw binary and mailsend-go is an archive', () {
      // Which one it is decides whether the hash can be compared with anything upstream publishes.
      for (final asset in kJqBinary.assets.values) {
        expect(asset.isArchive, isFalse);
      }
      for (final asset in kMailsendBinary.assets.values) {
        expect(asset.isArchive, isTrue, reason: 'the ARCHIVE is what gets verified, not its contents');
      }
    });

    test('destinations are the paths missingStockBinaries probes', () {
      expect(kHelperBinaries[kStockJqPath]!.destination, kStockJqPath);
      expect(kHelperBinaries[kStockMailsendPath]!.destination, kStockMailsendPath);
    });
  });

  group('install', () {
    test('a clean run verifies, installs and reports the architecture', () async {
      final router = _FakeRouter(_happy);
      final result = await BinaryInstaller(router.run).install(kJqBinary);

      expect(result.ok, isTrue);
      expect(result.arch, 'aarch64');
      expect(router.ran('jq-linux-arm64'), isTrue);
      expect(router.ran('chmod 755'), isTrue);
    });

    test('the checksum is computed BEFORE the binary is moved into place', () async {
      final router = _FakeRouter(_happy);
      await BinaryInstaller(router.run).install(kJqBinary);
      final hashed = router.commands.indexWhere((c) => c.contains('dgst'));
      final moved = router.commands.indexWhere((c) => c.contains('mv '));
      expect(hashed, greaterThan(-1));
      expect(hashed, lessThan(moved), reason: 'verifying after installing would verify nothing');
    });

    test('A MISMATCHED CHECKSUM IS FATAL and nothing is installed', () async {
      final router = _FakeRouter((cmd) => cmd.contains('dgst') ? 'SHA256(x)= ${'0' * 64}' : _happy(cmd));
      final result = await BinaryInstaller(router.run).install(kJqBinary);

      expect(result.ok, isFalse);
      expect(result.error, contains('checksum'));
      expect(router.ran('mv '), isFalse, reason: 'a file that failed verification must never be installed');
    });

    test('refuses to install when no checksum could be computed at all', () async {
      // Better to fail than to install something unverified because the tool was missing.
      final router = _FakeRouter((cmd) => cmd.contains('dgst') ? 'sha256sum: applet not found' : _happy(cmd));
      final result = await BinaryInstaller(router.run).install(kJqBinary);

      expect(result.ok, isFalse);
      expect(result.error, contains('unverified'));
      expect(router.ran('mv '), isFalse);
    });

    test('a binary that will not run is REMOVED, not left behind', () async {
      // Left in place it would satisfy the missing-binary check, and the real failure would then
      // surface somewhere far less obvious - mid-watchdog, on the router, days later.
      final router = _FakeRouter((cmd) => cmd.contains('-x ') ? 'FAIL' : _happy(cmd));
      final result = await BinaryInstaller(router.run).install(kJqBinary);

      expect(result.ok, isFalse);
      expect(router.ran('rm -f'), isTrue, reason: 'the broken binary must be deleted');
    });

    test('falls back to the other architecture when the first will not execute', () async {
      var attempt = 0;
      late final _FakeRouter router;
      router = _FakeRouter((cmd) {
        if (cmd.contains('-x ')) return ++attempt == 1 ? 'FAIL' : 'OK';
        if (cmd.contains('dgst')) return 'SHA256(x)= ${router.shaOfLastDownload()}';
        return _happy(cmd);
      });
      final result = await BinaryInstaller(router.run).install(kJqBinary);

      expect(result.ok, isTrue);
      expect(result.arch, 'armv7l', reason: 'uname said aarch64 but only the 32-bit build runs');
      expect(router.ran('jq-linux-armhf'), isTrue);
    });

    test('refuses when free space is short, and does not download', () async {
      final router = _FakeRouter((cmd) => cmd.startsWith('df')
          ? 'Filesystem 1K-blocks Used Available Use% Mounted on\n/dev/mtd 50000 49900 100 99% /jffs'
          : _happy(cmd));
      final result = await BinaryInstaller(router.run).install(kJqBinary);

      expect(result.ok, isFalse);
      expect(result.error, contains('free'));
      expect(router.ran('wget'), isFalse, reason: 'check space before spending bandwidth');
    });

    test('NEVER deletes anything to make room', () async {
      final router = _FakeRouter((cmd) => cmd.startsWith('df')
          ? 'Filesystem 1K-blocks Used Available Use% Mounted on\n/dev/mtd 50000 49900 100 99% /jffs'
          : _happy(cmd));
      await BinaryInstaller(router.run).install(kJqBinary);

      // Only the scratch directory may be removed - never anything under the app directory.
      for (final cmd in router.commands.where((c) => c.contains('rm '))) {
        expect(cmd, contains('/tmp/'), reason: 'the app must not decide the user\'s files are expendable: $cmd');
      }
    });

    test('the scratch directory is cleaned up even when the install fails', () async {
      // /tmp is RAM on these routers; a few megabytes left there persist until the next reboot.
      final router = _FakeRouter((cmd) => cmd.contains('wget') ? 'FAIL' : _happy(cmd));
      await BinaryInstaller(router.run).install(kJqBinary);
      expect(router.count('rm -rf'), greaterThanOrEqualTo(2), reason: 'set up and torn down');
    });

    test('a download failure is reported without mentioning checksums', () async {
      final router = _FakeRouter((cmd) => cmd.contains('wget') ? 'FAIL' : _happy(cmd));
      final result = await BinaryInstaller(router.run).install(kJqBinary);

      expect(result.ok, isFalse);
      expect(result.error, contains('download failed'));
      expect(router.ran('dgst'), isFalse);
    });

    test('an archive yielding no single member fails rather than guessing', () async {
      // get-bins.sh used `find ... | head -1`, which silently picks whichever entry came first.
      late final _FakeRouter router;
      router = _FakeRouter((cmd) {
        if (cmd.contains('dgst')) return 'SHA256(x)= ${router.shaOfLastDownload()}';
        if (cmd.contains('tar -xzf')) return '__OK__';
        // No exact match, two prefix matches - the case the prefix fallback must refuse rather
        // than resolve by picking the first, which is what get-bins.sh's `glob | head -1` did.
        if (cmd.startsWith('ls -1')) return 'mailsend-go-v1.0.12-linux-arm64-a\nmailsend-go-v1.0.12-linux-arm64-b';
        return _happy(cmd);
      });
      final result = await BinaryInstaller(router.run).install(kMailsendBinary);

      expect(result.ok, isFalse);
      expect(result.error, contains('more than one'), reason: 'the message must say WHICH problem it was');
      expect(router.ran('mv '), isFalse);
    });

    // The 2026-09-07 hardware run failed here on both architectures with "did not contain exactly
    // one", which could equally have meant tar failed, the archive was empty, or the binary is
    // named something else. The message has to distinguish them or the next failure is as opaque.
    test('an archive that will not open says so, and names what tar complained about', () async {
      late final _FakeRouter router;
      router = _FakeRouter((cmd) {
        if (cmd.contains('dgst')) return 'SHA256(x)= ${router.shaOfLastDownload()}';
        if (cmd.contains('tar -xzf')) return 'tar: invalid magic';
        return _happy(cmd);
      });
      final result = await BinaryInstaller(router.run).install(kMailsendBinary);

      expect(result.error, contains('could not open the archive'));
      expect(result.error, contains('invalid magic'), reason: "tar's own words are the diagnostic");
      expect(router.ran('ls -1'), isFalse, reason: 'nothing to look for if it never unpacked');
    });

    test('an archive missing the binary lists what it DID hold', () async {
      late final _FakeRouter router;
      router = _FakeRouter((cmd) {
        if (cmd.contains('dgst')) return 'SHA256(x)= ${router.shaOfLastDownload()}';
        if (cmd.contains('tar -xzf')) return '__OK__';
        if (cmd.startsWith('ls -1')) return 'README.md\nLICENSE.txt';
        return _happy(cmd);
      });
      final result = await BinaryInstaller(router.run).install(kMailsendBinary);

      // Both architectures are attempted, so this is the second one's report - hence the prefix
      // match rather than the exact arm64 name.
      expect(result.error, contains('no "mailsend-go-v1.0.12-linux-arm'));
      expect(result.error, contains('README.md'), reason: 'name the contents or the report is useless');
    });

    test('an empty archive is reported as empty, not as a missing member', () async {
      late final _FakeRouter router;
      router = _FakeRouter((cmd) {
        if (cmd.contains('dgst')) return 'SHA256(x)= ${router.shaOfLastDownload()}';
        if (cmd.contains('tar -xzf')) return '__OK__';
        if (cmd.startsWith('ls -1')) return '';
        return _happy(cmd);
      });
      final result = await BinaryInstaller(router.run).install(kMailsendBinary);
      expect(result.error, contains('unpacked nothing'));
      expect(
        result.error,
        contains('/tmp/cfg_pia_wg_dl'),
        reason: 'say WHERE it looked - the first',
      );
    });

    test('the real archive layout is handled', () async {
      // Verified on hardware 2026-09-07. The payload is named after the RELEASE, not the
      // program, and sits beside three documentation files:
      //
      //   LICENSE.txt  README.md  mailsend-go-v1.0.12-linux-arm64  platforms.txt
      //
      // Assuming a member called `mailsend-go` is what broke the first hardware run.
      late final _FakeRouter router;
      router = _FakeRouter((cmd) {
        if (cmd.contains('dgst')) return 'SHA256(x)= ${router.shaOfLastDownload()}';
        if (cmd.contains('tar -xzf')) return '__OK__';
        if (cmd.startsWith('ls -1')) {
          return 'LICENSE.txt\nREADME.md\nmailsend-go-v1.0.12-linux-arm64\nplatforms.txt';
        }
        return _happy(cmd);
      });
      final result = await BinaryInstaller(router.run).install(kMailsendBinary);

      expect(result.ok, isTrue);
      expect(router.ran('/tmp/cfg_pia_wg_dl/mailsend-go-v1.0.12-linux-arm64'), isTrue,
          reason: 'the release-named payload is the binary');
    });

    test('errors read correctly after "Could not install "', () async {
      // They are interpolated straight into that sentence, so a leading capital or a trailing full
      // stop reads wrong. Cheap to assert, and it was wrong on the first hardware run.
      final router = _FakeRouter((cmd) => cmd.contains('wget') ? 'FAIL' : _happy(cmd));
      final error = (await BinaryInstaller(router.run).install(kJqBinary)).error!;

      expect(error[0], equals(error[0].toLowerCase()), reason: 'no leading capital');
      expect(error.endsWith('.'), isFalse, reason: 'no trailing full stop');
    });

    test('progress and failures reach the ROUTER log, not just the app log', () async {
      // A support request comes with a router syslog far more often than an app screenshot.
      final router = _FakeRouter((cmd) => cmd.contains('wget') ? 'FAIL' : _happy(cmd));
      await BinaryInstaller(router.run).install(kJqBinary);

      final logged = router.commands.where((c) => c.contains('logger -t')).toList();
      expect(logged, isNotEmpty);
      expect(logged.any((c) => c.contains('downloading jq')), isTrue);
      expect(logged.any((c) => c.contains('failed')), isTrue);
    });

    test('an architecture with no working build fails only after trying every candidate', () async {
      // On a router neither build runs on, both downloads still verify - the assets are genuine,
      // just wrong. The only thing that catches it is the execute-test, which is the whole
      // argument for having one: `uname -m` alone would have installed a binary that cannot run.
      late final _FakeRouter router;
      router = _FakeRouter((cmd) {
        if (cmd.startsWith('uname')) return 'mips64';
        if (cmd.contains('dgst')) return 'SHA256(x)= ${router.shaOfLastDownload()}';
        if (cmd.contains('-x ')) return 'FAIL';
        return _happy(cmd);
      });
      final result = await BinaryInstaller(router.run).install(kJqBinary);

      expect(result.ok, isFalse);
      expect(result.error, contains('would not run'));
      expect(router.count('wget'), 2, reason: 'both candidates must be tried before giving up');
      expect(router.ran('rm -f'), isTrue, reason: 'neither broken binary may be left behind');
    });
  });

  group('verifyRuns', () {
    test('true only when the binary exists, is executable, and runs', () async {
      expect(await BinaryInstaller(_FakeRouter((_) => 'OK').run).verifyRuns('/x/jq', '--version'), isTrue);
      expect(await BinaryInstaller(_FakeRouter((_) => 'FAIL').run).verifyRuns('/x/jq', '--version'), isFalse);
    });

    test('the path is quoted, so a space in it cannot split the command', () async {
      final router = _FakeRouter((_) => 'OK');
      await BinaryInstaller(router.run).verifyRuns('/jffs/my dir/jq', '--version');
      expect(router.commands.single, contains("'/jffs/my dir/jq'"));
    });
  });
}
