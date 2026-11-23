#!/usr/bin/env python3
"""Fail-closed structural and measured performance gates. No missing-data passes."""
import argparse,json,re,statistics,subprocess,sys,os,shutil,tempfile,hashlib
from pathlib import Path
from d_source import tokens,imported_modules,declared_module,module_default,has_string_mixin,compiler_dependency_edges,module_thread_locals
from perf_stats import finite_samples,median_ratio_interval
from workspace import Workspace,edge_violations,package_repos
import module_budgets
ROOT=Path(__file__).resolve().parents[1]
P=json.loads((ROOT/'policy/packages.json').read_text(encoding='utf-8'))['packages']
B=json.loads((ROOT/'policy/budgets.json').read_text(encoding='utf-8'))
S=json.loads((ROOT/'policy/safety-policy.json').read_text(encoding='utf-8'))

def require(value,message):
    if not value:raise ValueError(message)

def owner(module):
    matches=[n for n,m in P.items() if module==m['module'] or module.startswith(m['module']+'.')]
    require(len(matches)<=1,'ambiguous module owner '+module)
    return matches[0] if matches else None

def prefix_match(module,prefixes):
    return any(module==p or module.startswith(p+'.') for p in prefixes)

def check_import(package,module,where):
    meta=P[package]
    if module in ['std','std.algorithm','std.range','std.all'] or module.startswith('std.regex'):
        require(meta['tier']>1 and not meta['better_c'],where+': forbidden heavy core import '+module)
    dep=owner(module)
    require(not module.startswith('flint.') or dep is not None,where+': unknown Flint module '+module)
    require(dep is None or dep==package or dep in meta['dependencies'],where+': undeclared import '+module)
    if dep is not None and dep!=package:
        private=[P[dep]['module']+'.'+part for part in ['internal','sys','ffi']]
        require(not prefix_match(module,private),where+': cross-package private boundary import '+module)

def check_thread_locals(module,ts,where):
    """Per-task state lives in FiberLocal!T (ADR-030), process state is shared or immutable. A module-level
    mutable variable is thread-local in D, so fibers that migrate or interleave would share it silently."""
    allowed=set(S['thread_local_allowlist'])
    found=set()
    for name,line in module_thread_locals(ts):
        found.add(module+'.'+name)
        require(module+'.'+name in allowed,where+':'+str(line)+': module-level thread-local mutable variable '+name
                +'; use FiberLocal!T for per-task state or shared/immutable storage, or allowlist a runtime root in policy/safety-policy.json')
    stale=sorted(entry for entry in allowed if entry.rsplit('.',1)[0]==module and entry not in found)
    require(not stale,where+': stale thread_local_allowlist entries '+', '.join(stale))

def project_mixin_tokens(text, compiler):
    # DMD dumps Phobos and druntime template expansions in the same file as Flint's.
    # Skip only expansions located inside the bundled compiler's standard library sources.
    installation = Path(compiler).resolve().parents[2]
    # DMD keeps druntime and Phobos under src/; LDC (ldmd2, on hosts without DMD) under import/.
    standard = (installation / 'src/phobos', installation / 'src/druntime/import',
                Path(compiler).resolve().parents[1] / 'import')
    headers = list(re.finditer(r'^// expansion at(?: (.+)\([0-9]+\))?$', text, re.MULTILINE))
    if not headers:
        yield from tokens(text)
        return
    yield from tokens(text[:headers[0].start()])
    for index, header in enumerate(headers):
        end = headers[index + 1].start() if index + 1 < len(headers) else len(text)
        location = header.group(1)
        if location:
            source = (ROOT / location).resolve()
            if source.is_file() and any(source.is_relative_to(root) for root in standard):
                continue
        yield from tokens(text[header.end():end])

