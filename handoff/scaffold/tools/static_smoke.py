#!/usr/bin/env python3
"""Build, audit, and execute canonical musl binaries without shared libraries."""
from __future__ import annotations
import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
MACHINES={'linux-x86_64-musl':62,'linux-aarch64-musl':183}
PROFILES={'O3':'-O3','Oz':'-Oz'}

def require(value,message):
    if not value:raise ValueError(message)

def digest(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def inspect_elf(data,expected_machine):
    """Audit ELF bytes independently of human-readable readelf formatting."""
    require(len(data)>=64 and data[:4]==b'\x7fELF','not an ELF executable')
    require(data[4:7]==b'\x02\x01\x01','requires current ELF64 little-endian encoding')
    fields=struct.unpack_from('<16sHHIQQQIHHHHHH',data)
    _,kind,machine,version,entry,phoff,_,_,ehsize,phsize,phnum,_,_,_=fields
    require(kind in (2,3) and version==1 and entry!=0,'not a canonical executable ELF')
    require(machine==expected_machine,'ELF machine differs from target architecture')
    require(ehsize==64 and phsize==56 and 0<phnum<65535,'unsupported ELF program-header table')
    require(phoff>=64 and phoff+phsize*phnum<=len(data),'ELF program-header table is out of bounds')
    dynamic_segments=0
    for index in range(phnum):
        ptype,_,offset,_,_,filesz,memsz,_=struct.unpack_from('<IIQQQQQQ',data,phoff+index*phsize)
        require(offset+filesz<=len(data),'ELF segment exceeds file bounds')
        require(ptype!=3,'PT_INTERP present: executable requires a dynamic interpreter')
        if ptype!=2:continue
        dynamic_segments+=1
        require(filesz>0 and filesz%16==0 and memsz>=filesz,'malformed ELF dynamic segment')
        terminated=False
        for position in range(offset,offset+filesz,16):
            tag,_=struct.unpack_from('<qQ',data,position)
            require(tag!=1,'DT_NEEDED present: executable requires a shared library')
            if tag==0:
                terminated=True;break
        require(terminated,'ELF dynamic segment has no DT_NULL terminator')
    return {'machine':machine,'elf_type':kind,'program_headers':phnum,
            'dynamic_segments':dynamic_segments,'has_interpreter':False,'needed_libraries':[]}

def execute(command,cwd,log,env=None,timeout=1800):
    result=subprocess.run([str(x) for x in command],cwd=cwd,env=env,capture_output=True,timeout=timeout)
    log.parent.mkdir(parents=True,exist_ok=True)
    log.write_bytes(result.stdout+b'\n--- stderr ---\n'+result.stderr)
    require(result.returncode==0,'command failed: '+str(command)+'; inspect '+str(log))
    return {'command':[str(x) for x in command],'exit_code':result.returncode,
            'artifact':str(log),'sha256':digest(log)}

def audit_binary(binary,target,output):
    require(binary.is_file() and binary.stat().st_size<256*1024*1024,'missing/oversized canonical executable')
    receipt=execute(['readelf','--wide','--file-header','--program-headers','--dynamic',binary],
                    ROOT,output)
    inspection=inspect_elf(binary.read_bytes(),MACHINES[target])
    return {**inspection,'binary_sha256':digest(binary),'bytes':binary.stat().st_size,'readelf':receipt}

def minimal_environment():
    # Do not carry host loader/preload/library-path or application secrets in.
    return {'LANG':'C','LC_ALL':'C','TZ':'UTC'}

def chroot_command(root,program,*arguments):
    executable=shutil.which('chroot')
    require(executable,'chroot utility is required for the empty-root proof')
    return [executable,str(root),'/'+program,*arguments]

def cli_smoke(binary,output):
    with tempfile.TemporaryDirectory(prefix='flint-static-cli-') as temporary:
        root=Path(temporary)
        shutil.copy2(binary,root/'bench-cli')
        shutil.copy2(ROOT/'benchmarks/bench-cli/application.json',root/'application.json')
        (root/'tmp').mkdir()
        command=chroot_command(root,'bench-cli','--name','Flint')
        completed=subprocess.run(command,cwd=ROOT,env=minimal_environment(),capture_output=True,timeout=15)
        output.write_bytes(completed.stdout+b'\n--- stderr ---\n'+completed.stderr)
        require(completed.returncode==0,'static CLI failed in empty root; inspect '+str(output))
        require(b'Hello, Flint!' in completed.stdout.splitlines(),'static CLI did not execute the config/CLI/log workload')
        return {'command':command,'exit_code':completed.returncode,'artifact':str(output),
                'sha256':digest(output),'root_files':['bench-cli','application.json'],
                'empty_directories':['tmp'],'shared_library_files':0}

def request(port,path,expected_type,expected_body):
    connection=http.client.HTTPConnection('127.0.0.1',port,timeout=2)
    try:
        connection.request('GET',path)
        response=connection.getresponse()
        body=response.read(len(expected_body)+1)
        require(response.status==200,'static REST returned wrong status')
        require((response.getheader('Content-Type') or '').split(';',1)[0].strip()==expected_type,
                'static REST returned wrong Content-Type')
        require(body==expected_body,'static REST returned wrong bytes for '+path)
    finally:connection.close()

def stop(process):
    if process.poll() is not None:return
    os.killpg(process.pid,signal.SIGTERM)
    try:process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=5)

