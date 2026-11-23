"""End-to-end checks of the flint CLI (Milestone 7) against the Python tools it takes over from.

The flint binary is bootstrapped by tools/install_toolchains.py --compiler flint when it is missing.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import install_toolchains  # noqa: E402
import profiles  # noqa: E402

FLINT = ROOT / '.flint' / 'bin' / 'flint'
# The executable that fills the DMD role: the forked DMD, or LDC's ldmd2 on macOS (ADR-024) and on Linux arm64
# until the DMD fork's AArch64 code generator lands there (ADR-025 section 3).
LDMD_HOST = sys.platform == 'darwin' or install_toolchains.linux_arm64_glibc()
DMD_BIN = (ROOT / '.tools' / install_toolchains.LDC_DARWIN / 'bin' if sys.platform == 'darwin'
           else ROOT / '.tools' / install_toolchains.LDC_LINUX_AARCH64 / 'bin' if LDMD_HOST
           else ROOT / '.tools' / 'dmd2' / 'linux' / 'bin64')


def environment(**extra):
    env = {k: v for k, v in os.environ.items() if k not in ('DFLAGS', 'FLINT_HOME', 'FLINT_COLOR')}
    env['PATH'] = str(DMD_BIN) + os.pathsep + env.get('PATH', '')
    env.update(extra)
    return env


def flint(*args, cwd=ROOT, env=None):
    return subprocess.run([str(FLINT), *args], cwd=cwd, env=env or environment(), capture_output=True, text=True)


def flint_json(*args, cwd=ROOT, env=None):
    args = list(args)
    split = args.index('--') if '--' in args else len(args)
    result = flint(*args[:split], '--json', *args[split:], cwd=cwd, env=env)
    document = json.loads(result.stdout)
    for key in ('schema', 'ok', 'exit_code', 'diagnostics'):
        assert key in document, (key, result.stdout)
    assert document['exit_code'] == result.returncode, (document, result.returncode)
    return result.returncode, document


def codes(document):
    return [item['code'] for item in document['diagnostics'] if item['severity'] == 'error']


def error(document, code):
    """The first error with `code`. Hosts without a toolchain receipt also report warnings, so never index."""
    return next(item for item in document['diagnostics'] if item['severity'] == 'error' and item['code'] == code)


def setUpModule():
    if not FLINT.is_file():
        subprocess.run([sys.executable, str(ROOT / 'tools/install_toolchains.py'), '--compiler', 'flint'],
                       cwd=ROOT, env=environment(), check=True, stdout=subprocess.DEVNULL)


class SharedPolicyTests(unittest.TestCase):
    def test_measurement_flags_unchanged_by_the_move_to_policy(self):
        import measure_builds
        self.assertEqual(measure_builds.native_profiles(), {
            'dmd': ['-preview=dip1000', '-debug', '-g', '-boundscheck=on'],
            'O3': ['-preview=dip1000', '-release', '-boundscheck=safeonly', '-O3', '--flto=thin',
                   '-link-defaultlib-shared=false'],
            'Oz': ['-preview=dip1000', '-release', '-boundscheck=safeonly', '-Oz', '--flto=thin',
                   '-link-defaultlib-shared=false']})
        self.assertEqual(measure_builds.native_profiles('/x/ld.lld')['O3'][-1], '-linker=/x/ld.lld')

    def test_sanitizer_flags_unchanged_by_the_move_to_policy(self):
        import ci
        self.assertEqual(' '.join(ci.sanitizer_dflags()),
                         '-g -O1 -unittest -preview=dip1000 -boundscheck=on -fsanitize=address '
                         '-defaultlib=' + install_toolchains.SANITIZER_DEFAULTLIB
                         + ' -gcc=clang -Xcc=-fsanitize=address,undefined')
        self.assertEqual(profiles.load()['test']['build_type'], 'unittest')

    def test_policy_schema_is_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'profiles.toml'
            path.write_text((ROOT / 'policy/profiles.toml').read_text() + '\n[profile.extra]\ncompiler = "dmd"\n')
            with self.assertRaises(ValueError):
                profiles.load(path)

    def test_bootstrap_recipe_equals_the_recipe_flint_generates(self):
        flint('build', '--project', str(ROOT / 'apps/flint'))
        generated = ROOT / 'apps/flint/.flint/generated/dub/dub.sdl'
        manifest = tomllib.loads((ROOT / 'apps/flint/flint.toml').read_text())
        # A verified DMD fork adds `-verror-hide`, which only changes how diagnostics read (ADR-027 section 5).
        lines = [line for line in generated.read_text().splitlines(True) if not line.startswith('dflags "-verror-hide=')]
        self.assertEqual(''.join(lines), install_toolchains.flint_recipe(manifest))


class StructuralParityTests(unittest.TestCase):
    """flint check --gate structural reaches tools/gates.py's verdict on the same inputs."""

    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-parity-')
        cls.base = Path(cls.temporary.name) / 'base'
        ignore = shutil.ignore_patterns('.dub', 'build', '*.a', '*.o', 'flint-*-test-*', '__pycache__')
        cls.base.mkdir()
        for name in ('policy', 'packages', 'tools', 'toolchain'):
            shutil.copytree(ROOT / name, cls.base / name, ignore=ignore, symlinks=True)
        for name in ('dub.sdl', 'flint.toml', 'dscanner.ini', 'dfmt.ini', '.editorconfig'):
            shutil.copy2(ROOT / name, cls.base / name)
        (cls.base / '.tools').symlink_to((ROOT / '.tools').resolve())

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def verdicts(self, package, mutate=None):
        work = Path(self.temporary.name) / 'work'
        if work.exists():
            shutil.rmtree(work)
        shutil.copytree(self.base, work, symlinks=True)
        if mutate:
            mutate(work)
        gate = subprocess.run([sys.executable, str(work / 'tools/gates.py'), '--gate', 'structural', '--package', package],
                              cwd=work, env=environment(), capture_output=True, text=True)
        status, document = flint_json('check', '--gate', 'structural', '--package', package, cwd=work,
                                      env=environment(FLINT_HOME=str(work)))
        if gate.returncode == 0:
            # The text output is byte-identical; the JSON schema always carries compiler_profiles.
            human = flint('check', '--gate', 'structural', '--package', package, cwd=work,
                          env=environment(FLINT_HOME=str(work)))
            self.assertEqual(human.stdout, gate.stdout)
            expected = json.loads(gate.stdout)
            expected['generated_dependencies'].setdefault('compiler_profiles', 0)
            expected.setdefault('repo', '')
            expected.setdefault('pending_repo_edges', [])
            self.assertEqual(expected, document['structural'])
        return gate.returncode == 0, status == 0, gate.stderr, codes(document)

    def assert_same(self, package, mutate, code):
        python_pass, flint_pass, message, found = self.verdicts(package, mutate)
        self.assertFalse(python_pass, 'gates.py accepted the mutation')
        self.assertFalse(flint_pass, 'flint accepted the mutation: ' + message)
        self.assertIn(code, found, message)

    def test_unmodified_workspace_passes_both(self):
        for package in ('cli', 'serde', 'arena', 'os'):
            python_pass, flint_pass, message, found = self.verdicts(package)
            self.assertTrue(python_pass and flint_pass, (package, message, found))

    def test_mutations_fail_both(self):
        def edit(relative, old, new):
            def apply(work):
                path = work / relative
                text = path.read_text()
                self.assertIn(old, text)
                path.write_text(text.replace(old, new, 1))
            return apply

        def append(relative, text):
            def apply(work):
                path = work / relative
                path.write_text(path.read_text() + text)
            return apply

        cli = 'packages/cli/source/flint/cli/types.d'
        cases = [
            ('cli', edit(cli, '@safe:', ''), 'FLINT-E0501'),
            ('cli', edit(cli, 'module flint.cli.types;', 'module flint.cli.kinds;'), 'FLINT-E0401'),
            ('cli', edit(cli, 'import flint.arena : Error;', 'import flint.arena : Error;\nimport flint.log : Logger;'),
             'FLINT-E0507'),
            ('cli', edit(cli, 'import flint.arena : Error;', 'import flint.arena.sys.pool : Error;'), 'FLINT-E0508'),
            ('cli', append(cli, '\nvoid unsafeThing() @trusted nothrow {}\n'), 'FLINT-E0502'),
            ('cli', append(cli, '\nenum generated = 1;\nmixin("int x;");\n'), 'FLINT-E0506'),
            ('arena', append('packages/arena/source/flint/arena/sys/pool.d', '\nvoid raw() @trusted nothrow {}\n'),
             'FLINT-E0503'),
            ('arena', append('packages/arena/source/flint/arena/sys/pool.d', '\n// SAFETY: x\n@trusted:\n'),
             'FLINT-E0504'),
            ('cli', edit('packages/cli/dub.sdl', 'dependency "flint:validate" version="*"', ''), 'FLINT-E0525'),
            ('cli', edit('dub.sdl', 'subPackage "packages/cli"\n', ''), 'FLINT-E0524'),
            # The repo split (plan section 7): flint's log may not depend on the framework's di.
            ('arena', edit('policy/packages.json', '"repo": "flint",\n      "dependencies": [\n        "arena",\n'
                           '        "conc"', '"repo": "flint",\n      "dependencies": [\n        "arena",\n'
                           '        "di",\n        "conc"'), 'FLINT-E0532'),
        ]
        for package, mutate, code in cases:
            with self.subTest(code=code):
                self.assert_same(package, mutate, code)


