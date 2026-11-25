#!/usr/bin/env python3
"""Deterministic per-request cost of one benchmarked Spring request: instructions by layer, GC allocations and bytes.

    python3 tools/spring_instr.py gs-rest-service greeting
    python3 tools/spring_instr.py petclinic-rest owner --binary build/spring/petclinic-rest-flint --json out.json
    python3 tools/spring_instr.py --list

Compare two commits in minutes, without a measurement window (decisions.md, 715a7c62): the counts do not depend on
machine load. They are not timing evidence; certified numbers come from the named baselines.

The requests are the benchmarked ones, from policy/spring-http-benchmark.json and
policy/spring-error-paths-benchmark.json: their path, method, headers and body, and the expected status, which the
first response must have. The Flint port is built as the HTTP benchmark builds it (spring_bench.py build_flint,
the release profile) unless --binary names an executable.

1. Instructions: the server runs under callgrind with one reactor (`SERVER_FLINT_THREADS=1`). After --warmup requests
   over one keep-alive connection the counters are zeroed, --requests more are sent, and the counters are dumped.
   Each function's own instructions go to a layer by its module (engine-reactor, engine-web, engine-servlet,
   webmvc, jdbc, engine-sql, libpq, druntime GC, libc, ...); the layers add up to the total. The GC allocation
   calls (druntime's ConservativeGC malloc, qalloc and calloc) come from the same dump.
2. Allocations and bytes: flint.arena's counting proxy, through Flint Boot's FLINT_ALLOCATION_REPORT (the
   collector's own block sizes). Two runs without callgrind, one of --warmup requests and one of --warmup plus
   --requests, each ended by SIGTERM; their difference over --requests is the per-request figure.

Everything runs under measure_queue.py hold (the queue's lock is found among this repository's worktrees when
FLINT_MEASURE_LOCK is unset), pinned to the CPUs above the benchmark's (policy: server 2-3, load 4-7, database
8-9). Every process it starts is stopped before it exits, on every path.
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import http.client
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
import spring_bench  # noqa: E402

MANIFESTS = (ROOT / 'policy' / 'spring-http-benchmark.json', ROOT / 'policy' / 'spring-error-paths-benchmark.json')
SCHEMA = 'flint.spring-instr/1'
GC_ALLOCATORS = ('14ConservativeGC6malloc', '14ConservativeGC6qalloc', '14ConservativeGC6calloc')

# Layers by D module prefix, most specific first; C symbols by name, then by the object that holds them.
D_LAYERS = (
    ('flint.engine.reactor', 'engine-reactor'), ('flint.engine.web', 'engine-web'),
    ('flint.engine.servlet', 'engine-servlet'), ('flint.engine.http', 'engine-http'),
    ('flint.engine.sql', 'engine-sql'), ('flint.engine.jdbc', 'jdbc'), ('flint.jdbc', 'jdbc'),
    ('flint.engine.aot', 'aot'), ('flint_aot', 'aot'), ('flint.engine.di', 'aot'),
    ('flint.web', 'webmvc'), ('flint.http', 'webmvc'), ('flint.jackson', 'jackson'), ('flint.boot', 'boot'),
    ('flint.security', 'security'), ('flint.transaction', 'tx'), ('flint.dao', 'tx'),
    ('flint.hibernate', 'validation'), ('flint.validation', 'validation'), ('flint.jakarta', 'validation'),
    ('flint.java', 'java'), ('flint.context', 'spring-core'), ('flint.beans', 'spring-core'),
    ('flint.core', 'spring-core'), ('flint.data', 'spring-core'), ('flint.arena', 'arena'),
    ('flint.slf4j', 'logging'), ('flint.log', 'logging'), ('flint.conc', 'conc'), ('flint.os', 'os'),
    ('core.internal.gc', 'druntime-gc'), ('core.gc', 'druntime-gc'), ('core', 'druntime'), ('object', 'druntime'),
    ('rt', 'druntime'), ('std', 'phobos'), ('flint', 'flint-other'),
)
C_PREFIXES = (
    (('PQ', 'pq', 'pg_', 'pqsecure', 'pgtls', 'scram_'), 'libpq'),
    (('ossl_', 'OSSL', 'SSL', 'ssl', 'EVP', 'evp', 'BN_', 'bn_', 'CRYPTO', 'ERR', 'BIO', 'tls'), 'openssl'),
    # engine-web's C shim around llhttp: its relay and parser callbacks.
    (('llhttp', 'llparse', 'relay', 'on_headers', 'on_field', 'on_value', 'on_url', 'on_message', 'on_body',
      'on_status', 'on_method', 'on_chunk'), 'llhttp'),
    (('io_uring', '__io_uring', '_io_uring'), 'liburing'), (('flint_',), 'flint-c'),
    (('gc_', 'onOutOfMemory'), 'druntime-gc'), (('_d_', 'rt_', '_aa', '__dmd', '_D'), 'druntime'),
)


def requests_by_name():
    """Every benchmarked request: name -> {app, method, path, headers, body, status}."""
    found = {}
    for manifest in MANIFESTS:
        document = json.loads(manifest.read_text())
        for key, row in document['apps'].items():
            app = row.get('app', key.partition(':')[0])
            expected = row.get('expected', {})
            request = expected.get('request', {})
            name = key.partition(':')[2] or {'gs-rest-service': 'greeting', 'petclinic-rest': 'owner'}.get(app, 'get')
            found[(app, name)] = {'app': app, 'name': name, 'method': request.get('method', 'GET'), 'path': row['path'],
                                  'headers': request.get('headers', {'Accept': '*/*'}), 'body': request.get('body'),
                                  'status': expected.get('status', 200), 'manifest': manifest.name}
    return found


def find_request(app, name):
    table = requests_by_name()
    aliases = {'nope': 'not-found', '404': 'not-found', 'invalid-post': 'validation-error', 'validation': 'validation-error',
               'owner1': 'owner', 'owner-1': 'owner'}
    key = (app, aliases.get(name, name))
    if key not in table:
        raise SystemExit(f'no benchmarked request {name!r} for {app}; --list shows them')
    return table[key]


# ---------------------------------------------------------------------------------------------------------------
# Running under hold, pinned


def queue_lock():
    """The measurement queue's MEASURING lock: FLINT_MEASURE_LOCK, else the worktree whose .flint/measure holds the
    watcher's log."""
    if os.environ.get('FLINT_MEASURE_LOCK'):
        return os.environ['FLINT_MEASURE_LOCK']
    listing = subprocess.run(['git', 'worktree', 'list', '--porcelain'], cwd=ROOT, capture_output=True, text=True).stdout
    for line in listing.splitlines():
        if line.startswith('worktree '):
            measure = Path(line[len('worktree '):]) / '.flint' / 'measure'
            if (measure / 'watch.log').is_file():
                return str(measure / 'MEASURING')
    return None