def generated_dependencies(packages):
    if not packages:return {'packages':0}
    # macOS arm64 has no DMD code generator (ADR-023); LDC's DMD-compatible driver runs the same front end.
    compiler=shutil.which(os.environ['DMD']) if 'DMD' in os.environ else shutil.which('dmd') or shutil.which('ldmd2')
    require(compiler,'approved string mixins require DMD (or ldmd2) on PATH or DMD=/absolute/path for compiler dependency audit')
    imports=['-I'+str(ROOT/'packages'/name/'source') for name in P]
    count=0
    with tempfile.TemporaryDirectory(prefix='flint-deps-') as temporary:
        for name in sorted(packages):
            sources=sorted((ROOT/'packages'/name/'source').rglob('*.d'))
            for profile in ['debug','release']:
                destination=Path(temporary)/(name+'-'+profile+'.deps')
                expansion=Path(temporary)/(name+'-'+profile+'.mixins.d')
                command=[compiler,'-o-','-unittest','-preview=dip1000','-'+profile,'-deps='+str(destination),'-mixin='+str(expansion)]+imports+[str(p) for p in sources]
                process=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
                require(process.returncode==0,'generated dependency compile failed: '+process.stdout+process.stderr)
                require(destination.is_file(),'compiler did not produce a dependency receipt')
                require(expansion.is_file() and expansion.stat().st_size>0,'string mixin has no instantiated expansion; add a positive unittest fixture')
                expanded=list(project_mixin_tokens(expansion.read_text(encoding='utf-8'),compiler))
                require(expanded,'string mixin has no audited application expansion')
                require(not imported_modules(expanded),'generated import statements are prohibited')
                values=[token.value for token in expanded]
                require(not any(values[i]=='@' and values[i+1] in ['trusted','system'] for i in range(len(values)-1)),'generated unsafe annotations are prohibited')
                for importing,imported in compiler_dependency_edges(destination.read_text(encoding='utf-8')):
                    package=owner(importing)
                    if package is not None:check_import(package,imported,'compiler-generated '+importing)
                count+=1
    return {'packages':len(packages),'compiler_profiles':count}

def boot_layers():
    """ADR-029 section 8: starters hold no D source; a Flint Boot library imports only the packages and Boot
    libraries policy/boot.json declares for it."""
    path=ROOT/'policy/boot.json'
    if not path.is_file():return
    policy=json.loads(path.read_text(encoding='utf-8'))
    libraries=policy['libraries']
    def home(meta):
        # With --workspace, a Boot library or starter is checked in its repo's checkout.
        return WORKSPACE.checkout(meta.get('repo','boot')) if WORKSPACE.file else ROOT
    for name,meta in policy['starters'].items():
        base=home(meta)/meta['directory']
        sources=sorted(str(f.relative_to(base)) for f in base.rglob('*.d') if f.relative_to(base).parts[0]!='example') if base.is_dir() else []
        require(not sources,name+': a starter has no D source: '+(meta['directory']+'/'+sources[0] if sources else ''))
    def boot_owner(module):
        for name,meta in libraries.items():
            if module==meta['module'] or module.startswith(meta['module']+'.'):return name
        return owner(module)
    for name,meta in libraries.items():
        base=home(meta)/meta['directory']/'source'
        for f in sorted(base.rglob('*.d')) if base.is_dir() else []:
            for module in imported_modules(tokens(f.read_text(encoding='utf-8'))):
                dep=boot_owner(module)
                require(dep is None or dep==name or dep in meta['dependencies'],str(f.relative_to(base.parent))+': undeclared Boot-layer import '+module)