class FixturePeerTests(unittest.TestCase):
    """flint test wraps a package's test binary in its declared peers and never skips a missing one (ADR-018)."""

    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-peers-')
        cls.work = Path(cls.temporary.name) / 'work'
        ignore = shutil.ignore_patterns('.dub', 'build', '*.a', '*.o', 'flint-*-test-*', '__pycache__')
        cls.work.mkdir()
        for name in ('policy', 'packages', 'tools', 'toolchain'):
            shutil.copytree(ROOT / name, cls.work / name, ignore=ignore, symlinks=True)
        for name in ('dub.sdl', 'flint.toml', 'dscanner.ini', 'dfmt.ini', '.editorconfig'):
            shutil.copy2(ROOT / name, cls.work / name)
        (cls.work / '.tools').symlink_to((ROOT / '.tools').resolve())
        cls.policy = cls.work / 'policy/test-peers.toml'
        cls.original = cls.policy.read_text()

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_arena(self, peers, packages):
        policy = self.original.replace('[packages]\n', peers + '[packages]\narena = ' + packages + '\n')
        self.policy.write_text(policy)
        return flint_json('test', 'arena', cwd=self.work, env=environment(FLINT_HOME=str(self.work)))

    def test_declared_peers_wrap_the_test_binary_outermost_first(self):
        log = Path(self.temporary.name) / 'peer-order'
        log.write_text('')
        # Each probe appends its name, exports a variable and runs the rest of the command line.
        script = ('import os, subprocess, sys; open(sys.argv[1], "a").write(sys.argv[2] + "\\n"); '
                  'sys.exit(subprocess.call(sys.argv[3:], env=dict(os.environ, FLINT_PROBE=sys.argv[2])))')
        peers = ''.join('[peer.%s]\ndescription = "probe"\ncommand = ["python3", "-c", %s, "%s", "%s"]\n\n'
                        % (name, json.dumps(script), log, name) for name in ('outer', 'inner'))
        status, document = self.run_arena(peers, '["outer", "inner"]')
        self.assertEqual(status, 0, document['diagnostics'])
        run = document['runs'][0]
        self.assertEqual((run['ok'], run['peers'], run['missing_peers']), (True, ['outer', 'inner'], []))
        self.assertIn('modules passed unittests', run['peer_summary'])
        self.assertEqual(log.read_text().split(), ['outer', 'inner'])

    def test_a_failing_peer_run_fails_the_package(self):
        peers = '[peer.broken]\ndescription = "probe"\ncommand = ["python3", "-c", "import sys; sys.exit(3)"]\n\n'
        status, document = self.run_arena(peers, '["broken"]')
        self.assertEqual((status, codes(document)), (1, ['FLINT-E0702']))
        self.assertIn('against broken', error(document, 'FLINT-E0702')['message'])

    def test_missing_peer_is_named_and_fails_the_run(self):
        peers = ('[binary.absent]\ndescription = "an unpinned fixture"\npath = ".flint/peers/absent"\n'
                 'unpinned = "absent has no pinned release"\n\n'
                 '[peer.absent]\ndescription = "probe"\ncommand = ["python3", "-c", "pass", "{bin:absent}"]\n\n')
        status, document = self.run_arena(peers, '["absent"]')
        self.assertEqual((status, codes(document)), (2, ['FLINT-E0815']), document['diagnostics'])
        run = document['runs'][0]
        self.assertEqual((run['ok'], run['missing_peers'], run['peers']), (False, ['absent'], []))
        self.assertIn('modules passed unittests', run['summary'])
        self.assertIn('absent has no pinned release', error(document, 'FLINT-E0815')['message'])


class ProjectLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='flint-project-')
        cls.directory = Path(cls.temporary.name)
        status, document = flint_json('new', 'demo', cwd=cls.directory)
        assert status == 0, document
        cls.project = cls.directory / 'demo'

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_new_build_run_test_check(self):
        status, built = flint_json('build', cwd=self.project)
        self.assertEqual(status, 0, built)
        self.assertEqual(built['schema'], 'flint.build/1')
        receipt = json.loads((self.project / '.flint/build/dev/demo.receipt.json').read_text())
        self.assertEqual(receipt['schema'], 'flint.receipt/1')
        self.assertEqual(receipt['profile']['effective_dflags'], profiles.dflags('dev'))
        self.assertEqual(receipt['outputs'][0]['sha256'], install_toolchains.sha256_file(self.project / '.flint/build/dev/demo'))

        status, ran = flint_json('run', '--', '--name', 'Ada', cwd=self.project)
        self.assertEqual(status, 0, ran)
        self.assertIn('Hello, Ada!\n', ran['program']['stdout_text'].splitlines(keepends=True))
        self.assertIn('message="greeting delivered"', ran['program']['stdout_text'])
        status, prod = flint_json('run', cwd=self.project, env=environment(FLINT_PROFILE='prod'))
        self.assertIn('Good day, world!\n', prod['program']['stdout_text'].splitlines(keepends=True))

        status, tested = flint_json('test', cwd=self.project)
        self.assertEqual(status, 0, tested)
        self.assertEqual(tested['passed'], 1)
        status, checked = flint_json('check', cwd=self.project)
        self.assertEqual(status, 0, checked)
        status, verified = flint_json('receipt', str(self.project / '.flint/build/dev/demo'), cwd=self.project)
        self.assertEqual(status, 0, verified)

    def test_new_is_deterministic_and_never_overwrites(self):
        status, first = flint_json('new', 'same', '--plan', cwd=self.directory)
        status2, second = flint_json('new', 'same', '--plan', cwd=self.directory)
        self.assertEqual(first, second)
        self.assertFalse((self.directory / 'same').exists())
        status, existing = flint_json('new', 'demo', cwd=self.directory)
        self.assertEqual((status, codes(existing)), (4, ['FLINT-E0006']))

    def test_stable_exit_codes(self):
        with tempfile.TemporaryDirectory() as temporary:
            status, document = flint_json('build', cwd=temporary)
            self.assertEqual((status, codes(document)), (4, ['FLINT-E0101']))
        status, document = flint_json('build', '--profile', 'nope', cwd=self.project)
        self.assertEqual((status, codes(document)), (4, ['FLINT-E0003']))
        status, document = flint_json('explain', 'FLINT-E9999')
        self.assertEqual((status, codes(document)), (4, ['FLINT-E0005']))
        status, document = flint_json('frobnicate')
        self.assertEqual((status, codes(document)), (4, ['FLINT-E0001']))

    def test_manifest_and_lock_failures(self):
        work = self.directory / 'broken'
        if work.exists():
            shutil.rmtree(work)
        shutil.copytree(self.project, work, ignore=shutil.ignore_patterns('.flint'))
        manifest = work / 'flint.toml'
        original = manifest.read_text()
        manifest.write_text(original.replace('version = "0.1.0"', 'verison = "0.1.0"'))
        status, document = flint_json('build', cwd=work)
        self.assertEqual(status, 1)
        typo = next(item for item in document['diagnostics'] if item['code'] == 'FLINT-E0103')
        self.assertEqual((typo['fix'], typo['file'], typo['line']), ('did you mean `version`?', 'flint.toml', 3))
        manifest.write_text(original.replace('"flint:log" = {}\n', '"flint:log" = {}\n"flint:di" = {}\n'))
        status, document = flint_json('build', cwd=work)
        self.assertEqual((status, codes(document)), (3, ['FLINT-E0202']))
        stale = next(item for item in document['diagnostics'] if item['code'] == 'FLINT-E0202')
        self.assertIn('added flint:di', stale['message'])
        status, document = flint_json('lock', cwd=work)
        self.assertEqual((status, document['state']), (0, 'written'))
        status, document = flint_json('lock', '--check', cwd=work)
        self.assertEqual((status, document['state']), (0, 'current'))

    def test_build_rejects_unsafe_sources_with_locations(self):
        work = self.directory / 'unsafe'
        if work.exists():
            shutil.rmtree(work)
        shutil.copytree(self.project, work, ignore=shutil.ignore_patterns('.flint'))
        source = work / 'src/demo/greeting.d'
        source.write_text(source.read_text().replace('@safe:', '') + '\nvoid poke() @trusted nothrow {}\n')
        (work / 'src/demo/stray.d').write_text('module demo.elsewhere;\n@safe:\n')
        (work / 'config/application.yaml').write_text('app:\n  greeting: no\n')
        status, document = flint_json('check', cwd=work)
        self.assertEqual(status, 1)
        self.assertTrue({'FLINT-E0501', 'FLINT-E0502', 'FLINT-E0401', 'FLINT-E0407'} <= set(codes(document)),
                        codes(document))
        located = next(item for item in document['diagnostics'] if item['code'] == 'FLINT-E0401')
        self.assertEqual((located['file'], located['line']), ('src/demo/stray.d', 1))
        manifest = work / 'flint.toml'
        manifest.write_text(manifest.read_text() + '\n[[waivers]]\nrule = "FLINT-E0401"\nfile = "src/demo/stray.d"\n'
                            'reason = "fixture"\n')
        status, document = flint_json('check', cwd=work)
        self.assertNotIn('FLINT-E0401', codes(document))
        self.assertEqual(document['waived'], 1)

    def test_receipt_detects_tampering(self):
        status, built = flint_json('build', cwd=self.project)
        self.assertEqual(status, 0, built)
        artifact = self.project / '.flint/build/dev/demo'
        (self.directory / 'tampered').mkdir(exist_ok=True)
        copy = self.directory / 'tampered' / 'demo'
        shutil.copy2(artifact, copy)
        shutil.copy2(artifact.with_name('demo.receipt.json'), copy.with_name('demo.receipt.json'))
        with copy.open('ab') as stream:
            stream.write(b'\0')
        status, document = flint_json('receipt', str(copy))
        self.assertEqual((status, codes(document)), (2, ['FLINT-E0902']))