def rerun_under_hold():
    if os.environ.get('FLINT_SPRING_INSTR_HELD') == '1':
        return
    env = dict(os.environ, FLINT_SPRING_INSTR_HELD='1')
    lock = queue_lock()
    if lock:
        env['FLINT_MEASURE_LOCK'] = lock
    command = [sys.executable, str(ROOT / 'tools' / 'measure_queue.py'), 'hold', '--', sys.executable,
               str(Path(__file__).resolve()), *sys.argv[1:]]
    sys.exit(subprocess.call(command, env=env))


def cpus():
    """Three CPUs above the benchmark's (2-9): the server, this client, and PostgreSQL."""
    available = sorted(os.sched_getaffinity(0))
    spare = [cpu for cpu in available if cpu > 9] or available
    spare = spare[-3:] if len(spare) >= 3 else (spare * 3)[:3]
    return {'server': spare[0], 'client': spare[1], 'database': spare[2]}


@contextlib.contextmanager
def started(argv, env, cwd, log):
    """A process in this process group (so hold and the freezer see it as the step's own), stopped on every path."""
    with open(log, 'wb') as out:
        process = subprocess.Popen(argv, env=env, cwd=cwd, stdout=out, stderr=subprocess.STDOUT)
    try:
        yield process
    finally:
        stop(process)


def stop(process, grace=60):
    if process.poll() is None:
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


