"""Template budgets only go down after the reset (owner decision 3): tools/template_budget_ratchet.py."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import template_budget_ratchet as ratchet  # noqa: E402


def git(root, *arguments):
    return subprocess.run(['git', *arguments], cwd=root, check=True, capture_output=True, text=True).stdout.strip()


class Repository:
    """A scratch repository with policy/packages.json and policy/framework.json."""

    def __init__(self, directory):
        self.root = Path(directory)
        git(self.root, 'init', '--quiet')
        git(self.root, 'config', 'user.email', 'ratchet@example.invalid')
        git(self.root, 'config', 'user.name', 'ratchet test')
        (self.root / 'policy').mkdir()

    def write(self, packages, framework):
        (self.root / 'policy/packages.json').write_text(json.dumps(
            {'packages': {n: {'budget': {'template_instances': v}} for n, v in packages.items()}}))
        (self.root / 'policy/framework.json').write_text(json.dumps(
            {'modules': {n: {'budget': {'template_instances': v}} for n, v in framework.items()}}))

    def commit(self, packages, framework, message):
        self.write(packages, framework)
        git(self.root, 'add', '-A')
        git(self.root, 'commit', '--quiet', '-m', message)
        return git(self.root, 'rev-parse', 'HEAD')

    def check(self, anchor):
        return ratchet.check(self.root, {'template_budget_ratchet': {'after': anchor}})


class TemplateBudgetRatchet(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.repo = Repository(self.directory.name)
        # Before the reset the budgets were too low; the reset raises them once, which the rule allows.
        self.anchor = self.repo.commit({'arena': 100}, {'core': 750}, 'old budgets')
        self.repo.commit({'arena': 200}, {'core': 8900}, 'reset')

    def tearDown(self):
        self.directory.cleanup()

    def test_the_reset_and_later_cuts_pass(self):
        self.assertEqual(self.repo.check(self.anchor), [])
        self.repo.commit({'arena': 150}, {'core': 8000}, 'cut')
        self.repo.commit({'arena': 150}, {'core': 8000, 'tx': 7500}, 'a new module starts at its first budget')
        self.assertEqual(self.repo.check(self.anchor), [])

    def test_a_committed_raise_fails_even_after_a_later_cut(self):
        self.repo.commit({'arena': 150}, {'core': 8000}, 'cut')
        self.repo.commit({'arena': 150}, {'core': 8100}, 'raise core back up')
        self.repo.commit({'arena': 120}, {'core': 8100}, 'cut arena')
        problems = self.repo.check(self.anchor)
        self.assertEqual(len(problems), 1)
        self.assertIn('framework core: template_instances budget raised from 8000 to 8100', problems[0])

    def test_a_raise_in_the_working_tree_fails(self):
        self.repo.write({'arena': 201}, {'core': 8900})
        problems = self.repo.check(self.anchor)
        self.assertEqual(len(problems), 1)
        self.assertIn('package arena: template_instances budget raised from 200 to 201 in the working tree',
                      problems[0])

    def test_the_rule_is_off_without_an_anchor_and_before_it(self):
        self.repo.write({'arena': 10 ** 6}, {'core': 10 ** 6})
        self.assertEqual(ratchet.check(self.repo.root, {}), [])
        # A checkout that does not descend from the anchor (a base older than the reset) is not subject to the rule.
        reset = git(self.repo.root, 'rev-parse', 'HEAD')
        git(self.repo.root, 'checkout', '--quiet', '--force', '--detach', self.anchor)
        elsewhere = self.repo.commit({'arena': 5}, {'core': 5}, 'a line the reset does not descend from')
        git(self.repo.root, 'checkout', '--quiet', '--force', '--detach', reset)
        self.repo.write({'arena': 10 ** 6}, {'core': 10 ** 6})
        self.assertEqual(self.repo.check(elsewhere), [])

    def test_a_missing_anchor_or_shallow_history_fails(self):
        problems = self.repo.check('0' * 40)
        self.assertEqual(len(problems), 1)
        self.assertIn('is not in this checkout', problems[0])
        with tempfile.TemporaryDirectory() as clone:
            git(Path(clone), 'clone', '--quiet', '--depth', '1', 'file://' + str(self.repo.root), 'shallow')
            problems = ratchet.check(Path(clone) / 'shallow', {'template_budget_ratchet': {'after': self.anchor}})
            self.assertEqual(len(problems), 1)
            self.assertIn('shallow', problems[0])

    def test_a_real_checkout_is_always_checked(self):
        policy = {'template_budget_ratchet': {'after': self.anchor}}
        self.assertIsNone(ratchet.not_applicable(self.repo.root, policy))
        self.repo.write({'arena': 201}, {'core': 8900})
        self.assertEqual(len(ratchet.check(self.repo.root, policy)), 1)

    def test_outside_a_git_checkout_the_rule_says_it_is_not_applicable(self):
        policy = {'template_budget_ratchet': {'after': self.anchor}}
        with tempfile.TemporaryDirectory() as directory:
            # A copied workspace: the policy files without the history (flint check's parity tests).
            copy = Repository.__new__(Repository)
            copy.root = Path(directory)
            (copy.root / 'policy').mkdir()
            copy.write({'arena': 10 ** 6}, {'core': 10 ** 6})
            note = ratchet.not_applicable(copy.root, policy)
            self.assertIn('not applicable: no git history', note)
            self.assertIn(self.anchor[:12], note)
            self.assertEqual(ratchet.check(copy.root, policy), [])
        # A tree inside another checkout is not that checkout: its history is not the tree's.
        nested = self.repo.root / 'workspace'
        (nested / 'policy').mkdir(parents=True)
        self.assertIn('not applicable', ratchet.not_applicable(nested, policy))
        # Without an anchor there is nothing to report.
        self.assertIsNone(ratchet.not_applicable(nested, {}))


class ApprovedRaises(unittest.TestCase):
    """A raise passes only in a commit whose Budget-Raise-Approved trailer names a rule or a decisions.md commit."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.repo = Repository(self.directory.name)
        self.anchor = self.repo.commit({'arena': 50, 'engine-web': 50}, {'ai-model': 50}, 'old budgets')
        (self.repo.root / ratchet.RULES).write_text(json.dumps({'rules': {
            'api-growth-rule': {'not_for': ['package engine-*', 'framework engine-*']}, 'new-module-rule': {}}}))
        self.repo.commit({'arena': 100, 'engine-web': 100}, {'ai-model': 1200}, 'reset, and the raise rules')

    def tearDown(self):
        self.directory.cleanup()

    def raise_ai_model(self, message):
        return self.repo.commit({'arena': 100, 'engine-web': 100}, {'ai-model': 1260}, message)

    def test_a_named_rule_in_the_trailer_approves_and_is_reported(self):
        commit = self.raise_ai_model('ai-model: RateLimit\n\n1,200 to 1,260\n\nBudget-Raise-Approved: api-growth-rule\n')
        problems, accepted = ratchet.report(self.repo.root, {'template_budget_ratchet': {'after': self.anchor}})
        self.assertEqual(problems, [])
        self.assertEqual(accepted, [f'framework ai-model: template_instances budget raised from 1200 to 1260 in '
                                    f'{commit[:12]}, approved by api-growth-rule'])

    def test_a_raise_without_the_trailer_fails(self):
        self.raise_ai_model('ai-model: RateLimit')
        problems = self.repo.check(self.anchor)
        self.assertEqual(len(problems), 1)
        self.assertIn('raised from 1200 to 1260', problems[0])
        self.assertIn('no Budget-Raise-Approved', problems[0])

    def test_an_unknown_id_fails(self):
        self.raise_ai_model('ai-model: RateLimit\n\nBudget-Raise-Approved: my-own-rule\n')
        problems = self.repo.check(self.anchor)
        self.assertEqual(len(problems), 1)
        self.assertIn("'my-own-rule' is neither a rule", problems[0])

    def test_a_rule_does_not_cover_what_it_excludes(self):
        self.repo.commit({'arena': 100, 'engine-web': 120}, {'ai-model': 1200},
                         'engine-web grows\n\nBudget-Raise-Approved: api-growth-rule\n')
        problems = self.repo.check(self.anchor)
        self.assertEqual(len(problems), 1)
        self.assertIn('api-growth-rule does not cover package engine-web', problems[0])

    def test_a_commit_that_recorded_a_decision_approves(self):
        decisions = self.repo.root / ratchet.DECISIONS
        decisions.parent.mkdir(parents=True)
        decisions.write_text('- owner: ai-model may grow to 1,260\n')
        git(self.repo.root, 'add', '-A')
        git(self.repo.root, 'commit', '--quiet', '-m', 'decision')
        decision = git(self.repo.root, 'rev-parse', 'HEAD')
        self.raise_ai_model(f'ai-model: RateLimit\n\nBudget-Raise-Approved: {decision[:10]}\n')
        self.assertEqual(self.repo.check(self.anchor), [])

    def test_a_commit_that_recorded_no_decision_does_not_approve(self):
        unrelated = git(self.repo.root, 'rev-parse', 'HEAD')  # changed the rules file, not decisions.md
        self.raise_ai_model(f'ai-model: RateLimit\n\nBudget-Raise-Approved: {unrelated}\n')
        problems = self.repo.check(self.anchor)
        self.assertEqual(len(problems), 1)
        self.assertIn('nor a commit that changed', problems[0])

    def test_the_trailer_cannot_approve_a_working_tree_raise(self):
        self.repo.write({'arena': 100, 'engine-web': 100}, {'ai-model': 1260})
        problems = self.repo.check(self.anchor)
        self.assertEqual(len(problems), 1)
        self.assertIn('in the working tree', problems[0])
        self.assertIn('commit it with the trailer', problems[0])


if __name__ == '__main__':
    unittest.main()
