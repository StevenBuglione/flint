"""tools/native_build.py --retarget-dub: a disposable checkout's native DUB blocks point at another target's install
for a cross package (linux-x86_64-musl from a glibc host), behind a marker that makes other builds refuse."""
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import native_build  # noqa: E402

GLIBC, MUSL = 'linux-x86_64-glibc', 'linux-x86_64-musl'


class RetargetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.work = Path(self.temporary.name) / '.native'
        for target, libraries in ((GLIBC, ('libssl.a', 'libextra.a')), (MUSL, ('libssl.a',))):
            install = self.work / 'install' / target
            (install / 'lib').mkdir(parents=True)
            (install / 'flint-native-install.json').write_text('{}', encoding='utf-8')
            for library in libraries:
                (install / 'lib' / library).write_bytes(b'!<arch>\n')
        glibc = self.work.resolve() / 'install' / GLIBC / 'lib'
        self.recipe = Path(self.temporary.name) / 'dub.sdl'
        self.original = (f'name "engine-web"\n// not a block: {glibc}/libssl.a\n\n// BEGIN FLINT NATIVE\n'
                         f'lflags "{glibc}/libssl.a" platform="linux-x86_64"\n'
                         f'lflags "{glibc}/libextra.a" platform="linux-x86_64"\n// END FLINT NATIVE\n')
        self.recipe.write_text(self.original, encoding='utf-8')

    def tearDown(self):
        self.temporary.cleanup()

    def retarget(self, target):
        return native_build.retarget_dub(self.work, target, recipes=[self.recipe], host=GLIBC)

    def test_a_retarget_and_back_restores_the_recipe_and_removes_the_marker(self):
        result = self.retarget(MUSL)
        text = self.recipe.read_text(encoding='utf-8')
        self.assertEqual((self.work / 'dub-target').read_text(encoding='utf-8').strip(), MUSL)
        musl = str(self.work.resolve() / 'install' / MUSL / 'lib')
        self.assertIn(f'lflags "{musl}/libssl.a"', text)
        self.assertIn(f'// not a block: {self.work.resolve()}/install/{GLIBC}/lib/libssl.a', text,
                      'only the native block changes')
        self.assertEqual(result['missing_in_install'], [musl + '/libextra.a'],
                         'an archive the target lacks is reported, so its link fails loudly')
        self.retarget(GLIBC)
        self.assertEqual(self.recipe.read_text(encoding='utf-8'), self.original)
        self.assertFalse((self.work / 'dub-target').exists())

    def test_a_target_without_an_install_receipt_is_refused_and_nothing_changes(self):
        (self.work / 'install' / MUSL / 'flint-native-install.json').unlink()
        with self.assertRaisesRegex(ValueError, 'native_musl.py'):
            self.retarget(MUSL)
        self.assertEqual(self.recipe.read_text(encoding='utf-8'), self.original)
        self.assertFalse((self.work / 'dub-target').exists())

    def test_the_command_line_takes_retarget_dub(self):
        import subprocess
        done = subprocess.run([sys.executable, str(ROOT / 'tools/native_build.py'), '--help'], capture_output=True,
                              text=True)
        self.assertIn('--retarget-dub', done.stdout)


if __name__ == '__main__':
    unittest.main()