@contextlib.contextmanager
def postgres(cpu):
    """A disposable cluster of the pinned PostgreSQL peer, run directly (not through pg_ctl, which would leave the
    step's process group), TCP only on a free loopback port. Yields spring_bench's database() callable."""
    prefix = spring_bench.postgres_bin()
    with tempfile.TemporaryDirectory(prefix='flint-instr-pg-') as directory:
        data = Path(directory) / 'data'
        quiet = {'stdout': subprocess.DEVNULL, 'stderr': subprocess.STDOUT}
        subprocess.run([str(prefix / 'initdb'), '-D', str(data), '-U', 'petclinic', '--auth=trust', '--encoding=UTF8',
                        '--locale=C.UTF-8', '--no-sync'], check=True, **quiet)
        port = spring_bench.free_port()
        argv = ['taskset', '--cpu-list', str(cpu), str(prefix / 'postgres'), '-D', str(data), '-c',
                'listen_addresses=127.0.0.1', '-p', str(port), '-c', 'unix_socket_directories=', '-c', 'fsync=off']
        with started(argv, None, directory, Path(directory) / 'server.log') as server:
            wait_port(port, server, 60)
            counter = [0]

            def database():
                counter[0] += 1
                name = f'petclinic{counter[0]}'
                for _ in range(100):
                    done = subprocess.run([str(prefix / 'createdb'), '-h', '127.0.0.1', '-p', str(port), '-U', 'petclinic',
                                           name], **quiet)
                    if done.returncode == 0:
                        break
                    time.sleep(0.1)
                return {'POSTGRES_URL': f'jdbc:postgresql://127.0.0.1:{port}/{name}', 'POSTGRES_USER': 'petclinic',
                        'POSTGRES_PASS': 'petclinic'}
            yield database


def wait_port(port, process, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise SystemExit(f'the server exited ({process.returncode}) before listening on {port}')
        with contextlib.suppress(OSError), socket.create_connection(('127.0.0.1', port), timeout=1):
            return
        time.sleep(0.1)
    raise SystemExit(f'nothing listened on port {port} within {timeout} s')


# ---------------------------------------------------------------------------------------------------------------
# Requests


def send(port, request, count, check=False):
    """`count` requests over one keep-alive connection; with `check`, the first must have the expected status."""
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=60)
    body = request['body'].encode() if request['body'] is not None else None
    try:
        for index in range(count):
            connection.request(request['method'], request['path'], body=body, headers=request['headers'])
            response = connection.getresponse()
            payload = response.read()
            if check and index == 0 and response.status != request['status']:
                raise SystemExit(f'{request["method"]} {request["path"]}: status {response.status}, expected '
                                 f'{request["status"]}: {payload[:300]!r}')
    finally:
        connection.close()


def server_environment(app, port, database, binary):
    argv, env, cwd = spring_bench.launch(app, 'flint', port, database=database, binary=binary)
    env['SERVER_FLINT_THREADS'] = '1'
    return argv, env, cwd


# ---------------------------------------------------------------------------------------------------------------
# Instructions


def measure_instructions(app, request, binary, database, pins, warmup, measured, work):
    port = spring_bench.free_port()
    argv, env, cwd = server_environment(app, port, database, binary)
    out = work / 'callgrind.out'
    command = ['taskset', '--cpu-list', str(pins['server']), 'valgrind', '--tool=callgrind', '--dump-instr=no', '--demangle=no',
               '--compress-strings=no', '--compress-pos=no', f'--callgrind-out-file={out}', *argv]
    with started(command, env, cwd, work / 'callgrind-server.log') as server:
        wait_port(port, server, 300)
        send(port, request, warmup, check=True)
        control(server.pid, '-z')
        send(port, request, measured)
        control(server.pid, '-d')
    dumps = sorted(work.glob('callgrind.out*'), key=lambda path: path.stat().st_mtime)
    dump = next((path for path in dumps if path.name != 'callgrind.out'), None) or out
    totals = parse_callgrind(dumps_after_zero(dumps))
    return totals, dump


def control(pid, flag):
    done = subprocess.run(['callgrind_control', flag, str(pid)], capture_output=True, text=True)
    if done.returncode:
        raise SystemExit(f'callgrind_control {flag} {pid}: {done.stdout}{done.stderr}')


