#!/usr/bin/env python3
"""heapSizeFactor sweep against Go on one workload (diagnostic, never evidence; coordinator 08:31Z on 2026-11-25).

    gc_sweep.py --workload <key> --factor 2 --factor 3 --factor 4 --factor 8 [--trials 2] --output <file>
    (run inside a checkout; key: petclinic-rest, gs-rest-service, gs-rest-service:not-found)

Arms: Go (the registered comparator) and Flint with `--DRT-gcopt=minPoolSize:1 incPoolSize:0 heapSizeFactor:N
profile:1` per factor, interleaved for --trials trials through load_bench's own trial (warm-up, fixed rate, capacity;
phase lengths shortened by flags). Per arm: latency at the fixed rate and at capacity, app CPU, peak RSS, the median
smaps RSS over the fixed-rate phase (sampled every 15 s and after each phase), and collections per 1,000 requests
from druntime's exit profile (whole process). RSS is also given as a ratio to Go's from the same run.
"""
import argparse
import contextlib
import json
import statistics
import sys
from pathlib import Path

ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / 'tools'))
import load_bench  # noqa: E402
import smaps_census  # noqa: E402
import spring_bench as spring  # noqa: E402
import spring_gc_matrix  # noqa: E402

MANIFESTS = {'petclinic-rest': 'policy/spring-http-benchmark.json', 'gs-rest-service': 'policy/spring-http-benchmark.json',
             'gs-rest-service:not-found': 'policy/spring-error-paths-benchmark.json'}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--workload', required=True, choices=list(MANIFESTS))
    p.add_argument('--factor', action='append', required=True)
    p.add_argument('--trials', type=int, default=2)
    p.add_argument('--warmup', type=int, default=10)
    p.add_argument('--latency', type=int, default=30)
    p.add_argument('--capacity', type=int, default=20)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    manifest = json.loads((ROOT / MANIFESTS[a.workload]).read_text())
    spec = manifest['apps'][a.workload]
    app = spec.get('app', a.workload)
    workload = dict(manifest['workload'], warmup_seconds=a.warmup, duration_seconds=a.latency,
                    capacity_seconds=a.capacity)
    environment = manifest.get('environment', {})
    oha = ROOT / '.tools' / 'oha-1.16.0' / 'oha'
    spring.build_go(app)
    flint = spring.flint_binary(app)
    outdir = a.output.parent / (a.output.stem + '-raw')
    outdir.mkdir(parents=True, exist_ok=True)
    arms = ['go'] + [f'hsf{f}' for f in a.factor]
    options = {f'hsf{f}': f'minPoolSize:1 incPoolSize:0 heapSizeFactor:{f} profile:1' for f in a.factor}
    rows = {arm: [] for arm in arms}
    observer = lambda event, pid: smaps_census.snapshot(pid)  # noqa: E731
    with (spring.postgres_cluster(workload['database_cpus']) if spring.app_row(app).get('database') == 'postgres'
          else contextlib.nullcontext()) as database:
        for trial in range(a.trials):
            order = arms if trial % 2 == 0 else list(reversed(arms))
            for arm in order:
                if arm == 'go':
                    row = load_bench.spring_measure(spring, app, spec, 'go', workload, oha, trial, outdir, environment,
                                                    database, False, label='go', observer=observer)
                else:
                    row = load_bench.spring_measure(spring, app, spec, 'flint', workload, oha, trial, outdir,
                                                    environment, database, False,
                                                    extra_args=(f'--DRT-gcopt={options[arm]}',), binary=flint,
                                                    label=arm, observer=observer)
                    row['gc_profile'] = spring_gc_matrix.gc_profile(row['server_log'])
                rows[arm].append(row)
                print(json.dumps({'workload': a.workload, 'trial': trial, 'arm': arm,
                                  'p99_ms': round(row['latency']['p99_ms'], 3)}), flush=True)

    def median(values):
        values = [v for v in values if v is not None]
        return statistics.median(values) if values else None

    summary = {}
    for arm, trials in rows.items():
        rss_samples = []
        for row in trials:
            rss_samples += [o['data']['totals_kb']['Rss'] * 1024 for o in row.get('observations', [])
                            if o['event'].startswith('latency+') or o['event'] == 'after-latency']
        served = [sum(row[ph]['count'] + row[ph]['process']['correctness_probes'] for ph in ('warmup', 'latency', 'capacity'))
                  for row in trials]
        collections = [(row.get('gc_profile') or {}).get('collections') for row in trials]
        per_1000 = [c * 1000 / s for c, s in zip(collections, served) if c is not None]
        summary[arm] = {
            'gcopt': options.get(arm), 'trials': len(trials),
            'fixed': {k: median([row['latency'][k] for row in trials]) for k in ('p50_ms', 'p99_ms', 'p999_ms')},
            'capacity': {k: median([row['capacity'][k] for row in trials])
                         for k in ('p50_ms', 'p99_ms', 'p999_ms', 'requests_per_second')},
            'cpu_us_per_request_fixed': median([row['latency']['cpu_ns_per_request'] for row in trials]) / 1000,
            'peak_rss_bytes': median([max(row[ph]['peak_rss_bytes'] for ph in ('latency', 'capacity')) for row in trials]),
            'median_rss_bytes_fixed': median(rss_samples),
            'collections_per_1000_requests': median(per_1000),
            'gc_profiles': [row.get('gc_profile') for row in trials]}
    go = summary['go']
    for arm, row in summary.items():
        row['peak_rss_vs_go'] = row['peak_rss_bytes'] / go['peak_rss_bytes']
        if row['median_rss_bytes_fixed'] and go['median_rss_bytes_fixed']:
            row['median_rss_vs_go'] = row['median_rss_bytes_fixed'] / go['median_rss_bytes_fixed']
    result = {'schema': 'flint.gc-sweep/1', 'note': 'diagnostic, never evidence', 'workload': a.workload,
              'effective_workload': workload, 'arms': summary, 'trials': {k: v for k, v in rows.items()}}
    a.output.write_text(json.dumps(result, indent=2, default=str) + '\n')


if __name__ == '__main__':
    main()
