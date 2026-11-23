#!/usr/bin/env python3
"""A/B of how a Spring port's release binary links (owner decision 6ecd8933): dynamic libc and system libraries, as
flint links release builds now, against fully static, as the Go comparator is. Non-gating: the result decides whether
the measured release profile switches to static.

    spring_static_ab.py --variants <json> [--app gs-rest-service] [--runs 6] [--root <checkout>] --output <file>

`--variants` maps each variant name to {"build": [argv run in the port], "binary": "<path in the port>",
"Oz": {"build": [...], "binary": "..."}}; the first variant is the base. For each variant:
- the binary is built, then must pass the application's black-box suite in exact mode;
- its stripped size, and the stripped size of its Oz build, are compared with the registered Go comparator's;
- the Spring-style workload (policy/spring-http-benchmark.json: the manifest's warm-up, latency and capacity phases,
  connections, rate and CPU sets, unchanged) runs `--runs` times per variant, the variants alternating in order
  (A, B, B, A, ...), as load_bench's Spring path measures Flint.
Go is not loaded in this run: the decision rule compares the variants with each other (static is chosen only if Oz
still passes against Go and no runtime metric gets worse beyond its interval), and Go's runtime numbers come from the
gs-rest-multicore runs. The report gives each metric's medians and the ratio of medians (variant / base) with a
bootstrap 99% interval (10,000 replicates, fixed seed).
"""
from __future__ import annotations

import argparse
import json
import random
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import load_bench  # noqa: E402
import spring_bench  # noqa: E402
import spring_builds  # noqa: E402

MANIFEST = ROOT / 'policy' / 'spring-http-benchmark.json'
METRICS = ('requests_per_second', 'p50_ms', 'p99_ms', 'p999_ms', 'peak_rss_bytes', 'cpu_ns_per_request')


def ratio_interval(new, old, replicates=10000):
    """median(new) / median(old) with a bootstrap 99% interval (independent resampling; any number of runs >= 2)."""
    rng = random.Random(20261123)
    samples = sorted(statistics.median(rng.choices(new, k=len(new))) / statistics.median(rng.choices(old, k=len(old)))
                     for _ in range(replicates))
    return {'ratio': statistics.median(new) / statistics.median(old), 'lower_99': samples[int(replicates * .005)],
            'upper_99': samples[int(replicates * .995)]}


