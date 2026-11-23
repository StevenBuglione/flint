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
AARCH64_FILES = {
    'dmd/argtypes_aarch64.d', 'dmd/target.d', 'dmd/iasm/dmdaarch64.d',
    'dmd/glue/e2ir.d', 'dmd/glue/package.d', 'dmd/glue/todt.d', 'dmd/glue/toir.d',
    'dmd/backend/arm/cod1.d', 'dmd/backend/arm/cod2.d', 'dmd/backend/arm/cod3.d', 'dmd/backend/arm/cod4.d',
    'dmd/backend/arm/instr.d', 'dmd/backend/x86/cgcod.d', 'dmd/backend/x86/cod3.d',
    'dmd/backend/backconfig.d', 'dmd/backend/cgelem.d', 'dmd/backend/cgen.d', 'dmd/backend/cgsched.d',
    'dmd/backend/code.d', 'dmd/backend/codebuilder.d', 'dmd/backend/dout.d', 'dmd/backend/dwarfdbginf.d',
    'dmd/backend/dwarfeh.d', 'dmd/backend/el.d', 'dmd/backend/elfobj.d', 'dmd/backend/elpicpie.d',
    'dmd/backend/machobj.d',
}


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

    def test_dmd_patch_touches_driver_condition_recording_trace_naming_and_diagnostics_only(self):
        # hdrgen.d and timetrace.d: -ftime-trace event naming without semantic side effects.
        # errors.d, flintdiag.d and mars.d: -verror-hide, confined to the diagnostic sink (ADR-027 section 5).
        files = [f for f in patched_files(TOOLCHAIN / 'dmd-2.114.0-flint.patch') if f not in AARCH64_FILES]
        self.assertEqual(files,
                         ['build.d', 'dmd/cond.d', 'dmd/errors.d', 'dmd/expressionsem.d', 'dmd/flintdiag.d',
                          'dmd/flintlink.d', 'dmd/flintserver.d', 'dmd/hdrgen.d', 'dmd/link.d', 'dmd/main.d',
                          'dmd/mars.d', 'dmd/timetrace.d'])

    def test_dmd_patch_aarch64_sections_stay_in_the_code_generator(self):
        # ADR-025 section 3: the AArch64 back end, its object file writers and the target's ABI; x86-64 output
        # is unchanged (toolchain/arm64/README.md).
        files = patched_files(TOOLCHAIN / 'dmd-2.114.0-flint.patch')
        self.assertEqual([f for f in files if f in AARCH64_FILES], sorted(AARCH64_FILES))

    def test_arm64_overlay_and_runtime_patches(self):
        self.assertEqual(patched_files(TOOLCHAIN / 'dmd-2.114.0-flint-darwin.patch'),
                         ['dmd/flintlink.d', 'dmd/flintserver.d'])
        # std.math.hardware's FPSR/FPCR access; the rest are test thresholds for a 64-bit real
        self.assertEqual(patched_files(TOOLCHAIN / 'phobos-2.114.0-flint.patch'),
                         ['std/complex.d', 'std/internal/math/gammafunction.d', 'std/math/hardware.d'])
        druntime = patched_files(TOOLCHAIN / 'druntime-2.114.0-flint.patch')
        self.assertIn('src/core/internal/atomic_aarch64.c', druntime)
        for module in ('core/atomic.d', 'core/internal/atomic.d', 'core/math.d', 'core/thread/osthread.d',
                       'core/stdc/config.d', 'core/stdc/math.d', 'core/stdc/stdlib.d'):
            # the import tree the compiler reads matches the sources the library is built from
            self.assertIn('src/' + module, druntime)
            self.assertIn('import/' + module, druntime)
        self.assertTrue((TOOLCHAIN / 'arm64' / 'run.py').is_file())
        self.assertGreaterEqual(len(list((TOOLCHAIN / 'arm64').glob('*.d'))), 19)

    def test_dmd_patches_per_host(self):
        from unittest import mock
        for system, overlay in (('Linux', []), ('Windows', [install_toolchains.DMD_WINDOWS_PATCH]),
                                ('Darwin', [install_toolchains.DMD_DARWIN_PATCH])):
            with mock.patch.object(install_toolchains.platform, 'system', return_value=system):
                self.assertEqual(install_toolchains.dmd_patches(), [install_toolchains.DMD_PATCH] + overlay)

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
