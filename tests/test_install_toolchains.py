import json
import shlex
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import install_toolchains
from install_toolchains import configure_dmd_linker, identify_elf_linker


class ProjectLinkerTests(unittest.TestCase):
    def test_relocatable_flags_and_private_elf_driver(self):
        with tempfile.TemporaryDirectory(prefix='flint tools ') as temp:
            root = Path(temp)
            bin_dir = root / 'bin'
            bin_dir.mkdir()
            config = bin_dir / 'dmd.conf'
            section32 = '[Environment32]\nDFLAGS=-m32\n\n'
            linker = root / 'external linker'
            linker.touch()
            for driver in ('lld', 'mold'):
                with self.subTest(driver=driver):
                    config.write_text(section32 + '[Environment64]\nDFLAGS=-I%@P%/phobos -L-L%@P%/lib -fPIC\n', encoding='utf-8', newline='\n')
                    configure_dmd_linker(bin_dir, {'driver': driver, 'path': linker})
                    header, flags = config.read_text(encoding='utf-8').split('[Environment64]\nDFLAGS=')
                    self.assertEqual(header, section32)
                    args = shlex.split(flags.replace('%@P%', str(bin_dir)))
                    # dmd.conf joins %@P% and the rest with '/', whatever the host's separator.
                    self.assertEqual(args, ['-I' + str(bin_dir) + '/phobos', '-L-L' + str(bin_dir) + '/lib', '-fPIC',
                                            '-Xcc=-B' + str(bin_dir) + '/flint-linker/', '-Xcc=-fuse-ld=' + driver])
                    self.assertTrue((bin_dir / 'flint-linker' / ('ld.' + driver)).samefile(linker))

    def test_aarch64_fork_configuration_takes_the_linker(self):
        # The AArch64 fork writes one [Environment] section (install_flint_fork); the linker is configured after it.
        with tempfile.TemporaryDirectory(prefix='flint tools ') as temp:
            bin_dir = Path(temp)
            linker = bin_dir / 'mold'
            linker.touch()
            (bin_dir / 'dmd.conf').write_text('[Environment]\nDFLAGS="-I%@P%/../../src/phobos" -marm64 -fPIC\n',
                                              encoding='utf-8', newline='\n')
            configure_dmd_linker(bin_dir, {'driver': 'mold', 'path': linker})
            self.assertEqual((bin_dir / 'dmd.conf').read_text(encoding='utf-8'),
                             '[Environment]\nDFLAGS="-I%@P%/../../src/phobos" -marm64 -fPIC '
                             '"-Xcc=-B%@P%/flint-linker/" -Xcc=-fuse-ld=mold\n')

    def test_mold_is_pinned_for_each_linux_architecture(self):
        # Linux AArch64 DMD links with mold too: the system BFD ld took 0.35-1.3 s for bench-cli in the arm64 VM.
        for machine, name in (('x86_64', 'mold-2.40.4-x86_64-linux'), ('aarch64', 'mold-2.40.4-aarch64-linux'),
                              ('arm64', 'mold-2.40.4-aarch64-linux')):
            self.assertEqual(install_toolchains.mold_name(machine), name)
            asset = install_toolchains.LOCK['assets'][name + '.tar.gz']
            self.assertEqual(asset['url'], 'https://github.com/rui314/mold/releases/download/v2.40.4/' + name + '.tar.gz')
            self.assertRegex(asset['sha256'], r'^[0-9a-f]{64}$')

    def test_unrecognized_linker_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Expected ld.lld or mold'):
            identify_elf_linker(sys.executable)


class SanitizerToolchainTests(unittest.TestCase):
    def test_llvm_subset_keeps_driver_resources_and_symbolizer_only(self):
        keep = install_toolchains.keep_llvm_member
        for name in ('bin/clang', 'bin/clang-22', 'bin/clang-tidy', 'bin/llvm-symbolizer', 'lib/clang/22/lib/x86_64-unknown-linux-gnu/libclang_rt.asan.a',
                     'lib/clang/22/include/stddef.h'):
            self.assertTrue(keep('LLVM-22.1.8-Linux-X64/' + name), name)
        for name in ('LLVM-22.1.8-Linux-X64/bin/clang-format', 'LLVM-22.1.8-Linux-X64/lib/libLLVMCore.a',
                     'LLVM-22.1.8-Linux-X64/bin/clang-22.backup', 'other/bin/clang'):
            self.assertFalse(keep(name), name)

    def test_sanitizer_runtime_receipt_binds_lock_inputs_and_library_hashes(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            (output / 'lib').mkdir()
            libraries = {}
            for name in install_toolchains.SANITIZER_LIBRARIES.values():
                path = output / 'lib' / ('lib' + name + '.a')
                path.write_bytes(name.encode())
                libraries[name] = {'sha256': install_toolchains.sha256_file(path), 'size': path.stat().st_size}
            receipt = {'inputs': install_toolchains.sanitizer_runtime_inputs(), 'libraries': libraries}
            (output / install_toolchains.SANITIZER_RUNTIME_RECEIPT).write_text(json.dumps(receipt), encoding='utf-8', newline='\n')
            self.assertEqual(install_toolchains.verified_sanitizer_runtime(output), receipt)
            self.assertIn('RT_SUPPORT_SANITIZERS=ON', receipt['inputs']['cmake'])
            (output / 'lib' / 'libdruntime-ldc-sanitizers.a').write_bytes(b'changed')
            self.assertIsNone(install_toolchains.verified_sanitizer_runtime(output))
            self.assertIsNone(install_toolchains.verified_sanitizer_runtime(output / 'missing'))

    def test_sanitizer_runtime_and_clang_sources_are_pinned(self):
        assets = install_toolchains.LOCK['assets']
        self.assertEqual(assets['ldc-1.43.0-src.tar.gz']['url'],
                         'https://github.com/ldc-developers/ldc/releases/download/v1.43.0/ldc-1.43.0-src.tar.gz')
        self.assertTrue(assets[install_toolchains.LLVM_ARCHIVE]['url'].startswith(
            'https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/'))
        for name in ('ldc-1.43.0-src.tar.gz', install_toolchains.LLVM_ARCHIVE):
            self.assertRegex(assets[name]['sha256'], r'^[0-9a-f]{64}$')
