"""Unit tests of the comparator baseline and its drift guard: `python3 tools/test_spring_baseline.py`."""
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import spring_baseline
import spring_bench


def record(**over):
    calibration = {m: [100.0, 101.0, 99.0, 100.5, 99.5] for m in spring_baseline.CALIBRATION_METRICS}
    probes = {'cpu_seconds': [0.10, 0.101, 0.099, 0.1, 0.1005], 'memory_seconds': [0.05, 0.051, 0.049, 0.05, 0.0505]}
    base = {'calibration': {'samples': calibration, 'bands': {m: spring_baseline.band(v) for m, v in calibration.items()}},
            'probe': {'samples': probes, 'bands': {m: spring_baseline.band(v) for m, v in probes.items()}}}
    base.update(over)
    return base


class Bands(unittest.TestCase):
    def test_prediction_band_widens_with_spread_and_small_n(self):
        b = spring_baseline.band([10.0, 10.0, 10.0, 10.0, 10.0])
        self.assertEqual((b['lower'], b['upper']), (10.0, 10.0))
        narrow = spring_baseline.band([10, 10.1, 9.9, 10, 10.05, 9.95, 10, 10.02, 9.98])
        wide = spring_baseline.band([10, 10.1, 9.9])
        self.assertLess(narrow['upper'] - narrow['lower'], wide['upper'] - wide['lower'])
        with self.assertRaises(ValueError):
            spring_baseline.band([1.0])

    def test_drift_flags_only_out_of_band_metrics(self):
        r = record()
        ok = {m: 100.0 for m in spring_baseline.CALIBRATION_METRICS}
        self.assertEqual(spring_baseline.drift(r, ok, {'cpu_seconds': [0.1] * 5, 'memory_seconds': [0.05] * 5}), [])
        slow = dict(ok, requests_per_second=80.0)
        found = spring_baseline.drift(r, slow, {'cpu_seconds': [0.2] * 5, 'memory_seconds': [0.05] * 5})
        self.assertEqual(len(found), 2)
        self.assertTrue(found[0].startswith('calibration requests_per_second'))
        self.assertTrue(found[1].startswith('probe cpu_seconds'))


class Fingerprint(unittest.TestCase):
    def test_stale_names_the_changed_inputs(self):
        now = spring_baseline.fingerprint('gs-rest-service', 'go', ['http'])
        self.assertEqual(spring_baseline.stale({'fingerprint': now}), [])
        old = dict(now, kernel='5.0.0', comparator_sha256='0' * 64)
        self.assertEqual(spring_baseline.stale({'fingerprint': old}), ['comparator_sha256', 'kernel'])

    def test_workloads_of_an_app(self):
        keys = spring_baseline.workload_keys('gs-rest-service', {'http', 'error'})
        self.assertIn(('http', 'gs-rest-service'), keys)
        self.assertIn(('error', 'gs-rest-service:not-found'), keys)
        self.assertNotIn(('error', 'petclinic-rest:validation-error'), keys)


class Probe(unittest.TestCase):
    def test_probe_samples_both_tasks(self):
        out = spring_baseline.probe(sorted(os.sched_getaffinity(0))[:1], samples=2)
        self.assertEqual(len(out['cpu_seconds']), 2)
        self.assertTrue(all(v > 0 for v in out['memory_seconds']))


class Assembly(unittest.TestCase):
    def test_runtime_parts_must_share_one_comparator_side(self):
        def http(sha):
            rec = {'mode': 'production', 'status': 'passed', 'effective_workload': {'runs': 9},
                   'apps': {'gs-rest-service': {'app': 'gs-rest-service'}}}
            if sha:
                rec['baseline'] = {'sha256': sha, 'record': '/nonexistent/record.json'}
            return {'entry': 'e', 'file': 'http.json', 'family': 'http', 'record': rec, 'commits': {'a' * 40}}
        runs = {'http': 9, 'gc': 9, 'error': 9}
        with mock.patch('spring_baseline.stale', return_value=[]), mock.patch('spring_baseline.load', return_value={}):
            self.assertEqual(spring_bench.consistency_problems([http('x' * 64), http('x' * 64)], runs), [])
            problems = spring_bench.consistency_problems([http('x' * 64), http(None)], runs)
            self.assertTrue(any('different comparator sides' in p for p in problems))
        with mock.patch('spring_baseline.stale', return_value=['kernel']), mock.patch('spring_baseline.load', return_value={}):
            problems = spring_bench.consistency_problems([http('y' * 64)], runs)
            self.assertTrue(any('stale: kernel' in p for p in problems))


if __name__ == '__main__':
    unittest.main()
