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


if __name__ == '__main__':
    unittest.main()