def framework_layers():
    """ADR-030: Spring-layer modules (the Spring Framework API and the third-party APIs of rulebook R1) live under
    framework/<artifact>, outside the 37 engine packages. Each is listed in policy/framework.json and keeps the
    package rules: module paths, module-scope @safe:, declared imports only, no private engine imports, no
    thread-local state and no unsafe annotations. EPL-2.0 sources live only in modules licensed EPL-2.0."""
    path=ROOT/'policy/framework.json'
    if not path.is_file():return 0
    modules=json.loads(path.read_text(encoding='utf-8'))['modules']
    root_sdl=(ROOT/'dub.sdl').read_text(encoding='utf-8')
    def layer_owner(module):
        for name,meta in modules.items():
            if module==meta['module'] or module.startswith(meta['module']+'.'):return name
        return None
    for name,meta in modules.items():
        base=ROOT/meta['directory']
        require(meta['directory']=='framework/'+name,name+': a framework module lives in framework/'+name)
        require(('subPackage "'+meta['directory']+'"') in root_sdl,name+': missing from the root subPackage list')
        sdl=(base/'dub.sdl').read_text(encoding='utf-8')
        require(re.search(r'^name "'+re.escape(name)+'"$',sdl,re.MULTILINE),name+': dub.sdl name differs')
        require(re.search(r'^license "'+re.escape(meta['licence'])+'"$',sdl,re.MULTILINE),name+': dub.sdl license differs from policy')
        actual=set(re.findall(r'dependency\s+"flint:([\w-]+)"\s+version="\*"',sdl))
        require(actual==set(meta['dependencies']),name+': SDL dependencies differ from policy')
        require(len(re.findall(r'\bdependency\b',sdl))==len(actual),name+': noncanonical dependency recipe')
        for dep in meta['dependencies']:
            require(dep in P or dep in modules,name+': unknown dependency '+dep)
        epl=meta['licence']=='EPL-2.0'
        require(epl==(base/'LICENSE').is_file(),name+': an EPL-2.0 module carries its own LICENSE, and only it')
        for f in sorted((base/'source').rglob('*.d')):
            text=f.read_text(encoding='utf-8');ts=list(tokens(text));where=str(f.relative_to(ROOT))
            module=declared_module(ts)
            parts=list(f.relative_to(base/'source').with_suffix('').parts)
            if parts[-1]=='package':parts.pop()
            require(module=='.'.join(parts),where+': module/path mismatch')
            require(layer_owner(module)==name,where+': source belongs to another module')
            require(module_default(ts)=='safe',where+': require module-scope @safe: before declarations')
            require(not has_string_mixin(ts) or meta.get('generator',False),where+': string mixin outside an approved API-layer internal')
            require(epl==('SPDX-License-Identifier: EPL-2.0' in text),where+': EPL-2.0 sources belong only to EPL-2.0 modules')
            values=[t.value for t in ts]
            require(not any(values[i]=='@' and values[i+1] in ['trusted','system'] for i in range(len(values)-1)),where+': the API layer stays @safe')
            for imported in imported_modules(ts):
                dep=layer_owner(imported)
                if dep is not None:
                    require(dep==name or dep in meta['dependencies'],where+': undeclared import '+imported)
                    continue
                dep=owner(imported)
                require(not imported.startswith('flint.') or dep is not None,where+': unknown Flint module '+imported)
                require(dep is None or dep in meta['dependencies'],where+': undeclared import '+imported)
                if dep is not None:
                    private=[P[dep]['module']+'.'+part for part in ['internal','sys','ffi']]
                    require(not prefix_match(imported,private),where+': cross-package private boundary import '+imported)
            check_thread_locals(module,ts,where)
    return len(modules)

WORKSPACE=Workspace()

