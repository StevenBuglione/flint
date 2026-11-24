"""Unit tests of the owner-1 diagnostic's measurement helpers: `python3 tools/test_spring_diag.py`."""
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import spring_diag


class Counters(unittest.TestCase):
    def test_deltas_of_cumulative_counters(self):
        before = {'timers': {'sql.lease_wait': {'count': 10, 'sum_ns': 1000, 'max_ns': 300}},
                  'workers': {'0': {'requests': 5}, '1': {'requests': 7}}}
        after = {'timers': {'sql.lease_wait': {'count': 30, 'sum_ns': 5000, 'max_ns': 900},
                            'sql.map': {'count': 4, 'sum_ns': 400, 'max_ns': 150}},
                 'gauges': {'sql.max_queue_depth': 9}, 'workers': {'0': {'requests': 25}, '1': {'requests': 7}}}
        delta = spring_diag.counter_delta(before, after)
        self.assertEqual(delta['timers']['sql.lease_wait'], {'count': 20, 'sum_ns': 4000, 'mean_ns': 200.0,
                                                             'max_ns_since_start': 900})
        self.assertEqual(delta['timers']['sql.map']['mean_ns'], 100.0)
        self.assertEqual(delta['workers'], {'0': 20, '1': 0})
        self.assertEqual(delta['gauges'], {'sql.max_queue_depth': 9})
        self.assertIsNone(spring_diag.counter_delta(None, after))

    def test_snapshot_waits_for_the_rewritten_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'counters.json'
            # A stand-in server: rewrites the file (temp + rename) on SIGUSR2.
            script = ('import json, os, signal, sys, time\n'
                      'p = sys.argv[1]; n = [0]\n'
                      'def dump(*_):\n'
                      '    n[0] += 1; open(p + ".tmp", "w").write(json.dumps({"timers": {"x": {"count": n[0], "sum_ns": 1}}}))\n'
                      '    os.rename(p + ".tmp", p)\n'
                      'signal.signal(signal.SIGUSR2, dump)\n'
                      'print("ready", flush=True)\n'
                      'while True: time.sleep(0.01)\n')
            server = subprocess.Popen([sys.executable, '-c', script, str(path)], stdout=subprocess.PIPE, text=True)
            try:
                server.stdout.readline()
                self.assertEqual(spring_diag.snapshot_counters(server.pid, path)['timers']['x']['count'], 1)
                self.assertEqual(spring_diag.snapshot_counters(server.pid, path)['timers']['x']['count'], 2)
            finally:
                server.kill()
                server.wait()


class Cpu(unittest.TestCase):
    def test_thread_and_process_cpu(self):
        threads = spring_diag.thread_cpu(os.getpid())
        self.assertIn(os.getpid(), threads)
        self.assertGreaterEqual(spring_diag.process_cpu(os.getpid()), 0.0)
        self.assertEqual(spring_diag.process_cpu(2 ** 22 + 12345), 0.0)

    def test_refuses_during_a_timed_measurement(self):
        with tempfile.TemporaryDirectory() as temporary:
            lock = Path(temporary) / 'MEASURING'
            lock.write_text('{}')
            with mock.patch.object(spring_diag, 'LOCK', lock), mock.patch.dict(os.environ, {}, clear=False):
                os.environ.pop('FLINT_MEASURE_WINDOW_CERTIFIED', None)
                with self.assertRaisesRegex(SystemExit, 'would void it'):
                    spring_diag.main(['--output', str(Path(temporary) / 'x.json')])


if __name__ == '__main__':
    unittest.main()
