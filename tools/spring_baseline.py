#!/usr/bin/env python3
"""Comparator baselines captured once, and the drift guard of Flint-only runs (owner decision c015f307).

    spring_baseline.py capture --app <app> --impl go|java [--workloads http,error] [--smoke] [--output-root <dir>]
    spring_baseline.py check <record>              is the record current on this runner? (exit 1 if not)

A capture measures one comparator of one application alone, after its suite passes (and, for a database app, its
ADR-032 SQL census is current and clean): the manifests' production trials of every workload the application has
(policy/spring-http-benchmark.json; with `error`, policy/spring-error-paths-benchmark.json), on the same CPU sets,
database, oha and phases as every other measurement. It writes a pinned record under
benchmarks/spring/baselines/<impl>/<app>/<stamp>/record.json with the raw trials beside it.

The record carries a fingerprint of everything whose change invalidates it (the comparator's digest and toolchain,
the manifests, the PostgreSQL peer, oha, the census record, the CPU model and microcode, the kernel, the frequency
governor and the CPU sets), and the drift references taken in the same session:
- calibration: short trials of the registered Go comparator at the scored fixed rate (5 s warm-up, 10 s fixed-rate,
  10 s capacity), five of them;
- probe: a fixed CPU and memory micro-probe on the server CPUs (SHA-256 of 64 MiB, a 256 MiB copy), nine samples.
Each reference metric gets a 99% prediction band for one new observation: mean +- t(0.995, n-1) * sd * sqrt(1 + 1/n).

A Flint-only run (load_bench.py / gc-matrix --baseline <record>) refuses a record whose fingerprint differs from
the runner now, takes one calibration trial and a five-sample probe before its Flint trials and again after, and is
not evidence when any reference metric falls outside its band: the record must be captured again. Never evidence
on its own: a capture is the comparator side of later Flint-only parts; the exit claim keeps its one interleaved
confirmation run (owner decision c25ae2b3).
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import math
import os
import platform
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import load_bench  # noqa: E402
import spring_bench  # noqa: E402

HTTP_MANIFEST = ROOT / 'policy' / 'spring-http-benchmark.json'
ERROR_MANIFEST = ROOT / 'policy' / 'spring-error-paths-benchmark.json'
BASELINES = ROOT / 'benchmarks' / 'spring' / 'baselines'
TARGETS = {'go': 'go', 'java': 'java-jvm'}
CALIBRATION = {'warmup_seconds': 5, 'duration_seconds': 10, 'capacity_seconds': 10}
CALIBRATION_METRICS = ('requests_per_second', 'p50_ms', 'p99_ms', 'cpu_ns_per_request')
# t(0.995, df) for the 99% prediction band, df = n - 1.
T995 = {1: 63.657, 2: 9.925, 3: 5.841, 4: 4.604, 5: 4.032, 6: 3.707, 7: 3.499, 8: 3.355, 9: 3.250, 10: 3.169}


# ---------------------------------------------------------------------------------------------------------------
# Fingerprint


def _read(path, default=''):
    try:
        return Path(path).read_text()
    except OSError:
        return default


def cpu_identity():
    info = _read('/proc/cpuinfo')
    first = info.split('\n\n', 1)[0]
    fields = dict(line.split(':', 1) for line in first.splitlines() if ':' in line)
    return {'model': fields.get('model name\t', fields.get('model name', '')).strip(),
            'microcode': fields.get('microcode\t', fields.get('microcode', '')).strip(),
            'logical_cpus': os.cpu_count()}


def governors():
    found = sorted({_read(path).strip() for path in Path('/sys/devices/system/cpu').glob('cpu[0-9]*/cpufreq/scaling_governor')})
    return found or ['unavailable']


def postgres_version():
    """The pinned PostgreSQL: libpq's version in native-lock.json (install_peers.py builds the server from it) and the
    server binary's digest."""
    libraries = json.loads((ROOT / 'policy' / 'native-lock.json').read_text())['libraries']
    rows = libraries if isinstance(libraries, list) else list(libraries.values())
    version = next(row for row in rows if row.get('name') == 'libpq')['version']
    try:
        binary = spring_bench.postgres_bin() / 'postgres'
        return {'version': version, 'postgres_sha256': spring_bench.sha256(binary)}
    except SystemExit:
        return {'version': version, 'postgres_sha256': None}


