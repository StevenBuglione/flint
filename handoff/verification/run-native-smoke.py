#!/usr/bin/env python3
"""Link the delivered C smoke fixture through DMD and LDC against one native prefix."""
import argparse, datetime, hashlib, json, pathlib, subprocess, tempfile

def main():
    p=argparse.ArgumentParser();p.add_argument('--prefix',required=True);p.add_argument('--dmd',default='dmd');p.add_argument('--ldc',default='ldc2');p.add_argument('--cc',default='cc');p.add_argument('--out',default='native-smoke.json');a=p.parse_args()
    root=pathlib.Path(__file__).resolve().parents[1];prefix=pathlib.Path(a.prefix).resolve();receipt=json.loads((prefix/'flint-native-install.json').read_text())
    archives=[receipt['ffi_archive']['path']]
    for name in ['llhttp','zlib']:archives.extend(x['path'] for x in receipt['libraries'][name]['archives'])
    checks=[]
    with tempfile.TemporaryDirectory(prefix='flint-native-smoke-') as tmp:
        tmp=pathlib.Path(tmp)
        def check(label,cmd):
            r=subprocess.run([str(x) for x in cmd],cwd=root,capture_output=True,text=True)
            checks.append({'name':label,'command':[str(x) for x in cmd],'exit_code':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
            print(label,r.returncode)
            if r.returncode:print(r.stderr)
            return r.returncode==0
        obj=tmp/'smoke.o'
        success=check('compile-C-smoke',[a.cc,'-std=c11','-O2','-c','-I'+str(prefix/'include'),'-I'+str(root/'scaffold/native/ffi'),root/'verification/ffi/native_smoke.c','-o',obj])
        for name,compiler in [('DMD',a.dmd),('LDC',a.ldc)]:
            exe=tmp/('smoke-'+name)
            cmd=[compiler,'-preview=dip1000',root/'scaffold/native/ffi/flint_abi_probe.d',root/'verification/ffi/native_smoke.d',obj,'-of='+str(exe)]+['-L'+x for x in archives]
            if success and check(name+'-C-link',cmd):success=check(name+'-C-run',[exe]) and success
            else:success=False
    payload={'verified_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'Linux native C source build plus actual ABI query, llhttp request parsing, zlib roundtrip and DMD/LDC C-ABI linkage. Does not establish any other library/platform acceptance.','native_install_receipt':receipt,'checks':checks,'passed':success}
    pathlib.Path(a.out).write_text(json.dumps(payload,indent=2)+'\n')
    raise SystemExit(0 if success else 1)
if __name__=='__main__':main()
