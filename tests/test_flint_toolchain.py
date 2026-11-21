import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import install_toolchains  # noqa: E402

TOOLCHAIN = ROOT / 'toolchain'


def patched_files(patch):
    return sorted(re.findall(r'^\+\+\+ b/(\S+)', patch.read_text(), flags=re.M))


class ForkSourcesTests(unittest.TestCase):
    def test_prelude_holds_only_toolchain_modules(self):
        names = [line.strip() for line in (TOOLCHAIN / 'dmd-server-prelude.txt').read_text().splitlines()
                 if line.strip() and not line.startswith('#')]
        self.assertIn('object', names)
        self.assertEqual(len(names), len(set(names)))
        for name in names:
            self.assertRegex(name, r'^(object|core(\.\w+)+|std(\.\w+)+|etc(\.\w+)+)$')
            self.assertNotIn('flint', name)

    def test_dmd_patch_touches_driver_and_condition_recording_only(self):
        self.assertEqual(patched_files(TOOLCHAIN / 'dmd-2.114.0-flint.patch'),
                         ['build.d', 'dmd/cond.d', 'dmd/expressionsem.d', 'dmd/flintlink.d',
                          'dmd/flintserver.d', 'dmd/link.d', 'dmd/main.d'])

    def test_dub_patch_files(self):
        self.assertEqual(patched_files(TOOLCHAIN / 'dub-1.43.0-flint.patch'),
                         ['build-files.txt', 'source/app.d', 'source/dub/commandline.d',
                          'source/dub/compilers/compiler.d', 'source/dub/compilers/dmd.d',
                          'source/dub/generators/build.d', 'source/dub/internal/flintar.d',
                          'source/dub/internal/flinttrace.d'])

    def test_dub_source_is_checksum_locked(self):
        asset = install_toolchains.LOCK['assets']['dub-1.43.0.tar.gz']
        self.assertEqual(asset['url'], 'https://github.com/dlang/dub/archive/refs/tags/v1.43.0.tar.gz')
        self.assertRegex(asset['sha256'], r'^[0-9a-f]{64}$')

    @unittest.skipUnless(shutil.which('patch'), 'patch(1) unavailable')
    def test_patches_apply_to_pinned_sources(self):
        dmd_src = ROOT / '.tools' / 'dmd2' / 'src' / 'dmd'
        dub_archive = ROOT / '.tools' / 'flint-fork-build' / 'dub-src' / 'dub-1.43.0.tar.gz'
        checked = 0
        with tempfile.TemporaryDirectory(prefix='flint fork ') as temp:
            temp = Path(temp)
            if (dmd_src / 'build.d').is_file() and not (dmd_src / 'dmd' / 'flintserver.d').exists():
                shutil.copytree(dmd_src, temp / 'dmd')
                subprocess.run(['patch', '-p1', '--dry-run', '--quiet', '-d', str(temp / 'dmd'),
                                '-i', str(TOOLCHAIN / 'dmd-2.114.0-flint.patch')], check=True)
                checked += 1
            if dub_archive.is_file():
                with tarfile.open(dub_archive) as archive:
                    archive.extractall(temp / 'dub', filter='data')
                subprocess.run(['patch', '-p1', '--dry-run', '--quiet', '-d', str(temp / 'dub' / 'dub-1.43.0'),
                                '-i', str(TOOLCHAIN / 'dub-1.43.0-flint.patch')], check=True)
                checked += 1
        if not checked:
            self.skipTest('pinned DMD/DUB sources are not installed')


class InstallerArgumentTests(unittest.TestCase):
    def test_fork_requires_dmd(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tools' / 'install_toolchains.py'), '--compiler', 'ldc',
                                 '--flint-fork'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('--flint-fork applies only to --compiler dmd', result.stderr)


if __name__ == '__main__':
    unittest.main()
