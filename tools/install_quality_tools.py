#!/usr/bin/env python3
"""Build the pinned dfmt and D-Scanner with DUB into .tools/bin, both on Flint's patched libdparse."""
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

# libdparse 0.25.1 and its master parse named arguments only in calls; Flint's UDA idiom, @Attr(name: value)
# (rulebook R2), needs toolchain/libdparse-0.25.1-named-uda.patch.
LIBDPARSE='0.25.1'

def patched_libdparse(compiler):
    """libdparse 0.25.1 with Flint's patch, in .tools/src/libdparse-0.25.1-flint (rebuilt from the fetched source)."""
    run(['dub','fetch','libdparse','--version='+LIBDPARSE])
    x=run(['dub','describe','libdparse@'+LIBDPARSE,'--compiler='+compiler],capture_output=True,text=True)
    source=Path(next(p for p in json.loads(x.stdout)['packages'] if p['name']=='libdparse')['path'])
    target=ROOT/'.tools/src'/('libdparse-'+LIBDPARSE+'-flint')
    shutil.rmtree(target,ignore_errors=True);target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copytree(source,target,ignore=shutil.ignore_patterns('.dub'))
    # .tools may sit inside a git checkout, where git apply resolves paths against that repository and silently
    # skips the patch; the copy gets a repository of its own, and the result is checked.
    run(['git','init','-q'],cwd=target)
    run(['git','apply','--whitespace=nowarn',str(ROOT/'toolchain'/('libdparse-'+LIBDPARSE+'-named-uda.patch'))],cwd=target)
    if 'namedArgumentList' not in (target/'src/dparse/ast.d').read_text():raise SystemExit('libdparse patch not applied')
    return target

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--compiler',default='dmd');a=ap.parse_args();out=ROOT/'.tools/bin';out.mkdir(parents=True,exist_ok=True)
    if os.name!='nt' and loadable_curl() is None:raise SystemExit('dub cannot download the quality tools: '+CURL_FIX)
    versions=json.loads((ROOT/'policy/toolchains.json').read_text())
    pins={name:versions['versions'][name] for name in ('dfmt','dscanner')}
    parser=patched_libdparse(a.compiler)
    for name,version in pins.items():
        run(['dub','fetch',name,'--version='+version])
        x=run(['dub','describe',name+'@'+version,'--compiler='+a.compiler],capture_output=True,text=True)
        doc=json.loads(x.stdout);pkg=next(p for p in doc['packages'] if p['name']==name);path=Path(pkg['path'])
        selections=json.loads((ROOT/f'policy/tooling-locks/{name}.json').read_text())
        # Both tools parse with the patched libdparse, so Flint's named-argument UDAs parse (work-queue item 22).
        if selections['versions'].get('libdparse')==LIBDPARSE:selections['versions']['libdparse']={'path':str(parser)}
        (path/'dub.selections.json').write_text(json.dumps(selections,indent=1)+'\n')
        run(['dub','build','--root='+str(path),'--compiler='+a.compiler,'--build=release','--force'])
        candidates=list(path.rglob(name+('.exe' if os.name=='nt' else '')))
        exe=next((p for p in candidates if p.is_file() and p.parent.name=='bin'),None)
        if exe is None:raise SystemExit('tool binary missing: '+name)
        shutil.copy2(exe,out/exe.name)
    if os.environ.get('GITHUB_PATH'):
        with open(os.environ['GITHUB_PATH'],'a') as f:f.write(str(out)+'\n')
    print(out)
if __name__=='__main__':main()
