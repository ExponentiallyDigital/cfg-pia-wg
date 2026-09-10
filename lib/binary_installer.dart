// binary_installer.dart - installs the stock-firmware helper binaries onto the router.
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see https://www.gnu.org/licenses/.
//
// Copyright (C) 2026 Andrew Newbury.
//
// Stock firmware ships neither `jq` nor `mailsend-go`, and the app cannot work without them:
// MANAGE parses PIA's JSON, and the watchdog sends email. Until now the user installed both by
// hand with scripts/get-bins.sh over SSH - a terminal, a script from GitHub, and a step that has
// nothing to do with the app they just installed. That friction is the single biggest reason to
// give up on stock support before it has done anything useful.
//
// This downloads an executable onto someone's router, so the rules are stricter than for anything
// else the app does. See .claude/plans/plan_install-helper-binaries.md for the reasoning.
//
//   - VERSIONS ARE PINNED and every download is checked against a SHA-256 shipped in the app.
//     BusyBox `wget` on stock has weak-to-absent TLS validation, so the transport cannot be
//     trusted; the checksum is what makes the result trustworthy. A mismatch is fatal, never a
//     warning. Each pinned hash below was verified against the checksum file the project
//     publishes AND recomputed on real hardware - see the plan for both.
//
//   - THE ARCHIVE IS HASHED, NOT THE EXTRACTED FILE. `jq` ships as a raw binary, so its hash is
//     directly comparable to the published one. `mailsend-go` ships as a .tar.gz; hashing the
//     binary inside it would produce a number nothing upstream publishes, which is trust-on-first-
//     use dressed up as verification. So the archive is verified before it is opened.
//
//   - THE ARCHITECTURE IS CONFIRMED BY RUNNING THE BINARY, not by trusting `uname -m`. A 64-bit
//     kernel with a 32-bit userspace is common on these devices, so the reported architecture is a
//     hint. If the first candidate will not execute, the other is tried before giving up.
//
//   - NOTHING IS DELETED TO MAKE ROOM. The app did not put whatever is on /jffs and does not get
//     to decide it is expendable.
//
// The caller is responsible for asking permission first, and - once freemium lands - for checking
// the entitlement BEFORE any of this runs. A user who cannot use the feature must not be prompted
// to put binaries on their router for it.
import 'firmware.dart';
import 'router_watchdog.dart' show buildLoggerCommand, shellSingleQuote;

/// One downloadable artefact for one architecture.
class HelperAsset {
  /// Release asset URL. Pinned to an exact version - never "latest", which would put whatever
  /// upstream published this morning onto the user's router, unreviewed.
  final String url;

  /// SHA-256 of the file at [url] exactly as downloaded, lower-case hex.
  final String sha256;

  /// Published size in bytes, used for the free-space estimate. Real figures from the release
  /// metadata rather than guesses.
  final int bytes;

  /// For an archive, the exact basename of the binary inside it - which is NOT the program's own
  /// name. mailsend-go ships a flat archive whose payload carries the release in its filename:
  ///
  ///     LICENSE.txt  README.md  mailsend-go-v1.0.12-linux-arm64  platforms.txt
  ///
  /// Assuming `mailsend-go` found nothing on the first hardware run. Null when [url] is the
  /// binary itself.
  final String? memberName;

  const HelperAsset({required this.url, required this.sha256, required this.bytes, this.memberName});

  bool get isArchive => memberName != null;

  /// `github.com/owner/repo` for display. "from github.com" is about as informative as "from the
  /// internet" when the user is being asked to approve running an executable.
  String get sourceLabel {
    final m = RegExp(r'^https://github\.com/([^/]+/[^/]+)/').firstMatch(url);
    return m == null ? Uri.parse(url).host : 'github.com/${m.group(1)}';
  }
}

/// A helper binary the app can install, with one [HelperAsset] per architecture it supports.
class HelperBinary {
  final String name;
  final String version;

