#!/usr/bin/env python3
"""Read-only dfmt check plus real D-Scanner reports. Finding != exit status."""
import argparse,difflib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
# framework/, boot/ and security/ join once their findings are fixed (owner decision 4; item 22's last step).
TREES=('packages','apps','benchmarks','examples','starters')
# The pre-port Boot libraries retire at the cutover (tools/cutover.py LEGACY_DIRECTORIES; boot's request in item 22).
LEGACY=('boot/boot/','boot/autoconfigure-','boot/actuator/')
COMPLEXITY='dscanner.metric.cyclomatic_complexity'
ALLOWLIST=ROOT/'policy/complexity-allowlist.json'

def legacy(p):
    try:rel=p.resolve().relative_to(ROOT).as_posix()
    except ValueError:return False
    return rel.startswith(LEGACY)

def complexity_allowlist(root=ROOT):
    """Ported functions that may exceed D-Scanner's cyclomatic complexity limit (owner decision 4, 2026-11-23):
    {(file, function): entry}. Every entry names its upstream project, file and method."""
    path=root/'policy/complexity-allowlist.json'
    if not path.is_file():return {}
    data=json.loads(path.read_text(encoding='utf-8'))
    projects={p['name'] for p in json.loads((root/'policy/upstream-licences.json').read_text(encoding='utf-8'))['projects']}
    allowed={}
    for entry in data['functions']:
        upstream=entry.get('upstream') or {}
        missing=[k for k in ('file','function') if not entry.get(k)]+[k for k in ('project','file','method') if not upstream.get(k)]
        if missing:raise SystemExit(f'{path.name}: {entry} lacks {missing}')
        if upstream['project'] not in projects:raise SystemExit(f"{path.name}: {entry['function']}: unknown upstream project {upstream['project']} (policy/upstream-licences.json)")
        if not (root/Path(entry['file']).parts[0]).is_dir():
            continue  # its tree left this checkout with its repo at the cutover (framework/, boot/, security/)
        if not (root/entry['file']).is_file():raise SystemExit(f"{path.name}: {entry['file']} does not exist")
        allowed[(entry['file'],entry['function'])]=entry
    return allowed

def function_at(path,line):
    """The function D-Scanner's complexity finding points at: the first `name(` on its declaration line."""
    lines=Path(path).read_text(encoding='utf-8').splitlines()
    found=re.search(r'([A-Za-z_]\w*)\s*\(',lines[line-1]) if 0<line<=len(lines) else None
    return found.group(1) if found else None
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--dfmt',default='dfmt');ap.add_argument('--dscanner',default='dscanner');ap.add_argument('--path',type=Path,action='append',help='Optional explicit source trees; defaults to '+', '.join(TREES)+'.');a=ap.parse_args()
    paths=a.path or [ROOT/name for name in TREES if (ROOT/name).is_dir()]
    for path in paths:
        if not path.is_dir():raise SystemExit('quality source tree missing: '+str(path))
    files=sorted({p for path in paths for p in path.rglob('*.d') if not any(part in ('.dub','.flint','build','artifacts') for part in p.relative_to(path).parts) and not legacy(p)})
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
    allowed=complexity_allowlist();used=set()
    for x in issues:
        if x.get('type') in ['warn','error']:
            if x.get('key')==COMPLEXITY:
                try:rel=Path(x['fileName']).resolve().relative_to(ROOT).as_posix()
                except ValueError:rel=None
                key=(rel,function_at(x['fileName'],x.get('line',0)))
                if key in allowed:
                    used.add(key);continue
            failures.append(f"{x.get('fileName')}:{x.get('line')}: {x.get('message')}")
    scanned={p.resolve().relative_to(ROOT).as_posix() for p in files if p.resolve().is_relative_to(ROOT)}
    for key in sorted(set(allowed)-used):
        if key[0] in scanned:failures.append(f'{key[0]}: {key[1]} is in policy/complexity-allowlist.json but within the complexity limit; remove the entry')
    if failures:raise SystemExit('\n'.join(failures))
    print(json.dumps({'files':len(files),'issues':0,'formatter':'dfmt0.15.2 stdout byte comparison'}))
if __name__=='__main__':main()
