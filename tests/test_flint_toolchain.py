import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
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
    'dmd/backend/machobj.d', 'dmd/backend/cc.d', 'dmd/lib/mach.d',
}


def patched_files(patch):
    # A file may have two sections: dmd/glue/package.d has a Flint one (-fno-moduleinfo-localclasses) and an
    # AArch64 one.
    return sorted(set(re.findall(r'^\+\+\+ b/(\S+)', patch.read_text(encoding='utf-8'), flags=re.M)))


class ForkSourcesTests(unittest.TestCase):
    def test_prelude_holds_only_toolchain_modules(self):
        names = [line.strip() for line in (TOOLCHAIN / 'dmd-server-prelude.txt').read_text(encoding='utf-8').splitlines()
                 if line.strip() and not line.startswith('#')]
        self.assertIn('object', names)
        self.assertEqual(len(names), len(set(names)))
        for name in names:
            self.assertRegex(name, r'^(object|core(\.\w+)+|std(\.\w+)+|etc(\.\w+)+)$')
            self.assertNotIn('flint', name)

    def test_dmd_patch_touches_driver_condition_recording_trace_naming_and_diagnostics_only(self):
        # hdrgen.d and timetrace.d: -ftime-trace event naming without semantic side effects.
        # errors.d, flintdiag.d and mars.d: -verror-hide, confined to the diagnostic sink (ADR-027 section 5).
        # templatesem.d: a served compile emits the template instances an in-process one would (platform prelude).
        # flintaot.d and typesem.d: -flint-aot-extract, an output switch like -X (stripDefaultArgs made public).
        files = [f for f in patched_files(TOOLCHAIN / 'dmd-2.114.0-flint.patch') if f not in AARCH64_FILES]
        self.assertEqual(files,
                         ['build.d', 'dmd/cond.d', 'dmd/errors.d', 'dmd/expressionsem.d', 'dmd/flintaot.d',
                          'dmd/flintdiag.d', 'dmd/flintlink.d', 'dmd/flintserver.d', 'dmd/hdrgen.d', 'dmd/link.d',
                          'dmd/main.d', 'dmd/mars.d', 'dmd/templatesem.d', 'dmd/timetrace.d', 'dmd/typesem.d'])

    def test_dmd_patch_leaves_out_local_classes_on_request(self):
        # ADR-030 section 5: -fno-moduleinfo-localclasses, named as LDC's, empties ModuleInfo.localClasses.
        text = (TOOLCHAIN / 'dmd-2.114.0-flint.patch').read_text(encoding='utf-8')
        self.assertIn('+        else if (arg == "-fno-moduleinfo-localclasses")', text)
        self.assertIn('+public __gshared bool flintNoLocalClasses;', text)
        self.assertIn('+    if (!flintNoLocalClasses)\n+        getLocalClasses(m, aclasses);', text)

    def test_dmd_patch_aarch64_sections_stay_in_the_code_generator(self):
        # ADR-025 section 3: the AArch64 back end, its object file writers and the target's ABI; x86-64 output
        # is unchanged (toolchain/arm64/README.md).
        files = patched_files(TOOLCHAIN / 'dmd-2.114.0-flint.patch')
        self.assertEqual([f for f in files if f in AARCH64_FILES], sorted(AARCH64_FILES))

    def test_arm64_overlay_and_runtime_patches(self):
        self.assertEqual(patched_files(TOOLCHAIN / 'dmd-2.114.0-flint-darwin.patch'),
                         ['dmd/flintlink.d', 'dmd/flintserver.d'])
        # std.math.hardware's FPSR/FPCR access and std.conv's exact decimal parsing with a 64-bit real;
        # the rest are test thresholds for a 64-bit real
        self.assertEqual(patched_files(TOOLCHAIN / 'phobos-2.114.0-flint.patch'),
                         ['std/complex.d', 'std/conv.d', 'std/internal/math/gammafunction.d', 'std/math/hardware.d'])
        druntime = patched_files(TOOLCHAIN / 'druntime-2.114.0-flint.patch')
        self.assertIn('src/core/internal/atomic_aarch64.c', druntime)
        for module in ('core/atomic.d', 'core/internal/atomic.d', 'core/math.d', 'core/thread/osthread.d',
                       'core/stdc/config.d', 'core/stdc/math.d', 'core/stdc/stdlib.d'):
            # the import tree the compiler reads matches the sources the library is built from
            self.assertIn('src/' + module, druntime)
            self.assertIn('import/' + module, druntime)
        self.assertTrue((TOOLCHAIN / 'arm64' / 'run.py').is_file())
        self.assertGreaterEqual(len(list((TOOLCHAIN / 'arm64').glob('*.d'))), 19)

    def test_fork_reads_stat_mtime_on_every_host(self):
        # LDC's druntime for Linux AArch64 has st_mtime and st_mtimensec, not st_mtim: the fork reads st_mtim only
        # where stat_t has it, or Flint cannot bootstrap there.
        for patch in ('dmd-2.114.0-flint.patch', 'dmd-2.114.0-flint-darwin.patch'):
            added = [line[1:] for line in (TOOLCHAIN / patch).read_text(encoding='utf-8').splitlines() if line.startswith('+')]
            for i, line in enumerate(added):
                if re.search(r'\.st_mtim\b', line):
                    self.assertIn('__traits(hasMember, stat_t, "st_mtim")', added[i - 1], f'{patch}: {line.strip()}')

    def test_dmd_patches_per_host(self):
        from unittest import mock
        for system, overlay in (('Linux', []), ('Windows', [install_toolchains.DMD_WINDOWS_PATCH]),
                                ('Darwin', [install_toolchains.DMD_DARWIN_PATCH])):
            with mock.patch.object(install_toolchains.platform, 'system', return_value=system):
                self.assertEqual(install_toolchains.dmd_patches(), [install_toolchains.DMD_PATCH] + overlay)

    def test_dub_patches_per_host(self):
        from unittest import mock
        for system, overlay in (('Linux', []), ('Windows', [install_toolchains.DUB_WINDOWS_PATCH]),
                                ('Darwin', [install_toolchains.DUB_DARWIN_PATCH])):
            with mock.patch.object(install_toolchains.platform, 'system', return_value=system):
                self.assertEqual(install_toolchains.dub_patches(), [install_toolchains.DUB_PATCH] + overlay)
        self.assertEqual(patched_files(TOOLCHAIN / 'dub-1.43.0-flint-darwin.patch'), ['source/dub/internal/flintar.d'])

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
                # Each host's overlay applies on top of the shared patch (f3419a15 changed the shared patch's
                # compile server imports, and Windows' overlay stopped applying).
                subprocess.run(['patch', '-p1', '--quiet', '-d', str(temp / 'dmd'),
                                '-i', str(TOOLCHAIN / 'dmd-2.114.0-flint.patch')], check=True)
                for overlay in ('dmd-2.114.0-flint-windows.patch', 'dmd-2.114.0-flint-darwin.patch'):
                    subprocess.run(['patch', '-p1', '--dry-run', '--quiet', '-d', str(temp / 'dmd'),
                                    '-i', str(TOOLCHAIN / overlay)], check=True)
                checked += 1
            if dub_archive.is_file():
                with tarfile.open(dub_archive) as archive:
                    archive.extractall(temp / 'dub', filter='data')
                subprocess.run(['patch', '-p1', '--dry-run', '--quiet', '-d', str(temp / 'dub' / 'dub-1.43.0'),
                                '-i', str(TOOLCHAIN / 'dub-1.43.0-flint.patch')], check=True)
                checked += 1
        if not checked:
            self.skipTest('pinned DMD/DUB sources are not installed')


