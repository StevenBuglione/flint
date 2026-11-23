"""Flint's patched dfmt stacks user-defined attributes above declarations, as Java lays out annotations.

toolchain/dfmt-0.15.2-stack-udas.patch adds dfmt_stack_udas, which .editorconfig turns on; tools/quality.py,
`flint check` and `flint fmt` all run that one dfmt with that one configuration."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'tests/fixtures/dfmt_stack_udas'
SUFFIX = '+flint.stack-udas'


def dfmt():
    found = ROOT / '.tools/bin' / ('dfmt.exe' if os.name == 'nt' else 'dfmt')
    return str(found) if found.is_file() else shutil.which('dfmt')


@unittest.skipIf(dfmt() is None, 'dfmt is not installed (python3 tools/install_quality_tools.py)')
class StackedUdaTests(unittest.TestCase):
    def format(self, source, *options):
        # .editorconfig applies to *.d, so the input keeps that extension.
        with tempfile.TemporaryDirectory(prefix='flint-dfmt-') as temporary:
            path = Path(temporary) / 'input.d'
            path.write_text(source, encoding='utf-8')
            result = subprocess.run([dfmt(), '--config', str(ROOT), *options, str(path)], capture_output=True,
                                    text=True, encoding='utf-8')
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_the_installed_dfmt_is_flints(self):
        version = subprocess.run([dfmt(), '--version'], capture_output=True, text=True, encoding='utf-8').stdout
        self.assertIn(SUFFIX, version, 'run python3 tools/install_quality_tools.py')

    def test_user_defined_attributes_stack_above_their_declarations(self):
        expected = (FIXTURES / 'expected.d').read_text(encoding='utf-8')
        self.assertEqual(self.format((FIXTURES / 'input.d').read_text(encoding='utf-8')), expected)

    def test_stacked_output_is_stable(self):
        expected = (FIXTURES / 'expected.d').read_text(encoding='utf-8')
        self.assertEqual(self.format(expected), expected)

    def test_the_layout_follows_the_editorconfig_switch(self):
        source = '@RestController @RequestMapping("/api") class X\n{\n    @Autowired Service service;\n}\n'
        self.assertEqual(self.format(source),
                         '@RestController\n@RequestMapping("/api")\nclass X\n{\n    @Autowired\n    Service service;\n}\n')
        # Upstream's layout, which the switch replaces: dfmt joins the attributes onto the declaration's line.
        self.assertEqual(self.format(source, '--stack_udas=false'),
                         '@RestController @RequestMapping("/api") class X\n{\n    @Autowired Service service;\n}\n')

    def test_parameter_attributes_stay_inline(self):
        source = 'void get(@PathVariable("id") long id, @RequestParam string name)\n{\n}\n'
        self.assertEqual(self.format(source), source)


if __name__ == '__main__':
    unittest.main()
