"""The vibe-coding benchmark's harness and acceptance tests (ADR-021 section 11, ADR-027 section 6): a checked-in
reference solution passes its acceptance test, and an untouched project fails it, so the test is not vacuous."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from test_flint_cli import ROOT, environment, setUpModule  # noqa: F401

BENCH = ROOT / 'tools' / 'vibe_bench.py'


def bench(*arguments):
    return subprocess.run([sys.executable, str(BENCH), *arguments], cwd=ROOT, capture_output=True, text=True,
                          env=environment(), timeout=900)


class VibeBenchTests(unittest.TestCase):
    def test_every_task_has_a_statement_and_an_acceptance_test(self):
        listed = bench('list').stdout.split()
        self.assertEqual(listed, ['cli-todo', 'queue-worker', 'rest-notes', 'tui-dashboard'])
        for task in listed:
            directory = ROOT / 'benchmarks' / 'vibe' / 'tasks' / task
            self.assertTrue((directory / 'TASK.md').read_text().startswith('# '), task)
            self.assertIn('def checks(program)', (directory / 'acceptance.py').read_text(), task)

    def test_the_flint_reference_passes_cli_todo(self):
        result = bench('reference', 'cli-todo')
        self.assertEqual(result.returncode, 0, result.stdout[-3000:] + result.stderr[-2000:])
        self.assertIn('cli-todo (flint): 29/29 checks — success', result.stdout)

    def test_every_acceptance_test_is_passed_by_its_oracle(self):
        # Minimal Python solutions prove the tests themselves sound where no reference exists yet.
        result = bench('oracle', 'rest-notes', 'queue-worker', 'tui-dashboard')
        self.assertEqual(result.returncode, 0, result.stdout[-3000:] + result.stderr[-2000:])
        for task in ('rest-notes', 'queue-worker', 'tui-dashboard'):
            self.assertRegex(result.stdout, task + r' \(oracle\): (\d+)/\1 checks — success')

    def test_a_fresh_project_fails_and_the_prompt_names_the_mcp_tools(self):
        with tempfile.TemporaryDirectory(prefix='vibe-test-') as temporary:
            workspace = Path(temporary) / 'work'
            prepared = bench('prepare', 'cli-todo', '--language', 'flint', '--dir', str(workspace))
            self.assertEqual(prepared.returncode, 0, prepared.stderr)
            prompt = (workspace / 'PROMPT.md').read_text()
            self.assertIn('search_api', prompt)
            self.assertIn('# To-do CLI with configuration and subcommands', prompt)
            self.assertTrue((workspace / 'AGENTS.md').is_file())
            report = Path(temporary) / 'result.json'
            result = bench('accept', 'cli-todo', '--language', 'flint', '--dir', str(workspace), '--json', str(report))
            self.assertEqual(result.returncode, 1, result.stdout[-2000:])
            record = json.loads(report.read_text())
            self.assertTrue(record['built'])
            self.assertFalse(record['success'])
            self.assertGreater(record['total'], 20)
            self.assertLess(record['passed'], record['total'] // 2)
            self.assertGreater(record['review']['lines'], 0)


if __name__ == '__main__':
    unittest.main()