def structural(selected):
    visited=set();active=set()
    def visit(n):
        require(n not in active,'dependency cycle at '+n)
        if n in visited:return
        active.add(n)
        for d in P[n]['dependencies']:
            require(d in P,'unknown dependency '+d)
            require(P[d]['tier']<=P[n]['tier'],'higher-tier import '+n+' -> '+d)
            require(not(P[n]['tier']==4 and P[d]['tier'] in [2,3]),'CLI/web-data isolation')
            visit(d)
        active.remove(n);visited.add(n)
    for n in P:visit(n)
    if (ROOT/'policy/packages.json').is_file():
        violations,_=edge_violations(ROOT)
        require(not violations,'repo edge: '+(violations[0][2] if violations else ''))
    root_sdl=(ROOT/'dub.sdl').read_text(encoding='utf-8')
    require(set(re.findall(r'subPackage\s+"packages/([\w-]+)"',root_sdl))==set(P),'root subpackage list differs')
    boot_layers()
    module_budgets.load(B,P,ROOT)
    framework=framework_layers()
    mixin_packages=set()
    for n in selected:
        meta=P[n];pkg=WORKSPACE.package_dir(n,ROOT) if WORKSPACE.file else ROOT/'packages'/n;sdl=(pkg/'dub.sdl').read_text(encoding='utf-8')
        actual=set(re.findall(r'dependency\s+"flint:([\w-]+)"\s+version="\*"',sdl))
        require(actual==set(meta['dependencies']),n+': SDL dependencies differ from policy')
        require(len(re.findall(r'\bdependency\b',sdl))==len(actual),n+': noncanonical dependency recipe')
        for f in (pkg/'source').rglob('*.d'):
            text=f.read_text(encoding='utf-8');ts=list(tokens(text));vals=[t.value for t in ts]
            module=declared_module(ts)
            relative=f.relative_to(pkg/'source').with_suffix('')
            parts=list(relative.parts)
            if parts[-1]=='package':parts.pop()
            require(module=='.'.join(parts),str(f)+': module/path mismatch')
            require(owner(module)==n,str(f)+': source belongs to another package')
            low=prefix_match(module,S['unsafe_module_prefixes'].get(n,[]))
            default=module_default(ts)
            require(default=='safe' or (low and default=='system'),str(f)+': require module-scope @safe: before declarations; raw allowlisted FFI may use @system:')
            if has_string_mixin(ts):
                require(prefix_match(module,S['generator_module_prefixes']),str(f)+': string mixin outside approved generator module')
                mixin_packages.add(n)
            for mod in imported_modules(ts):
                check_import(n,mod,str(f))
            check_thread_locals(module,ts,str(f))
            lines=text.splitlines()
            for i,t in enumerate(ts[:-1]):
                if t.value!='@' or ts[i+1].value not in ['trusted','system']:continue
                require(low,str(f)+': unsafe annotation outside allowlisted low-level directory')
                if ts[i+1].value=='trusted':
                    require(i+2>=len(ts) or ts[i+2].value not in [':','{'],str(f)+': no @trusted scopes/blocks')
                    nearby='\n'.join(lines[max(0,t.line-3):t.line])
                    require('// SAFETY:' in nearby,str(f)+': @trusted missing adjacent SAFETY rationale')
                    j=i+2
                    while j<len(ts) and ts[j].value not in ['{',';']:j+=1
                    if j<len(ts) and ts[j].value=='{':
                        depth=1;k=j+1
                        while k<len(ts) and depth:
                            depth+=(ts[k].value=='{')-(ts[k].value=='}');k+=1
                        require(depth==0,str(f)+': unbalanced trusted body')
                        require(ts[k-1].line-ts[j].line<=S['max_trusted_lines'],str(f)+': trusted function exceeds 60 lines')
    return {'packages':len(selected),'graph_nodes':len(P),'framework_modules':framework,'generated_dependencies':generated_dependencies(mixin_packages)}

def compare_series(new,old,ceiling,label,minimum=9):
    finite_samples(new,minimum);finite_samples(old,minimum)
    med,lo,hi=median_ratio_interval(new,old)
    require(med<=ceiling and hi<=ceiling,label+f': ratio median {med:.4f}, 99% upper {hi:.4f} exceeds {ceiling}')
    return [med,lo,hi]

