"""The class-monitor gate (FLINT-E0536, tools/check_class_monitor.py).

Run: `python3 -m unittest tests.test_class_monitor_gate`.

The fixtures under tests/fixtures/class-monitor/ mark each line the gate must reject with `// expect: FLINT-E0536`.
"""
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import check_class_monitor as gate  # noqa: E402

FIXTURES = ROOT / 'tests/fixtures/class-monitor'
RECIPE = 'name "{name}"\ntargetType "library"\nsourcePaths "source"\nimportPaths "source"\n'


def compiler_or_skip(test, explicit=None):
    try:
        return gate.compiler_path(explicit)
    except gate.GateError as error:
        test.skipTest(str(error))


def expected_lines(directory):
    found = set()
    for path in directory.rglob('*.d'):
        for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
            if '// expect: FLINT-E0536' in line:
                found.add((path.relative_to(directory).as_posix(), number))
    return found


def run(directory, compiler=None):
    return gate.check(directory, tops=('.',), compiler=compiler, extra_roots=[])


def project(root, name, files):
    """A throwaway DUB package under `root` with `files` ({module path: source})."""
    directory = root / name
    (directory / 'source').mkdir(parents=True)
    (directory / 'dub.sdl').write_text(RECIPE.format(name=name), encoding='utf-8')
    for relative, text in files.items():
        path = directory / 'source' / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
    return directory


class Rejects(unittest.TestCase):
    def test_every_metadata_argument_is_rejected_at_its_line(self):
        compiler_or_skip(self)
        result = run(FIXTURES / 'reject')
        self.assertEqual(result.errors, [])
        self.assertEqual({(f, n) for f, n, _, _ in result.findings}, expected_lines(FIXTURES / 'reject'))
        self.assertFalse(result.ok)
        line = result.lines()[0]
        self.assertRegex(line, r'^source/monitor_fixture/reject\.d:\d+: FLINT-E0536: ')
        self.assertIn('lock a dedicated `new Mutex()` instead of giving class metadata a GC-allocated monitor', line)
        self.assertIn('class metadata never owns a GC monitor', line)

    def test_ldc_reaches_the_same_verdict(self):
        dmd = compiler_or_skip(self)
        # The pinned LDC sits beside the pinned DMD (.tools/ldc2-*/bin/ldmd2), else on PATH.
        ldc = sorted(ROOT.glob('.tools/ldc2-*/bin/ldmd2')) + sorted(dmd.parents[3].glob('ldc2-*/bin/ldmd2'))
        ldc = ldc or [shutil.which('ldmd2')]
        if not ldc[0]:
            self.skipTest('no ldmd2')
        result = run(FIXTURES / 'reject', compiler=str(ldc[0]))
        self.assertEqual(result.errors, [])
        self.assertEqual({(f, n) for f, n, _, _ in result.findings}, expected_lines(FIXTURES / 'reject'))

    def test_a_public_alias_declared_elsewhere_is_followed(self):
        compiler_or_skip(self)
        with tempfile.TemporaryDirectory() as temporary:
            directory = project(Path(temporary), 'alias', {
                'locks.d': 'module locks;\nimport core.sync.mutex : Mutex;\nalias Guard = Mutex;\n',
                'user.d': 'module user;\nimport locks : Guard;\nclass Foo {}\n'
                          'void use() { auto g = new Guard(typeid(Foo)); }\n',
            })
            result = run(directory)
        self.assertEqual([(f, n) for f, n, _, _ in result.findings], [('source/user.d', 4)])

    def test_a_module_the_gate_cannot_type_check_fails_closed(self):
        compiler_or_skip(self)
        with tempfile.TemporaryDirectory() as temporary:
            directory = project(Path(temporary), 'broken', {
                'broken.d': 'module broken;\nimport core.sync.mutex : Mutex;\nimport nowhere.to.be.found;\n'
                            'void use() { auto m = new Mutex(); }\n',
            })
            result = run(directory)
        self.assertFalse(result.ok)
        self.assertEqual(result.findings, [])
        self.assertIn('could not type-check', result.errors[0][2])


