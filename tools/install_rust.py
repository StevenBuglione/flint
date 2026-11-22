#!/usr/bin/env python3
"""Install the pinned native Rust host toolchain in project-private directories."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
TRIPLES={
    'linux-x86_64-glibc':'x86_64-unknown-linux-gnu',
    'linux-aarch64-glibc':'aarch64-unknown-linux-gnu',
    'linux-x86_64-musl':'x86_64-unknown-linux-musl',
    'linux-aarch64-musl':'aarch64-unknown-linux-musl',
    'macos-arm64':'aarch64-apple-darwin',
    'windows-x86_64':'x86_64-pc-windows-msvc',
}

def require(value,message):
    if not value:raise ValueError(message)

def digest(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def environment(prefix,version):
    prefix=Path(prefix).resolve();env=os.environ.copy()
    for key in ('RUSTFLAGS','CARGO_ENCODED_RUSTFLAGS','CARGO_TARGET_DIR','RUSTC','RUSTC_WRAPPER','RUSTC_WORKSPACE_WRAPPER'):
        env.pop(key,None)
    env.update(RUSTUP_HOME=str(prefix/'rustup'),CARGO_HOME=str(prefix/'cargo'),
               RUSTUP_TOOLCHAIN=version,RUSTUP_DIST_SERVER='https://static.rust-lang.org',
               RUSTUP_UPDATE_ROOT='https://static.rust-lang.org/rustup')
    env['PATH']=str(prefix/'cargo/bin')+os.pathsep+env.get('PATH','')
    return env

def download(url,expected,destination):
    require(url.startswith('https://static.rust-lang.org/'),'Rust downloads require the official distribution origin')
    require(re.fullmatch('[0-9a-f]{64}',expected),'missing pinned Rust asset SHA256')
    destination=Path(destination);destination.parent.mkdir(parents=True,exist_ok=True)
    if destination.is_file() and digest(destination)==expected:return
    temporary=destination.with_suffix(destination.suffix+'.part')
    try:
        with urllib.request.urlopen(url,timeout=90) as source,temporary.open('wb') as output:
            shutil.copyfileobj(source,output)
        require(digest(temporary)==expected,'Rust asset checksum mismatch: '+url)
        temporary.replace(destination)
    finally:
        if temporary.exists():temporary.unlink()

def install(target,prefix):
    from native_build import host_target
    require(host_target()==target,'Rust installation requires the actual native target host')
    lock=json.loads((ROOT/'policy/toolchains.json').read_text())
    version=lock['versions']['rust'];rustup_version=lock['versions']['rustup'];triple=TRIPLES[target]
    require(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',version),'Rust toolchain must be an exact stable version')
    prefix=Path(prefix).resolve();prefix.mkdir(parents=True,exist_ok=True)
    env=environment(prefix,version);suffix='.exe' if target.startswith('windows') else ''
    manifest=prefix/'bootstrap/channel-rust.toml';asset=lock['rust']['bootstrap'][triple]
    require(lock['rust']['hosts'][triple]['available'] is True,'official Rust host toolchain is unavailable')
    download(lock['rust']['manifest_url'],lock['rust']['manifest_sha256'],manifest)
    bootstrap=prefix/('bootstrap/rustup-init'+suffix)
    download(asset['url'],asset['sha256'],bootstrap)
    if os.name!='nt':bootstrap.chmod(0o755)
    commands=[]
    def run(command):
        command=[str(x) for x in command];commands.append(command)
        subprocess.run(command,cwd=ROOT,env=env,check=True)
    run([bootstrap,'-y','--no-modify-path','--profile','minimal','--default-toolchain',version,'--default-host',triple])
    rustup=prefix/('cargo/bin/rustup'+suffix)
    run([rustup,'set','auto-self-update','disable'])
    run([rustup,'toolchain','install',version,'--profile','minimal','--target',triple])
    rustc=prefix/('cargo/bin/rustc'+suffix);cargo=prefix/('cargo/bin/cargo'+suffix)
    rustup_text=subprocess.check_output([str(rustup),'--version'],env=env,text=True)
    rustc_text=subprocess.check_output([str(rustc),'--version','--verbose'],env=env,text=True)
    cargo_text=subprocess.check_output([str(cargo),'--version'],env=env,text=True)
    require(rustup_text.startswith('rustup '+rustup_version+' '),'installed Rustup identity differs from the pin')
    require(re.search(r'^release: '+re.escape(version)+r'$',rustc_text,re.M),'installed rustc release differs from the pin')
    require(re.search(r'^host: '+re.escape(triple)+r'$',rustc_text,re.M),'installed rustc host differs from target')
    require(cargo_text.startswith('cargo '+version+' '),'installed Cargo version differs from the pin')
    # Keep the upstream manifest identity alongside actual executable/tool output.
    require(digest(manifest)==lock['rust']['manifest_sha256'],'retained Rust distribution manifest changed')
    receipt={'schema':1,'target':target,'host':triple,'rust_version':version,'rustup_version':rustup_version,
             'manifest_sha256':digest(manifest),'bootstrap_sha256':digest(bootstrap),'commands':commands,
             'rustup_version_output':rustup_text,'rustc_version_output':rustc_text,'cargo_version_output':cargo_text,
             'environment':{key:env[key] for key in ('RUSTUP_HOME','CARGO_HOME','RUSTUP_TOOLCHAIN')},
             'status':'installed','verification':'Pinned bootstrap bytes and distribution manifest verified; Rustup verifies downloaded component checksums.'}
    (prefix/'flint-rust-install.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'target':target,'rust':version,'rustup':rustup_version,'receipt':str(prefix/'flint-rust-install.json')}))

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target',choices=sorted(TRIPLES),required=True)
    parser.add_argument('--destination',type=Path,default=ROOT/'.tools/rust')
    args=parser.parse_args(argv);install(args.target,args.destination)

if __name__=='__main__':
    try:main()
    except (ValueError,KeyError,OSError,subprocess.SubprocessError) as error:
        print('RUST TOOLCHAIN INSTALLATION FAILED:',error,file=sys.stderr);raise SystemExit(1)
