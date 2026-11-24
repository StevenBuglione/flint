#!/usr/bin/env python3
"""Diagnostic (never evidence): where a Spring port's request time goes, along a concurrency ladder.

    spring_diag.py [--app petclinic-rest] [--ladder 1,8,10,16,64] [--seconds 10] [--warmup 3] [--impl flint --impl go]
                   [--flint-binary <path>] [--env KEY=VALUE ...] [--counters] [--force] --output <file>

Throughput plan change 2 (docs/spring/phase1/throughput-plan-astra.md): an owner-1 diagnostic for petclinic-rest
that separates lease wait, lease hold, SQL drive, row mapping, dispatch and response time, with a concurrency ladder,
per-worker traffic and PostgreSQL CPU. data-access defines the server's counters; this tool drives the load and
measures everything it can from outside:

- one server per implementation, on the manifest's server CPUs, against a disposable PostgreSQL cluster on the
  database CPUs (the benchmark's own launch path, spring_bench.launch through load_bench.spring_server);
- per ladder step: a warm-up, then `oha -z <seconds> -c <connections>` unthrottled on the load CPUs (capacity at
  that concurrency) against the manifest's path (petclinic: GET /petclinic/api/owners/1, owner 1);
- per step: requests per second, latency mean/p50/p99/p99.9, the server's CPU per request and per thread
  (/proc/<pid>/task/*/stat), PostgreSQL's CPU per request (the cluster's postmaster and its backends), and for a
  Flint server started with --counters, the deltas of its counters (FLINT_DIAG_COUNTERS=<file>; the server rewrites
  the file on SIGUSR2; schema flint.diag-counters/1, defined with data-access).

It refuses to run while a timed measurement holds the queue's lock, unless the queue itself runs it
(FLINT_MEASURE_WINDOW_CERTIFIED) or --force is given: diagnostic load would void someone's window.
"""
from __future__ import annotations

import argparse
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import load_bench  # noqa: E402
import spring_bench  # noqa: E402

MANIFEST = ROOT / 'policy' / 'spring-http-benchmark.json'
LOCK = ROOT / '.flint' / 'measure' / 'MEASURING'
TICK = os.sysconf('SC_CLK_TCK')


def thread_cpu(pid):
    """{tid: (name, cpu seconds)} for every thread of `pid`."""
    out = {}
    for task in Path(f'/proc/{pid}/task').iterdir():
        try:
            text = (task / 'stat').read_text()
        except OSError:
            continue
        name = text[text.index('(') + 1:text.rindex(')')]
        fields = text[text.rindex(')') + 2:].split()
        out[int(task.name)] = (name, (int(fields[11]) + int(fields[12])) / TICK)
    return out


def process_cpu(pid):
    """CPU seconds of a process (all threads, children not included)."""
    try:
        fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    except OSError:
        return 0.0
    return (int(fields[11]) + int(fields[12])) / TICK


def postgres_pids(port):
    """The postmaster listening on `port` and its children (backends and workers)."""
    processes = {}
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            stat = (entry / 'stat').read_text()
            cmdline = (entry / 'cmdline').read_bytes().split(b'\0')
        except OSError:
            continue
        processes[int(entry.name)] = (int(stat.rsplit(')', 1)[1].split()[1]), cmdline)
    postmasters = {pid for pid, (_, cmd) in processes.items()
                   if cmd and cmd[0].endswith(b'/postgres') and b'-p' in b' '.join(cmd).split()
                   and str(port).encode() in cmd[cmd.index(b'-p') + 1:cmd.index(b'-p') + 2]}
    return postmasters | {pid for pid, (ppid, _) in processes.items() if ppid in postmasters}


def snapshot_counters(pid, path, timeout=5.0):
    """Ask the server to rewrite its counters file (SIGUSR2) and read it once it changes."""
    before = path.stat().st_mtime_ns if path.is_file() else 0
    os.kill(pid, signal.SIGUSR2)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.is_file() and path.stat().st_mtime_ns != before:
            try:
                return json.loads(path.read_text())
            except ValueError:
                pass  # being replaced; the server renames atomically, so retry
        time.sleep(0.02)
    return None


