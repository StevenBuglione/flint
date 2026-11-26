"""tools/module_probes.py: which modules a candidate touches, and which cap breaches are the candidate's."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import module_probes  # noqa: E402


class Judging(unittest.TestCase):
    CAPS = {'aop': {'incremental_linked_bytes': 16384, 'template_instances': 1530},
            'security-core': {'incremental_linked_bytes': 4096, 'template_instances': 2800}}

    def test_a_new_breach_fails_and_names_main_within_cap(self):
        head = {'aop': {'incremental_linked_bytes': 21769, 'template_instances': 1538}}
        base = {'aop': {'incremental_linked_bytes': 11480, 'template_instances': 1520}}
        found = module_probes.judge(head, self.CAPS, base)
        self.assertEqual([(m, k) for m, k, *_ in found], [('aop', 'incremental_linked_bytes'), ('aop', 'template_instances')])

    def test_main_s_own_breach_does_not_fail_a_candidate_unless_it_grows(self):
        base = {'security-core': {'incremental_linked_bytes': 2821, 'template_instances': 2900}}
        same = {'security-core': {'incremental_linked_bytes': 2821, 'template_instances': 2900}}
        fixed = {'security-core': {'incremental_linked_bytes': 2821, 'template_instances': 2790}}
        worse = {'security-core': {'incremental_linked_bytes': 2821, 'template_instances': 2950}}
        self.assertEqual(module_probes.judge(same, self.CAPS, base), [])
        self.assertEqual(module_probes.judge(fixed, self.CAPS, base), [])
        self.assertEqual([k for _, k, *_ in module_probes.judge(worse, self.CAPS, base)], ['template_instances'])

    def test_an_open_breach_growing_a_little_is_a_notice_not_a_failure(self):
        # 5a2d60f43 on real probes: web 528,985 -> 529,073 (cap 126,976); aop 11,360 -> 21,729 (cap 11,537).
        caps = {'web': {'incremental_linked_bytes': 126976}, 'aop': {'incremental_linked_bytes': 11537}}
        head = {'web': {'incremental_linked_bytes': 529073}, 'aop': {'incremental_linked_bytes': 21729}}
        base = {'web': {'incremental_linked_bytes': 528985}, 'aop': {'incremental_linked_bytes': 11360}}
        notices = []
        found = module_probes.judge(head, caps, base, notices)
        self.assertEqual([m for m, *_ in found], ['aop'])
        self.assertEqual([m for m, *_ in notices], ['web'])

    def test_a_module_without_a_cap_or_a_value_is_not_judged(self):
        self.assertEqual(module_probes.judge({'web': {'incremental_linked_bytes': None}}, self.CAPS, {}), [])


class Measuring(unittest.TestCase):
    def test_measure_builds_runs_with_the_linked_natives_excluded(self):
        # 17:15Z train: the base worktree links .native, which .gitignore's `.native/` does not match as a link, and
        # measure_builds refused it as an untracked input; the train landed nothing.
        from unittest import mock
        seen = {}

        def fake(command, cwd, capture_output, text, env):
            seen.update(env=env, excludes=Path(env['GIT_CONFIG_VALUE_0']).read_text())
            out = Path(command[command.index('--output') + 1])
            out.write_text('{"framework": {"aop": {"incremental_linked_bytes": 1, "template_instances": 2}}}')
            return mock.Mock(returncode=0, stdout='', stderr='')
        with mock.patch.object(module_probes.subprocess, 'run', side_effect=fake):
            values = module_probes.measure(['aop'], Path('.'))
        self.assertEqual(values, {'aop': {'incremental_linked_bytes': 1, 'template_instances': 2}})
        self.assertEqual(seen['env']['GIT_CONFIG_KEY_0'], 'core.excludesFile')
        self.assertIn('.native', seen['excludes'].split())


class Selection(unittest.TestCase):
    def test_owner_is_the_longest_directory(self):
        directories = {'boot': 'boot/boot', 'boot-autoconfigure': 'boot/boot-autoconfigure', 'core': 'framework/core'}
        self.assertEqual(module_probes.owner('boot/boot-autoconfigure/source/x.d', directories), 'boot-autoconfigure')
        self.assertEqual(module_probes.owner('boot/boot/source/x.d', directories), 'boot')
        self.assertIsNone(module_probes.owner('docs/x.md', directories))

    def test_a_core_change_selects_its_dependents_and_a_json_change_none(self):
        # 5a2d60f43 changed framework/core (MIME boundaries) and pulled flint.conc into core: aop and security-core
        # went over their caps on main through it (coordinator, 2026-11-26 15:14Z).
        selected = module_probes.affected('5a2d60f43^', '5a2d60f43')
        self.assertIn('core', selected)
        self.assertTrue({'aop', 'security-core'} <= set(selected), selected)
        self.assertEqual(module_probes.affected('6c1348942^', '6c1348942'), [])


if __name__ == '__main__':
    unittest.main()
