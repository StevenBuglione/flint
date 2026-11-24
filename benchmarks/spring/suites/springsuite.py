"""Black-box acceptance suites for the Spring side-by-side applications (ADR-030 section 8).

A suite is a list of cases run in order against a freshly started implementation. The expected observations are a
golden file recorded from the Java Spring Boot reference (`spring_bench.py record`), so the same suite scores the
Java reference, the Flint port and the Go comparator without a JVM in the loop.

What is compared, for an HTTP case:
- the status code;
- every response header except `Date`, as a multiset of (lower-cased name, value) that keeps the order of repeated
  names (`Vary: Origin`, `Vary: Access-Control-Request-Method`, ...);
- the body: JSON bodies (`application/json`, `*+json`) structurally, with object key order; other bodies as text.

Values that legitimately differ between two runs of the same implementation are named by the case, never guessed:
- `volatile` lists JSON paths whose recorded value is replaced by a matcher (`instant`: an ISO-8601 UTC instant);
- `normalize` lists (regex, replacement) pairs applied to text bodies before comparison;
- the origin (`http://127.0.0.1:<port>`) is recorded as `{origin}`, because ProblemDetail's `type` and actuator links
  embed the request URL.

Wire modes:
- `exact` (the default, and the mode the Flint port must pass): everything above, including the reason phrase,
  message framing (`Content-Length` versus `Transfer-Encoding: chunked`) and compact JSON with Spring's key order.
- `semantic` (the mode Go comparators are registered with): the reason phrase and the framing headers
  (`Content-Length`, `Transfer-Encoding`, `Connection`, `Keep-Alive`) are not compared and JSON key order is free.
  Every other header, the status and the body values are compared exactly. It remains for context comparisons.
- `parity` (the mode Go comparators are registered with, ADR-033 and owner decisions 118b4482 and 081851b0):
  `semantic` plus HTTP parity with the golden, so a comparator does the Java reference's transport work:
  - the reason phrase;
  - the framing: `Transfer-Encoding`, and whether `Content-Length` is present, though not its value, since body
    bytes may differ where `semantic` allows it;
  - the connection lifetime: the `Connection` header, and what the server then does. Each case runs on a raw
    socket, followed by a harmless second request (`PROBE`) on the same socket. A case the golden marks
    `Connection: close` must close; any other case must answer the second request.

A command case (an application that runs to completion, such as gs-relational-data-access) compares the exit code
and the application's own log events, extracted from Spring Boot's default console pattern with the timestamp and
PID removed. Spring Boot's own start-up lines under the application's logger (`Starting ...`, `No active profile
set ...`, `Started ... in N seconds`) are left out, since they carry versions, paths and timings.

The module uses Python's standard library only.
"""
from __future__ import annotations

import http.client
import json
import os
import re
import signal
import socket
import subprocess
import time
from dataclasses import dataclass, field
from urllib.parse import urlsplit

