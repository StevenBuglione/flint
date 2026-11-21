#!/usr/bin/env python3
import argparse,json,os,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--compiler',default='dmd');a=ap.parse_args();out=ROOT/'.tools/bin';out.mkdir(parents=True,exist_ok=True)
    for name in ['dfmt','dscanner']:
        subprocess.run(['dub','fetch',name,'--version=0.15.2'],check=True)
        x=subprocess.run(['dub','describe',name+'@0.15.2','--compiler='+a.compiler],capture_output=True,text=True,check=True)
        doc=json.loads(x.stdout);pkg=next(p for p in doc['packages'] if p['name']==name);path=Path(pkg['path'])
        shutil.copyfile(ROOT/f'policy/tooling-locks/{name}.json',path/'dub.selections.json')
        subprocess.run(['dub','build','--root='+str(path),'--compiler='+a.compiler,'--build=release'],check=True)
        candidates=list(path.rglob(name+('.exe' if os.name=='nt' else '')))
        exe=next((p for p in candidates if p.is_file() and p.parent.name=='bin'),None)
        if exe is None:raise SystemExit('tool binary missing: '+name)
        shutil.copy2(exe,out/exe.name)
    if os.environ.get('GITHUB_PATH'):
        with open(os.environ['GITHUB_PATH'],'a') as f:f.write(str(out)+'\n')
    print(out)
if __name__=='__main__':main()