class KnowledgeTests(unittest.TestCase):
    def test_explain_and_catalogue(self):
        status, document = flint_json('explain', 'e0401')
        self.assertEqual(status, 0)
        self.assertEqual(document['codes'][0]['code'], 'FLINT-E0401')
        status, listing = flint_json('explain', '--list')
        self.assertGreater(len(listing['codes']), 60)
        self.assertEqual(len({item['code'] for item in listing['codes']}), len(listing['codes']))

    def test_version_doctor_and_daemon_report_json(self):
        status, version = flint_json('version')
        self.assertEqual((status, version['tool']['release'], version['tool']['platform']), (0, '0.7.0', '1.0'))
        status, doctor = flint_json('doctor')
        self.assertIn(status, (0, 2))
        self.assertTrue({'installation', 'dmd', 'fork', 'compile server'} <= {c['name'] for c in doctor['checks']})
        if LDMD_HOST:
            # The compile server belongs to the Linux x86-64 DMD fork (ADR-024).
            status, refused = flint_json('daemon', 'start')
            self.assertEqual((status, codes(refused)), (2, ['FLINT-E0810']))
            return
        with tempfile.TemporaryDirectory(dir='/tmp') as runtime:
            env = environment(XDG_RUNTIME_DIR=runtime)
            status, started = flint_json('daemon', 'start', env=env)
            self.assertEqual(status, 0, started)
            self.assertTrue(any(s['alive'] and s['flags'] == profiles.dflags('dev') for s in started['servers']))
            status, listed = flint_json('daemon', 'status', env=env)
            self.assertEqual(len([s for s in listed['servers'] if s['alive']]), 1)
            status, stopped = flint_json('daemon', 'stop', env=env)
            self.assertEqual(status, 0)
            status, after = flint_json('daemon', 'status', env=env)
            self.assertEqual(after['servers'], [])
        with tempfile.TemporaryDirectory(dir='/tmp') as runtime:
            deep = Path(runtime) / ('x' * 100)
            deep.mkdir()
            status, refused = flint_json('daemon', 'start', env=environment(XDG_RUNTIME_DIR=str(deep)))
            self.assertEqual((status, codes(refused)), (2, ['FLINT-E0810']))
            self.assertIn('too long', refused['diagnostics'][0]['message'])


if __name__ == '__main__':
    unittest.main()
