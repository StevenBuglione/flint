"""Unit tests of the Spring gate on synthetic evidence: `python3 tools/test_spring_gate.py`."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import spring_bench
import spring_gate

APPS = ['gs-rest-service']
RUNS = {'http': 9, 'gc': 9, 'error': 9}
MATRIX = {'settings': {'precise': 'gc:precise'}, 'apps': ['gs-rest-service']}


def series(value):
    return [value * (1 + 0.001 * i) for i in range(9)]


class SpringGate(unittest.TestCase):
    def evidence(self, directory, flint_factor=0.5, mode='production', drop=None, assembly=None, tamper=None, stray=None):
        golden = spring_bench.sha256(spring_bench.golden_path('gs-rest-service'))
        registered = {'gs-rest-service': {'sha256': 'abc'}}
        for impl in spring_bench.IMPLEMENTATIONS:
            record = [{'app': 'gs-rest-service', 'implementation': impl, 'golden_sha256': golden,
                       'wire': spring_bench.WIRE_DEFAULT[impl], 'cases': [{'name': 'x', 'problems': []}]}]
            (directory / f'acceptance-{impl}.json').write_text(json.dumps(record))
        go = {'go_std_cold_seconds': series(1.0), 'go_scratch_seconds': series(10.0),
              'go_std_incremental_seconds': series(0.5), 'binary_bytes': 1000}
        flint = {'flint_cached_cold_seconds': series(flint_factor), 'flint_scratch_seconds': series(10 * flint_factor),
                 'flint_cached_incremental_seconds': series(0.5 * flint_factor),
                 'flint_static_incremental_seconds': series(0.5 * flint_factor), 'Oz': {'binary_bytes': 500}}
        (directory / 'builds.json').write_text(json.dumps({
            'mode': mode, 'status': 'passed', 'trials_per_series': 9, 'comparators': registered,
            'apps': {'gs-rest-service': {'go': go, 'flint': flint}}}))
        metrics = {'p50_ms': 0.5, 'p99_ms': 1.0, 'p999_ms': 2.0, 'peak_rss_bytes': 1e7, 'cpu_ns_per_request': 1e4}
        go_http = {k: series(v) for k, v in metrics.items()} | {'requests_per_second': series(1e5)}
        flint_http = {k: series(v * flint_factor) for k, v in metrics.items()} | {
            'requests_per_second': series(1e5 / flint_factor)}
        (directory / 'http.json').write_text(json.dumps({
            'schema': 2, 'mode': mode, 'status': 'passed', 'comparators': registered, 'acceptance': [],
            'apps': {'gs-rest-service': {'measured': {'flint': flint_http, 'go': go_http}}}}))
        (directory / 'http-error-paths.json').write_text(json.dumps({
            'schema': 2, 'mode': mode, 'status': 'passed', 'comparators': registered,
            'apps': {key: {'measured': {'flint': flint_http, 'go': go_http}} for key in
                     json.loads((spring_bench.ROOT / 'policy' / 'spring-error-paths-benchmark.json').read_text())['apps']}}))
        (directory / 'gc-matrix-gs-rest-service.json').write_text(json.dumps({
            'mode': mode, 'status': 'passed', 'settings': {'precise': {'suite': {'passed': 18, 'total': 18}}}}))
        files = {path.name: spring_bench.sha256(path) for path in directory.glob('*.json')}
        (directory / 'assembled.json').write_text(json.dumps(dict(
            {'schema': 'flint.spring-evidence/2', 'commit': 'c' * 40, 'missing': [], 'problems': [], 'files': files},
            **(assembly or {}))))
        if drop:
            (directory / drop).unlink()
        if tamper:
            (directory / tamper).write_text((directory / tamper).read_text() + ' ')
        if stray:
            (directory / stray).write_text('{}')
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
        for label in ('primary', 'secondary', 'incremental', 'p50_ms', 'p99_ms', 'peak_rss_bytes', 'throughput',
                      'not-found'):
            self.assertIn(label, joined)

    def test_p999_is_reported_not_scored(self):
        report, failures = self.gate()
        self.assertEqual(failures, [])
        self.assertIn('p999_ms (reported)', report['http gs-rest-service'])

    def test_assembly_problems_and_missing_assembly_fail(self):
        _, failures = self.gate(assembly={'problems': ['the parts were not all measured at one source commit']})
        self.assertTrue(any(f.startswith('assembly: the parts were not') for f in failures))
        _, failures = self.gate(assembly={'commit': None})
        self.assertTrue(any('no single source commit' in f for f in failures))
        _, failures = self.gate(drop='assembled.json')
        self.assertTrue(any('assembled.json: missing' in f for f in failures))
        _, failures = self.gate(assembly={'schema': 'flint.spring-evidence/1'})
        self.assertTrue(any('reassemble' in f for f in failures))

    def test_files_not_written_by_the_assembly_fail(self):
        _, failures = self.gate(tamper='http.json')
        self.assertIn('http.json: differs from what the assembly wrote', failures)
        _, failures = self.gate(stray='http-extra.json')
        self.assertIn('http-extra.json: not written by the assembly', failures)

    def test_smoke_and_missing_evidence_fail(self):
        _, failures = self.gate(mode='smoke')
        self.assertTrue(any('builds.json: mode smoke' in f for f in failures))
        _, failures = self.gate(drop='acceptance-flint.json')
        self.assertTrue(any('acceptance-flint.json: missing' in f for f in failures))


class AssembleParts(unittest.TestCase):
    def test_per_application_parts_merge_into_one_record(self):
        def part(app, status='passed'):
            return {'schema': 'flint.spring-builds/1', 'mode': 'production', 'status': status, 'commit': 'abc',
                    'host': {}, 'trials_per_series': 9, 'comparators': {app: {}}, 'missing_flint': [],
                    'apps': {app: {'go': {}, 'flint': {}}}, 'trials': [{'app': app}]}
        with tempfile.TemporaryDirectory() as temporary:
            paths = []
            for app in ('gs-rest-service', 'petclinic-rest'):
                path = Path(temporary) / f'{app}.json'
                path.write_text(json.dumps(part(app)))
                paths.append((path, part(app)))
            merged = spring_bench.merge_builds(paths)
            self.assertEqual(sorted(merged['apps']), ['gs-rest-service', 'petclinic-rest'])
            self.assertEqual((merged['mode'], merged['status'], len(merged['trials'])), ('production', 'passed', 2))
            paths[1] = (paths[1][0], dict(part('petclinic-rest', 'failed'), trials_per_series=1))
            merged = spring_bench.merge_builds(paths)
            self.assertEqual((merged['mode'], merged['status']), ('mixed', 'failed'))
        self.assertEqual(len(spring_bench.merge_acceptance([(None, {'app': 'a'}), (None, [{'app': 'b'}, {'app': 'c'}])])), 3)


class AssembleFailsClosed(unittest.TestCase):
    @staticmethod
    def part(entry, family, record, commit='a' * 40, file=None):
        return {'entry': entry, 'family': family, 'record': record, 'commits': {commit},
                'file': file or {'builds': 'builds.json', 'http': 'http.json'}.get(family, 'x.json')}

    def builds(self, **extra):
        return dict({'mode': 'production', 'status': 'passed', 'trials_per_series': 9, 'commit': 'a' * 12}, **extra)

    def http(self, runs=9):
        return {'mode': 'production', 'status': 'passed', 'effective_workload': {'runs': runs}}

    def test_one_commit_production_and_trial_counts_pass(self):
        parts = [self.part('b', 'builds', self.builds()), self.part('h', 'http', self.http()),
                 self.part('e', 'error', self.http()), self.part('g', 'gc', self.http())]
        self.assertEqual(spring_bench.consistency_problems(parts, RUNS), [])

    def test_mismatched_commits_fail(self):
        parts = [self.part('b', 'builds', self.builds()), self.part('h', 'http', self.http(), commit='b' * 40)]
        problems = spring_bench.consistency_problems(parts, RUNS)
        self.assertTrue(any('one source commit' in p for p in problems))

    def test_trial_counts_and_self_reported_commit_fail(self):
        parts = [self.part('b', 'builds', self.builds(trials_per_series=3)), self.part('h', 'http', self.http(runs=4)),
                 self.part('c', 'builds', self.builds(commit='d' * 12))]
        problems = ' | '.join(spring_bench.consistency_problems(parts, RUNS))
        for text in ('3 trials per series', '4 runs', 'names commit dddd'):
            self.assertIn(text, problems)

    def test_builds_without_commit_and_error_runs_from_their_own_manifest(self):
        builds = self.builds(); builds.pop('commit')
        problems = ' | '.join(spring_bench.consistency_problems([self.part('b', 'builds', builds)], RUNS))
        self.assertIn('names no commit', problems)
        problems = spring_bench.consistency_problems([self.part('e', 'error', self.http(runs=9))], dict(RUNS, error=5))
        self.assertTrue(any("manifest's 5 required" in p for p in problems))

    def test_assemble_refuses_a_non_empty_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            (Path(temporary) / 'http.json').write_text('{}')
            with self.assertRaisesRegex(SystemExit, 'not empty'):
                spring_bench.assemble(temporary)

    def test_builds_must_be_served(self):
        def part(dmd_server):
            row = self.part('b', 'builds', self.builds())
            row['steps'] = [{'command': ['python3', 'tools/measure_builds.py'], 'dmd_server': {'scored': dmd_server}}]
            return row
        self.assertEqual(spring_bench.consistency_problems([part({'compiled': 40, 'refused': 0})], RUNS), [])
        for bad in ({'compiled': 40, 'refused': 2}, {'compiled': 0, 'refused': 0}, None):
            problems = spring_bench.consistency_problems([part(bad)], RUNS)
            self.assertTrue(any('served compiles' in p for p in problems), bad)

    def test_smoke_part_fails(self):
        problems = spring_bench.consistency_problems([self.part('h', 'http', dict(self.http(), mode='smoke'))], RUNS)
        self.assertTrue(any('mode smoke' in p for p in problems))

    def test_coverage_gaps_fail(self):
        apps = sorted(spring_bench.registry()['apps'])
        parts = [self.part('b', 'builds', dict(self.builds(), apps={apps[0]: {}}))]
        problems = ' | '.join(spring_bench.coverage_problems(parts))
        self.assertIn('builds: not covered', problems)
        for family in ('http', 'error', 'gc', 'acceptance'):
            self.assertIn(f'{family}: not covered', problems)


class PlatformOnlyCache(unittest.TestCase):
    def test_project_entries_are_stripped_and_stray_ones_refused(self):
        import spring_builds
        with tempfile.TemporaryDirectory() as temporary:
            root, port = Path(temporary), Path(temporary) / 'port'
            cache = root / 'cache'
            (cache / 'projects' / 'abc' / 'aot' / 'models').mkdir(parents=True)
            (cache / 'projects' / 'abc' / 'aot' / 'models' / 'm.json').write_text(f'{{"file": "{port}/src/app.d"}}')
            (cache / 'aot' / 'models').mkdir(parents=True)
            (cache / 'aot' / 'models' / 'p.json').write_text('{"file": "/platform/source/flint/x.d"}')
            (cache / 'digests.log').write_text(f'/platform/x.d\t1 2 3 abc\n{port}/src/app.d\t1 2 3 def\n')
            self.assertEqual(spring_builds.platform_only_cache(cache, root / 'platform', port), 1)
            self.assertEqual(sorted(p.name for p in (root / 'platform').rglob('*') if p.is_file()),
                             ['digests.log', 'p.json'])
            # The pruned log is a copy of its own: flint appends to it, and the primed cache must not change.
            self.assertEqual((root / 'platform' / 'digests.log').read_text(), '/platform/x.d\t1 2 3 abc\n')
            self.assertEqual((cache / 'digests.log').stat().st_nlink, 1)
            (cache / 'aot' / 'outputs').mkdir()
            (cache / 'aot' / 'outputs' / 'o.json').write_text(f'{{"root": "{port}"}}')
            with self.assertRaisesRegex(RuntimeError, 'outputs/o.json'):
                spring_builds.platform_only_cache(cache, root / 'platform-2', port)

    def test_aot_counts(self):
        import spring_builds
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / 'build.log'
            log.write_text('    Generated 11 Flint AOT modules for a.B (2 extracted in 9 ms, 21 from the shared cache, '
                           '12 written, 30 ms)\n')
            self.assertEqual(spring_builds.aot_counts(log), (2, 21))
            log.write_text('Built\n')
            self.assertIsNone(spring_builds.aot_counts(log))


if __name__ == '__main__':
    unittest.main()
