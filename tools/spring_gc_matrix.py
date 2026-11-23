"""The GC matrix: a Flint port under each druntime GC setting of benchmarks/spring/gc-matrix.json (ADR-030 section 4).

    spring_bench.py gc-matrix <app> --output <file> [--setting <name>]... [--smoke] [--binary <stand-in>]

For each setting the same Flint binary runs with `--DRT-gcopt=<setting> profile:1`:
1. the black-box suite must still pass (a GC setting may not change behaviour);
2. the Spring-style REST workload of policy/spring-http-benchmark.json measures p50/p99/p99.9, peak RSS, CPU per
   request and capacity, with the same phases, CPU sets and runner-quiet rule as load_bench.py;
3. druntime's exit profile (collections, total and maximum pause) is read from the server log.
The registered Go comparator runs in the same session, interleaved with the settings in every trial, so each
setting's ratios against Go come from the same machine state.

`--binary` measures a stand-in executable instead of the Flint port, to check the harness before a port exists;
such a record is marked "stand-in" and never counts as evidence.
"""
from __future__ import annotations

import json
import os
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import load_bench  # noqa: E402
import spring_bench  # noqa: E402

PROFILE = {
    'collections': re.compile(r'Number of collections:\s+(\d+)'),
    'total_pause_ms': re.compile(r'Grand total GC time:\s+(\d+) milliseconds'),
    'max_pause_ms': re.compile(r'Max Pause Time:\s+(\d+) milliseconds'),
    'mark_ms': re.compile(r'Total mark time:\s+(\d+) milliseconds'),
    'sweep_ms': re.compile(r'Total sweep time:\s+(\d+) milliseconds'),
}


def gc_profile(log_path):
    """druntime's `profile:1` report, printed when the process ends through druntime; None if it is absent."""
    text = Path(log_path).read_text(errors='replace')
    found = {key: pattern.search(text) for key, pattern in PROFILE.items()}
    if not found['collections']:
        return None
    return {key: int(match.group(1)) for key, match in found.items() if match}


def summary(values):
    return {'median': statistics.median(values), 'min': min(values), 'max': max(values)} if values else None