def measured(current,baseline=None):
    require(current['schema']==1 and (baseline is None or baseline['schema']==1),'evidence schema must equal 1')
    if baseline is not None:
        for key in ['runner_fingerprint','toolchain_fingerprint','dependency_lock_sha256','workload_sha256']:
            require(current['environment'][key]==baseline['environment'][key],key+' differs; comparisons invalid')
    require(current['environment']['runner_label']==B['runner'],'wrong performance runner')
    if baseline is not None:require(current['commit']!=baseline['commit'],'baseline must identify a different base commit')
    expected={'quality','safety','dag','betterc','sanitizers','cross_platform','hot_gc','runtime','compile','size'}
    require(set(current['receipts'])==expected,'missing/unknown gate receipts')
    for name,r in current['receipts'].items():
        require(r['exit_code']==0 and isinstance(r['command'],list) and r['command'] and re.fullmatch(r'[0-9a-f]{64}',r['sha256']),name+': unsuccessful or malformed command receipt')
    require(set(current['packages'])==set(P) and (baseline is None or set(baseline['packages'])==set(P)),'all 37 package measurements required')
    for name,meta in P.items():
        x=current['packages'][name];y=baseline['packages'][name] if baseline is not None else None
        for k in ['dmd_cold_seconds','dmd_incremental_seconds','ldc_cold_seconds','ldc_incremental_seconds']:
            finite_samples(x[k],9)
            require(statistics.median(x[k])<meta['budget'][k],name+': '+k+' absolute ceiling')
            if y is not None:compare_series(x[k],y[k],B['regression']['compile_ratio_max'],name+': '+k)
        for k in ['compiler_peak_rss_bytes','template_instances']:
            require(type(x[k]) is int and (x[k]>0 if k=='compiler_peak_rss_bytes' else x[k]>=0)
                    and x[k]<=meta['budget'][k],name+': '+k+' absolute ceiling')
            ratio=B['regression']['compiler_rss_ratio_max' if k=='compiler_peak_rss_bytes' else 'template_ratio_max']
            if y is not None:require(x[k]<=y[k]*ratio,name+': '+k+' regression')
        require(type(x['incremental_linked_bytes']) is int and 0<=x['incremental_linked_bytes']<=meta['budget']['incremental_linked_bytes'],name+': incremental size ceiling')
        if y is not None:require(x['incremental_linked_bytes']<=y['incremental_linked_bytes']*B['regression']['binary_ratio_max'],name+': incremental size regression')
    module_budgets.check_measured(module_budgets.load(B,P,ROOT),current,baseline,B['regression']['binary_ratio_max'])
    for app,caps in B['benchmark_apps'].items():
        x=current['apps'][app];y=baseline['apps'][app] if baseline is not None else None
        for k,cap in caps.items():
            if k.endswith('seconds'):
                finite_samples(x[k],9)
                require(statistics.median(x[k])<cap,app+': '+k+' ceiling')
                if y is not None:compare_series(x[k],y[k],B['regression']['compile_ratio_max'],app+': '+k)
            else:
                for profile in ['O3','Oz']:
                    require(type(x[profile][k]) is int and 0<x[profile][k]<cap,app+': '+profile+' '+k+' ceiling')
                    if y is not None:require(x[profile][k]<=y[profile][k]*B['regression']['binary_ratio_max'],app+': size regression')
    require(current['gc']['worker_count']>0 and len(current['gc']['allocated_bytes_per_worker'])==current['gc']['worker_count'],'missing GC worker counters')
    require(all(x==0 for x in current['gc']['allocated_bytes_per_worker']) and current['gc']['collection_delta']==0,'hot-path GC activity')
    required_platforms={'linux-x86_64-glibc','linux-aarch64-glibc','linux-x86_64-musl','linux-aarch64-musl','macos-arm64','windows-x86_64','wasm32'}
    require(set(current['platforms'])==required_platforms and all(value is True for value in current['platforms'].values()),'missing/failing cross-platform validation')
    for metric in ['p50_ms','p99_ms','p999_ms','peak_rss_bytes','cpu_ns_per_request']:
        finite_samples(current['rest'][metric],9)
        if baseline is not None:compare_series(current['rest'][metric],baseline['rest'][metric],B['regression']['latency_ratio_max'],'REST '+metric)
    finite_samples(current['rest']['requests_per_second'],9)
    if baseline is not None:compare_series([1/x for x in current['rest']['requests_per_second']],[1/x for x in baseline['rest']['requests_per_second']],1/B['regression']['throughput_ratio_min'],'REST throughput')
    for micro in ['arena','serde','validate','router','reactor_echo']:
        finite_samples(current['micro'][micro],21)
        if baseline is not None:compare_series(current['micro'][micro],baseline['micro'][micro],B['regression']['latency_ratio_max'],micro,21)
    for metric in ['p99_ms','peak_rss_bytes','cpu_ns_per_request']:
        compare_series(current['rest'][metric],current['go']['rest'][metric],.99,'Go comparison '+metric)
    compare_series([1/x for x in current['rest']['requests_per_second']],[1/x for x in current['go']['rest']['requests_per_second']],1/1.01,'Go throughput')
    for app in ['bench-cli','bench-rest']:
        compare_series(current['apps'][app]['dmd_cold_seconds'],current['go']['apps'][app]['cold_seconds'],.99,'Go build '+app)
        require(current['apps'][app]['Oz']['binary_bytes']<=current['go']['apps'][app]['binary_bytes']*B['go_relative']['binary_ratio_max'],'Go binary size '+app)
    if baseline is None:
        return {'initial_baseline_validation':'pass','regression_comparison':'not_run_no_prior_baseline','commit':current['commit']}
    return {'all_six_gates':'pass','commit':current['commit']}

