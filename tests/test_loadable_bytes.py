"""incremental_linked_bytes measures loadable section bytes, not the page-rounded stripped file size
(decisions.md 2026-11-26 01:20Z): tools/measure_builds.py's section-listing parsers."""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import measure_builds  # noqa: E402

ELF = """There are 9 section headers, starting at offset 0x61b8:

Section Headers:
  [Nr] Name              Type            Address          Off    Size   ES Flg Lk Inf Al
  [ 0]                   NULL            0000000000000000 000000 000000 00      0   0  0
  [ 1] .note.gnu.property NOTE            0000000000000338 000338 000030 00   A  0   0  8
  [ 2] .text             PROGBITS        0000000000001000 001000 {text} 00  AX  0   0 16
  [ 3] .rodata           PROGBITS        0000000000002000 002000 000100 00   A  0   0 16
  [ 4] .tbss             NOBITS          0000000000003000 003000 000040 00 WAT  0   0  8
  [ 5] .data             PROGBITS        0000000000003000 003000 000020 00  WA  0   0  8
  [ 6] .bss              NOBITS          0000000000003020 003020 000010 00  WA  0   0  8
  [ 7] .comment          PROGBITS        0000000000000000 003020 00002b 01  MS  0   0  1
  [ 8] .shstrtab         STRTAB          0000000000000000 00304b 000050 00      0   0  1
Key to Flags:
  W (write), A (alloc), X (execute), M (merge), S (strings), I (info)
"""


class LoadableBytes(unittest.TestCase):
    def test_allocated_sections_count_and_the_rest_do_not(self):
        # .note 0x30 + .text 0x200 + .rodata 0x100 + .data 0x20 + .bss 0x10; .tbss, .comment and .shstrtab are out.
        self.assertEqual(measure_builds.elf_loadable_bytes(ELF.format(text='000200')), 0x30 + 0x200 + 0x100 + 0x20 + 0x10)

    def test_a_few_bytes_more_code_reads_as_those_bytes_not_a_page(self):
        before = measure_builds.elf_loadable_bytes(ELF.format(text='000200'))
        after = measure_builds.elf_loadable_bytes(ELF.format(text='000208'))
        self.assertEqual(after - before, 8)

    def test_macho_sections(self):
        listing = '\n'.join(['Section', '  sectname __text', '   segname __TEXT', '      size 0x0000000000000200',
                             'Section', '  sectname __bss', '   segname __DATA', '      size 0x0000000000000010',
                             'Section', '  sectname __thread_bss', '   segname __DATA', '      size 0x0000000000000040'])
        self.assertEqual(measure_builds.macho_loadable_bytes(listing), 0x210)

    @unittest.skipUnless(shutil.which('readelf') and shutil.which('cc'), 'needs readelf and a C compiler')
    def test_a_real_executable_has_its_loadable_bytes_below_its_rounded_file_size(self):
        with tempfile.TemporaryDirectory() as directory:
            source, binary = Path(directory) / 'probe.c', Path(directory) / 'probe'
            source.write_text('int main(void) { return 0; }\n')
            subprocess.run(['cc', '-O2', '-s', '-o', str(binary), str(source)], check=True)
            listing = subprocess.run(['readelf', '--wide', '--sections', str(binary)], check=True,
                                     capture_output=True, text=True).stdout
            loadable = measure_builds.elf_loadable_bytes(listing)
            self.assertGreater(loadable, 0)
            self.assertLess(loadable, binary.stat().st_size)


if __name__ == '__main__':
    unittest.main()
