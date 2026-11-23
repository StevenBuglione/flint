"""Go-style repository-path dependencies through flint (Milestone 8, ADR-023), with local git fixtures only."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_flint_cli import ROOT, codes, environment, flint, flint_json, setUpModule  # noqa: F401


def git(directory, *arguments):
    subprocess.run(['git', '-C', str(directory), *arguments], check=True, capture_output=True,
                   env=dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@t', GIT_COMMITTER_NAME='t',
                            GIT_COMMITTER_EMAIL='t@t'))


def publish(proxy, name, version, requirements='', body='', imports=''):
    """Commit a Flint library at example.test/acme/<name> and tag it v<version>."""
    directory = proxy / 'example.test' / 'acme' / name
    if not directory.exists():
        (directory / 'src' / name).mkdir(parents=True)
        git(directory, 'init', '-q', '-b', 'main')
    (directory / 'flint.toml').write_text(f'[project]\nname = "{name}"\nversion = "{version}"\nflint = "1.0"\n'
                                          f'type = "library"\n\n[dependencies]\n{requirements}', encoding='utf-8', newline='\n')
    (directory / 'src' / name / 'package.d').write_text(
        f'module {name};\n\n{imports}@safe:\n\n/// Release.\nenum string release = "{version}";\n{body}', encoding='utf-8', newline='\n')
    git(directory, 'add', '-A')
    git(directory, 'commit', '-q', '-m', f'{name} {version}')
    git(directory, 'tag', 'v' + version)
    return directory


CENTS = '\n/// Cents as text.\nstring cents(long value) pure\n{\n    import std.conv : to;\n\n    return value.to!string;\n}\n'


class RemoteDependencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-deps-')
        base = Path(cls.temporary.name)
        cls.proxy = base / 'proxy'
        cls.cache = base / 'cache'
        for version in ('1.0.0', '1.1.0'):
            publish(cls.proxy, 'money', version)
        publish(cls.proxy, 'money', '1.2.0', body=CENTS)
        publish(cls.proxy, 'money', '2.0.0-rc.1', body=CENTS)
        publish(cls.proxy, 'ledger', '1.0.0', '"example.test/acme/money" = "1.1.0"\n', imports='static import money;\n\n')
        publish(cls.proxy, 'invoice', '1.0.0', '"example.test/acme/money" = "1.2.0"\n',
                body='\n/// Total.\nstring total() pure\n{\n    return cents(1250);\n}\n', imports='import money : cents;\n\n')
        cls.env = environment(FLINT_PROXY='file://' + str(cls.proxy), FLINT_CACHE=str(cls.cache))
        status, document = flint_json('new', 'app', cwd=base, env=cls.env)
        assert status == 0, document
        cls.project = base / 'app'
        manifest = cls.project / 'flint.toml'
        manifest.write_text(manifest.read_text(encoding='utf-8').replace('[dependencies]\n', '[dependencies]\n'
                            '"example.test/acme/money" = "1.0.0"\n"example.test/acme/ledger" = "1.0.0"\n'
                            '"example.test/acme/invoice" = "1.0.0"\n'), encoding='utf-8', newline='\n')
        greeting = cls.project / 'src/app/greeting.d'
        greeting.write_text(greeting.read_text(encoding='utf-8').replace('@safe:\n', 'import invoice : total;\n\n@safe:\n', 1)
                            .replace('"!";', '"! " ~ total();'), encoding='utf-8', newline='\n')

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_flint(self, *arguments, env=None):
        return flint_json(*arguments, cwd=self.project, env=env or self.env)

    def test_1_minimal_version_selection_locks_exact_versions_and_hashes(self):
        status, document = self.run_flint('lock')
        self.assertEqual(status, 0, document['diagnostics'])
        locked = {p['name']: p for p in document['packages']}
        self.assertEqual(locked['example.test/acme/money']['kind'], 'remote')
        text = (self.project / 'flint.lock').read_text(encoding='utf-8')
        self.assertIn('name = "example.test/acme/money"\nkind = "remote"\nversion = "1.2.0"', text)
        self.assertNotIn('2.0.0-rc.1', text)
        status, why = self.run_flint('deps', 'why', 'example.test/acme/money')
        self.assertEqual(why['paths'], [['example.test/acme/money']])
        status, tree = self.run_flint('deps', 'tree')
        names = [(n['name'], n['version_number']) for n in tree['nodes']]
        self.assertIn(('example.test/acme/invoice', '1.0.0'), names)

    def test_2_build_run_test_offline(self):
        status, built = self.run_flint('build')
        self.assertEqual(status, 0, built['diagnostics'])
        status, ran = self.run_flint('run', '--', '-n', 'Ada')
        self.assertIn('Hello, Ada! 1250', ran['program']['stdout_text'])
        offline = dict(self.env, FLINT_PROXY='off')
        status, again = self.run_flint('build', '--force', env=offline)
        self.assertEqual(status, 0, again['diagnostics'])
        status, tested = self.run_flint('check', env=offline)
        self.assertEqual(status, 0, tested['diagnostics'])

    def test_3_tampering_and_unavailable_modules_fail(self):
        lock = (self.project / 'flint.lock').read_text(encoding='utf-8')
        content = lock.split('name = "example.test/acme/money"')[1].split('content_sha256 = "')[1].split('"')[0]
        source = self.cache / 'content' / content / 'src' / 'money' / 'package.d'
        original = source.read_text(encoding='utf-8')
        source.write_text(original + '// edited\n', encoding='utf-8', newline='\n')
        try:
            status, document = self.run_flint('build')
            self.assertEqual((status, codes(document)[:1]), (3, ['FLINT-E0309']))
        finally:
            source.write_text(original, encoding='utf-8', newline='\n')
        empty = dict(self.env, FLINT_PROXY='off', FLINT_CACHE=str(Path(self.temporary.name) / 'empty-cache'))
        status, document = self.run_flint('build', env=empty)
        self.assertEqual((status, codes(document)[:1]), (3, ['FLINT-E0307']))

    def test_4_vendor_builds_without_cache_or_network(self):
        status, vendored = self.run_flint('deps', 'vendor')
        self.assertEqual(status, 0, vendored['diagnostics'])
        self.assertTrue((self.project / 'vendor/example.test/acme/money/flint.toml').is_file())
        empty = dict(self.env, FLINT_PROXY='off', FLINT_CACHE=str(Path(self.temporary.name) / 'no-cache'))
        try:
            status, built = self.run_flint('build', '--force', env=empty)
            self.assertEqual(status, 0, built['diagnostics'])
        finally:
            shutil.rmtree(self.project / 'vendor')

    def test_5_update_raises_requirements_to_the_latest_release(self):
        work = Path(self.temporary.name) / 'update'
        shutil.copytree(self.project, work, ignore=shutil.ignore_patterns('.flint'))
        status, updated = flint_json('deps', 'update', cwd=work, env=self.env)
        self.assertEqual(status, 0, updated['diagnostics'])
        self.assertIn('example.test/acme/money 1.0.0 -> 1.2.0', updated['changes'])
        self.assertIn('"example.test/acme/money" = "1.2.0"', (work / 'flint.toml').read_text(encoding='utf-8'))

    def test_6_missing_tags_and_path_dependencies_in_published_modules_fail(self):
        work = Path(self.temporary.name) / 'missing'
        shutil.copytree(self.project, work, ignore=shutil.ignore_patterns('.flint'))
        manifest = work / 'flint.toml'
        manifest.write_text(manifest.read_text(encoding='utf-8').replace('"example.test/acme/money" = "1.0.0"',
                                                         '"example.test/acme/money" = "9.0.0"'), encoding='utf-8', newline='\n')
        status, document = flint_json('lock', cwd=work, env=self.env)
        self.assertEqual((status, codes(document)[:1]), (3, ['FLINT-E0308']))
        publish(self.proxy, 'leaky', '1.0.0', 'local = { path = "../local" }\n')
        manifest.write_text(manifest.read_text(encoding='utf-8').replace('"example.test/acme/money" = "9.0.0"',
                                                         '"example.test/acme/leaky" = "1.0.0"'), encoding='utf-8', newline='\n')
        status, document = flint_json('lock', cwd=work, env=self.env)
        self.assertEqual((status, codes(document)[:1]), (3, ['FLINT-E0310']))


if __name__ == '__main__':
    unittest.main()
