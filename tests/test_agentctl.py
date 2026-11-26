"""tools/agentctl.py: the harness-neutral coordination store (docs/agents/README.md)."""
from __future__ import annotations

import contextlib
import io
import json
import os
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import agentctl  # noqa: E402


class AgentctlTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'coordination'
        os.environ['FLINT_COORD_DIR'] = str(self.root)
        self.addCleanup(os.environ.pop, 'FLINT_COORD_DIR', None)
        self.run_cli('register', 'web-http', '--area', 'servlet adapter and HTTP engine')
        self.run_cli('register', 'coordinator', '--area', 'coordination')

    def run_cli(self, *argv, stdin: str | None = None) -> str:
        out = io.StringIO()
        old_stdin = sys.stdin
        if stdin is not None:
            sys.stdin = io.StringIO(stdin)
        try:
            with contextlib.redirect_stdout(out):
                self.assertEqual(agentctl.main(list(argv)), 0)
        finally:
            sys.stdin = old_stdin
        return out.getvalue()

    def test_a_held_role_refuses_a_second_agent_until_forced(self):
        self.run_cli('claim', 'web-http', '--agent', 'claude-web', '--harness', 'claude')
        with self.assertRaises(SystemExit) as refused:
            self.run_cli('claim', 'web-http', '--agent', 'codex-web', '--harness', 'codex')
        self.assertIn('held by claude-web', str(refused.exception))
        self.run_cli('claim', 'web-http', '--agent', 'codex-web', '--harness', 'codex', '--force', 'claude stopped')
        lease = json.loads((self.root / 'leases.json').read_text())['web-http']
        self.assertEqual((lease['agent'], lease['harness']), ('codex-web', 'codex'))
        events = [json.loads(line) for line in (self.root / 'events.jsonl').read_text().splitlines()]
        self.assertEqual(events[-1]['forced_from'], 'claude-web')

    def test_a_lapsed_lease_can_be_taken_without_force(self):
        self.run_cli('claim', 'web-http', '--agent', 'claude-web', '--harness', 'claude', '--ttl-min', '0')
        self.run_cli('claim', 'web-http', '--agent', 'codex-web', '--harness', 'codex')
        self.assertEqual(json.loads((self.root / 'leases.json').read_text())['web-http']['agent'], 'codex-web')

    def test_unknown_roles_are_refused(self):
        with self.assertRaises(SystemExit):
            self.run_cli('claim', 'nobody', '--agent', 'a', '--harness', 'codex')
        with self.assertRaises(SystemExit):
            self.run_cli('send', '--from', 'coordinator', '--to', 'nobody', 'hi')
        with self.assertRaises(SystemExit):
            self.run_cli('claim', '../etc', '--agent', 'a', '--harness', 'codex')

    def test_mail_is_unread_until_marked_and_multi_line_messages_stay_one_entry(self):
        self.run_cli('send', '--from', 'coordinator', '--to', 'web-http', 'first line\nsecond line')
        unread = self.run_cli('inbox', 'web-http')
        self.assertIn('coordinator -> web-http: first line\n  second line', unread)
        store = agentctl.Store(self.root)
        self.assertEqual(store.unread('web-http'), 1)
        self.run_cli('inbox', 'web-http', '--mark-read')
        self.assertEqual(self.run_cli('inbox', 'web-http'), '')
        self.run_cli('send', '--from', 'coordinator', '--to', 'web-http', stdin='from stdin\n')
        self.assertEqual(store.unread('web-http'), 1)
        self.assertIn('first line', self.run_cli('inbox', 'web-http', '--all'))

    def test_send_to_all_skips_the_sender(self):
        output = self.run_cli('send', '--from', 'coordinator', '--to', 'all', 'heads up')
        self.assertEqual(output.strip(), 'sent to web-http')
        self.assertEqual((self.root / 'inbox' / 'coordinator.md').read_text(), '')

    def test_placeholder_and_self_addressed_mail_is_refused(self):
        for body in ('noop', 'NOOP', ' ping '):
            with self.assertRaises(SystemExit):
                self.run_cli('send', '--from', 'web-http', '--to', 'coordinator', body)
        with self.assertRaises(SystemExit):
            self.run_cli('send', '--from', 'coordinator', '--to', 'coordinator', 'real text')
        self.assertEqual((self.root / 'inbox' / 'coordinator.md').read_text(), '')

    def test_handoff_keeps_history_and_refreshes_the_heartbeat(self):
        self.run_cli('claim', 'web-http', '--agent', 'codex-web', '--harness', 'codex')
        self.run_cli('handoff', 'web-http', '--agent', 'codex-web', stdin='## Next\n- wire accept-count\n')
        self.run_cli('handoff', 'web-http', '--agent', 'codex-web', '-', stdin='## Next\n- measure RSS\n')
        self.assertIn('measure RSS', self.run_cli('state', 'web-http'))
        self.assertEqual(len(list((self.root / 'state' / 'history' / 'web-http').glob('*.md'))), 1)
        self.assertIn('measure RSS', self.run_cli('board'))

    def test_brief_carries_the_protocol_state_and_unread_mail(self):
        self.run_cli('handoff', 'web-http', '--agent', 'x', stdin='## Current task\n- max-handlers step 2\n')
        self.run_cli('send', '--from', 'coordinator', '--to', 'web-http', 'please rebase')
        text = self.run_cli('brief', 'web-http', '--harness', 'codex')
        for expected in ('AGENTS.md', 'docs/agents/README.md', 'claim web-http', 'max-handlers step 2', 'please rebase'):
            self.assertIn(expected, text)
        self.assertEqual(agentctl.Store(self.root).unread('web-http'), 1, 'brief must not mark mail read')

    def test_concurrent_senders_never_lose_or_interleave_entries(self):
        def send(index):
            agentctl.Store(self.root).send('coordinator', ['web-http'], f'message {index} ' + 'x' * 2000)
        threads = [threading.Thread(target=send, args=(i,)) for i in range(40)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        lines = (self.root / 'inbox' / 'web-http.md').read_text().splitlines()
        self.assertEqual(len(lines), 40)
        self.assertTrue(all(line.startswith('- ') and line.endswith('x' * 2000) for line in lines))

    def test_launch_dry_run_names_codex_exec_in_the_role_worktree(self):
        self.run_cli('register', 'web-http', '--area', 'servlet', '--worktree', '/tmp/wt-web')
        output = self.run_cli('launch', 'web-http', '--harness', 'codex', '--loop', '20', '--dry-run')
        self.assertIn('codex exec --cd /tmp/wt-web', output)
        self.assertIn('resume --last', output)



class QueueTests(unittest.TestCase):
    """The FIFO queue for a slot such as apps-landing (coordinator, 2026-11-26)."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'coordination'
        os.environ['FLINT_COORD_DIR'] = str(self.root)
        self.addCleanup(os.environ.pop, 'FLINT_COORD_DIR', None)
        self.run_cli('register', 'apps-landing', '--area', 'landing mutex', '--queued')
        self.run_cli('register', 'web-http', '--area', 'servlet adapter')

    run_cli = AgentctlTests.run_cli

    def claim(self, agent):
        return self.run_cli('claim', 'apps-landing', '--agent', agent, '--harness', 'codex', '--ttl-min', '40')

    def refused(self, agent):
        with self.assertRaises(SystemExit) as caught:
            self.claim(agent)
        return str(caught.exception)

    def age(self, **minutes):
        """Move the stored queue times back, as if that many minutes had passed."""
        import time as clock
        queues = json.loads((self.root / 'queues.json').read_text())
        for key, value in minutes.items():
            queues['apps-landing'][key] = agentctl._dt.datetime.fromtimestamp(
                clock.time() - value * 60, agentctl._dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        (self.root / 'queues.json').write_text(json.dumps(queues))

    def test_a_free_slot_with_an_empty_queue_is_anyone_s(self):
        self.claim('sol-data')
        self.assertEqual(json.loads((self.root / 'leases.json').read_text())['apps-landing']['agent'], 'sol-data')

    def test_only_the_head_may_claim_and_claiming_leaves_the_queue(self):
        for agent in ('sol-data', 'sol-security', 'sol-context'):
            self.run_cli('queue', 'apps-landing', 'join', '--agent', agent)
        self.assertIn('sol-data is next (3 waiting); you are number 2', self.refused('sol-security'))
        self.assertIn('join it: agentctl.py queue apps-landing join --agent sol-ai', self.refused('sol-ai'))
        self.claim('sol-data')
        shown = self.run_cli('queue', 'apps-landing', 'show')
        self.assertIn('apps-landing: held by sol-data; queue: 1. sol-security (next), 2. sol-context', shown)
        self.assertIn('held by sol-data', self.refused('sol-security'))
        self.run_cli('release', 'apps-landing', '--agent', 'sol-data')
        self.assertIn('sol-security is next', self.refused('sol-context'))
        self.claim('sol-security')

    def test_a_head_that_does_not_claim_within_ten_minutes_of_the_slot_freeing_is_skipped(self):
        self.claim('sol-data')
        for agent in ('sol-security', 'sol-context', 'sol-jpa'):
            self.run_cli('queue', 'apps-landing', 'join', '--agent', agent)
        self.run_cli('release', 'apps-landing', '--agent', 'sol-data')
        self.age(freed=11, head_since=60)  # freed 11 minutes ago; the head has waited longer, since joining
        self.assertIn('sol-context is next', self.refused('sol-jpa'))
        self.claim('sol-context')
        events = [json.loads(line) for line in (self.root / 'events.jsonl').read_text().splitlines()]
        self.assertIn({'role': 'apps-landing', 'agent': 'sol-security', 'event': 'queue-skip'},
                      [{k: e[k] for k in ('role', 'agent', 'event')} for e in events if e['event'] == 'queue-skip'])

    def test_skips_cascade_ten_minutes_per_head(self):
        for agent in ('a', 'b', 'c'):
            self.run_cli('queue', 'apps-landing', 'join', '--agent', agent)
        self.age(freed=25, head_since=25)
        self.assertIn('c is next (1 waiting)', self.refused('d'))

    def test_the_clock_starts_when_the_slot_frees_not_when_the_head_joined(self):
        self.claim('sol-data')
        self.run_cli('queue', 'apps-landing', 'join', '--agent', 'sol-security')
        self.run_cli('queue', 'apps-landing', 'join', '--agent', 'sol-context')
        self.age(head_since=90)  # waited 90 minutes behind a held slot
        self.run_cli('release', 'apps-landing', '--agent', 'sol-data')
        self.assertIn('sol-security is next', self.refused('sol-context'))

    def test_a_lapsed_lease_frees_the_slot_for_the_head(self):
        self.run_cli('claim', 'apps-landing', '--agent', 'sol-data', '--harness', 'codex', '--ttl-min', '0')
        self.run_cli('queue', 'apps-landing', 'join', '--agent', 'sol-security')
        self.claim('sol-security')

    def test_leaving_and_joining_twice(self):
        self.run_cli('queue', 'apps-landing', 'join', '--agent', 'a')
        with self.assertRaises(SystemExit):
            self.run_cli('queue', 'apps-landing', 'join', '--agent', 'a')
        self.run_cli('queue', 'apps-landing', 'join', '--agent', 'b')
        self.run_cli('queue', 'apps-landing', 'leave', '--agent', 'a')
        self.claim('b')
        with self.assertRaises(SystemExit):
            self.run_cli('queue', 'apps-landing', 'leave', '--agent', 'a')

    def test_force_overrides_the_queue_and_is_logged(self):
        self.run_cli('queue', 'apps-landing', 'join', '--agent', 'a')
        self.run_cli('claim', 'apps-landing', '--agent', 'b', '--harness', 'codex', '--force', 'a is offline')
        self.assertEqual(json.loads((self.root / 'leases.json').read_text())['apps-landing']['agent'], 'b')

    def test_an_unqueued_role_claims_as_before(self):
        self.run_cli('claim', 'web-http', '--agent', 'x', '--harness', 'codex')
        self.assertFalse((self.root / 'queues.json').exists())

    def test_the_board_shows_each_queue(self):
        self.claim('sol-data')
        self.run_cli('queue', 'apps-landing', 'join', '--agent', 'sol-security')
        board = self.run_cli('board')
        self.assertIn('queues\napps-landing: held by sol-data; queue: 1. sol-security (next)', board)
        self.run_cli('release', 'apps-landing', '--agent', 'sol-data')
        self.assertRegex(self.run_cli('board'), r'apps-landing: free; queue: 1\. sol-security \(claim by \d\d:\d\dZ\)')

    def test_concurrent_joins_keep_one_entry_each_in_order_of_arrival(self):
        store = agentctl.Store(self.root)
        threads = [threading.Thread(target=store.queue, args=('apps-landing', 'join', f'lane{i}')) for i in range(12)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        members = [m['agent'] for m in json.loads((self.root / 'queues.json').read_text())['apps-landing']['members']]
        self.assertEqual(sorted(members), sorted(f'lane{i}' for i in range(12)))


if __name__ == '__main__':
    unittest.main()