def counter_delta(before, after):
    """Per-step deltas of cumulative counters: timers as count, mean and the step's share; gauges as read after."""
    if not before or not after:
        return None
    timers = {}
    for name, row in after.get('timers', {}).items():
        old = before.get('timers', {}).get(name, {'count': 0, 'sum_ns': 0})
        count, total = row['count'] - old['count'], row['sum_ns'] - old['sum_ns']
        timers[name] = {'count': count, 'sum_ns': total, 'mean_ns': total / count if count else None,
                        'max_ns_since_start': row.get('max_ns')}
    workers = {wid: row.get('requests', 0) - before.get('workers', {}).get(wid, {}).get('requests', 0)
               for wid, row in after.get('workers', {}).items()}
    return {'timers': timers, 'gauges': after.get('gauges', {}), 'workers': workers}


def wait_ready(port, process, seconds=60):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise SystemExit(f'the server exited with {process.returncode} before listening')
        try:
            socket.create_connection(('127.0.0.1', port), timeout=1).close()
            return
        except OSError:
            time.sleep(0.05)
    raise SystemExit(f'the server did not listen on {port} within {seconds} s')


def oha_run(oha, url, connections, seconds, cpus, request):
    argv = ['taskset', '--cpu-list', ','.join(map(str, cpus)), str(oha), '-z', f'{seconds}s', '-c', str(connections),
            '--no-tui', '--output-format', 'json']
    if request.get('method', 'GET') != 'GET':
        argv += ['-m', request['method']]
    for key, value in request.get('headers', {}).items():
        argv += ['-H', f'{key}: {value}']
    if request.get('body'):
        argv += ['-d', request['body']]
    completed = subprocess.run(argv + [url], capture_output=True, text=True)
    if completed.returncode:
        raise SystemExit(f'oha failed: {completed.stderr[-500:]}')
    return json.loads(completed.stdout)


