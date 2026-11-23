#!/usr/bin/env python3
"""A/B of the link thread count for a Spring port's dev edit build (m7-flint-cli's question, approved by the coordinator
on 2026-11-23): does FLINT_LINK_THREADS=8 beat the default 4 for gs-rest-service's static edit build?

    spring_link_ab.py [--app gs-rest-service] [--arms 4 8] [--trials 15] [--shared] [--root <checkout>] --output <file>

`--root` measures the port of another checkout (the queue's worktree at the pinned commit) with this harness.

The port is built in place, as measure_builds --spring builds it (flint.lock records the platform's paths), with a
FLINT_CACHE of the run's own, primed by one unscored build per series. Each trial appends one line to the port's
edit source and builds once per arm, the arms alternating in order (A, B, B, A, ...), so drift falls on both. The edit
source is restored at the end. Every build is an edit build: the arms differ only in FLINT_LINK_THREADS.

For each series (static: `measure.cached_static`, and with --shared the shared-object dev build `measure.cached`),
the report gives per arm the medians of phases_ms.link, phases_ms.total and the wall time, and for each metric the
difference of medians (second arm minus first) with a bootstrap 99% interval (independent resampling of each arm,
10,000 replicates, fixed seed). The default changes only if the interval excludes zero.
"""
from __future__ import annotations

import argparse
import json
import os
import random
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import spring_bench  # noqa: E402
import spring_builds  # noqa: E402

METRICS = ('link', 'total', 'wall')


def difference_interval(first, second, replicates=10000):
    """Median(second) - median(first), with a bootstrap 99% interval."""
    if len(first) < 2 or len(second) < 2:
        return {'difference': statistics.median(second) - statistics.median(first), 'note': 'too few trials'}
    rng = random.Random(20261123)
    samples = sorted(statistics.median(rng.choices(second, k=len(second)))
                     - statistics.median(rng.choices(first, k=len(first))) for _ in range(replicates))
    lower, upper = samples[int(replicates * .005)], samples[int(replicates * .995)]
    return {'difference': statistics.median(second) - statistics.median(first), 'lower_99': lower, 'upper_99': upper,
            'excludes_zero': lower > 0 or upper < 0}


def build(command, directory, env, log):
    began = time.time() - 1
    start = time.perf_counter()
    with open(log, 'wb') as stream:
        completed = subprocess.run(command, cwd=directory, env=env, stdout=stream, stderr=subprocess.STDOUT)
    wall = (time.perf_counter() - start) * 1000
    if completed.returncode:
        raise SystemExit(f'build failed ({completed.returncode}): {command}; see {log}')
    phases = spring_builds.build_phases(directory, began) or {}
    return {'wall': wall, 'link': phases.get('link', -1), 'total': phases.get('total', -1), 'phases_ms': phases}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--app', default='gs-rest-service')
    parser.add_argument('--arms', nargs=2, default=['4', '8'], help='FLINT_LINK_THREADS of the two arms')
    parser.add_argument('--trials', type=int, default=15)
    parser.add_argument('--shared', action='store_true', help='also the shared-object dev edit build')
    parser.add_argument('--root', type=Path, default=ROOT, help='the checkout whose port is built (default: this one)')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--smoke', action='store_true', help='2 trials; never evidence')
    args = parser.parse_args(argv)
    trials = 2 if args.smoke else args.trials
    directory = args.root.resolve() / spring_bench.app_row(args.app)['flint']['directory']
    spec = json.loads((directory / 'flint-spring.json').read_text())['measure']
    series = {'static': spec['cached_static']} | ({'shared': spec['cached']} if args.shared else {})
    edit = directory / spec['edit_source']
    original = edit.read_bytes()
    logs = args.output.parent / 'link-ab-logs'
    logs.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='flint-link-ab-'))
    result = {'schema': 'flint.spring-link-ab/1', 'mode': 'smoke' if args.smoke else 'production', 'app': args.app,
              'root': str(args.root.resolve()), 'arms': {'first': args.arms[0], 'second': args.arms[1]}, 'trials_per_arm': trials,
              'variable': 'FLINT_LINK_THREADS', 'series': {}, 'trials': []}
    try:
        base = dict(os.environ, FLINT_CACHE=str(temporary / 'cache'))
        base.pop('FLINT_LINK_THREADS', None)
        result['dev_linker'] = spring_builds.dev_linker(base)
        shutil.rmtree(directory / '.flint', ignore_errors=True)
        edits = 0
        for name, command in series.items():
            # One unscored build primes the cache and the project for this series; its edit builds follow.
            build(command, directory, base, logs / f'{name}-prime.log')
            observed = {arm: {metric: [] for metric in METRICS} for arm in args.arms}
            for trial in range(trials):
                for arm in (args.arms if trial % 2 == 0 else list(reversed(args.arms))):
                    edits += 1
                    with edit.open('a', encoding='utf-8') as output:
                        output.write(f'\nenum flintLinkEdit{edits} = {edits};\n')
                    row = build(command, directory, dict(base, FLINT_LINK_THREADS=arm),
                                logs / f'{name}-{arm}-{trial}.log')
                    for metric in METRICS:
                        observed[arm][metric].append(row[metric])
                    result['trials'].append(dict(row, series=name, arm=arm, trial=trial))
            first, second = (observed[arm] for arm in args.arms)
            result['series'][name] = {
                'medians_ms': {arm: {m: statistics.median(observed[arm][m]) for m in METRICS} for arm in args.arms},
                'difference_ms': {m: difference_interval(first[m], second[m]) for m in METRICS
                                  if min(first[m] + second[m]) >= 0},
            }
        result['status'] = 'passed'
    finally:
        edit.write_bytes(original)
        shutil.rmtree(temporary, ignore_errors=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    for name, row in result['series'].items():
        for metric, cell in row['difference_ms'].items():
            interval = (f" [{cell['lower_99']:.1f}, {cell['upper_99']:.1f}]"
                        f"{' excludes 0' if cell['excludes_zero'] else ''}") if 'lower_99' in cell else ''
            print(f"{name:7} {metric:6} {args.arms[0]}: {row['medians_ms'][args.arms[0]][metric]:8.1f} "
                  f"{args.arms[1]}: {row['medians_ms'][args.arms[1]][metric]:8.1f}  "
                  f"diff {cell['difference']:+.1f}{interval}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
