#!/usr/bin/env python3
"""Diagnostic dev-profile build timings against Go, on any host (ADR-025).

tools/measure_builds.py produces the certifying evidence on the Linux performance runner. This tool times only
wall-clock builds, so a host it does not support (Windows, a development VM) can still show the effect of each
toolchain change. It uses that tool's definitions:

- cold: a fresh copy of the workspace and a fresh DUB_HOME, with the toolchain and native installs shared;
- incremental: the same workspace rebuilt after appending a declaration to the app's edit source;
- Go cold: a fresh copy of the reference app with a fresh clone of a cache primed with only the standard library;
- Go incremental: the same app rebuilt after appending a declaration to its main.go.

The dev profile's flags come from policy/profiles.toml through DFLAGS with DUB's plain build type, as in
measure_builds.py. Results are diagnostic: they are never written as release evidence.
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import shlex
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import profiles

ROOT = Path(__file__).resolve().parents[1]
POLICY = json.loads((ROOT / 'policy/build-benchmarks.json').read_text(encoding='utf-8'))
EXCLUDED = {'.git', '.dub', '.dub-home', '.ci-dub-home', '.tools', '.native', '.native-sanitized', '.flint',
            '__pycache__', 'artifacts', 'build'}


def copy_workspace(destination):
    """The repository without caches, toolchains and build outputs."""
    def ignore(directory, names):
        return [name for name in names if name in EXCLUDED or name.endswith(('.exe', '.obj', '.pdb', '.o'))]
    shutil.copytree(ROOT, destination, ignore=ignore)


def timed(command, cwd, env):
    start = time.perf_counter()
    result = subprocess.run([str(part) for part in command], cwd=cwd, env=env, capture_output=True, text=True)
    elapsed = time.perf_counter() - start
    if result.returncode:
        raise SystemExit('build failed: ' + ' '.join(map(str, command)) + '\n' + result.stdout[-4000:] + result.stderr[-4000:])
    return elapsed


def append_d(path, iteration):
    with Path(path).open('a', encoding='utf-8') as output:
        output.write('\nprivate enum uint __flint_measure_edit_' + str(iteration) + ' = ' + str(iteration) + ';\n')


def append_go(path, iteration):
    with Path(path).open('a', encoding='utf-8') as output:
        output.write('\nconst flintMeasureEdit' + str(iteration) + ' = ' + str(iteration) + '\n')


def flint_trials(app, trials, dub, dmd, extra_env, extra_dflags=()):
    fixture = POLICY['apps'][app]
    flags = profiles.dflags('dev') + profiles.link_dflags('dev') + list(extra_dflags)
    cold, incremental = [], []
    for iteration in range(trials):
        with tempfile.TemporaryDirectory(prefix='flint-dev-') as temporary:
            workspace = Path(temporary) / 'workspace'
            copy_workspace(workspace)
            env = dict(os.environ, DUB_HOME=str(workspace / '.dub-home'), DFLAGS=shlex.join(flags), **extra_env)
            command = [dub, 'build', '--compiler=' + dmd, '--build=plain', '--skip-registry=all']
            cwd = workspace / fixture['fixture']
            cold.append(timed(command, cwd, env))
            append_d(workspace / fixture['edit_source'], iteration)
            incremental.append(timed(command, cwd, env))
    return cold, incremental


def go_trials(app, trials, go):
    source = ROOT / POLICY['go_apps'][app]['directory']
    env = dict(os.environ, GOTOOLCHAIN='local', GOPROXY='off', GOSUMDB='off', GOWORK='off', CGO_ENABLED='0')
    cold, incremental = [], []
    with tempfile.TemporaryDirectory(prefix='flint-go-') as temporary:
        temporary = Path(temporary)
        prime = temporary / 'prime'
        prime.mkdir()
        build = [go, 'build', '-buildvcs=false', '-trimpath']
        subprocess.run(build + ['std'], cwd=ROOT, env=dict(env, GOCACHE=str(prime)), check=True, capture_output=True)
        for iteration in range(trials):
            work = temporary / ('app-' + str(iteration))
            shutil.copytree(source, work)
            cache = temporary / ('cache-' + str(iteration))
            shutil.copytree(prime, cache)
            trial_env = dict(env, GOCACHE=str(cache))
            command = build + ['-ldflags=-s -w', '-o', str(work / ('reference' + ('.exe' if os.name == 'nt' else ''))), '.']
            cold.append(timed(command, work, trial_env))
            append_go(work / 'main.go', iteration)
            incremental.append(timed(command, work, trial_env))
    return cold, incremental


def summary(samples):
    return {'median': statistics.median(samples), 'samples': samples}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--app', action='append', choices=sorted(POLICY['apps']), help='default: bench-cli')
    parser.add_argument('--trials', type=int, default=5)
    parser.add_argument('--dub', default='dub')
    parser.add_argument('--dmd', default='dmd')
    parser.add_argument('--go', default='go')
    parser.add_argument('--no-go', action='store_true')
    parser.add_argument('--env', action='append', default=[], metavar='NAME=VALUE',
                        help='environment for the Flint builds, such as FLINT_DUB_PIPELINE=0')
    parser.add_argument('--dflag', action='append', default=[], metavar='FLAG',
                        help='a compiler flag appended to the dev profile, such as -L/DEBUG:FASTLINK')
    parser.add_argument('--label', default='', help='a name for this toolchain configuration')
    args = parser.parse_args()
    extra = dict(item.split('=', 1) for item in args.env)
    report = {'diagnostic': True, 'host': platform.platform(), 'cpus': os.cpu_count(), 'label': args.label,
              'trials': args.trials, 'environment': extra, 'dflags': args.dflag, 'apps': {}}
    for app in args.app or ['bench-cli']:
        cold, incremental = flint_trials(app, args.trials, args.dub, args.dmd, extra, args.dflag)
        row = {'flint_cold': summary(cold), 'flint_incremental': summary(incremental)}
        if not args.no_go:
            go_cold, go_incremental = go_trials(app, args.trials, args.go)
            row['go_cold'] = summary(go_cold)
            row['go_incremental'] = summary(go_incremental)
            row['ratio_cold'] = row['flint_cold']['median'] / row['go_cold']['median']
            row['ratio_incremental'] = row['flint_incremental']['median'] / row['go_incremental']['median']
        report['apps'][app] = row
    json.dump(report, sys.stdout, indent=2)
    print()


if __name__ == '__main__':
    main()