def fingerprint(app, impl, workloads):
    peers = json.loads((ROOT / 'policy' / 'peer-lock.json').read_text())['peers']
    toolchains = json.loads((ROOT / 'policy' / 'toolchains.json').read_text())['versions']
    manifest = json.loads(HTTP_MANIFEST.read_text())
    out = {'app': app, 'impl': impl, 'workloads': sorted(workloads),
           'http_manifest_sha256': spring_bench.sha256(HTTP_MANIFEST),
           'error_manifest_sha256': spring_bench.sha256(ERROR_MANIFEST) if 'error' in workloads else None,
           'oha_sha256': load_bench.OHA_SHA256,
           'postgres': postgres_version() if spring_bench.app_row(app).get('database') == 'postgres' else None,
           'database_protocol': load_bench.DATABASE_PROTOCOL if spring_bench.app_row(app).get('database') == 'postgres' else None,
           'cpu': cpu_identity(), 'kernel': platform.release(), 'governors': governors(),
           'cpu_sets': {k: manifest['workload'][k] for k in ('server_cpus', 'load_cpus', 'database_cpus')}}
    if impl == 'go':
        out['comparator_sha256'] = spring_bench.comparator_digest(app)
        out['go'] = toolchains.get('go')
    else:
        out['jdk'] = peers.get('jdk', {}).get('version')
        out['reference_commit'] = spring_bench.app_row(app)['upstream']['commit']
    census = spring_bench.CENSUS / f'{app}.json'
    out['census_sha256'] = spring_bench.sha256(census) if census.is_file() else None
    return out


def stale(record):
    """The fingerprint fields that differ between the record and this runner now; empty when it is current."""
    want = record['fingerprint']
    now = fingerprint(want['app'], want['impl'], want['workloads'])
    return sorted(key for key in set(want) | set(now) if want.get(key) != now.get(key))


# ---------------------------------------------------------------------------------------------------------------
# Drift references


def band(samples):
    """The 99% prediction band for one new observation drawn like `samples`."""
    n = len(samples)
    if n < 2:
        raise ValueError('a band needs at least two samples')
    mean, sd = statistics.mean(samples), statistics.stdev(samples)
    half = T995.get(n - 1, 2.576) * sd * math.sqrt(1 + 1 / n)
    return {'mean': mean, 'sd': sd, 'n': n, 'lower': mean - half, 'upper': mean + half}


def probe(cpus, samples=9):
    """Seconds for a fixed CPU task (SHA-256 of 64 MiB) and a fixed memory task (copying 256 MiB), on `cpus`."""
    data = os.urandom(1 << 20) * 64
    big = bytearray(256 << 20)
    previous = os.sched_getaffinity(0)
    os.sched_setaffinity(0, set(cpus))
    out = {'cpu_seconds': [], 'memory_seconds': []}
    try:
        for _ in range(samples):
            began = time.perf_counter()
            hashlib.sha256(data).digest()
            out['cpu_seconds'].append(time.perf_counter() - began)
            began = time.perf_counter()
            bytes(big)
            out['memory_seconds'].append(time.perf_counter() - began)
    finally:
        os.sched_setaffinity(0, previous)
    return out


def calibration_trial(app, workload, oha, outdir, database, trial, tag, smoke=False, vacuum=True):
    """One short trial of the registered Go comparator at the app's scored fixed rate."""
    manifest = json.loads(HTTP_MANIFEST.read_text())
    spec = manifest['apps'][app]
    short = dict(workload, **CALIBRATION)
    if smoke:
        short.update(warmup_seconds=1, duration_seconds=2, capacity_seconds=2)
    row = load_bench.spring_measure(spring_bench, app, spec, 'go', short, oha, trial, outdir,
                                    manifest.get('environment', {}), database, smoke, label=f'go-calibration-{tag}',
                                    vacuum=vacuum)
    return {metric: row['capacity' if metric == 'requests_per_second' else 'latency'][metric]
            for metric in CALIBRATION_METRICS}


def drift(record, observed_calibration, observed_probe):
    """Which reference metrics fall outside the record's bands: [] means in band."""
    out = []
    for metric, value in observed_calibration.items():
        b = record['calibration']['bands'][metric]
        if not b['lower'] <= value <= b['upper']:
            out.append(f'calibration {metric} {value:.6g} outside [{b["lower"]:.6g}, {b["upper"]:.6g}]')
    for metric, values in observed_probe.items():
        value = statistics.median(values)
        b = record['probe']['bands'][metric]
        if not b['lower'] <= value <= b['upper']:
            out.append(f'probe {metric} {value:.6g} outside [{b["lower"]:.6g}, {b["upper"]:.6g}]')
    return out


def load(path):
    path = Path(path)
    record = json.loads((path / 'record.json' if path.is_dir() else path).read_text())
    record['_path'] = str(path / 'record.json' if path.is_dir() else path)
    record['_sha256'] = spring_bench.sha256(Path(record['_path']))
    return record


