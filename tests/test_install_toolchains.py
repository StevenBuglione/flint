import shlex
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
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
                    config.write_text(section32 + '[Environment64]\nDFLAGS=-I%@P%/phobos -L-L%@P%/lib -fPIC\n')
                    configure_dmd_linker(bin_dir, {'driver': driver, 'path': linker})
                    header, flags = config.read_text().split('[Environment64]\nDFLAGS=')
                    self.assertEqual(header, section32)
                    args = shlex.split(flags.replace('%@P%', str(bin_dir)))
                    self.assertEqual(args, ['-I' + str(bin_dir / 'phobos'), '-L-L' + str(bin_dir / 'lib'), '-fPIC',
                                            '-Xcc=-B' + str(bin_dir / 'flint-linker') + '/', '-Xcc=-fuse-ld=' + driver])
                    self.assertTrue((bin_dir / 'flint-linker' / ('ld.' + driver)).samefile(linker))

    def test_unrecognized_linker_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Expected ld.lld or mold'):
            identify_elf_linker(sys.executable)
