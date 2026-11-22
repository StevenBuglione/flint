#!/usr/bin/env python3
"""Read-only dfmt check plus real D-Scanner reports. Finding != exit status."""
import argparse,difflib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--dfmt',default='dfmt');ap.add_argument('--dscanner',default='dscanner');ap.add_argument('--path',type=Path,action='append',help='Optional explicit source trees; defaults to packages, apps, benchmarks and examples.');a=ap.parse_args()
    paths=a.path or [ROOT/name for name in ('packages','apps','benchmarks','examples') if (ROOT/name).is_dir()]
    for path in paths:
        if not path.is_dir():raise SystemExit('quality source tree missing: '+str(path))
    files=sorted({p for path in paths for p in path.rglob('*.d') if not any(part in ('.dub','.flint','build','artifacts') for part in p.relative_to(path).parts)})
    if not files:raise SystemExit('quality gate has no implementation sources')
    failures=[]
    for p in files:
        source=p.read_bytes();r=subprocess.run([a.dfmt,'--config',str(ROOT),str(p)],capture_output=True,check=True)
        if r.stdout!=source:
            failures.append(str(p)+': formatter difference')
            print(''.join(difflib.unified_diff(source.decode().splitlines(True),r.stdout.decode().splitlines(True),fromfile=str(p),tofile='dfmt output')))
    reports=[];issues=[]
    for start in range(0,len(files),100):
        batch=files[start:start+100]
        r=subprocess.run([a.dscanner,'--report','--config',str(ROOT/'dscanner.ini'),*[str(p) for p in batch]],capture_output=True,text=True,check=True)
        report=json.loads(r.stdout);found=report.get('issues')
        if not isinstance(found,list):raise SystemExit('unknown D-Scanner report shape')
        reports.append({'files':[str(p) for p in batch],'report':report});issues.extend(found)
    artifact=ROOT/'artifacts/quality.json';artifact.parent.mkdir(exist_ok=True);artifact.write_text(json.dumps({'reports':reports,'issues':issues},indent=2)+'\n')
    for x in issues:
        if x.get('type') in ['warn','error']:
            failures.append(f"{x.get('fileName')}:{x.get('line')}: {x.get('message')}")
    if failures:raise SystemExit('\n'.join(failures))
    print(json.dumps({'files':len(files),'issues':0,'formatter':'dfmt0.15.2 stdout byte comparison'}))
if __name__=='__main__':main()
