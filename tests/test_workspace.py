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
        self.assertIn('engine-security', workspace.packages_of('framework'))
        self.assertEqual(workspace.packages_of('ai'), ['engine-ai', 'engine-mcp'])
        self.assertEqual(workspace.packages_of('data-jdbc'), ['engine-data'])
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
            packages['packages']['log']['dependencies'].append('engine-web')
            (root / 'policy/packages.json').write_text(json.dumps(packages))
            for name in ('boot.json', 'repos.json'):
                (root / 'policy' / name).write_text((ROOT / 'policy' / name).read_text())
            violations, _ = workspace.edge_violations(root)
            self.assertEqual([message for _, _, message in violations],
                             ['log (flint) -> engine-web (framework): flint may not depend on framework'])


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
            self.assertEqual(pinned.package_dir('engine-web'), ROOT / 'packages/engine-web')
            self.assertEqual(pinned.package_dir('starter-web'), ROOT / 'starters/web')
            stale = workspace.Workspace(self.write(temporary, '0000000'))
            self.assertEqual(len(stale.verify()), len(workspace.repo_policy()['repos']))

    def test_the_gate_checks_one_repo_and_refuses_a_stale_workspace(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate = subprocess.run([sys.executable, str(ROOT / 'tools/gates.py'), '--gate', 'structural',
                                   '--repo', 'ai', '--package', 'engine-ai'], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(gate.returncode, 0, gate.stderr)
            self.assertEqual(json.loads(gate.stdout)['repo'], 'ai')
            stale = subprocess.run([sys.executable, str(ROOT / 'tools/gates.py'), '--gate', 'structural',
                                    '--workspace', str(self.write(temporary, '0000000'))],
                                   cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(stale.returncode, 1)
            self.assertIn('workspace:', stale.stderr)


if __name__ == '__main__':
    unittest.main()


class PlatformModuleTests(unittest.TestCase):
    def test_platform_lock_covers_every_repo_and_the_bill_of_materials_is_current(self):
        import platform_modules as module
        self.assertEqual(module.problems(), [])
        bom = json.loads((ROOT / 'boot/dependencies/flint-dependencies.json').read_text())
        self.assertEqual(bom['artifacts']['flint:starter-web'], {'repo': 'boot', 'version': 'monorepo'})
        self.assertEqual(bom['artifacts']['flint:arena'], {'repo': 'flint', 'version': 'monorepo'})
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ('policy', 'boot/dependencies'):
                (root / name).mkdir(parents=True)
            for name in ('packages.json', 'boot.json', 'repos.json', 'platform.toml'):
                (root / 'policy' / name).write_text((ROOT / 'policy' / name).read_text())
            (root / 'platform.lock').write_text((ROOT / 'platform.lock').read_text())
            stale = dict(bom, artifacts=dict(bom['artifacts']))
            del stale['artifacts']['flint:engine-web']
            (root / 'boot/dependencies/flint-dependencies.json').write_text(json.dumps(stale))
            self.assertEqual(module.problems(root), ['boot/dependencies/flint-dependencies.json is stale: run '
                                                     'python3 tools/platform_modules.py --write'])

    def test_a_project_outside_the_checkout_locks_each_package_at_its_platform_version(self):
        flint = ROOT / '.flint/bin/flint'
        with tempfile.TemporaryDirectory(prefix='flint-platform-') as temporary:
            created = subprocess.run([str(flint), 'new', 'shop'], cwd=temporary, capture_output=True, text=True)
            self.assertEqual(created.returncode, 0, created.stderr)
            project = Path(temporary) / 'shop'
            added = subprocess.run([str(flint), 'add', 'web'], cwd=project, capture_output=True, text=True)
            self.assertEqual(added.returncode, 0, added.stderr)
            lock = (project / 'flint.lock').read_text()
            self.assertIn('name = "flint:starter-web"\nkind = "core"\nsource = "flint-home"\nplatform = "boot@monorepo"',
                          lock)
            self.assertIn('name = "flint:arena"\nkind = "core"\nsource = "flint-home"\nplatform = "flint@monorepo"',
                          lock)


class LockPartitionTests(unittest.TestCase):
    def test_each_repo_carries_its_slice_of_the_native_and_peer_locks(self):
        import platform_modules

        partitions = platform_modules.lock_partitions()
        self.assertEqual(partitions, json.loads((ROOT / 'policy/lock-partitions.json').read_text()))
        self.assertEqual(partitions['native']['flint'], ['libyaml', 'utf8proc'])
        framework = set(partitions['native']['framework'])
        self.assertTrue({'openssl', 'sqlite', 'llhttp', 'zlib', 'zstd'} <= framework)
        self.assertNotIn('libyaml', framework)
        self.assertEqual(partitions['peers']['framework'], ['jre', 'kafka', 'minio', 'nats', 'valkey'])
        self.assertEqual(partitions['peers']['flint'], ['graalvm', 'jdk', 'maven', 'spring-boot'])
        native = json.loads((ROOT / 'policy/native-lock.json').read_text())['libraries']
        covered = set().union(*map(set, partitions['native'].values()))
        self.assertEqual(covered, {row['name'] for row in native})


class AppRepoTests(unittest.TestCase):
    def test_flint_mcp_belongs_to_ai_and_an_app_edge_is_checked(self):
        apps = json.loads((ROOT / 'policy/apps.json').read_text())['apps']
        self.assertEqual(apps['flint-mcp'], {'directory': 'apps/flint-mcp', 'repo': 'ai'})
        self.assertEqual(apps['flint']['repo'], 'flint')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'policy').mkdir()
            for name in ('packages.json', 'boot.json', 'repos.json'):
                (root / 'policy' / name).write_text((ROOT / 'policy' / name).read_text())
            moved = dict(apps, **{'flint-mcp': {'directory': 'apps/flint-mcp', 'repo': 'flint'}})
            (root / 'policy/apps.json').write_text(json.dumps({'schema': 'flint.apps/1', 'apps': moved}))
            (root / 'apps/flint-mcp').mkdir(parents=True)
            (root / 'apps/flint-mcp/flint.toml').write_text((ROOT / 'apps/flint-mcp/flint.toml').read_text())
            violations, _ = workspace.edge_violations(root)
            self.assertEqual([message for _, _, message in violations],
                             ['app flint-mcp (flint) -> engine-mcp (ai): flint may not depend on ai'])


class ExtractionTests(unittest.TestCase):
    def test_each_repo_takes_its_packages_boot_and_starters_and_its_apps(self):
        import extract_repo

        # A repo with an API mapping takes api/<repo>, which extraction renames to api/.
        self.assertEqual(extract_repo.moving_paths('boot'), ['api/boot', 'boot', 'starters'])
        self.assertEqual(extract_repo.moving_paths('ai'), ['apps/flint-mcp', 'packages/engine-ai', 'packages/engine-mcp'])
        self.assertEqual(extract_repo.moving_paths('data-jdbc'), ['packages/engine-data'])
        framework = extract_repo.moving_paths('framework')
        self.assertIn('packages/engine-security', framework)
        self.assertIn('api/framework', framework)
        self.assertNotIn('packages/arena', framework)
        self.assertEqual(len(framework), len(workspace.packages_of('framework')) + 1)
        self.assertEqual(extract_repo.moving_paths('batch'), [])

    def test_the_workspace_root_recipe_joins_every_checkout_under_the_flint_name(self):
        with tempfile.TemporaryDirectory() as temporary:
            recipe = workspace.dub_root(workspace.Workspace(), Path(temporary) / 'root').read_text()
            self.assertIn('name "flint"\ntargetType "none"\n', recipe)
            lines = [line for line in recipe.splitlines() if line.startswith('subPackage ')]
            self.assertEqual(len(lines), len([n for n, (_, d) in workspace.package_repos().items()
                                              if (ROOT / d / 'dub.sdl').is_file()]))
            self.assertTrue(any(line.endswith('packages/engine-web"') for line in lines))
            self.assertTrue(any(line.endswith('starters/web"') for line in lines))

    def test_an_extracted_repo_mirrors_springs_layout_and_its_checkout_is_found_there(self):
        import extract_repo

        layout = workspace.repo_layout
        self.assertEqual(layout('packages/engine-web', 'framework'), 'engine/web')
        self.assertEqual(layout('framework/jakarta-annotation', 'framework'), 'flint-jakarta-annotation')
        self.assertEqual(layout('boot/core/flint-boot', 'boot'), 'core/flint-boot')
        self.assertEqual(layout('boot/boot', 'boot'), 'legacy/flint-boot')
        self.assertEqual(layout('boot/dependencies', 'boot'), 'platform/flint-boot-dependencies')
        self.assertEqual(layout('boot/actuator', 'boot'), 'module/flint-boot-actuator')
        self.assertEqual(layout('starters/starter', 'boot'), 'starter/flint-boot-starter')
        self.assertEqual(layout('starters/web', 'boot'), 'starter/flint-boot-starter-web')
        self.assertEqual(layout('apps/flint-mcp', 'ai'), 'apps/flint-mcp')
        self.assertEqual(layout('packages/arena', 'flint'), 'packages/arena')
        with tempfile.TemporaryDirectory() as temporary:
            checkout = Path(temporary) / 'flint-framework'
            (checkout / 'engine/web').mkdir(parents=True)
            (checkout / 'engine/web/dub.sdl').write_text('name "engine-web"\n')
            (checkout / 'engine/web/README.md').write_text('See packages/engine-web/source and '
                                                           'packages/engine-webx.\n')
            subprocess.run(['git', 'init', '-q', str(checkout)], check=True)
            subprocess.run(['git', '-C', str(checkout), 'add', '-A'], check=True)
            file = Path(temporary) / 'workspace.json'
            file.write_text(json.dumps({'schema': 'flint.workspace/1',
                                        'checkouts': {'framework': {'path': 'flint-framework'}}}))
            self.assertEqual(workspace.Workspace(file).package_dir('engine-web'), checkout / 'engine/web')
            pairs = [('packages/engine-web', 'engine/web')]
            self.assertEqual(extract_repo.rewrite_references(checkout, pairs), ['engine/web/README.md'])
            self.assertEqual((checkout / 'engine/web/README.md').read_text(),
                             'See engine/web/source and packages/engine-webx.\n')

    def test_extraction_keeps_the_history_of_a_directorys_earlier_name(self):
        import extract_repo

        with tempfile.TemporaryDirectory() as temporary:
            checkout = Path(temporary)
            git = ['git', '-C', str(checkout), '-c', 'user.name=t', '-c', 'user.email=t@t']
            subprocess.run(['git', 'init', '-q', str(checkout)], check=True)
            (checkout / 'packages/web/source').mkdir(parents=True)
            (checkout / 'packages/web/source/router.d').write_text('module flint.web.router;\n' * 20)
            subprocess.run([*git, 'add', '-A'], check=True)
            subprocess.run([*git, 'commit', '-qm', 'web'], check=True)
            subprocess.run([*git, 'mv', 'packages/web', 'packages/engine-web'], check=True)
            subprocess.run([*git, 'commit', '-qm', 'rename'], check=True)
            self.assertEqual(extract_repo.earlier_names(checkout, ['packages/engine-web']),
                             {'packages/web': 'packages/engine-web'})
            self.assertEqual(extract_repo.earlier_names(checkout, ['packages/engine-mq']), {})

    def test_the_refresh_needs_all_to_push_and_one_repo_otherwise(self):
        script = str(ROOT / 'tools/extract_repo.py')
        with tempfile.TemporaryDirectory() as temporary:
            for args in (['--push', 'ai'], [], ['--all', 'ai']):
                result = subprocess.run([sys.executable, script, *args, '--into', temporary], capture_output=True,
                                        text=True)
                self.assertEqual(result.returncode, 2, args)
                self.assertIn('name one repo, or --all', result.stderr)
