"""Diagnostics v2 (Milestone 9, ADR-027 section 5): every framework misuse in tests/compile/misuse yields one
readable error that names the field, handler or service; with the DMD fork's -verror-hide it is reported at the
user's line, not inside the library. Each fixture's second line is `// expect: <regex>` for that error.
"""
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import ci  # noqa: E402

MISUSE = ROOT / 'tests' / 'compile' / 'misuse'
TOOLS = Path(os.environ.get('FLINT_TOOLCHAIN_DIR') or ROOT / '.tools')
import install_toolchains  # noqa: E402

# The forked DMD fills the DMD role; on macOS and Linux arm64 with its AArch64 code generator (ADR-025 section 3).
DMD = TOOLS / 'dmd2' / ('osx' if sys.platform == 'darwin' else 'linux') / 'bin64' / 'dmd'
# flint condenses the fork's diagnostics on Linux x86-64 only (flint_tool.engine.builder.condensedDiagnostics).
FORK_HOST = sys.platform == 'linux' and os.uname().machine in ('x86_64', 'amd64')
ERROR = re.compile(r'^(?P<file>.+?)\((?P<line>\d+)(?:,\d+)?\): Error: (?P<message>.*)$')


def hide_flags():
    """The flags flint adds for the fork (flint_tool.engine.builder.condensedDiagnostics)."""
    bin_dir = DMD.parent
    spellings = [ROOT / 'packages', Path(str(bin_dir) + '/../../src'), (bin_dir / '../../src').resolve()]
    if (ROOT / '.flint' / 'platform').is_dir():  # after the cutover the engines are in the platform modules
        spellings.append(ROOT / '.flint' / 'platform')
    return ['-verror-hide=' + str(path) + '/' for path in spellings]


def compile_fixture(source, extra=()):
    command = [str(DMD), '-c', '-o-', '-preview=dip1000', *ci.import_flags(), *extra, str(source)]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr


def errors(output):
    return [match for match in map(ERROR.match, output.splitlines()) if match]


def expectation(source):
    line = source.read_text().splitlines()[1]
    assert line.startswith('// expect: '), source
    return re.compile(line[len('// expect: '):])


class MisuseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixtures = sorted(MISUSE.glob('*.d'))
        assert len(cls.fixtures) >= 8, cls.fixtures

    def test_every_misuse_is_rejected_first_by_an_error_naming_the_field(self):
        # Any DMD or LDC: the library's check is the first error. A check that runs during CTFE is followed by the
        # compiler's generic "error instantiating", which only the fork's condensing folds into it.
        for source in self.fixtures:
            with self.subTest(source.name):
                status, output = compile_fixture(source)
                self.assertEqual(status, 1, output)
                found = errors(output)
                self.assertIn(len(found), (1, 2), output)
                self.assertRegex(found[0]['message'], expectation(source), output)
                if len(found) == 2:
                    self.assertIn('error instantiating', found[1]['message'], output)

    def test_the_fork_reports_it_at_the_users_line(self):
        if not FORK_HOST:
            self.skipTest('no DMD fork on this host (ADR-024, ADR-026)')
        status, output = self.probe_hide_support()
        self.assertEqual(status, 0, 'the installed DMD fork predates toolchain/dmd-2.114.0-flint.patch and does not '
                         'know -verror-hide; rebuild it with `flint toolchain install`:\n' + output)
        for source in self.fixtures:
            with self.subTest(source.name):
                status, output = compile_fixture(source, hide_flags())
                self.assertEqual(status, 1, output)
                found = errors(output)
                self.assertEqual(len(found), 1, output)
                self.assertEqual(Path(found[0]['file']).resolve(), source.resolve(), output)
                self.assertRegex(found[0]['message'], expectation(source), output)
                # The library's own message, without DMD's `static assert:  "..."` wrapper.
                self.assertFalse(found[0]['message'].startswith('static assert:'), output)
                self.assertRegex(output, r'raised in library code at .*packages/.*, through \d+ hidden frames?')
                self.assertNotIn('instantiated from here', output)

    def test_condensing_changes_no_object_byte(self):
        if not FORK_HOST:
            self.skipTest('no DMD fork on this host (ADR-024, ADR-026)')
        status, output = self.probe_hide_support()
        self.assertEqual(status, 0, output)
        sources = [ROOT / 'tests/compile/positive.d', ROOT / 'tests/compile/reactor_protocol.d']
        with tempfile.TemporaryDirectory(prefix='flint-diagnostics-') as temporary:
            for source in sources:
                objects = []
                for index, extra in enumerate(([], hide_flags())):
                    output = Path(temporary) / f'{source.stem}-{index}.o'
                    subprocess.run([str(DMD), '-c', '-preview=dip1000', '-debug', '-g', *ci.import_flags(), *extra,
                                    str(source), '-of' + str(output)], cwd=ROOT, check=True, capture_output=True)
                    objects.append(output.read_bytes())
                self.assertEqual(objects[0], objects[1], source.name)

    def probe_hide_support(self):
        with tempfile.TemporaryDirectory(prefix='flint-diagnostics-') as temporary:
            empty = Path(temporary) / 'empty.d'
            empty.write_text('module empty;\n')
            result = subprocess.run([str(DMD), '-c', '-o-', '-verror-hide=/nonexistent/', str(empty)],
                                    capture_output=True, text=True)
            return result.returncode, result.stdout + result.stderr


if __name__ == '__main__':
    unittest.main()