class FlintDubTests(unittest.TestCase):
    def test_compiler_family_comes_from_the_binary_name(self):
        # DUB matched "dmd" anywhere in the compiler path, so LDC under a directory such as dmd-tools/ (or a
        # checkout in ~/work/dmd-arm64/) was driven with DMD's switches and failed its platform probe.
        dubs = [ROOT / '.tools' / directory / 'dub' for directory in ('dub-1.43.0/bin', 'dmd2/linux/bin64')]
        dub = next((d for d in dubs if d.is_file()), None)
        ldc = next(iter(sorted((ROOT / '.tools').glob('ldc2-1.43.0-*/bin/ldc2'))), None)
        if dub is None or ldc is None or sys.platform == 'win32':
            self.skipTest('the Flint DUB and the pinned LDC are not installed')
        with tempfile.TemporaryDirectory(prefix='flint dub ') as temp:
            temp = Path(temp)
            (temp / 'dmd-tools').mkdir()
            (temp / 'dmd-tools' / 'ldc2').symlink_to(ldc)
            package = temp / 'probe'
            (package / 'source').mkdir(parents=True)
            (package / 'dub.sdl').write_text('name "probe"\n', encoding='utf-8', newline='\n')
            (package / 'source' / 'app.d').write_text('void main() {}\n', encoding='utf-8', newline='\n')
            env = dict(os.environ, DUB_HOME=str(temp / 'dub-home'), HOME=str(temp))
            result = subprocess.run([str(dub), 'describe', '--root', str(package), '--skip-registry=all',
                                     '--compiler=' + str(temp / 'dmd-tools' / 'ldc2')],
                                    capture_output=True, text=True, encoding='utf-8', env=env, timeout=300)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(result.stdout)['compiler'], 'ldc')


