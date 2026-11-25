#!/usr/bin/env python3
"""Byte identity of gs-rest-service's error responses with the default-JSON-404 specialization on and off.

The specialization (Astra error-paths action 3; engine hook `ErrorPageShortcut`, flint.engine.servlet) writes Boot's
default JSON 404 without the /error dispatch, only while startup proves that dispatch stock and the request qualifies.
It must change no byte a client can see. This tool checks that with the requests of
benchmarks/spring/suites/gs_rest_service_errors.py:

    spring_error_identity.py record [--java-cache DIR]
        Run the Java reference twice per run and record golden/gs-rest-service-errors.json (the runs must agree).
    spring_error_identity.py check --on BIN --off BIN [--installed REGEX]
        Run both Flint builds. Each must match the golden exactly (status, reason, headers but Date, body, framing,
        compact JSON, and connection lifetime). Then the two must be identical byte for byte, with the Date value and
        the digits of the timestamp masked. `--installed` names a log line the on build must print, so a build that
        never installed the specialization cannot pass as identical.
    spring_error_identity.py check --binary BIN
        One build against the golden only.

Every process it starts is stopped before it returns, on success or failure. It uses no load, so it needs no
measurement hold. Python's standard library only.
"""
from __future__ import annotations

import argparse
import json
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

import spring_bench  # noqa: E402  (puts the suites directory on sys.path)
import springsuite  # noqa: E402
import gs_rest_service_errors as suite  # noqa: E402

APP = 'gs-rest-service'
GOLDEN = spring_bench.GOLDEN / 'gs-rest-service-errors.json'
SCHEMA = 'flint.spring-error-identity/1'
WHITELABEL = [(r"<div id='created'>[^<]*</div>", "<div id='created'>*</div>")]
DATE_FIELD = re.compile(rb'(?im)^(date:[ \t]*)([^\r\n]*)')
TIMESTAMP = re.compile(rb'("timestamp":")([^"]*)(")')
CREATED = re.compile(rb"(<div id='created'>)([^<]*)(</div>)")
DIGIT = re.compile(rb'[0-9]')


class _Recorder(springsuite._Reader):
    """A reader that keeps every byte it receives, so the response's exact wire form can be compared."""

    def __init__(self, sock):
        super().__init__(sock)
        self.received = b''

    def fill(self):
        before = len(self.buffer)
        super().fill()
        self.received += self.buffer[before:]


def request_bytes(origin, request):
    """The request exactly as the case writes it: `Host` first, then its fields in order, then `Content-Length` for
    a body unless the case gave one."""
    host = origin.split('://', 1)[1]
    lines = [f'{request.method} {request.target} HTTP/1.1', f'Host: {host}']
    lines += [f'{name}: {value}' for name, value in request.fields]
    if request.body and not any(name.lower() == 'content-length' for name, _ in request.fields):
        lines.append(f'Content-Length: {len(request.body)}')
    return ('\r\n'.join(lines) + '\r\n\r\n').encode('utf-8') + request.body


def exchange(origin, request, timeout=10):
    """(status, reason, headers, body, wire, lifetime): `wire` is every byte of the response, `lifetime` whether a
    probe on the same socket was answered (`keep`) or the server closed it (`close`)."""
    host, port = origin.split('://', 1)[1].rsplit(':', 1)
    with socket.create_connection((host, int(port)), timeout=timeout) as sock:
        sock.sendall(request_bytes(origin, request))
        reader = _Recorder(sock)
        status, reason, headers, body = springsuite.read_response(reader, request.method)
        wire = reader.received[:len(reader.received) - len(reader.buffer)]
        try:
            probe = springsuite.Case('probe', 'GET', springsuite.PROBE)
            sock.sendall(springsuite.raw_request(origin, 'GET', probe.path, {'Accept': '*/*'}, None))
            springsuite.read_response(reader, 'GET')
            lifetime = 'keep'
        except (EOFError, ConnectionResetError, BrokenPipeError):
            lifetime = 'close'
    return status, reason, headers, body, wire, lifetime


