"""Unit tests of the Spring gate on synthetic evidence: `python3 tools/test_spring_gate.py`."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import spring_bench
import spring_gate

APPS = ['gs-rest-service']
MATRIX = {'settings': {'precise': 'gc:precise'}, 'apps': ['gs-rest-service']}


def series(value):
    return [value * (1 + 0.001 * i) for i in range(9)]


class SpringGate(unittest.TestCase):
    def evidence(self, directory, flint_factor=0.5, mode='production', drop=None):
        golden = spring_bench.sha256(spring_bench.golden_path('gs-rest-service'))
        registered = {'gs-rest-service': {'sha256': 'abc'}}
        for impl in spring_bench.IMPLEMENTATIONS:
            record = [{'app': 'gs-rest-service', 'implementation': impl, 'golden_sha256': golden,
                       'wire': spring_bench.WIRE_DEFAULT[impl], 'cases': [{'name': 'x', 'problems': []}]}]
            (directory / f'acceptance-{impl}.json').write_text(json.dumps(record))
        go = {'go_std_cold_seconds': series(1.0), 'go_scratch_seconds': series(10.0),
              'go_std_incremental_seconds': series(0.5), 'binary_bytes': 1000}
        flint = {'flint_cached_cold_seconds': series(flint_factor), 'flint_scratch_seconds': series(10 * flint_factor),
                 'flint_cached_incremental_seconds': series(0.5 * flint_factor), 'Oz': {'binary_bytes': 500}}
        (directory / 'builds.json').write_text(json.dumps({
            'mode': mode, 'status': 'passed', 'trials_per_series': 9, 'comparators': registered,
            'apps': {'gs-rest-service': {'go': go, 'flint': flint}}}))
        metrics = {'p99_ms': 1.0, 'peak_rss_bytes': 1e7, 'cpu_ns_per_request': 1e4}
        go_http = {k: series(v) for k, v in metrics.items()} | {'requests_per_second': series(1e5)}
        flint_http = {k: series(v * flint_factor) for k, v in metrics.items()} | {
            'requests_per_second': series(1e5 / flint_factor)}
        (directory / 'http.json').write_text(json.dumps({
            'schema': 2, 'mode': mode, 'status': 'passed', 'comparators': registered, 'acceptance': [],
            'apps': {'gs-rest-service': {'measured': {'flint': flint_http, 'go': go_http}}}}))
        (directory / 'gc-matrix-gs-rest-service.json').write_text(json.dumps({
            'mode': mode, 'status': 'passed', 'settings': {'precise': {'suite': {'passed': 18, 'total': 18}}}}))
        if drop:
            (directory / drop).unlink()
        return registered

    def gate(self, **kwargs):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            registered = self.evidence(directory, **kwargs)
            registry = {'apps': {'gs-rest-service': spring_bench.registry()['apps']['gs-rest-service']}}
            with mock.patch.object(spring_bench, 'registry', return_value=registry), \
                    mock.patch.object(spring_bench, 'check_registry', return_value=[]), \
                    mock.patch.object(spring_gate.json, 'loads', side_effect=self.loads(registered)):
                return spring_gate.spring_gate(directory)

    @staticmethod
    def loads(registered):
        real = json.JSONDecoder().decode

        def decode(text, *args, **kwargs):
            value = real(text)
            if isinstance(value, dict) and value.get('schema') == 'flint.spring-comparators/1':
                return dict(value, comparators=registered)
            if isinstance(value, dict) and value.get('schema') == 'flint.spring-gc-matrix/1':
                return dict(value, **MATRIX)
            return value
        return decode

    def test_faster_flint_passes(self):
        report, failures = self.gate()
        self.assertEqual(failures, [])
        self.assertLess(report['build gs-rest-service']['primary']['median'], 0.99)

    def test_slower_flint_fails_every_comparison(self):
        _, failures = self.gate(flint_factor=1.0)
        joined = ' | '.join(failures)
        for label in ('primary', 'secondary', 'incremental', 'p99_ms', 'peak_rss_bytes', 'throughput'):
            self.assertIn(label, joined)

    def test_smoke_and_missing_evidence_fail(self):
        _, failures = self.gate(mode='smoke')
        self.assertTrue(any('builds.json: mode smoke' in f for f in failures))
        _, failures = self.gate(drop='acceptance-flint.json')
        self.assertTrue(any('acceptance-flint.json: missing' in f for f in failures))


if __name__ == '__main__':
    unittest.main()