def toolchain_tool(name):
    """A tool of the toolchain under test: FLINT_TOOLCHAIN_DIR's when set (as flint reads it), else this checkout's
    .tools; None when it is not installed."""
    tools = Path(os.environ.get('FLINT_TOOLCHAIN_DIR') or ROOT / '.tools')
    path = tools / 'dmd2' / 'linux' / 'bin64' / name
    return path if path.is_file() else None


class DubPipelineTests(unittest.TestCase):
    """The Flint DUB's parallel pipeline takes a graph with a pre-build command and a C source (41053ce3): flint:term
    builds its terminal object in a pre-build script and flint:os has a C source, and either one used to send a whole
    application graph down DUB's serial path."""

    def test_a_pre_build_command_and_a_c_source_take_the_pipeline(self):
        dub, dmd = toolchain_tool('dub'), toolchain_tool('dmd')
        if dub is None or dmd is None or sys.platform != 'linux':
            self.skipTest('the Flint DUB and DMD are not installed')
        with tempfile.TemporaryDirectory(prefix='flint-pipeline-') as temp:
            temp = Path(temp)

            def write(path, text):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding='utf-8', newline='\n')

            # pre: its pre-build command writes the file the app string-imports, so it must run before the app
            # compiles, and it appends to a log, so it must run once.
            write(temp / 'pre/dub.sdl', 'name "pre"\ntargetType "library"\n'
                  'preBuildCommands "sh stamp.sh"\n')
            write(temp / 'pre/stamp.sh', 'mkdir -p views\necho ran >> ../pre-build.log\n'
                  'printf generated > views/stamp.txt\n')
            write(temp / 'pre/source/pre/value.d', 'module pre.value;\n\nint preValue() { return 1; }\n')
            # cpart: a C source beside a D module, compiled by DMD (ImportC).
            write(temp / 'cpart/dub.sdl', 'name "cpart"\ntargetType "library"\nsourceFiles "c/answer.c"\n')
            write(temp / 'cpart/c/answer.c', 'int c_answer(void) { return 41; }\n')
            write(temp / 'cpart/source/cpart/answer.d', 'module cpart.answer;\n\nextern (C) int c_answer();\n\n'
                  'int answer() { return c_answer() + 1; }\n')
            write(temp / 'app/dub.sdl', 'name "app"\ntargetType "executable"\nstringImportPaths "../pre/views"\n'
                  'dependency "pre" path="../pre"\ndependency "cpart" path="../cpart"\n')
            write(temp / 'app/source/app.d', 'import std.stdio : writeln;\nimport cpart.answer : answer;\n'
                  'import pre.value : preValue;\n\nenum stamp = import("stamp.txt");\n\n'
                  'void main() { writeln(stamp, " ", answer() + preValue()); }\n')
            env = dict(os.environ, DUB_HOME=str(temp / 'dub-home'), HOME=str(temp), FLINT_DMD_SERVER='0')
            env.pop('FLINT_DUB_PIPELINE', None)
            built = subprocess.run([str(dub), 'build', '--root', str(temp / 'app'), '--skip-registry=all',
                                    '--compiler=' + str(dmd), '-v'], capture_output=True, text=True,
                                   encoding='utf-8', env=env, timeout=600)
            output = built.stdout + built.stderr
            self.assertEqual(built.returncode, 0, output)
            self.assertRegex(output, r'Compiling \d+ modules in \d+ parallel jobs', 'the pipeline built the graph')
            self.assertEqual((temp / 'pre-build.log').read_text(encoding='utf-8'), 'ran\n', 'the pre-build ran once')
            jobs = [line for line in output.splitlines() if line.strip().startswith('[cwd=') and ' -c ' in line]
            c_jobs = [line for line in jobs if 'answer.c' in line]
            self.assertEqual(len(c_jobs), 1, jobs)
            self.assertIn('answer.d', c_jobs[0], 'the C source compiles in its target\'s one job')
            ran = subprocess.run([str(temp / 'app' / 'app')], capture_output=True, text=True, timeout=60)
            self.assertEqual(ran.stdout.strip(), 'generated 43', ran.stdout + ran.stderr)


def fork_dmd():
    """The installed DMD fork when it serves a platform prelude (FLINT_DMD_SERVER_PRELUDE), else None."""
    for host, exe in (('linux', 'dmd'), ('osx', 'dmd'), ('windows', 'dmd.exe')):
        dmd = ROOT / '.tools' / 'dmd2' / host / 'bin64' / exe
        if dmd.is_file() and b'FLINT_DMD_SERVER_PRELUDE' in dmd.read_bytes():
            return dmd
    return None


