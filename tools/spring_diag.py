#!/usr/bin/env python3
"""Diagnostic (never evidence): where a Spring port's request time goes, along a concurrency ladder.

    spring_diag.py [--app petclinic-rest] [--ladder 1,8,10,16,64] [--seconds 10] [--warmup 3] [--impl flint --impl go]
                   [--flint-binary <path>] [--env KEY=VALUE ...] [--counters] [--force] --output <file>

Throughput plan change 2 (docs/spring/phase1/throughput-plan-astra.md): an owner-1 diagnostic for petclinic-rest
that separates lease wait, lease hold, SQL drive, row mapping, dispatch and response time, with a concurrency ladder,
per-worker traffic and PostgreSQL CPU. data-access defines the server's counters; this tool drives the load and
measures everything it can from outside:

- one server process per ladder step (a fresh database each), on the manifest's server CPUs, against a disposable PostgreSQL cluster on the
  database CPUs (the benchmark's own launch path, spring_bench.launch through load_bench.spring_server);
- per ladder step: a warm-up, then `oha -z <seconds> -c <connections>` unthrottled on the load CPUs (capacity at
  that concurrency) against the manifest's path (petclinic: GET /petclinic/api/owners/1, owner 1);
- per step: requests per second, latency mean/p50/p99/p99.9, the server's CPU per request and per thread
  (/proc/<pid>/task/*/stat), PostgreSQL's CPU per request (the cluster's postmaster and its backends), and for a
  Flint server started with --counters, its counters (FLINT_DIAG_COUNTERS=<file>, written at exit; schema
  flint.diag-counters/1, defined by data-access), which cover that step's warm-up and measurement;
- with kernel.perf_event_paranoid at 2 or lower, `perf stat` on the server during each measured phase: instructions
  and cycles per request in user space (and in the kernel at 1 or lower), and context switches;
- after the ladder, a database census per implementation: a counted burst with statement logging on, giving parses
  (named and unnamed), binds, executions, simple statements, transactions, statement kinds, rows and connections
  opened per successful request, and the most frequent statements.

It refuses to run while a timed measurement holds the queue's lock, unless the queue itself runs it
(FLINT_MEASURE_WINDOW_CERTIFIED) or --force is given: diagnostic load would void someone's window.
"""
from __future__ import annotations

import argparse
import json
import os
import re
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


def read_counters(path):
    """The counters the server wrote at exit (data-access's contract: FLINT_DIAG_COUNTERS=<file>, replaced atomically
    at exit and whenever a pool closes; schema flint.diag-counters/1). Cumulative over the process: one server runs
    per ladder step, so they cover that step's warm-up and measurement."""
    if not path or not path.is_file():
        return None
    data = json.loads(path.read_text())
    timers = {name: dict(row, mean_ns=row['sum_ns'] / row['count'] if row.get('count') else None)
              for name, row in data.get('timers', {}).items()}
    return {'schema': data.get('schema'), 'timers': timers, 'gauges': data.get('gauges', {})}


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


def oha_run(oha, url, connections, seconds, cpus, request, rate=None):
    argv = ['taskset', '--cpu-list', ','.join(map(str, cpus)), str(oha), '-z', f'{seconds}s', '-c', str(connections),
            '--no-tui', '--output-format', 'json'] + (['-q', str(rate)] if rate else [])
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


PARANOID = Path('/proc/sys/kernel/perf_event_paranoid')
PERF_EVENTS = ('instructions:u', 'cycles:u', 'instructions:k', 'cycles:k', 'context-switches')


def perf_level():
    """kernel.perf_event_paranoid: at 2 a user may count its processes in user space only, at 1 or lower in the
    kernel too; above 2 not at all (venus defaults to 4; the owner lowers it to 2 for diagnostics, until reboot)."""
    try:
        return int(PARANOID.read_text())
    except (OSError, ValueError):
        return None


def perf_start(pid, seconds):
    """`perf stat` on the server for the measured phase, or None when the kernel refuses it."""
    level = perf_level()
    if level is None or level > 2:
        return None
    argv = ['perf', 'stat', '-x', ',', '-e', ','.join(PERF_EVENTS), '-p', str(pid), '--', 'sleep', str(seconds)]
    return subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)