  /// Where it ends up on the router.
  final String destination;

  /// Argument that makes it print something and exit successfully, used to prove it runs.
  final String versionFlag;

  /// Keyed by `uname -m` output.
  final Map<String, HelperAsset> assets;

  const HelperBinary({
    required this.name,
    required this.version,
    required this.destination,
    required this.versionFlag,
    required this.assets,
  });
}

/// `jq` 1.8.2. Raw binaries, so each hash is of the installed file and matches the project's
/// published `sha256sum.txt` directly.
const HelperBinary kJqBinary = HelperBinary(
  name: 'jq',
  version: '1.8.2',
  destination: kStockJqPath,
  versionFlag: '--version',
  assets: {
    'aarch64': HelperAsset(
      url: 'https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-arm64',
      sha256: '8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309',
      bytes: 1797688,
    ),
    'armv7l': HelperAsset(
      url: 'https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-armhf',
      sha256: '78458244fb546469b4042e9e07cf78714ef6848895eb9515df76b4eb0b1dc992',
      bytes: 1340000,
    ),
  },
);

/// `mailsend-go` v1.0.12. Archives, so each hash is of the `.tar.gz` and is checked before the
/// archive is opened - see the header.
const HelperBinary kMailsendBinary = HelperBinary(
  name: 'mailsend-go',
  version: 'v1.0.12',
  destination: kStockMailsendPath,
  versionFlag: '--help',
  assets: {
    'aarch64': HelperAsset(
      url: 'https://github.com/muquit/mailsend-go/releases/download/v1.0.12/mailsend-go-v1.0.12-linux-arm64.d.tar.gz',
      sha256: '408bedba0cfbcb5cdc94d4b4575d43c3d40d9fbb0b62c766da3f057987acd731',
      bytes: 2205850,
      memberName: 'mailsend-go-v1.0.12-linux-arm64',
    ),
    'armv7l': HelperAsset(
      url: 'https://github.com/muquit/mailsend-go/releases/download/v1.0.12/mailsend-go-v1.0.12-linux-arm.d.tar.gz',
      sha256: '5a35d15b1fa54b5e0da769327c635d9ea6db124df34c5656f61c71af5bc942af',
      bytes: 2376027,
      memberName: 'mailsend-go-v1.0.12-linux-arm',
    ),
  },
);

/// Everything installable, indexed by the destination path `missingStockBinaries` reports.
const Map<String, HelperBinary> kHelperBinaries = {
  kStockJqPath: kJqBinary,
  kStockMailsendPath: kMailsendBinary,
};

/// Free space demanded before downloading, as a multiple of the download size.
///
/// The extracted size of an archive is not published, and a Go binary expands considerably, so
/// this is a deliberate over-estimate rather than a figure that would have to be kept accurate.
/// `/tmp` holds the archive and its contents at once; `/jffs` holds the result.
const int kFreeSpaceMultiple = 5;

/// The architectures the pinned assets cover, most likely first for an unrecognised `uname -m`.
const List<String> kSupportedArches = ['aarch64', 'armv7l'];

/// Which architectures to try, in order, for [unameOutput].
///
/// The reported architecture leads, but it is only a hint: these routers commonly run a 64-bit
/// kernel over a 32-bit userspace, so a binary chosen from `uname -m` alone may not execute. The
/// other candidate follows so the caller can fall back rather than fail.
List<String> archCandidates(String unameOutput) {
  final reported = unameOutput.trim();
  final known = <String, String>{
    'aarch64': 'aarch64',
    'arm64': 'aarch64',
    'armv8l': 'aarch64',
    'armv7l': 'armv7l',
    'armv7': 'armv7l',
    'armhf': 'armv7l',
    'armv6l': 'armv7l',
  };
  final first = known[reported];
  if (first == null) return kSupportedArches;
  return [first, ...kSupportedArches.where((a) => a != first)];
}

