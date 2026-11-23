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


if __name__ == '__main__':
    unittest.main()
