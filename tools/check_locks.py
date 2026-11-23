#!/usr/bin/env python3
"""Every flint.lock in this checkout matches what `flint lock` writes now.

    python3 tools/check_locks.py          # exit 1, naming each stale lock and its fix

A change to a core package's, Boot library's or framework module's dependencies changes the resolved graph of every
project that uses it: the apps, the starter examples, the benchmark references and the Spring side-by-side ports.
`flint build` then fails with FLINT-E0202 for whoever builds next. This runs `flint lock --check` over each
committed project, so the session that changes the dependencies relocks them (`flint lock -C <project>`) in the
same commit. Projects under tests/ are fixtures the suites compile themselves, and a Spring port whose
flint-spring.json says "skeleton" is not written yet; both are skipped.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def projects(root=ROOT):
    listed = subprocess.run(['git', 'ls-files', '*flint.lock'], cwd=root, capture_output=True, text=True,
                            check=True).stdout.split()
    for lock in sorted(listed):
        project = (root / lock).parent
        if lock.startswith('tests/') or not (project / 'flint.toml').is_file():
            continue
        spec = project / 'flint-spring.json'
        if spec.is_file() and json.loads(spec.read_text()).get('status') == 'skeleton':
            continue
        yield project


def main():
    flint = ROOT / '.flint' / 'bin' / ('flint.exe' if sys.platform == 'win32' else 'flint')
    if not flint.is_file():
        raise SystemExit('the flint CLI is not installed: python3 tools/install_toolchains.py --compiler flint')
    stale = []
    checked = 0
    for project in projects():
        checked += 1
        result = subprocess.run([str(flint), 'lock', '--check', '--json'], cwd=project, capture_output=True, text=True)
        if result.returncode != 0:
            relative = project.relative_to(ROOT).as_posix()
            try:
                messages = [d['message'] for d in json.loads(result.stdout)['diagnostics']]
            except (ValueError, KeyError):
                messages = [(result.stdout + result.stderr).strip().splitlines()[-1:] or ['flint lock --check failed']][0]
            stale.append(relative)
            print(f'STALE {relative}: {"; ".join(messages)}\n  fix: flint lock -C {relative}', file=sys.stderr)
    print(json.dumps({'projects': checked, 'stale': stale}))
    return 1 if stale else 0


if __name__ == '__main__':
    sys.exit(main())
