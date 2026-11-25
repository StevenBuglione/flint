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
# Flint's patched dfmt (toolchain/dfmt-0.15.2-stack-udas.patch) stacks user-defined attributes as Java stacks annotations.
DFMT_FLINT_SUFFIX='+flint.stack-udas'

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
BASELINE_SCHEMA='flint.quality-baseline/1'
def rel(path):
    try:return Path(path).resolve().relative_to(ROOT).as_posix()
    except ValueError:return str(path)
def finding_key(check,message):
    """A finding's identity in the baseline: its check and message, with numbers (line counts, complexity scores) and
    the line it is on left out, so an edit elsewhere in the file does not move it."""
    return check+': '+re.sub(r'\d+','#',message)
def baseline_counts(path):
    """{file: {finding key: count}} over every tree of a policy/quality-baseline.json."""
    if not path.is_file():return {}
    data=json.loads(path.read_text(encoding='utf-8'))
    if data.get('schema')!=BASELINE_SCHEMA:raise SystemExit(f'{path}: schema must be {BASELINE_SCHEMA}')
    return {f:dict(keys) for tree in data['trees'].values() for f,keys in tree.items()}
def write_baseline(path,counts):
    trees={}
    for f in sorted(counts):
        if counts[f]:trees.setdefault(f.split('/',1)[0],{})[f]=dict(sorted(counts[f].items()))
    path.write_text(json.dumps({'schema':BASELINE_SCHEMA,'note':'Known quality findings per file, a ratchet: '
        'tools/quality.py --baseline fails on any finding not listed here and on any listed finding that is gone. It '
        'only shrinks (--shrink-baseline); recording findings (--record-baseline) is the integration owner\'s, '
        '2026-11-25 coordinator decision on the definition of done.','trees':trees},indent=2)+'\n',encoding='utf-8')
def under(f,roots):return any(f==r or f.startswith(r+'/') for r in roots)
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--dfmt',default='dfmt');ap.add_argument('--dscanner',default='dscanner');ap.add_argument('--path',type=Path,action='append',help='Optional explicit source trees; defaults to '+', '.join(TREES)+'.')
    ap.add_argument('--baseline',type=Path,help='a ratchet (policy/quality-baseline.json): fail only on findings it does not list, and on listed findings that are gone')
    ap.add_argument('--shrink-baseline',action='store_true',help='with --baseline: remove the listed findings that are gone under --path; never adds one')
    ap.add_argument('--record-baseline',action='store_true',help='with --baseline: record every current finding under --path (integration owner only)')
    a=ap.parse_args()
    if (a.shrink_baseline or a.record_baseline) and not a.baseline:raise SystemExit('--shrink-baseline and --record-baseline need --baseline')
    paths=a.path or [ROOT/name for name in TREES if (ROOT/name).is_dir()]
    for path in paths:
        if not path.is_dir():raise SystemExit('quality source tree missing: '+str(path))
    files=sorted({p for path in paths for p in path.rglob('*.d') if not any(part in ('.dub','.flint','build','artifacts') for part in p.relative_to(path).parts) and not legacy(p)})
    if not files:raise SystemExit('quality gate has no implementation sources')
    version=subprocess.run([a.dfmt,'--version'],capture_output=True,text=True)
    if DFMT_FLINT_SUFFIX not in version.stdout:
        raise SystemExit(f'{a.dfmt} is not Flint\'s patched dfmt (its --version lacks {DFMT_FLINT_SUFFIX}); run python3 tools/install_quality_tools.py')
    known=baseline_counts(a.baseline) if a.baseline else {}
    findings=[];diffs={}  # (file, key, text)
    for p in files:
        source=p.read_bytes();r=subprocess.run([a.dfmt,'--config',str(ROOT),str(p)],capture_output=True,check=True)
        if r.stdout!=source:
            findings.append((rel(p),finding_key('dfmt','formatter difference'),str(p)+': formatter difference'))
            diffs[str(p)]=''.join(difflib.unified_diff(source.decode().splitlines(True),r.stdout.decode().splitlines(True),fromfile=str(p),tofile='dfmt output'))
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
                key=(rel(x['fileName']),function_at(x['fileName'],x.get('line',0)))
                if key in allowed:
                    used.add(key);continue
            findings.append((rel(x['fileName']),finding_key(x.get('key',''),x.get('message','')),f"{x.get('fileName')}:{x.get('line')}: {x.get('message')}"))
    scanned={rel(p) for p in files if p.resolve().is_relative_to(ROOT)}
    for key in sorted(set(allowed)-used):
        if key[0] in scanned:findings.append((key[0],finding_key('complexity-allowlist',key[1]),f'{key[0]}: {key[1]} is in policy/complexity-allowlist.json but within the complexity limit; remove the entry'))
    roots=[rel(p) for p in paths]
    current={}
    for f,key,_ in findings:current.setdefault(f,{}).setdefault(key,0);current[f][key]+=1
    if a.record_baseline or a.shrink_baseline:
        counts={f:dict(v) for f,v in known.items() if not under(f,roots)}
        for f in set(current)|{f for f in known if under(f,roots)}:
            mine=current.get(f,{}) if a.record_baseline else {k:min(n,current.get(f,{}).get(k,0)) for k,n in known.get(f,{}).items()}
            mine={k:n for k,n in mine.items() if n}
            if mine:counts[f]=mine
        write_baseline(a.baseline,counts)
        print(json.dumps({'baseline':str(a.baseline),'files':len(counts),'findings':sum(sum(v.values()) for v in counts.values())}));return
    failures=[];seen={}
    for f,key,text in findings:
        seen.setdefault((f,key),0);seen[(f,key)]+=1
        if seen[(f,key)]>known.get(f,{}).get(key,0):
            failures.append(text)
            if text.endswith(': formatter difference') and text[:-len(': formatter difference')] in diffs:print(diffs[text[:-len(': formatter difference')]])
    if a.baseline:
        for f in sorted(f for f in known if under(f,roots)):
            for key,n in sorted(known[f].items()):
                gone=n-current.get(f,{}).get(key,0)
                if gone>0:failures.append(f'{f}: {gone} of {n} baseline finding(s) "{key}" are gone; shrink the baseline: python3 tools/quality.py '+' '.join('--path '+r for r in roots)+f' --baseline {rel(a.baseline)} --shrink-baseline')
    if failures:raise SystemExit('\n'.join(failures))
    print(json.dumps({'files':len(files),'issues':0,'baseline_findings':sum(sum(v.values()) for f,v in current.items()) if a.baseline else 0,'formatter':'dfmt0.15.2+flint.stack-udas stdout byte comparison'}))
if __name__=='__main__':main()