def step(process, pgport, oha, url, connections, seconds, warmup, workload, request, counters):
    oha_run(oha, url, connections, warmup, workload['load_cpus'], request)
    threads0, pg0 = thread_cpu(process.pid), {p: process_cpu(p) for p in postgres_pids(pgport)} if pgport else {}
    counters0 = snapshot_counters(process.pid, counters) if counters else None
    raw = oha_run(oha, url, connections, seconds, workload['load_cpus'], request)
    threads1 = thread_cpu(process.pid)
    pg1 = {p: process_cpu(p) for p in postgres_pids(pgport)} if pgport else {}
    counters1 = snapshot_counters(process.pid, counters) if counters else None
    summary, percentiles = raw['summary'], raw.get('latencyPercentiles', {})
    statuses = raw.get('statusCodeDistribution', {})
    requests = sum(statuses.values())
    per_thread = {f'{name}[{tid}]': cpu - threads0.get(tid, (name, 0.0))[1] for tid, (name, cpu) in threads1.items()}
    server_cpu = sum(per_thread.values())
    pg_cpu = sum(cpu - pg0.get(pid, 0.0) for pid, cpu in pg1.items())
    expected = str(request.get('status', 200))
    return {'connections': connections, 'seconds': seconds, 'requests': requests, 'statuses': statuses,
            'unexpected_statuses': requests - statuses.get(expected, 0),
            'requests_per_second': summary['requestsPerSec'],
            'latency_ms': {'mean': summary['average'] * 1000,
                           **{key: percentiles[q] * 1000 for key, q in (('p50', 'p50'), ('p99', 'p99'), ('p999', 'p99.9'))
                              if percentiles.get(q) is not None}},
            'server_cpu_seconds': server_cpu, 'server_cpu_us_per_request': server_cpu / requests * 1e6 if requests else None,
            'server_cpu_per_thread': {k: round(v, 3) for k, v in sorted(per_thread.items(), key=lambda kv: -kv[1]) if v > 0},
            'postgres_cpu_seconds': pg_cpu, 'postgres_cpu_us_per_request': pg_cpu / requests * 1e6 if requests and pgport else None,
            'counters': counter_delta(counters0, counters1)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--app', default='petclinic-rest')
    parser.add_argument('--ladder', default='1,8,10,16,64')
    parser.add_argument('--seconds', type=int, default=10)
    parser.add_argument('--warmup', type=int, default=3)
    parser.add_argument('--impl', action='append', choices=['flint', 'go'])
    parser.add_argument('--flint-binary', type=Path, help='a Flint build made elsewhere (a diagnostic build, say)')
    parser.add_argument('--env', action='append', default=[], help='KEY=VALUE for the Flint server')
    parser.add_argument('--counters', action='store_true', help='start Flint with FLINT_DIAG_COUNTERS and read them')
    parser.add_argument('--oha', type=Path, default=Path(os.environ.get('OHA', ROOT / '.tools' / 'oha-1.16.0' / 'oha')))
    parser.add_argument('--force', action='store_true', help='run although a timed measurement holds the lock')
    parser.add_argument('--smoke', action='store_true', help='ladder 1,8 for 1 s each')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    if LOCK.exists() and not os.environ.get('FLINT_MEASURE_WINDOW_CERTIFIED') and not args.force:
        raise SystemExit(f'a timed measurement is in progress ({LOCK}); diagnostic load would void it')
    if not args.oha.is_file() or load_bench.file_hash(args.oha) != load_bench.OHA_SHA256:
        raise SystemExit('the pinned oha is missing (--oha or OHA)')
    ladder = [1, 8] if args.smoke else [int(c) for c in args.ladder.split(',')]
    seconds, warmup = (1, 1) if args.smoke else (args.seconds, args.warmup)
    manifest = json.loads(MANIFEST.read_text())
    spec, workload = manifest['apps'][args.app], manifest['workload']
    request = dict(spec['expected'].get('request', {}), status=spec['expected']['status'])
    impls = args.impl or ['flint', 'go']
    result = {'schema': 'flint.spring-diag/1', 'evidence': False, 'app': args.app, 'path': spec['path'],
              'ladder': ladder, 'seconds': seconds, 'warmup_seconds': warmup, 'workload_cpus':
              {k: workload[k] for k in ('server_cpus', 'load_cpus', 'database_cpus')}, 'binaries': {}, 'steps': {}}
    binaries = {'flint': (args.flint_binary.resolve() if args.flint_binary else spring_bench.build_flint(args.app))
                if 'flint' in impls else None,
                'go': spring_bench.build_go(args.app) if 'go' in impls else None}
    database_kind = spring_bench.app_row(args.app).get('database')
    with tempfile.TemporaryDirectory(prefix='flint-diag-') as temporary, \
            (spring_bench.postgres_cluster(workload['database_cpus']) if database_kind == 'postgres'
             else _no_database()) as database:
        for impl in impls:
            created = []

            def tracked():
                env = database()
                created.append(env)
                return env
            port = spring_bench.free_port()
            extra_env = dict(item.split('=', 1) for item in args.env) if impl == 'flint' else {}
            counters = Path(temporary) / f'{impl}-counters.json' if (impl == 'flint' and args.counters) else None
            if counters:
                extra_env['FLINT_DIAG_COUNTERS'] = str(counters)
            argv_, env, cwd, identity = load_bench.spring_server(
                spring_bench, args.app, impl, port, tracked if database else None, workload,
                manifest.get('environment', {}), False, binary=binaries[impl])
            env.update(extra_env)
            pgport = int(created[0]['POSTGRES_URL'].rsplit(':', 1)[1].split('/')[0]) if created else None
            result['binaries'][impl] = dict(identity, env=extra_env)
            log = args.output.with_suffix(f'.{impl}-server.log')
            with log.open('wb') as stream:
                process = subprocess.Popen(argv_, env=env, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
            try:
                wait_ready(port, process)
                url = f'http://127.0.0.1:{port}{spec["path"]}'
                result['steps'][impl] = []
                for connections in ladder:
                    row = step(process, pgport, args.oha, url, connections, seconds, warmup, workload, request, counters)
                    result['steps'][impl].append(row)
                    print(json.dumps({'impl': impl, 'connections': connections,
                                      'rps': round(row['requests_per_second']),
                                      'server_cpu_us': row['server_cpu_us_per_request'] and round(row['server_cpu_us_per_request'], 1),
                                      'postgres_cpu_us': row['postgres_cpu_us_per_request'] and round(row['postgres_cpu_us_per_request'], 1),
                                      'p50_ms': round(row['latency_ms'].get('p50', 0), 3)}), flush=True)
            finally:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    return 0


class _no_database:
    def __enter__(self):
        return None

    def __exit__(self, *exc):
        return False


if __name__ == '__main__':
    sys.exit(main())