class Accepts(unittest.TestCase):
    def test_dedicated_mutexes_ordinary_objects_and_synchronized_metadata_pass(self):
        compiler_or_skip(self)
        result = run(FIXTURES / 'accept')
        self.assertEqual((result.findings, result.errors), ([], []))
        self.assertEqual((result.modules, result.compiles), (1, 1))
        self.assertTrue(result.ok)

    def test_a_tree_without_watched_names_compiles_nothing(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = project(Path(temporary), 'plain', {'plain.d': 'module plain;\nint answer() { return 42; }\n'})
            result = run(directory)
        self.assertTrue(result.ok)
        self.assertEqual((result.modules, result.compiles), (0, 0))

    def test_the_whole_repository_passes(self):
        compiler_or_skip(self)
        result = gate.check(ROOT)
        self.assertEqual(result.lines(), [])
        self.assertGreater(result.modules, 0)


class RecipeParsing(unittest.TestCase):
    def test_a_directive_attribute_is_not_a_version(self):
        # A local native block: `platform="..."` filters the directive, it does not add a version.
        self.assertEqual(gate._sdl_values('versions "FlintNativeHiredis" platform="linux-x86_64"', 'versions'),
                         ['FlintNativeHiredis'])
        self.assertEqual(gate._sdl_values('    versions "A" "B"', 'versions'), ['A', 'B'])


class Suppressions(unittest.TestCase):
    def test_a_suppressed_line_passes_and_its_unsuppressed_copy_fails(self):
        compiler_or_skip(self)
        result = run(FIXTURES / 'suppressed')
        self.assertEqual(result.errors, [])
        self.assertEqual({(f, n) for f, n, _, _ in result.findings}, expected_lines(FIXTURES / 'suppressed'))
        self.assertEqual([reason for _, _, reason in result.suppressed],
                         ["the verifier's negative test", "the verifier's negative test, shared"])
        self.assertIn('2 suppression(s) honoured', result.summary())

    def test_removing_the_suppressions_fails_every_line(self):
        compiler_or_skip(self)
        with tempfile.TemporaryDirectory() as temporary:
            copy = Path(temporary) / 'suppressed'
            shutil.copytree(FIXTURES / 'suppressed', copy)
            path = copy / 'source/monitor_fixture/suppressed.d'
            path.write_text(re.sub(r'\s*// flint: allow-class-monitor \([^)]*\)', '', path.read_text(encoding='utf-8')),
                            encoding='utf-8')
            result = run(copy)
        self.assertEqual(len(result.findings), 3)
        self.assertEqual(result.suppressed, [])

    def test_a_suppression_needs_a_reason_and_a_finding(self):
        compiler_or_skip(self)
        with tempfile.TemporaryDirectory() as temporary:
            directory = project(Path(temporary), 'reasons', {
                'reasons.d': 'module reasons;\nimport core.sync.mutex : Mutex;\nclass Foo {}\nvoid use()\n{\n'
                             '    auto a = new Mutex(typeid(Foo)); // flint: allow-class-monitor ()\n'
                             '    auto b = new Mutex(typeid(Foo)); // flint: allow-class-monitor\n'
                             '    auto c = new Mutex(); // flint: allow-class-monitor (nothing to allow)\n}\n',
            })
            result = run(directory)
        self.assertEqual([n for _, n, _, _ in result.findings], [6, 7])
        self.assertEqual([(n, message) for _, n, message, _ in result.errors], [
            (6, 'a class-monitor suppression needs a reason: `// flint: allow-class-monitor (why this is deliberate)`'),
            (7, 'a class-monitor suppression needs a reason: `// flint: allow-class-monitor (why this is deliberate)`'),
            (8, 'a class-monitor suppression matches no finding')])


class CommandLine(unittest.TestCase):
    def test_exit_status_and_report(self):
        compiler_or_skip(self)
        with tempfile.TemporaryDirectory() as temporary:
            for fixture, status in (('reject', 1), ('accept', 0)):
                # --root scans the standard source roots, so stage the fixture as a package.
                root = Path(temporary) / fixture
                shutil.copytree(FIXTURES / fixture, root / 'packages' / fixture)
                done = subprocess.run([sys.executable, str(ROOT / 'tools/check_class_monitor.py'), '--root', str(root)],
                                      capture_output=True, text=True)
                self.assertEqual(done.returncode, status, done.stdout + done.stderr)
                self.assertIn('class-monitor gate (FLINT-E0536): 1 module(s) type-checked', done.stdout)


if __name__ == '__main__':
    unittest.main()
