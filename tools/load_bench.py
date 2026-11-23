#!/usr/bin/env python3
"""Collect real, paired Linux HTTP measurements using pinned oha, fail closed.

Schema-1 manifests (policy/http-benchmark.json) measure the 26-byte JSON workload; schema-2 manifests
(policy/spring-http-benchmark.json) measure the Spring-style REST workload of benchmarks/spring (ADR-030 section 8).
"""
from __future__ import annotations
import argparse
import contextlib
import hashlib
import http.client
import json
import math
import os
from pathlib import Path
import re as _re
import resource
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
OHA_VERSION = "oha 1.16.0"
OHA_SHA256 = "620bb9e16fb53eabc9a3fc45f88bdb41fefa3fee5c05e75892011ce320391716"
FIELDS = ["p50_ms","p99_ms","p999_ms","peak_rss_bytes","cpu_ns_per_request","requests_per_second"]

def require(condition, message):
    if not condition:
        raise ValueError(message)

def file_hash(path):
    digest=hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda:stream.read(1024*1024),b""):
            digest.update(block)
    return digest.hexdigest()

def positive_number(value, name):
    require(isinstance(value,(int,float)) and not isinstance(value,bool)
            and math.isfinite(value) and value>0, name+" must be positive and finite")
    return value

def parse_oha(payload, expected_status, expected_body_bytes):
    summary=payload["summary"]
    status=payload["statusCodeDistribution"]
    errors=payload["errorDistribution"]
    require(isinstance(status,dict) and set(status)=={str(expected_status)},
            "unexpected HTTP statuses in oha result")
    count=status[str(expected_status)]
    require(isinstance(count,int) and not isinstance(count,bool) and count>0,
            "missing successful request count")
    require(isinstance(errors,dict) and all(isinstance(v,int) and not isinstance(v,bool) and v==0 for v in errors.values()),
            "oha reported transport errors or deadline-aborted requests")
    require(summary["successRate"]==1, "oha success rate is not 100%")
    require(summary["totalData"]==count*expected_body_bytes, "body byte total differs from contract")
    require(summary["sizePerRequest"]==expected_body_bytes, "body size differs from contract")
    latency=payload["latencyPercentiles"]
    p50=positive_number(latency["p50"],"p50")*1000
    p99=positive_number(latency["p99"],"p99")*1000
    p999=positive_number(latency["p99.9"],"p99.9")*1000
    require(p50<=p99<=p999, "latency percentiles are not monotonic")
    return {
        "count":count,
        "duration_seconds":positive_number(summary["total"],"total duration"),
        "requests_per_second":positive_number(summary["requestsPerSec"],"requests/second"),
        "p50_ms":p50,"p99_ms":p99,"p999_ms":p999,
    }

def cpu_list(text):
    values=set()
    for item in text.strip().split(","):
        if not item:continue
        if "-" in item:
            a,b=map(int,item.split("-"));values.update(range(a,b+1))
        else:values.add(int(item))
    return values