def perf_finish(perf, requests):
    """Counts per successful request; an event the kernel refused is reported as unavailable."""
    if perf is None:
        return {'available': False, 'perf_event_paranoid': perf_level()}
    _, err = perf.communicate(timeout=60)
    out = {'available': True, 'perf_event_paranoid': perf_level(), 'per_request': {}, 'unavailable': []}
    for line in err.splitlines():
        fields = line.split(',')
        if len(fields) < 3 or fields[2] not in PERF_EVENTS:
            continue
        if fields[0].startswith('<'):
            out['unavailable'].append(fields[2])
        elif requests:
            out['per_request'][fields[2]] = float(fields[0]) / requests
    return out


def step(process, pgport, oha, url, connections, seconds, warmup, workload, request, rate=None):
    oha_run(oha, url, connections, warmup, workload['load_cpus'], request, rate)
    threads0, pg0 = thread_cpu(process.pid), {p: process_cpu(p) for p in postgres_pids(pgport)} if pgport else {}
    perf = perf_start(process.pid, seconds)
    raw = oha_run(oha, url, connections, seconds, workload['load_cpus'], request, rate)
    threads1 = thread_cpu(process.pid)
    pg1 = {p: process_cpu(p) for p in postgres_pids(pgport)} if pgport else {}
    summary, percentiles = raw['summary'], raw.get('latencyPercentiles', {})
    statuses = raw.get('statusCodeDistribution', {})
    requests = sum(statuses.values())
    per_thread = {f'{name}[{tid}]': cpu - threads0.get(tid, (name, 0.0))[1] for tid, (name, cpu) in threads1.items()}
    server_cpu = sum(per_thread.values())
    pg_cpu = sum(cpu - pg0.get(pid, 0.0) for pid, cpu in pg1.items())
    expected = str(request.get('status', 200))
    counted = perf_finish(perf, statuses.get(expected, 0))
    return {'connections': connections, 'fixed_rate': rate, 'seconds': seconds, 'requests': requests, 'statuses': statuses,
            'unexpected_statuses': requests - statuses.get(expected, 0),
            'requests_per_second': summary['requestsPerSec'],
            'latency_ms': {'mean': summary['average'] * 1000,
                           **{key: percentiles[q] * 1000 for key, q in (('p50', 'p50'), ('p99', 'p99'), ('p999', 'p99.9'))
                              if percentiles.get(q) is not None}},
            'server_cpu_seconds': server_cpu, 'server_cpu_us_per_request': server_cpu / requests * 1e6 if requests else None,
            'server_cpu_per_thread': {k: round(v, 3) for k, v in sorted(per_thread.items(), key=lambda kv: -kv[1]) if v > 0},
            'perf': counted,
            'postgres_cpu_seconds': pg_cpu, 'postgres_cpu_us_per_request': pg_cpu / requests * 1e6 if requests and pgport else None}


# ---------------------------------------------------------------------------------------------------------------
# The syscall census (coordinator 16:00Z, petclinic CPU plan): writes and waits per response. strace attaches to the
# warmed-up server (this process's own child, which ptrace_scope 1 allows) only for a counted burst, so start-up
# writes are not counted and the timed steps never run under ptrace. A fiber park is not a syscall; the waits a
# parked reactor makes (epoll, io_uring_enter, futex) per response are its visible part.

SYSCALLS = ('sendto', 'sendmsg', 'write', 'writev', 'recvfrom', 'read', 'io_uring_enter', 'epoll_wait', 'epoll_pwait',
            'epoll_pwait2', 'futex')
WRITES = ('sendto', 'sendmsg', 'write', 'writev')
WAITS = ('io_uring_enter', 'epoll_wait', 'epoll_pwait', 'epoll_pwait2', 'futex')


def strace_argv(log):
    """The server runs as strace's child (ptrace_scope 1 lets a tracer trace only its own descendants), every call
    timestamped, so the census counts only calls inside the burst's window."""
    return ['strace', '-f', '-ttt', '-qq', '-e', 'trace=' + ','.join(SYSCALLS), '-o', str(log)]


def parse_strace_log(text, began, ended):
    """{syscall: calls} for the calls `strace -f -ttt` logged between `began` and `ended` (epoch seconds). A call
    split by another thread's ("<unfinished ...>" then "<... resumed>") counts once, at its start."""
    calls = {}
    for line in text.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 3 or parts[2].startswith('<...'):
            continue
        try:
            when = float(parts[1])
        except ValueError:
            continue
        name = parts[2].split('(', 1)[0]
        if began <= when <= ended and name in SYSCALLS:
            calls[name] = calls.get(name, 0) + 1
    return calls


