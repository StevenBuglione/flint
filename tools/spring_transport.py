#!/usr/bin/env python3
"""Diagnostic (never evidence): what HTTP/1.1 framing and connection lifetime cost on the gated error paths.

    spring_transport.py [--workload gs-rest-service:not-found] [--workload petclinic-rest:validation-error]
                        [--workload petclinic-rest] [--trials 7] [--warmup 10] [--latency 30] [--capacity 20] [--no-java] [--smoke] --output <file>

Astra's error-path review (docs/spring/phase1/error-paths-astra.md, action 1) prices the transport difference before
the owner decides on HTTP parity (ADR-033): Java's Tomcat answers both error paths with chunked framing and closes
the connection after the validation 400, Flint copies both, and the Go comparators send Content-Length and keep
every connection. The same golden records chunked framing for petclinic's owner GET, the Phase 1 HTTP workload
(policy/spring-http-benchmark.json 'petclinic-rest'), so that workload is priced too. Run it inside a build tree (the queue's `in: tree`): it uses that tree's load_bench and
spring_bench, so the Flint port and the Go comparator are the tree's.

1. Raw exchange, per workload and implementation (Java, Flint, Go and the Go variants): one HTTP/1.1 request with
   no Connection header on a fresh socket, the response bytes exactly as received (status line, headers in order,
   framing, chunk sizes), whether the server then closes the socket, and the outcome of a second request on it.
2. Load, per workload: Go as registered and the Go variants, interleaved for --trials trials through load_bench's
   own trial (fixed-rate latency phase, then capacity), and Flint and Java once each for context. Each trial counts
   accepted connections from the kernel's TCP PassiveOpens counter around each phase, less the harness's own
   probes (each opens one connection), per completed request.

The Go variants are a scratch copy of the registered comparator with one hook before the status line its writeJSON
sends (only the measured path is requested under load): GO_TRANSPORT_CHUNKED=1 sets `Transfer-Encoding: chunked` (net/http then frames the body
in chunks, written with the head and the terminator in one flush), GO_TRANSPORT_CLOSE_STATUS=400 adds
`Connection: close` to 400 responses (net/http closes after the reply). The registered comparator is untouched.

Arms: `go` (registered), `go-chunked` (chunked, connection kept), and for the workload whose status is 400
`go-chunked-close` (chunked, closed after each 400, as Tomcat does).

It refuses to run while a timed measurement holds the queue's lock, unless the queue itself runs it
(FLINT_MEASURE_WINDOW_CERTIFIED) or --force is given.

    spring_transport.py parity --app <app> [--impl go|flint] [--record]

ADR-033's enforcement (owner decision 118b4482): on every gated error path (policy/spring-error-paths-benchmark.json)
an implementation matches the Java golden's reason phrase, framing and connection lifetime. This starts the
implementation of this checkout (the registered Go comparator by default), makes the raw exchange of each of the
app's gated workloads and compares it with the golden. --record writes benchmarks/spring/parity/<app>.json, which
spring_bench.py register and check-registry require of the comparator's current source, as ADR-032 requires its SQL
census. Short and untimed; run it under `measure_queue.py hold`.
"""
from __future__ import annotations

import argparse
import json
import os
import random
import shutil
import socket
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOCK = HERE.parent / '.flint' / 'measure' / 'MEASURING'
ERRORS = 'policy/spring-error-paths-benchmark.json'
WORKLOADS = {'gs-rest-service:not-found': ERRORS, 'petclinic-rest:validation-error': ERRORS,
             'petclinic-rest': 'policy/spring-http-benchmark.json'}

HOOK = '''package main

// Diagnostic only (tools/spring_transport.py); never part of the registered comparator.

import (
	"net/http"
	"os"
	"strconv"
)

var transportChunked = os.Getenv("GO_TRANSPORT_CHUNKED") == "1"

var transportCloseStatus = func() int {
	status, _ := strconv.Atoi(os.Getenv("GO_TRANSPORT_CLOSE_STATUS"))
	return status
}()

func transportVariant(w http.ResponseWriter, status int) {
	if transportChunked {
		w.Header().Set("Transfer-Encoding", "chunked")
	}
	if transportCloseStatus != 0 && status == transportCloseStatus {
		w.Header().Set("Connection", "close")
	}
}
'''

ARM_ENV = {'go': {}, 'go-chunked': {'GO_TRANSPORT_CHUNKED': '1'},
           'go-chunked-close': {'GO_TRANSPORT_CHUNKED': '1', 'GO_TRANSPORT_CLOSE_STATUS': '400'}}


