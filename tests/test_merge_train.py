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

    def test_appends_to_the_playbook_by_two_lanes_both_land(self):
        playbook = 'docs/spring/performance-playbook.md'
        (self.work / 'docs' / 'spring').mkdir(parents=True)
        (self.work / playbook).write_text('# Playbook\n- R-1 old\n')
        git(self.work, 'checkout', '-q', '--detach', 'origin/main')
        git(self.work, 'add', '.')
        git(self.work, 'commit', '-q', '-m', 'playbook')
        git(self.work, 'push', '-q', 'origin', 'HEAD:main')
        self.lane('sol-a', {playbook: '# Playbook\n- R-1 old\n- R-2 from a\n'})
        self.lane('sol-b', {playbook: '# Playbook\n- R-1 old\n- R-3 from b\n'})
        self.hold_slot()
        result = self.train.run('runner')
        self.assertEqual((result['landed'], result['failed']), (['sol-a', 'sol-b'], []))
        text = git(self.work, 'show', f'origin/main:{playbook}')
        self.assertIn('R-2 from a', text)
        self.assertIn('R-3 from b', text)

    GENERATOR = """import json, pathlib
rows = sorted(json.loads(p.read_text())['id'] for p in pathlib.Path('api/deviations').glob('*.json'))
for out in ('docs/spring/java-differences.md', 'docs/spring/api-mapping.md'):
    path = pathlib.Path(out); path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('# generated\\n' + ''.join(f'- {r}\\n' for r in rows))
"""

    def test_a_conflict_only_in_generated_pages_is_regenerated(self):
        (self.work / 'tools').mkdir()
        (self.work / 'tools' / 'api_differences.py').write_text(self.GENERATOR)
        (self.work / 'api' / 'deviations').mkdir(parents=True)
        for page in ('java-differences.md', 'api-mapping.md'):
            (self.work / 'docs' / 'spring').mkdir(parents=True, exist_ok=True)
            (self.work / 'docs' / 'spring' / page).write_text('# generated\n')
        git(self.work, 'checkout', '-q', '--detach', 'origin/main')
        git(self.work, 'add', '.')
        git(self.work, 'commit', '-q', '-m', 'generator')
        git(self.work, 'push', '-q', 'origin', 'HEAD:main')
        for role, dev in (('sol-a', 'D-A-1'), ('sol-b', 'D-B-1')):
            self.lane(role, {f'api/deviations/{dev}.json': json.dumps({'id': dev}),
                             'docs/spring/java-differences.md': f'# generated\n- {dev}\n',
                             'docs/spring/api-mapping.md': f'# generated\n- {dev}\n'})
        self.hold_slot()
        result = self.train.run('runner')
        self.assertEqual((result['landed'], result['failed']), (['sol-a', 'sol-b'], []))
        page = git(self.work, 'show', 'origin/main:docs/spring/java-differences.md')
        self.assertEqual(page, '# generated\n- D-A-1\n- D-B-1')

    def test_a_conflict_beyond_the_generated_pages_still_fails(self):
        self.lane('sol-a', {'src/app.txt': 'a\n'})
        self.lane('sol-b', {'src/app.txt': 'b\n'})
        self.hold_slot()
        self.assertEqual(self.train.run('runner')['failed'], ['sol-b'])

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

    def test_a_failed_push_keeps_every_submission_queued_at_the_head_and_tells_the_lanes(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.lane('sol-b', {'src/b.txt': 'b'})
        self.hold_slot()
        self.train.push = lambda *args, **kwargs: None  # main never stops moving
        result = self.train.run('runner')
        self.assertEqual((result['landed'], result['failed']), ([], []))
        self.assertEqual([s['role'] for s in self.train.submissions()], ['sol-a', 'sol-b'])
        queue, _, _ = self.store.queue_view('apps-landing')
        self.assertEqual([m['agent'] for m in queue['members']][:2], ['sol-a', 'sol-b'])
        self.assertIn('could not land', self.store.inbox('sol-a', True, False))

    def test_submitting_joins_the_queue(self):
        git(self.work, 'checkout', '-q', '-B', 'sol-c', 'origin/main')
        git(self.work, 'checkout', '-q', '--detach')
        self.train.submit('sol-c', 'sol-c', 'sol-c')
        queue, _, _ = self.store.queue_view('apps-landing')
        self.assertIn('sol-c', [m['agent'] for m in queue['members']])

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

    def test_a_resubmission_during_a_run_stays_queued_for_the_next_train(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.hold_slot()
        train = self.train
        original = train.verify

        def verify(commit):  # sol-a resubmits a longer branch while the train is verifying the old one
            if train.verifications == 0:
                git(self.work, 'checkout', '-q', '-B', 'sol-a-more', 'sol-a')
                (self.work / 'src' / 'a2.txt').write_text('more')
                git(self.work, 'add', '.')
                git(self.work, 'commit', '-q', '-m', 'sol-a: more')
                git(self.work, 'checkout', '-q', '--detach')
                train.submit('sol-a', 'sol-a', 'sol-a-more')
            return original(commit)
        train.verify = verify
        result = train.run('runner')
        self.assertEqual(result['landed'], ['sol-a'])
        self.assertEqual(result['pending'], ['sol-a'])
        self.assertEqual(train.submissions()[0]['ref'], 'sol-a-more')
        queue, _, _ = self.store.queue_view('apps-landing')
        self.assertIn('sol-a', [m['agent'] for m in queue['members']])
        self.assertIn('newer submission stays queued', self.store.inbox('sol-a', True, False))
        train.verify = original
        self.assertEqual(train.run('runner')['landed'], ['sol-a'])  # the next train lands only the new commit
        self.assertEqual(self.main_log(), ['sol-a: more', 'sol-a: change', 'base'])

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
                       'rm -rf "$FLINT_CACHE"', 'benchmarks/spring/flint/*/.flint "$WT"'):
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

    class FakeVerifier:
        """Red when the candidate's tree has src/BAD; None (unavailable) when told to be."""

        def __init__(self, test, name, budget=False, unavailable=False):
            self.test, self.name, self.budget, self.unavailable = test, name, budget, unavailable
            self.seen = []

        def __call__(self, commit, repo):
            import threading
            self.seen.append((commit, threading.current_thread().name))
            if self.unavailable:
                return None, f'{self.name}: ssh failed'
            files = git(self.test.work, 'ls-tree', '-r', '--name-only', commit).split()
            return 'src/BAD' not in files, f'{self.name} verified {commit[:8]}'

    def stacked(self, *verifiers):
        return merge_train.Train(self.store, repo=self.work, worktree=self.tree, remote='origin', closure=('src/',),
                                 verifiers=list(verifiers))

    def test_two_verifiers_check_two_stacked_candidates_at_once_and_land_both(self):
        for i in range(6):
            self.lane(f'sol-{"abcdef"[i]}', {f'src/{i}.txt': str(i)})
        self.hold_slot()
        desktop, posidon = self.FakeVerifier(self, 'desktop'), self.FakeVerifier(self, 'posidon', budget=True)
        result = self.stacked(posidon, desktop).run('runner')
        self.assertEqual((len(result['landed']), result['verifications']), (6, 2))
        self.assertEqual((len(desktop.seen), len(posidon.seen)), (1, 1))
        files = lambda c: git(self.work, 'ls-tree', '-r', '--name-only', c).split()
        self.assertEqual(len([f for f in files(desktop.seen[0][0]) if f.startswith('src/') and f[4].isdigit()]), 4)
        self.assertEqual(posidon.seen[0][0], result['pushed'])  # the budget verifier saw the deepest candidate
        self.assertNotEqual(desktop.seen[0][1], posidon.seen[0][1])  # concurrently, on two threads

    def test_a_red_second_candidate_lands_the_first_and_bisects_its_own_group(self):
        for i, role in enumerate(('sol-a', 'sol-b', 'sol-c', 'sol-d', 'sol-e')):
            self.lane(role, {f'src/{i}.txt': str(i)})
        self.lane('sol-f', {'src/BAD': 'x'})
        self.hold_slot()
        result = self.stacked(self.FakeVerifier(self, 'desktop'), self.FakeVerifier(self, 'posidon', True)).run('runner')
        self.assertEqual(result['landed'], ['sol-a', 'sol-b', 'sol-c', 'sol-d', 'sol-e'])
        self.assertEqual(result['failed'], ['sol-f'])

    def test_a_red_first_candidate_holds_everything_stacked_on_it_for_re_verification(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.lane('sol-b', {'src/BAD': 'x'})
        for i, role in enumerate(('sol-c', 'sol-d', 'sol-e', 'sol-f')):
            self.lane(role, {f'src/{i}.txt': str(i)})
        self.hold_slot()
        result = self.stacked(self.FakeVerifier(self, 'desktop'), self.FakeVerifier(self, 'posidon', True)).run('runner')
        self.assertEqual((result['landed'], result['failed']), (['sol-a'], ['sol-b']))
        self.assertEqual(result['pending'], ['sol-c', 'sol-d', 'sol-e', 'sol-f'])

    class SlowAwareVerifier(FakeVerifier):
        """posidon's budget: red when the candidate has src/SLOW (an instruction regression acceptance can't see)."""

        def __call__(self, commit, repo):
            ok, log = super().__call__(commit, repo)
            files = git(self.test.work, 'ls-tree', '-r', '--name-only', commit).split()
            return (ok and 'src/SLOW' not in files), log

    def test_a_budget_failure_rechecks_a_prefix_only_acceptance_verified(self):
        for i, role in enumerate(('sol-a', 'sol-b', 'sol-c', 'sol-d', 'sol-e', 'sol-f')):
            self.lane(role, {'src/SLOW' if role == 'sol-b' else f'src/{i}.txt': str(i)})
        self.hold_slot()
        desktop = self.FakeVerifier(self, 'desktop')
        posidon = self.SlowAwareVerifier(self, 'posidon', budget=True)
        result = self.stacked(desktop, posidon).run('runner')
        self.assertEqual((result['landed'], result['failed']), (['sol-a'], ['sol-b']))
        self.assertEqual(result['pending'], ['sol-c', 'sol-d', 'sol-e', 'sol-f'])

    def test_a_budget_red_after_a_budget_green_prefix_bisects_only_the_red_group(self):
        for i, role in enumerate(('sol-a', 'sol-b', 'sol-c', 'sol-d', 'sol-e', 'sol-f')):
            self.lane(role, {'src/SLOW' if role == 'sol-f' else f'src/{i}.txt': str(i)})
        self.hold_slot()
        posidon = self.SlowAwareVerifier(self, 'posidon', budget=True)
        result = self.stacked(self.FakeVerifier(self, 'desktop'), posidon).run('runner')
        self.assertEqual((result['landed'], result['failed']), (['sol-a', 'sol-b', 'sol-c', 'sol-d', 'sol-e'], ['sol-f']))
        self.assertEqual(len(posidon.seen), 3)  # the deepest candidate, the prefix once, one step inside the red group

    def test_returned_lanes_do_not_block_the_scheduler(self):
        self.store.queue('apps-landing', 'front', 'sol-x')  # returned by a train, not resubmitted yet
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.store.queue('apps-landing', 'leave', 'sol-a')
        self.store.queue('apps-landing', 'join', 'sol-a')
        self.assertTrue(merge_train.next_train(self.store, self.train.submissions()))
        self.store.queue('apps-landing', 'join', 'hand-lander')
        self.store.queue('apps-landing', 'leave', 'sol-a')
        self.assertFalse(merge_train.next_train(self.store, self.train.submissions()))

    def test_an_unavailable_verifier_blames_nobody(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.lane('sol-b', {'src/b.txt': 'b'})
        self.hold_slot()
        result = self.stacked(self.FakeVerifier(self, 'desktop', unavailable=True)).run('runner')
        self.assertEqual((result['landed'], result['failed'], result['pending']), ([], [], ['sol-a', 'sol-b']))
        self.assertEqual(self.main_log(), ['base'])

    def test_a_verifier_entry_becomes_its_script(self):
        entry = {'name': 'desktop', 'host': 'sbuglione@10.10.10.122', 'push_to': 'flint-verifier/flint.git',
                 'bare': '$HOME/flint-verifier/flint.git', 'worktree': '$HOME/flint-verifier/wt-train',
                 'tools': '$HOME/flint-verifier/.tools', 'peers': '$HOME/flint-verifier/.flint/peers',
                 'native_install': '$HOME/flint-verifier/.native/install', 'prelude': 'export PATH="$HOME/x:$PATH"',
                 'receipts': {'flint-verifier/.tools/dmd2/linux/bin64/dmd': 'ab' * 32}}
        script = merge_train.RemoteVerifier(entry).script('c0ffee', 'train-x', 'S')
        self.assertIn('export PATH="$HOME/x:$PATH"', script)
        self.assertIn('--json', script)
        self.assertIn('--no-flint-budget', script)
        self.assertIn(f'{"ab" * 32}  flint-verifier/.tools/dmd2/linux/bin64/dmd', script)
        self.assertIn('[ "$REPO" = "$BARE" ]', script)
        posidon = merge_train.RemoteVerifier(merge_train.DEFAULT_VERIFIERS[0]).script('c0ffee', 'train-x', 'S')
        self.assertNotIn('--no-flint-budget', posidon)
        self.assertIn('source "$HOME/flint-work/posidon.env"', posidon)

    def test_verifiers_come_from_the_coordination_file(self):
        self.assertEqual([v.name for v in merge_train.load_verifiers(self.store)], ['posidon'])
        (self.store.root / 'train').mkdir(exist_ok=True)
        (self.store.root / 'train' / 'verifiers.json').write_text(json.dumps({'verifiers': [
            merge_train.DEFAULT_VERIFIERS[0], dict(merge_train.DEFAULT_VERIFIERS[0], name='desktop', budget=False),
            dict(merge_train.DEFAULT_VERIFIERS[0], name='neptune', enabled=False)]}))
        self.assertEqual([v.name for v in merge_train.load_verifiers(self.store)], ['posidon', 'desktop'])

    def test_only_build_relevant_changes_count_as_moving_the_closure(self):
        closure = merge_train.closure_paths(merge_train.ROOT)
        names = merge_train.closure_names(merge_train.ROOT)
        self.assertIn('web', names)
        same = lambda path: ('{"modules": {"web": {"a": 1}, "ai-core": {"a": 1}}}',) * 2
        ai_only = lambda path: ('{"modules": {"web": {"a": 1}}}', '{"modules": {"web": {"a": 1}, "ai-core": {}}}')
        web = lambda path: ('{"modules": {"web": {"a": 1}}}', '{"modules": {"web": {"a": 2}}}')
        quiet = ['policy/framework.json', 'policy/upstream-tests-baseline.json', 'policy/quality-baseline.json',
                 'framework/java/closure-baseline.json', 'framework/web/upstream-tests.json', 'docs/spring/x.md',
                 'apps/flint/test/flint_tool/api/api_test.d', 'apps/flint/src/flint_tool/api/coverage.d',
                 'framework/web/README.md']
        self.assertEqual(merge_train.build_relevant(quiet, closure, names, ai_only), [])
        self.assertEqual(merge_train.build_relevant(['policy/framework.json'], closure, names, web),
                         ['policy/framework.json'])
        self.assertEqual(merge_train.build_relevant(['framework/web/source/flint/web/package.d',
                                                     'policy/request-allocations.json', 'apps/flint/src/flint_tool/engine/builder.d'],
                                                    closure, names, same),
                         ['framework/web/source/flint/web/package.d', 'policy/request-allocations.json',
                          'apps/flint/src/flint_tool/engine/builder.d'])

    def test_only_one_scheduler_runs(self):
        import fcntl
        (self.store.root / 'train').mkdir(exist_ok=True)
        with open(self.store.root / 'train' / 'scheduler.lock', 'a+') as held:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            lines = []
            merge_train.serve(self.store, self.train, once=True, log=lines.append)
            self.assertIn('another scheduler holds', lines[0])

    def test_the_closure_covers_the_apps_packages_and_shared_paths(self):
        paths = merge_train.closure_paths(merge_train.ROOT)
        for expected in ('framework/web/', 'framework/jdbc/', 'boot/core/flint-boot/', 'policy/profiles.toml', 'benchmarks/spring/'):
            self.assertIn(expected, paths)
        self.assertEqual(merge_train.touches(['docs/x.md', 'framework/web/a.d'], paths), ['framework/web/a.d'])


if __name__ == '__main__':
    unittest.main()
