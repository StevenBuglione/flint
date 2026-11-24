#!/usr/bin/env python3
"""Parity and timing of the DMD fork's native Flint AOT extraction (-flint-aot-extract) against the CTFE describer.

The describer (extract.d's describerSource) is the normative definition of the model. This tool compiles the same
modules twice with the same flags, once through a describer root and once through the native switch, and compares
the FLINT-AOT lines byte for byte, order included. It is evidence for toolchain/README.md, not a gate: the
toolchain tests (AotExtractionTests) carry the regression fixture.

  parity.py capture <app>     one cold `flint build` of <app> under strace (Linux), keeping the argv of its
                              extraction compile and the annotation types it already held
  parity.py run <app> [--modules a,b | --prelude-modules] [--src DIR] [--like APP]
                              one parity set; --like takes the flags and known types of an app captured before
  parity.py all               every set recorded in README.md (captures what is missing)
  parity.py timing <app>      served compiles (the compile server, with and without the platform prelude) of an
                              import-only root, the native root and the describer root

Work files go to .flint/aot-parity/ at the repository root. --dmd picks the compiler (default: the installed fork).
"""
import argparse
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.flint' / 'aot-parity'
APPS = ROOT / 'benchmarks' / 'spring' / 'flint'
EXTRACT = ROOT / 'apps' / 'flint' / 'src' / 'flint_tool' / 'engine' / 'aot' / 'extract.d'
# The describer itself fails on this module (with or without the prelude), so the platform set leaves it out.
DESCRIBER_FAILS = {'flint.arena.sys.gc.counting'}
TESTS_AOT = ['annotations', 'autoconfig', 'date', 'diagnostics', 'exporter', 'gs-rest-service', 'hierarchy',
             'imports', 'petclinic-rest', 'sample']


def default_dmd():
    for host in ('linux', 'osx'):
        dmd = ROOT / '.tools' / 'dmd2' / host / 'bin64' / 'dmd'
        if dmd.is_file():
            return dmd
    raise SystemExit('no DMD under .tools; pass --dmd')


def module_name(path):
    match = re.search(r'^module\s+([\w.]+)\s*;', path.read_text(encoding='utf-8', errors='replace'), re.M)
    return match.group(1) if match else None


def source_modules(directory):
    return sorted(filter(None, (module_name(p) for p in Path(directory).rglob('*.d'))))


# --- capture -------------------------------------------------------------------------------------------------------

def strace_argv(text):
    """The argv array of one strace execve line: ["a", "b\\"c", ...]."""
    start = text.index('[')
    values, i, current, quoted = [], start + 1, None, False
    while i < len(text):
        c = text[i]
        if quoted:
            if c == '\\':
                current += {'n': '\n', 't': '\t', '"': '"', '\\': '\\'}.get(text[i + 1], text[i + 1])
                i += 1
            elif c == '"':
                quoted = False
                values.append(current)
            else:
                current += c
        elif c == '"':
            quoted, current = True, ''
        elif c == ']':
            break
        i += 1
    return values


