#!/usr/bin/env python3
"""Package a Spring port fully static for linux-x86_64-musl and prove it: O3 and Oz, audited, then acceptance.

    python3 tools/native_musl.py                                             # once: the musl native packages
    python3 tools/native_build.py --target linux-x86_64-musl --retarget-dub   # a disposable checkout only
    python3 tools/musl_smoke.py gs-rest-service

It runs `flint package --target linux-x86_64-musl` (release, O3) and again with `--profile size` (Oz) in the port's
directory. It requires each executable to be fully static, with no interpreter and no shared library. It then
serves the O3 binary and runs the port's acceptance cases against it. Both binaries are copied beside the
summary, because the next build of the port overwrites .flint/build.

It never skips: without the musl native install, or with the checkout's native blocks not retargeted to musl, it
fails and says which command to run first.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import socket
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import spring_bench  # noqa: E402

TARGET = 'linux-x86_64-musl'


def preconditions():
    receipt = ROOT / '.native' / 'install' / TARGET / 'flint-native-install.json'
    if not receipt.is_file():
        raise SystemExit(f'musl native packages are missing ({receipt}): run python3 tools/native_musl.py first')
    marker = ROOT / '.native' / 'dub-target'
    marked = marker.read_text(encoding='utf-8').strip() if marker.is_file() else ''
    if marked != TARGET:
        raise SystemExit(f'the native DUB blocks are not retargeted to {TARGET} (marker: {marked or "absent"}): run '
                         f'python3 tools/native_build.py --target {TARGET} --retarget-dub first, in a disposable '
                         'checkout')


def flint_command():
    local = ROOT / '.flint' / 'bin' / 'flint'
    return str(local) if local.is_file() else 'flint'


def package(port, profile, output):
    done = subprocess.run([flint_command(), 'package', '--target', TARGET, '--profile', profile, '--json'],
                          cwd=port, capture_output=True, text=True)
    try:
        document = json.loads(done.stdout)
    except ValueError:
        raise SystemExit(f'flint package --profile {profile} printed no JSON (exit {done.returncode}):\n'
                         + done.stderr[-3000:])
    if done.returncode != 0 or not document.get('ok'):
        raise SystemExit(f'flint package --profile {profile} failed: {json.dumps(document["diagnostics"])[:3000]}')
    if not document['fully_static'] or document['needed']:
        raise SystemExit(f'the {profile} executable is not fully static: needs {document["needed"]}')
    executable = next(item for item in document['outputs'] if item['kind'] == 'executable')
    source = Path(executable['path'])
    source = source if source.is_absolute() else port / source
    copy = output / f'{port.name}-{profile}'
    shutil.copyfile(source, copy)
    copy.chmod(0o755)
    return {'bytes': executable['bytes'], 'sha256': hashlib.sha256(copy.read_bytes()).hexdigest(), 'path': str(copy)}


def free_port():
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('app', nargs='?', default='gs-rest-service')
    parser.add_argument('--output', type=Path, default=ROOT / '.flint' / 'musl-smoke')
    args = parser.parse_args()
    preconditions()
    port = ROOT / spring_bench.app_row(args.app)['flint']['directory']
    args.output.mkdir(parents=True, exist_ok=True)
    binaries = {profile: package(port, profile, args.output) for profile in ('release', 'size')}
    listen = free_port()
    accepted = subprocess.run([sys.executable, str(ROOT / 'tools' / 'spring_bench.py'), 'accept', args.app,
                               '--start', f'{binaries["release"]["path"]} --server.port={listen}',
                               '--url', f'http://127.0.0.1:{listen}', '--cwd', str(port)],
                              capture_output=True, text=True)
    summary = {'app': args.app, 'target': TARGET, 'binaries': binaries,
               'acceptance': (accepted.stdout.strip().splitlines() or [''])[0]}
    (args.output / f'{args.app}.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(summary))
    if accepted.returncode != 0:
        raise SystemExit(f'acceptance failed against the static O3 binary:\n{accepted.stdout[-3000:]}{accepted.stderr[-2000:]}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