def main(args):
    matrix = json.loads((ROOT / 'benchmarks' / 'spring' / 'gc-matrix.json').read_text())
    manifest_path = ROOT / 'policy' / 'spring-http-benchmark.json'
    raw = manifest_path.read_bytes()
    manifest = json.loads(raw)
    app = args.app
    if app not in manifest['apps']:
        raise SystemExit(f'{app} has no Spring workload in {manifest_path.relative_to(ROOT)}')
    settings = args.setting or list(matrix['settings'])
    unknown = set(settings) - set(matrix['settings'])
    if unknown:
        raise SystemExit('unknown GC settings: ' + ', '.join(sorted(unknown)))
    workload = load_bench.validate_spring_manifest(manifest, args.smoke).copy()
    if args.smoke:
        workload.update(runs=1, duration_seconds=2, capacity_seconds=2, warmup_seconds=1,
                        connections=min(workload['connections'], 8))
    load = load_bench.spring_quiet(args.smoke)
    oha = Path(os.environ.get('OHA') or ROOT / '.tools' / 'oha-1.16.0' / 'oha')
    if not oha.is_file() or load_bench.file_hash(oha) != load_bench.OHA_SHA256:
        raise SystemExit('the pinned oha is missing; tools/install_toolchains.py --compiler oha (or set OHA)')
    problems = spring_bench.check_registry([app])
    if problems:
        raise SystemExit('Go comparator: ' + '; '.join(problems))
    stand_in = Path(args.binary).resolve() if args.binary else None
    if stand_in is None:
        spring_bench.build_flint(app)
    spring_bench.build_go(app)
    spec = manifest['apps'][app]
    environment = manifest.get('environment', {})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    outdir = args.output.parent / (args.output.stem + '-raw')
    outdir.mkdir(exist_ok=True)
    result = {'schema': 'flint.spring-gc-matrix-result/1', 'app': app,
              'mode': 'stand-in' if stand_in else ('smoke' if args.smoke else 'production'), 'status': 'running',
              'stand_in': str(stand_in) if stand_in else None, 'workload_sha256': load_bench.hashlib.sha256(raw).hexdigest(),
              'effective_workload': workload, 'load_average_at_start': load, 'settings': {}, 'trials': []}

    def gcopt(name):
        return [f"--DRT-gcopt={matrix['settings'][name]} {matrix['profile']}"]

    try:
        for name in settings:
            record = spring_bench.accept(app, 'flint', 'exact', extra_args=gcopt(name), binary=stand_in)
            if not record['success']:
                if not stand_in:
                    raise ValueError(f'{app} fails its black-box suite under GC setting {name}')
            result['settings'][name] = {'gcopt': matrix['settings'][name], 'suite': {
                'passed': record['passed'], 'total': record['total']}, 'series': {k: [] for k in load_bench.FIELDS},
                'gc_profiles': []}
        result['go'] = {'series': {k: [] for k in load_bench.FIELDS}}
        database_context = (spring_bench.postgres_cluster(workload['database_cpus'])
                            if spring_bench.app_row(app).get('database') == 'postgres' else load_bench.contextlib.nullcontext())
        with database_context as database:
            for trial in range(workload['runs']):
                order = ['go'] + settings if trial % 2 == 0 else list(reversed(settings)) + ['go']
                for name in order:
                    if name == 'go':
                        row = load_bench.spring_measure(spring_bench, app, spec, 'go', workload, oha, trial, outdir,
                                                        environment, database, args.smoke)
                        target = result['go']
                    else:
                        row = load_bench.spring_measure(spring_bench, app, spec, 'flint', workload, oha, trial, outdir,
                                                        environment, database, args.smoke, extra_args=gcopt(name),
                                                        binary=stand_in, label='flint-' + name)
                        target = result['settings'][name]
                        profile = gc_profile(row['server_log'])
                        target['gc_profiles'].append(profile)
                        row['gc_profile'] = profile
                    row['setting'] = name
                    result['trials'].append(row)
                    for key in load_bench.FIELDS:
                        target['series'][key].append(row['capacity' if key == 'requests_per_second' else 'latency'][key])
                    print(json.dumps({'app': app, 'trial': trial, 'setting': name, 'status': 'measured'}), flush=True)
        go = {key: statistics.median(values) for key, values in result['go']['series'].items()}
        for name, row in result['settings'].items():
            medians = {key: statistics.median(values) for key, values in row['series'].items()}
            row['against_go'] = {key: medians[key] / go[key] for key in medians}
            pauses = [p['max_pause_ms'] for p in row['gc_profiles'] if p and 'max_pause_ms' in p]
            row['max_pause_ms'] = summary(pauses)
            if len(pauses) != len(row['gc_profiles']):
                row['profile_note'] = ('druntime printed no exit profile for some runs: the process did not end '
                                       'through druntime after SIGTERM')
        result['status'] = 'stand-in' if stand_in else 'passed'
    except Exception as exc:
        result['status'] = 'failed'
        result['error'] = str(exc)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        raise
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f"{'setting':28} {'p99/Go':>8} {'RSS/Go':>8} {'CPU/Go':>8} {'rps/Go':>8} {'max pause ms':>13}")
    for name, row in result['settings'].items():
        ratio = row['against_go']
        pause = row['max_pause_ms']['median'] if row['max_pause_ms'] else '-'
        print(f"{name:28} {ratio['p99_ms']:8.3f} {ratio['peak_rss_bytes']:8.3f} {ratio['cpu_ns_per_request']:8.3f} "
              f"{ratio['requests_per_second']:8.3f} {pause:>13}")
    print('Wrote the GC matrix', args.output, f"({result['status']})")
    return 0