def dumps_after_zero(dumps):
    """The dump `callgrind_control -d` wrote: the one numbered .1 (or later), not the final dump at exit."""
    numbered = [path for path in dumps if re.search(r'\.\d+$', path.name)]
    return numbered[-1] if numbered else dumps[-1]


def demangled_module(symbol):
    """The dotted module path of a D symbol (`_D5flint6engine3web...` -> flint.engine.web...), or None."""
    if not symbol.startswith('_D'):
        return None
    rest, parts = symbol[2:], []
    while rest and rest[0].isdigit() and len(parts) < 4:
        digits = re.match(r'\d+', rest).group(0)
        length = int(digits)
        parts.append(rest[len(digits):len(digits) + length])
        rest = rest[len(digits) + length:]
    return '.'.join(parts) if parts else None


def layer_of(function, obj):
    module = demangled_module(function)
    if module is not None:
        for prefix, layer in D_LAYERS:
            if module == prefix or module.startswith(prefix + '.'):
                return layer
        if module.split('.')[0] not in ('flint', 'core', 'std', 'object', 'rt'):
            return 'app'
        return 'druntime'
    for prefixes, layer in C_PREFIXES:
        if function.startswith(prefixes):
            return layer
    name = (obj or '').rsplit('/', 1)[-1]
    if name.startswith('libc.so') or name.startswith('libc-'):
        return 'libc'
    if name.startswith('ld-linux') or name.startswith('ld.so'):
        return 'ld.so'
    if name.startswith(('libm.so', 'libpthread', 'libgcc', 'libdl')):
        return 'libc'
    return 'other'


def parse_callgrind(path):
    """Each function's own instructions, summed by layer; the dump's total; GC allocation calls."""
    layers, functions = {}, {}
    gc_calls, total = 0, None
    obj = fn = None
    callee = None
    skip_next = False
    with open(path, encoding='utf-8', errors='replace') as stream:
        for line in stream:
            if skip_next:
                skip_next = False
                continue
            if line.startswith('ob='):
                obj = line[3:].strip()
            elif line.startswith('fn='):
                fn = line[3:].strip()
            elif line.startswith('cfn='):
                callee = line[4:].strip()
            elif line.startswith('calls='):
                count = int(line[6:].split()[0])
                if callee and callee.startswith('_D') and any(name in callee for name in GC_ALLOCATORS) \
                        and not (fn and '14ConservativeGC' in fn):
                    gc_calls += count
                skip_next = True  # the call's inclusive cost: not this function's own
            elif line.startswith(('summary:', 'totals:')):
                total = int(line.split()[1])
            elif line[:1].isdigit() or line[:1] in '+-*':
                parts = line.split()
                if len(parts) >= 2 and fn is not None:
                    cost = int(parts[1])
                    functions[fn] = functions.get(fn, 0) + cost
                    layer = layer_of(fn, obj)
                    layers[layer] = layers.get(layer, 0) + cost
    own = sum(layers.values())
    return {'total': total if total is not None else own, 'own_sum': own, 'layers': layers, 'gc_calls': gc_calls,
            'functions': functions}


# ---------------------------------------------------------------------------------------------------------------
# Allocations


def measure_allocations(app, request, binary, database, pins, warmup, measured, work):
    """flint.arena's counts after `warmup` and after `warmup + measured` requests, each from its own run."""
    results = []
    for count in (warmup, warmup + measured):
        port = spring_bench.free_port()
        argv, env, cwd = server_environment(app, port, database, binary)
        report = work / f'allocations-{count}.txt'
        report.unlink(missing_ok=True)
        env['FLINT_ALLOCATION_REPORT'] = str(report)
        command = ['taskset', '--cpu-list', str(pins['server']), *argv]
        with started(command, env, cwd, work / f'allocations-{count}.log') as server:
            wait_port(port, server, 120)
            send(port, request, count, check=True)
        if not report.is_file():
            return None  # a binary built before Flint Boot's FLINT_ALLOCATION_REPORT
        allocations, size = (int(value) for value in report.read_text().split())
        results.append((allocations, size))
    (a0, b0), (a1, b1) = results
    return {'allocations': (a1 - a0) / measured, 'bytes': (b1 - b0) / measured}


