"""Flint Boot's graceful SIGTERM and SIGINT (ADR-028, "Graceful SIGTERM and SIGINT in Flint Boot"): a Boot app closes
its context on the first signal (the web server drains, the beans are destroyed) and returns from main with 0, so
druntime finishes and prints its GC report, which phase1-gc-matrix reads."""
import os
import signal
import socket
import subprocess
import sys
import time
import unittest
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(os.environ.get('FLINT_ROOT') or Path(__file__).resolve().parents[2]) / 'tests'))
from flint_testing import FLINT_ROOT  # noqa: E402
from test_flint_cli import FLINT, environment, setUpModule  # noqa: E402,F401

APP = FLINT_ROOT / 'benchmarks' / 'spring' / 'flint' / 'gs-rest-service'
BINARY = APP / '.flint' / 'build' / 'dev' / 'gs-rest-service'
# The servlet engine's HTTP parser is the pinned llhttp; a checkout that does not link it cannot serve at all.
NO_PARSER = 'pinned llhttp provider is unavailable'


def free_port():
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


@unittest.skipIf(sys.platform == 'win32', 'POSIX signals; Windows delivers Ctrl+Break through the same hook')
class GracefulShutdownTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        built = subprocess.run([str(FLINT), 'build', '--json'], cwd=APP, capture_output=True, text=True,
                               env=environment())
        if built.returncode != 0:
            raise AssertionError(built.stdout[-3000:] + built.stderr[-2000:])

    def stop_with(self, number):
        port = free_port()
        process = subprocess.Popen([str(BINARY), f'--server.port={port}', '--DRT-gcopt=profile:1'], cwd=APP,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            body = None
            for _ in range(200):
                if process.poll() is not None:
                    break
                try:
                    with urllib.request.urlopen(f'http://127.0.0.1:{port}/greeting?name=Ada', timeout=2) as r:
                        body = r.read().decode()
                        break
                except OSError:
                    time.sleep(0.05)
            if process.poll() is not None:
                output = process.stdout.read()
                if NO_PARSER in output:
                    self.skipTest('this checkout does not link the pinned llhttp provider, so the server cannot '
                                  'start (engine-web native block); a skip, not a pass')
                self.fail(output[-3000:])
            self.assertEqual(body, '{"id":1,"content":"Hello, Ada!"}')
            process.send_signal(number)
            output, _ = process.communicate(timeout=40)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        return process.returncode, output

    def test_sigterm_closes_the_context_and_exits_0(self):
        code, output = self.stop_with(signal.SIGTERM)
        self.assertEqual(code, 0, output[-3000:])
        # main returned through druntime: its GC profile (--DRT-gcopt=profile:1) is printed at exit.
        self.assertIn('Number of collections', output)

    def test_sigint_closes_the_context_and_exits_0(self):
        code, output = self.stop_with(signal.SIGINT)
        self.assertEqual(code, 0, output[-3000:])
        self.assertIn('Number of collections', output)


if __name__ == '__main__':
    unittest.main()
