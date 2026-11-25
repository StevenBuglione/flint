"""Release and size links code-generate ThinLTO bitcode at the profile's level, never at O0 (decision dd774a24).

DUB's LDC link step forwards --flto but not -O, so a link that relied on the dflags alone ran the linker plugin at
-plugin-opt=O0 and left every function unoptimised. The profiles pass the level as elf_lflags. This test builds a
two-module DUB project with the pinned DUB and LDC, through DFLAGS as flint and measure_builds do, and looks at the code
the link generated: at O0 the cross-module call stays and every value goes through the stack.
"""
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import profiles  # noqa: E402

LDC = ROOT / '.tools' / 'ldc2-1.43.0-linux-x86_64' / 'bin' / 'ldc2'
DUB = ROOT / '.tools' / 'dmd2' / 'linux' / 'bin64' / 'dub'

WORK = '''module work;

long mix(const(long)[] xs) @safe pure nothrow @nogc
{
    long sum;
    foreach (i, x; xs)
        sum += x * cast(long) i ^ (sum >> 3);
    return sum;
}
'''

APP = '''module app;

import work : mix;

void main()
{
    import core.stdc.stdio : printf;

    auto xs = new long[](1000);
    foreach (i, ref x; xs)
        x = i * 7;
    printf("%lld\\n", mix(xs));
}
'''


def function_body(binary, symbol_part):
    """The instructions of the first function whose symbol contains `symbol_part`, or None when it was inlined away."""
    names = subprocess.run(['nm', str(binary)], capture_output=True, text=True, check=True).stdout.split('\n')
    found = next((line.split()[-1] for line in names if symbol_part in line and (' T ' in line or ' t ' in line)), None)
    if found is None:
        return None
    text = subprocess.run(['objdump', '-d', '--no-show-raw-insn', str(binary)], capture_output=True, text=True,
                          check=True).stdout
    match = re.search(r'<' + re.escape(found) + r'>:\n(.*?)\n\n', text, re.S)
    return match.group(1).splitlines() if match else []


def stack_references(lines):
    return sum(1 for line in lines if '(%rsp)' in line or '(%rbp)' in line)


@unittest.skipUnless(sys.platform.startswith('linux') and LDC.is_file() and DUB.is_file() and shutil.which('objdump'),
                     'needs Linux, the pinned LDC and DUB, and objdump')
class ThinLtoLevelTests(unittest.TestCase):
    def build(self, directory, dflags):
        project = Path(directory) / 'project'
        (project / 'source').mkdir(parents=True)
        (project / 'dub.sdl').write_text('name "ltolevel"\ntargetType "executable"\n')
        (project / 'source' / 'work.d').write_text(WORK)
        (project / 'source' / 'app.d').write_text(APP)
        env = dict(os.environ, DFLAGS=shlex.join(dflags), DUB_HOME=str(Path(directory) / 'dub-home'))
        # One object per module, as Flint's packages are: only the link can inline across them.
        done = subprocess.run([str(DUB), 'build', '--compiler=' + str(LDC), '--build=plain', '--skip-registry=all',
                               '--build-mode=singleFile'],
                              cwd=project, env=env, capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        binary = project / 'ltolevel'
        ran = subprocess.run([str(binary)], capture_output=True, text=True, check=True)
        return binary, ran.stdout

    def code(self, profile, with_link_level):
        dflags = profiles.dflags(profile) + [flag for flag in profiles.link_dflags(profile)
                                             if with_link_level or 'plugin-opt' not in flag]
        with tempfile.TemporaryDirectory(prefix='flint-lto-level-') as directory:
            binary, output = self.build(directory, dflags)
            return function_body(binary, '4work3mix'), function_body(binary, '_Dmain'), output

    def test_release_and_size_links_are_not_code_generated_at_O0(self):
        for profile in ('release', 'size'):
            with self.subTest(profile=profile):
                self.assertTrue(any('plugin-opt=O' in flag for flag in profiles.link_dflags(profile, elf=True)),
                                profile + ' passes the ThinLTO level at the link')
                mixed, main, output = self.code(profile, with_link_level=True)
                self.assertEqual(stack_references(main), 0, profile + ': _Dmain spills to the stack')
                if mixed is not None:
                    self.assertEqual(stack_references(mixed), 0, profile + ': mix spills to the stack')
                # The control: the same link without the profile's level is code-generated at O0, which this test
                # must be able to see.
                o0_mixed, o0_main, o0_output = self.code(profile, with_link_level=False)
                self.assertEqual(o0_output, output)
                self.assertIsNotNone(o0_mixed, profile + ' at O0 keeps the cross-module call')
                self.assertGreater(stack_references(o0_mixed) + stack_references(o0_main), 0)


if __name__ == '__main__':
    unittest.main()