def capture(app):
    """Run one cold flint build of the app with the compile server off (strace then exits with the build) and keep
    the extraction compile's flags and known annotation types in .flint/aot-parity/<app>/capture.json."""
    app = Path(app).resolve()
    work = WORK / app.name
    work.mkdir(parents=True, exist_ok=True)
    flint = ROOT / '.flint' / 'bin' / 'flint'
    if not flint.is_file():
        raise SystemExit(f'{flint} missing: python3 tools/install_toolchains.py --compiler flint')
    shutil.rmtree(app / '.flint', ignore_errors=True)
    cache = work / 'cache'
    shutil.rmtree(cache, ignore_errors=True)
    log = work / 'strace.txt'
    env = dict(os.environ, FLINT_DMD_SERVER='0', FLINT_CACHE=str(cache))
    subprocess.run(['strace', '-f', '-qq', '-v', '-s', '1048576', '-e', 'trace=execve', '-o', str(log),
                    str(flint), 'build', '-C', str(app)], env=env, check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    argv = None
    for line in log.read_text(errors='replace').splitlines():
        if 'execve(' in line and 'flint_aot_extract.d' in line and '= 0' in line[-8:]:
            argv = strace_argv(line[line.index('execve('):])
    if argv is None:
        raise SystemExit(f'no extraction compile in {log}')
    flags = [a for a in argv[1:] if a.startswith(('-I', '-preview', '-version')) and 'aot-extract' not in a]
    generated = app / '.flint' / 'generated' / 'aot-extract'
    request = generated / 'flint_aot_request.txt'
    if request.is_file():
        known = [l.split(None, 1)[1] for l in request.read_text().splitlines() if l.startswith('known ')]
    else:
        known = re.findall(r'case "([^"]+)":', (generated / 'flint_aot_known.d').read_text())
    prelude = app / '.flint' / 'generated' / 'platform' / 'dmd-server-prelude.txt'
    record = {'flags': flags, 'known': sorted(known), 'prelude': str(prelude) if prelude.is_file() else None}
    (work / 'capture.json').write_text(json.dumps(record, indent=1) + '\n')
    log.unlink()
    return record


def captured(app):
    path = WORK / Path(app).resolve().name / 'capture.json'
    return json.loads(path.read_text()) if path.is_file() else capture(app)


# --- roots ---------------------------------------------------------------------------------------------------------

def prepare(work, modules, known):
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    describer = re.search(r'^enum describerSource = `(.*?)`;$', EXTRACT.read_text(encoding='utf-8'), re.S | re.M)
    (work / 'flint_aot_describe.d').write_text(describer.group(1), encoding='utf-8')
    (work / 'flint_aot_known.d').write_text(
        'module flint_aot_known;\n\nbool flintAotKnownAnnotation(string name) pure nothrow @safe @nogc\n{\n'
        '    switch (name)\n    {\n' + ''.join(f'    case "{k}":\n' for k in known)
        + ('        return true;\n' if known else '') + '    default:\n        return false;\n    }\n}\n',
        encoding='utf-8')
    imports = ''.join(f'static import {m};\n' for m in modules)
    (work / 'r_describer.d').write_text('module r_describer;\nimport flint_aot_describe : describeModule;\n' + imports
                                        + ''.join(f'static if (describeModule!({m}, "{m}")) {{}}\n' for m in modules))
    (work / 'r_imports.d').write_text('module r_imports;\n' + imports)
    (work / 'request.txt').write_text(''.join(f'module {m}\n' for m in modules)
                                      + ''.join(f'known {k}\n' for k in known))


def compile_root(dmd, work, cwd, flags, extra, served=False, prelude=None):
    env = dict(os.environ)
    env.pop('FLINT_DMD_SERVER_PRELUDE', None)
    if not served:
        env['FLINT_DMD_SERVER'] = '0'
    elif prelude:
        env['FLINT_DMD_SERVER_PRELUDE'] = prelude
    command = [str(dmd), '-c', '-of=' + str(work / 'x.o'), '-I' + str(work)] + flags + extra
    start = time.perf_counter()
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
    return result, (time.perf_counter() - start) * 1000


def aot_lines(result):
    return [l for l in (result.stdout + result.stderr).splitlines() if l.startswith('FLINT-AOT-')]


def first_error(result):
    """The first error without its location: the two roots differ in name and line, the error itself must not."""
    line = next((l for l in result.stderr.splitlines() if 'Error:' in l), '')
    if line.split('(')[0].endswith(('r_describer.d', 'r_imports.d')):
        line = line[line.index('Error:'):]
    return line[:300]


# --- run -----------------------------------------------------------------------------------------------------------

def run(dmd, name, app, modules, flags, known, src=None):
    """One parity set: returns a result dict and leaves describer.txt and native.txt in its work directory."""
    work = WORK / 'sets' / name
    prepare(work, modules, known)
    extra_src = ['-I' + str(src)] if src else []
    d, td = compile_root(dmd, work, app, extra_src + flags, [str(work / 'r_describer.d')])
    n, tn = compile_root(dmd, work, app, extra_src + flags,
                         ['-flint-aot-extract=' + str(work / 'request.txt'), str(work / 'r_imports.d')])
    ld, ln = aot_lines(d), aot_lines(n)
    (work / 'describer.txt').write_text('\n'.join(ld) + '\n')
    (work / 'native.txt').write_text('\n'.join(ln) + '\n')
    out = {'set': name, 'modules': len(modules), 'describer_rc': d.returncode, 'native_rc': n.returncode,
           'lines': len(ld), 'native_lines': len(ln), 'identical': ld == ln,
           'describer_ms': round(td), 'native_ms': round(tn)}
    if d.returncode or n.returncode:
        out['describer_error'], out['native_error'] = first_error(d), first_error(n)
        out['same_error'] = out['describer_error'] == out['native_error'] and d.returncode == n.returncode
    if ld != ln:
        i = next((i for i, (x, y) in enumerate(zip(ld, ln)) if x != y), min(len(ld), len(ln)))
        out['first_difference'] = {'line': i, 'describer': ld[i][:300] if i < len(ld) else None,
                                   'native': ln[i][:300] if i < len(ln) else None}
    return out


def prelude_modules(record):
    lines = Path(record['prelude']).read_text().split()
    return [m for m in lines if not m.startswith('-') and m not in DESCRIBER_FAILS]


def every_set(dmd):
    petclinic = APPS / 'petclinic-rest'
    pc = captured(petclinic)
    yield run(dmd, 'petclinic-rest-platform', petclinic, prelude_modules(pc), pc['flags'], pc['known'])
    for name in ('petclinic-rest', 'gs-rest-service', 'gs-relational-data-access'):
        record = captured(APPS / name)
        yield run(dmd, name, APPS / name, source_modules(APPS / name / 'src'), record['flags'], record['known'])
    for name in TESTS_AOT:
        test = ROOT / 'tests' / 'aot' / name
        src = test if name == 'annotations' else test / ('source' if (test / 'source').is_dir() else 'src')
        yield run(dmd, 'tests-aot-' + name, test, source_modules(src), pc['flags'], pc['known'], src)


def verdict(result):
    if result['identical'] and not (result['describer_rc'] or result['native_rc']):
        return 'identical'
    if result.get('same_error') and result['describer_rc'] and result['native_rc']:
        # A failed extraction compile is an error whatever it printed first: the describer's pragma(msg) lines
        # for the modules before the error, the native walker nothing (it runs only after a clean semantic2).
        return 'both fail, same first error'
    return 'DIFFERENT'


def summary(result):
    return (f"| {result['set']} | {result['modules']} | {result['lines']} | {verdict(result)} | "
            f"{result['describer_ms']} | {result['native_ms']} |")


# --- timing --------------------------------------------------------------------------------------------------------

def timing(dmd, app, repeat):
    app = Path(app).resolve()
    record = captured(app)
    modules = source_modules(app / 'src')
    work = WORK / 'timing' / app.name
    prepare(work, modules, record['known'])
    request = '-flint-aot-extract=' + str(work / 'request.txt')
    roots = {'imports': [str(work / 'r_imports.d')], 'native': [request, str(work / 'r_imports.d')],
             'describer': [str(work / 'r_describer.d')]}
    for prelude in (record['prelude'], None):
        for label, extra in roots.items():
            times = []
            for i in range(repeat + 2):  # two warm-ups: the server starts, then loads the prelude
                result, ms = compile_root(dmd, work, app, record['flags'], extra, served=True, prelude=prelude)
                if result.returncode:
                    print(label, 'failed:', first_error(result))
                    break
                if i >= 2:
                    times.append(ms)
            if times:
                print(f"{label:10} {'prelude' if prelude else 'no prelude':10} median {statistics.median(times):7.1f} ms"
                      f"  min {min(times):7.1f}  ({len(aot_lines(result))} lines)", flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('command', choices=['capture', 'run', 'all', 'timing'])
    ap.add_argument('app', nargs='?')
    ap.add_argument('--dmd', type=Path)
    ap.add_argument('--modules')
    ap.add_argument('--prelude-modules', action='store_true')
    ap.add_argument('--src', type=Path)
    ap.add_argument('--like')
    ap.add_argument('--repeat', type=int, default=7)
    ap.add_argument('--json', action='store_true', help='print results as JSON lines')
    a = ap.parse_args()
    dmd = a.dmd or default_dmd()
    if a.command != 'all' and not a.app:
        ap.error(a.command + ' needs an app directory')
    if a.command == 'capture':
        print(json.dumps(capture(a.app), indent=1))
    elif a.command == 'timing':
        timing(dmd, a.app, a.repeat)
    else:
        if a.command == 'all':
            results = every_set(dmd)
        else:
            app = Path(a.app).resolve()
            record = captured(APPS / a.like if a.like else app)
            modules = (a.modules.split(',') if a.modules else prelude_modules(record) if a.prelude_modules
                       else source_modules(a.src or app / 'src'))
            src = a.src.resolve() if a.src else None
            results = [run(dmd, app.name, app, modules, record['flags'], record['known'], src)]
        if not a.json:
            print('| Set | Modules | Lines | Result | Describer ms | Native ms |\n| --- | --- | --- | --- | --- | --- |')
        failed = False
        for result in results:
            print(json.dumps(result) if a.json else summary(result), flush=True)
            failed |= verdict(result) == 'DIFFERENT'
        sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
