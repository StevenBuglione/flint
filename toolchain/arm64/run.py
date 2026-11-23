#!/usr/bin/env python3
"""Regression tests for the Flint DMD fork's AArch64 code generator (ADR-025 section 3).

Each test is a self-checking D program that exits 0 on success. It is compiled with
`dmd -marm64` three ways (no flags, -O, -O -release -inline), linked against druntime
for the target, and run natively on arm64 or under QEMU user mode elsewhere. A test
`name.d` may have a C companion `name.c`, and a directory `name/` of D modules (and C
files, which DMD compiles as ImportC) that `dmd -lib` builds into a static library the
test links with. A test `betterc_*.d` is compiled with -betterC and linked without druntime.

    python3 toolchain/arm64/run.py --dmd DMD --druntime-import DIR --druntime LIB
        [--os linux|osx] [--cc CC] [--run-prefix "qemu-aarch64 -L /usr/aarch64-linux-gnu"]
"""
import argparse, os, shlex, shutil, subprocess, sys, tempfile
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
    # The C preprocessor for ImportC: the cross compiler's when one is given (aarch64-linux-gnu-gcc -> -cpp)
    cc = shlex.split(a.cc)[0]
    cpp = ['-cpp=' + cc[:-3] + 'cpp'] if a.os == 'linux' and cc.endswith('-gcc') else []
    with tempfile.TemporaryDirectory() as tmp:
        for t in tests:
            for flags in FLAGS:
                name = t.stem + ''.join(flags).replace('-', '_')
                obj, exe = Path(tmp) / (name + '.o'), Path(tmp) / name
                common = [a.dmd, '-conf=', '-marm64', '-os=' + a.os, '-I' + a.druntime_import, *flags,
                          *(['-fPIC'] if a.os == 'linux' else []), *cpp]
                steps = []
                library = []
                directory = t.with_suffix('')
                modules = sorted(directory.glob('*.d')) + sorted(directory.glob('*.c')) if directory.is_dir() else []
                if modules:
                    lib = Path(tmp) / (name + '.a')
                    steps.append(common + ['-lib', *map(str, modules), '-of' + str(lib)])
                    library = [str(lib)]
                betterc = t.name.startswith('betterc_')
                steps.append(common + ['-I' + str(HERE), *(['-betterC'] if betterc else []), '-c', str(t), '-of' + str(obj)])
                cfile = t.with_suffix('.c')
                steps.append(shlex.split(a.cc) + [str(obj)] + ([str(cfile)] if cfile.exists() else [])
                             + library + ([] if betterc else [a.druntime]) + libs + ['-o', str(exe)])
                steps.append(shlex.split(a.run_prefix) + [str(exe)])
                for step in steps:
                    # DMD preprocesses ImportC files and links with $CC
                    r = subprocess.run(step, capture_output=True, text=True, timeout=300,
                                       env=dict(os.environ, CC=a.cc) if a.cc != 'cc' else None)
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
        # The driver: -L-Wl,... is a C compiler driver switch, passed to cc without -Xlinker
        # (native packages give Apple frameworks as -Wl,-framework,NAME).
        source = Path(tmp) / 'wl.d'
        source.write_text('extern(C) int main() { return 0; }\n')
        wl = '-L-Wl,-framework,CoreFoundation' if a.os == 'osx' else '-L-Wl,--as-needed'
        dmd = shutil.which(a.dmd) or a.dmd
        link = [str(Path(dmd).resolve()), '-conf=', '-marm64', '-os=' + a.os, '-betterC',
                '-I' + str(Path(a.druntime_import).resolve()), *(['-fPIC'] if a.os == 'linux' else []),
                str(source), wl, '-of' + str(Path(tmp) / 'wl')]
        # On macOS the fork links with ld directly, from the cached expansion of `cc -###` (flintlink)
        cache = Path(tmp) / 'cache'
        env = dict(os.environ, XDG_CACHE_HOME=str(cache), **({'CC': a.cc} if a.cc != 'cc' else {}))
        r = subprocess.run(link, capture_output=True, text=True, timeout=120, env=env, cwd=tmp)
        if r.returncode == 0 and a.os == 'osx' and not list(cache.glob('flint-dmd/link-*.txt')):
            failed.append('dmd links with ' + wl + ' through cc, not directly with ld')
        if r.returncode == 0:
            r = subprocess.run(shlex.split(a.run_prefix) + [str(Path(tmp) / 'wl')], capture_output=True, text=True,
                               timeout=60)
        if r.returncode != 0:
            failed.append('dmd links with ' + wl + ':\n' + (r.stdout + r.stderr)[-2000:])
    total = len(tests) * len(FLAGS) + 2
    for f in failed:
        print('FAIL', f)
    print(f'{total - len(failed)}/{total} passed')
    return 1 if failed else 0

if __name__ == '__main__':
    sys.exit(main())
