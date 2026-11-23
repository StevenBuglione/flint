"""The platform cache (ADR-030 section 5): `flint build` links the pinned platform modules from archives compiled
once per compiler, flags, platform version and target, and a local rebuild reproduces every archive byte for byte.

Each test class builds a `flint new` project against its own FLINT_CACHE, so nothing here reads or fills the
home's cache.
"""
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_flint_cli import FLINT, ROOT, environment, flint, flint_json  # noqa: E402

LINUX = sys.platform.startswith('linux')


def setUpModule():
    if not FLINT.is_file():
        subprocess.run([sys.executable, str(ROOT / 'tools/install_toolchains.py'), '--compiler', 'flint'],
                       cwd=ROOT, env=environment(), check=True, stdout=subprocess.DEVNULL)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def entries(cache):
    """key -> (module, archive sha256 recorded, archive sha256 on disk)."""
    found = {}
    for record in sorted((Path(cache) / 'platform').glob('*/module.json')):
        data = json.loads(record.read_text())
        archives = [p for p in record.parent.iterdir() if p.name != 'module.json']
        found[record.parent.name] = (data['module'], data['sha256'], sha256(archives[0]))
    return found


@unittest.skipUnless(LINUX, 'the platform cache is enabled on Linux hosts first')
class PlatformCacheTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-platform-cache-')
        cls.directory = Path(cls.temporary.name)
        status, document = flint_json('new', 'demo', cwd=cls.directory)
        assert status == 0, document
        cls.project = cls.directory / 'demo'
        cls.cache = cls.directory / 'cache-a'
        cls.first = flint('build', cwd=cls.project, env=environment(FLINT_CACHE=str(cls.cache)))
        assert cls.first.returncode == 0, cls.first.stdout + cls.first.stderr

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def receipt(self, project):
        return json.loads((project / '.flint/build/dev/demo.receipt.json').read_text())

    def test_the_first_build_primes_the_cache_and_links_its_archives(self):
        self.assertIn('Priming', self.first.stderr)
        stored = entries(self.cache)
        self.assertTrue(stored, 'no archive was stored')
        for key, (module, recorded, actual) in stored.items():
            self.assertEqual(recorded, actual, module)
        linked = self.receipt(self.project)['platform_archives']
        self.assertTrue(linked)
        self.assertEqual({(item['key'], item['sha256']) for item in linked},
                         {(key, recorded) for key, (_, recorded, _) in stored.items()})
        recipe = (self.project / '.flint/generated/dub/dub.sdl').read_text()
        self.assertIn('dependency "flint:arena" path="../deps/../platform"', recipe)
        self.assertIn('"--start-group"', recipe)
        platform = (self.project / '.flint/generated/platform/dub.sdl').read_text()
        self.assertIn('targetType "sourceLibrary"', platform)
        self.assertNotIn('sourcePaths', platform)

    def test_another_project_links_the_same_archives_without_compiling_them(self):
        other = self.directory / 'other'
        shutil.copytree(self.project, other, ignore=shutil.ignore_patterns('.flint'))
        built = flint('build', cwd=other, env=environment(FLINT_CACHE=str(self.cache)))
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        self.assertNotIn('Priming', built.stderr)
        self.assertEqual(self.receipt(other)['platform_archives'], self.receipt(self.project)['platform_archives'])
        ran = subprocess.run([str(other / '.flint/build/dev/demo')], cwd=other, capture_output=True, text=True,
                             timeout=60)
        self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)

    def test_a_local_rebuild_reproduces_every_archive(self):
        rebuilt = self.directory / 'rebuilt'
        shutil.copytree(self.project, rebuilt, ignore=shutil.ignore_patterns('.flint'))
        cache = self.directory / 'cache-b'
        built = flint('build', cwd=rebuilt, env=environment(FLINT_CACHE=str(cache)))
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        self.assertIn('Priming', built.stderr)
        self.assertEqual(entries(cache), entries(self.cache))

    def test_no_platform_cache_compiles_the_modules_from_source(self):
        plain = self.directory / 'plain'
        shutil.copytree(self.project, plain, ignore=shutil.ignore_patterns('.flint'))
        built = flint('build', '--no-platform-cache', cwd=plain, env=environment(FLINT_CACHE=str(self.cache)))
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        self.assertEqual(self.receipt(plain)['platform_archives'], [])
        self.assertNotIn('/platform"', (plain / '.flint/generated/dub/dub.sdl').read_text())

    def test_flint_platform_cache_0_turns_it_off(self):
        off = self.directory / 'off'
        shutil.copytree(self.project, off, ignore=shutil.ignore_patterns('.flint'))
        built = flint('build', cwd=off, env=environment(FLINT_CACHE=str(self.cache), FLINT_PLATFORM_CACHE='0'))
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        self.assertEqual(self.receipt(off)['platform_archives'], [])


if __name__ == '__main__':
    unittest.main()
