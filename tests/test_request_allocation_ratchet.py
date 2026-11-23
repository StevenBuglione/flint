"""Per-request allocation budgets only go down (owner decision 9a9aefa0): tools/request_allocation_ratchet.py."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import request_allocation_ratchet as ratchet  # noqa: E402


def git(root, *arguments):
    return subprocess.run(['git', *arguments], cwd=root, check=True, capture_output=True, text=True).stdout.strip()


class Repository:
    """A scratch repository with policy/request-allocations.json."""

    def __init__(self, directory):
        self.root = Path(directory)
        git(self.root, 'init', '--quiet')
        git(self.root, 'config', 'user.email', 'ratchet@example.invalid')
        git(self.root, 'config', 'user.name', 'ratchet test')
        (self.root / 'policy').mkdir()

    def write(self, requests):
        (self.root / ratchet.FILE).write_text(json.dumps({'apps': {'gs-rest-service': {'requests': {
            name: {'allocations': allocations, 'bytes': size} for name, (allocations, size) in requests.items()}}}}))

    def commit(self, requests, message):
        self.write(requests)
        git(self.root, 'add', '-A')
        git(self.root, 'commit', '--quiet', '-m', message)


class RequestAllocationRatchet(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.repo = Repository(self.directory.name)
        self.repo.commit({'default name': (32, 5080)}, 'budgets from the measured cost x1.25')

    def tearDown(self):
        self.directory.cleanup()

    def test_cuts_and_new_requests_pass(self):
        self.repo.commit({'default name': (20, 4000)}, 'a cut')
        self.repo.commit({'default name': (20, 4000), 'HEAD': (40, 9000)}, 'a new request starts at its first budget')
        self.assertEqual(ratchet.check(self.repo.root), [])

    def test_a_committed_raise_is_refused(self):
        self.repo.commit({'default name': (33, 5080)}, 'raise')
        problems = ratchet.check(self.repo.root)
        self.assertEqual(len(problems), 1, problems)
        self.assertIn('allocations budget raised from 32 to 33', problems[0])

    def test_a_raise_in_the_working_tree_is_refused(self):
        self.repo.write({'default name': (32, 6000)})
        problems = ratchet.check(self.repo.root)
        self.assertEqual(len(problems), 1, problems)
        self.assertIn('bytes budget raised from 5080 to 6000 in the working tree', problems[0])

    def test_lowering_then_raising_back_is_a_raise(self):
        self.repo.commit({'default name': (20, 5080)}, 'a cut')
        self.repo.commit({'default name': (32, 5080)}, 'back up')
        self.assertTrue(ratchet.check(self.repo.root))

    def test_a_copied_tree_says_it_cannot_check(self):
        with tempfile.TemporaryDirectory() as copy:
            self.assertIsNotNone(ratchet.not_applicable(copy))
            self.assertEqual(ratchet.check(copy), [])

    def test_the_real_policy_has_no_raise(self):
        self.assertEqual(ratchet.check(ROOT), [])


if __name__ == '__main__':
    unittest.main()