class CompileServerPreludeTests(unittest.TestCase):
    """The compile server's platform prelude (item 23, ADR-030 section 5): FLINT_DMD_SERVER_PRELUDE names a file of
    -I and -version= lines and module names that the server analyses once, beside druntime and Phobos."""

    PLATFORM = {
        # twice!int is instantiated at module level by a module the app never imports (CTFE in an initializer).
        'plat/twice.d': 'module plat.twice;\nT twice(T)(T x) { return x * 2; }\n',
        'plat/boot.d': 'module plat.boot;\npublic import plat.twice;\nversion (PlatformOn) enum platformOn = true;\n',
        'plat/unused.d': 'module plat.unused;\nimport plat.twice;\nenum int doubled = twice!int(21);\n'
                         '__gshared int[doubled] table;\n',
    }
    APP = 'import plat.boot;\nstatic assert(platformOn);\nint main() { return twice!int(21) == 42 ? 0 : 1; }\n'

    def setUp(self):
        self.dmd = fork_dmd()
        if self.dmd is None or sys.platform == 'win32':
            self.skipTest('the installed DMD fork predates the platform prelude (install_toolchains.py --compiler dmd '
                          '--flint-fork)')
        self.temp = Path(tempfile.mkdtemp(prefix='flint-prelude-'))
        self.addCleanup(shutil.rmtree, self.temp, True)
        self.addCleanup(self.stop_servers)
        for name, text in self.PLATFORM.items():
            (self.temp / 'lib' / name).parent.mkdir(parents=True, exist_ok=True)
            (self.temp / 'lib' / name).write_text(text, encoding='utf-8')
        (self.temp / 'app.d').write_text(self.APP, encoding='utf-8')
        self.prelude = self.temp / 'prelude.txt'
        self.write_prelude()
        # The server's socket lives here: keep its path within macOS's 104-byte sun_path ($TMPDIR is long there).
        self.runtime = Path(tempfile.mkdtemp(prefix='fp-', dir='/tmp'))
        self.addCleanup(shutil.rmtree, self.runtime, True)
        self.trace = self.temp / 'trace.txt'
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.runtime), FLINT_DMD_SERVER_IDLE='60',
                        FLINT_DMD_SERVER_PRELUDE=str(self.prelude), FLINT_DMD_SERVER_TRACE=str(self.trace))
        self.env.pop('FLINT_DMD_SERVER', None)
        self.env.pop('DFLAGS', None)

    def write_prelude(self, extra=''):
        self.prelude.write_text(f'-I{self.temp / "lib"}\n-version=PlatformOn\nplat.boot\nplat.unused\n{extra}',
                                encoding='utf-8')

    def stop_servers(self):
        listing = subprocess.run(['ps', '-axo', 'pid=,command='], capture_output=True, text=True).stdout
        for line in listing.splitlines():
            pid, _, command = line.strip().partition(' ')
            if str(self.runtime) in command and pid.isdigit():
                try:
                    os.kill(int(pid), 9)
                except OSError:
                    pass

    def sockets(self):
        return sorted((self.runtime / 'flint-dmd').glob('*.sock'))

    def compile(self, *args, env=None):
        return subprocess.run([str(self.dmd), *args], cwd=self.temp, env=env or self.env, capture_output=True,
                              text=True, timeout=300)

    def served(self, *args, env=None, sockets=1):
        """Compiles until a server answers: the first request starts it and compiles in-process. Returns the
        result and the server's verdict, 'compiled' or 'refused'."""
        result = self.compile(*args, env=env)
        for _ in range(600):
            if len(self.sockets()) >= sockets:
                break
            time.sleep(0.1)
        self.assertGreaterEqual(len(self.sockets()), sockets, (self.runtime / 'flint-dmd').iterdir())
        before = self.trace.read_text().count('\n') if self.trace.exists() else 0
        result = self.compile(*args, env=env)
        events = self.trace.read_text().splitlines()[before:] if self.trace.exists() else []
        verdicts = [line.split()[-1] for line in events if line.split()[-1] in ('compiled', 'refused')]
        self.assertEqual(len(verdicts), 1, events)
        return result, verdicts[0]

    def test_served_compile_emits_what_an_in_process_compile_emits(self):
        # The server analysed plat.unused, which instantiates twice!int; this compile does not import it, so app.o
        # must still define twice!int, as without the server (DMD elides an instance a non-root module instantiates).
        result, verdict = self.served('-I' + str(self.temp / 'lib'), '-version=PlatformOn', '-c', 'app.d')
        self.assertEqual((result.returncode, verdict), (0, 'compiled'), result.stderr)
        link = self.compile('app.o', '-ofapp', env=dict(self.env, FLINT_DMD_SERVER='0'))
        self.assertEqual(link.returncode, 0, link.stderr)
        self.assertEqual(subprocess.run([str(self.temp / 'app')]).returncode, 0)

    # druntime instances the server's preload creates speculatively (inside CTFE and __traits(compiles)), which this
    # module instantiates for real: mulu has inline assembly, the array hooks are templates.
    HOOKS = ('module hooks;\nimport core.checkedint : mulu;\nint[] both(int[] a, int[] b) { return a ~ b; }\n'
             'void add(ref int[] a, int x) { a ~= x; }\nstring bang(string s) { return s ~ "!"; }\n'
             'size_t product(size_t a, size_t b) { bool overflow; return mulu(a, b, overflow); }\n')

    def assert_served_object_is_the_in_process_object(self, *switches):
        (self.temp / 'hooks.d').write_text(self.HOOKS, encoding='utf-8')
        common = ['-I' + str(self.temp / 'lib'), '-version=PlatformOn', '-c', *switches, 'hooks.d']
        local = self.compile(*common, '-oflocal.o', env=dict(self.env, FLINT_DMD_SERVER='0'))
        self.assertEqual(local.returncode, 0, local.stderr)
        objects = []
        for name in ('served1.o', 'served2.o'):
            result, verdict = self.served(*common, '-of' + name)
            self.assertEqual((result.returncode, verdict), (0, 'compiled'), result.stderr)
            objects.append((self.temp / name).read_bytes())
        self.assertEqual(objects[0], objects[1])
        # Byte for byte, so the same symbols are defined and undefined and the linker pulls the same members: a served
        # object once left mulu and __arrayAlloc!char undefined (the instance stayed in the preloaded module that
        # created it speculatively), and then assembled mulu with 16-bit addressing (preloaded before backend_init).
        self.assertEqual(objects[0], (self.temp / 'local.o').read_bytes())

    def test_a_served_object_is_the_in_process_object(self):
        self.assert_served_object_is_the_in_process_object()

    def test_a_served_object_is_the_in_process_object_with_codegen_switches(self):
        # The server's own backend_init must not leave its switches in the backend configuration a request sees.
        self.assert_served_object_is_the_in_process_object('-O', '-g', '-release')

    def test_a_request_without_the_platform_paths_or_versions_compiles_in_process(self):
        # A relative spelling of the platform path is the same path (DUB passes them relative to the package).
        result, verdict = self.served('-Ilib', '-version=PlatformOn', '-c', 'app.d')
        self.assertEqual((result.returncode, verdict), (0, 'compiled'), result.stderr)
        result, verdict = self.served('-Ilib', '-c', 'app.d')
        self.assertEqual(verdict, 'refused')
        self.assertNotEqual(result.returncode, 0)       # in-process: static assert(platformOn) fails, as it should
        (self.temp / 'other.d').write_text('int main() { return 0; }\n', encoding='utf-8')
        result, verdict = self.served('-version=PlatformOn', '-c', 'other.d')
        self.assertEqual((result.returncode, verdict), (0, 'refused'), result.stderr)

    def test_a_root_module_beside_preloaded_modules_of_its_package_is_served(self):
        # A DUB package compiles its own modules (flint.config.*) while modules of other packages under the same top
        # level name (flint.arena.*) are preloaded: only a preloaded module of the same name, or a file of one in an
        # extra import path, could change what the compile sees.
        (self.temp / 'own' / 'plat').mkdir(parents=True)
        (self.temp / 'own' / 'plat' / 'app.d').write_text(
            'module plat.app;\nimport plat.boot;\nint main() { return twice!int(21) == 42 ? 0 : 1; }\n', encoding='utf-8')
        result, verdict = self.served('-Ilib', '-Iown', '-version=PlatformOn', '-c', 'own/plat/app.d', '-ofown.o')
        self.assertEqual((result.returncode, verdict), (0, 'compiled'), result.stderr)
        link = self.compile('own.o', '-ofownapp', env=dict(self.env, FLINT_DMD_SERVER='0'))
        self.assertEqual(link.returncode, 0, link.stderr)
        self.assertEqual(subprocess.run([str(self.temp / 'ownapp')]).returncode, 0)

    def test_an_import_path_holding_a_preloaded_module_is_refused(self):
        # The request's own copy of plat.twice would be found before the preloaded one in-process
        (self.temp / 'copy' / 'plat').mkdir(parents=True)
        (self.temp / 'copy' / 'plat' / 'twice.d').write_text('module plat.twice;\nT twice(T)(T x) { return x * 3; }\n',
                                                            encoding='utf-8')
        result, verdict = self.served('-Icopy', '-Ilib', '-version=PlatformOn', '-c', 'app.d')
        self.assertEqual(verdict, 'refused')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_root_module_the_server_preloaded_is_refused(self):
        result, verdict = self.served('-Ilib', '-version=PlatformOn', '-c', 'lib/plat/unused.d')
        self.assertEqual(verdict, 'refused')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_allinst_compiles_use_the_toolchain_only_server(self):
        # -allinst makes a root module emit the instances its imports instantiate, which a preloaded module's would
        # escape: such compiles (Flint AOT's generated platform modules) keep the toolchain-only server.
        (self.temp / 'other.d').write_text('int main() { return 0; }\n', encoding='utf-8')
        result, verdict = self.served('-allinst', '-c', 'other.d')
        self.assertEqual((result.returncode, verdict), (0, 'compiled'), result.stderr)

    def test_the_prelude_content_and_dflags_select_the_server(self):
        args = ('-Ilib', '-version=PlatformOn', '-c', 'app.d')
        self.assertEqual(self.served(*args)[1], 'compiled')
        self.write_prelude('# changed\n')
        self.assertEqual(self.served(*args, sockets=2)[1], 'compiled')
        self.assertEqual(self.served(*args, env=dict(self.env, DFLAGS='-w'), sockets=3)[1], 'compiled')

    def test_a_prelude_that_cannot_load_stops_further_servers(self):
        self.write_prelude('plat.missing\n')
        result = self.compile('-Ilib', '-version=PlatformOn', '-c', 'app.d')
        self.assertEqual(result.returncode, 0, result.stderr)
        for _ in range(600):
            if list((self.runtime / 'flint-dmd').glob('*.sock.failed')):
                break
            time.sleep(0.1)
        self.assertTrue(list((self.runtime / 'flint-dmd').glob('*.sock.failed')))
        result = self.compile('-Ilib', '-version=PlatformOn', '-c', 'app.d')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.sockets(), [])


