#!/usr/bin/env python3
"""DUB workspace orchestration. Never reports source-free packages as built/tested."""
import argparse,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PACKAGES=json.loads((ROOT/'policy/packages.json').read_text())['packages']

def closure(names,reverse=False):
    result=set(names)
    while True:
        prior=set(result)
        for name,meta in PACKAGES.items():
            if reverse and result.intersection(meta['dependencies']):result.add(name)
            if not reverse and name in result:result.update(meta['dependencies'])
        if result==prior:return result

def ordered(names):
    result=[];seen=set()
    def visit(n):
        if n in seen:return
        seen.add(n)
        for d in PACKAGES[n]['dependencies']:visit(d)
        if n in names:result.append(n)
    for n in sorted(names):visit(n)
    return result

def affected(base):
    r=subprocess.run(['git','diff','--name-only',base,'--'],cwd=ROOT,text=True,capture_output=True,check=True)
    paths=r.stdout.splitlines();out=set()
    for p in paths:
        parts=Path(p).parts
        if len(parts)>2 and parts[0]=='packages' and parts[1] in PACKAGES:out.add(parts[1])
        elif not p.endswith('.md'):return set(PACKAGES)
    return closure(out,True)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['list','affected','build','test','describe'])
    ap.add_argument('--package',action='append',choices=sorted(PACKAGES));ap.add_argument('--base')
    ap.add_argument('--compiler',default='dmd');ap.add_argument('--build',default='debug')
    a=ap.parse_args();names=affected(a.base) if a.base else set(a.package or PACKAGES)
    if a.action in ['list','affected']:
        print('\n'.join(ordered(names)));return
    for n in ordered(names):
        pkg=ROOT/'packages'/n
        if a.action!='describe' and not list((pkg/'source').rglob('*.d')):
            raise SystemExit(f'{n}: no implementation sources; follow its milestone task')
        cmd=['dub',a.action,':'+n,'--compiler='+a.compiler]
        if a.action=='build':cmd.append('--build='+a.build)
        print('+',' '.join(cmd),flush=True);subprocess.run(cmd,cwd=ROOT,check=True)
if __name__=='__main__':main()