def require(condition, message):
    if not condition:
        raise SystemExit(message)


# ---------------------------------------------------------------------------------------------------------------
# The Go variant


def insert_hook(source):
    """writeJSON's text with transportVariant(w, status) before its WriteHeader(status); None when this file has
    no writeJSON."""
    start = source.find('func writeJSON(')
    if start < 0:
        return None
    end = source.find('\n}\n', start)
    call = source.find('\tw.WriteHeader(status)', start, end)
    require(call >= 0, 'writeJSON has no w.WriteHeader(status)')
    return source[:call] + '\ttransportVariant(w, status)\n' + source[call:]


def build_variant(spring, app, directory):
    """A scratch copy of the tree's registered Go comparator with the transport hook, built as spring_bench builds
    the comparator (pinned Go, CGO off, trimmed, stripped)."""
    source = spring.ROOT / spring.app_row(app)['go']['directory']
    copy = directory / f'go-variant-{app}'
    if copy.exists():
        shutil.rmtree(copy)
    shutil.copytree(source, copy)
    hooked = []
    for path in sorted(copy.glob('*.go')):
        text = insert_hook(path.read_text())
        if text is not None:
            path.write_text(text)
            hooked.append(path.name)
    require(len(hooked) == 1, f'{app}: expected one writeJSON in the Go comparator, found {hooked}')
    (copy / 'transport_variant.go').write_text(HOOK)
    env = spring.vibe_bench.go_environment()
    env['CGO_ENABLED'] = '0'
    binary = directory / f'{app}-go-variant'
    subprocess.run([str(spring.vibe_bench.pinned_go()), 'build', '-buildvcs=false', '-trimpath', '-ldflags=-s -w',
                    '-o', str(binary), '.'], cwd=copy, env=env, check=True)
    return binary, hooked[0]


# ---------------------------------------------------------------------------------------------------------------
# One raw exchange


def request_bytes(spec, port):
    request = spec['expected'].get('request', {})
    body = request.get('body')
    lines = [f"{request.get('method', 'GET')} {spec['path']} HTTP/1.1", f'Host: 127.0.0.1:{port}']
    lines += [f'{name}: {value}' for name, value in request.get('headers', {}).items()]
    if body is not None:
        lines.append(f'Content-Length: {len(body.encode())}')
    return ('\r\n'.join(lines) + '\r\n\r\n').encode() + (body.encode() if body is not None else b'')


class Reader:
    def __init__(self, sock):
        self.sock, self.buffer = sock, b''

    def fill(self):
        data = self.sock.recv(65536)
        if not data:
            raise EOFError('connection closed mid-response')
        self.buffer += data

    def until(self, marker):
        while marker not in self.buffer:
            self.fill()
        index = self.buffer.index(marker) + len(marker)
        part, self.buffer = self.buffer[:index], self.buffer[index:]
        return part

    def exactly(self, count):
        while len(self.buffer) < count:
            self.fill()
        part, self.buffer = self.buffer[:count], self.buffer[count:]
        return part


def read_response(reader):
    """(raw bytes, parsed) of one HTTP/1.1 response; the body is dechunked into `body`."""
    head = reader.until(b'\r\n\r\n')
    lines = head.decode('latin-1').split('\r\n')[:-2]
    status_line, headers = lines[0], [tuple(part.strip() for part in line.split(':', 1)) for line in lines[1:]]
    names = {name.lower(): value for name, value in headers}
    raw, body, chunks = head, b'', []
    if names.get('transfer-encoding', '').lower() == 'chunked':
        while True:
            size_line = reader.until(b'\r\n')
            size = int(size_line.split(b';')[0], 16)
            raw += size_line
            if size == 0:
                raw += reader.until(b'\r\n')  # no trailers expected: the empty line ends the message
                break
            data = reader.exactly(size + 2)
            raw += data
            body += data[:-2]
            chunks.append(size)
        framing = 'chunked'
    elif 'content-length' in names:
        body = reader.exactly(int(names['content-length']))
        raw += body
        framing = 'content-length'
    else:
        framing = 'close-delimited'
    parts = status_line.split(' ', 2)
    return raw, {'status_line': status_line, 'status': int(parts[1]), 'reason': parts[2] if len(parts) > 2 else '',
                 'headers': [list(pair) for pair in headers], 'framing': framing, 'chunks': chunks,
                 'body_bytes': len(body), 'body': body.decode('utf-8', 'replace'),
                 'connection': names.get('connection')}


