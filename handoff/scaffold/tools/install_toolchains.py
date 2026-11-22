#!/usr/bin/env python3
"""Install checksum-locked official archives into a project-private directory."""
import argparse,hashlib,json,os,platform,shutil,subprocess,tarfile,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
LOCK=json.loads((ROOT/'policy/toolchains.json').read_text())

def install(name,destination):
    a=LOCK['assets'][name];destination.mkdir(parents=True,exist_ok=True);archive=destination/name
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest()!=a['sha256']:
        with urllib.request.urlopen(a['url'],timeout=90) as response,archive.open('wb') as out:
            while True:
                block=response.read(1048576)
                if not block:break
                out.write(block)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=a['sha256']:raise SystemExit('checksum mismatch: '+name)
    if name=='oha-linux-amd64':
        binary=destination/'oha-1.16.0/oha';binary.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(archive,binary);binary.chmod(0o755)
    elif name.endswith('.7z'):subprocess.run(['7z','x','-y',str(archive),'-o'+str(destination)],check=True)
    else:
        with tarfile.open(archive) as t:t.extractall(destination,filter='data')
    return destination

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--compiler',choices=['dmd','ldc','go','oha'],required=True);ap.add_argument('--musl',action='store_true');ap.add_argument('--destination',type=Path,default=ROOT/'.tools');a=ap.parse_args()
    a.destination=a.destination.resolve()
    osname=platform.system();arch=platform.machine().lower();arch='aarch64' if arch in ['arm64','aarch64'] else 'x86_64' if arch in ['amd64','x86_64'] else arch
    if a.compiler=='dmd':
        if (osname,arch)!=('Linux','x86_64') or a.musl:raise SystemExit('DMD development pin supports Linux x86_64 glibc; use LDC for this target')
        name='dmd.2.114.0.linux.tar.xz';relative='dmd2/linux/bin64'
    elif a.compiler=='oha':
        if (osname,arch)!=('Linux','x86_64'):raise SystemExit('oha benchmark pin is Linux x86_64')
        name='oha-linux-amd64';relative='oha-1.16.0'
    elif a.compiler=='go':
        if (osname,arch)!=('Linux','x86_64'):raise SystemExit('Go reference benchmark pin is Linux x86_64')
        name='go1.27.4.linux-amd64.tar.gz';relative='go/bin'
    else:
        suffix={'Linux':('alpine' if a.musl else 'linux')+'-'+arch,'Darwin':'osx-arm64','Windows':'windows-x64'}.get(osname)
        if suffix is None:raise SystemExit('unsupported host '+osname)
        if osname=='Darwin' and arch!='aarch64':raise SystemExit('macOS contract is arm64')
        if osname=='Windows' and arch!='x86_64':raise SystemExit('Windows contract is x86_64')
        stem='ldc2-1.43.0-'+suffix;name=stem+('.7z' if osname=='Windows' else '.tar.xz');relative=stem+'/bin'
    install(name,a.destination);binary_path=a.destination/relative
    if not binary_path.is_dir():raise SystemExit('archive layout did not contain '+str(binary_path))
    if os.environ.get('GITHUB_PATH'):
        with open(os.environ['GITHUB_PATH'],'a') as f:f.write(str(binary_path)+'\n')
    print(json.dumps({'compiler':a.compiler,'version':LOCK['versions'][a.compiler],'bin':str(binary_path),'sha256':LOCK['assets'][name]['sha256']}))
if __name__=='__main__':main()
