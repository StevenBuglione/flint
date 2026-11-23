"""The repo split's policy and workspaces (plan section 7, ADR-030): every package has a repo, edges follow
policy/repos.json, and a flint.workspace/1 file pins each repo's checkout."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import workspace  # noqa: E402


class RepoPolicyTests(unittest.TestCase):
    def test_every_package_boot_library_and_starter_has_a_known_repo(self):
        repos = workspace.repo_policy()['repos']
        owners = workspace.package_repos()
        self.assertEqual(set(workspace.packages_of('flint')),
                         {'arena', 'conc', 'validate', 'serde', 'config', 'log', 'cli', 'os', 'term', 'test'})
        self.assertIn('security', workspace.packages_of('framework'))
        self.assertEqual(workspace.packages_of('ai'), ['ai', 'mcp'])
        self.assertEqual(workspace.packages_of('data-jdbc'), ['data'])
        self.assertIn('boot-autoconfigure-web', workspace.packages_of('boot'))
        self.assertIn('starter-web', workspace.packages_of('boot'))
        for name, (repo, _) in owners.items():
            self.assertIn(repo, repos, name)

    def test_the_monorepo_has_no_wrong_way_edges_and_none_pending(self):
        violations, deferred = workspace.edge_violations()
        self.assertEqual((violations, deferred), ([], []))

    def test_a_wrong_way_edge_is_found(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'policy').mkdir()
            packages = json.loads((ROOT / 'policy/packages.json').read_text())
            packages['packages']['log']['dependencies'].append('web')
            (root / 'policy/packages.json').write_text(json.dumps(packages))
            for name in ('boot.json', 'repos.json'):
                (root / 'policy' / name).write_text((ROOT / 'policy' / name).read_text())
            violations, _ = workspace.edge_violations(root)
            self.assertEqual([message for _, _, message in violations],
                             ['log (flint) -> web (framework): flint may not depend on framework'])


class WorkspaceTests(unittest.TestCase):
    def write(self, directory, commit):
        path = Path(directory) / 'workspace.json'
        checkouts = {repo: {'path': str(ROOT), 'commit': commit} for repo in workspace.repo_policy()['repos']}
        path.write_text(json.dumps({'schema': 'flint.workspace/1', 'checkouts': checkouts}))
        return path

    def test_pinned_checkouts_resolve_packages_and_verify(self):
        head = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, capture_output=True, text=True).stdout.strip()
        with tempfile.TemporaryDirectory() as temporary:
            pinned = workspace.Workspace(self.write(temporary, head))
            self.assertEqual(pinned.verify(), [])
            self.assertEqual(pinned.package_dir('web'), ROOT / 'packages/web')
            self.assertEqual(pinned.package_dir('starter-web'), ROOT / 'starters/web')
            stale = workspace.Workspace(self.write(temporary, '0000000'))
            self.assertEqual(len(stale.verify()), len(workspace.repo_policy()['repos']))

    def test_the_gate_checks_one_repo_and_refuses_a_stale_workspace(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate = subprocess.run([sys.executable, str(ROOT / 'tools/gates.py'), '--gate', 'structural',
                                   '--repo', 'ai', '--package', 'ai'], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(gate.returncode, 0, gate.stderr)
            self.assertEqual(json.loads(gate.stdout)['repo'], 'ai')
            stale = subprocess.run([sys.executable, str(ROOT / 'tools/gates.py'), '--gate', 'structural',
                                    '--workspace', str(self.write(temporary, '0000000'))],
                                   cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(stale.returncode, 1)
            self.assertIn('workspace:', stale.stderr)


if __name__ == '__main__':
    unittest.main()