/// Available kilobytes from a BusyBox `df` report, or null if it cannot be read.
///
/// BusyBox prints a header then one line per filesystem, with the available column fourth. A
/// long device name wraps onto its own line, so the numbers are found by position from the end of
/// whichever line carries them rather than by counting from the start.
int? parseAvailableKb(String dfOutput) {
  for (final line in dfOutput.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty)) {
    if (line.toLowerCase().startsWith('filesystem')) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 4) continue;
    // ... 1k-blocks used available use% mounted-on
    final available = int.tryParse(parts[parts.length - 3]);
    if (available != null) return available;
  }
  return null;
}

/// The hash from `openssl dgst -sha256 FILE` or `sha256sum FILE`, lower-case, or '' if neither
/// form is recognised. Both are accepted because which one exists varies by BusyBox build.
String parseSha256(String output) {
  final text = output.trim();
  final openssl = RegExp(r'=\s*([0-9a-fA-F]{64})\b').firstMatch(text);
  if (openssl != null) return openssl.group(1)!.toLowerCase();
  final plain = RegExp(r'\b([0-9a-fA-F]{64})\b').firstMatch(text);
  return plain == null ? '' : plain.group(1)!.toLowerCase();
}

/// Outcome of one install attempt.
class InstallResult {
  final bool ok;

  /// Architecture whose asset was installed, or the last one tried.
  final String arch;

  /// Human-readable failure, null on success.
  final String? error;

  const InstallResult.success(this.arch)
      : ok = true,
        error = null;
  const InstallResult.failure(this.arch, this.error) : ok = false;
}

/// Downloads, verifies and installs the helper binaries over an existing SSH session.
///
/// [run] executes one command on the router and returns its trimmed output - the same seam the
/// rest of the router code uses, so tests need no SSH.
class BinaryInstaller {
  BinaryInstaller(this.run, {this.onLog});

  final Future<String> Function(String cmd) run;
  final void Function(String message, {bool isError, bool isSuccess})? onLog;

  /// Writes to the app log AND the router syslog, so a failure is diagnosable from the router
  /// afterwards rather than only from a screenshot of the app. Mirrors RouterWatchdog._logRouter.
  Future<void> _log(String m, {bool isError = false, bool isSuccess = false}) async {
    onLog?.call(m, isError: isError, isSuccess: isSuccess);
    try {
      await run(buildLoggerCommand('install: $m'));
    } catch (_) {
      // Best-effort: never fail an install because the router would not take a log line.
    }
  }

  /// `uname -m`, untranslated.
  Future<String> reportedArch() async => (await run('uname -m')).trim();

  /// Whether [path] exists, is executable, and actually runs. The last part matters: a binary
  /// built for the wrong architecture, or left half-written by an interrupted download, exists
  /// and is executable and still does nothing useful.
  Future<bool> verifyRuns(String path, String versionFlag) async {
    final q = shellSingleQuote(path);
    final out = await run('[ -x $q ] && $q $versionFlag >/dev/null 2>&1 && echo OK || echo FAIL');
    return out.contains('OK');
  }

  /// Free kilobytes on the filesystem holding [path], or null if `df` could not be read.
  Future<int?> freeKb(String path) async => parseAvailableKb(await run('df ${shellSingleQuote(path)} 2>/dev/null'));

  /// Installs [binary], trying each architecture from [archCandidates] until one runs.
  ///
  /// Returns the first success, or the failure from the last attempt. Nothing is left behind on
  /// failure: a downloaded file that did not verify is removed rather than retried later.
  Future<InstallResult> install(HelperBinary binary) async {
    final reported = await reportedArch();
    final candidates = archCandidates(reported);
    await _log('${binary.name} ${binary.version}: router reports architecture "$reported", '
        'will try ${candidates.join(' then ')}.');

    InstallResult? last;
    for (final arch in candidates) {
      final asset = binary.assets[arch];
      if (asset == null) continue;
      last = await _installAsset(binary, asset, arch);
      if (last.ok) return last;
      await _log('${binary.name} $arch failed: ${last.error}', isError: true);
    }
    return last ??
        InstallResult.failure(
          reported,
          'no ${binary.name} build for architecture "$reported" - install it by hand with scripts/get-bins.sh',
        );
  }

