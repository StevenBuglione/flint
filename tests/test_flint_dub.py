"""DUB packages through the compatibility index, and [unchecked] waivers (Milestone 8, ADR-023). Git fixtures only."""
import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_flint_cli import codes, environment, error, flint, flint_json, setUpModule  # noqa: F401
from test_flint_deps import git


def tree_hash(directory):
    """flint's content hash: sorted 'path\\0sha256\\n' records, skipping .git and cache or build directories."""
    records = []
    for path in sorted(p for p in directory.rglob('*') if p.is_file()):
        relative = path.relative_to(directory).as_posix()
        if {'.git', '.dub', '.flint', 'build', 'artifacts', '__pycache__'} & set(relative.split('/')):
            continue
        records.append(relative + '\0' + hashlib.sha256(path.read_bytes()).hexdigest() + '\n')
    return hashlib.sha256(''.join(records).encode()).hexdigest()


CLEAN = 'module {module};\n\n@safe:\n\n/// Twice the value.\nint twice(int value) pure nothrow @nogc\n{{\n    return value * 2;\n}}\n'
RAW = 'module {module};\n\nimport cleanlib : twice;\n\n/// Four times the value.\nint quad(int value) @trusted\n{{\n    return twice(twice(value));\n}}\n'


def publish_dub(proxy, name, version, source, dependencies=''):
    directory = proxy / 'example.test' / 'dub' / name
    if not directory.exists():
        (directory / 'source').mkdir(parents=True)
        git(directory, 'init', '-q', '-b', 'main')
    (directory / 'dub.sdl').write_text(f'name "{name}"\nlicense "MIT"\ntargetType "library"\n{dependencies}')
    (directory / 'source' / (name + '.d')).write_text(source.format(module=name))
    git(directory, 'add', '-A')
    git(directory, 'commit', '-q', '-m', f'{name} {version}')
    git(directory, 'tag', '-f', 'v' + version)
    commit = subprocess.run(['git', '-C', str(directory), 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
    return commit, tree_hash(directory)


def entry(name, version, commit, tree, dependencies=()):
    deps = ', '.join('"%s"' % d for d in dependencies)
    return (f'[[package]]\nname = "{name}"\nversion = "{version}"\nrepository = "example.test/dub/{name}"\n'
            f'commit = "{commit}"\ntree_sha256 = "{tree}"\nlicense = "MIT"\ndependencies = [{deps}]\nnative = []\n\n')


class DubIndexTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-dub-')
        base = Path(cls.temporary.name)
        proxy = base / 'proxy'
        index = ''
        clean1 = publish_dub(proxy, 'cleanlib', '1.0.0', CLEAN)
        index += entry('cleanlib', '1.0.0', *clean1)
        clean2 = publish_dub(proxy, 'cleanlib', '1.1.0', CLEAN + '\n/// Marker.\nenum release = 2;\n')
        index += entry('cleanlib', '1.1.0', *clean2)
        raw = publish_dub(proxy, 'rawlib', '0.3.0', RAW, 'dependency "cleanlib" version="~>1.0"\n')
        index += entry('rawlib', '0.3.0', *raw, dependencies=['cleanlib@1.0.0'])
        cls.index = base / 'index.toml'
        cls.index.write_text(index)
        cls.proxy = proxy
        cls.env = environment(FLINT_PROXY='file://' + str(proxy), FLINT_CACHE=str(base / 'cache'),
                              FLINT_DUB_INDEX=str(cls.index))
        status, document = flint_json('new', 'app', cwd=base, env=cls.env)
        assert status == 0, document
        cls.project = base / 'app'
        cls.manifest = cls.project / 'flint.toml'
        cls.original = cls.manifest.read_text()
        (cls.project / 'test' / 'app' / 'dub_test.d').write_text(
            'module app.dub_test;\n\nimport cleanlib : twice;\n\n@safe:\n\n@("an indexed DUB package links")\nunittest\n'
            '{\n    assert(twice(21) == 42);\n}\n')

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def use(self, dependencies, unchecked=''):
        self.manifest.write_text(self.original.replace('[dependencies]\n', '[dependencies]\n' + dependencies)
                                 + ('\n[unchecked]\n' + unchecked if unchecked else ''))
        (self.project / 'flint.lock').unlink(missing_ok=True)

    def run_flint(self, *arguments, env=None):
        return flint_json(*arguments, cwd=self.project, env=env or self.env)

    def test_1_a_clean_package_builds_tests_and_locks(self):
        self.use('"dub:cleanlib" = "1.1.0"\n')
        status, document = self.run_flint('test', '--compiler', 'both')
        self.assertEqual(status, 0, document['diagnostics'])
        lock = (self.project / 'flint.lock').read_text()
        self.assertIn('name = "dub:cleanlib"\nkind = "dub"\npath = "example.test/dub/cleanlib"\nversion = "1.1.0"', lock)
        cache = Path(self.env['FLINT_CACHE']) / 'content'
        # DUB builds a working copy; the verified cache keeps exactly the fetched tree.
        for tree in cache.iterdir():
            self.assertEqual(tree_hash(tree), tree.name)

    def test_2_a_failing_package_needs_an_unchecked_waiver(self):
        self.use('"dub:rawlib" = "0.3.0"\n')
        status, document = self.run_flint('build')
        self.assertEqual((status, codes(document)), (1, ['FLINT-E0316']))
        self.assertIn('dub:rawlib 0.3.0 fails', error(document, 'FLINT-E0316')['message'])
        self.use('"dub:rawlib" = "0.3.0"\n', '"dub:rawlib" = "legacy maths pending a port"\n')
        result = flint('build', cwd=self.project, env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Unchecked dub:rawlib 0.3.0: legacy maths pending a port', result.stderr)
        receipt = json.loads((self.project / '.flint/build/dev/app.receipt.json').read_text())
        self.assertTrue(receipt['unchecked'][0].startswith('dub:rawlib 0.3.0: legacy maths pending a port'))
        status, audit = self.run_flint('deps', 'audit')
        self.assertEqual(status, 0, audit['diagnostics'])
        self.assertEqual([d['code'] for d in audit['diagnostics'] if d['severity'] == 'warning'], ['FLINT-E0313'])
        components = {c['name']: c for c in audit['components']}
        self.assertEqual(components['dub:rawlib']['waiver'], 'legacy maths pending a port')
        self.assertEqual(components['dub:cleanlib']['version_number'], '1.0.0')
        self.assertTrue(any('dub:rawlib 0.3.0 tree sha256' in line for line in audit['verified']))

    def test_3_unlisted_versions_and_conflicts_are_refused(self):
        self.use('"dub:cleanlib" = "9.9.9"\n')
        status, document = self.run_flint('lock')
        self.assertEqual((status, codes(document)), (3, ['FLINT-E0314']))
        self.assertIn('1.0.0, 1.1.0', document['diagnostics'][0]['fix'])
        self.use('"dub:cleanlib" = "1.1.0"\n"dub:rawlib" = "0.3.0"\n', '"dub:rawlib" = "test"\n')
        status, document = self.run_flint('lock')
        self.assertEqual((status, codes(document)), (3, ['FLINT-E0315']))
        message = document['diagnostics'][0]['message']
        self.assertIn('the project needs 1.1.0', message)
        self.assertIn('dub:rawlib needs 1.0.0', message)

    def test_4_a_moved_tag_is_refused(self):
        self.use('"dub:cleanlib" = "1.0.0"\n')
        with tempfile.TemporaryDirectory() as cache:
            env = dict(self.env, FLINT_CACHE=cache)
            directory = self.proxy / 'example.test' / 'dub' / 'cleanlib'
            git(directory, 'tag', '-f', 'v1.0.0', 'v1.1.0')
            try:
                status, document = self.run_flint('lock', env=env)
                self.assertEqual((status, codes(document)), (3, ['FLINT-E0309']))
                self.assertIn('compatibility index pins commit', document['diagnostics'][0]['message'])
            finally:
                first = subprocess.run(['git', '-C', str(directory), 'rev-list', '--max-parents=0', 'HEAD'],
                                       capture_output=True, text=True).stdout.strip()
                git(directory, 'tag', '-f', 'v1.0.0', first)

    def test_5_vendored_dub_packages_build_offline(self):
        self.use('"dub:rawlib" = "0.3.0"\n', '"dub:rawlib" = "vendored"\n')
        self.assertEqual(self.run_flint('lock')[0], 0)
        status, document = self.run_flint('deps', 'vendor')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertTrue((self.project / 'vendor/example.test/dub/rawlib/dub.sdl').is_file())
        with tempfile.TemporaryDirectory() as empty:
            status, document = self.run_flint('build', env=dict(self.env, FLINT_CACHE=empty, FLINT_OFFLINE='1'))
            self.assertEqual(status, 0, document['diagnostics'])
        subprocess.run(['rm', '-rf', str(self.project / 'vendor')], check=True)

    def test_6_local_dub_directories_follow_the_same_rule(self):
        local = Path(self.temporary.name) / 'localraw'
        (local / 'source').mkdir(parents=True, exist_ok=True)
        (local / 'dub.sdl').write_text('name "localraw"\ntargetType "library"\n')
        (local / 'source' / 'localraw.d').write_text('module localraw;\n\n/// One.\nint one() @trusted\n{\n    return 1;\n}\n')
        before = tree_hash(local)
        self.use('localraw = { path = "../localraw" }\n')
        status, document = self.run_flint('build')
        self.assertEqual((status, codes(document)), (1, ['FLINT-E0316']))
        self.use('localraw = { path = "../localraw" }\n', 'localraw = "in-house, pending review"\n')
        status, document = self.run_flint('build')
        self.assertEqual(status, 0, document['diagnostics'])
        status, document = self.run_flint('build')
        self.assertEqual(status, 0, document['diagnostics'])
        self.assertEqual(tree_hash(local), before)


if __name__ == '__main__':
    unittest.main()
