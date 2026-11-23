#!/usr/bin/env python3
"""Build the pinned dfmt and D-Scanner with DUB into .tools/bin."""
import argparse,ctypes,json,os,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
# The names Phobos' std.net.curl tries when DUB downloads from code.dlang.org (it loads libcurl at run time).
CURL_LIBRARIES=('libcurl.so','libcurl.so.4','libcurl-gnutls.so.4','libcurl-nss.so.4','libcurl.so.3')
# On macOS Phobos loads the system libcurl by its install name (ADR-024).
if os.name!='nt' and os.uname().sysname=='Darwin':CURL_LIBRARIES=('libcurl.4.dylib','libcurl.dylib')
CURL_FIX=('DUB loads libcurl at run time and the dynamic loader cannot find it. Install libcurl '
          '(Debian/Ubuntu: sudo apt-get install libcurl4), or point LD_LIBRARY_PATH at the directory that holds '
          'libcurl.so.4 (NixOS: export LD_LIBRARY_PATH="$(nix-build \'<nixpkgs>\' -A curl.out --no-out-link)/lib")')

def loadable_curl():
    for name in CURL_LIBRARIES:
        try:
            ctypes.CDLL(name);return name
        except OSError:
            continue
    return None

def run(argv,**kwargs):
    result=subprocess.run(argv,**kwargs)
    if result.returncode:
        detail=(getattr(result,'stderr',None) or '').strip().splitlines()
        raise SystemExit(' '.join(argv)+' failed with exit status '+str(result.returncode)+(': '+detail[-1] if detail else ''))
    return result

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--compiler',default='dmd');a=ap.parse_args();out=ROOT/'.tools/bin';out.mkdir(parents=True,exist_ok=True)
    if os.name!='nt' and loadable_curl() is None:raise SystemExit('dub cannot download the quality tools: '+CURL_FIX)
    for name in ['dfmt','dscanner']:
        run(['dub','fetch',name,'--version=0.15.2'])
        x=run(['dub','describe',name+'@0.15.2','--compiler='+a.compiler],capture_output=True,text=True)
        doc=json.loads(x.stdout);pkg=next(p for p in doc['packages'] if p['name']==name);path=Path(pkg['path'])
        shutil.copyfile(ROOT/f'policy/tooling-locks/{name}.json',path/'dub.selections.json')
        run(['dub','build','--root='+str(path),'--compiler='+a.compiler,'--build=release'])
        candidates=list(path.rglob(name+('.exe' if os.name=='nt' else '')))
        exe=next((p for p in candidates if p.is_file() and p.parent.name=='bin'),None)
        if exe is None:raise SystemExit('tool binary missing: '+name)
        shutil.copy2(exe,out/exe.name)
    if os.environ.get('GITHUB_PATH'):
        with open(os.environ['GITHUB_PATH'],'a') as f:f.write(str(out)+'\n')
    print(out)
if __name__=='__main__':main()