def aot_extract_dmd():
    """The installed DMD fork when it has native Flint AOT extraction (-flint-aot-extract=), else None."""
    for host, exe in (('linux', 'dmd'), ('osx', 'dmd'), ('windows', 'dmd.exe')):
        dmd = ROOT / '.tools' / 'dmd2' / host / 'bin64' / exe
        if dmd.is_file() and b'cannot read the Flint AOT request' in dmd.read_bytes():
            return dmd
    return None


class AotExtractionTests(unittest.TestCase):
    """-flint-aot-extract (design 3A): the fork prints the lines Flint AOT's CTFE describer prints, byte for byte,
    from the analysed AST. The describer is taken from extract.d, so the two cannot drift apart unnoticed."""

    FIXTURE = {
        'fx/ann.d': '''module fx.ann;
enum Level { low, high = 5 }
struct Meta { string note = "m"; }
@Meta struct Mark { string value = "v\\t\\"q\\""; bool on = true; int count = -3; uint size = 7; char c = 'x';
    double ratio = 1.5; Level level = Level.high; string[] tags = ["a", "b"]; string none; }
struct Known { int x; }
struct Kind
{
    string id = "ALPHA";
    string name() const { return id; }
    int ordinal() const { return 0; }
    static immutable Kind ALPHA = Kind("ALPHA");
}
struct Tagged { Kind kind = Kind.ALPHA; Mark mark; }
struct Ref { string name; }
struct Excluding { Ref[] exclude; }
''',
        'fx/box.d': 'module fx.box;\nstruct Box(T, int n) { T[n] items; }\n',
        'fx/model.d': '''module fx.model;
import fx.ann;
import fx.box;
interface Named { string name(); }
@Mark("base", false) abstract class Base : Named
{
    protected int id;
    string name() { return "b"; }
    abstract void run(int times);
}
@Known(1) @Tagged() @(42) @(Level.low) @Mark final class Item : Base
{
    @Mark("f") private const(string)[] labels;
    Box!(int, 3) box;
    shared(Box!(Item, 1)) slot;
    const(Box!(int, 2)) frozen;
    int[string] counts;
    Item* next;
    shared(const(int))* view;
    this(int id) { this.id = id; }
    @property bool ready() const { return true; }
    override void run(int times) {}
    void run(string label, int times = 2) {}
    static Item make(scope void delegate(string key, Object value) @safe sink, const(int[]) values,
        ref int counter, @Mark("p") out string result) { return null; }
    private void hidden(void function(int unnamed) callback) {}
    Base parent() { return null; }
    enum Inner { a, b }
    struct Nested { float weight; }
}
@Excluding struct Plain { int x; void touch() {} }
''',
    }
    MODULES = ['fx.ann', 'fx.box', 'fx.model']

    def setUp(self):
        self.dmd = aot_extract_dmd()
        if self.dmd is None:
            self.skipTest('the installed DMD fork has no native Flint AOT extraction')
        self.work = Path(tempfile.mkdtemp(prefix='flint-aot-extract-'))
        self.addCleanup(shutil.rmtree, self.work, ignore_errors=True)
        for name, text in self.FIXTURE.items():
            (self.work / name).parent.mkdir(parents=True, exist_ok=True)
            (self.work / name).write_text(text, encoding='utf-8')
        source = (ROOT / 'apps/flint/src/flint_tool/engine/aot/extract.d').read_text(encoding='utf-8')
        describer = re.search(r'^enum describerSource = `(.*?)`;$', source, re.S | re.M).group(1)
        (self.work / 'flint_aot_describe.d').write_text(describer, encoding='utf-8')
        (self.work / 'flint_aot_known.d').write_text(
            'module flint_aot_known;\nbool flintAotKnownAnnotation(string name) pure nothrow @safe @nogc\n{\n'
            '    return name == "fx.ann.Known";\n}\n', encoding='utf-8')
        imports = ''.join(f'static import {m};\n' for m in self.MODULES)
        (self.work / 'r_describer.d').write_text(
            'module r_describer;\nimport flint_aot_describe : describeModule;\n' + imports
            + ''.join(f'static if (describeModule!({m}, "{m}"))\n{{\n}}\n' for m in self.MODULES), encoding='utf-8')
        (self.work / 'r_native.d').write_text('module r_native;\n' + imports, encoding='utf-8')
        (self.work / 'request.txt').write_text(
            ''.join(f'module {m}\n' for m in self.MODULES) + 'known fx.ann.Known\n', encoding='utf-8')

    def extract(self, *arguments):
        env = dict(os.environ, FLINT_DMD_SERVER='0')
        env.pop('FLINT_DMD_SERVER_PRELUDE', None)
        result = subprocess.run([str(self.dmd), '-c', '-of=' + str(self.work / 'x.o'), '-I' + str(self.work),
                                 *arguments], cwd=self.work, env=env, capture_output=True, text=True)
        return result.returncode, [line for line in (result.stdout + result.stderr).splitlines()
                                   if line.startswith('FLINT-AOT-')], result.stderr

    def test_native_extraction_prints_the_describers_lines(self):
        status, expected, errors = self.extract(str(self.work / 'r_describer.d'))
        self.assertEqual(status, 0, errors)
        status, actual, errors = self.extract('-flint-aot-extract=' + str(self.work / 'request.txt'),
                                              str(self.work / 'r_native.d'))
        self.assertEqual(status, 0, errors)
        # The fixture reaches every rule that differed while the parity runs were made: inherited and private
        # methods, @property, overloads, a constructor, qualified arrays, an associative array, pointers,
        # delegate and function parameters (names dropped as in a template argument), template instances (also
        # qualified ones: is(T == X!Args) matches through shared and const),
        # nested types, enum, enum-like and nested annotation values, a known annotation type, and an annotation
        # type reached only through an empty array's element type (announced before the annotation using it).
        self.assertGreater(len(expected), 8)
        self.assertEqual(actual, expected)
        self.assertNotIn('fx.ann.Known"', ''.join(line for line in actual if line.startswith('FLINT-AOT-ANNOTATION')))

    def test_a_module_the_root_does_not_import_is_an_error(self):
        (self.work / 'request.txt').write_text('module fx.missing\n', encoding='utf-8')
        status, actual, errors = self.extract('-flint-aot-extract=' + str(self.work / 'request.txt'),
                                              str(self.work / 'r_native.d'))
        self.assertNotEqual(status, 0)
        self.assertEqual(actual, [])
        self.assertIn('module `fx.missing` is not imported by the extraction root', errors)

    def test_an_attribute_that_fails_to_evaluate_fails_the_compile(self):
        # The describer reports an attribute's error and fails; native extraction must not swallow it.
        (self.work / 'fx/bad.d').write_text('module fx.bad;\nint boom() { assert(0); }\n@(boom()) struct Bad {}\n',
                                            encoding='utf-8')
        (self.work / 'r_native.d').write_text('module r_native;\nstatic import fx.bad;\n', encoding='utf-8')
        (self.work / 'request.txt').write_text('module fx.bad\n', encoding='utf-8')
        status, actual, errors = self.extract('-flint-aot-extract=' + str(self.work / 'request.txt'),
                                              str(self.work / 'r_native.d'))
        self.assertNotEqual(status, 0)


