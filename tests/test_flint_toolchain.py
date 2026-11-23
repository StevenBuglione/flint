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
        files = [f for f in patched_files(TOOLCHAIN / 'dmd-2.114.0-flint.patch') if f not in AARCH64_FILES]
        self.assertEqual(files,
                         ['build.d', 'dmd/cond.d', 'dmd/errors.d', 'dmd/expressionsem.d', 'dmd/flintdiag.d',
                          'dmd/flintlink.d', 'dmd/flintserver.d', 'dmd/hdrgen.d', 'dmd/link.d', 'dmd/main.d',
                          'dmd/mars.d', 'dmd/templatesem.d', 'dmd/timetrace.d'])

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


def fork_dmd():
    """The installed DMD fork when it serves a platform prelude (FLINT_DMD_SERVER_PRELUDE), else None."""
    for host in ('linux', 'osx'):
        dmd = ROOT / '.tools' / 'dmd2' / host / 'bin64' / 'dmd'
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
        self.runtime = self.temp / 'run'
        self.runtime.mkdir()
        self.trace = self.temp / 'trace.txt'
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.runtime), FLINT_DMD_SERVER_IDLE='60',
                        FLINT_DMD_SERVER_PRELUDE=str(self.prelude), FLINT_DMD_SERVER_TRACE=str(self.trace))
        self.env.pop('FLINT_DMD_SERVER', None)
        self.env.pop('DFLAGS', None)

    def write_prelude(self, extra=''):
        self.prelude.write_text(f'-I{self.temp / "lib"}\n-version=PlatformOn\nplat.boot\nplat.unused\n{extra}',
                                encoding='utf-8')

    def stop_servers(self):
        for proc in Path('/proc').glob('[0-9]*'):
            try:
                if str(self.runtime).encode() in (proc / 'cmdline').read_bytes():
                    os.kill(int(proc.name), 9)
            except (OSError, ValueError):
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


class InstallerArgumentTests(unittest.TestCase):
    def test_fork_requires_dmd(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tools' / 'install_toolchains.py'), '--compiler', 'ldc',
                                 '--flint-fork'], capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(result.returncode, 2)
        self.assertIn('--flint-fork applies only to --compiler dmd', result.stderr)


if __name__ == '__main__':
    unittest.main()