def observation(request, status, reason, headers, body, lifetime, origin, mask):
    """The golden form of one response (springsuite.observe), with Boot's timestamp named volatile when present."""
    volatile = {}
    if body.startswith(b'{"timestamp":'):
        volatile = {'timestamp': 'instant-millis'}
    case = springsuite.Case(request.name, request.method, request.target, volatile=volatile, normalize=WHITELABEL)
    observed = springsuite.observe(case, status, reason, headers, body, origin, mask)
    observed['lifetime'] = lifetime
    return observed


def masked(wire):
    """The response bytes with the clock removed: the `Date` value and the digits of Boot's timestamp (JSON or the
    Whitelabel page) become zeros, keeping every length, so framing and chunk sizes are still compared."""
    wire = DATE_FIELD.sub(lambda m: m.group(1) + b'0' * len(m.group(2)), wire)
    for pattern in (TIMESTAMP, CREATED):
        wire = pattern.sub(lambda m: m.group(1) + DIGIT.sub(b'0', m.group(2)) + m.group(3), wire)
    return wire


def run(command, env, cwd, origin, requests, log_path, mask):
    """Start one implementation, send `requests` in order, stop it. [(observation, wire)]."""
    if not springsuite.port_free(origin):
        raise SystemExit(f'{origin} is already in use')
    with open(log_path, 'wb') as log:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            springsuite.wait_for_port(origin, process, time.monotonic() + 90, log_path)
            results = []
            for request in requests:
                status, reason, headers, body, wire, lifetime = exchange(origin, request)
                results.append((observation(request, status, reason, headers, body, lifetime, origin, mask), wire))
            return results
        finally:
            springsuite.stop(process)


def launch(implementation, args, binary=None):
    port = spring_bench.free_port()
    command, env, cwd = spring_bench.launch(APP, implementation, port, extra_args=args, binary=binary)
    return command, env, cwd, f'http://127.0.0.1:{port}'


def logs():
    directory = spring_bench.BUILD / 'logs'
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def slug(text):
    return re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')


def record(java_cache):
    if java_cache:
        spring_bench.CACHE = Path(java_cache)
    runs = []
    for entry in suite.RUNS:
        observed = []
        for attempt in (1, 2):
            command, env, cwd, origin = launch('java', entry.args('java'))
            log_path = logs() / f'{APP}-errors-java-{slug(entry.label)}-{attempt}.log'
            observed.append([row for row, _ in run(command, env, cwd, origin, entry.requests, log_path, True)])
        if observed[0] != observed[1]:
            differing = [request.name for request, left, right in zip(entry.requests, *observed) if left != right]
            raise SystemExit(f'{entry.label}: two runs of the Java reference differ in {differing}')
        runs.append({'label': entry.label, 'properties': entry.properties,
                     'observations': [{'name': request.name, 'request': {'method': request.method,
                                                                         'target': request.target,
                                                                         'fields': request.fields},
                                       'response': response}
                                      for request, response in zip(entry.requests, observed[0])]})
    row = spring_bench.app_row(APP)
    golden = {'schema': SCHEMA, 'app': APP,
              'reference': {'repo': row['upstream']['repo'], 'commit': row['upstream']['commit'],
                            'spring_boot': spring_bench.registry()['spring_boot']},
              'runs': runs}
    GOLDEN.write_text(json.dumps(golden, indent=1, ensure_ascii=False) + '\n')
    count = sum(len(entry['observations']) for entry in runs)
    print(f'recorded {count} responses in {len(runs)} runs into {GOLDEN.relative_to(spring_bench.ROOT)}')