FRAMING = ('content-length', 'transfer-encoding', 'connection', 'keep-alive')
WIRES = ('exact', 'parity', 'semantic')
PROBE = '/flint-parity-probe'  # a path no application maps: the lifetime check's second request changes no state
MATCHERS = {
    # java.time.Instant as Jackson writes it: the fraction trimmed to 0, 3, 6 or 9 digits (ProblemDetail properties).
    'instant': re.compile(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d{1,9})?Z$'),
    # java.util.Date as Jackson's StdDateFormat writes it (Boot's error attributes): always three millisecond digits,
    # so `.000` and `.390` keep their zeros.
    'instant-millis': re.compile(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$'),
}
JSON_TYPE = re.compile(r'^application/([a-z0-9.+-]*\+)?json$')


@dataclass
class Case:
    """One HTTP exchange. `volatile` maps a dotted JSON path (`timestamp`, `errors.0.time`) to a matcher name."""
    name: str
    method: str
    path: str
    headers: dict = field(default_factory=dict)
    body: object = None
    volatile: dict = field(default_factory=dict)
    normalize: list = field(default_factory=list)

    def request_body(self):
        if self.body is None:
            return None
        if isinstance(self.body, (bytes, str)):
            return self.body.encode() if isinstance(self.body, str) else self.body
        return json.dumps(self.body, separators=(',', ':')).encode()


@dataclass
class CommandSuite:
    """An application that runs to completion. `logger` is the abbreviated logger name Boot prints for the app."""
    logger: str
    timeout: float = 60


BOOT_LINE = re.compile(r'^(?P<ts>\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}(?:Z|[+-]\d\d:\d\d))\s+'
                       r'(?P<level>TRACE|DEBUG|INFO|WARN|ERROR) (?P<pid>\d+) --- '
                       r'(?P<rest>(?:\[[^\]]*\] )?\[[^\]]*\] (?P<logger>\S+)\s*: (?P<message>.*))$')
BOOT_STARTUP = ('Starting ', 'No active profile set', 'Started ', 'The following ')


def log_events(text, logger):
    """The application's own log events, as Boot prints them with the timestamp and PID removed."""
    events = []
    for line in text.splitlines():
        match = BOOT_LINE.match(line)
        if not match or match['logger'] != logger or match['message'].startswith(BOOT_STARTUP):
            continue
        events.append(f"{match['level']:>5} --- {match['rest']}")
    return events


# ---------------------------------------------------------------------------------------------------------------
# Observation and golden form


def substitute_origin(value, origin):
    if isinstance(value, str):
        return value.replace(origin, '{origin}')
    if isinstance(value, list):
        return [substitute_origin(item, origin) for item in value]
    if isinstance(value, dict):
        return {key: substitute_origin(item, origin) for key, item in value.items()}
    return value


def apply_volatile(value, path, matcher):
    """Replace the value at a dotted path by {"$match": matcher}; a missing path is a failure of the recording."""
    head, _, rest = path.partition('.')
    key = int(head) if isinstance(value, list) else head
    if isinstance(value, list):
        if not 0 <= key < len(value):
            raise KeyError(path)
    elif not isinstance(value, dict) or key not in value:
        raise KeyError(path)
    if rest:
        value[key] = apply_volatile(value[key], rest, matcher)
    else:
        if not isinstance(value[key], str) or not MATCHERS[matcher].match(value[key]):
            raise ValueError(f'{path}: {value[key]!r} does not match {matcher}')
        value[key] = {'$match': matcher}
    return value


def media_type(headers):
    for name, value in headers:
        if name == 'content-type':
            return value.split(';', 1)[0].strip().lower()
    return ''


def observe(case, status, reason, headers, raw, origin, mask=True):
    """The golden form of one response: what a later run must reproduce. `mask` replaces the case's volatile values
    by their matchers, which recording wants; acceptance keeps the values, and `compare` checks them."""
    headers = [(name.lower(), substitute_origin(value, origin)) for name, value in headers if name.lower() != 'date']
    observed = {'status': status, 'reason': reason, 'headers': headers}
    text = raw.decode('utf-8', errors='replace')
    if raw and JSON_TYPE.match(media_type(headers)):
        parsed = json.loads(text, object_pairs_hook=lambda pairs: dict(pairs))
        observed['compact'] = json.dumps(parsed, separators=(',', ':'), ensure_ascii=False) == text
        parsed = substitute_origin(parsed, origin)
        for path, matcher in (case.volatile.items() if mask else ()):
            parsed = apply_volatile(parsed, path, matcher)
        observed['json'] = parsed
    else:
        text = substitute_origin(text, origin)
        for pattern, replacement in case.normalize:
            text = re.sub(pattern, replacement, text)
        observed['text'] = text
    return observed


# ---------------------------------------------------------------------------------------------------------------
# Comparison


def json_difference(expected, actual, path, ordered):
    if isinstance(expected, dict) and set(expected) == {'$match'}:
        matcher = MATCHERS[expected['$match']]
        if not isinstance(actual, str) or not matcher.match(actual):
            return f'{path or "$"}: {actual!r} is not an {expected["$match"]}'
        return ''
    if type(expected) is not type(actual) and not (isinstance(expected, (int, float)) and isinstance(actual, (int, float))
                                                   and not isinstance(expected, bool) and not isinstance(actual, bool)):
        return f'{path or "$"}: expected {json.dumps(expected)[:200]}, got {json.dumps(actual)[:200]}'
    if isinstance(expected, dict):
        if ordered and list(expected) != list(actual):
            return f'{path or "$"}: keys {list(actual)} differ from {list(expected)} (order included)'
        if set(expected) != set(actual):
            return f'{path or "$"}: keys {sorted(actual)} differ from {sorted(expected)}'
        for key in expected:
            problem = json_difference(expected[key], actual[key], f'{path}.{key}' if path else key, ordered)
            if problem:
                return problem
        return ''
    if isinstance(expected, list):
        if len(expected) != len(actual):
            return f'{path or "$"}: {len(actual)} elements, expected {len(expected)}'
        for index, (left, right) in enumerate(zip(expected, actual)):
            problem = json_difference(left, right, f'{path}.{index}' if path else str(index), ordered)
            if problem:
                return problem
        return ''
    if expected != actual:
        return f'{path or "$"}: expected {json.dumps(expected)}, got {json.dumps(actual)}'
    return ''


def header_multiset(headers, wire):
    if wire == 'parity':
        # Framing as Java does it, not the body's length: the presence of Content-Length, never its value.
        rows = [(name, 'present' if name == 'content-length' else value) for name, value in headers
                if name != 'keep-alive']
    else:
        rows = [(name, value) for name, value in headers if wire == 'exact' or name not in FRAMING]
    grouped = {}
    for name, value in rows:
        grouped.setdefault(name, []).append(value)
    return grouped


def compare(expected, actual, wire):
    """Problems with `actual` against the golden `expected`; an empty list is a pass."""
    problems = []
    if expected['status'] != actual['status']:
        problems.append(f"status {actual['status']}, expected {expected['status']}")
    if wire in ('exact', 'parity') and expected['reason'] != actual['reason']:
        problems.append(f"reason phrase {actual['reason']!r}, expected {expected['reason']!r}")
    want = header_multiset([tuple(row) for row in expected['headers']], wire)
    got = header_multiset([tuple(row) for row in actual['headers']], wire)
    for name in sorted(set(want) | set(got)):
        if want.get(name) != got.get(name):
            problems.append(f'header {name}: {got.get(name)}, expected {want.get(name)}')
    if 'json' in expected:
        if 'json' not in actual:
            problems.append(f"body is not JSON: {actual.get('text', '')[:200]!r}")
        else:
            problem = json_difference(expected['json'], actual['json'], '', wire == 'exact')
            if problem:
                problems.append('body ' + problem)
            if wire == 'exact' and expected['compact'] != actual['compact']:
                problems.append('JSON body whitespace differs from Spring\'s compact output')
    elif expected.get('text') != actual.get('text', json.dumps(actual.get('json'))):
        problems.append(f"body {actual.get('text', actual.get('json'))!r:.300}, expected {expected.get('text')!r:.300}")
    if wire == 'parity':
        want = expected_lifetime(expected)
        if actual.get('lifetime') != want:
            problems.append(f"connection lifetime {actual.get('lifetime')!r}, expected {want!r}")
    return problems


def expected_lifetime(expected):
    """Tomcat's connection lifetime as the golden records it: `close` when it sent `Connection: close`."""
    return 'close' if ['connection', 'close'] in [list(row) for row in expected['headers']] else 'keep'


# ---------------------------------------------------------------------------------------------------------------
# Running an implementation


def exchange(origin, case, timeout=10):
    target = urlsplit(origin)
    connection = http.client.HTTPConnection(target.hostname, target.port, timeout=timeout)
    try:
        headers = {'Accept': '*/*', 'User-Agent': 'flint-spring-suite/1'}
        headers.update(case.headers)
        body = case.request_body()
        if body is not None and 'Content-Type' not in headers:
            headers['Content-Type'] = 'application/json'
        connection.request(case.method, case.path, body=body, headers=headers)
        response = connection.getresponse()
        raw = b'' if case.method == 'HEAD' else response.read()
        return response.status, response.reason, response.getheaders(), raw
    finally:
        connection.close()


def raw_request(origin, method, path, headers, body):
    """The bytes http.client sends for exchange()'s request: Host and Accept-Encoding first, then the headers, then
    Content-Length (0 for a method that expects a body and has none)."""
    target = urlsplit(origin)
    lines = [f'{method} {path} HTTP/1.1', f'Host: {target.hostname}:{target.port}', 'Accept-Encoding: identity']
    lines += [f'{name}: {value}' for name, value in headers.items()]
    if body is not None or method in ('POST', 'PUT', 'PATCH'):
        lines.append(f'Content-Length: {len(body or b"")}')
    return ('\r\n'.join(lines) + '\r\n\r\n').encode('latin-1') + (body or b'')


class _Reader:
    def __init__(self, sock):
        self.sock, self.buffer = sock, b''

    def fill(self):
        data = self.sock.recv(65536)
        if not data:
            raise EOFError('the connection closed')
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

    def rest(self):
        while True:
            try:
                self.fill()
            except EOFError:
                part, self.buffer = self.buffer, b''
                return part


def read_response(reader, method):
    """(status, reason, headers, body) of one HTTP/1.1 response, skipping interim 1xx responses."""
    while True:
        head = reader.until(b'\r\n\r\n').decode('latin-1').split('\r\n')
        parts = head[0].split(' ', 2)
        status = int(parts[1])
        if not 100 <= status < 200:
            break
    reason = parts[2].strip() if len(parts) > 2 else ''
    headers = [(name, value.strip()) for name, _, value in (line.partition(':') for line in head[1:] if line)]
    names = {name.lower(): value for name, value in headers}
    if method == 'HEAD' or status in (204, 304):
        return status, reason, headers, b''
    if names.get('transfer-encoding', '').lower() == 'chunked':
        body = b''
        while True:
            size = int(reader.until(b'\r\n').split(b';')[0], 16)
            if size == 0:
                while reader.until(b'\r\n') != b'\r\n':  # trailers, if any, then the empty line
                    pass
                return status, reason, headers, body
            body += reader.exactly(size + 2)[:-2]
    if 'content-length' in names:
        return status, reason, headers, reader.exactly(int(names['content-length']))
    return status, reason, headers, reader.rest()


def lifetime_exchange(origin, case, timeout=10):
    """exchange() on a raw socket, plus the connection's lifetime: after the response, a second request (PROBE) goes
    on the same socket; `keep` when it is answered, `close` when the server has closed the connection."""
    target = urlsplit(origin)
    headers = {'Accept': '*/*', 'User-Agent': 'flint-spring-suite/1'}
    headers.update(case.headers)
    body = case.request_body()
    if body is not None and 'Content-Type' not in headers:
        headers['Content-Type'] = 'application/json'
    with socket.create_connection((target.hostname, target.port), timeout=timeout) as sock:
        sock.sendall(raw_request(origin, case.method, case.path, headers, body))
        reader = _Reader(sock)
        status, reason, response_headers, raw = read_response(reader, case.method)
        try:
            sock.sendall(raw_request(origin, 'GET', PROBE, {'Accept': '*/*', 'User-Agent': 'flint-spring-suite/1'},
                                     None))
            read_response(reader, 'GET')
            lifetime = 'keep'
        except (EOFError, ConnectionResetError, BrokenPipeError):
            lifetime = 'close'
    return status, reason, response_headers, raw, lifetime


def wait_for_port(origin, process, deadline, log_path):
    """Readiness is a TCP accept: an HTTP probe would change state (gs-rest-service counts requests)."""
    target = urlsplit(origin)
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f'the implementation exited with {process.returncode} before listening; see {log_path}')
        try:
            socket.create_connection((target.hostname, target.port), timeout=.2).close()
            return
        except OSError:
            time.sleep(.05)
    raise RuntimeError(f'the implementation did not listen on {origin} in time; see {log_path}')