def verify_evidence_artifacts(evidence,directory):
    require(evidence.get('mode')=='production','only production evidence can pass the full gate')
    directory=Path(directory).resolve()
    def verify(item):
        path=(directory/item['artifact']).resolve()
        require(path.is_relative_to(directory),'receipt artifact leaves evidence bundle')
        require(path.is_file(),'receipt artifact missing: '+str(path))
        digest=hashlib.sha256()
        with path.open('rb') as source:
            for chunk in iter(lambda:source.read(1024*1024),b''):digest.update(chunk)
        require(digest.hexdigest()==item['sha256'],'receipt artifact digest mismatch: '+str(path))
    for name,receipt in evidence['receipts'].items():
        require(receipt.get('schema')==1 and receipt.get('commit')==evidence['commit'],name+': receipt identity differs')
        require(type(receipt.get('exit_code')) is int and receipt['exit_code']==0 and
                isinstance(receipt.get('command'),list) and receipt['command'] and
                all(isinstance(value,str) and value for value in receipt['command']),name+': unsuccessful command receipt')
        verify(receipt)
        for artifact in receipt.get('artifacts',[]):verify(artifact)
    # Retained source receipts bind displayed metrics as well as their files.
    def payload(name):return json.loads((directory/evidence['receipts'][name]['artifact']).read_text(encoding='utf-8'))
    builds=payload('compile')
    require(builds==payload('size'),'compile and size evidence came from different builds')
    for key in ['packages','apps','modules']:require(evidence[key]==builds[key],key+': summary differs from measured source artifact')
    require(evidence['go']['apps']==builds['go']['apps'],'Go build summary differs from measured source artifact')
    runtime=payload('runtime')
    require(evidence['rest']==runtime['http']['rest'] and evidence['go']['rest']==runtime['http']['go']['rest'],
            'HTTP summary differs from measured source artifact')
    require(evidence['micro']==runtime['micro'],'micro summary differs from measured source artifact')
    require(evidence['gc']==payload('hot_gc')['gc'],'GC summary differs from measured source artifact')
    require(evidence['platforms']==payload('cross_platform')['platforms'],'platform summary differs from recorded source artifact')

def api_mapping(checkout,repo):
    """A repo's API mapping: api/<repo>/mapping.json in the monorepo, api/mapping.json in an extracted repo."""
    nested=checkout/'api'/repo/'mapping.json'
    return nested if nested.is_file() else checkout/'api'/'mapping.json'

def run_flint_json(flint,arguments,home):
    """Run `flint <arguments> --json` with the Flint home at `home`; the parsed document."""
    out=subprocess.run([str(flint),*arguments,'--json'],capture_output=True,text=True,env=dict(os.environ,FLINT_HOME=str(home)))
    try:return json.loads(out.stdout)
    except ValueError:raise ValueError('flint '+' '.join(arguments[:2])+' printed no JSON: '+(out.stderr or out.stdout)[-400:])

