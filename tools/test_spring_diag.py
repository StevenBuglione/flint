"""Unit tests of the owner-1 diagnostic's measurement helpers: `python3 tools/test_spring_diag.py`."""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import spring_diag


class Counters(unittest.TestCase):
    def test_counters_written_at_exit(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'counters.json'
            self.assertIsNone(spring_diag.read_counters(path))
            path.write_text(json.dumps({'schema': 'flint.diag-counters/1',
                                        'timers': {'sql.lease_wait': {'count': 4, 'sum_ns': 400, 'max_ns': 300},
                                                   'sql.handoff': {'count': 0, 'sum_ns': 0, 'max_ns': 0}},
                                        'gauges': {'sql.max_queue_depth': 9}}))
            row = spring_diag.read_counters(path)
            self.assertEqual(row['timers']['sql.lease_wait']['mean_ns'], 100.0)
            self.assertIsNone(row['timers']['sql.handoff']['mean_ns'])
            self.assertEqual(row['gauges'], {'sql.max_queue_depth': 9})


class Census(unittest.TestCase):
    def test_statement_log_counts(self):
        log = '\n'.join([
            '2026-11-24 03:40:00.001 UTC [11] db=petclinic1 LOG:  connection authorized: user=petclinic database=petclinic1',
            '2026-11-24 03:40:00.002 UTC [11] db=petclinic1 LOG:  duration: 0.030 ms  parse <unnamed>: BEGIN READ ONLY',
            '2026-11-24 03:40:00.003 UTC [11] db=petclinic1 LOG:  duration: 0.010 ms  bind <unnamed>: BEGIN READ ONLY',
            '2026-11-24 03:40:00.004 UTC [11] db=petclinic1 LOG:  duration: 0.010 ms  execute <unnamed>: BEGIN READ ONLY',
            '2026-11-24 03:40:00.005 UTC [11] db=petclinic1 LOG:  duration: 0.050 ms  parse S_1: SELECT * FROM owners WHERE id = $1',
            '2026-11-24 03:40:00.006 UTC [11] db=petclinic1 LOG:  duration: 0.020 ms  execute S_1: SELECT * FROM owners WHERE id = $1',
            '2026-11-24 03:40:00.007 UTC [11] db=petclinic1 LOG:  duration: 0.020 ms  statement: COMMIT',
            '2026-11-24 03:40:00.008 UTC [12] db=petclinic2 LOG:  duration: 0.020 ms  statement: SELECT 1',
            '\tcontinuation of a multi-line statement'])
        counts, kinds, texts = spring_diag.parse_census(log, 'petclinic1')
        self.assertEqual(counts, {'parse': 2, 'parse_unnamed': 1, 'bind': 1, 'execute': 2, 'simple': 1, 'connections': 1})
        self.assertEqual(kinds, {'begin': 1, 'select': 1, 'commit': 1})
        self.assertEqual(texts['SELECT * FROM owners WHERE id = $1'], 1)


class Perf(unittest.TestCase):
    def test_counts_and_refusals(self):
        class Fake:
            def communicate(self, timeout=None):
                return '', ('2000000,,instructions:u,100,100.00,,\n1000000,,cycles:u,100,100.00,,\n'
                            '<not supported>,,instructions:k,0,100.00,,\n<not counted>,,cycles:k,0,0.00,,\n'
                            '500,,context-switches,100,100.00,,\n')
        out = spring_diag.perf_finish(Fake(), 1000)
        self.assertEqual(out['per_request'], {'instructions:u': 2000.0, 'cycles:u': 1000.0, 'context-switches': 0.5})
        self.assertEqual(out['unavailable'], ['instructions:k', 'cycles:k'])
        self.assertFalse(spring_diag.perf_finish(None, 1000)['available'])

    def test_refused_above_level_two(self):
        with mock.patch.object(spring_diag, 'perf_level', return_value=4):
            self.assertIsNone(spring_diag.perf_start(os.getpid(), 1))


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