def server_dmd():
    """The installed DMD fork when it has the compile server, else None."""
    for host, exe in (('linux', 'dmd'), ('osx', 'dmd'), ('windows', 'dmd.exe')):
        dmd = ROOT / '.tools' / 'dmd2' / host / 'bin64' / exe
        if dmd.is_file() and b'-fork-server=' in dmd.read_bytes():
            return dmd
    return None


class CompileServerStatusTests(unittest.TestCase):
    """A served request fails exactly as the same request in-process does: same exit status, same diagnostics. The
    workers inherited the server's ignored SIGCHLD, so the driver's waitpid for the linker failed and a failed link
    (shared library or executable) exited 0 without its output."""

    def setUp(self):
        self.dmd = server_dmd()
        if self.dmd is None or sys.platform == 'win32':
            self.skipTest('the installed DMD fork has no compile server')
        self.temp = Path(tempfile.mkdtemp(prefix='flint-status-'))
        self.addCleanup(shutil.rmtree, self.temp, True)
        self.runtime = Path(tempfile.mkdtemp(prefix='fs-', dir='/tmp'))     # within macOS's sun_path
        self.addCleanup(shutil.rmtree, self.runtime, True)
        self.addCleanup(self.stop_servers)
        (self.temp / 'bad.d').write_text('module bad;\nint x = ;\n', encoding='utf-8')
        (self.temp / 'app.d').write_text('module app;\nvoid main() {}\n', encoding='utf-8')
        (self.temp / 'lib.d').write_text('module lib;\nextern (C) int f() { return 1; }\n', encoding='utf-8')
        self.trace = self.temp / 'trace.txt'
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.runtime), FLINT_DMD_SERVER_IDLE='60',
                        FLINT_DMD_SERVER_TRACE=str(self.trace))
        for name in ('FLINT_DMD_SERVER', 'FLINT_DMD_SERVER_PRELUDE', 'DFLAGS'):
            self.env.pop(name, None)

    def stop_servers(self):
        listing = subprocess.run(['ps', '-axo', 'pid=,command='], capture_output=True, text=True).stdout
        for line in listing.splitlines():
            pid, _, command = line.strip().partition(' ')
            if str(self.runtime) in command and pid.isdigit():
                try:
                    os.kill(int(pid), 9)
                except OSError:
                    pass

    def run_dmd(self, args, served):
        env = dict(self.env) if served else dict(self.env, FLINT_DMD_SERVER='0')
        return subprocess.run([str(self.dmd), *args], cwd=self.temp, env=env, capture_output=True, text=True,
                              timeout=300)

    def assert_same_failure(self, args, diagnostic):
        local = self.run_dmd(args, served=False)
        self.assertNotEqual(local.returncode, 0, local.stderr)
        self.run_dmd(args, served=True)                         # starts the server, compiles in-process
        for _ in range(600):
            if list((self.runtime / 'flint-dmd').glob('*.sock')):
                break
            time.sleep(0.1)
        before = self.trace.read_text().count('\n') if self.trace.exists() else 0
        served = self.run_dmd(args, served=True)
        verdicts = [line.split()[-1] for line in self.trace.read_text().splitlines()[before:]] if self.trace.exists() else []
        self.assertIn('received', verdicts, 'the request was not served')     # a worker took it
        self.assertEqual(served.returncode, local.returncode, served.stdout + served.stderr)
        self.assertIn(diagnostic, served.stdout + served.stderr)
        self.assertIn(diagnostic, local.stdout + local.stderr)

    def test_a_failing_compile(self):
        self.assert_same_failure(['-c', 'bad.d'], 'Error: expression expected')

    def test_a_failing_link(self):
        self.assert_same_failure(['app.d', '-L-lflint_no_such_library', '-ofapp'], 'linker exited with status')
        self.assertFalse((self.temp / 'app').exists())

    def test_a_failing_shared_library_link(self):
        self.assert_same_failure(['-shared', 'lib.d', '-L-lflint_no_such_library', '-oflib.so'],
                                 'linker exited with status')
        self.assertFalse((self.temp / 'lib.so').exists())

    def test_a_successful_link_is_served(self):
        result = self.run_dmd(['app.d', '-ofapp'], served=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.temp / 'app').exists())


class InstallerArgumentTests(unittest.TestCase):
    def test_fork_requires_dmd(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tools' / 'install_toolchains.py'), '--compiler', 'ldc',
                                 '--flint-fork'], capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(result.returncode, 2)
        self.assertIn('--flint-fork applies only to --compiler dmd', result.stderr)


if __name__ == '__main__':
    unittest.main()
