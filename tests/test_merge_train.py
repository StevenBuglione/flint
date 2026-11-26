"""tools/merge_train.py: the apps-landing merge train, on real temporary git repositories with a stub verification."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import agentctl  # noqa: E402
import merge_train  # noqa: E402


def git(cwd, *args):
    return subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


class TrainTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        identity = {'GIT_AUTHOR_NAME': 'lane', 'GIT_AUTHOR_EMAIL': 'lane@example.invalid',
                    'GIT_COMMITTER_NAME': 'train', 'GIT_COMMITTER_EMAIL': 'train@example.invalid'}
        for key, value in identity.items():
            self.addCleanup(os.environ.pop, key, None) if key not in os.environ else None
            os.environ[key] = value
        self.remote, self.work, self.tree = base / 'remote.git', base / 'work', base / 'train'
        git(base, 'init', '-q', '--bare', '-b', 'main', str(self.remote))
        git(base, 'clone', '-q', str(self.remote), str(self.work))
        (self.work / 'src').mkdir()
        (self.work / 'src' / 'app.txt').write_text('base\n')
        git(self.work, 'add', '.')
        git(self.work, 'commit', '-q', '-m', 'base')
        git(self.work, 'push', '-q', 'origin', 'HEAD:main')
        git(self.work, 'worktree', 'add', '-q', '--detach', str(self.tree), 'origin/main')
        self.store = agentctl.Store(base / 'coordination')
        self.store.register('apps-landing', 'landing mutex', None, None, queued=True)
        for role in ('sol-a', 'sol-b', 'sol-c', 'sol-d', 'sol-e'):
            self.store.register(role, role, None, None)
        self.train = merge_train.Train(self.store, repo=self.work, worktree=self.tree, remote='origin',
                                       verify=['test ! -e src/BAD'], closure=('src/',), mail=True)

    def lane(self, role, files, parent='origin/main'):
        """A ready branch: one commit on `parent` writing `files` ({path: text})."""
        git(self.work, 'checkout', '-q', '-B', role, parent)
        for path, text in files.items():
            (self.work / path).parent.mkdir(parents=True, exist_ok=True)
            (self.work / path).write_text(text)
        git(self.work, 'add', '.')
        git(self.work, 'commit', '-q', '-m', f'{role}: change')
        git(self.work, 'checkout', '-q', '--detach')
        for agent in [role]:
            self.store.queue('apps-landing', 'join', agent)
        self.train.submit(role, role, role)

    def hold_slot(self):
        queue, _, _ = self.store.queue_view('apps-landing')
        for member in queue['members']:
            self.store.queue('apps-landing', 'leave', member['agent'])
        self.store.claim('apps-landing', 'runner', 'codex', None, 40)
        # Rejoin so queue order still means submission order.
        for s in self.store._read_json('train.json', {})['submissions']:
            self.store.queue('apps-landing', 'join', s['agent'])

    def main_log(self):
        git(self.work, 'fetch', '-q', 'origin')
        return git(self.work, 'log', '--format=%s', 'origin/main').splitlines()

    def test_a_green_train_lands_every_submission_in_queue_order_with_one_verification(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.lane('sol-b', {'src/b.txt': 'b'})
        self.lane('sol-c', {'docs/c.txt': 'c'})
        self.hold_slot()
        result = self.train.run('runner')
        self.assertEqual((result['landed'], result['failed'], result['verifications']), (['sol-a', 'sol-b', 'sol-c'], [], 1))
        self.assertEqual(self.main_log(), ['sol-c: change', 'sol-b: change', 'sol-a: change', 'base'])
        self.assertEqual(self.train.submissions(), [])
        self.assertIn('landed on main', self.store.inbox('sol-b', True, False))

    def test_a_red_train_bisects_lands_the_green_prefix_and_returns_the_culprit_to_the_head(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.lane('sol-b', {'src/BAD': 'breaks the apps'})
        self.lane('sol-c', {'src/c.txt': 'c'})
        self.lane('sol-d', {'src/d.txt': 'd'})
        self.hold_slot()
        result = self.train.run('runner')
        self.assertEqual((result['landed'], result['failed']), (['sol-a'], ['sol-b']))
        self.assertEqual(self.main_log(), ['sol-a: change', 'base'])
        self.assertEqual(result['pending'], ['sol-c', 'sol-d'])
        self.assertEqual(result['verifications'], 3)  # the train, then prefixes of 2 and 1
        queue, _, _ = self.store.queue_view('apps-landing')
        self.assertEqual(queue['members'][0]['agent'], 'sol-b')
        log = Path(result['logs']['sol-b']).read_text()
        self.assertIn('test ! -e src/BAD', log)
        self.assertIn('back at the head', self.store.inbox('sol-b', True, False))

    def test_a_red_main_blames_nobody(self):
        (self.work / 'src' / 'BAD').write_text('main broke')
        git(self.work, 'checkout', '-q', '--detach', 'origin/main')
        git(self.work, 'add', '.')
        git(self.work, 'commit', '-q', '-m', 'main breaks')
        git(self.work, 'push', '-q', 'origin', 'HEAD:main')
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.lane('sol-b', {'src/b.txt': 'b'})
        self.hold_slot()
        result = self.train.run('runner')
        self.assertEqual((result['landed'], result['failed'], result['pending']), ([], [], ['sol-a', 'sol-b']))
        self.assertIn('main_red', result)

    def test_a_conflicting_submission_fails_alone(self):
        self.lane('sol-a', {'src/app.txt': 'a\n'})
        self.lane('sol-b', {'src/app.txt': 'b\n'})
        self.lane('sol-c', {'src/c.txt': 'c'})
        self.hold_slot()
        result = self.train.run('runner')
        self.assertEqual((result['landed'], result['failed']), (['sol-a', 'sol-c'], ['sol-b']))
        self.assertIn('conflict', Path(result['logs']['sol-b']).read_text())

    def test_commits_already_on_main_drop_out_of_a_submission(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        git(self.work, 'push', '-q', 'origin', 'sol-a:main')  # sol-a pushed by itself meanwhile
        self.lane('sol-b', {'src/b.txt': 'b'}, parent='sol-a')
        self.hold_slot()
        result = self.train.run('runner')
        self.assertEqual(result['landed'], ['sol-a', 'sol-b'])
        self.assertEqual(self.main_log(), ['sol-b: change', 'sol-a: change', 'base'])

    def move_main(self, path):
        other = Path(self.temp.name) / f'other-{path.replace("/", "-")}'
        git(self.temp.name, 'clone', '-q', str(self.remote), str(other))
        (other / path).parent.mkdir(parents=True, exist_ok=True)
        (other / path).write_text('elsewhere')
        git(other, 'add', '.')
        git(other, 'commit', '-q', '-m', f'elsewhere: {path}')
        git(other, 'push', '-q', 'origin', 'HEAD:main')

    def moving_train(self, path):
        train = self.train
        original = train.verify

        def verify(commit):
            if train.verifications == 0:
                self.move_main(path)
            return original(commit)
        train.verify = verify
        return train

    def test_main_moving_outside_the_closure_lands_without_a_second_verification(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.hold_slot()
        result = self.moving_train('docs/readme.txt').run('runner')
        self.assertEqual((result['landed'], result['verifications']), (['sol-a'], 1))
        self.assertEqual(self.main_log(), ['sol-a: change', 'elsewhere: docs/readme.txt', 'base'])

    def test_main_moving_inside_the_closure_verifies_again(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.hold_slot()
        result = self.moving_train('src/other.txt').run('runner')
        self.assertEqual((result['landed'], result['verifications']), (['sol-a'], 2))

    def test_the_train_needs_the_slot(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        with self.assertRaises(SystemExit) as refused:
            self.train.run('runner')
        self.assertIn('claim apps-landing', str(refused.exception))

    def test_at_most_four_board_a_train_and_dry_run_changes_nothing(self):
        for role in ('sol-a', 'sol-b', 'sol-c', 'sol-d', 'sol-e'):
            self.lane(role, {f'src/{role}.txt': role})
        self.hold_slot()
        self.assertEqual(self.train.run('runner', dry_run=True), {'batch': ['sol-a', 'sol-b', 'sol-c', 'sol-d']})
        self.assertEqual(self.main_log(), ['base'])
        result = self.train.run('runner')
        self.assertEqual((result['landed'], result['pending']), (['sol-a', 'sol-b', 'sol-c', 'sol-d'], ['sol-e']))

    def test_a_resubmission_replaces_the_role_s_earlier_one(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        first = self.train.submissions()[0]['commit']
        self.store.queue('apps-landing', 'leave', 'sol-a')
        self.lane('sol-a', {'src/a.txt': 'a2'})
        submissions = self.train.submissions()
        self.assertEqual(len(submissions), 1)
        self.assertNotEqual(submissions[0]['commit'], first)

    def fake_posidon(self, status):
        """A posidon stand-in: `host` is a local bare repository, and `ssh` records the script it is given."""
        base = Path(self.temp.name)
        bare = base / 'posidon.git'
        if not bare.exists():
            git(base, 'init', '-q', '--bare', str(bare))
        recorder = base / 'fake_ssh.py'
        recorder.write_text('import sys\nopen(sys.argv[1], "a").write(sys.stdin.read() + "\\n====\\n")\n'
                            f'sys.exit({status})\n')
        self.scripts = base / 'scripts.txt'
        return merge_train.PosidonVerifier(host='posidon', url=str(bare),
                                           ssh=[sys.executable, str(recorder), str(self.scripts)]), bare

    def test_the_verification_runs_on_posidon_and_lands_only_when_green(self):
        verifier, bare = self.fake_posidon(0)
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.hold_slot()
        train = merge_train.Train(self.store, repo=self.work, worktree=self.tree, remote='origin', closure=('src/',),
                                  verifier=verifier)
        result = train.run('runner')
        self.assertEqual((result['landed'], result['verifications']), (['sol-a'], 1))
        script = self.scripts.read_text()
        tip = git(self.work, 'rev-parse', 'origin/main')
        self.assertIn(f'git checkout -q -f --detach "{tip}"', script)
        for needed in ('source "$HOME/flint-work/posidon.env"', 'export FLINT_HOME="$WT"', 'measure_queue.py hold --',
                       '--emit-dub', '--step apps --apps gs-rest-service,petclinic-rest', 'trap cleanup EXIT',
                       'SHIMS="--shims-only"',
                       'rm -rf "$FLINT_CACHE"'):
            self.assertIn(needed, script)
        self.assertIn('refs/heads/train-', git(bare, 'for-each-ref', '--format=%(refname)'))

    def test_a_red_posidon_verification_lands_nothing(self):
        verifier, _ = self.fake_posidon(1)
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.hold_slot()
        train = merge_train.Train(self.store, repo=self.work, worktree=self.tree, remote='origin', closure=('src/',),
                                  verifier=verifier)
        result = train.run('runner')  # always red, so main is red too: nothing lands and nobody is blamed
        self.assertEqual((result['landed'], result['failed'], result['pending']), ([], [], ['sol-a']))
        self.assertEqual(self.main_log(), ['base'])
        self.assertEqual(result['verifications'], 2)

    def test_the_scheduler_runs_only_for_a_free_slot_whose_head_submitted(self):
        self.assertFalse(merge_train.next_train(self.store, []))
        self.store.queue('apps-landing', 'join', 'hand-lander')
        self.lane('sol-a', {'src/a.txt': 'a'})
        subs = self.train.submissions()
        self.assertFalse(merge_train.next_train(self.store, subs))  # the hand-lander's turn
        self.store.queue('apps-landing', 'leave', 'hand-lander')
        self.assertTrue(merge_train.next_train(self.store, subs))
        self.store.claim('apps-landing', 'someone', 'codex', 'test: a hand landing in progress', 40)
        self.assertFalse(merge_train.next_train(self.store, subs))

    def test_one_scheduler_pass_lands_the_train_and_frees_the_slot(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.lane('sol-b', {'src/b.txt': 'b'})
        lines = []
        merge_train.serve(self.store, self.train, once=True, log=lines.append)
        self.assertEqual(self.main_log(), ['sol-b: change', 'sol-a: change', 'base'])
        self.assertNotIn('apps-landing', self.store.leases())
        queue, _, _ = self.store.queue_view('apps-landing')
        self.assertEqual(queue['members'], [])
        self.assertIn('"landed": ["sol-a", "sol-b"]', lines[0])

    def test_the_closure_covers_the_apps_packages_and_shared_paths(self):
        paths = merge_train.closure_paths(merge_train.ROOT)
        for expected in ('framework/web/', 'framework/jdbc/', 'boot/core/flint-boot/', 'policy/', 'benchmarks/spring/'):
            self.assertIn(expected, paths)
        self.assertEqual(merge_train.touches(['docs/x.md', 'framework/web/a.d'], paths), ['framework/web/a.d'])


if __name__ == '__main__':
    unittest.main()
