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
        # Restacked behind the culprit and verified once more in this train (coordinator, 19:27Z).
        self.assertEqual((result['landed'], result['failed']), (['sol-a', 'sol-c', 'sol-d'], ['sol-b']))
        self.assertEqual(self.main_log(), ['sol-d: change', 'sol-c: change', 'sol-a: change', 'base'])
        self.assertEqual(result['pending'], [])
        self.assertEqual(result['verifications'], 4)  # the train, prefixes of 2 and 1, then the restack
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

    def test_adjacent_removals_from_a_shrink_only_id_list_both_land(self):
        (self.work / 'tools').mkdir()
        (self.work / 'tools' / 'api_differences.py').write_text('pass\n')
        (self.work / 'api').mkdir()
        ids = [f'java.util.X#m{i}()' for i in range(8)]
        unconfirmed = 'api/jdk-unconfirmed.json'
        dump = lambda keep: json.dumps({'note': 'n', 'ids': keep}, indent=1) + '\n'  # noqa: E731
        (self.work / unconfirmed).write_text(dump(ids))
        git(self.work, 'checkout', '-q', '--detach', 'origin/main')
        git(self.work, 'add', '.')
        git(self.work, 'commit', '-q', '-m', 'unconfirmed ids')
        git(self.work, 'push', '-q', 'origin', 'HEAD:main')
        # Adjacent lines: sol-a confirms m2 and m3, sol-b confirms m4 and adds nothing else.
        self.lane('sol-a', {unconfirmed: dump([i for i in ids if not i.endswith(('m2()', 'm3()'))])})
        self.lane('sol-b', {unconfirmed: dump([i for i in ids if not i.endswith('m4()')])})
        self.hold_slot()
        result = self.train.run('runner')
        self.assertEqual((result['landed'], result['failed']), (['sol-a', 'sol-b'], []))
        landed = json.loads(git(self.work, 'show', f'origin/main:{unconfirmed}'))
        self.assertEqual(landed['ids'], sorted(i for i in ids if not i.endswith(('m2()', 'm3()', 'm4()'))))
        self.assertEqual(landed['note'], 'n')

    def test_two_lanes_shrinking_the_upstream_tests_baseline_side_by_side_both_land_in_its_own_format(self):
        # sol-jackson, 2026-11-26: adjacent deletions by two lanes conflicted in policy/upstream-tests-baseline.json.
        path = 'policy/upstream-tests-baseline.json'
        base = {'schema': 'flint.upstream-tests-baseline/1', 'note': 'n',
                'modules': {'jackson-core': ['A.java', 'B.java', 'C.java', 'D.java'], 'web': ['W.java']}}
        (self.work / 'policy').mkdir(exist_ok=True)
        (self.work / path).write_text(json.dumps(base, indent=2) + '\n')
        (self.work / 'tools').mkdir(exist_ok=True)
        (self.work / 'tools' / 'api_differences.py').write_text('')  # the regeneration after a set merge: nothing here
        git(self.work, 'checkout', '-q', 'origin/main')
        git(self.work, 'add', '.')
        git(self.work, 'commit', '-q', '-m', 'baseline')
        git(self.work, 'push', '-q', 'origin', 'HEAD:main')
        git(self.work, 'fetch', '-q', 'origin')
        for role, drop in (('sol-a', 'B.java'), ('sol-b', 'C.java')):
            shrunk = json.loads(json.dumps(base))
            shrunk['modules']['jackson-core'].remove(drop)
            self.lane(role, {path: json.dumps(shrunk, indent=2) + '\n'})
        self.hold_slot()
        result = self.train.run('runner')
        self.assertEqual((result['landed'], result['failed']), (['sol-a', 'sol-b'], []))
        text = git(self.work, 'show', f'origin/main:{path}')
        self.assertEqual(json.loads(text)['modules']['jackson-core'], ['A.java', 'D.java'])
        self.assertEqual(list(json.loads(text)), ['schema', 'note', 'modules'])
        self.assertTrue(text.splitlines()[1].startswith('  "schema"'), text[:80])  # indent 2 kept, not reformatted

    def test_json_indent_follows_the_file(self):
        self.assertEqual(merge_train.json_indent('{\n  "a": 1\n}\n'), 2)
        self.assertEqual(merge_train.json_indent('{\n "a": 1\n}\n'), 1)
        self.assertEqual(merge_train.json_indent('[]\n'), 1)

    def test_merge_sets_keeps_both_sides_and_refuses_a_removed_entry_the_other_side_changed(self):
        base = {'note': 'n', 'ids': ['a', 'b', 'c', 'd']}
        self.assertEqual(merge_train.merge_sets(base, {'note': 'n', 'ids': ['a', 'c', 'd', 'e']},
                                                {'note': 'n', 'ids': ['a', 'b', 'd']}),
                         {'note': 'n', 'ids': ['a', 'd', 'e']})
        self.assertEqual(merge_train.merge_sets({'gaps': {'x': 1, 'y': 2}}, {'gaps': {'y': 2}},
                                                {'gaps': {'x': 1, 'y': 2, 'z': 3}}), {'gaps': {'y': 2, 'z': 3}})
        with self.assertRaises(merge_train.SetConflict):
            merge_train.merge_sets({'gaps': {'x': 1}}, {'gaps': {}}, {'gaps': {'x': 9}})
        with self.assertRaises(merge_train.SetConflict):
            merge_train.merge_sets({'note': 'a'}, {'note': 'b'}, {'note': 'c'})

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
                       'SHIMS="--shims-only"', '--repeat 5', 'decision 6478897a', '[ "full" = budget ]',
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

    def test_a_restack_that_fails_again_is_bisected_without_a_second_restack(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.lane('sol-b', {'src/BAD': 'b'})
        self.lane('sol-c', {'src/c.txt': 'c'})
        self.lane('sol-d', {'src/BAD': 'd'})
        self.hold_slot()
        result = self.train.run('runner')
        self.assertEqual((result['landed'], sorted(result['failed'])), (['sol-a', 'sol-c'], ['sol-b', 'sol-d']))
        events = [json.loads(line) for line in (self.store.root / 'events.jsonl').read_text().splitlines()]
        self.assertEqual([e['culprit'] for e in events if e['event'] == 'train-restack'], ['sol-b'])

    def test_a_red_first_candidate_holds_everything_stacked_on_it_for_re_verification(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.lane('sol-b', {'src/BAD': 'x'})
        for i, role in enumerate(('sol-c', 'sol-d', 'sol-e', 'sol-f')):
            self.lane(role, {f'src/{i}.txt': str(i)})
        self.hold_slot()
        result = self.stacked(self.FakeVerifier(self, 'desktop'), self.FakeVerifier(self, 'posidon', True)).run('runner')
        # Restacked behind the culprit and verified once more in this train (coordinator, 19:27Z).
        self.assertEqual((result['landed'], result['failed']), (['sol-a', 'sol-c', 'sol-d', 'sol-e', 'sol-f'], ['sol-b']))

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
        # Restacked behind the culprit and verified once more in this train (coordinator, 19:27Z).
        self.assertEqual((result['landed'], result['failed']), (['sol-a', 'sol-c', 'sol-d', 'sol-e', 'sol-f'], ['sol-b']))

    def test_a_budget_red_after_a_budget_green_prefix_bisects_only_the_red_group(self):
        for i, role in enumerate(('sol-a', 'sol-b', 'sol-c', 'sol-d', 'sol-e', 'sol-f')):
            self.lane(role, {'src/SLOW' if role == 'sol-f' else f'src/{i}.txt': str(i)})
        self.hold_slot()
        posidon = self.SlowAwareVerifier(self, 'posidon', budget=True)
        result = self.stacked(self.FakeVerifier(self, 'desktop'), posidon).run('runner')
        self.assertEqual((result['landed'], result['failed']), (['sol-a', 'sol-b', 'sol-c', 'sol-d', 'sol-e'], ['sol-f']))
        self.assertEqual(len(posidon.seen), 3)  # the deepest candidate, the prefix once, one step inside the red group

    class ModalVerifier(SlowAwareVerifier):
        """posidon with modes: records (mode, apps) per call; its red verdicts carry a flint budget report."""
        supports_modes = True

        def __call__(self, commit, repo, mode='full', apps=None, tight=None):
            ok, log = super().__call__(commit, repo)
            self.modes = getattr(self, 'modes', []) + [(mode, tuple(apps or ()))]
            if not ok:
                report = {'schema': 'flint.budget/1-report', 'failed': False,
                          'problems': ["petclinic-rest: 'list vets': instructions 407,377 -> 412,348 (+1.22%, tolerance +1.00%)"]}
                log += '\n' + json.dumps(report)
            return ok, log

    def test_a_red_stack_checks_main_then_bisects_with_flint_budget_alone(self):
        for i, role in enumerate(('sol-a', 'sol-b', 'sol-c', 'sol-d', 'sol-e')):
            self.lane(role, {'src/SLOW' if role == 'sol-b' else f'src/{i}.txt': str(i)})
        self.hold_slot()
        posidon = self.ModalVerifier(self, 'posidon', budget=True)
        result = self.stacked(self.FakeVerifier(self, 'desktop'), posidon).run('runner')
        # Restacked behind the culprit and verified once more in this train (coordinator, 19:27Z).
        self.assertEqual((result['landed'], result['failed']), (['sol-a', 'sol-c', 'sol-d'], ['sol-b']))
        self.assertEqual(result['pending'], ['sol-e'])  # one acceptance verifier: a batch of four
        both = ('budget', tuple(merge_train.APPS))
        # The whole stack (red), main (green), then budget-only steps for the app that missed: a,b red, then a green.
        self.assertEqual(posidon.modes[:4], [both, both, ('budget', ('petclinic-rest',)), ('budget', ('petclinic-rest',))])
        self.assertNotIn('train-screened', (self.store.root / 'events.jsonl').read_text())
        mail = self.store.inbox('sol-b', True, False)
        self.assertIn("petclinic-rest 'list vets' 407,377 -> 412,348 (+1.22%, tolerance 1.00%)", mail)

    def test_a_new_package_is_not_screened(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.lane('sol-b', {'docs/b.md': 'b'})  # outside the closure ('src/')
        self.hold_slot()
        posidon = self.ModalVerifier(self, 'posidon', budget=True)
        result = self.stacked(self.FakeVerifier(self, 'desktop'), posidon).run('runner')
        self.assertEqual(result['landed'], ['sol-a', 'sol-b'])
        self.assertEqual(posidon.modes, [('budget', tuple(merge_train.APPS))])  # the stack once, green: no screens

    def test_a_green_stack_lands_on_one_posidon_run_without_screens(self):
        for i, role in enumerate(('sol-a', 'sol-b', 'sol-c', 'sol-d')):
            self.lane(role, {f'src/{i}.txt': str(i)})
        self.hold_slot()
        posidon = self.ModalVerifier(self, 'posidon', budget=True)
        result = self.stacked(self.FakeVerifier(self, 'desktop'), posidon).run('runner')
        self.assertEqual(result['landed'], ['sol-a', 'sol-b', 'sol-c', 'sol-d'])
        self.assertEqual(posidon.modes, [('budget', tuple(merge_train.APPS))])
        events = [json.loads(line)['event'] for line in (self.store.root / 'events.jsonl').read_text().splitlines()]
        self.assertNotIn('train-screened', events)

    def test_an_acceptance_failure_with_a_red_stack_budget_checks_the_green_prefix(self):
        for i, role in enumerate(('sol-a', 'sol-b', 'sol-c', 'sol-d', 'sol-e', 'sol-f')):
            self.lane(role, {'src/SLOW' if role == 'sol-a' else 'src/BAD' if role == 'sol-f' else f'src/{i}.txt': str(i)})
        self.hold_slot()
        desktop, neptune = self.FakeVerifier(self, 'desktop'), self.FakeVerifier(self, 'neptune')
        posidon = self.ModalVerifier(self, 'posidon', budget=True)
        result = self.stacked(desktop, neptune, posidon).run('runner')
        # sol-f fails acceptance on neptune and is bisected there; the acceptance-green prefix (sol-a..sol-e) is
        # budget-checked, red, then main is checked and the prefix bisected with flint budget: sol-a goes back, and
        # the lanes behind it are restacked and land in this train.
        self.assertEqual(sorted(result['failed']), ['sol-a', 'sol-f'])
        self.assertEqual((result['landed'], result['pending']), (['sol-b', 'sol-c', 'sol-d', 'sol-e'], []))
        self.assertTrue(all(mode[0] == 'budget' for mode in posidon.modes[:3]), posidon.modes)

    def test_a_budget_only_failure_is_bisected_with_flint_budget_alone(self):
        for i, role in enumerate(('sol-a', 'sol-b', 'sol-c', 'sol-d')):
            self.lane(role, {'src/SLOW' if role == 'sol-c' else f'src/{i}.txt': str(i)})
        self.hold_slot()
        posidon = self.ModalVerifier(self, 'posidon', budget=True)  # posidon alone: no screening, the stacked path
        result = self.stacked(posidon).run('runner')
        # Restacked behind the culprit and verified once more in this train (coordinator, 19:27Z).
        self.assertEqual((result['landed'], result['failed']), (['sol-a', 'sol-b', 'sol-d'], ['sol-c']))
        self.assertEqual(posidon.modes[0][0], 'full')
        # The bisect steps run flint budget alone; the restack is a full verification again.
        steps = posidon.modes[1:-1]
        self.assertTrue(steps and all(mode == ('budget', ('petclinic-rest',)) for mode in steps), posidon.modes)
        self.assertEqual(posidon.modes[-1][0], 'full')

    def playbook_base(self, rows):
        path = self.work / 'docs' / 'spring' / 'performance-playbook.md'
        path.parent.mkdir(parents=True, exist_ok=True)
        self.playbook_text = '# Playbook\n\n| ID | Entry |\n| --- | --- |\n' + ''.join(f'| {r} | {r} entry |\n' for r in rows)
        path.write_text(self.playbook_text)
        git(self.work, 'checkout', '-q', 'origin/main')
        git(self.work, 'add', '.')
        git(self.work, 'commit', '-q', '-m', 'playbook')
        git(self.work, 'push', '-q', 'origin', 'HEAD:main')
        git(self.work, 'fetch', '-q', 'origin')
        return path

    def edited(self, path, row, text):
        return self.playbook_text.replace(f'| {row} | {row} entry |', f'| {row} | {text} |')

    def test_rows_both_sides_edited_get_one_row_per_id_and_conflicts_name_paths(self):
        path = self.playbook_base(['S-1', 'S-2', 'S-3'])
        playbook = 'docs/spring/performance-playbook.md'
        self.lane('sol-a', {playbook: self.edited(path, 'S-1', 'S-1 entry, extended by a')})
        self.lane('sol-b', {playbook: self.edited(path, 'S-2', 'S-2 entry, extended by b')})
        self.lane('sol-c', {playbook: self.edited(path, 'S-1', 'S-1 entry, rewritten by c')})
        self.hold_slot()
        result = self.train.run('runner')
        self.assertEqual((result['landed'], result['failed']), (['sol-a', 'sol-b'], ['sol-c']))
        git(self.work, 'fetch', '-q', 'origin')
        text = git(self.work, 'show', f'origin/main:{playbook}')
        rows = merge_train.id_rows(text)
        self.assertEqual({k: len(v) for k, v in rows.items()}, {'S-1': 1, 'S-2': 1, 'S-3': 1})
        self.assertIn('extended by a', rows['S-1'][0])
        self.assertIn('extended by b', rows['S-2'][0])
        self.assertIn(f'{playbook} S-1', Path(result['logs']['sol-c']).read_text())

    def test_a_main_that_misses_its_budget_returns_no_screened_lane_only_conflicts(self):
        # 16:45Z: main a2c47a78 was red; screening every submission alone on it would have returned each for main's miss.
        (self.work / 'src' / 'SLOW').write_text('main')
        git(self.work, 'checkout', '-q', 'origin/main')
        git(self.work, 'add', '.')
        git(self.work, 'commit', '-q', '-m', 'main regresses')
        git(self.work, 'push', '-q', 'origin', 'HEAD:main')
        git(self.work, 'fetch', '-q', 'origin')
        self.store.register('coordinator', 'coordinator', None, None)
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.lane('sol-b', {'src/app.txt': 'b\n'})
        self.lane('sol-c', {'src/app.txt': 'c\n'})
        self.hold_slot()
        posidon = self.ModalVerifier(self, 'posidon', budget=True)
        result = self.stacked(self.FakeVerifier(self, 'desktop'), posidon).run('runner')
        self.assertIn('main_red', result)
        self.assertEqual((result['landed'], result['failed']), ([], ['sol-c']))  # only the real conflict goes back
        self.assertEqual(sorted(s['role'] for s in self.store._read_json('train.json', {})['submissions']),
                         ['sol-a', 'sol-b'])
        self.assertIn('list vets', Path(result['main_red_log']).read_text())
        self.assertIn('itself fails verification', self.store.inbox('coordinator', True, False))
        self.assertNotIn('train-screened', (self.store.root / 'events.jsonl').read_text())

    def test_a_reused_entry_id_and_a_real_conflict_are_returned_with_their_paths(self):
        path = self.playbook_base(['S-1'])
        playbook = 'docs/spring/performance-playbook.md'
        self.lane('sol-a', {playbook: self.playbook_text + '| S-1 | a second entry under a taken ID |\n'})
        self.lane('sol-b', {'src/app.txt': 'b\n'})
        self.lane('sol-c', {'src/app.txt': 'c\n'})
        self.hold_slot()
        result = self.train.run('runner')
        self.assertEqual((result['landed'], sorted(result['failed'])), (['sol-b'], ['sol-a', 'sol-c']))
        self.assertIn('S-1 (duplicate entry ID', Path(result['logs']['sol-a']).read_text())
        self.assertIn('conflict) in: src/app.txt', Path(result['logs']['sol-c']).read_text())

    def test_merge_rows_keeps_old_collisions_and_reports_both_sided_changes(self):
        base = '| B-10 | one |\n| B-10 | two |\n| S-1 | s |\n'
        ours = '| B-10 | one |\n| B-10 | two |\n| S-1 | s, ours |\n'
        theirs = '| B-10 | one |\n| B-10 | two |\n| S-1 | s, theirs |\n'
        union = '| B-10 | one |\n| B-10 | two |\n| S-1 | s, ours |\n| S-1 | s, theirs |\n'
        self.assertEqual(merge_train.merge_rows(union, base, ours, theirs), (union, ['S-1']))
        deleted = '| B-10 | one |\n| B-10 | two |\n'
        self.assertEqual(merge_train.merge_rows(union.replace('| S-1 | s, ours |\n', '| S-1 | s |\n'), base, base,
                                                theirs)[0], deleted + '| S-1 | s, theirs |\n')

    def test_module_probes_block_only_on_a_breach_they_attribute(self):
        script = merge_train.RemoteVerifier(dict(merge_train.DEFAULT_VERIFIERS[0])).script('c', 'r', 's', base='b' * 40)
        probes = script[script.index('== module probes against main'):]
        probes = probes[:probes.index('\n  fi\n')]
        self.assertIn('--base "' + 'b' * 40 + '"', probes)
        self.assertIn('[ $mrc -eq 1 ] && exit 1', probes)
        self.assertNotIn('exit 3', probes)  # could not run (2): not judged, never a failed verifier

    def test_the_load_guard_marks_a_busy_run_not_quiet(self):
        s = merge_train.VERIFY_SCRIPT
        functions = s[s.index('LOAD_MEAN=0.5'):s.index('\n}\n', s.index('load_stop() {')) + 3]
        with tempfile.TemporaryDirectory() as work:
            for samples, quiet in (('0\n0\n1\n0\n', True), ('13\n12\n13\n', False), ('0\n0\n6\n0\n0\n0\n', False)):
                cache = Path(work) / 'cache'
                (Path(work) / 'cache.load').write_text(samples)
                (Path(work) / 'cache.noisy').unlink(missing_ok=True)
                done = subprocess.run(['bash', '-c', f'FLINT_CACHE={cache}; LOAD_PID=; {functions}\nload_stop'],
                                      capture_output=True, text=True)
                self.assertIn('NOT quiet' if not quiet else ': quiet', done.stdout, samples)
                self.assertEqual((Path(work) / 'cache.noisy').exists(), not quiet, samples)
        # A run that was not quiet writes no tight endpoints, so its borderline misses get the median re-measure.
        self.assertIn('TIGHTFILE="$FLINT_CACHE.notight.json"', s)
        self.assertLess(s.index('load_start; $H flint budget "$@" --report'), s.index('cat > "$FLINT_CACHE.tight.json"'))

    def test_main_s_open_misses_are_judged_relative_to_main(self):
        s = merge_train.VERIFY_SCRIPT
        start = s.index("<<'PY'\n", s.index('TIGHT\n  apps=')) + len("<<'PY'\n")
        classifier = s[start:s.index('\nPY\n', start)]
        work = Path(self.temp.name) / 'relative'
        (work / 'benchmarks' / 'spring').mkdir(parents=True)
        (work / 'benchmarks' / 'spring' / 'train-budget-relative.json').write_text(json.dumps({'endpoints': {
            'gs-rest-service': {'name with spaces and plus': {'main': 24097, 'tolerance': 0.005}}}}))
        (work / 'tight.json').write_text('{}')

        def judge(*problems, final=False):
            (work / 'report.json').write_text(json.dumps({'schema': 'flint.budget/1-report', 'problems': list(problems)}))
            done = subprocess.run([sys.executable, '-c', classifier, 'report.json', 'tight.json', *(['final'] if final else [])],
                                  cwd=work, capture_output=True, text=True)
            return done.returncode, done.stdout.strip()
        main_miss = "gs-rest-service: 'name with spaces and plus': instructions 23,968 -> 24,106 (+0.58%, tolerance +0.50%)"
        worse = "gs-rest-service: 'name with spaces and plus': instructions 23,968 -> 24,400 (+1.80%, tolerance +0.50%)"
        other = "gs-rest-service: 'JSON escaping': instructions 24,630 -> 24,800 (+0.69%, tolerance +0.50%)"
        self.assertEqual(judge(main_miss), (0, 'RELATIVE-GREEN'))
        self.assertEqual(judge(worse)[0], 1)  # past main by more than the tolerance, and not borderline
        self.assertEqual(judge(main_miss, other), (0, 'gs-rest-service'))  # the other one is re-measured
        self.assertEqual(judge(main_miss, final=True), (0, 'RELATIVE-GREEN'))
        self.assertEqual(judge(other, final=True)[0], 1)

    def test_budget_logs_are_parsed(self):
        dod = json.dumps({'steps': [{'step': 'apps', 'details': {'petclinic-rest allocation tests': 'pass',
                                                                  'petclinic-rest flint budget': 'regression'},
                                     'messages': ["  budget: petclinic-rest: 'wrong method': instructions 169,195 -> 174,773 (+3.30%, tolerance +1.00%)"]}]})
        self.assertEqual(merge_train.budget_only_apps('noise ' + dod), ['petclinic-rest'])
        mixed = dod.replace('"pass"', '"exit 3"')
        self.assertIsNone(merge_train.budget_only_apps(mixed))
        self.assertEqual(merge_train.budget_misses(dod), [('petclinic-rest', 'wrong method', '169,195', '174,773', 3.3, 1.0)])
        (self.store.root / 'train').mkdir(exist_ok=True)
        (self.store.root / 'train' / 'budget-spread.json').write_text(json.dumps(
            {'spread': {'petclinic-rest': {'list vets': 0.0003, 'create owner: telephone with letters': 0.012}}}))
        self.assertEqual(merge_train.tight_endpoints(self.store), {'petclinic-rest': ['list vets']})

    def test_a_paused_queue_starts_no_train(self):
        self.lane('sol-a', {'src/a.txt': 'a'})
        self.store.queue('apps-landing', 'pause', 'proof-harness')
        self.assertFalse(merge_train.next_train(self.store, self.train.submissions()))
        self.store.queue('apps-landing', 'resume', 'proof-harness')
        self.assertTrue(merge_train.next_train(self.store, self.train.submissions()))

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
        new_package = lambda path: ('subPackage "framework/web"\n', 'subPackage "framework/web"\nsubPackage "framework/micrometer-commons"\n')
        self.assertEqual(merge_train.build_relevant(['dub.sdl'], closure, names, new_package), [])
        app_package = lambda path: ('dflags "-a"\n', 'dflags "-b"\n')
        self.assertEqual(merge_train.build_relevant(['dub.sdl'], closure, names, app_package), ['dub.sdl'])
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