def guard(record, app, workload, oha, outdir, database, when, smoke=False):
    """A drift check: one calibration trial and a five-sample probe, judged against the record's bands."""
    calibration = calibration_trial(app, workload, oha, outdir, database, 0, when, smoke)
    measured_probe = probe(workload['server_cpus'], samples=5)
    return {'when': when, 'calibration': calibration, 'probe': measured_probe,
            'out_of_band': drift(record, calibration, measured_probe)}


# ---------------------------------------------------------------------------------------------------------------
# Capture


def workload_keys(app, workloads):
    keys = []
    for name, path in (('http', HTTP_MANIFEST), ('error', ERROR_MANIFEST)):
        if name not in workloads:
            continue
        manifest = json.loads(path.read_text())
        keys += [(name, key) for key, spec in manifest['apps'].items() if spec.get('app', key) == app]
    return keys


def capture(app, impl, workloads, output_root, smoke=False):
    target = TARGETS[impl]
    problems = spring_bench.check_registry([app]) if impl == 'go' else []
    if problems:
        raise SystemExit('; '.join(problems))
    oha = Path(os.environ.get('OHA') or ROOT / '.tools' / 'oha-1.16.0' / 'oha')
    if not oha.is_file() or load_bench.file_hash(oha) != load_bench.OHA_SHA256:
        raise SystemExit('the pinned oha is missing (OHA)')
    spring_bench.build(app, 'java' if impl == 'java' else impl)
    if impl != 'go':
        spring_bench.build_go(app)  # the calibration reference is always the registered Go comparator
    record_acceptance = spring_bench.accept(app, 'java' if impl == 'java' else impl, spring_bench.WIRE_DEFAULT[impl])
    if not record_acceptance['success']:
        raise SystemExit(f'{app} [{impl}] fails its suite: {record_acceptance["passed"]}/{record_acceptance["total"]}')
    stamp = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())
    directory = Path(output_root) / impl / app / stamp
    raw = directory / 'raw'
    raw.mkdir(parents=True)
    record = {'schema': 'flint.spring-baseline/1', 'mode': 'smoke' if smoke else 'production', 'app': app,
              'impl': impl, 'captured': stamp, 'fingerprint': fingerprint(app, impl, workloads),
              'acceptance': {'passed': record_acceptance['passed'], 'total': record_acceptance['total']},
              'series': {}, 'effective_workloads': {}, 'trials': []}
    database_context = (spring_bench.postgres_cluster(json.loads(HTTP_MANIFEST.read_text())['workload']['database_cpus'])
                        if spring_bench.app_row(app).get('database') == 'postgres' else contextlib.nullcontext())
    with database_context as database:
        for name, key in workload_keys(app, workloads):
            path = HTTP_MANIFEST if name == 'http' else ERROR_MANIFEST
            manifest = json.loads(path.read_text())
            workload = load_bench.validate_spring_manifest(manifest, smoke).copy()
            if smoke:
                workload.update(runs=1, duration_seconds=2, capacity_seconds=2, warmup_seconds=1,
                                connections=min(workload['connections'], 8))
            record['effective_workloads'][key] = workload
            series = {field: [] for field in load_bench.FIELDS}
            for trial in range(workload['runs']):
                row = load_bench.spring_measure(spring_bench, app, manifest['apps'][key], target, workload, oha, trial,
                                                raw, manifest.get('environment', {}), database, smoke, label=f'{impl}-{name}')
                for field in load_bench.FIELDS:
                    series[field].append(row['capacity' if field == 'requests_per_second' else 'latency'][field])
                record['trials'].append({'workload': key, 'trial': trial, 'identity': row['identity'],
                                         'server_log': row['server_log']})
                print(json.dumps({'capture': key, 'impl': impl, 'trial': trial, 'status': 'measured'}), flush=True)
            record['series'][key] = series
        workload = load_bench.validate_spring_manifest(json.loads(HTTP_MANIFEST.read_text()), smoke).copy()
        calibrations = [calibration_trial(app, workload, oha, raw, database, n, 'capture', smoke)
                        for n in range(2 if smoke else 5)]
    record['calibration'] = {'samples': {m: [c[m] for c in calibrations] for m in CALIBRATION_METRICS}}
    record['calibration']['bands'] = {m: band(v) for m, v in record['calibration']['samples'].items()}
    probes = probe(workload['server_cpus'], samples=3 if smoke else 9)
    record['probe'] = {'samples': probes, 'bands': {m: band(v) for m, v in probes.items()}}
    (directory / 'record.json').write_text(json.dumps(record, indent=2) + '\n')
    print(f'captured {directory / "record.json"}')
    return directory