def syscall_census(log, began, ended, requests_ok, connections):
    calls = parse_strace_log(Path(log).read_text(errors='replace'), began, ended) if Path(log).is_file() else {}
    per = {name: calls.get(name, 0) / requests_ok for name in SYSCALLS} if requests_ok else {}
    return {'requests': requests_ok, 'connections': connections, 'calls': calls, 'per_response': per,
            'writes_per_response': sum(per.get(n, 0) for n in WRITES) if requests_ok else None,
            'waits_per_response': sum(per.get(n, 0) for n in WAITS) if requests_ok else None}


def traced_children(pid):
    """The traced server: the direct children of strace."""
    out = []
    for task in Path(f'/proc/{pid}/task').glob('*/children'):
        try:
            out += [int(child) for child in task.read_text().split()]
        except OSError:
            pass
    return out


# ---------------------------------------------------------------------------------------------------------------
# The database census (coordinator 03:37Z, Astra concurrency review): statements, prepares against executions,
# transactions, rows and connections per successful request, for each implementation, from the server's statement
# log. The pinned PostgreSQL has no pg_stat_statements, so the census turns on log_min_duration_statement=0 (the
# extended protocol logs parse, bind and execute separately) for a counted burst after the ladder; logging costs the
# backends CPU, so the ladder's CPU figures, taken without it, stay the clean ones.

CENSUS_SETTINGS = (('log_min_duration_statement', '0'), ('log_connections', 'on'),
                   ('log_line_prefix', "'%m [%p] db=%d '"))
DURATION = re.compile(r'LOG:  duration: [\d.]+ ms  (?:(parse|bind|execute) (.+?)|statement): (.*)$')
STAT_COLUMNS = ('xact_commit', 'xact_rollback', 'tup_returned', 'tup_fetched', 'sessions')


def psql(pgport, database, *commands):
    argv = [str(spring_bench.postgres_bin() / 'psql'), '-X', '-At', '-h', '127.0.0.1', '-p', str(pgport), '-U',
            'petclinic', '-d', database]
    for command in commands:
        argv += ['-c', command]  # one -c each: ALTER SYSTEM cannot run inside the implicit transaction of a list
    completed = subprocess.run(argv, capture_output=True, text=True)
    if completed.returncode:
        raise SystemExit(f'psql failed: {completed.stderr[-400:]}')
    return completed.stdout


def database_stats(pgport, database):
    row = psql(pgport, database, f"SELECT {', '.join(STAT_COLUMNS)} FROM pg_stat_database WHERE datname = '{database}'")
    return dict(zip(STAT_COLUMNS, map(int, row.strip().split('|'))))


def statement_kind(sql):
    head = sql.lstrip().split(None, 1)[0].upper() if sql.strip() else ''
    return {'BEGIN': 'begin', 'START': 'begin', 'COMMIT': 'commit', 'END': 'commit', 'ROLLBACK': 'rollback',
            'SET': 'set', 'SHOW': 'show', 'SELECT': 'select', 'INSERT': 'insert', 'UPDATE': 'update',
            'DELETE': 'delete'}.get(head, 'other')


def parse_census(text, database):
    """Counts from the statement log lines of one database."""
    counts = {'parse': 0, 'parse_unnamed': 0, 'bind': 0, 'execute': 0, 'simple': 0, 'connections': 0}
    kinds, texts = {}, {}
    tag = f' db={database} '
    for line in text.splitlines():
        if tag not in line:
            continue
        if 'connection authorized' in line:
            counts['connections'] += 1
            continue
        match = DURATION.search(line)
        if not match:
            continue
        phase, name, sql = match.groups()
        if phase == 'parse':
            counts['parse'] += 1
            counts['parse_unnamed'] += name == '<unnamed>'
            continue
        if phase == 'bind':
            counts['bind'] += 1
            continue
        counts['execute' if phase == 'execute' else 'simple'] += 1
        kind = statement_kind(sql)
        kinds[kind] = kinds.get(kind, 0) + 1
        key = ' '.join(sql.split())[:160]
        texts[key] = texts.get(key, 0) + 1
    return counts, kinds, texts


