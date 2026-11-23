#!/usr/bin/env python3
"""Regression tests for the Flint DMD fork's AArch64 code generator (ADR-025 section 3).

Each test is a self-checking D program that exits 0 on success. It is compiled with
`dmd -marm64` three ways (no flags, -O, -O -release -inline), linked against druntime
for the target, and run natively on arm64 or under QEMU user mode elsewhere. A test
`name.d` may have a C companion `name.c`, and a directory `name/` of D modules that
`dmd -lib` builds into a static library the test links with.

    python3 toolchain/arm64/run.py --dmd DMD --druntime-import DIR --druntime LIB
        [--os linux|osx] [--cc CC] [--run-prefix "qemu-aarch64 -L /usr/aarch64-linux-gnu"]
"""
import argparse, os, shlex, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
FLAGS = [[], ['-O'], ['-O', '-release', '-inline']]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dmd', required=True)
    ap.add_argument('--druntime-import', required=True)
    ap.add_argument('--druntime', required=True, help='static druntime library for the target')
    ap.add_argument('--os', default='linux', choices=['linux', 'osx'])
    ap.add_argument('--cc', default='cc')
    ap.add_argument('--run-prefix', default='')
    ap.add_argument('tests', nargs='*')
    a = ap.parse_args()
    tests = [HERE / t for t in a.tests] if a.tests else sorted(HERE.glob('*.d'))
    libs = ['-lpthread', '-lm'] + (['-ldl'] if a.os == 'linux' else [])
    failed = []
    with tempfile.TemporaryDirectory() as tmp:
        for t in tests:
            for flags in FLAGS:
                name = t.stem + ''.join(flags).replace('-', '_')
                obj, exe = Path(tmp) / (name + '.o'), Path(tmp) / name
                common = [a.dmd, '-conf=', '-marm64', '-os=' + a.os, '-I' + a.druntime_import, *flags,
                          *(['-fPIC'] if a.os == 'linux' else [])]
                steps = []
                library = []
                modules = sorted(t.with_suffix('').glob('*.d')) if t.with_suffix('').is_dir() else []
                if modules:
                    lib = Path(tmp) / (name + '.a')
                    steps.append(common + ['-lib', *map(str, modules), '-of' + str(lib)])
                    library = [str(lib)]
                steps.append(common + ['-I' + str(HERE), '-c', str(t), '-of' + str(obj)])
                cfile = t.with_suffix('.c')
                steps.append(shlex.split(a.cc) + [str(obj)] + ([str(cfile)] if cfile.exists() else [])
                             + library + [a.druntime] + libs + ['-o', str(exe)])
                steps.append(shlex.split(a.run_prefix) + [str(exe)])
                for step in steps:
                    r = subprocess.run(step, capture_output=True, text=True, timeout=300)
                    if r.returncode != 0:
                        failed.append(f'{t.name} {" ".join(flags) or "(no flags)"}: {Path(step[0]).name} '
                                      f'exited {r.returncode}\n{(r.stdout + r.stderr)[-2000:]}')
                        break
        # The driver: -marm64 in dmd.conf's DFLAGS, as the installed toolchain has it, is no change of
        # architecture, even for `dmd --version`, which stops before applying it.
        conf = Path(tmp) / 'dmd.conf'
        conf.write_text('[Environment]\nDFLAGS=-marm64\n')
        r = subprocess.run([a.dmd, '-conf=' + str(conf), '--version'], capture_output=True, text=True, timeout=60)
        if r.returncode != 0 or 'Error' in r.stdout + r.stderr:
            failed.append('dmd --version with -marm64 in dmd.conf:\n' + (r.stdout + r.stderr)[-2000:])
    total = len(tests) * len(FLAGS) + 1
    for f in failed:
        print('FAIL', f)
    print(f'{total - len(failed)}/{total} passed')
    return 1 if failed else 0

if __name__ == '__main__':
    sys.exit(main())
