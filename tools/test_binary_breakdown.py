"""Unit tests of the binary breakdown's attribution: `python3 tools/test_binary_breakdown.py`."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

import binary_breakdown


class Attribution(unittest.TestCase):
    def test_d_package_from_mangled_names(self):
        self.assertEqual(binary_breakdown.d_package('_D5flint3web7servlet3mvc6method3aot3fooFZv'), 'flint.web.servlet')
        self.assertEqual(binary_breakdown.d_package('_D5flint4java4util__T7HashSetTAyaZQn6__ctorMFZQs'), 'flint.java.util')
        self.assertEqual(binary_breakdown.d_package('_D5flint5serde8internal3fooFZv'), 'flint.serde')
        self.assertEqual(binary_breakdown.d_package('_D3std6format8internal6floats3fooFZv'), 'std.format')
        self.assertEqual(binary_breakdown.d_package('_D4core8internal5array3fooFZv'), 'core.internal')
        self.assertEqual(binary_breakdown.d_package('_D6object9Throwable6__initZ'), 'object')
        self.assertEqual(binary_breakdown.d_package('_D5flint4http9MediaType6__initZ'), 'flint.http')
        self.assertEqual(binary_breakdown.d_package('_D25TypeInfo_S5flint4http9MediaType6__initZ'), 'TypeInfo')
        # Negative: a name that is not a qualified D name stays unattributed rather than guessed.
        self.assertEqual(binary_breakdown.d_package('_D'), 'D (other)')
        self.assertEqual(binary_breakdown.identifiers('_D5flint'), ['flint'])

    def test_origin(self):
        owner = {'SSL_new': 'libssl', '__func__.0': 'C (ambiguous)'}
        self.assertEqual(binary_breakdown.origin('_D5flint3webQd', owner), 'D')
        self.assertEqual(binary_breakdown.origin('SSL_new', owner), 'libssl')
        self.assertEqual(binary_breakdown.origin('__func__.0', owner), 'C (ambiguous)')
        self.assertEqual(binary_breakdown.origin('memcpy', owner), 'C (unattributed)')

    @unittest.skipUnless(shutil.which('cc') and shutil.which('ar') and shutil.which('nm'), 'needs cc, ar and nm')
    def test_end_to_end_on_a_small_c_program(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / 'big.c').write_text('const char big_table[40000] = {1};\nint big(int i) { return big_table[i]; }\n')
            (root / 'local.c').write_text('static int helper(int i) { return i + 1; }\nint local(int i) { return helper(i); }\n')
            (root / 'main.c').write_text('int big(int); int local(int);\nint main(int c, char **v) { return big(c) + local(c); }\n')
            libraries = root / 'lib'
            libraries.mkdir()
            for name in ('big', 'local'):
                subprocess.run(['cc', '-c', '-O1', str(root / f'{name}.c'), '-o', str(root / f'{name}.o')], check=True)
                subprocess.run(['ar', 'rcs', str(libraries / f'lib{name}.a'), str(root / f'{name}.o')], check=True)
            executable = root / 'program'
            subprocess.run(['cc', str(root / 'main.c'), '-L', str(libraries), '-lbig', '-llocal', '-o', str(executable)],
                           check=True)
            report = binary_breakdown.breakdown(executable, libraries, 5)
            self.assertGreaterEqual(report['symbol_bytes_by_origin']['libbig'], 40000)
            self.assertIn('liblocal', report['symbol_bytes_by_origin'])
            self.assertLessEqual(report['stripped_bytes'], report['file_bytes'])
            self.assertEqual(report['largest_symbols'][0]['symbol'], 'big_table')


if __name__ == '__main__':
    unittest.main()
