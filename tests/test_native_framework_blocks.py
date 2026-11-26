"""tools/native_build.py --emit-dub: a policy/framework.json module that a native-lock library names as a consumer
gets the same verified native DUB block as a core package (framework/java-zip over the pinned zlib), and a module no
library names gets none."""
import argparse
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import native_build  # noqa: E402

TARGET = 'linux-x86_64-glibc'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class FrameworkNativeBlockTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        policy = self.root / 'policy'
        policy.mkdir()
        (policy / 'packages.json').write_text(json.dumps({'packages': {
            'engine-codec': {'repo': 'flint', 'dependencies': []}}}), encoding='utf-8')
        (policy / 'framework.json').write_text(json.dumps({'modules': {
            'java-zip': {'directory': 'framework/java-zip', 'repo': 'framework', 'dependencies': ['java'],
                         'bench': {'fixture': 'framework/java-zip/bench',
                                   'baseline': 'framework/java-zip/bench/baseline'}},
            'java': {'directory': 'framework/java', 'repo': 'framework', 'dependencies': []}}}), encoding='utf-8')
        for directory in ('packages/engine-codec', 'packages/engine-codec/bench/baseline', 'framework/java-zip',
                          'framework/java-zip/bench/baseline', 'framework/java'):
            (self.root / directory).mkdir(parents=True)
            (self.root / directory / 'dub.sdl').write_text('name "x"\n', encoding='utf-8')
        install = self.root / '.native' / 'install' / TARGET / 'lib'
        install.mkdir(parents=True)
        archives = {}
        for name in ('libz.a', 'libflint_ffi_framework.a', 'libflint_ffi_base.a'):
            (install / name).write_bytes(b'!<arch>\n' + name.encode())
            archives[name] = {'path': str(install / name), 'sha256': sha256(install / name)}
        self.zlib = install / 'libz.a'
        self.rows = {'zlib': {'name': 'zlib', 'consumers': ['engine-codec', 'java-zip'], 'dependencies': []}}
        self.builder = native_build.Builder.__new__(native_build.Builder)
        self.builder.a = argparse.Namespace(target=TARGET, phase='build')
        self.builder.rows = self.rows
        self.builder.receipt = {'target': TARGET, 'libraries': {'zlib': {'archives': [archives['libz.a']]}},
                                'ffi_archives': {'framework': archives['libflint_ffi_framework.a'],
                                                 'base': archives['libflint_ffi_base.a']}}
        self.original_root = native_build.ROOT
        native_build.ROOT = self.root

    def tearDown(self):
        native_build.ROOT = self.original_root
        self.temporary.cleanup()

    def test_only_a_framework_module_a_library_consumes_is_a_native_package(self):
        packages = native_build.native_packages(self.rows)
        self.assertEqual(sorted(packages), ['engine-codec', 'java-zip'])
        self.assertEqual(packages['java-zip'], {'repo': 'framework', 'directory': 'framework/java-zip',
                                                'baseline': 'framework/java-zip/bench/baseline',
                                                'dependencies': ['java']})
        self.assertEqual(packages['engine-codec']['directory'], 'packages/engine-codec')

    def test_a_framework_consumer_gets_the_verified_block_in_its_own_directory(self):
        recipes = self.builder.dub_recipe_blocks()
        self.assertEqual(sorted(recipes), ['framework/java-zip/bench/baseline/dub.sdl', 'framework/java-zip/dub.sdl',
                                           'packages/engine-codec/bench/baseline/dub.sdl',
                                           'packages/engine-codec/dub.sdl'])
        block = recipes['framework/java-zip/dub.sdl']
        self.assertIn('versions "FlintNativeZlib" platform="linux-x86_64"', block)
        # A framework-repo package links flint_ffi_framework, then flint_ffi_base, then the provider archives.
        lines = [line for line in block.splitlines() if line.startswith('lflags ')]
        self.assertEqual([json.loads(line.split(' ', 1)[1].rsplit(' platform=', 1)[0]) for line in lines[:3]], [
            self.builder.receipt['ffi_archives']['framework']['path'],
            self.builder.receipt['ffi_archives']['base']['path'], str(self.zlib)])
        # The core package's block is unchanged: it links only the flint repo's shims.
        self.assertNotIn('libflint_ffi_framework.a', recipes['packages/engine-codec/dub.sdl'])

    def test_emit_writes_the_framework_recipes_and_replaces_an_old_block(self):
        self.builder.emit_dub()
        self.builder.emit_dub()
        for relative in ('framework/java-zip/dub.sdl', 'framework/java-zip/bench/baseline/dub.sdl'):
            text = (self.root / relative).read_text(encoding='utf-8')
            self.assertEqual(text.count('// BEGIN FLINT NATIVE'), 1, relative)
            self.assertTrue(text.startswith('name "x"\n'))
        self.assertNotIn('BEGIN FLINT NATIVE', (self.root / 'framework/java/dub.sdl').read_text(encoding='utf-8'))
        self.assertEqual(sorted(path.relative_to(self.root).as_posix() for path in native_build.native_recipes(
            {'libraries': list(self.rows.values())})), [
            'framework/java-zip/bench/baseline/dub.sdl', 'framework/java-zip/dub.sdl',
            'packages/engine-codec/bench/baseline/dub.sdl', 'packages/engine-codec/dub.sdl'])

    def test_a_changed_archive_is_refused_for_a_framework_consumer_too(self):
        self.rows['zlib']['consumers'] = ['java-zip']
        self.zlib.write_bytes(b'!<arch>\nchanged')
        with self.assertRaisesRegex(RuntimeError, 'Installed archive changed'):
            self.builder.dub_blocks()

    def test_a_framework_consumer_without_a_baseline_gets_only_its_own_recipe(self):
        modules = json.loads((self.root / 'policy/framework.json').read_text(encoding='utf-8'))
        del modules['modules']['java-zip']['bench']
        (self.root / 'policy/framework.json').write_text(json.dumps(modules), encoding='utf-8')
        self.assertIn('framework/java-zip/dub.sdl', self.builder.dub_recipe_blocks())
        self.assertNotIn('framework/java-zip/bench/baseline/dub.sdl', self.builder.dub_recipe_blocks())


if __name__ == '__main__':
    unittest.main()
