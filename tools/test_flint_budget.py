"""flint budget's comparison, update and raise rules (tools/flint_budget.py, tools/budget_raise_check.py)."""
import unittest

import budget_raise_check
import flint_budget

RUNNER = 'CPU / glibc / valgrind'


def budgets(**endpoints):
    return {'schema': flint_budget.SCHEMA, 'runner': RUNNER, 'tolerance': {'instructions': 0.01},
            'endpoints': {name: {'instructions': value} for name, value in endpoints.items()}}


class CompareTests(unittest.TestCase):
    def test_within_tolerance_passes_and_a_drop_is_a_notice(self):
        problems, notices = flint_budget.compare('app', {'a': {'instructions': 1005}, 'b': {'instructions': 900}},
                                                 budgets(a=1000, b=1000), {}, RUNNER)
        self.assertEqual(problems, [])
        self.assertEqual(len(notices), 1)
        self.assertIn("'b'", notices[0])

    def test_a_raise_beyond_tolerance_names_the_endpoint_and_delta(self):
        problems, _ = flint_budget.compare('app', {'a': {'instructions': 1100}}, budgets(a=1000), {}, RUNNER)
        self.assertEqual(len(problems), 1)
        self.assertIn("'a': instructions 1,000 -> 1,100 (+10.00%", problems[0])

    def test_missing_and_stale_budgets_fail(self):
        problems, _ = flint_budget.compare('app', {'new': {'instructions': 10}}, budgets(old=10), {}, RUNNER)
        self.assertEqual(len(problems), 2)
        self.assertTrue(any("'new' has no instruction budget" in line for line in problems))
        self.assertTrue(any("'old' has a budget but is no longer a suite case" in line for line in problems))

    def test_another_runner_class_fails_closed(self):
        problems, _ = flint_budget.compare('app', {'a': {'instructions': 1000}}, budgets(a=1000), {}, 'other')
        self.assertEqual(len(problems), 1)
        self.assertIn('budgets recorded on', problems[0])

    def test_allocations_and_bytes_are_compared_with_the_allocation_budgets(self):
        measured = {'a': {'instructions': 1000, 'allocations': 3, 'bytes': 200}}
        problems, _ = flint_budget.compare('app', measured, budgets(a=1000), {'a': {'allocations': 2, 'bytes': 200}},
                                           RUNNER)
        self.assertEqual(len(problems), 1)
        self.assertIn('allocations 3 over the budget of 2', problems[0])


class UpdateTests(unittest.TestCase):
    def test_lowering_is_free_and_a_raise_needs_a_decision(self):
        document, raised = flint_budget.update('app', {'a': {'instructions': 900}, 'b': {'instructions': 1500}},
                                               budgets(a=1000, b=1000), RUNNER, None)
        self.assertEqual(document['endpoints']['a'], {'instructions': 900})
        self.assertEqual(document['endpoints']['b'], {'instructions': 1000})  # kept until a decision allows it
        self.assertEqual(len(raised), 1)
        document, raised = flint_budget.update('app', {'b': {'instructions': 1500}}, budgets(b=1000), RUNNER, 'abc123')
        self.assertEqual(document['endpoints']['b'], {'instructions': 1500, 'raised': 'abc123'})
        self.assertEqual(raised, [])

    def test_an_endpoint_note_survives_an_update(self):
        stored = budgets(a=1000)
        stored['endpoints']['a']['note'] = 'seeded above the first measurement: a deliberate trade'
        document, _ = flint_budget.update('app', {'a': {'instructions': 990}}, stored, RUNNER, None)
        self.assertEqual(document['endpoints']['a'], {'instructions': 990, 'note': stored['endpoints']['a']['note']})

    def test_each_endpoint_gets_three_times_its_own_noise_but_at_least_half_a_percent(self):
        document, _ = flint_budget.update('app', {'a': {'instructions': 10}, 'b': {'instructions': 10}}, {}, RUNNER,
                                          None, noise={'a': 0.0001, 'b': 0.004})
        self.assertEqual(document['tolerance']['instructions'], 0.005)
        self.assertNotIn('tolerance', document['endpoints']['a'])
        self.assertEqual(document['endpoints']['b']['tolerance'], 0.012)

    def test_an_app_floor_widens_the_file_tolerance_and_absorbs_smaller_noise(self):
        document, _ = flint_budget.update('petclinic-rest', {'a': {'instructions': 10}, 'b': {'instructions': 10}}, {},
                                          RUNNER, None, noise={'a': 0.003, 'b': 0.004})
        self.assertEqual(document['tolerance']['instructions'], 0.01)
        self.assertNotIn('tolerance', document['endpoints']['a'])
        self.assertEqual(document['endpoints']['b']['tolerance'], 0.012)

    def test_an_endpoint_tolerance_is_used_when_comparing(self):
        stored = budgets(a=1000)
        stored['endpoints']['a']['tolerance'] = 0.05
        problems, _ = flint_budget.compare('app', {'a': {'instructions': 1040}}, stored, {}, RUNNER)
        self.assertEqual(problems, [])


class HoldTests(unittest.TestCase):
    def test_the_hold_reruns_flint_budget_itself(self):
        import os
        import spring_instr
        from unittest import mock
        with mock.patch.dict(os.environ, {'FLINT_SPRING_INSTR_HELD': ''}), \
                mock.patch.object(spring_instr.subprocess, 'call', return_value=0) as call, \
                mock.patch.object(spring_instr, 'queue_lock', return_value=None), \
                mock.patch.object(spring_instr.sys, 'argv', ['flint_budget.py', '--app', 'x']), \
                self.assertRaises(SystemExit):
            spring_instr.rerun_under_hold(flint_budget.Path(flint_budget.__file__).resolve())
        command = call.call_args.args[0]
        self.assertTrue(command[-3].endswith('flint_budget.py'), command)
        self.assertEqual(command[-2:], ['--app', 'x'])


class RaiseCheckTests(unittest.TestCase):
    def test_raises_beyond_the_old_tolerance_only(self):
        self.assertEqual(budget_raise_check.raises(budgets(a=1000, b=1000), budgets(a=1005, b=1200)),
                         [('b', 1000, 1200)])

    def test_a_first_budget_or_a_new_runner_class_is_not_a_raise(self):
        self.assertEqual(budget_raise_check.raises(None, budgets(a=1)), [])
        moved = budgets(a=5000)
        moved['runner'] = 'another class'
        self.assertEqual(budget_raise_check.raises(budgets(a=1000), moved), [])


if __name__ == '__main__':
    unittest.main()