def peer_state(sock, wait=0.3):
    """'closed' (FIN), 'reset' (RST) or 'open' after the first response."""
    sock.settimeout(wait)
    try:
        data = sock.recv(1, socket.MSG_PEEK)
        return 'closed' if data == b'' else 'data'
    except socket.timeout:
        return 'open'
    except ConnectionResetError:
        return 'reset'
    finally:
        sock.settimeout(5)


def exchange(port, spec):
    """One request on a fresh socket, the server's state after it, and a second request on the same socket."""
    request = request_bytes(spec, port)
    with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
        sock.sendall(request)
        reader = Reader(sock)
        raw, first = read_response(reader)
        after = peer_state(sock)
        second = {}
        try:
            sock.sendall(request)
            _, response = read_response(reader)
            second = {'outcome': 'answered', 'status': response['status']}
        except (EOFError, ConnectionResetError, BrokenPipeError, socket.timeout) as exc:
            second = {'outcome': 'refused', 'error': type(exc).__name__}
    first['raw'] = raw.decode('latin-1')
    first['raw_bytes'] = len(raw)
    return {'request': request.decode('latin-1'), 'first': first, 'after_first': after, 'second_request': second,
            'reused': second.get('outcome') == 'answered'}


# ---------------------------------------------------------------------------------------------------------------
# ADR-033: parity with the golden on the gated paths


def golden_transport(golden, spec):
    """(expected transport, golden case names) of a gated workload: the golden's cases with the workload's method,
    path, status and media type, which must agree."""
    request = spec['expected'].get('request', {})
    rows, names = [], []
    for case in golden['observations']:
        response = case['response']
        headers = {name.lower(): value for name, value in response.get('headers', [])}
        if (case['request'].get('method', 'GET') == request.get('method', 'GET') and case['request'].get('path') == spec['path']
                and response.get('status') == spec['expected']['status']
                and headers.get('content-type', '').split(';')[0].strip() == spec['expected']['content_type']):
            rows.append({'reason': response.get('reason', ''),
                         'framing': 'chunked' if headers.get('transfer-encoding', '').lower() == 'chunked' else 'content-length',
                         'connection': 'close' if headers.get('connection', '').lower() == 'close' else 'keep'})
            names.append(case['name'])
    require(rows, f"the golden has no case for {request.get('method', 'GET')} {spec['path']} {spec['expected']['status']}")
    require(all(row == rows[0] for row in rows), f"the golden's cases for {spec['path']} disagree on transport: {rows}")
    return rows[0], names


def observed_transport(result):
    """What an exchange shows: the reason phrase, the framing, and the connection's lifetime, which is 'close' only
    when the response says `Connection: close` and the server closes, 'keep' only when it says neither and answers a
    second request on the socket."""
    first = result['first']
    announced = (first['connection'] or '').lower() == 'close'
    if announced and not result['reused']:
        lifetime = 'close'
    elif not announced and result['reused']:
        lifetime = 'keep'
    else:
        lifetime = f"inconsistent (Connection: {first['connection']}, second request {result['second_request']['outcome']})"
    return {'reason': first['reason'], 'framing': first['framing'], 'connection': lifetime}


def parity_problems(expected, observed):
    return [f'{field}: expected {expected[field]!r}, got {observed[field]!r}'
            for field in ('reason', 'framing', 'connection') if expected[field] != observed[field]]


