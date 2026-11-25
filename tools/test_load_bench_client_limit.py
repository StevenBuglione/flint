#!/usr/bin/env python3
"""The client-limit rule (owner decision ae7858f8): `python3 tools/test_load_bench_client_limit.py`."""
import os
import subprocess
import sys
import unittest
from pathlib import Path

import load_bench


def phases(latency, capacity):
    return {'latency': {'load_cpu_fraction': latency}, 'capacity': {'load_cpu_fraction': capacity}}


class ClientLimit(unittest.TestCase):
    def test_a_saturated_capacity_phase_is_context_on_the_error_paths(self):
        p = phases(0.40, 0.93)
        load_bench.client_limit(p, capacity_context=True)
        self.assertEqual(p['capacity']['client_limited'], 'client-limited, context (owner decision ae7858f8)')

    def test_a_saturated_fixed_rate_phase_is_still_refused(self):
        with self.assertRaises(ValueError) as caught:
            load_bench.client_limit(phases(0.90, 0.40), capacity_context=True)
        self.assertIn('fixed-rate phase', str(caught.exception))

    def test_other_workloads_refuse_either_phase(self):
        with self.assertRaises(ValueError):
            load_bench.client_limit(phases(0.40, 0.93))
        quiet = phases(0.40, 0.80)
        load_bench.client_limit(quiet)
        self.assertNotIn('client_limited', quiet['capacity'])

    def test_only_the_error_paths_manifest_makes_capacity_context(self):
        self.assertEqual(load_bench.ERROR_PATHS_MANIFEST, 'spring-error-paths-benchmark.json')

    def test_the_bench_root_can_point_at_another_checkout(self):
        here = Path(__file__).resolve().parent
        out = subprocess.run([sys.executable, '-c', 'import load_bench; print(load_bench.ROOT)'], cwd=here,
                             env=dict(os.environ, FLINT_BENCH_ROOT='/tmp'), capture_output=True, text=True, check=True)
        self.assertEqual(out.stdout.strip(), str(Path('/tmp').resolve()))


if __name__ == '__main__':
    unittest.main()