def port_free(origin):
    target = urlsplit(origin)
    try:
        socket.create_connection((target.hostname, target.port), timeout=.2).close()
    except OSError:
        return True
    return False


def stop(process):
    if process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=5)


def run_http(cases, origin, command, env, cwd, log_path, startup_timeout=90, mask=True, lifetime=False):
    """Start `command`, run every case in order, stop it. Returns [(case, observation)]. `lifetime` (wire `parity`)
    runs each case through lifetime_exchange and records the connection's lifetime in the observation."""
    if not port_free(origin):
        raise RuntimeError(f'{origin} is already in use; stop whatever listens there first')
    with open(log_path, 'wb') as log:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            started = time.monotonic()
            wait_for_port(origin, process, started + startup_timeout, log_path)
            results = []
            for case in cases:
                if lifetime:
                    status, reason, headers, raw, kept = lifetime_exchange(origin, case)
                    observation = observe(case, status, reason, headers, raw, origin, mask)
                    observation['lifetime'] = kept
                else:
                    status, reason, headers, raw = exchange(origin, case)
                    observation = observe(case, status, reason, headers, raw, origin, mask)
                results.append((case, observation))
            return results, time.monotonic() - started
        finally:
            stop(process)


def run_command(suite, command, env, cwd, log_path):
    with open(log_path, 'wb') as log:
        started = time.monotonic()
        try:
            completed = subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT,
                                       timeout=suite.timeout, start_new_session=True)
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(f'the implementation did not exit within {suite.timeout} s; see {log_path}') from exc
    text = open(log_path, encoding='utf-8', errors='replace').read()
    return {'exit_code': completed.returncode, 'events': log_events(text, suite.logger)}, time.monotonic() - started


def compare_command(expected, actual):
    problems = []
    if expected['exit_code'] != actual['exit_code']:
        problems.append(f"exit code {actual['exit_code']}, expected {expected['exit_code']}")
    want, got = expected['events'], actual['events']
    for index in range(max(len(want), len(got))):
        left = want[index] if index < len(want) else '<none>'
        right = got[index] if index < len(got) else '<none>'
        if left != right:
            problems.append(f'log event {index}: {right!r}, expected {left!r}')
    return problems