  Future<InstallResult> _installAsset(HelperBinary binary, HelperAsset asset, String arch) async {
    final tmp = '/tmp/cfg_pia_wg_dl';
    final download = '$tmp/${binary.name}.download';
    final needKb = (asset.bytes * kFreeSpaceMultiple) ~/ 1024;

    await run('rm -rf ${shellSingleQuote(tmp)}; mkdir -p ${shellSingleQuote(tmp)}');
    try {
      // Space first: failing here costs nothing, whereas failing mid-write leaves a truncated
      // file occupying the space that made it fail.
      for (final entry in {'/tmp': tmp, kRouterAppDir: kRouterAppDir}.entries) {
        final free = await freeKb(entry.value);
        if (free != null && free < needKb) {
          return InstallResult.failure(
            arch,
            '${entry.key} has only ${(free / 1024).toStringAsFixed(1)} MB free, '
            '${binary.name} needs about ${(needKb / 1024).toStringAsFixed(1)} MB',
          );
        }
      }

      await _log('downloading ${binary.name} ${binary.version} ($arch, '
          '${(asset.bytes / 1048576).toStringAsFixed(1)} MB) from ${asset.sourceLabel}');
      final got = await run(
        'wget -T 60 -O ${shellSingleQuote(download)} ${shellSingleQuote(asset.url)} >/dev/null 2>&1 && echo OK || echo FAIL',
      );
      if (!got.contains('OK')) {
        return InstallResult.failure(arch, 'download failed - check the router can reach ${asset.sourceLabel}');
      }

      // The checksum is the whole security argument - the transport is not trusted, so a
      // mismatch is fatal and the file is destroyed rather than kept for inspection.
      final digest = parseSha256(await run(
        'openssl dgst -sha256 ${shellSingleQuote(download)} 2>/dev/null || sha256sum ${shellSingleQuote(download)} 2>/dev/null',
      ));
      if (digest.isEmpty) {
        return InstallResult.failure(
            arch, 'no checksum tool on the router (openssl, sha256sum) - refusing to install unverified');
      }
      if (digest != asset.sha256) {
        await _log('checksum mismatch for ${binary.name} $arch: expected ${asset.sha256}, got $digest', isError: true);
        return InstallResult.failure(
          arch,
          'checksum did not match and the download was discarded - either it was corrupted, '
          'or something altered it in transit',
        );
      }
      await _log('${binary.name} $arch checksum verified');

      String? staged = download;
      if (asset.isArchive) {
        final extracted = await _extract(tmp, download, asset.memberName!);
        if (extracted.path == null) return InstallResult.failure(arch, extracted.problem!);
        staged = extracted.path;
      }

      await run('mkdir -p ${shellSingleQuote(kRouterAppDir)}');
      final dest = shellSingleQuote(binary.destination);
      final moved = await run('mv ${shellSingleQuote(staged!)} $dest && chmod 755 $dest && echo OK || echo FAIL');
      if (!moved.contains('OK')) return InstallResult.failure(arch, 'could not write ${binary.destination}');

      // Ownership comes out of the ARCHIVE otherwise: mailsend-go's tarball carries 501:201, the
      // uid/gid of whoever built it, and tar preserves them. Numeric 0:0 rather than root:root,
      // because BusyBox needs the names to exist in /etc/passwd and /etc/group and there is no
      // reason to depend on that. Best-effort: the binary runs as root either way, so a router
      // that will not take the chown is odd rather than broken, and refusing the install over it
      // would be worse than the thing it is guarding against.
      try {
        await run('chown 0:0 $dest 2>/dev/null; chown 0:0 ${shellSingleQuote(kRouterAppDir)} 2>/dev/null; true');
      } catch (_) {
        // Swallowed on purpose. See above: this is tidying, not a precondition.
      }

      if (!await verifyRuns(binary.destination, binary.versionFlag)) {
        // Wrong architecture is the expected reason, and the caller will try the other one. Leave
        // nothing behind: a binary that does not run is worse than none, because the missing-binary
        // check would then pass and the failure would surface somewhere less obvious.
        await run('rm -f $dest');
        return InstallResult.failure(arch, 'the $arch binary would not run on this router');
      }

      await _log('${binary.name} ${binary.version} ($arch) installed to ${binary.destination}', isSuccess: true);
      return InstallResult.success(arch);
    } finally {
      // Always: /tmp is RAM on these routers, so a few megabytes left here persist until reboot.
      await run('rm -rf ${shellSingleQuote(tmp)}');
    }
  }

