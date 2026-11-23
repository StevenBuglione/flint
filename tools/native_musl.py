#!/usr/bin/env python3
"""Build the linux-x86_64-musl native packages of this checkout inside the pinned Alpine image.

    python3 tools/native_musl.py                      # the rest profile and the Boot closure's other libraries
    python3 tools/native_musl.py --profile ci         # every C provider

tools/native_build.py builds only for the libc it runs on, so musl packages build in the digest-pinned
`alpine-musl` image of policy/toolchains.json, as CI's musl lane does. The checkout is mounted at its own path, so
the install receipt and the paths it records match the host. The files are handed back to the calling user.

The result is `.native/install/linux-x86_64-musl`. Nothing for any other target changes. To link those packages:

    python3 tools/native_build.py --target linux-x86_64-musl --retarget-dub    # this checkout's DUB blocks
    python3 tools/musl_smoke.py gs-rest-service                               # package, audit, acceptance
    python3 tools/native_build.py --target linux-x86_64-glibc --retarget-dub   # back

Retarget only a disposable checkout: while it is retargeted, every non-musl flint build refuses (FLINT-E0713).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = 'linux-x86_64-musl'
# The rest profile plus what a Boot application's closure links besides (engine-reactor, serde, engine-sql).
DEFAULT_LIBRARIES = ('zlib', 'liburing', 'libyaml', 'sqlite', 'libpq')
PACKAGES = ('python3 build-base binutils clang cmake ninja meson perl pkgconf git coreutils curl autoconf automake '
            'libtool bison flex linux-headers')


def image():
    lock = json.loads((ROOT / 'policy' / 'toolchains.json').read_text(encoding='utf-8'))
    pinned = lock['containers']['alpine-musl']['image']
    if not re.fullmatch(r'docker\.io/library/alpine:[\w.]+@sha256:[0-9a-f]{64}', pinned):
        raise SystemExit('policy/toolchains.json: the alpine-musl image must name an immutable digest')
    return pinned


def git_common_dir():
    out = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', '--path-format=absolute', '--git-common-dir'],
                         capture_output=True, text=True, check=True).stdout.strip()
    return Path(out)


def command(args):
    build = ['python3', 'tools/native_build.py', '--target', TARGET, '--phase', 'build',
             '--profile', args.profile, '--jobs', str(args.jobs)]
    for library in args.library if args.library else (DEFAULT_LIBRARIES if args.profile == 'rest' else ()):
        build += ['--library', library]
    root = shlex.quote(str(ROOT))
    script = (f'set -u; apk add --no-cache {PACKAGES} >/dev/null && git config --global --add safe.directory {root} '
              f'&& {shlex.join(build)}; status=$?; chown -R {os.getuid()}:{os.getgid()} {root}/.native; exit $status')
    mounts = ['--mount', f'type=bind,source={ROOT},target={ROOT}']
    common = git_common_dir()
    if not common.is_relative_to(ROOT):
        # A worktree's .git file points into the main repository's git directory.
        mounts += ['--mount', f'type=bind,source={common},target={common},readonly']
    # Docker's default seccomp profile denies io_uring_setup, which liburing's tests use.
    return ['docker', 'run', '--rm', '--security-opt', 'seccomp=unconfined', *mounts, '--workdir', str(ROOT),
            '--env', 'HOME=/tmp', image(), 'sh', '-c', script]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--profile', default='rest', help='a tools/native_build.py profile (default: rest)')
    parser.add_argument('--library', action='append', default=[],
                        help='libraries to add; default with the rest profile: ' + ' '.join(DEFAULT_LIBRARIES))
    parser.add_argument('--jobs', type=int, default=min(os.cpu_count() or 2, 8))
    parser.add_argument('--plan', action='store_true', help='print the docker command instead of running it')
    args = parser.parse_args()
    argv = command(args)
    if args.plan:
        print(shlex.join(argv))
        return 0
    result = subprocess.run(argv)
    receipt = ROOT / '.native' / 'install' / TARGET / 'flint-native-install.json'
    if result.returncode != 0 or not receipt.is_file():
        raise SystemExit(f'the musl native build failed (exit {result.returncode}); no receipt at {receipt}')
    libraries = json.loads(receipt.read_text(encoding='utf-8'))['libraries']
    names = sorted(item['name'] if isinstance(item, dict) else item for item in libraries)
    print(json.dumps({'target': TARGET, 'receipt': str(receipt), 'libraries': names}))
    return 0


if __name__ == '__main__':
    sys.exit(main())
