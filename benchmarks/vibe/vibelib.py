"""Shared pieces of the vibe-coding benchmark's acceptance tests (ADR-021 section 11, ADR-027 section 6).

An acceptance test is black-box: it runs the built program the way the task statement says and checks what it
observes, so the same test scores a Flint, Go or Spring Boot solution. Each task's `acceptance.py` defines
`checks(program)` returning a list of `Check`s. Python's standard library only.
"""
import json
import os
import re
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Program:
    """How to start the solution: `argv` prefix (the executable, or `java -jar app.jar`) and its environment."""
    argv: list
    env: dict = field(default_factory=dict)

    def command(self, *arguments):
        return [*self.argv, *map(str, arguments)]

    def environment(self, **extra):
        env = {k: v for k, v in os.environ.items() if not k.startswith(('FLINT_', 'DFLAGS'))}
        env.update(self.env)
        env.update({k: str(v) for k, v in extra.items()})
        return env


@dataclass
class Check:
    name: str
    passed: bool
    detail: str = ''


class Recorder:
    """Collects checks; a failed expectation records the failure instead of stopping the run."""

    def __init__(self):
        self.results = []

    def check(self, name, condition, detail=''):
        self.results.append(Check(name, bool(condition), '' if condition else str(detail)[:2000]))
        return bool(condition)

    def equal(self, name, actual, expected):
        return self.check(name, actual == expected, f'expected {expected!r}, got {actual!r}')

    def crashed(self, name, error):
        self.results.append(Check(name, False, f'{type(error).__name__}: {error}'[:2000]))


def free_port():
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def wait_for_port(port, process, timeout=30.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            return False
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.5):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def http(port, method, path, body=None, token=None, raw=None, timeout=10.0):
    """One request; returns (status, parsed JSON or None, raw text)."""
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    request = urllib.request.Request(f'http://127.0.0.1:{port}{path}', data=data, method=method)
    if data is not None:
        request.add_header('Content-Type', 'application/json')
    if token:
        request.add_header('Authorization', 'Bearer ' + token)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status, text = response.status, response.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as error:
        status, text = error.code, error.read().decode('utf-8', 'replace')
    try:
        parsed = json.loads(text) if text.strip() else None
    except ValueError:
        parsed = None
    return status, parsed, text


def stop(process, timeout=10.0):
    """SIGTERM, then SIGKILL; returns (exit code, seconds to exit after SIGTERM)."""
    if process.poll() is not None:
        return process.returncode, 0.0
    started = time.monotonic()
    process.send_signal(signal.SIGTERM)
    try:
        process.wait(timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    return process.returncode, time.monotonic() - started


ANSI = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]|\x1b[()][0-9A-Za-z]|\x1b[=>78DEHMNOZc]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)')


def visible_text(output):
    """Terminal output without escape sequences, for presence checks. A cursor movement becomes a line break, so
    text drawn at different places never runs together."""
    return ANSI.sub(lambda match: '\n' if match.group(0)[-1] in 'HfABCDEFGd' else '', output)


def write_atomically(path, text):
    path = Path(path)
    temporary = path.with_name('.' + path.name + '.tmp')
    temporary.write_text(text)
    os.replace(temporary, path)
