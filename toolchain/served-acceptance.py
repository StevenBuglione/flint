#!/usr/bin/env python3
"""Acceptance of served builds against stock builds (toolchain/README.md, "Served compiles and stock compiles").

A served compile's objects can differ from a stock DMD compile's: the compile server's preloaded analysis can add
ModuleInfo imports (and so linked modules and static constructors) and weak instances. Builds are consistent
either way (all served or all stock), but behaviour must not differ. For each Phase 1 application this builds
  - a served dev build: the platform prelude, the compile server (a private one, traced), and a fresh cache; the
    trace must show every compile served (no `client-local` event);
  - a stock dev build: FLINT_DMD_SERVER=0, no platform cache, a fresh cache;
and runs the application's acceptance suite (tools/spring_bench.py accept) against each.

  python3 toolchain/served-acceptance.py [app ...] [--json report.json]

Exit status 1 when a build fails, a served build compiled anything in-process, or a suite fails on either build.
Run it on venus under `python3 tools/measure_queue.py hold --`.
"""
import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APPS = {  # name: expected cases (the golden files' counts)
    'gs-rest-service': 18,
    'petclinic-rest': 109,
    'gs-relational-data-access': 1,
}


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def artifact(stdout):
    for line in reversed(stdout.splitlines()):
        if line.startswith('{'):
            try:
                return json.loads(line)['artifact']['path']
            except (ValueError, KeyError, TypeError):
                continue
    return None


def build(app, served, work):
    directory = ROOT / 'benchmarks' / 'spring' / 'flint' / app
    env = dict(os.environ, FLINT_CACHE=str(work / 'cache'))
    env.pop('FLINT_DMD_SERVER_TRACE', None)
    command = [str(ROOT / '.flint' / 'bin' / 'flint'), 'build', '-C', str(directory), '--force', '--json']
    trace = None
    runtime = None
    if served:
        runtime = Path(tempfile.mkdtemp(prefix='fsa-', dir='/tmp'))  # short: the socket path limit
        trace = work / 'trace.txt'
        env.update(XDG_RUNTIME_DIR=str(runtime), FLINT_DMD_SERVER_TRACE=str(trace))
        env.pop('FLINT_DMD_SERVER', None)
    else:
        env['FLINT_DMD_SERVER'] = '0'
        command.append('--no-platform-cache')
    try:
        done = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
    finally:
        if runtime:
            stop_servers(runtime)
            shutil.rmtree(runtime, ignore_errors=True)
    result = {'mode': 'served' if served else 'stock', 'build_status': done.returncode}
    if done.returncode != 0:
        (work / 'build.log').write_text(done.stdout + done.stderr)
        errors = [l for l in (done.stdout + done.stderr).splitlines() if 'rror' in l or 'undefined' in l][:6]
        result['problem'] = 'build failed: ' + ' | '.join(e[:300] for e in errors)
        return result, None
    if served:
        events = [' '.join(line.split()[2:]) for line in trace.read_text().splitlines()] if trace.exists() else []
        served_count = events.count('client-served')
        # A C source or a switch the server never takes compiles stock in every build alike: not a mix.
        local = sorted({e for e in events if e.startswith('client-local')} - {'client-local c-source', 'client-local forced'})
        result.update(served_compiles=served_count, local_compiles=local)
        if local or not served_count:
            result['problem'] = f'not every compile was served: {served_count} served, local {local}'
    binary = artifact(done.stdout)
    if binary and not Path(binary).is_absolute():
        binary = str(ROOT / binary)  # flint reports it relative to where it ran; command apps run from their own
    return result, binary


def stop_servers(runtime):
    listing = subprocess.run(['ps', '-axo', 'pid=,command='], capture_output=True, text=True).stdout
    for line in listing.splitlines():
        pid, _, command = line.strip().partition(' ')
        if str(runtime) in command and pid.isdigit():
            try:
                os.kill(int(pid), 9)
            except OSError:
                pass


def accept(app, binary, work):
    port = free_port()
    report = work / 'accept.json'
    directory = ROOT / 'benchmarks' / 'spring' / 'flint' / app
    done = subprocess.run([sys.executable, str(ROOT / 'tools' / 'spring_bench.py'), 'accept', app,
                           '--start', f'{binary} --server.port={port}', '--url', f'http://127.0.0.1:{port}',
                           '--cwd', str(directory), '--json', str(report)], capture_output=True, text=True)
    if not report.exists():
        return {'accept_status': done.returncode, 'problem': 'no acceptance report: ' + (done.stdout + done.stderr)[-1200:]}
    rows = json.loads(report.read_text())
    row = rows[0] if isinstance(rows, list) else rows
    out = {'passed': row.get('passed'), 'total': row.get('total'), 'success': row.get('success')}
    if not row.get('success') or row.get('total') != APPS[app]:
        failing = [case['name'] for case in row.get('cases', []) if case.get('problems')][:5]
        out['problem'] = f"acceptance {row.get('passed')}/{row.get('total')} (expected {APPS[app]}/{APPS[app]}); failing {failing}"
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('apps', nargs='*', default=list(APPS))
    ap.add_argument('--json', type=Path)
    a = ap.parse_args()
    rows, failed = [], False
    for app in a.apps:
        for served in (True, False):
            with tempfile.TemporaryDirectory(prefix='served-acceptance-') as temporary:
                work = Path(temporary)
                row, binary = build(app, served, work)
                row['app'] = app
                if binary:
                    row.update(accept(app, binary, work))
                failed |= 'problem' in row
                rows.append(row)
                print(f"{app:28} {row['mode']:6} " + (row.get('problem') or
                      f"{row['passed']}/{row['total']} passed" + (f", {row['served_compiles']} compiles served"
                                                                 if served else '')), flush=True)
    if a.json:
        a.json.write_text(json.dumps({'schema': 'flint.served-acceptance/1', 'rows': rows}, indent=1) + '\n')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