def rest_smoke(binary,output):
    with tempfile.TemporaryDirectory(prefix='flint-static-rest-') as temporary:
        root=Path(temporary);shutil.copy2(binary,root/'bench-rest');(root/'tmp').mkdir()
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1',0));port=reservation.getsockname()[1]
        command=chroot_command(root,'bench-rest','--listen','127.0.0.1:'+str(port))
        with output.open('wb') as log:
            process=subprocess.Popen(command,cwd=ROOT,env=minimal_environment(),stdout=log,stderr=log,start_new_session=True)
            try:
                deadline=time.monotonic()+15
                while True:
                    require(process.poll() is None,'static REST exited before readiness; inspect '+str(output))
                    try:request(port,'/health','text/plain',b'ok\n');break
                    except (OSError,http.client.HTTPException,ValueError):
                        require(time.monotonic()<deadline,'static REST readiness deadline expired')
                        time.sleep(.05)
                for _ in range(5):
                    request(port,'/json','application/json',b'{"message":"hello","n":42}')
                    request(port,'/health','text/plain',b'ok\n')
                require(process.poll() is None,'static REST exited during correctness requests')
            finally:stop(process)
        return {'command':command,'correctness_requests':11,'status':'passed',
                'artifact':str(output),'sha256':digest(output),'root_files':['bench-rest'],
                'empty_directories':['tmp'],'shared_library_files':0,'cleanup_exit_code':process.returncode}

def run(args):
    from native_build import host_target
    require(sys.platform=='linux' and os.geteuid()==0,'empty-root smoke requires root inside the disposable Linux container')
    require(host_target()==args.target,'static proof must execute on the actual musl target, not a glibc host or emulator')
    for utility in ('dub','ldc2','strip','readelf','chroot'):
        require(shutil.which(utility),'missing static-lane tool: '+utility)
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    caps=json.loads((ROOT/'policy/budgets.json').read_text())['benchmark_apps']
    result={'schema':1,'target':args.target,'scope':'native static compatibility and size ceilings; not a performance comparison',
            'profiles':{},'status':'running'}
    try:
        for profile,optimization in PROFILES.items():
            directory=output/profile;directory.mkdir(exist_ok=True)
            rows={};result['profiles'][profile]=rows
            for name in ('bench-cli','bench-rest'):
                env=os.environ.copy()
                env['DUB_HOME']=str(ROOT/'.ci-dub-home/static'/args.target/profile)
                env['DFLAGS']=' '.join([optimization,'-release','-boundscheck=on','-preview=dip1000',
                                      '-link-defaultlib-shared=false','-static'])
                build=execute(['dub','build','--root=benchmarks/'+name,'--compiler=ldc2','--build=plain','--force'],
                              ROOT,directory/(name+'-build.log'),env)
                build['dflags']=env['DFLAGS'];build['dub_home']=env['DUB_HOME']
                binary=directory/name
                require((ROOT/'build'/name).is_file(),'DUB did not publish the expected canonical executable: '+name)
                shutil.copy2(ROOT/'build'/name,binary)
                strip_receipt=execute(['strip','--strip-unneeded',binary],ROOT,directory/(name+'-strip.log'))
                audit=audit_binary(binary,args.target,directory/(name+'-readelf.log'))
                require(0<audit['bytes']<caps[name]['binary_bytes'],name+' static '+profile+' binary exceeds the absolute size ceiling')
                smoke=(cli_smoke if name=='bench-cli' else rest_smoke)(binary,directory/(name+'-smoke.log'))
                rows[name]={'build':build,'strip':strip_receipt,'audit':audit,'empty_root_execution':smoke}
        result['status']='passed'
    except Exception as error:
        result['status']='failed';result['error']=str(error);raise
    finally:
        (output/'static-proof.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'target':args.target,'static_proof':str(output/'static-proof.json'),'status':'passed'}))

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target',choices=sorted(MACHINES),required=True)
    parser.add_argument('--output',type=Path,required=True)
    run(parser.parse_args(argv))

if __name__=='__main__':
    try:main()
    except (ValueError,OSError,subprocess.SubprocessError) as error:
        print('STATIC MUSL PROOF FAILED:',error,file=sys.stderr);raise SystemExit(1)