def validate_manifest(m, smoke):
    require(m.get("schema")==1,"HTTP manifest schema must be 1")
    require(set(m["targets"])=={"flint","go"},"manifest requires exactly flint and go targets")
    w=m["workload"]
    if not smoke:
        require(w["runs"]==9 and w["duration_seconds"]>=60 and w["capacity_seconds"]>=60
                and w["warmup_seconds"]>=10,"production requires 9 trials, >=60s phases, >=10s warmup")
    for key in ["runs","duration_seconds","capacity_seconds","warmup_seconds","fixed_rate_qps","connections","request_timeout_seconds"]:
        positive_number(w[key],key)
    for key in ["runs","connections"]:
        require(isinstance(w[key],int) and not isinstance(w[key],bool),key+" must be integer")
    server=set(w["server_cpus"]);load=set(w["load_cpus"])
    require(server and load and server.isdisjoint(load),"server/load CPU sets must be nonempty and disjoint")
    require(all(isinstance(v,int) and not isinstance(v,bool) and v>=0 for v in server|load),"CPU IDs must be nonnegative integers")
    allowed=os.sched_getaffinity(0)
    require(server|load<=allowed,"configured CPUs are not in runner cpuset")
    if not smoke:
        for core in server:
            siblings=Path(f"/sys/devices/system/cpu/cpu{core}/topology/thread_siblings_list")
            require(siblings.is_file(),"missing CPU topology; cannot verify physical separation")
            require(not (cpu_list(siblings.read_text())&load),"server/load CPUs share an SMT core")
    expected=m["expected"]
    require(expected["status"]==200 and isinstance(expected["body"],str),"expected response must have status200 and exact text body")
    require(expected["body"] and expected["content_type"]=="application/json","canonical JSON workload required")
    json.loads(expected["body"])
    urls=set()
    for name,target in m["targets"].items():
        require(isinstance(target["command"],list) and target["command"] and all(isinstance(v,str) for v in target["command"]),
                name+" command must be nonempty argv")
        require(isinstance(target.get("environment",{}),dict) and
                all(isinstance(k,str) and isinstance(v,str) for k,v in target.get("environment",{}).items()),
                name+" environment must map strings to strings")
        url=urlsplit(target["url"])
        require(url.scheme=="http" and url.hostname in ("127.0.0.1","localhost","::1")
                and url.port and not url.username and not url.password,
                "load tests are restricted to explicit loopback HTTP endpoints")
        require(target["url"] not in urls,"targets must use distinct endpoints")
        urls.add(target["url"])
    return w

def proc_stats(pid):
    base=Path("/proc")/str(pid)
    text=(base/"stat").read_text()
    tail=text[text.rfind(")")+2:].split()
    ticks=int(tail[11])+int(tail[12])
    values={}
    for line in (base/"status").read_text().splitlines():
        if line.startswith(("VmRSS:","VmHWM:")):
            key,value,*_=line.split();values[key[:-1]]=int(value)*1024
    require("VmRSS" in values and "VmHWM" in values,"missing process RSS evidence")
    return {"ticks":ticks,"peak_rss_bytes":max(values.values()),"start_ticks":int(tail[19])}

def check_no_children(pid):
    for task in (Path("/proc")/str(pid)/"task").iterdir():
        p=task/"children"
        try:
            require(not p.read_text().strip(),"benchmark server spawned a child; single-process accounting invalid")
        except FileNotFoundError:
            continue

def verify_body(url, expected):
    target=urlsplit(url)
    conn=http.client.HTTPConnection(target.hostname,target.port,timeout=2)
    try:
        path=target.path or "/"
        if target.query:path+="?"+target.query
        conn.request("GET",path,headers={"Connection":"close","Accept":"application/json"})
        response=conn.getresponse()
        body=response.read(len(expected["body"].encode())+1)
        require(response.status==expected["status"],"response status differs from workload")
        actual_type=(response.getheader("Content-Type") or "").split(";",1)[0].strip()
        require(actual_type==expected["content_type"],"response Content-Type differs")
        require(body==expected["body"].encode(),"response body differs byte-for-byte")
    finally:
        conn.close()

def ensure_port_unused(url):
    target=urlsplit(url)
    try:
        connection=socket.create_connection((target.hostname,target.port),timeout=.2)
    except OSError:
        return
    connection.close()
    raise ValueError("benchmark endpoint is already listening: "+url)

class Monitor:
    def __init__(self, process, url, expected, verifier=None):
        self.process=process;self.url=url;self.expected=expected;self.verifier=verifier or verify_body
        self.stop=threading.Event();self.errors=[];self.probes=0;self.samples=0
        self.initial=proc_stats(process.pid);self.last=self.initial
        self.peak=self.initial["peak_rss_bytes"]
        self.thread=threading.Thread(target=self.run,daemon=True)
    def run(self):
        next_probe=time.monotonic()+1
        while not self.stop.wait(.02):
            try:
                require(self.process.poll() is None,"server exited during measurement")
                self.last=proc_stats(self.process.pid);self.samples+=1
                require(self.last["start_ticks"]==self.initial["start_ticks"],"server PID changed")
                self.peak=max(self.peak,self.last["peak_rss_bytes"])
                if time.monotonic()>=next_probe:
                    self.verifier(self.url,self.expected);self.probes+=1
                    next_probe=time.monotonic()+1
            except Exception as exc:
                self.errors.append(str(exc));return
    def start(self):
        self.thread.start()
    def finish(self):
        self.stop.set();self.thread.join(timeout=3)
        require(not self.thread.is_alive(),"correctness monitor did not terminate")
        require(not self.errors,"correctness/process monitor failed: "+"; ".join(self.errors))
        final=proc_stats(self.process.pid)
        check_no_children(self.process.pid)
        require(final["start_ticks"]==self.initial["start_ticks"],"server PID changed")
        cpu_ns=(final["ticks"]-self.initial["ticks"])*1_000_000_000/os.sysconf("SC_CLK_TCK")
        return {"cpu_nanoseconds":cpu_ns,"peak_rss_bytes":max(self.peak,final["peak_rss_bytes"]),
                "correctness_probes":self.probes,"rss_samples":self.samples}