# ---------------------------------------------------------------------------------------------------------------


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def report_table(result):
    lines = [f'{result["app"]} {result["request"]["name"]} ({result["request"]["method"]} {result["request"]["path"]}): '
             f'{result["measured"]} requests after {result["warmup"]}, commit {result["commit"][:12]}',
             f'  instructions/request   {result["instructions_per_request"]:>10,.0f}']
    for layer, value in sorted(result['layers_per_request'].items(), key=lambda item: -item[1]):
        if value >= 1:
            lines.append(f'    {layer:<20} {value:>10,.0f}  {100 * value / result["instructions_per_request"]:5.1f}%')
    lines.append(f'  GC allocation calls/request {result["gc_allocation_calls_per_request"]:>8.2f}')
    if result.get('allocations_per_request') is not None:
        lines.append(f'  allocations/request    {result["allocations_per_request"]:>10.2f}')
        lines.append(f'  bytes/request          {result["bytes_per_request"]:>10.1f}')
    else:
        lines.append('  allocations/request    unavailable (the binary predates FLINT_ALLOCATION_REPORT)')
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('app', nargs='?')
    parser.add_argument('request', nargs='?', help='greeting, not-found (nope), owner, validation-error (invalid-post)')
    parser.add_argument('--binary', type=Path, help='the Flint executable (default: build it as the benchmark does)')
    parser.add_argument('--warmup', type=int, default=1000)
    parser.add_argument('--requests', type=int, default=2000, help='measured requests')
    parser.add_argument('--no-allocations', action='store_true', help='skip the two allocation-counting runs')
    parser.add_argument('--json', type=Path, help='write the JSON summary here too')
    parser.add_argument('--keep', type=Path, help='keep the callgrind dump and logs in this directory')
    parser.add_argument('--list', action='store_true', help='list the benchmarked requests')
    args = parser.parse_args()
    if args.list:
        for (app, name), row in sorted(requests_by_name().items()):
            print(f'{app} {name}: {row["method"]} {row["path"]} -> {row["status"]} ({row["manifest"]})')
        return 0
    if not args.app or not args.request:
        parser.error('name an app and a request (--list shows them)')
    request = find_request(args.app, args.request)
    rerun_under_hold()
    pins = cpus()
    os.sched_setaffinity(0, {pins['client']})
    if args.binary:
        binary = args.binary.resolve()
    else:
        local = ROOT / '.flint' / 'bin'
        if (local / 'flint').is_file():  # this checkout's flint, as its builds use
            os.environ['PATH'] = str(local) + os.pathsep + os.environ.get('PATH', '')
        spring_bench.build_flint(args.app)
        binary = spring_bench.flint_binary(args.app)
    commit = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    with contextlib.ExitStack() as stack:
        work = Path(stack.enter_context(tempfile.TemporaryDirectory(prefix='flint-instr-'))) if not args.keep \
            else args.keep.resolve()
        work.mkdir(parents=True, exist_ok=True)
        database = None
        if spring_bench.app_row(args.app).get('database') == 'postgres':
            database = stack.enter_context(postgres(pins['database']))
        instructions, dump = measure_instructions(args.app, request, binary, database, pins, args.warmup,
                                                  args.requests, work)
        allocations = None if args.no_allocations else measure_allocations(
            args.app, request, binary, database, pins, args.warmup, args.requests, work)
        per = args.requests
        top = sorted(instructions['functions'].items(), key=lambda item: -item[1])[:25]
        result = {
            'schema': SCHEMA, 'app': args.app, 'request': request, 'commit': commit,
            'binary': {'path': str(binary), 'sha256': sha256(binary)}, 'warmup': args.warmup, 'measured': per,
            'instructions_per_request': instructions['total'] / per,
            'layers_per_request': {layer: value / per for layer, value in instructions['layers'].items()},
            'gc_allocation_calls_per_request': instructions['gc_calls'] / per,
            'allocations_per_request': allocations['allocations'] if allocations else None,
            'bytes_per_request': allocations['bytes'] if allocations else None,
            'top_functions_per_request': [[name, value / per] for name, value in top],
            'cpus': pins, 'callgrind_dump': str(dump) if args.keep else None,
        }
    text = json.dumps(result, indent=2)
    if args.json:
        args.json.write_text(text + '\n')
    print(report_table(result))
    print(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