  /// Result of opening an archive: the staged binary, or why it could not be identified.
  ///
  /// A plain null told us nothing. Build 412's first hardware run failed here on both
  /// architectures with "did not contain exactly one" - which could equally have meant the archive
  /// was empty, tar had failed, or the binary is named something else, and the message did not
  /// distinguish them. Carrying the reason is the fix.
  Future<({String? path, String? problem})> _extract(String dir, String archive, String memberName) async {
    final q = shellSingleQuote(archive);
    final d = shellSingleQuote(dir);

    // Capture tar's own complaint rather than discarding it: BusyBox builds vary in whether `-z`
    // is supported, and "tar failed" and "tar worked but the file is not where expected" need
    // different fixes.
    // `cd` then extract, rather than `tar -C dir`. BusyBox tar reported success while extracting
    // nothing into the -C directory on an RT-AX88U (build 412, hardware) - it is not worth
    // establishing which BusyBox builds honour -C after -f when changing directory first removes
    // the question entirely.
    final tar = await run('cd $d && tar -xzf $q 2>&1 && echo __OK__');
    if (!tar.contains('__OK__')) {
      final detail = tar.replaceAll('__OK__', '').trim();
      return (path: null, problem: 'could not open the archive${detail.isEmpty ? '' : ' ($detail)'}');
    }

    // Everything extracted, minus the download itself. Listed first so a failure can name what was
    // actually there - the single most useful thing when the layout is not what was assumed.
    // `ls -1`, not `find`. On an RT-AX88U (build 412, hardware) `find DIR -type f` returned nothing
    // while `ls -la` on the same directory listed all five extracted files - this BusyBox is built
    // without find's `-type` support, and with stderr discarded a find that ERRORS looks exactly
    // like one that matched nothing. `ls` is always present and its output needs no options.
    //
    // This assumes a flat archive, which every asset pinned here is. A nested one would show its
    // directory in the listing below rather than failing silently.
    final entries = (await run('ls -1 $d 2>&1'))
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l != archive.split('/').last)
        .toList();
    if (entries.isEmpty) {
      return (path: null, problem: 'the archive unpacked nothing into $dir');
    }

    const docs = {'.txt', '.md', '.html', '.pdf', '.1'};
    bool isDoc(String n) => docs.any((e) => n.toLowerCase().endsWith(e));

    // Exact name first. Falling back to a prefix match covers an archive that decorates the
    // binary with its version, which is what get-bins.sh's `mailsend-go*` glob was really for -
    // but unlike that glob plus `head -1`, an ambiguous result fails instead of picking one.
    var matches = entries.where((n) => n == memberName).toList();
    if (matches.isEmpty) {
      matches = entries.where((n) => n.startsWith(memberName) && !isDoc(n)).toList();
    }

    if (matches.length == 1) return (path: '$dir/${matches.first}', problem: null);
    return (
      path: null,
      problem: matches.isEmpty
          ? 'no "$memberName" in the archive (it holds: ${entries.join(', ')})'
          : 'more than one "$memberName" in the archive (${matches.join(', ')})',
    );
  }
}