def run_oha(oha,url,workload,duration,rate,raw_path,process,expected,verifier=None,parse=None,require_sustained=True,request=None):
    command=["taskset","--cpu-list",",".join(map(str,workload["load_cpus"])),str(oha),
             "--no-tui","--output-format","json","--http-version","1.1",
             "--worker-threads",str(len(workload["load_cpus"])),"-c",str(workload["connections"]),
             "-z",f"{duration}s","-w","-t",f"{workload['request_timeout_seconds']}s"]
    if rate is not None:command += ["-q",str(rate),"--latency-correction"]
    if request:
        # Schema-2 error-path workloads: the method, headers and body of the request under load.
        command += ["-m",request.get("method","GET")]
        for name,value in request.get("headers",{}).items():command += ["-H",f"{name}: {value}"]
        if request.get("body") is not None:command += ["-d",request["body"]]
    command += [url]
    stderr_path=raw_path.with_suffix(".stderr.txt")
    monitor=Monitor(process,url,expected,verifier);monitor.start()
    before=resource.getrusage(resource.RUSAGE_CHILDREN)
    began=time.monotonic()
    try:
        with raw_path.open("wb") as stdout,stderr_path.open("wb") as stderr:
            child=subprocess.Popen(command,cwd=ROOT,stdout=stdout,stderr=stderr,start_new_session=True)
            try:
                exit_code=child.wait(timeout=duration+workload["request_timeout_seconds"]+15)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid,signal.SIGKILL);child.wait()
                raise ValueError("oha exceeded phase deadline")
        elapsed=time.monotonic()-began
        after=resource.getrusage(resource.RUSAGE_CHILDREN)
        cpu=(after.ru_utime+after.ru_stime)-(before.ru_utime+before.ru_stime)
        require(exit_code==0,f"oha failed; inspect {stderr_path}")
        measured=monitor.finish()
        if parse is None:
            decoded=parse_oha(json.loads(raw_path.read_text()),expected["status"],len(expected["body"].encode()))
        else:
            decoded=parse(json.loads(raw_path.read_text()),expected)
        if rate is not None:
            sustained=decoded["count"]>=math.floor(rate*duration*.995)
            require(sustained or not require_sustained,
                    "fixed-rate offered load was not sustained; missing scheduled work")
            if not require_sustained:decoded["sustained"]=sustained
        require(measured["cpu_nanoseconds"]>0,"server CPU counter did not advance")
        decoded["cpu_ns_per_request"]=measured["cpu_nanoseconds"]/(decoded["count"]+measured["correctness_probes"])
        decoded["peak_rss_bytes"]=measured["peak_rss_bytes"]
        decoded["load_cpu_fraction"]=cpu/(elapsed*len(workload["load_cpus"]))
        decoded["receipt"]={"command":command,"exit_code":exit_code,"sha256":file_hash(raw_path),
                            "raw_file":str(raw_path),"stderr_file":str(stderr_path),"wall_seconds":elapsed}
        decoded["process"]=measured
        return decoded
    finally:
        monitor.stop.set();monitor.thread.join(timeout=3)

def terminate(process):
    if process.poll() is not None:return
    os.killpg(process.pid,signal.SIGTERM)
    try:process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=5)