def census(pgport, database, process, oha, url, requests, connections, cpus, request):
    data_directory = psql(pgport, database, 'SHOW data_directory').strip()
    log = Path(data_directory).parent / 'server.log'  # spring_bench.postgres_cluster's layout
    time.sleep(11)  # idle backends flush their statistics within 10 s
    stats0, offset = database_stats(pgport, database), log.stat().st_size
    psql(pgport, database, *[f'ALTER SYSTEM SET {key} = {value}' for key, value in CENSUS_SETTINGS],
         'SELECT pg_reload_conf()')
    pg_pids = postgres_pids(pgport)
    pg0 = {pid: process_cpu(pid) for pid in pg_pids}
    try:
        time.sleep(0.5)
        argv = ['taskset', '--cpu-list', ','.join(map(str, cpus)), str(oha), '-n', str(requests), '-c', str(connections),
                '--no-tui', '--output-format', 'json']
        if request.get('method', 'GET') != 'GET':
            argv += ['-m', request['method']]
        raw = json.loads(subprocess.run(argv + [url], capture_output=True, text=True, check=True).stdout)
        time.sleep(0.5)
    finally:
        psql(pgport, database, *[f'ALTER SYSTEM RESET {key}' for key, _ in CENSUS_SETTINGS], 'SELECT pg_reload_conf()')
    pg_cpu = sum(process_cpu(pid) - pg0.get(pid, 0.0) for pid in postgres_pids(pgport))
    time.sleep(11)
    stats1 = database_stats(pgport, database)
    with log.open('rb') as stream:
        stream.seek(offset)
        text = stream.read().decode(errors='replace')
    counts, kinds, texts = parse_census(text, database)
    ok = raw.get('statusCodeDistribution', {}).get(str(request.get('status', 200)), 0)
    per = (lambda value: value / ok if ok else None)
    stats = {key: stats1[key] - stats0[key] for key in STAT_COLUMNS}
    return {'requests': ok, 'connections': connections,
            'per_request': {**{key: per(value) for key, value in counts.items()},
                            **{f'statements_{kind}': per(value) for kind, value in sorted(kinds.items())},
                            'transactions_committed (pg_stat_database)': per(stats['xact_commit']),
                            'rows_returned (pg_stat_database)': per(stats['tup_returned']),
                            'rows_fetched (pg_stat_database)': per(stats['tup_fetched']),
                            'sessions_opened (pg_stat_database)': per(stats['sessions']),
                            'backend_cpu_us_with_logging': per(pg_cpu * 1e6)},
            'totals': {'log': counts, 'kinds': kinds, 'pg_stat_database': stats},
            'top_statements': sorted(texts.items(), key=lambda kv: -kv[1])[:15]}


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
    parser.add_argument('--census-requests', type=int, default=2000, help='requests in the statement-log census')
    parser.add_argument('--no-census', action='store_true')
    parser.add_argument('--variant-binary', type=Path, help='the binary the --variant arms run (a floor reference)')
    parser.add_argument('--variant', action='append', default=[],
                        help='NAME=KEY=VALUE[,KEY=VALUE]: an arm running --variant-binary with that environment')
    parser.add_argument('--fixed-rate', type=int, help='also a step at this fixed rate (req/s) beside each capacity step')
    parser.add_argument('--syscalls', type=int, default=0, help='requests in an untimed strace census per arm (0: none)')
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
    impls = args.impl if args.impl is not None else ([] if args.variant else ['flint', 'go'])
    variants = {}
    for item in args.variant:
        name, _, settings = item.partition('=')
        variants[name] = dict(pair.split('=', 1) for pair in settings.split(',') if pair)
    impls = impls + list(variants)
    result = {'schema': 'flint.spring-diag/1', 'evidence': False, 'app': args.app, 'path': spec['path'],
              'ladder': ladder, 'seconds': seconds, 'warmup_seconds': warmup, 'workload_cpus':
              {k: workload[k] for k in ('server_cpus', 'load_cpus', 'database_cpus')}, 'binaries': {}, 'steps': {}}
    binaries = {'flint': (args.flint_binary.resolve() if args.flint_binary else spring_bench.build_flint(args.app))
                if 'flint' in impls else None,
                'go': spring_bench.build_go(args.app) if 'go' in impls else None}
    for name in variants:
        binaries[name] = args.variant_binary.resolve()
    database_kind = spring_bench.app_row(args.app).get('database')
    with tempfile.TemporaryDirectory(prefix='flint-diag-') as temporary, \
            (spring_bench.postgres_cluster(workload['database_cpus']) if database_kind == 'postgres'
             else _no_database()) as database:
        for impl in impls:
            extra_env = (dict(item.split('=', 1) for item in args.env) if impl == 'flint' else dict(variants.get(impl, {})))
            target = 'go' if impl == 'go' else 'flint'
            result['steps'][impl] = []

            def serve(label, counters=None, trace=None):
                """One server process (a fresh database each launch), for one ladder step or the census."""
                created = []

                def tracked():
                    env = database()
                    created.append(env)
                    return env
                port = spring_bench.free_port()
                launch_env = dict(extra_env, **({'FLINT_DIAG_COUNTERS': str(counters)} if counters else {}))
                argv_, env, cwd, identity = load_bench.spring_server(
                    spring_bench, args.app, target, port, tracked if database else None, workload,
                    manifest.get('environment', {}), False, binary=binaries[impl])
                env.update(launch_env)
                if trace:
                    argv_ = strace_argv(trace) + argv_
                result['binaries'][impl] = dict(identity, env=extra_env)
                log = args.output.with_suffix(f'.{impl}-{label}-server.log')
                with log.open('wb') as stream:
                    process = subprocess.Popen(argv_, env=env, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
                url = f'http://127.0.0.1:{port}{spec["path"]}'
                url_db = created[0]['POSTGRES_URL'] if created else None
                pgport = int(url_db.rsplit(':', 1)[1].split('/')[0]) if url_db else None
                return process, url, pgport, url_db.rsplit('/', 1)[1] if url_db else None

            def stop(process, traced=False):
                if traced:
                    # SIGTERM to the traced server, never to strace: a signalled strace detaches and leaves it running.
                    for child in traced_children(process.pid):
                        try:
                            os.kill(child, signal.SIGTERM)
                        except OSError:
                            pass
                else:
                    process.terminate()  # SIGTERM: Boot exits cleanly and the counters file is written
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()

            plan = [(c, None) for c in ladder] + ([(c, args.fixed_rate) for c in ladder] if args.fixed_rate else [])
            for connections, rate in plan:
                label = f'c{connections}' + (f'-q{rate}' if rate else '')
                counters = Path(temporary) / f'{impl}-{label}-counters.json' if (target == 'flint' and args.counters) else None
                process, url, pgport, _ = serve(label, counters)
                try:
                    wait_ready(int(url.split(':')[2].split('/')[0]), process)
                    row = step(process, pgport, args.oha, url, connections, seconds, warmup, workload, request, rate)
                finally:
                    stop(process)
                row['counters'] = read_counters(counters)
                result['steps'][impl].append(row)
                print(json.dumps({'impl': impl, 'connections': connections, 'rate': rate,
                                  'rps': round(row['requests_per_second']),
                                  'server_cpu_us': row['server_cpu_us_per_request'] and round(row['server_cpu_us_per_request'], 1),
                                  'postgres_cpu_us': row['postgres_cpu_us_per_request'] and round(row['postgres_cpu_us_per_request'], 1),
                                  'p50_ms': round(row['latency_ms'].get('p50', 0), 3)}), flush=True)
            if args.syscalls:
                trace = args.output.with_suffix(f'.{impl}-strace.log')
                process, url, pgport, _ = serve('syscalls', trace=trace)
                try:
                    wait_ready(int(url.split(':')[2].split('/')[0]), process)
                    oha_run(args.oha, url, 8, warmup, workload['load_cpus'], request)
                    count = 200 if args.smoke else args.syscalls
                    argv = ['taskset', '--cpu-list', ','.join(map(str, workload['load_cpus'])), str(args.oha), '-n',
                            str(count), '-c', '8', '--no-tui', '--output-format', 'json', url]
                    began = time.time()
                    raw = json.loads(subprocess.run(argv, capture_output=True, text=True, check=True).stdout)
                    ended = time.time()
                    ok = raw.get('statusCodeDistribution', {}).get(str(request.get('status', 200)), 0)
                finally:
                    stop(process, traced=True)
                result.setdefault('syscalls', {})[impl] = syscall_census(trace, began, ended, ok, 8)
                print(json.dumps({'impl': impl, 'writes_per_response': result['syscalls'][impl]['writes_per_response'],
                                  'waits_per_response': result['syscalls'][impl]['waits_per_response']}), flush=True)
            if database and not args.no_census:
                process, url, pgport, name = serve('census')
                try:
                    wait_ready(int(url.split(':')[2].split('/')[0]), process)
                    oha_run(args.oha, url, 8, warmup, workload['load_cpus'], request)
                    result.setdefault('census', {})[impl] = census(
                        pgport, name, process, args.oha, url, 200 if args.smoke else args.census_requests, 8,
                        workload['load_cpus'], request)
                finally:
                    stop(process)
                print(json.dumps({'impl': impl, 'census': {k: v and round(v, 3) for k, v in
                                                           result['census'][impl]['per_request'].items()}}), flush=True)
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
