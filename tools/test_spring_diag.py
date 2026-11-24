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


class Smaps(unittest.TestCase):
    def test_pools_bucket_by_size(self):
        import smaps_census
        text = '\n'.join([
            '7f0000000000-7f0000100000 rw-p 00000000 00:00 0 ', 'Rss:                1024 kB', 'Anonymous:          1024 kB',
            '7f0000100000-7f0000500000 rw-p 00000000 00:00 0 ', 'Rss:                3000 kB', 'Anonymous:          3000 kB',
            '7f0000500000-7f0000900000 rw-p 00000000 00:00 0 ', 'Rss:                 100 kB', 'Anonymous:           100 kB',
            '55d000000000-55d000021000 rw-p 00000000 00:00 0                          [heap]', 'Rss:                 132 kB',
            '7f1000000000-7f1000200000 r-xp 00000000 08:01 42                         /usr/lib/libc.so.6', 'Rss:                 900 kB'])
        out = smaps_census.summarize(smaps_census.parse(text))
        self.assertEqual(out['totals_kb']['Rss'], 1024 + 3000 + 100 + 132 + 900)
        self.assertEqual(out['anon_by_size_kb']['4096'], {'mappings': 2, 'Rss': 3100, 'Anonymous': 3100})
        self.assertEqual(out['anon_by_size_kb']['1024']['Rss'], 1024)
        self.assertEqual(list(out['largest_kb'])[0], '[anon]')


class Syscalls(unittest.TestCase):
    def test_strace_log_counts_inside_the_window(self):
        text = '\n'.join([
            '101 1000.000100 write(2, "starting", 8) = 8',
            '102 1010.000100 epoll_pwait(5, [], 64, 10, NULL, 8) = 1',
            '102 1010.000200 sendto(7, "HTTP/1.1 200", 120, MSG_NOSIGNAL, NULL, 0 <unfinished ...>',
            '103 1010.000250 futex(0x7f, FUTEX_WAKE_PRIVATE, 1) = 0',
            '102 1010.000300 <... sendto resumed>) = 120',
            '102 1010.000400 sendto(7, "{}", 2, MSG_NOSIGNAL, NULL, 0) = 2',
            '101 1020.000100 write(2, "stopping", 8) = 8'])
        self.assertEqual(spring_diag.parse_strace_log(text, 1005, 1015), {'epoll_pwait': 1, 'sendto': 2, 'futex': 1})
        out = spring_diag.syscall_census.__wrapped__ if hasattr(spring_diag.syscall_census, '__wrapped__') else None
        self.assertIsNone(out)


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