def build(command, port, log):
    with open(log, 'wb') as stream:
        completed = subprocess.run(command, cwd=port, stdout=stream, stderr=subprocess.STDOUT)
    if completed.returncode:
        raise SystemExit(f'build failed ({completed.returncode}): {command}; see {log}')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--app', default='gs-rest-service')
    parser.add_argument('--variants', required=True, help='JSON: name -> {build, binary, Oz: {build, binary}}')
    parser.add_argument('--runs', type=int, default=6)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--oha', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--smoke', action='store_true', help='1 run, short phases; never evidence')
    args = parser.parse_args(argv)
    variants = json.loads(args.variants)
    names = list(variants)
    if len(names) != 2:
        raise SystemExit('--variants names exactly two variants, the base first')
    # Not ready until every variant names its builds: the musl-static Oz option does not exist yet (m7-flint-cli).
    unready = [f'{name} {profile}' for name, variant in variants.items()
               for profile, row in (('O3', variant), ('Oz', variant.get('Oz') or {})) if not (row.get('build')
                                                                                              and row.get('binary'))]
    if unready:
        raise SystemExit('not ready: no build command for ' + ', '.join(unready))
    port = args.root.resolve() / spring_bench.app_row(args.app)['flint']['directory']
    manifest = json.loads(MANIFEST.read_text())
    spec = manifest['apps'][args.app]
    workload = dict(manifest['workload'], runs=1 if args.smoke else args.runs)
    if args.smoke:
        workload.update(duration_seconds=2, capacity_seconds=2, warmup_seconds=1, connections=8)
    oha = args.oha or next((r / '.tools' / 'oha-1.16.0' / 'oha' for r in (args.root.resolve(), ROOT)
                            if (r / '.tools' / 'oha-1.16.0' / 'oha').is_file()), None)
    if oha is None or load_bench.file_hash(oha) != load_bench.OHA_SHA256:
        raise SystemExit('the pinned oha is missing')
    out = args.output.parent / (args.output.stem + '-raw')
    out.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='flint-static-ab-'))
    result = {'schema': 'flint.spring-static-ab/1', 'mode': 'smoke' if args.smoke else 'production', 'app': args.app,
              'root': str(args.root.resolve()), 'variants': variants, 'base': names[0], 'effective_workload': workload,
              'manifest_sha256': spring_bench.sha256(MANIFEST), 'status': 'running', 'binaries': {}, 'acceptance': {},
              'sizes': {}, 'series': {}, 'trials': []}
    try:
        # Each variant's binaries are built and copied aside, so building the next variant cannot replace them.
        for name, variant in variants.items():
            entry = {}
            for profile, row in (('O3', variant), ('Oz', variant['Oz'])):
                build(row['build'], port, out / f'build-{name}-{profile}.log')
                kept = temporary / f'{name}-{profile}'
                kept.write_bytes((port / row['binary']).read_bytes())
                kept.chmod(0o755)
                entry[profile] = {'path': str(kept), 'sha256': spring_bench.sha256(kept),
                                  'file': subprocess.run(['file', '-b', str(kept)], capture_output=True,
                                                         text=True).stdout.strip(),
                                  **spring_builds.stripped(kept, temporary)}
            result['binaries'][name] = entry
        go_bytes = spring_builds.stripped(spring_bench.build_go(args.app), temporary)['binary_bytes']
        for name in names:
            result['sizes'][name] = {profile: {'bytes': result['binaries'][name][profile]['binary_bytes'],
                                               'against_go': result['binaries'][name][profile]['binary_bytes'] / go_bytes}
                                     for profile in ('O3', 'Oz')}
        result['sizes']['go_bytes'] = go_bytes
        # Both binaries pass the black-box suite exactly before any load.
        for name in names:
            record = spring_bench.accept(args.app, 'flint', 'exact', binary=Path(result['binaries'][name]['O3']['path']),
                                         start_cwd=str(port))
            result['acceptance'][name] = {'passed': record['passed'], 'total': record['total']}
            if not record['success']:
                raise SystemExit(f'{name} fails the suite: {record["passed"]}/{record["total"]}')
        series = {name: {metric: [] for metric in METRICS} for name in names}
        environment = manifest.get('environment', {})
        for trial in range(workload['runs']):
            for name in (names if trial % 2 == 0 else list(reversed(names))):
                row = load_bench.spring_measure(spring_bench, args.app, spec, 'flint', workload, oha, trial, out,
                                                environment, None, args.smoke,
                                                binary=result['binaries'][name]['O3']['path'], label=name)
                for metric in METRICS:
                    series[name][metric].append(row['capacity' if metric == 'requests_per_second' else 'latency'][metric])
                result['trials'].append(dict(row, variant=name))
                print(json.dumps({'trial': trial, 'variant': name, 'status': 'measured'}), flush=True)
        base, other = names
        result['series'] = series
        result['medians'] = {name: {m: statistics.median(series[name][m]) for m in METRICS} for name in names}
        result['ratios'] = {m: ratio_interval(series[other][m], series[base][m]) for m in METRICS}
        result['status'] = 'passed'
    except BaseException as exc:
        result['status'], result['error'] = 'failed', str(exc)[:2000]
        raise
    finally:
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    for metric, cell in result['ratios'].items():
        print(f"{metric:20} {names[0]} {result['medians'][names[0]][metric]:12.4g}  {names[1]} "
              f"{result['medians'][names[1]][metric]:12.4g}  ratio {cell['ratio']:.3f} "
              f"[{cell['lower_99']:.3f}, {cell['upper_99']:.3f}]")
    for name in names:
        print(name, {p: f"{v['bytes']} ({v['against_go']:.3f} of Go)" for p, v in result['sizes'][name].items()})
    return 0


if __name__ == '__main__':
    sys.exit(main())