def db_state_check(app, record_path, pairs, outdir, smoke=False):
    """Does the database state explain a calibration drift (coordinator, 2026-11-24)? Go calibration trials alternate
    without and with VACUUM ANALYZE on one cluster, each against the record's band. Diagnostic only."""
    record = load(record_path)
    oha = Path(os.environ.get('OHA') or ROOT / '.tools' / 'oha-1.16.0' / 'oha')
    spring_bench.build_go(app)
    workload = load_bench.validate_spring_manifest(json.loads(HTTP_MANIFEST.read_text()), smoke).copy()
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    rows = []
    with spring_bench.postgres_cluster(workload['database_cpus']) as database:
        for n in range(pairs):
            for vacuum in ((False, True) if n % 2 == 0 else (True, False)):
                calibration = calibration_trial(app, workload, oha, outdir, database, n, f'vacuum-{vacuum}', smoke, vacuum)
                rows.append({'pair': n, 'vacuum_analyze': vacuum, 'calibration': calibration,
                             'out_of_band': drift(record, calibration, {})})
                print(json.dumps(rows[-1]), flush=True)
    summary = {v: {m: statistics.median(r['calibration'][m] for r in rows if r['vacuum_analyze'] == v)
                   for m in CALIBRATION_METRICS} for v in (False, True)}
    out = {'schema': 'flint.spring-db-state-check/1', 'record': record['_path'], 'bands': record['calibration']['bands'],
           'rows': rows, 'medians': {str(k): v for k, v in summary.items()}}
    (outdir / 'db-state-check.json').write_text(json.dumps(out, indent=2) + '\n')
    return out


SESSIONS = BASELINES / 'calibration-sessions'


def calibrate(app, samples, smoke=False, log=None):
    """One calibration session (coordinator, 2026-11-24 10:35Z): `samples` Go calibration trials and a probe, appended
    to benchmarks/spring/baselines/calibration-sessions/<app>.jsonl. Several sessions across idle gaps give the
    between-session spread that sets the guard's bands; one capture's samples alone understate it."""
    oha = Path(os.environ.get('OHA') or ROOT / '.tools' / 'oha-1.16.0' / 'oha')
    spring_bench.build_go(app)
    workload = load_bench.validate_spring_manifest(json.loads(HTTP_MANIFEST.read_text()), smoke).copy()
    outdir = Path(os.environ.get('FLINT_CALIBRATION_RAW') or '/tmp/flint-calibration-raw')
    outdir.mkdir(parents=True, exist_ok=True)
    context = (spring_bench.postgres_cluster(workload['database_cpus'])
               if spring_bench.app_row(app).get('database') == 'postgres' else contextlib.nullcontext())
    with context as database:
        trials = [calibration_trial(app, workload, oha, outdir, database, n, 'session', smoke) for n in range(samples)]
    row = {'time': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'app': app, 'smoke': smoke,
           'fingerprint': fingerprint(app, 'go', ['http']), 'database_protocol': load_bench.DATABASE_PROTOCOL,
           'calibration': {m: [t[m] for t in trials] for m in CALIBRATION_METRICS},
           'probe': probe(workload['server_cpus'], samples=5)}
    log = Path(log) if log else SESSIONS / f'{app}.jsonl'
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('a') as stream:
        stream.write(json.dumps(row) + '\n')
    print(json.dumps({k: statistics.median(v) for k, v in row['calibration'].items()}))
    return row


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('capture')
    p.add_argument('--app', required=True)
    p.add_argument('--impl', choices=sorted(TARGETS), default='go')
    p.add_argument('--workloads', default='http,error')
    p.add_argument('--smoke', action='store_true', help='one short trial per workload; never a usable record')
    p.add_argument('--output-root', type=Path, default=BASELINES)
    p = sub.add_parser('check')
    p.add_argument('record', type=Path)
    p = sub.add_parser('calibrate')
    p.add_argument('--app', required=True)
    p.add_argument('--samples', type=int, default=3)
    p.add_argument('--smoke', action='store_true')
    p.add_argument('--log', type=Path, help='the JSON-lines file to append to (default: the app\'s session log)')
    p = sub.add_parser('db-state-check')
    p.add_argument('--app', default='petclinic-rest')
    p.add_argument('--record', type=Path, required=True)
    p.add_argument('--pairs', type=int, default=3)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--smoke', action='store_true')
    args = parser.parse_args(argv)
    if args.command == 'calibrate':
        calibrate(args.app, args.samples, args.smoke, args.log)
        return 0
    if args.command == 'db-state-check':
        db_state_check(args.app, args.record, args.pairs, args.output, args.smoke)
        return 0
    if args.command == 'capture':
        capture(args.app, args.impl, set(args.workloads.split(',')), args.output_root, args.smoke)
        return 0
    record = load(args.record)
    differing = stale(record)
    print('current' if not differing else 'stale: ' + ', '.join(differing))
    return 1 if differing else 0


if __name__ == '__main__':
    sys.exit(main())
