#!/usr/bin/env python3
"""Floor of a native AOT extractor on petclinic: time served compiles of three roots, with and without the prelude."""
import json, os, shutil, statistics, subprocess, sys, time
from pathlib import Path

S = Path(__file__).resolve().parent
APP = Path.home() / 'flint-work/dmd-arm64/flint/benchmarks/spring/flint/petclinic-rest'
args = json.load(open(S / 'extract-args.json'))
dmd = args[0]
flags = [a for a in args[1:] if a.startswith('-I') or a.startswith('-preview') or a.startswith('-version')]
flags = [f for f in flags if 'aot-extract' not in f]
modules = (S / 'pc-modules.txt').read_text().split()
work = S / 'floor'
shutil.rmtree(work, ignore_errors=True)
work.mkdir()
for f in ('flint_aot_describe.d', 'flint_aot_known.d'):
    shutil.copy(APP / '.flint/generated/aot-extract' / f, work / f)
imports = ''.join(f'static import {m};\n' for m in modules)
(work / 'r_desc.d').write_text('module r_desc;\nimport flint_aot_describe : describeModule;\n' + imports + ''.join(
    f'static if (describeModule!({m}, "{m}")) {{}}\n' for m in modules))
(work / 'r_imp.d').write_text('module r_imp;\n' + imports)
sources = sorted(str(p) for p in (APP / 'src').rglob('*.d'))
import re
known = re.findall(r'case "([^"]+)":', (work / 'flint_aot_known.d').read_text())
(work / 'request.txt').write_text(''.join(f'module {m}\n' for m in modules) + ''.join(f'known {k}\n' for k in known))
prelude = str(APP / '.flint/generated/platform/dmd-server-prelude.txt')

def run(label, extra, env_prelude, n=7):
    env = dict(os.environ)
    env.pop('FLINT_DMD_SERVER_PRELUDE', None)
    if env_prelude:
        env['FLINT_DMD_SERVER_PRELUDE'] = prelude
    env['FLINT_DMD_SERVER_TRACE'] = str(work / f'trace-{label}.txt')
    times = []
    for i in range(n + 2):
        t = time.perf_counter()
        p = subprocess.run([dmd, '-c', '-of=' + str(work / 'x.o'), '-I' + str(work)] + flags + extra,
                           cwd=APP, env=env, capture_output=True, text=True)
        dt = (time.perf_counter() - t) * 1000
        if p.returncode:
            print(label, 'FAILED', p.stderr[-800:]); return
        if i >= 2:
            times.append(dt)
    lines = sum(1 for l in p.stdout.splitlines() + p.stderr.splitlines() if l.startswith('FLINT-AOT-TYPE'))
    print(f'{label:24} median {statistics.median(times):7.1f} ms  min {min(times):7.1f}  types {lines}', flush=True)

for pre in (True, False):
    tag = 'prelude' if pre else 'toolchain'
    run(f'imports/{tag}', [str(work / 'r_imp.d')], pre)
    run(f'native/{tag}', ['-flint-aot-extract=' + str(work / 'request.txt'), str(work / 'r_imp.d')], pre)
    run(f'describer/{tag}', [str(work / 'r_desc.d')], pre, n=3)
for f in sorted(work.glob('trace-*.txt')):
    t = f.read_text().split()
    print(f.name, {w: t.count(w) for w in set(t) if w in ('compiled', 'refused', 'received')})