def api_gate(repos,flint,release=False):
    """ADR-030 section 8: per repo, `flint api headers` over its packages (every ported file carries the section 7
    header for an upstream the licence matrix lets Flint port) and `flint api coverage` of its mapping over every
    manifest api/upstreams.json assigns to it. Coverage is a ratchet: no module's unclassified count may rise above
    the repo's coverage-baseline.json, and a checklist its slice marks complete must be complete. With `release`,
    every element must be classified, as the release requires."""
    require(flint.is_file(),f'flint api gate: {flint} is missing; bootstrap it with python3 tools/install_toolchains.py --compiler flint')
    home=WORKSPACE.checkout('flint')
    pins=json.loads((home/'api'/'upstreams.json').read_text(encoding='utf-8'))['upstreams']
    owners={u['repo'] for u in pins if (home/'api'/'upstream'/(u['project']+'-'+u['version']+'.json')).is_file()}
    report,failures={},[]
    for repo in repos:
        checkout=WORKSPACE.checkout(repo)
        dirs=[str(WORKSPACE.package_dir(n)) for n in sorted(package_repos(ROOT)) if package_repos(ROOT)[n][0]==repo and WORKSPACE.package_dir(n).is_dir()]
        entry={}
        if dirs:
            headers=run_flint_json(flint,['api','headers',*dirs],home)
            entry['headers']={'files':headers.get('files',0),'ported':headers.get('ported',0),'problems':headers.get('problems',0)}
            if not headers.get('ok'):failures.append(f'{repo}: {len(headers.get("diagnostics",[]))} ported-header problems, first: '+
                                                    next((d['file']+': '+d['message'] for d in headers.get('diagnostics',[])),'flint api headers failed'))
        if repo in owners:
            mapping=api_mapping(checkout,repo)
            if not mapping.is_file():failures.append(f'{repo}: owns upstream manifests but has no {mapping.relative_to(checkout)}')
            else:
                slices=sum((['--slice',str(s)] for s in sorted((checkout/'docs'/'spring').glob('*/slice.json'))),[])
                coverage=run_flint_json(flint,['api','coverage','--repo',repo,'--mapping',str(mapping),'--show','0',*slices,
                                               *(['--release'] if release else [])],home)
                entry['coverage']={m['project']+'@'+m['version']:{k:m['summary'][k] for k in ('total','ported','adapted','excluded','unclassified')} for m in coverage.get('manifests',[])}
                entry['mode']=coverage.get('mode')
                if coverage.get('improvements'):entry['lower_the_baseline']=coverage['improvements']
                if not coverage.get('ok'):failures.append(f'{repo}: '+'; '.join(d['message'] for d in coverage.get('diagnostics',[]) if d['severity']=='error'))
        report[repo]=entry
    return report,failures

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--package',action='append',choices=sorted(P));ap.add_argument('--gate',choices=['structural','baseline','all','api','spring'],required=True)
    ap.add_argument('--flint',type=Path,default=ROOT/'.flint'/'bin'/'flint',help='api gate: the flint executable (default: .flint/bin/flint)')
    ap.add_argument('--release',action='store_true',help='api gate: require every element classified, not just the baseline ratchet')
    ap.add_argument('--evidence',type=Path,help='baseline/all: the evidence file; spring: the harness output directory');ap.add_argument('--baseline',type=Path)
    ap.add_argument('--repo',help='check only this repo\'s packages (policy/repos.json), as its own CI will after the split')
    ap.add_argument('--workspace',type=Path,help='flint.workspace/1 file: the checkouts of each repo at pinned commits; default: this monorepo')
    a=ap.parse_args()
    global WORKSPACE
    WORKSPACE=Workspace(a.workspace)
    problems=WORKSPACE.verify()
    require(not problems,'workspace: '+'; '.join(problems))
    selected=a.package or [n for n in P if a.repo is None or package_repos(ROOT)[n][0]==a.repo]
    require(a.repo is None or a.repo in {r for r,_ in package_repos(ROOT).values()},'unknown repo '+str(a.repo))
    if a.gate=='spring':
        # ADR-030 section 8: the side-by-side suites, both build headlines, the Spring workload and the GC matrix.
        require(a.evidence is not None,'spring gate: --evidence <directory> of the harness output is required')
        from spring_gate import spring_gate
        report,failures=spring_gate(a.evidence)
        print(json.dumps({'spring':report,'failures':failures},indent=2))
        require(not failures,'spring: '+' | '.join(failures))
        return
    if a.gate=='api':
        repos=[a.repo] if a.repo else sorted({r for r,_ in package_repos(ROOT).values()}|{u['repo'] for u in json.loads((ROOT/'api'/'upstreams.json').read_text(encoding='utf-8'))['upstreams']})
        report,failures=api_gate(repos,a.flint.resolve(),a.release)
        print(json.dumps({'api':report,'failures':failures},indent=2))
        require(not failures,'api: '+' | '.join(failures))
        return
    result=structural(selected)
    if a.repo:result['repo']=a.repo
    _,deferred=edge_violations(ROOT)
    if deferred:result['pending_repo_edges']=sorted(message for _,_,message in deferred)
    if a.gate in ['baseline','all']:
        require(a.evidence is not None,'measured evidence is required; missing evidence never passes')
        require(a.gate!='all' or a.baseline is not None,'regression gates require measured base evidence')
        require(a.gate!='baseline' or a.baseline is None,'initial baseline validation cannot silently accept a comparison baseline')
        current=json.loads(a.evidence.read_text(encoding='utf-8'))
        verify_evidence_artifacts(current,a.evidence.parent)
        baseline=None
        if a.baseline is not None:
            baseline=json.loads(a.baseline.read_text(encoding='utf-8'))
            verify_evidence_artifacts(baseline,a.baseline.parent)
        result.update(measured(current,baseline))
    print(json.dumps(result,indent=2))
if __name__=='__main__':
    try:main()
    except (ValueError,KeyError,OSError) as e:print('GATE FAILED:',e,file=sys.stderr);sys.exit(1)
