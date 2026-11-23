#!/usr/bin/env python3
"""count-lines.py - the lines of code and the lines of tests that README.md's "Testing" bullet gives (ID-679).

Run from anywhere inside the repository:  python scripts/count-lines.py

It counts every line of every tracked file of these kinds, blanks and comments included:
  code   the Dart in lib/, the native Kotlin, Swift and C headers under android/, ios/, macos/, windows/ and linux/,
         and every shell, PowerShell, batch and Python script that is build, release, install or tooling
  tests  the Dart in test/, and every script that checks, verifies, probes or measures behaviour

A script is a test only if it is in TEST_SCRIPTS below. A new script that is in neither list is counted as code and
reported at the end, so it gets classified here on purpose: add it to TEST_SCRIPTS if it checks, verifies, probes or
measures behaviour, and to CODE_SCRIPTS if it does not. CI workflow YAML is configuration and is not counted.
"""
import os
import subprocess
import sys

SCRIPT_EXT = ('.sh', '.ps1', '.psm1', '.bat', '.cmd', '.py')
NATIVE_EXT = ('.kt', '.kts', '.swift', '.h', '.java', '.m')
NATIVE_DIRS = ('android/', 'ios/', 'macos/', 'windows/', 'linux/')

# Scripts that check, verify, probe or measure behaviour (CLAUDE.md, ID-679).
TEST_SCRIPTS = {
    'scripts/check-claims.sh', 'scripts/e2e.sh', 'scripts/test-backoff.sh', 'scripts/test_app_store_connect.py',
    'scripts/mailsend-go_test.sh', 'scripts/verify-device-assignment.sh', 'scripts/check-reboot.sh',
    'scripts/guard-watch.sh', 'scripts/move-watch.sh', 'scripts/presence-probe.sh', 'scripts/probe-claims.sh',
    'scripts/probe-device-assignment.sh', 'scripts/pktrunner-order.sh', 'scripts/runner-host-table.sh',
    'scripts/runner-tunnel-speed.sh', 'scripts/capture-baseline.sh', 'scripts/exit-ip.ps1',
    'scripts/webui-presence.ps1', 'test/combine-files.ps1',
}

# Scripts that build, release, install or support the project: code, not tests.
CODE_SCRIPTS = {
    'ios/stamp_build_info.sh', 'promotion/blog/make_diagrams.py', 'promotion/blog/make_wordpress.py',
    'scripts/S50asuslighttpd-TEMPLATE.sh', 'scripts/S50downloadmaster-TEMPLATE.sh', 'scripts/app-store-screenshots.py',
    'scripts/app_store_connect.py', 'scripts/build-optimisation.sh', 'scripts/build.ps1', 'scripts/build.sh',
    'scripts/check-changelog-current.sh', 'scripts/clear-cfg-pia-wg.sh', 'scripts/clearall.sh',
    'scripts/count-lines.py', 'scripts/extract-with-context.ps1', 'scripts/find-recorded-build.sh', 'scripts/get-bins.sh', 'scripts/get-latest-tag.sh',
    'scripts/network-traffic-logical.py', 'scripts/network-traffic-representative.py',
    'scripts/pin-actions-latest.ps1', 'scripts/pin-actions-latest.sh', 'scripts/play-screenshots.py',
    'scripts/play_promote.py', 'scripts/read-vpnc_clientlist.sh', 'scripts/readme-crops.py', 'scripts/showall.sh',
    'scripts/svg-dark-variant.py', 'scripts/wait-for-checks.sh', 'scripts/wait-for-release.sh', 'scripts/xcode-storekit.sh',
}


def lines_in(path):
    with open(path, 'rb') as fh:
        data = fh.read()
    return data.count(b'\n') + (0 if not data or data.endswith(b'\n') else 1)


def tracked():
    root = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True, check=True).stdout.strip()
    os.chdir(root)
    out = subprocess.run(['git', 'ls-files'], capture_output=True, text=True, check=True).stdout
    return [f for f in out.split('\n') if f and not f.startswith(('build/', 'coverage/', '.dart_tool/'))]


def main():
    code, tests, unclassified = {}, {}, []
    for f in tracked():
        if not os.path.exists(f):
            continue
        if f.startswith('lib/') and f.endswith('.dart'):
            code.setdefault('Dart (lib/)', []).append(f)
        elif f.startswith('test/') and f.endswith('.dart'):
            tests.setdefault('Dart (test/)', []).append(f)
        elif f.endswith(SCRIPT_EXT):
            if f in TEST_SCRIPTS:
                tests.setdefault('scripts', []).append(f)
            else:
                code.setdefault('scripts', []).append(f)
                if f not in CODE_SCRIPTS:
                    unclassified.append(f)
        elif f.endswith(NATIVE_EXT) and f.startswith(NATIVE_DIRS):
            code.setdefault('native (Kotlin, Swift)', []).append(f)
    for name, groups in (('code', code), ('tests', tests)):
        total = 0
        for kind, files in sorted(groups.items()):
            n = sum(lines_in(f) for f in files)
            total += n
            print('%-5s %-24s %4d files %7d lines' % (name, kind, len(files), n))
        print('%-5s %-24s %12s %7d lines' % (name, 'TOTAL', '', total))
    missing = sorted(f for f in TEST_SCRIPTS | CODE_SCRIPTS if not os.path.exists(f))
    if missing:
        print('\nlisted here but not in the repository: ' + ', '.join(missing))
    if unclassified:
        print('\nnew scripts counted as code until classified in this file: ' + ', '.join(sorted(unclassified)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
