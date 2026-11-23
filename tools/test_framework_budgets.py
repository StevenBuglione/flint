"""Unit tests of the framework-module budgets: `python3 tools/test_framework_budgets.py`."""
import unittest
from unittest import mock

import framework_budgets
from perf_stats import median_ratio_interval

BUDGET = {'dmd_cold_seconds': 1.0, 'dmd_incremental_seconds': 0.5, 'ldc_cold_seconds': 5.0,
          'ldc_incremental_seconds': 2.0, 'incremental_linked_bytes': 100000, 'compiler_peak_rss_bytes': 10 ** 9,
          'template_instances': 500}
LISTED = {'core': {'directory': 'framework/core', 'module': 'flint.core', 'budget': BUDGET,
                   'bench': {'fixture': 'framework/core/bench', 'baseline': 'framework/core/bench/baseline',
                             'edit_source': 'framework/core/source/flint/core/env/Environment.d'}}}
REGRESSION = {'compile_ratio_max': 1.1, 'compiler_rss_ratio_max': 1.1, 'template_ratio_max': 1.1,
              'binary_ratio_max': 1.05}


def compare_series(new, old, ceiling, label):
    median, _, upper = median_ratio_interval(new, old)
    if median > ceiling or upper > ceiling:
        raise ValueError(f'{label}: ratio {median:.3f} exceeds {ceiling}')


def row(scale=1.0, templates=300):
    series = lambda v: [v * scale * (1 + .001 * i) for i in range(9)]
    return {'dmd_cold_seconds': series(.5), 'dmd_incremental_seconds': series(.2), 'ldc_cold_seconds': series(3),
            'ldc_incremental_seconds': series(1), 'incremental_linked_bytes': 50000,
            'compiler_peak_rss_bytes': 5 * 10 ** 8, 'template_instances': templates}


class FrameworkBudgets(unittest.TestCase):
    def check(self, current, baseline=None):
        with mock.patch.object(framework_budgets, 'modules', return_value=LISTED):
            return framework_budgets.check(current, baseline, REGRESSION, compare_series)

    def test_within_budget_passes(self):
        self.assertEqual(self.check({'framework': {'core': row()}}), [])
        self.assertEqual(self.check({'framework': {'core': row()}}, {'framework': {'core': row()}}), [])

    def test_budget_regression_and_coverage_fail(self):
        self.assertTrue(any('dmd_cold_seconds median' in p for p in self.check({'framework': {'core': row(3)}})))
        self.assertTrue(any('template_instances' in p for p in self.check({'framework': {'core': row(templates=600)}})))
        regressed = self.check({'framework': {'core': row(1.5)}}, {'framework': {'core': row()}})
        self.assertTrue(any('ratio' in p for p in regressed))
        self.assertTrue(any('missing' in p for p in self.check({'framework': {}})))
        self.assertTrue(any('unlisted' in p for p in self.check({'framework': {'core': row(), 'extra': row()}})))

    def test_load_requires_budget_and_probe(self):
        with mock.patch.object(framework_budgets, 'modules', return_value=LISTED):
            self.assertEqual(framework_budgets.load('.')['core']['directory'], 'framework/core')
        broken = {'core': dict(LISTED['core'], budget={'dmd_cold_seconds': 1})}
        with mock.patch.object(framework_budgets, 'modules', return_value=broken):
            with self.assertRaises(ValueError):
                framework_budgets.load('.')

    def test_provisional_skips_only_the_ceiling(self):
        listed = {'core': dict(LISTED['core'], provisional=['dmd_cold_seconds', 'compiler_peak_rss_bytes'])}
        slow = dict(row(), compiler_peak_rss_bytes=2 * 10 ** 9)
        slow['dmd_cold_seconds'] = [3.0 * (1 + .001 * i) for i in range(9)]
        with mock.patch.object(framework_budgets, 'modules', return_value=listed):
            # Over the placeholder ceilings, and still clean: only the absolute test is skipped.
            self.assertEqual(framework_budgets.check({'framework': {'core': slow}}, None, REGRESSION, compare_series), [])
            # The regression ratio against a base still applies to a provisional key.
            regressed = framework_budgets.check({'framework': {'core': slow}}, {'framework': {'core': row()}},
                                                REGRESSION, compare_series)
            self.assertTrue(any('dmd_cold_seconds' in p for p in regressed))
            # So does the nine-finite-samples rule.
            short = dict(slow, dmd_cold_seconds=[1.0])
            self.assertTrue(any('9 finite samples' in p for p in
                                framework_budgets.check({'framework': {'core': short}}, None, REGRESSION, compare_series)))
            # A non-provisional key keeps its ceiling.
            over = dict(slow, template_instances=600)
            self.assertTrue(any('template_instances' in p for p in
                                framework_budgets.check({'framework': {'core': over}}, None, REGRESSION, compare_series)))
            self.assertEqual(framework_budgets.provisional_report('.'),
                             {'core': ['compiler_peak_rss_bytes', 'dmd_cold_seconds']})

    def test_provisional_is_validated(self):
        for bad in ([], ['incremental_linked_bytes'], ['template_instances'], ['dmd_cold_seconds', 'dmd_cold_seconds'],
                    ['unknown'], 'dmd_cold_seconds'):
            listed = {'core': dict(LISTED['core'], provisional=bad)}
            with mock.patch.object(framework_budgets, 'modules', return_value=listed):
                with self.assertRaises(ValueError, msg=repr(bad)):
                    framework_budgets.load('.')
        with mock.patch.object(framework_budgets, 'modules', return_value=LISTED):
            self.assertEqual(framework_budgets.provisional_report('.'), {})


class ApplyMeasured(unittest.TestCase):
    def test_only_provisional_keys_take_measured_values(self):
        import json, tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'policy').mkdir()
            meta = dict(LISTED['core'], budget=dict(BUDGET),
                        provisional=['dmd_cold_seconds', 'ldc_cold_seconds', 'compiler_peak_rss_bytes'])
            (root / 'policy' / 'framework.json').write_text(json.dumps({'schema': 'flint.framework/1',
                                                                         'modules': {'core': meta}}, indent=1) + '\n')
            result = {'mode': 'framework-builds', 'framework': {'core': row()}}
            changes = framework_budgets.apply(root, result, receipt='queue receipt')
            written = json.loads((root / 'policy' / 'framework.json').read_text())['modules']['core']
        self.assertEqual(set(changes['core']), {'dmd_cold_seconds', 'ldc_cold_seconds', 'compiler_peak_rss_bytes'})
        self.assertEqual(written['budget']['dmd_cold_seconds'], 0.76)  # median 0.502 x 1.5, rounded up to 0.01
        self.assertEqual(written['budget']['compiler_peak_rss_bytes'], 597 << 20)  # 5e8 x 1.25, up to a MiB
        self.assertEqual(written['budget']['dmd_incremental_seconds'], BUDGET['dmd_incremental_seconds'])
        self.assertNotIn('provisional', written)
        self.assertEqual(written['budget_source']['measured'], 'queue receipt')

    def test_apply_refuses_other_results(self):
        with self.assertRaises(ValueError):
            framework_budgets.apply('.', {'mode': 'framework-sizes', 'framework': {}})


if __name__ == '__main__':
    unittest.main()
