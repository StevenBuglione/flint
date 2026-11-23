#!/usr/bin/env python3
"""A/B of two builds of one Spring port on the Spring-style workload: two variants built from the same tree, each
passing the black-box suite before any load, optionally with the registered Go comparator interleaved.

    spring_binary_ab.py --variants <json> [--app gs-rest-service] [--runs 4] [--go] [--root <checkout>] --output <file>

`--variants` maps each variant name to:
- "build": argv run in the port, with "env" (optional) added to the environment;
- "binary": the executable's path in the port (copied aside after the build, so the next build cannot replace it);
- "require_text" (optional): {"path": <file in the port>, "text": <substring>} checked after the build, to prove the
  variant really is what it claims (a generated function, say);
- "Oz" (optional): {"build", "binary", "env"} for a size build, whose stripped size is reported (against Go's with
  --go).
The first variant is the base. Uses so far: release-static-ab (owner decision 6ecd8933: dynamic glibc against fully
static musl) and fast-path-ab (fast-path.md section 9: FLINT_AOT_FAST_PATH off against on).

Every variant passes `spring_bench.py accept` in exact mode before load. Then the Spring workload
(policy/spring-http-benchmark.json: warm-up, latency and capacity phases, connections, rate and CPU sets unchanged)
runs `--runs` times per arm, the arms alternating in order (Go, A, B, then B, A, Go), as load_bench's Spring path
measures. The report gives each arm's medians and, for each metric, the ratio of medians (variant / base, and with
--go each variant / Go) with a bootstrap 99% interval (10,000 replicates, fixed seed; independent resampling, valid
for any run count >= 2, wide for small ones).

The servers run from the harness checkout's copy of the port (spring_bench.launch), so the port's non-source files
(configuration, resources) must match between `--root` and the harness; the tool refuses otherwise.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
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
    """median(new) / median(old) with a bootstrap 99% interval."""
    rng = random.Random(20261123)
    samples = sorted(statistics.median(rng.choices(new, k=len(new))) / statistics.median(rng.choices(old, k=len(old)))
                     for _ in range(replicates))
    return {'ratio': statistics.median(new) / statistics.median(old), 'lower_99': samples[int(replicates * .005)],
            'upper_99': samples[int(replicates * .995)]}


def build(row, port, log):
    with open(log, 'wb') as stream:
        completed = subprocess.run(row['build'], cwd=port, env=dict(os.environ, **row.get('env', {})), stdout=stream,
                                   stderr=subprocess.STDOUT)
    if completed.returncode:
        raise SystemExit(f"build failed ({completed.returncode}): {row['build']}; see {log}")


def port_files(port):
    """sha256 of every file of the port outside its sources and build state."""
    out = {}
    for path in sorted(port.rglob('*')):
        relative = path.relative_to(port)
        if path.is_file() and relative.parts[0] not in ('src', '.flint', 'source'):
            out[str(relative)] = hashlib.sha256(path.read_bytes()).hexdigest()
    return out


def unready(variants):
    missing = []
    for name, variant in variants.items():
        rows = [('O3', variant)] + ([('Oz', variant['Oz'])] if 'Oz' in variant else [])
        missing += [f'{name} {profile}' for profile, row in rows if not (row and row.get('build') and row.get('binary'))]
    return missing


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--app', default='gs-rest-service')
    parser.add_argument('--variants', required=True, help='JSON: name -> {build, binary, env?, require_text?, Oz?}')
    parser.add_argument('--runs', type=int, default=4)
    parser.add_argument('--go', action='store_true', help='interleave the registered Go comparator')
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--oha', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--smoke', action='store_true', help='1 run, short phases; never evidence')
    args = parser.parse_args(argv)
    variants = json.loads(args.variants)
    names = list(variants)
    if len(names) != 2:
        raise SystemExit('--variants names exactly two variants, the base first')
    missing = unready(variants)
    if missing:
        raise SystemExit('not ready: no build command for ' + ', '.join(missing))
    relative = spring_bench.app_row(args.app)['flint']['directory']
    port, served = args.root.resolve() / relative, ROOT / relative
    if port != served.resolve():
        differ = sorted(k for k, v in port_files(port).items() if port_files(served).get(k) != v)
        if differ:
            raise SystemExit(f'the port differs from the harness copy the servers run from: {", ".join(differ[:8])}')
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
    temporary = Path(tempfile.mkdtemp(prefix='flint-binary-ab-'))
    result = {'schema': 'flint.spring-binary-ab/1', 'mode': 'smoke' if args.smoke else 'production', 'app': args.app,
              'root': str(args.root.resolve()), 'variants': variants, 'base': names[0], 'go': args.go,
              'effective_workload': workload, 'manifest_sha256': spring_bench.sha256(MANIFEST), 'status': 'running',
              'binaries': {}, 'acceptance': {}, 'sizes': {}, 'series': {}, 'trials': []}
    try:
        for name, variant in variants.items():
            entry = {}
            for profile, row in [('O3', variant)] + ([('Oz', variant['Oz'])] if 'Oz' in variant else []):
                build(row, port, out / f'build-{name}-{profile}.log')
                if profile == 'O3' and variant.get('require_text'):
                    check = variant['require_text']
                    if check['text'] not in (port / check['path']).read_text(errors='replace'):
                        raise SystemExit(f"{name}: {check['path']} lacks {check['text']!r}; the variant is not built as claimed")
                kept = temporary / f'{name}-{profile}'
                kept.write_bytes((port / row['binary']).read_bytes())
                kept.chmod(0o755)
                entry[profile] = {'path': str(kept), 'sha256': spring_bench.sha256(kept),
                                  'file': subprocess.run(['file', '-b', str(kept)], capture_output=True,
                                                         text=True).stdout.strip(),
                                  **spring_builds.stripped(kept, temporary)}
            result['binaries'][name] = entry
        go_bytes = None
        if args.go:
            go_bytes = spring_builds.stripped(spring_bench.build_go(args.app), temporary)['binary_bytes']
            result['sizes']['go_bytes'] = go_bytes
        for name in names:
            result['sizes'][name] = {profile: {'bytes': row['binary_bytes'],
                                               **({'against_go': row['binary_bytes'] / go_bytes} if go_bytes else {})}
                                     for profile, row in result['binaries'][name].items()}
        for name in names:
            record = spring_bench.accept(args.app, 'flint', 'exact', binary=Path(result['binaries'][name]['O3']['path']),
                                         start_cwd=str(served))
            result['acceptance'][name] = {'passed': record['passed'], 'total': record['total']}
            if not record['success']:
                raise SystemExit(f'{name} fails the suite: {record["passed"]}/{record["total"]}')
        arms = (['go'] if args.go else []) + names
        series = {arm: {metric: [] for metric in METRICS} for arm in arms}
        environment = manifest.get('environment', {})
        for trial in range(workload['runs']):
            for arm in (arms if trial % 2 == 0 else list(reversed(arms))):
                if arm == 'go':
                    row = load_bench.spring_measure(spring_bench, args.app, spec, 'go', workload, oha, trial, out,
                                                    environment, None, args.smoke)
                else:
                    row = load_bench.spring_measure(spring_bench, args.app, spec, 'flint', workload, oha, trial, out,
                                                    environment, None, args.smoke,
                                                    binary=result['binaries'][arm]['O3']['path'], label=arm)
                for metric in METRICS:
                    series[arm][metric].append(row['capacity' if metric == 'requests_per_second' else 'latency'][metric])
                result['trials'].append(dict(row, arm=arm))
                print(json.dumps({'trial': trial, 'arm': arm, 'status': 'measured'}), flush=True)
        base, other = names
        result['series'] = series
        result['medians'] = {arm: {m: statistics.median(series[arm][m]) for m in METRICS} for arm in arms}
        result['ratios'] = {f'{other}/{base}': {m: ratio_interval(series[other][m], series[base][m]) for m in METRICS}}
        if args.go:
            for name in names:
                result['ratios'][f'{name}/go'] = {m: ratio_interval(series[name][m], series['go'][m]) for m in METRICS}
        result['status'] = 'passed'
    except BaseException as exc:
        result['status'], result['error'] = 'failed', str(exc)[:2000]
        raise
    finally:
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    for label, cells in result['ratios'].items():
        print(label)
        for metric, cell in cells.items():
            print(f"  {metric:20} {cell['ratio']:.3f} [{cell['lower_99']:.3f}, {cell['upper_99']:.3f}]")
    print('sizes', json.dumps(result['sizes']))
    return 0


if __name__ == '__main__':
    sys.exit(main())