def parity_main(argv):
    p = argparse.ArgumentParser(prog='spring_transport.py parity')
    p.add_argument('--app', required=True)
    p.add_argument('--impl', choices=['go', 'flint'], default='go')
    p.add_argument('--binary', type=Path, help='measure this build instead of the checkout\'s')
    p.add_argument('--record', action='store_true', help='write benchmarks/spring/parity/<app>.json (Go only)')
    a = p.parse_args(argv)
    require(not (a.record and (a.impl != 'go' or a.binary)), '--record is for the checkout\'s Go comparator')
    sys.path.insert(0, str(HERE))
    import spring_bench as spring
    manifest = json.loads((spring.ROOT / ERRORS).read_text())
    keys = [key for key, spec in manifest['apps'].items() if spec.get('app', key) == a.app]
    require(keys, f'{a.app} has no gated error path in {ERRORS}')
    golden_file = spring.golden_path(a.app)
    golden = json.loads(golden_file.read_text())
    # Absolute: a Flint port runs from its own directory.
    binary = a.binary.resolve() if a.binary else (spring.build_go(a.app) if a.impl == 'go' else spring.build_flint(a.app))
    record = {'schema': 'flint.spring-parity/1', 'app': a.app, 'implementation': a.impl,
              'adr': 'docs/adr/ADR-033-http-parity-on-the-gated-paths.md', 'manifest': ERRORS,
              'golden_sha256': spring.sha256(golden_file), 'binary_sha256': spring.sha256(binary),
              'comparator_sha256': spring.comparator_digest(a.app) if a.impl == 'go' else None,
              'taken': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'workloads': {}}
    import contextlib
    with (spring.postgres_cluster() if spring.app_row(a.app).get('database') == 'postgres'
          else contextlib.nullcontext()) as database:
        for key in keys:
            spec = manifest['apps'][key]
            expected, cases = golden_transport(golden, spec)
            port = spring.free_port()
            argv, env, cwd = spring.launch(a.app, a.impl, port, database, (), binary)
            with tempfile_log() as log:
                process = subprocess.Popen(argv, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT,
                                           start_new_session=True)
                try:
                    exchanges = None
                    deadline = time.monotonic() + 30
                    while exchanges is None:
                        require(process.poll() is None, f'{a.app} [{a.impl}] exited before it answered')
                        try:
                            exchanges = [exchange(port, spec) for _ in range(3)]
                        except OSError:
                            require(time.monotonic() < deadline, f'{a.app} [{a.impl}] did not answer')
                            time.sleep(.1)
                finally:
                    process.terminate()
                    try:
                        process.wait(10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
            observed = [observed_transport(result) for result in exchanges]
            problems = sorted({problem for seen in observed for problem in parity_problems(expected, seen)})
            record['workloads'][key] = {'golden_cases': cases, 'expected': expected, 'observed': observed[0],
                                        'repeats_agree': all(seen == observed[0] for seen in observed),
                                        'problems': problems,
                                        'response': exchanges[0]['first']['raw']}
            print(f"{key} [{a.impl}]: {'parity' if not problems else '; '.join(problems)}")
    record['problems'] = sum(len(w['problems']) + (not w['repeats_agree']) for w in record['workloads'].values())
    if a.record:
        spring.PARITY.mkdir(parents=True, exist_ok=True)
        (spring.PARITY / f'{a.app}.json').write_text(json.dumps(record, indent=2) + '\n')
    return 1 if record['problems'] else 0


@__import__('contextlib').contextmanager
def tempfile_log():
    import tempfile
    with tempfile.TemporaryFile() as stream:
        yield stream


# ---------------------------------------------------------------------------------------------------------------
# Accepted connections


def passive_opens():
    """The kernel's TCP PassiveOpens: connections accepted by every listener (the runner is otherwise quiet)."""
    lines = [line.split() for line in Path('/proc/net/snmp').read_text().splitlines() if line.startswith('Tcp:')]
    return int(lines[1][lines[0].index('PassiveOpens')])


def accepts_per_phase(row):
    """Accepted connections per completed request in each measured phase: the PassiveOpens delta across the phase,
    less the harness's own connections (one per correctness probe, and the readiness check after the previous
    phase)."""
    marks = {o['event']: o['data'] for o in row['observations']}
    result = {}
    for phase, before in (('latency', 'after-warmup'), ('capacity', 'after-latency')):
        delta = marks['after-' + phase] - marks[before]
        own = row[phase]['process']['correctness_probes'] + 1
        result[phase] = {'passive_opens': delta, 'harness_connections': own, 'requests': row[phase]['count'],
                         'accepts_per_request': max(delta - own, 0) / row[phase]['count']}
    return result


# ---------------------------------------------------------------------------------------------------------------
# Summary


def bootstrap(new, old, replicates=10000):
    """perf_stats.median_ratio_interval's estimator (same seed, 99%), for fewer than nine trials as well."""
    rng = random.Random(20261121)
    medians = sorted(statistics.median(rng.choices(new, k=len(new))) /
                     statistics.median(rng.choices(old, k=len(old))) for _ in range(replicates))
    return [statistics.median(new) / statistics.median(old), medians[int(replicates * .005)],
            medians[int(replicates * .995)]]


METRICS = (('p50_us', 'latency', 'p50_ms', 1000), ('p99_us', 'latency', 'p99_ms', 1000),
           ('p999_us', 'latency', 'p999_ms', 1000), ('cpu_us_per_request', 'latency', 'cpu_ns_per_request', 1e-3),
           ('capacity_rps', 'capacity', 'requests_per_second', 1))


def summarize(rows):
    arms = {}
    for row in rows:
        series = arms.setdefault(row['arm'], {name: [] for name, *_ in METRICS} |
                                 {'accepts_per_request_latency': [], 'accepts_per_request_capacity': []})
        for name, phase, field, scale in METRICS:
            series[name].append(row[phase][field] * scale)
        for phase in ('latency', 'capacity'):
            series['accepts_per_request_' + phase].append(row['accepts'][phase]['accepts_per_request'])
    medians = {arm: {name: statistics.median(values) for name, values in series.items()} for arm, series in arms.items()}
    ratios = {}
    if 'go' in arms:
        for arm in arms:
            if arm.startswith('go-') and len(arms[arm]['p99_us']) > 1 and len(arms['go']['p99_us']) > 1:
                ratios[arm + ' / go'] = {name: bootstrap(arms[arm][name], arms['go'][name]) for name, *_ in METRICS}
    return {'series': arms, 'medians': medians, 'ratios': ratios}


# ---------------------------------------------------------------------------------------------------------------


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ['parity']:
        return parity_main(argv[1:])
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--workload', action='append', choices=list(WORKLOADS))
    p.add_argument('--trials', type=int, default=7, help='interleaved trials of each Go arm')
    p.add_argument('--warmup', type=int, default=10)
    p.add_argument('--latency', type=int, default=30, help='seconds of the fixed-rate phase')
    p.add_argument('--capacity', type=int, default=20, help='seconds of the unthrottled phase')
    p.add_argument('--no-java', action='store_true', help='skip the Java reference (raw exchange and context trial)')
    p.add_argument('--no-flint', action='store_true')
    p.add_argument('--force', action='store_true', help='run although a timed measurement holds the lock')
    p.add_argument('--smoke', action='store_true', help='one trial, 2 s phases; never a result')
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args(argv)
    if LOCK.exists() and not os.environ.get('FLINT_MEASURE_WINDOW_CERTIFIED') and not a.force:
        raise SystemExit('a timed measurement holds the queue lock; queue this (tools/measure_queue.py) or pass --force')
    root = Path.cwd()
    sys.path.insert(0, str(root / 'tools'))
    import load_bench
    import spring_bench as spring
    require(Path(load_bench.__file__).resolve().parent == root / 'tools', 'run inside a checkout (cwd) with tools/')
    manifests = {path: json.loads((root / path).read_text()) for path in set(WORKLOADS.values())}
    for manifest in manifests.values():
        load_bench.validate_spring_manifest(manifest, True)
    require(len({json.dumps(m['workload'], sort_keys=True) for m in manifests.values()}) == 1,
            'the two manifests differ in their workload (CPU sets, connections)')
    workload = dict(manifests[ERRORS]['workload'])
    workload.update(warmup_seconds=a.warmup, duration_seconds=a.latency, capacity_seconds=a.capacity)
    trials = a.trials
    if a.smoke:
        workload.update(warmup_seconds=1, duration_seconds=2, capacity_seconds=2,
                        connections=min(workload['connections'], 8))
        trials = 1
    oha = Path(shutil.which('oha') or root / '.tools/oha-1.16.0/oha')
    require(oha.is_file() and load_bench.file_hash(oha) == load_bench.OHA_SHA256, 'the pinned oha is missing')
    a.output.parent.mkdir(parents=True, exist_ok=True)
    outdir = a.output.parent / (a.output.stem + '-raw')
    outdir.mkdir(exist_ok=True)
    result = {'schema': 'flint.spring-transport/1', 'mode': 'smoke' if a.smoke else 'diagnostic',
              'note': 'diagnostic, never evidence: prices framing and connection lifetime on the error paths',
              'manifests': {k: WORKLOADS[k] for k in a.workload or WORKLOADS}, 'workload': workload, 'trials_per_go_arm': trials, 'status': 'running',
              'tree': subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=root, capture_output=True, text=True).stdout.strip(),
              'workloads': {}, 'errors': []}

    def save():
        a.output.write_text(json.dumps(result, indent=2) + '\n')

    try:
        for key in a.workload or WORKLOADS:
            manifest = manifests[WORKLOADS[key]]
            environment = manifest.get('environment', {})
            spec = manifest['apps'][key]
            app = spec.get('app', key)
            status = spec['expected']['status']
            spring.build_go(app)
            variant, hooked = build_variant(spring, app, outdir)
            arms = ['go', 'go-chunked'] + (['go-chunked-close'] if status == 400 else [])
            context = ([] if a.no_flint else ['flint']) + ([] if a.no_java else ['java-jvm'])
            for target in list(context):
                try:
                    {'flint': spring.build_flint, 'java-jvm': spring.build_java}[target](app)
                except (SystemExit, subprocess.CalledProcessError) as exc:
                    result['errors'].append(f'{key} [{target}] did not build: {str(exc)[:300]}')
                    context.remove(target)
            entry = result['workloads'][key] = {'app': app, 'status': status, 'go_variant': {
                'binary': str(variant), 'sha256': load_bench.file_hash(variant), 'hooked_file': hooked,
                'arms': {arm: ARM_ENV[arm] for arm in arms}}, 'exchanges': {}, 'trials': []}
            database_needed = spring.app_row(app).get('database') == 'postgres'

            def arm_args(arm):
                if arm in ARM_ENV:
                    env = dict(environment)
                    env['go'] = {**environment.get('go', {}), **ARM_ENV[arm]}
                    return 'go', (variant if arm != 'go' else None), env
                return arm, None, environment

            import contextlib
            with (spring.postgres_cluster(workload['database_cpus']) if database_needed
                  else contextlib.nullcontext()) as database:
                # 1. Raw exchanges.
                for arm in context + arms:
                    target, binary, env = arm_args(arm)
                    port = spring.free_port()
                    argv, server_env, cwd, identity = load_bench.spring_server(spring, app, target, port, database,
                                                                               workload, env, True, (), binary)
                    log = outdir / f'exchange-{app}-{arm}-server.log'
                    with log.open('wb') as stream:
                        process = subprocess.Popen(argv, cwd=cwd, env=server_env, stdout=stream,
                                                   stderr=subprocess.STDOUT, start_new_session=True)
                        try:
                            url = f"http://127.0.0.1:{port}{spec['path']}"
                            deadline = time.monotonic() + (120 if target == 'java-jvm' else 30)
                            while True:
                                require(process.poll() is None, f'{arm} exited before readiness: {log}')
                                try:
                                    load_bench.spring_verifier(url, spec['expected'])
                                    break
                                except Exception:
                                    require(time.monotonic() < deadline, f'{arm} did not become ready: {log}')
                                    time.sleep(.05)
                            entry['exchanges'][arm] = {'identity': identity, 'runs': [exchange(port, spec)
                                                                                      for _ in range(3)]}
                        finally:
                            load_bench.terminate(process)
                    print(json.dumps({'workload': key, 'exchange': arm,
                                      'framing': entry['exchanges'][arm]['runs'][0]['first']['framing'],
                                      'reused': entry['exchanges'][arm]['runs'][0]['reused']}), flush=True)
                save()
                # 2. Load: the Go arms interleaved (rotating order), then Flint and Java once each.
                schedule = [(trial, arms[trial % len(arms):] + arms[:trial % len(arms)]) for trial in range(trials)]
                schedule.append((trials, context))
                for trial, order in schedule:
                    for arm in order:
                        target, binary, env = arm_args(arm)
                        try:
                            row = load_bench.spring_measure(spring, app, spec, target, workload, oha, trial, outdir,
                                                            env, database, a.smoke, binary=binary, label=arm,
                                                            observer=lambda event, pid: passive_opens())
                        except ValueError as exc:
                            if arm in ARM_ENV:
                                raise
                            result['errors'].append(f'{key} [{arm}] trial {trial}: {exc}')
                            continue
                        row['arm'] = arm
                        row['accepts'] = accepts_per_phase(row)
                        entry['trials'].append(row)
                        print(json.dumps({'workload': key, 'trial': trial, 'arm': arm,
                                          'p99_us': round(row['latency']['p99_ms'] * 1000),
                                          'accepts_per_request': round(row['accepts']['latency']['accepts_per_request'], 4)}),
                              flush=True)
                        save()
            entry['summary'] = summarize(entry['trials'])
            save()
        result['status'] = 'passed'
        save()
        return 0
    except BaseException as exc:
        result['status'] = 'failed'
        result['error'] = str(exc)
        save()
        raise


if __name__ == '__main__':
    sys.exit(main())