def golden_problems(golden_run, results):
    """(problems, known): differences from the golden, with those suite.KNOWN names set apart. A known case that
    now matches is a problem, so the list cannot outlive its divergence."""
    problems, known = [], []
    for expected, (actual, _) in zip(golden_run['observations'], results):
        found = springsuite.compare(expected['response'], actual, 'exact')
        if actual['lifetime'] != expected['response']['lifetime']:
            found.append(f"connection lifetime {actual['lifetime']}, expected {expected['response']['lifetime']}")
        label = f"{golden_run['label']} / {expected['name']}"
        reason = suite.KNOWN.get((golden_run['label'], expected['name']))
        if reason and found:
            known.append(f'{label}: {reason}')
        elif reason:
            problems.append(f'{label}: listed in KNOWN but matches the golden now; remove it from KNOWN')
        else:
            problems += [f'{label}: {problem}' for problem in found]
    return problems, known


def check(binaries, installed):
    binaries = {arm: str(Path(binary).resolve()) for arm, binary in binaries.items()}  # each runs from its app's directory
    golden = json.loads(GOLDEN.read_text())
    if golden.get('schema') != SCHEMA:
        raise SystemExit(f'{GOLDEN}: not a {SCHEMA} file')
    labels = [entry.label for entry in suite.RUNS]
    if [entry['label'] for entry in golden['runs']] != labels:
        raise SystemExit(f'{GOLDEN} is stale against gs_rest_service_errors.py; record it again')
    problems, known, compared = [], [], 0
    for entry, golden_run in zip(suite.RUNS, golden['runs']):
        if [row['name'] for row in golden_run['observations']] != [request.name for request in entry.requests]:
            raise SystemExit(f'{GOLDEN}: run {entry.label!r} is stale; record it again')
        wires = {}
        for arm, binary in binaries.items():
            command, env, cwd, origin = launch('flint', entry.args('flint'), binary)
            log_path = logs() / f'{APP}-errors-{arm}-{slug(entry.label)}.log'
            results = run(command, env, cwd, origin, entry.requests, log_path, False)
            found, divergent = golden_problems(golden_run, results)
            problems += [f'{arm}: {problem}' for problem in found]
            known += [f'{arm}: {problem}' for problem in divergent]
            wires[arm] = [masked(wire) for _, wire in results]
            if arm == 'on' and installed and entry.label == 'default':
                if not re.search(installed, Path(log_path).read_text(errors='replace')):
                    problems.append(f'on: {entry.label}: the log has no line matching {installed!r}; '
                                    'the specialization was not installed')
        if set(wires) == {'on', 'off'}:
            for request, on, off in zip(entry.requests, wires['on'], wires['off']):
                compared += 1
                if on != off:
                    problems.append(f'{entry.label} / {request.name}: bytes differ\n  off: {off!r:.600}\n'
                                    f'  on:  {on!r:.600}')
    total = sum(len(entry.requests) for entry in suite.RUNS)
    for line in known:
        print(f'known: {line}')
    for problem in problems:
        print(problem)
    arms = ' and '.join(binaries)
    print(f'{total} responses in {len(suite.RUNS)} runs: {arms} against the golden, '
          f'{compared} compared byte for byte; {len(known)} known divergences, {len(problems)} problems')
    return 1 if problems else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n', 1)[0])
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('record')
    p.add_argument('--java-cache', help="the spring_bench cache holding the built Java reference "
                                        "(default: this checkout's .flint/spring)")
    p = sub.add_parser('check')
    p.add_argument('--on', help='the build with the specialization')
    p.add_argument('--off', help='the build without it (FLINT_AOT_FAST_PATH=0)')
    p.add_argument('--binary', help='one build, against the golden only')
    p.add_argument('--installed', help="a regex the on build's log must match")
    args = parser.parse_args(argv)
    if args.command == 'record':
        record(args.java_cache)
        return 0
    if args.binary and not (args.on or args.off):
        return check({'build': args.binary}, None)
    if not (args.on and args.off):
        parser.error('check needs --on and --off, or --binary')
    return check({'off': args.off, 'on': args.on}, args.installed)


if __name__ == '__main__':
    sys.exit(main())
