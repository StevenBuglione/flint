#!/usr/bin/env python3
"""Run Flint's concrete CI producers. Missing implementation/evidence is a failure."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
import profiles
from install_rust import environment as rust_environment
from install_toolchains import (LLVM_ROOT, SANITIZER_DEFAULTLIB, SANITIZER_RUNTIME,
                                SANITIZER_RUNTIME_RECEIPT, verified_sanitizer_runtime)

ROOT=Path(__file__).resolve().parents[1]
PYTHON=sys.executable
PACKAGES=json.loads((ROOT/'policy/packages.json').read_text())['packages']
PLATFORMS=('linux-x86_64-glibc','linux-aarch64-glibc','linux-x86_64-musl',
           'linux-aarch64-musl','macos-arm64','windows-x86_64','wasm32')
STATIC=('quality','dag','api','safety','betterc')
# Sanitizer lane only: druntime/Phobos built with fake-stack GC scanning
# (tools/install_toolchains.py --compiler ldc-sanitizer-runtime). Normal lanes
# keep the shipped LDC runtime.
SANITIZER_CLANG=r'clang version 22\.1\.8\b'

def require(value,message):
    if not value:raise ValueError(message)

def digest(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def git_head(root):
    text=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
    require(re.fullmatch(r'[a-f0-9]{40}|[a-f0-9]{64}',text),'checkout has no exact Git identity')
    return text

class Runner:
    def __init__(self,plan=False):self.plan=plan
    def run(self,command,*,cwd=ROOT,env=None):
        command=[str(value) for value in command]
        print(json.dumps({'command':command,'cwd':str(cwd),'plan_only':self.plan}),flush=True)
        if not self.plan:subprocess.run(command,cwd=cwd,env=env,check=True)

def package_source(name):
    """A package's source directory: under packages/ here, or in its repo's checkout after the cutover (the
    workspace FLINT_WORKSPACE names, else the fetched platform modules' .flint/platform/workspace.json)."""
    local=ROOT/'packages'/name/'source'
    if local.is_dir():return local
    sys.path.insert(0,str(ROOT/'tools'))
    import workspace
    named=os.environ.get('FLINT_WORKSPACE') or ROOT/'.flint'/'platform'/'workspace.json'
    if not Path(named).is_file():return local
    return workspace.Workspace(named).package_dir(name,ROOT)/'source'

def implementation_required():
    missing=[]
    for name,meta in PACKAGES.items():
        module=Path(*meta['module'].split('.'))
        source=package_source(name)
        # A package whose root holds only leaf modules (flint:engine-aot, AOT contract section 4) has no package.d.
        if not (source/module.with_suffix('.d')).is_file() and not (source/module/'package.d').is_file() \
                and not any((source/module).glob('*.d')):
            missing.append(name)
    require(not missing,'implementation milestone incomplete; public source modules missing: '+', '.join(missing))

def import_flags():
    return ['-I'+str(package_source(name)) for name in PACKAGES]

def native_target():
    machine=platform.machine().lower()
    arch='aarch64' if machine in ('arm64','aarch64') else 'x86_64' if machine in ('amd64','x86_64') else machine
    if sys.platform=='win32':return 'windows-'+arch
    if sys.platform=='darwin':return 'macos-'+('arm64' if arch=='aarch64' else arch)
    libc='musl' if list(Path('/lib').glob('ld-musl-*.so.1')) else 'glibc'
    return 'linux-'+arch+'-'+libc

def windows_environment():
    if sys.platform!='win32':return
    if shutil.which('cl') and shutil.which('msbuild'):return
    vswhere=Path(os.environ.get('ProgramFiles(x86)',r'C:\Program Files (x86)'))/'Microsoft Visual Studio/Installer/vswhere.exe'
    require(vswhere.is_file(),'Visual Studio Build Tools and vswhere are required')
    installation=subprocess.check_output([str(vswhere),'-latest','-products','*','-requires',
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64','-property','installationPath'],text=True).strip()
    setup=Path(installation)/'Common7/Tools/VsDevCmd.bat'
    require(setup.is_file(),'missing Visual Studio x64 developer environment')
    with tempfile.TemporaryDirectory(prefix='flint-msvc-') as temporary:
        batch=Path(temporary)/'environment.cmd'
        batch.write_text('@echo off\ncall "'+str(setup)+'" -arch=x64 -host_arch=x64 >nul\nif errorlevel 1 exit /b 1\nset\n')
        values=subprocess.check_output(['cmd.exe','/d','/c',str(batch)],text=True)
    # Capture the environment privately; never print it or retain it as an artifact.
    for line in values.splitlines():
        if '=' in line and not line.startswith('='):
            key,value=line.split('=',1);os.environ[key]=value
    require(shutil.which('cl') and shutil.which('msbuild'),'MSVC environment was not initialized')

def windows_tools(runner):
    require(sys.platform=='win32' or runner.plan,'Windows prerequisite installation is Windows-only')
    runner.run([PYTHON,'-m','pip','install','meson==1.12.1'])
    if runner.plan:return
    lock=json.loads((ROOT/'policy/toolchains.json').read_text())
    asset=lock['assets']['win_flex_bison-2.5.25.zip']
    directory=ROOT/'.tools/winflexbison-2.5.25';directory.mkdir(parents=True,exist_ok=True)
    archive=directory/'upstream.zip'
    if not archive.is_file() or digest(archive)!=asset['sha256']:
        with urllib.request.urlopen(asset['url'],timeout=60) as source,archive.open('wb') as output:
            shutil.copyfileobj(source,output)
    require(digest(archive)==asset['sha256'],'winflexbison archive checksum mismatch')
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.infolist():
            destination=(directory/member.filename).resolve()
            require(destination.is_relative_to(directory.resolve()) and ':' not in member.filename,
                    'unsafe winflexbison archive path')
            require((member.external_attr>>16)&0o170000!=0o120000,'symlink in winflexbison archive')
        bundle.extractall(directory)
    for original,alias in (('win_bison.exe','bison.exe'),('win_flex.exe','flex.exe')):
        require((directory/original).is_file(),'unexpected winflexbison archive layout')
        shutil.copy2(directory/original,directory/alias)
    if os.environ.get('GITHUB_PATH'):
        with open(os.environ['GITHUB_PATH'],'a') as output:output.write(str(directory)+'\n')
    print(json.dumps({'winflexbison':str(directory),'sha256':asset['sha256']}))

def native(runner,target,sanitize=False):
    if not runner.plan:require(native_target()==target,'native test target differs from actual host: '+native_target())
    if not runner.plan:windows_environment()
    prefix=ROOT/'.tools/rust'
    runner.run([PYTHON,'tools/install_rust.py','--target',target,'--destination',prefix])
    version=json.loads((ROOT/'policy/toolchains.json').read_text())['versions']['rust']
    env=rust_environment(prefix,version)
    command=[PYTHON,'tools/native_build.py','--profile','ci','--target',target,'--phase','build','--emit-dub']
    if sanitize:
        # Rust's default host engine remains uninstrumented. Install it into the
        # cumulative prefix before rebuilding the C providers/shims with ASan/UBSan.
        # Start from an empty prefix: the uninstrumented engine must never link the
        # instrumented providers a previous sanitizer run installed there.
        if not runner.plan:shutil.rmtree(ROOT/'.native-sanitized'/'install'/target,ignore_errors=True)
        runner.run([PYTHON,'tools/native_build.py','--profile','wasm-host','--target',target,
                    '--phase','build','--work-dir','.native-sanitized/engine-build',
                    '--prefix','.native-sanitized/install/'+target],env=env)
        command+=['--sanitize','address,undefined','--cc','clang','--cxx','clang++','--work-dir','.native-sanitized']
    else:
        command+=['--library','wasmtime']
        # macOS also tests the WKWebView backend: the lane runs in the user's GUI session (ADR-024).
        if target=='macos-arm64':command+=['--library','wkwebview']
    runner.run(command,env=env)

def sanitizer_runtime_dir():
    return ROOT/'.tools'/SANITIZER_RUNTIME

def probe(command):
    try:return subprocess.check_output(command,text=True,stderr=subprocess.STDOUT)
    except (OSError,subprocess.CalledProcessError):return ''

def sanitizer_toolchain(runner):
    """Select Clang 22.1.8 and prepare the fake-stack-aware LDC runtime."""
    if not re.search(SANITIZER_CLANG,probe(['clang','--version'])):
        # No matching host Clang: use the pinned official LLVM release subset.
        runner.run([PYTHON,'tools/install_toolchains.py','--compiler','clang'])
        os.environ['PATH']=str(ROOT/'.tools'/LLVM_ROOT/'bin')+os.pathsep+os.environ.get('PATH','')
    runner.run([PYTHON,'tools/install_toolchains.py','--compiler','ldc-sanitizer-runtime'])
    if runner.plan:return
    require(re.search(SANITIZER_CLANG,probe(['clang','--version'])),'sanitizer runner requires Clang 22.1.8 matching LDC LLVM 22')
    version=probe(['ldc2','--version'])
    require('(1.43.0)' in version and 'LLVM 22.1.8' in version,'sanitizer lane requires the pinned LDC 1.43.0 (LLVM 22.1.8)')
    require(verified_sanitizer_runtime(sanitizer_runtime_dir()),'LDC sanitizer runtime missing or changed: '+str(sanitizer_runtime_dir()))

def llvm_symbolizer():
    path=probe(['clang','-print-prog-name=llvm-symbolizer']).strip()
    if os.path.isabs(path) and os.access(path,os.X_OK):return path
    return shutil.which('llvm-symbolizer')

def preserve_native(target,sanitize=False,*,destination=None):
    root=ROOT/('.native-sanitized' if sanitize else '.native')
    destination=Path(destination) if destination else ROOT/'artifacts'/('native-sanitizers' if sanitize else 'native-'+target)
    rust_receipt=ROOT/'.tools/rust/flint-rust-install.json'
    if root.exists() or rust_receipt.is_file():
        destination.mkdir(parents=True,exist_ok=True)
        logs=root/'logs'/target
        if logs.is_dir():shutil.copytree(logs,destination/'logs',dirs_exist_ok=True)
        engine_logs=root/'engine-build/logs'/target
        if sanitize and engine_logs.is_dir():shutil.copytree(engine_logs,destination/'engine-logs',dirs_exist_ok=True)
        for receipt in (root/'install').rglob('flint-native-install.json'):
            shutil.copy2(receipt,destination/(receipt.parent.name+'-install.json'))
        if rust_receipt.is_file():shutil.copy2(rust_receipt,destination/'rust-toolchain-install.json')
        runtime_receipt=sanitizer_runtime_dir()/SANITIZER_RUNTIME_RECEIPT
        if sanitize and runtime_receipt.is_file():shutil.copy2(runtime_receipt,destination/SANITIZER_RUNTIME_RECEIPT)

def sanitizer_dflags():
    """The sanitize profile's flags (policy/profiles.toml), checked against the installed runtime's names."""
    flags=profiles.dflags('sanitize')
    require('-defaultlib='+SANITIZER_DEFAULTLIB in flags,'sanitize profile must link '+SANITIZER_DEFAULTLIB)
    # DUB splits DFLAGS on whitespace.
    require(all(' ' not in flag for flag in flags),'sanitize profile flags must not contain spaces')
    return flags

def run_tests(runner,compiler,*,sanitize=False):
    if not runner.plan:implementation_required()
    env=os.environ.copy()
    env.pop('DFLAGS',None)
    env['DUB_HOME']=str(ROOT/'.ci-dub-home'/('sanitized' if sanitize else 'normal')/Path(compiler).name)
    if sanitize:
        if not runner.plan:
            require(verified_sanitizer_runtime(sanitizer_runtime_dir()),'LDC sanitizer runtime missing or changed: '+str(sanitizer_runtime_dir()))
        # DUB splits DFLAGS on whitespace, so the runtime directory travels through
        # LIBRARY_PATH (honoured by the clang link driver) rather than -L-L.
        env['DFLAGS']=' '.join(sanitizer_dflags())
        env['LIBRARY_PATH']=os.pathsep.join([str(sanitizer_runtime_dir()/'lib'),*filter(None,[env.get('LIBRARY_PATH')])])
        # Stack-use-after-return keeps locals in ASan fake frames; only the sanitizer
        # runtime's GC scans them.
        env['ASAN_OPTIONS']='detect_leaks=1:abort_on_error=1:detect_stack_use_after_return=1'
        env['UBSAN_OPTIONS']='halt_on_error=1:print_stacktrace=1'
        symbolizer=None if runner.plan else llvm_symbolizer()
        if symbolizer:env['ASAN_SYMBOLIZER_PATH']=symbolizer
    build_type=profiles.load()['sanitize' if sanitize else 'test']['build_type']
    for name in PACKAGES:
        command=['dub','test',':'+name,'--compiler='+compiler,'--build='+build_type,'--force']
        package_env=env
        if name=='engine-desktop':
            # The ci closure builds the optional SDL canvas backend, whose pinned SDL has no Wayland
            # driver (ADR-020), so its suite runs on SDL's offscreen driver. The default WebKitGTK
            # backend is built by the desktop native profile and tested on a real display.
            # macOS has no EGL for SDL's offscreen driver; its headless driver is dummy. The WKWebView
            # backend is built there and opens real AppKit windows (ADR-024).
            package_env={**env,'SDL_VIDEODRIVER':'dummy' if sys.platform=='darwin' else 'offscreen'}
            if sanitize:
                # Software rendering without framebuffer acceleration never loads the host's
                # uninstrumented EGL drivers, whose one-time internal allocations LeakSanitizer
                # reports after SDL unloads them; no leak suppressions are used.
                package_env.update({'SDL_RENDER_DRIVER':'software','SDL_FRAMEBUFFER_ACCELERATION':'0'})
        runner.run(command,env=package_env)

def negative_tests(runner,compiler):
    imports=import_flags()
    fixtures=ROOT/'tests/compile'
    for filename in ('positive.d','reactor_protocol.d'):
        positive=fixtures/filename
        if not runner.plan:require(positive.is_file(),'positive scope/@nogc compile fixture missing: '+filename)
        runner.run([compiler,'-c','-o-','-preview=dip1000',*imports,positive])
    negatives=[('escape_borrow.d',r'(?i)scope|escap'),('escape_storage.d',r'(?i)scope|escap|local'),
               ('forge_buffer.d',r'(?i)private|accessible|constructor'),('gc_in_hot_path.d',r'@nogc'),
               ('reactor_read_retained.d',r'(?i)(scope variable|escapes the scope|scope parameter)')]
    out=ROOT/'artifacts/compile-negative'/Path(compiler).name
    if not runner.plan:out.mkdir(parents=True,exist_ok=True)
    for filename,pattern in negatives:
        source=fixtures/filename
        command=[compiler,'-c','-o-','-preview=dip1000',*imports,str(source)]
        if runner.plan:runner.run(command);continue
        require(source.is_file(),'negative compile fixture missing: '+filename)
        result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
        output=result.stdout+result.stderr
        (out/(filename+'.log')).write_text(output)
        require(result.returncode>0 and result.returncode<128 and re.search(pattern,output),
                filename+': expected specific compiler rejection, got '+str(result.returncode)+'\n'+output)
        require(not re.search(r'(?i)internal compiler error|segmentation fault|access violation',output),
                filename+': compiler crash is not a safety pass')
        print(json.dumps({'negative_fixture':filename,'compiler':compiler,'expected_rejection':True}),flush=True)

def betterc(runner,compiler='ldc2'):
    if not runner.plan:implementation_required()
    directory=ROOT/'artifacts/betterc'/Path(compiler).name
    if not runner.plan:directory.mkdir(parents=True,exist_ok=True)
    for name,meta in PACKAGES.items():
        if not meta['better_c']:continue
        fixture=package_source(name).parent/'tests/betterc.d'
        if not runner.plan:require(fixture.is_file(),'BetterC runtime fixture missing: '+name)
        executable=directory/(name+('.exe' if sys.platform=='win32' else ''))
        runner.run([compiler,'-betterC','-preview=dip1000','-i=flint',*import_flags(),fixture,'-of='+str(executable)])
        runner.run([executable])

def wasm_betterc(runner):
    directory=ROOT/'artifacts/wasm-betterc'
    if not runner.plan:directory.mkdir(parents=True,exist_ok=True)
    for name,meta in PACKAGES.items():
        if not meta['better_c']:continue
        fixture=package_source(name).parent/'tests/betterc.d'
        if not runner.plan:require(fixture.is_file(),'WASM BetterC fixture missing: '+name)
        output=directory/(name+'.wasm')
        runner.run(['ldc2','-betterC','-preview=dip1000','-mtriple=wasm32-unknown-unknown-wasm',
                    '-mattr=+bulk-memory','-checkaction=halt','-boundscheck=on','-i=flint',
                    '-link-internally','-L--no-entry','-L--export=flint_test','-L--export-memory',
                    *import_flags(),fixture,'-of='+str(output)])
        runner.run(['node','tests/wasm/betterc.mjs',output])

def repo_suites():
    """Every repo's own suites, which the flint repo's tooling runs (coordinator's decision 3): tests/<repo>/ in
    the monorepo, or each checkout's tests/ of the workspace FLINT_WORKSPACE names."""
    sys.path.insert(0,str(ROOT/'tools'))
    import workspace
    named=os.environ.get('FLINT_WORKSPACE')
    if named:
        pinned=workspace.Workspace(named)
        return [(repo,path/'tests') for repo,(path,_) in sorted(pinned.checkouts.items())
                if repo!='flint' and (path/'tests').is_dir()]
    repos=workspace.repo_policy(ROOT)['repos']
    return [(repo,ROOT/'tests'/repo) for repo in sorted(repos) if repo!='flint' and (ROOT/'tests'/repo).is_dir()]

def check(runner,gate):
    if not runner.plan:implementation_required()
    if gate=='quality':
        runner.run([PYTHON,'tools/quality.py'])
        runner.run([PYTHON,'-m','unittest','discover','-s','tests','-p','test_*.py'])
        for _,suites in repo_suites():
            runner.run([PYTHON,'-m','unittest','discover','-s',suites,'-p','test_*.py'],
                       env=dict(os.environ,FLINT_ROOT=str(ROOT)))
        runner.run([PYTHON,'tools/test_guards.py'])
    elif gate=='dag':runner.run([PYTHON,'tools/gates.py','--gate','structural'])
    elif gate=='api':
        # ADR-030 section 8: ported-file headers always pass, and API coverage only ratchets up.
        runner.run([PYTHON,'tools/install_toolchains.py','--compiler','flint'])
        runner.run([PYTHON,'tools/gates.py','--gate','api'])
    elif gate=='safety':
        runner.run([PYTHON,'tools/gates.py','--gate','structural'])
        negative_tests(runner,'dmd');negative_tests(runner,'ldc2')
        run_tests(runner,'dmd')
    elif gate=='betterc':
        betterc(runner,'dmd');betterc(runner,'ldc2')
    elif gate=='sanitizers':
        if not runner.plan:
            require(native_target()=='linux-x86_64-glibc','sanitizer lane requires the approved Linux x86-64 runner')
        sanitizer_toolchain(runner)
        try:
            native(runner,'linux-x86_64-glibc',sanitize=True)
            run_tests(runner,'ldc2',sanitize=True)
        finally:
            if not runner.plan:preserve_native('linux-x86_64-glibc',sanitize=True)
    else:raise ValueError('unknown gate '+gate)

def receipt(runner,name,command,*,platform_name=None):
    directory=Path('artifacts/platforms' if platform_name else 'artifacts/receipts')
    stem=platform_name or name
    argv=[PYTHON,'tools/collect_evidence.py','record','--name',name,
          '--output',str(directory/(stem+'.json')),'--artifact',str(directory/(stem+'.log'))]
    if platform_name:argv+=['--platform',platform_name]
    runner.run([*argv,'--',*command])

def static(runner):
    for gate in ('quality','dag','api'):
        receipt(runner,gate,[PYTHON,'tools/ci.py','check','--gate',gate])
    try:
        native(runner,'linux-x86_64-glibc')
        for gate in ('safety','betterc'):
            receipt(runner,gate,[PYTHON,'tools/ci.py','check','--gate',gate])
    finally:
        if not runner.plan:preserve_native('linux-x86_64-glibc')

def peer_tests(runner):
    """Run the packages policy/test-peers.toml gives fixture peers through flint test, which wraps each
    package's unittests in its pinned peers on both compilers and fails when a peer is missing (ADR-024)."""
    import tomllib
    peered=sorted(tomllib.loads((ROOT/'policy/test-peers.toml').read_text())['packages'])
    runner.run([PYTHON,'tools/install_toolchains.py','--compiler','flint'])
    runner.run([PYTHON,'tools/install_peers.py','--peer','go','--peer','postgres','--peer','valkey','--peer','minio',
                '--peer','nats','--peer','kafka','--peer','jre'])
    runner.run([ROOT/'.flint/bin/flint','test',*peered,'--compiler','both','--verify'])
    # The declared live scenarios: mq against a real Kafka on the pinned JRE and NATS JetStream, plain and TLS.
    scenarios=sorted(tomllib.loads((ROOT/'policy/test-peers.toml').read_text()).get('scenarios',{}))
    runner.run([ROOT/'.flint/bin/flint','test',*scenarios,'--scenarios','--verify'])

def platform_run(runner,target):
    if not runner.plan:implementation_required()
    if target=='wasm32':
        wasm_betterc(runner)
        runner.run([PYTHON,'benchmarks/bench-wasm/build.py','--ldc','ldc2','--profile','Oz','--output','build/bench-wasm.wasm'])
        runner.run(['node','tests/wasm/run.mjs','build/bench-wasm.wasm'])
        return
    # macOS runs the forked DMD's AArch64 code generator in the DMD role (ADR-025 section 3, stage 2), and LDC.
    compilers=(str(ROOT/'.tools/dmd2/osx/bin64/dmd'),'ldc2') if target=='macos-arm64' else ('ldc2',)
    try:
        native(runner,target)
        for compiler in compilers:run_tests(runner,compiler)
        if target=='macos-arm64':peer_tests(runner)
        for compiler in compilers:negative_tests(runner,compiler)
        for compiler in compilers:betterc(runner,compiler)
        if target.endswith('-musl'):
            runner.run([PYTHON,'tools/static_smoke.py','--target',target,'--output','artifacts/static-'+target])
    finally:
        if not runner.plan:preserve_native(target)

def run_container(runner,target):
    require(target in ('linux-x86_64-musl','linux-aarch64-musl'),'container lane is only for musl targets')
    lock=json.loads((ROOT/'policy/toolchains.json').read_text())
    image=lock['containers']['alpine-musl']['image']
    require(re.fullmatch(r'docker\.io/library/alpine:[\w.]+@sha256:[0-9a-f]{64}',image),'Alpine image must have an immutable digest')
    mounts=['--mount','type=bind,source='+str(ROOT)+',target=/work']
    # A git worktree's .git file points into the main repository's git directory; mount that
    # read-only at the same path so the tools inside the container can read the commit.
    common=Path(probe(['git','-C',str(ROOT),'rev-parse','--path-format=absolute','--git-common-dir']).strip() or ROOT/'.git')
    if not common.is_relative_to(ROOT):
        mounts+=['--mount','type=bind,source='+str(common)+',target='+str(common)+',readonly']
    # Docker's default seccomp profile denies io_uring_setup. The reactor falls back to epoll when
    # that happens, and a dedicated test covers the denial, but this lane must exercise real io_uring
    # on musl, so the disposable test container runs without that filter.
    runner.run(['docker','run','--rm','--security-opt','seccomp=unconfined',*mounts,
                '--workdir','/work','--env','FLINT_TARGET='+target,image,
                'sh','.github/scripts/musl.sh'])

def perf(runner,args):
    if not runner.plan:
        implementation_required()
        require(native_target()=='linux-x86_64-glibc','performance requires Linux x86-64 glibc')
        require(os.environ.get('FLINT_RUNNER_LABEL')=='flint-perf-x86_64-v1','performance requires the approved runner label')
        # ADR-017 decision 1: the designated runner states whether it is a single-job ephemeral image;
        # the evidence records the answer instead of assuming it.
        require(os.environ.get('FLINT_EPHEMERAL_RUNNER') in ('0','1'),'runner must attest FLINT_EPHEMERAL_RUNNER=1 (single-job ephemeral) or 0')
        for name in ('micro','hot-gc'):
            require((ROOT/'benchmarks'/name/'dub.sdl').is_file(),name+' producer missing; implement REQUIRED_PRODUCERS.md')
    directory=args.artifacts.resolve()
    output=args.output.resolve()
    if not runner.plan:directory.mkdir(parents=True,exist_ok=True)
    try:native(runner,'linux-x86_64-glibc')
    finally:
        if not runner.plan:preserve_native('linux-x86_64-glibc',destination=directory/'native')
    runner.run([PYTHON,'tools/measure_builds.py','--manifest','policy/build-benchmarks.json','--output',directory/'builds.json'])
    runner.run([PYTHON,'tools/load_bench.py','--manifest','policy/http-benchmark.json','--output',directory/'http-load.json','--oha',args.oha])
    for kind,fixture in (('micro','micro'),('gc','hot-gc')):
        runner.run([PYTHON,'tools/collect_evidence.py','capture-json','--kind',kind,'--output',directory/(kind+'.json'),'--',
                    'dub','run','--quiet','--root=benchmarks/'+fixture,'--compiler=ldc2','--build=release'])
    runner.run([PYTHON,'tools/collect_evidence.py','collect','--builds',directory/'builds.json',
                '--http',directory/'http-load.json','--micro',directory/'micro.json','--gc',directory/'gc.json',
                '--receipts-dir',args.receipts.resolve(),'--platform-receipts-dir',args.platforms.resolve(),
                '--dependency-lock','policy/native-lock.json','--output',output,'--runner-label','flint-perf-x86_64-v1',
                '--runner-ephemeral',os.environ.get('FLINT_EPHEMERAL_RUNNER','1')])

def pair(runner,args):
    base=args.base.resolve();candidate=args.candidate.resolve();out=args.output.resolve();evidence=args.evidence.resolve()
    if not runner.plan:
        require(base!=candidate,'base and candidate must be separate checkouts')
        require(git_head(base)!=git_head(candidate),'base must identify a different real commit')
        for name in ('native-lock.json','toolchains.json','http-benchmark.json','build-benchmarks.json'):
            require(digest(base/'policy'/name)==digest(candidate/'policy'/name),name+' changed; regenerate a real baseline under the new environment before comparing')
        for root in (base,candidate):
            for name in ('ci.py','measure_builds.py','load_bench.py','collect_evidence.py'):
                require((root/'tools'/name).is_file(),'initial baseline blocked: '+str(root/'tools'/name)+' is absent')
        out.mkdir(parents=True,exist_ok=True)
    for label,root in (('base',base),('candidate',candidate)):
        runner.run([PYTHON,root/'tools/ci.py','performance','--artifacts',out/label,
                    '--receipts',evidence/label/'receipts','--platforms',evidence/label/'platforms',
                    '--output',out/(label+'.json'),'--oha',Path(args.oha).resolve()],cwd=root)
    runner.run([PYTHON,candidate/'tools/gates.py','--gate','all','--evidence',out/'candidate.json','--baseline',out/'base.json'],cwd=candidate)

def baseline_environment():
    repository=os.environ.get('GITHUB_REPOSITORY','')
    require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repository),'missing repository identity')
    value=json.loads(subprocess.check_output(['gh','api','-H','X-GitHub-Api-Version: 2026-03-10',
        'repos/'+repository+'/environments/flint-baseline'],text=True))
    reviewers=[rule for rule in value.get('protection_rules',[]) if rule.get('type')=='required_reviewers']
    require(len(reviewers)==1 and reviewers[0].get('reviewers') and reviewers[0].get('prevent_self_review') is True,
            'flint-baseline must have required reviewers and prevent self-review')
    require(value.get('deployment_branch_policy',{}).get('protected_branches') is True,
            'flint-baseline must be restricted to protected branches')

def refs(args):
    event=json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    kind=os.environ.get('GITHUB_EVENT_NAME','')
    mode=event.get('inputs',{}).get('mode','compare') if kind=='workflow_dispatch' else 'compare'
    require(mode in ('compare','baseline'),'unknown workflow mode')
    if kind=='pull_request':
        # GitHub attaches the required check to this exact tested merge commit.
        base=event['pull_request']['base']['sha'];candidate=os.environ.get('GITHUB_SHA','')
    elif kind=='workflow_dispatch':
        base=event.get('inputs',{}).get('base_sha','');candidate=os.environ.get('GITHUB_SHA','')
    elif kind=='push':
        base=event.get('before','');candidate=event.get('after','')
    else:raise ValueError('unsupported CI event '+kind)
    if mode=='baseline':
        default=event.get('repository',{}).get('default_branch')
        require(default and os.environ.get('GITHUB_REF')=='refs/heads/'+default,
                'baseline validation requires an owner dispatch from the default branch')
        baseline_environment()
        base=''
    for label,value in ([('candidate',candidate)] if mode=='baseline' else [('base',base),('candidate',candidate)]):
        require(re.fullmatch(r'[a-f0-9]{40}|[a-f0-9]{64}',value) and set(value)!={'0'},
                label+' commit missing; initial baseline is blocked until a real measured base exists')
    require(mode=='baseline' or base!=candidate,'base and candidate commit identities must differ')
    roles=['candidate'] if mode=='baseline' else ['base','candidate']
    print(json.dumps({'base':base,'candidate':candidate,'mode':mode,'roles':roles}))
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'],'a') as output:
            output.write('base='+base+'\ncandidate='+candidate+'\nmode='+mode+'\nroles='+json.dumps(roles)+'\n')

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan',action='store_true',help='Print commands only; not verification evidence.')
    sub=parser.add_subparsers(dest='action',required=True)
    sub.add_parser('refs')
    sub.add_parser('windows-tools')
    command=sub.add_parser('check');command.add_argument('--gate',choices=(*STATIC,'sanitizers'),required=True)
    sub.add_parser('static')
    sub.add_parser('sanitizers')
    for action in ('platform','platform-run','container'):
        command=sub.add_parser(action);command.add_argument('--target',choices=PLATFORMS,required=True)
    for action in ('performance','baseline'):
        command=sub.add_parser(action)
        for name in ('artifacts','receipts','platforms','output'):
            command.add_argument('--'+name,type=Path,required=True)
        command.add_argument('--oha',required=True)
    command=sub.add_parser('pair')
    for name in ('base','candidate','evidence','output'):
        command.add_argument('--'+name,type=Path,required=True)
    command.add_argument('--oha',required=True)
    args=parser.parse_args(argv);runner=Runner(args.plan)
    if args.action=='refs':refs(args)
    elif args.action=='windows-tools':windows_tools(runner)
    elif args.action=='check':check(runner,args.gate)
    elif args.action=='static':static(runner)
    elif args.action=='sanitizers':receipt(runner,'sanitizers',[PYTHON,'tools/ci.py','check','--gate','sanitizers'])
    elif args.action=='platform':receipt(runner,'platform',[PYTHON,'tools/ci.py','platform-run','--target',args.target],platform_name=args.target)
    elif args.action=='platform-run':platform_run(runner,args.target)
    elif args.action=='container':run_container(runner,args.target)
    elif args.action=='performance':perf(runner,args)
    elif args.action=='baseline':
        perf(runner,args)
        runner.run([PYTHON,'tools/gates.py','--gate','baseline','--evidence',args.output.resolve()])
    elif args.action=='pair':pair(runner,args)
    return 0

if __name__=='__main__':
    try:raise SystemExit(main())
    except (ValueError,KeyError,OSError,subprocess.SubprocessError) as error:
        print('CI BLOCKED:',error,file=sys.stderr);raise SystemExit(1)
