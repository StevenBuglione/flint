#!/usr/bin/env python3
"""Execute small native compiler/ThinLTO/PGO probes; no Flint performance claim."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dmd', default='dmd')
    parser.add_argument('--ldc', default='ldc2')
    parser.add_argument('--report', type=Path, default=ROOT/'verification/toolchain-capabilities.json')
    args = parser.parse_args()
    source = ROOT/'verification/probes/toolchain_flags.d'
    results = []
    def run(name, command, *, env=None, expected_error=None):
        result = subprocess.run([str(item) for item in command], text=True, capture_output=True, env=env)
        accepted = result.returncode == 0 if expected_error is None else result.returncode != 0 and expected_error in result.stderr
        results.append({'name':name, 'command':[str(item) for item in command],
                        'exit_code':result.returncode, 'passed':accepted,
                        'expected':'success' if expected_error is None else expected_error,
                        'stdout':result.stdout, 'stderr':result.stderr})
        if not accepted:
            raise RuntimeError(name + ': ' + result.stdout + result.stderr)
        return result
    failure = None
    try:
        dmd = run('DMD identity', [args.dmd, '--version'])
        ldc = run('LDC identity', [args.ldc, '--version'])
        if 'v2.114.0' not in dmd.stdout or '1.43.0' not in ldc.stdout:
            raise RuntimeError('these receipts require the exact pinned compiler versions')
        with tempfile.TemporaryDirectory(prefix='flint-toolchain-') as directory:
            directory = Path(directory)
            target = directory/'dmd-dev'
            run('DMD development flags', [args.dmd,'-g','-w','-de','-preview=dip1000',source,'-of='+str(target)])
            run('DMD native execution', [target])
            for profile in ['O3','Oz']:
                target=directory/profile
                run('LDC '+profile+' ThinLTO release link',[args.ldc,'-'+profile,'--flto=thin','-release',
                    '-boundscheck=safeonly','-preview=dip1000',source,'-of='+str(target)])
                run('LDC '+profile+' native execution',[target])
            run('LDC D AddressSanitizer flag',[args.ldc,'-c','-fsanitize=address',source,'-of='+str(directory/'asan.o')])
            run('LDC rejects unsupported UBSan flag',[args.ldc,'-c','-fsanitize=address,undefined',source,
                '-of='+str(directory/'undefined.o')],expected_error="Unrecognized -fsanitize value 'undefined'")
            trace=directory/'trace.json'
            run('LDC explicit time trace',[args.ldc,'-c','-ftime-trace','-ftime-trace-file='+str(trace),source,
                '-of='+str(directory/'trace.o')])
            if not json.loads(trace.read_text()).get('traceEvents'):
                raise RuntimeError('time trace was not actually produced')
            generate=directory/'pgo-generate';raw=directory/'training.profraw';merged=directory/'training.profdata'
            run('PGO instrumented link',[args.ldc,'-O3','--flto=thin','-fprofile-instr-generate',source,'-of='+str(generate)])
            environment=os.environ.copy();environment['LLVM_PROFILE_FILE']=str(raw)
            run('PGO training execution',[generate],env=environment)
            if not raw.is_file() or raw.stat().st_size == 0:
                raise RuntimeError('PGO training did not emit a profile')
            compiler=Path(shutil.which(args.ldc) or args.ldc).resolve()
            run('PGO merge',[compiler.parent/'ldc-profdata','merge','-o',merged,raw])
            use=directory/'pgo-use'
            run('PGO use link',[args.ldc,'-O3','--flto=thin','-fprofile-instr-use='+str(merged),source,'-of='+str(use)])
            run('PGO optimized execution',[use])
    except (OSError,ValueError,RuntimeError) as error:
        failure=str(error)
    report={'schema':1,'checked_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'scope':'standalone Linux native compiler capability probes; PGO profile is synthetic toolchain verification, not a production training workload',
            'source':str(source.relative_to(ROOT)),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'checks':results,'passed':failure is None,'failure':failure,
            'not_claimed':['D runtime ASan execution','D UBSan support','framework performance or binary-size results']}
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'passed':report['passed'],'checks':len(results),'failure':failure,'report':str(args.report)}))
    return 0 if report['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
