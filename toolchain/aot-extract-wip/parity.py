#!/usr/bin/env python3
"""Parity of -flint-aot-extract with the CTFE describer: same compile flags, same modules, lines compared.

usage: parity.py <app dir> [--dmd DMD] [--modules a,b] [--known-from-describer]
Runs both in-process (no compile server) unless --served is given, which uses the installed fork and the prelude.
"""
import argparse, json, os, re, shutil, subprocess, sys, time
from pathlib import Path

S = Path(__file__).resolve().parent
FLINT = Path.home() / 'flint-work/dmd-arm64/flint'
TOOLS = FLINT / '.tools/dmd2'
DEBUG = Path.home() / 'flint-work/dmd-arm64/work/dmd2/generated/linux/debug/64/dmd'

ap = argparse.ArgumentParser()
ap.add_argument('app')
ap.add_argument('--dmd', default=str(DEBUG))
ap.add_argument('--modules')
ap.add_argument('--args', default=str(S / 'extract-args.json'))
ap.add_argument('--keep-going', action='store_true')
ap.add_argument('--src')
ap.add_argument('--gen')
a = ap.parse_args()

app = Path(a.app).resolve()
args = json.load(open(a.args))
flags = [x for x in args[1:] if (x.startswith('-I') or x.startswith('-preview') or x.startswith('-version'))
         and 'aot-extract' not in x]
base = (['-I' + a.src] if a.src else []) + ['-conf=', '-I' + str(TOOLS / 'src/phobos'), '-I' + str(TOOLS / 'src/druntime/import')]
if a.modules:
    modules = a.modules.split(',')
else:
    modules = sorted(re.search(r'^module\s+([\w.]+)\s*;', p.read_text(), re.M).group(1)
                     for p in Path(a.src or app / 'src').rglob('*.d')
                     if re.search(r'^module\s+([\w.]+)\s*;', p.read_text(), re.M))
work = S / 'parity' / app.name
shutil.rmtree(work, ignore_errors=True)
work.mkdir(parents=True)
gen = Path(a.gen) if a.gen else app / '.flint/generated/aot-extract'
shutil.copy(gen / 'flint_aot_describe.d', work)
shutil.copy(gen / 'flint_aot_known.d', work)
known = re.findall(r'case "([^"]+)":', (gen / 'flint_aot_known.d').read_text())
imports = ''.join(f'static import {m};\n' for m in modules)
(work / 'r_desc.d').write_text('module r_desc;\nimport flint_aot_describe : describeModule;\n' + imports + ''.join(
    f'static if (describeModule!({m}, "{m}")) {{}}\n' for m in modules))
(work / 'r_native.d').write_text('module r_native;\n' + imports)
(work / 'request.txt').write_text(''.join(f'module {m}\n' for m in modules) + ''.join(f'known {k}\n' for k in known))


def run(extra, root):
    env = dict(os.environ)
    env.pop('FLINT_DMD_SERVER_PRELUDE', None)
    env['FLINT_DMD_SERVER'] = '0'
    cmd = [a.dmd, '-c', '-of=' + str(work / 'x.o'), '-I' + str(work)] + base + flags + extra + [str(work / root)]
    t = time.perf_counter()
    p = subprocess.run(cmd, cwd=app, env=env, capture_output=True, text=True)
    return p, (time.perf_counter() - t) * 1000


def lines(p):
    out = [l for l in (p.stdout + p.stderr).splitlines() if l.startswith('FLINT-AOT-')]
    other = [l for l in (p.stdout + p.stderr).splitlines() if l and not l.startswith('FLINT-AOT-')]
    return out, other


pd, td = run([], 'r_desc.d')
pn, tn = run(['-flint-aot-extract=' + str(work / 'request.txt')], 'r_native.d')
ld, od = lines(pd)
ln, on = lines(pn)
print(f'{app.name}: describer rc={pd.returncode} {len(ld)} lines {td:.0f} ms | native rc={pn.returncode} {len(ln)} lines {tn:.0f} ms')
for label, o in (('describer', od), ('native', on)):
    if o:
        print(f'  {label} other output:', *o[:8], sep='\n    ')
(work / 'describer.txt').write_text('\n'.join(ld) + '\n')
(work / 'native.txt').write_text('\n'.join(ln) + '\n')
types_d = [l for l in ld if not l.startswith('FLINT-AOT-ANNOTATION')]
types_n = [l for l in ln if not l.startswith('FLINT-AOT-ANNOTATION')]
ann_d = [l for l in ld if l.startswith('FLINT-AOT-ANNOTATION')]
ann_n = [l for l in ln if l.startswith('FLINT-AOT-ANNOTATION')]
print(f'  module/type lines identical: {types_d == types_n}; annotations identical: {ann_d == ann_n}, '
      f'as sets: {sorted(ann_d) == sorted(ann_n)}; full order identical: {ld == ln}')
if types_d != types_n:
    for i, (x, y) in enumerate(zip(types_d, types_n)):
        if x != y:
            j = next((k for k in range(min(len(x), len(y))) if x[k] != y[k]), min(len(x), len(y)))
            print(f'  first type difference, line {i}, column {j}:')
            print('    describer:', x[max(0, j - 150):j + 250])
            print('    native:   ', y[max(0, j - 150):j + 250])
            break
    else:
        print('  type line counts differ', len(types_d), len(types_n))
if sorted(ann_d) != sorted(ann_n):
    sd, sn = set(ann_d), set(ann_n)
    for x in sorted(sd - sn)[:2]:
        print('  annotation only in describer:', x[:400])
    for x in sorted(sn - sd)[:2]:
        print('  annotation only in native:   ', x[:400])