def server_identity(target,workload):
    executable=Path(target["command"][0])
    executable=(executable if executable.is_absolute() else ROOT/executable).resolve(strict=True)
    require(executable.is_file() and os.access(executable,os.X_OK),"server executable is not an executable file")
    with executable.open("rb") as stream:
        require(stream.read(4)==b"\x7fELF","benchmark requires a directly executed native ELF server")
    command=["taskset","--cpu-list",",".join(map(str,workload["server_cpus"])),str(executable)]+target["command"][1:]
    return {"executable":str(executable),"sha256":file_hash(executable),"argv":command,
            "environment":target.get("environment",{})}

def measure_target(name,target,identity,m,workload,oha,trial,outdir,smoke):
    ensure_port_unused(target["url"])
    env=os.environ.copy();env.update(target.get("environment",{}))
    command=identity["argv"]
    require(file_hash(identity["executable"])==identity["sha256"],"server binary changed before trial")
    prefix=f"{trial:02d}-{name}"
    log_path=outdir/(prefix+"-server.log")
    with log_path.open("wb") as log:
        process=subprocess.Popen(command,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        try:
            deadline=time.monotonic()+15
            while True:
                require(process.poll() is None,"server exited before readiness: "+str(log_path))
                try:verify_body(target["url"],m["expected"]);break
                except (OSError,http.client.HTTPException,ValueError):
                    require(time.monotonic()<deadline,"server did not satisfy readiness contract")
                    time.sleep(.05)
            for _ in range(5):verify_body(target["url"],m["expected"])
            require(file_hash(Path(f"/proc/{process.pid}/exe"))==identity["sha256"],
                    "running process differs from the measured server executable")
            check_no_children(process.pid)
            warm=run_oha(oha,target["url"],workload,workload["warmup_seconds"],
                         workload["fixed_rate_qps"],outdir/(prefix+"-warmup.json"),process,m["expected"])
            latency=run_oha(oha,target["url"],workload,workload["duration_seconds"],
                            workload["fixed_rate_qps"],outdir/(prefix+"-latency.json"),process,m["expected"])
            verify_body(target["url"],m["expected"])
            capacity=run_oha(oha,target["url"],workload,workload["capacity_seconds"],
                             None,outdir/(prefix+"-capacity.json"),process,m["expected"])
            verify_body(target["url"],m["expected"])
            if not smoke:
                require(latency["load_cpu_fraction"]<.85 and capacity["load_cpu_fraction"]<.85,
                        "load generator used >=85% of its CPUs; comparison may be client-limited")
            require(file_hash(identity["executable"])==identity["sha256"],"server binary changed during trial")
            return {"target":name,"trial":trial,"server_command":command,"server_pid":process.pid,
                    "server_binary_sha256":identity["sha256"],"server_executable":identity["executable"],
                    "server_log":str(log_path),"warmup":warm,"latency":latency,"capacity":capacity}
        finally:
            terminate(process)

# ---------------------------------------------------------------------------------------------------------------
# The Spring-style REST workload (schema 2, policy/spring-http-benchmark.json; ADR-030 section 8)
#
# Each application of benchmarks/spring/apps.json is served by the Flint port and the registered Go comparator,
# and by the Java reference on the JVM as context, which is reported and never compared. Before any trial every
# implementation must pass its black-box suite; the Go comparator is rebuilt from its registered source. Trials
# alternate the order of the measured targets, as the schema-1 workload does, and use the same phases.


def spring_verifier(url, expected):
    target=urlsplit(url)
    conn=http.client.HTTPConnection(target.hostname,target.port,timeout=2)
    try:
        path=target.path or "/"
        if target.query:path+="?"+target.query
        request=expected.get("request",{})
        headers={"Connection":"close","Accept":"application/json",**request.get("headers",{})}
        body=request.get("body")
        conn.request(request.get("method","GET"),path,body=body.encode() if body is not None else None,headers=headers)
        response=conn.getresponse()
        body=response.read(expected["max_body_bytes"]+1)
        require(response.status==expected["status"],"response status differs from workload")
        actual_type=(response.getheader("Content-Type") or "").split(";",1)[0].strip()
        require(actual_type==expected["content_type"],"response Content-Type differs")
        text=body.decode("utf-8","replace")
        if "body_json" in expected:
            try:value=json.loads(text)
            except ValueError:raise ValueError("response body is not JSON")
            require(json_matches(expected["body_json"],value),"response body differs from the workload")
        else:
            require(_re.fullmatch(expected["body_regex"],text),"response body differs from the workload")
    finally:
        conn.close()

def json_matches(pattern, value):
    """Order-free JSON comparison; {"$regex": r} matches a string by regular expression. Error bodies carry a
    timestamp and the request URL, and a comparator may order keys differently (semantic wire mode)."""
    if isinstance(pattern,dict) and set(pattern)=={"$regex"}:
        return isinstance(value,str) and _re.fullmatch(pattern["$regex"],value) is not None
    if isinstance(pattern,dict):
        return isinstance(value,dict) and set(pattern)==set(value) and all(json_matches(pattern[k],value[k]) for k in pattern)
    if isinstance(pattern,list):
        return isinstance(value,list) and len(pattern)==len(value) and all(json_matches(a,b) for a,b in zip(pattern,value))
    return type(pattern) is type(value) and pattern==value

def parse_spring_oha(payload, expected):
    """parse_oha's checks, with a body-size range instead of one size: gs-rest-service's id grows a digit at a time."""
    summary=payload["summary"];status=payload["statusCodeDistribution"];errors=payload["errorDistribution"]
    require(isinstance(status,dict) and set(status)=={str(expected["status"])},"unexpected HTTP statuses in oha result")
    count=status[str(expected["status"])]
    require(isinstance(count,int) and not isinstance(count,bool) and count>0,"missing successful request count")
    require(isinstance(errors,dict) and all(isinstance(v,int) and not isinstance(v,bool) and v==0 for v in errors.values()),
            "oha reported transport errors or deadline-aborted requests")
    require(summary["successRate"]==1,"oha success rate is not 100%")
    require(count*expected["min_body_bytes"]<=summary["totalData"]<=count*expected["max_body_bytes"],
            "body byte total is outside the workload's body-size range")
    latency=payload["latencyPercentiles"]
    p50=positive_number(latency["p50"],"p50")*1000;p99=positive_number(latency["p99"],"p99")*1000
    p999=positive_number(latency["p99.9"],"p99.9")*1000
    require(p50<=p99<=p999,"latency percentiles are not monotonic")
    return {"count":count,"duration_seconds":positive_number(summary["total"],"total duration"),
            "requests_per_second":positive_number(summary["requestsPerSec"],"requests/second"),
            "p50_ms":p50,"p99_ms":p99,"p999_ms":p999}

def validate_spring_manifest(m, smoke):
    require(m.get("schema")==2,"Spring HTTP manifest schema must be 2")
    require(m["targets"]==["flint","go"],"the Spring workload measures exactly flint and go")
    require(set(m.get("context",[]))<={"java-jvm","java-native"},"context targets: java-jvm, java-native")
    w=m["workload"]
    if not smoke:
        require(w["runs"]==9 and w["duration_seconds"]>=60 and w["capacity_seconds"]>=60
                and w["warmup_seconds"]>=10,"production requires 9 trials, >=60s phases, >=10s warmup")
    for key in ["runs","duration_seconds","capacity_seconds","warmup_seconds","connections","request_timeout_seconds"]:
        positive_number(w[key],key)
    groups=[set(w[k]) for k in ("server_cpus","load_cpus","database_cpus")]
    require(all(groups) and all(a.isdisjoint(b) for i,a in enumerate(groups) for b in groups[i+1:]),
            "server, load and database CPU sets must be nonempty and disjoint")
    require(set().union(*groups)<=os.sched_getaffinity(0),"configured CPUs are not in runner cpuset")
    if not smoke:
        for core in w["server_cpus"]:
            siblings=Path(f"/sys/devices/system/cpu/cpu{core}/topology/thread_siblings_list")
            require(siblings.is_file(),"missing CPU topology; cannot verify physical separation")
            require(not (cpu_list(siblings.read_text())&(groups[1]|groups[2])),"server CPUs share an SMT core with load or database")
    for name,app in m["apps"].items():
        positive_number(app["fixed_rate_qps"],name+" fixed_rate_qps")
        e=app["expected"]
        require(isinstance(e["status"],int) and 200<=e["status"]<600,name+": HTTP status")
        require(e["content_type"] in ("application/json","application/problem+json"),name+": JSON response required")
        require(bool(e.get("body_regex"))!=("body_json" in e),name+": exactly one of body_regex and body_json")
        require(0<e["min_body_bytes"]<=e["max_body_bytes"],name+": body-size range")
    return w

def spring_quiet(smoke):
    """ADR-030 measurements run only when the runner is otherwise quiet."""
    load=os.getloadavg()[0]
    if not smoke:
        require(load<1.0,f"the runner is busy (1-minute load {load:.2f}); measure when it is otherwise quiet")
    return load

def spring_server(spring, app, target, port, database, workload, environment, smoke, extra_args=(), binary=None):
    """argv, environment and identity of one implementation, pinned to the server CPUs."""
    argv,env,cwd=spring.launch(app,"java" if target=="java-jvm" else target,port,database,extra_args,binary)
    if target=="java-native":env.pop("JAVA_TOOL_OPTIONS",None)
    env.update(environment.get(target,{}))
    executable=Path(argv[0])
    identity={"executable":str(executable),"sha256":file_hash(executable)}
    if target=="java-jvm":
        identity["jar"]=argv[2];identity["jar_sha256"]=file_hash(argv[2])
    else:
        with executable.open("rb") as stream:
            require(stream.read(4)==b"\x7fELF","benchmark requires a directly executed native ELF server")
    if target=="java-native":
        identity["note"]="Spring Boot native image (GraalVM), context only"
    argv=["taskset","--cpu-list",",".join(map(str,workload["server_cpus"]))]+argv
    return argv,env,cwd,identity

def spring_measure(spring, app, spec, target, workload, oha, trial, outdir, environment, database, smoke,
                   extra_args=(), binary=None, label=None):
    port=spring.free_port();url=f"http://127.0.0.1:{port}{spec['path']}"
    argv,env,cwd,identity=spring_server(spring,app,target,port,database,workload,environment,smoke,extra_args,binary)
    expected=spec["expected"];prefix=f"{trial:02d}-{app}-{label or target}"
    log_path=outdir/(prefix+"-server.log")
    with log_path.open("wb") as log:
        process=subprocess.Popen(argv,cwd=cwd,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        try:
            deadline=time.monotonic()+(120 if target=="java-jvm" else 30)
            while True:
                require(process.poll() is None,"server exited before readiness: "+str(log_path))
                try:spring_verifier(url,expected);break
                except (OSError,http.client.HTTPException,ValueError):
                    require(time.monotonic()<deadline,"server did not satisfy readiness contract")
                    time.sleep(.05)
            for _ in range(5):spring_verifier(url,expected)
            if target!="java-jvm":
                require(file_hash(Path(f"/proc/{process.pid}/exe"))==identity["sha256"],"running process differs from the measured executable")
            check_no_children(process.pid)
            phases={}
            for phase,seconds,rate in (("warmup",workload["warmup_seconds"],spec["fixed_rate_qps"]),
                                       ("latency",workload["duration_seconds"],spec["fixed_rate_qps"]),
                                       ("capacity",workload["capacity_seconds"],None)):
                # Context targets are reported, never compared: a JVM that cannot hold the fixed rate is recorded
                # as unsustained rather than dropped.
                phases[phase]=run_oha(oha,url,workload,seconds,rate,outdir/f"{prefix}-{phase}.json",process,expected,
                                      spring_verifier,parse_spring_oha,require_sustained=not target.startswith("java-"),
                                      request=expected.get("request"))
                spring_verifier(url,expected)
            if not smoke:
                require(phases["latency"]["load_cpu_fraction"]<.85 and phases["capacity"]["load_cpu_fraction"]<.85,
                        "load generator used >=85% of its CPUs; comparison may be client-limited")
            return {"app":app,"target":target,"trial":trial,"server_command":argv,"server_pid":process.pid,
                    "identity":identity,"server_log":str(log_path),**phases}
        finally:
            terminate(process)

def spring_main(a, raw, m):
    sys.path.insert(0,str(ROOT/"tools"))
    import spring_bench as spring
    workload=validate_spring_manifest(m,a.smoke).copy()
    keys=a.app or list(m["apps"])
    require(set(keys)<=set(m["apps"]),"unknown application")
    # A workload entry measures the application its "app" names (default: its key), so one application can carry
    # several workloads, such as its 404 and validation-error paths (policy/spring-error-paths-benchmark.json).
    app_of={key:m["apps"][key].get("app",key) for key in keys}
    apps=sorted(set(app_of.values()))
    if a.smoke:
        workload.update(runs=1,duration_seconds=2,capacity_seconds=2,warmup_seconds=1,connections=min(workload["connections"],8))
    load=spring_quiet(a.smoke)
    oha=a.oha or Path(shutil.which("oha") or ROOT/".tools/oha-1.16.0/oha")
    require(oha.is_file() and file_hash(oha)==OHA_SHA256,"provide the pinned oha with --oha, PATH or tools/install_toolchains.py --compiler oha")
    version=subprocess.run([str(oha),"--version"],capture_output=True,text=True,check=True).stdout.strip()
    require(version==OHA_VERSION,"oha version differs from pin")
    problems=spring.check_registry(apps)
    require(not problems,"Go comparators: "+"; ".join(problems))
    a.output.parent.mkdir(parents=True,exist_ok=True)
    outdir=a.output.parent/(a.output.stem+"-raw");outdir.mkdir(exist_ok=True)
    targets=list(m["targets"])
    missing=[app for app in apps if not (ROOT/spring.app_row(app)["flint"]["directory"]/"flint-spring.json").is_file()]
    if missing:
        require(a.allow_missing_flint,"the Flint port is missing for "+", ".join(missing)+
                "; a missing port fails its claim (pass --allow-missing-flint to measure the rest as an incomplete record)")
    context=[] if a.no_context else list(m.get("context",[]))
    result={"schema":2,"mode":"smoke" if a.smoke else "production","status":"running",
            "workload_sha256":hashlib.sha256(raw).hexdigest(),"manifest":str(a.manifest),"effective_workload":workload,
            "tool":{"version":version,"sha256":OHA_SHA256},"load_average_at_start":load,
            "comparators":json.loads(spring.REGISTRY.read_text())["comparators"],"apps":{},"trials":[],"acceptance":[],
            "missing_flint":missing,"context_errors":[]}
    try:
        for key in keys:
            spec=m["apps"][key];app=app_of[key]
            measured=[t for t in targets if not (t=="flint" and app in missing)]
            builds={"go":spring.build_go,"flint":spring.build_flint,"java-jvm":spring.build_java,
                    "java-native":spring.build_java_native}
            available=list(context)
            for target in measured+context:
                try:
                    builds[target](app)
                except SystemExit as exc:
                    if target not in context:raise
                    result["context_errors"].append(f"{app} [{target}] did not build: {str(exc)[:500]}")
                    available.remove(target);continue
                impl="java" if target=="java-jvm" else target
                try:
                    record=spring.accept(app,impl,spring.WIRE_DEFAULT[impl])
                except (RuntimeError,OSError) as exc:
                    if target not in context:raise
                    result["context_errors"].append(f"{app} [{target}] did not run: {str(exc)[:500]}")
                    available.remove(target);continue
                result["acceptance"].append(record)
                if not record["success"]:
                    require(target in context,f"{app} [{target}] fails its black-box suite; it is not measured")
                    result["context_errors"].append(f"{app} [{target}] fails its suite")
                    available.remove(target)
            series={t:{k:[] for k in FIELDS} for t in measured+available}
            with spring.postgres_cluster(workload["database_cpus"]) if spring.app_row(app).get("database")=="postgres" \
                    else contextlib.nullcontext() as database:
                for trial in range(workload["runs"]):
                    order=measured if trial%2==0 else list(reversed(measured))
                    for target in order+available:
                        try:
                            row=spring_measure(spring,app,spec,target,workload,oha,trial,outdir,m.get("environment",{}),database,a.smoke)
                        except ValueError as exc:
                            if target not in context:raise
                            result["context_errors"].append(f"{app} [{target}] trial {trial}: {exc}");continue
                        result["trials"].append(row)
                        for key in FIELDS:
                            series[target][key].append(row["capacity" if key=="requests_per_second" else "latency"][key])
                        print(json.dumps({"workload":key,"trial":trial,"target":target,"status":"measured"}),flush=True)
            result["apps"][key]={"app":app,"measured":{t:series[t] for t in measured},"context":{t:series[t] for t in available}}
        result["status"]="incomplete" if missing else "passed"
        a.output.write_text(json.dumps(result,indent=2)+"\n")
        return 0
    except Exception as exc:
        result["status"]="failed";result["error"]=str(exc)
        a.output.write_text(json.dumps(result,indent=2)+"\n")
        raise

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest",type=Path,default=ROOT/"policy/http-benchmark.json")
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--oha",type=Path)
    parser.add_argument("--smoke",action="store_true",help="Short harness check; never acceptable as production gate evidence.")
    parser.add_argument("--app",action="append",help="schema 2 (Spring workload): measure only this application")
    parser.add_argument("--allow-missing-flint",action="store_true",
                        help="schema 2: record the Go and Java sides when a Flint port is missing; the record is incomplete and never passes a gate")
    parser.add_argument("--no-context",action="store_true",help="schema 2: skip the Java context target")
    a=parser.parse_args(argv)
    require(sys.platform=="linux" and hasattr(os,"sched_getaffinity"),"performance harness requires Linux/proc and CPU affinity")
    require(shutil.which("taskset"),"taskset is required")
    raw=a.manifest.read_bytes();m=json.loads(raw)
    if m.get("schema")==2:
        return spring_main(a,raw,m)
    workload=validate_manifest(m,a.smoke).copy()
    if a.smoke:
        workload.update(runs=1,duration_seconds=2,capacity_seconds=2,warmup_seconds=1,
                        fixed_rate_qps=min(workload["fixed_rate_qps"],1000),connections=min(workload["connections"],8))
    oha=a.oha or Path(shutil.which("oha") or "")
    require(oha.is_file(),"provide pinned oha with --oha or PATH")
    require(file_hash(oha)==OHA_SHA256,"oha executable checksum does not match pinned Linux x86_64 binary")
    version=subprocess.run([str(oha),"--version"],capture_output=True,text=True,check=True).stdout.strip()
    require(version==OHA_VERSION,"oha version differs from pin")
    a.output.parent.mkdir(parents=True,exist_ok=True)
    outdir=a.output.parent/(a.output.stem+"-raw");outdir.mkdir(exist_ok=True)
    result={"schema":1,"mode":"smoke" if a.smoke else "production",
            "workload_sha256":hashlib.sha256(raw).hexdigest(),"manifest":str(a.manifest),
            "effective_workload":workload,"tool":{"version":version,"sha256":OHA_SHA256},
            "rest":{k:[] for k in FIELDS},"go":{"rest":{k:[] for k in FIELDS}},"trials":[]}
    result["servers"]={name:server_identity(target,workload) for name,target in m["targets"].items()}
    os.sched_setaffinity(0,set(workload["load_cpus"]))
    try:
        for trial in range(workload["runs"]):
            order=["flint","go"] if trial%2==0 else ["go","flint"]
            for name in order:
                row=measure_target(name,m["targets"][name],result["servers"][name],m,workload,oha,trial,outdir,a.smoke)
                result["trials"].append(row)
                dest=result["rest"] if name=="flint" else result["go"]["rest"]
                for key in FIELDS:
                    phase="capacity" if key=="requests_per_second" else "latency"
                    dest[key].append(row[phase][key])
                print(json.dumps({"trial":trial,"target":name,"status":"measured"}),flush=True)
        result["status"]="passed"
        a.output.write_text(json.dumps(result,indent=2)+"\n")
        return 0
    except Exception as exc:
        result["status"]="failed";result["error"]=str(exc)
        a.output.write_text(json.dumps(result,indent=2)+"\n")
        raise

if __name__=="__main__":
    try:sys.exit(main())
    except (ValueError,KeyError,OSError,subprocess.SubprocessError) as exc:
        print("HTTP BENCH FAILED:",exc,file=sys.stderr);sys.exit(1)
