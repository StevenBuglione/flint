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
        data = json.loads(record.read_text(encoding='utf-8'))
        if data['module'] == 'flint-platform-shared':
            continue  # a dev build's shared object: linked from the archives, not claimed byte-reproducible
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
        return json.loads((project / '.flint/build/dev/demo.receipt.json').read_text(encoding='utf-8'))

    def test_the_first_build_primes_the_cache_and_links_its_archives(self):
        self.assertIn('Priming', self.first.stderr)
        stored = entries(self.cache)
        self.assertTrue(stored, 'no archive was stored')
        for key, (module, recorded, actual) in stored.items():
            self.assertEqual(recorded, actual, module)
        linked = [item for item in self.receipt(self.project)['platform_archives']
                  if item['name'] != 'flint-platform-shared']
        self.assertTrue(linked)
        self.assertEqual({(item['key'], item['sha256']) for item in linked},
                         {(key, recorded) for key, (_, recorded, _) in stored.items()})
        recipe = (self.project / '.flint/generated/dub/dub.sdl').read_text(encoding='utf-8')
        self.assertIn('dependency "flint:arena" path="../deps/../platform"', recipe)
        # A dev build links the platform as one shared object (owner decision 2, 2026-11-23).
        self.assertIn('libflint-platform.so"', recipe)
        self.assertIn('"-defaultlib=libphobos2.so"', recipe)
        platform = (self.project / '.flint/generated/platform/dub.sdl').read_text(encoding='utf-8')
        self.assertIn('targetType "sourceLibrary"', platform)
        self.assertNotIn('sourcePaths', platform)
        prelude = (self.project / '.flint/generated/platform/dmd-server-prelude.txt').read_text(encoding='utf-8').splitlines()
        self.assertTrue(any(line.startswith('-I') for line in prelude), prelude)
        self.assertIn('flint.arena', prelude)

    def test_another_project_links_the_same_archives_without_compiling_them(self):
        other = self.directory / 'other'
        shutil.copytree(self.project, other, ignore=shutil.ignore_patterns('.flint'))
        built = flint('build', cwd=other, env=environment(FLINT_CACHE=str(self.cache)))
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        self.assertNotIn('Priming', built.stderr)
        self.assertEqual(self.receipt(other)['platform_archives'], self.receipt(self.project)['platform_archives'])
        ran = subprocess.run([str(other / '.flint/build/dev/demo')], cwd=other, capture_output=True, text=True, encoding='utf-8',
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

    def test_a_dev_build_runs_against_the_shared_platform_object(self):
        names = [item['name'] for item in self.receipt(self.project)['platform_archives']]
        self.assertIn('flint-platform-shared', names)
        shared = list((self.cache / 'platform').glob('shared-*/libflint-platform.so'))
        self.assertEqual(len(shared), 1, shared)
        ran = subprocess.run([str(self.project / '.flint/build/dev/demo')], cwd=self.project, capture_output=True,
                             text=True, encoding='utf-8', timeout=60)
        self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)

    def test_static_links_the_archives_into_a_dev_build(self):
        static = self.directory / 'static'
        shutil.copytree(self.project, static, ignore=shutil.ignore_patterns('.flint'))
        built = flint('build', '--static', cwd=static, env=environment(FLINT_CACHE=str(self.cache)))
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        recipe = (static / '.flint/generated/dub/dub.sdl').read_text(encoding='utf-8')
        self.assertIn('"--start-group"', recipe)
        self.assertNotIn('libflint-platform.so', recipe)
        self.assertNotIn('flint-platform-shared', [item['name'] for item in self.receipt(static)['platform_archives']])
        ran = subprocess.run([str(static / '.flint/build/dev/demo')], cwd=static, capture_output=True, text=True,
                             encoding='utf-8', timeout=60)
        self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)

    def test_a_dev_edit_builds_directly_without_dub(self):
        direct = self.directory / 'direct'
        shutil.copytree(self.project, direct, ignore=shutil.ignore_patterns('.flint'))
        env = environment(FLINT_CACHE=str(self.cache))
        first = flint('build', cwd=direct, env=env)
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        artifact = direct / '.flint/build/dev/demo'
        built = artifact.stat().st_mtime_ns
        again = flint('build', cwd=direct, env=env)
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertEqual(artifact.stat().st_mtime_ns, built, 'an up-to-date build relinks nothing')
        source = next((direct / 'src').rglob('*.d'))
        source.write_text(source.read_text(encoding='utf-8') + '\nprivate enum edited = 1;\n', encoding='utf-8',
                          newline='\n')
        edited = flint('build', cwd=direct, env=env)
        self.assertEqual(edited.returncode, 0, edited.stdout + edited.stderr)
        phases = self.receipt(direct)['phases_ms']
        self.assertEqual(phases['plan'], 0, phases)
        self.assertGreaterEqual(phases['compile'], 0, phases)
        self.assertGreaterEqual(phases['link'], 0, phases)
        ran = subprocess.run([str(artifact)], cwd=direct, capture_output=True, text=True, encoding='utf-8',
                             timeout=60)
        self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
        config = direct / 'config/application.toml'
        if config.is_file():
            config.write_text(config.read_text(encoding='utf-8') + '\n', encoding='utf-8', newline='\n')
            before = artifact.stat().st_mtime_ns
            rebuilt = flint('build', cwd=direct, env=env)
            self.assertEqual(rebuilt.returncode, 0, rebuilt.stdout + rebuilt.stderr)
            self.assertNotEqual(artifact.stat().st_mtime_ns, before, 'a string import changed')
        source.write_text(source.read_text(encoding='utf-8') + '\nprivate enum edited2 = 1;\n', encoding='utf-8',
                          newline='\n')
        dub = flint('build', cwd=direct, env=environment(FLINT_CACHE=str(self.cache), FLINT_DIRECT_BUILD='0'))
        self.assertEqual(dub.returncode, 0, dub.stdout + dub.stderr)
        self.assertGreater(self.receipt(direct)['phases_ms']['plan'], 0)

    def test_no_debug_builds_carry_no_debug_information_or_symbol_table(self):
        """Owner decision 4b27d207: measured builds match Go's -ldflags=-s -w, platform archives included."""
        def sections(path):
            listed = subprocess.run(['readelf', '-SW', str(path)], capture_output=True, text=True, encoding='utf-8')
            self.assertEqual(listed.returncode, 0, listed.stderr)
            return {line.split(']', 1)[1].split()[0] for line in listed.stdout.splitlines() if '] .' in line}

        debug_keys = {item['key'] for item in self.receipt(self.project)['platform_archives']}
        nodebug_cache = self.directory / 'cache-nodebug'  # the class's cache keeps only the first build's entries
        shutil.copytree(self.cache, nodebug_cache)
        for mode in ([], ['--static']):
            copy = self.directory / ('nodebug' + ''.join(mode))
            shutil.copytree(self.project, copy, ignore=shutil.ignore_patterns('.flint'))
            built = flint('build', '--no-debug', *mode, cwd=copy, env=environment(FLINT_CACHE=str(nodebug_cache)))
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            binary = copy / '.flint/build/dev/demo'
            names = sections(binary)
            self.assertFalse([name for name in names if name.startswith('.debug')], (mode, names))
            self.assertNotIn('.symtab', names, mode)
            linked = self.receipt(copy)['platform_archives']
            self.assertTrue(linked)
            self.assertFalse(debug_keys & {item['key'] for item in linked},
                             'a no-debug build never reuses an archive or shared object built with debug information')
            for item in linked:
                if item['name'] == 'flint-platform-shared':
                    shared = next((nodebug_cache / 'platform').glob('shared-' + item['key'] + '/libflint-platform.so'))
                    self.assertFalse([n for n in sections(shared) if n.startswith('.debug')])
                    self.assertNotIn('.symtab', sections(shared))
            ran = subprocess.run([str(binary)], cwd=copy, capture_output=True, text=True, encoding='utf-8', timeout=60)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)

    def test_a_static_replay_follows_added_and_removed_modules(self):
        """A static dev build replays DUB's recorded commands; a new or removed module, even in a new directory, must
        discard the record, and a replay must give DUB's binary byte for byte."""
        project = self.directory / 'replay'
        shutil.copytree(self.project, project, ignore=shutil.ignore_patterns('.flint'))
        env = environment(FLINT_CACHE=str(self.cache))
        binary = project / '.flint/build/dev/demo'
        greeting = project / 'src/demo/greeting.d'
        original = greeting.read_text(encoding='utf-8')

        def build(*extra, environment_=env):
            built = flint('build', '--static', *extra, cwd=project, env=environment_)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            return built.stderr

        def output():
            ran = subprocess.run([str(binary)], cwd=project, capture_output=True, text=True, encoding='utf-8',
                                 timeout=60)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            return ran.stdout

        def edit(text):
            greeting.write_text(text, encoding='utf-8', newline='\n')

        build()  # through DUB, recorded
        edit(original + '\n// edited\n')
        self.assertIn("DUB's recorded commands", build())
        self.assertIn('Hello, world!', output())

        extras = project / 'src/demo/extras'
        extras.mkdir()
        (extras / 'punctuation.d').write_text('module demo.extras.punctuation;\n\n@safe:\n\n/// More emphasis.\n'
                                              'string mark() pure\n{\n    return "?!";\n}\n', encoding='utf-8',
                                              newline='\n')
        edit(original.replace('module demo.greeting;', 'module demo.greeting;\n\nimport demo.extras.punctuation : mark;')
             .replace('"world") ~ "!";', '"world") ~ "!" ~ mark();'))
        self.assertNotIn("DUB's recorded commands", build(), 'a module in a new directory discards the record')
        self.assertIn('Hello, world!?!', output())

        edit(greeting.read_text(encoding='utf-8') + '\n// again\n')
        self.assertIn("DUB's recorded commands", build())
        replayed = binary.read_bytes()
        build('--force', environment_=environment(FLINT_CACHE=str(self.cache), FLINT_DIRECT_BUILD='0'))
        self.assertEqual(replayed, binary.read_bytes(), "a replay links DUB's binary byte for byte")

        shutil.rmtree(extras)
        edit(original)
        self.assertNotIn("DUB's recorded commands", build(), 'a removed module discards the record')
        self.assertIn('Hello, world!', output())
        self.assertNotIn('?!', output())

        # A string-imported file (config/ is the recipe's string import path): an edit re-runs the recorded
        # compile, which reads the new content; a new file discards the record.
        config = project / 'config/application.toml'
        build()
        before = binary.stat().st_mtime_ns
        config.write_text(config.read_text(encoding='utf-8') + '\n', encoding='utf-8', newline='\n')
        self.assertIn("DUB's recorded commands", build())
        self.assertNotEqual(binary.stat().st_mtime_ns, before, 'an edited string import rebuilds')
        (project / 'config/application-staging.toml').write_text('[app]\ngreeting = "Hi"\n', encoding='utf-8',
                                                                  newline='\n')
        self.assertNotIn("DUB's recorded commands", build(), 'a new string-import file discards the record')

    def test_a_build_of_another_configuration_keeps_the_platform_description(self):
        """DUB copies each library it builds into its package's directory. A description recorded for one
        configuration must survive another configuration's build: a cold build then reads the record and runs no
        `dub describe` (every certified cold trial re-described before, m7 2026-11-23)."""
        project = self.directory / 'describe'
        cache = self.directory / 'cache-describe'
        shutil.copytree(self.project, project, ignore=shutil.ignore_patterns('.flint'))
        shutil.copytree(self.cache, cache)
        # flint:term's pre-build command writes the C shim object its recipe links, so priming it rewrites a
        # directory inside the package as well.
        manifest = project / 'flint.toml'
        manifest.write_text(manifest.read_text(encoding='utf-8').replace('[dependencies]\n',
                                                                         '[dependencies]\n"flint:term" = {}\n'),
                            encoding='utf-8', newline='\n')
        env = environment(FLINT_CACHE=str(cache))
        locked = flint('lock', cwd=project, env=env)
        self.assertEqual(locked.returncode, 0, locked.stdout + locked.stderr)
        recorded = flint('build', '--no-debug', cwd=project, env=env)
        self.assertEqual(recorded.returncode, 0, recorded.stdout + recorded.stderr)
        # The same order as a certified run's priming: another configuration compiles the platform modules again.
        other = flint('build', cwd=project, env=env)
        self.assertEqual(other.returncode, 0, other.stdout + other.stderr)
        self.assertIn('Priming', other.stderr, 'the debug build compiles flint:term, which the class cache lacks')
        shutil.rmtree(project / '.flint')
        log = self.directory / 'describe.jsonl'
        cold = flint('build', '--no-debug', cwd=project, env=environment(FLINT_CACHE=str(cache), FLINT_LOG=str(log)))
        self.assertEqual(cold.returncode, 0, cold.stdout + cold.stderr)
        commands = [json.loads(line).get('fields', {}).get('argv', '') for line in log.read_text().splitlines()]
        self.assertFalse([c for c in commands if ' describe ' in c], 'the cold build re-described the platform')

    def test_no_platform_cache_compiles_the_modules_from_source(self):
        plain = self.directory / 'plain'
        shutil.copytree(self.project, plain, ignore=shutil.ignore_patterns('.flint'))
        built = flint('build', '--no-platform-cache', cwd=plain, env=environment(FLINT_CACHE=str(self.cache)))
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        self.assertEqual(self.receipt(plain)['platform_archives'], [])
        self.assertNotIn('/platform"', (plain / '.flint/generated/dub/dub.sdl').read_text(encoding='utf-8'))

    def test_flint_platform_cache_0_turns_it_off(self):
        off = self.directory / 'off'
        shutil.copytree(self.project, off, ignore=shutil.ignore_patterns('.flint'))
        built = flint('build', cwd=off, env=environment(FLINT_CACHE=str(self.cache), FLINT_PLATFORM_CACHE='0'))
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        self.assertEqual(self.receipt(off)['platform_archives'], [])


if __name__ == '__main__':
    unittest.main()
