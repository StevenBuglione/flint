#!/usr/bin/env python3
"""Stop-the-world pause census per GC setting (diagnostic): petclinic-rest under strace, tgkill only.

    gc_pauses.py --arm NAME=GCOPTS [--arm ...] --rate 5000 --seconds 20 --output <file>   (run inside a checkout)

druntime stops the world for a collection by signalling every other thread (suspend), marks, then signals them again
(resume). With `strace -f --seccomp-bpf -e trace=tgkill`, only those calls stop the traced process. A collection's
pause is the time from its first suspend tgkill to its last resume tgkill. The sweep that follows runs with the world
resumed (allocating threads may still wait on the GC lock), so this is the stop-the-world part of each collection.
The server runs as strace's child (posidon's ptrace_scope 1 refuses attaching), pinned to the manifest's server CPUs;
oha drives the fixed rate from the load CPUs.
"""
import argparse
import json
import re
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / 'tools'))
import load_bench  # noqa: E402
import spring_bench as spring  # noqa: E402

LINE = re.compile(r'^(\d+)\s+(\d+\.\d+)\s+tgkill\((\d+), (\d+), (SIG\w+)\)')


def pauses(log):
    """[(start, seconds, threads)] of every stop-the-world episode in an strace -f -ttt tgkill log."""
    events = []
    for line in log.read_text().splitlines():
        m = LINE.match(line)
        if m:
            events.append((float(m.group(2)), m.group(5)))
    if not events:
        return [], None
    suspend = events[0][1]
    episodes, start, last_resume, count, state = [], None, None, 0, 'idle'
    for t, sig in events:
        if sig == suspend:
            if state == 'resuming':  # a new collection begins: close the previous one
                episodes.append((start, last_resume - start, count))
                start, count, state = None, 0, 'idle'
            if start is None:
                start = t
            count += 1
            state = 'suspending'
        else:
            last_resume = t
            state = 'resuming'
    if state == 'resuming':
        episodes.append((start, last_resume - start, count))
    return episodes, suspend


def percentile(values, q):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(q * len(ordered)))] if ordered else None


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--arm', action='append', required=True)
    p.add_argument('--rate', type=int, default=5000)
    p.add_argument('--seconds', type=int, default=20)
    p.add_argument('--warmup', type=int, default=5)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    manifest = json.loads((ROOT / 'policy' / 'spring-http-benchmark.json').read_text())
    workload, spec = manifest['workload'], manifest['apps']['petclinic-rest']
    oha = ROOT / '.tools' / 'oha-1.16.0' / 'oha'
    binary = spring.flint_binary('petclinic-rest')
    result = {'schema': 'flint.gc-pauses/1', 'note': 'diagnostic, never evidence', 'rate': a.rate,
              'seconds': a.seconds, 'binary_sha256': spring.sha256(binary), 'arms': {}}
    out = a.output.parent
    with spring.postgres_cluster(workload['database_cpus']) as database:
        for item in a.arm:
            name, _, options = item.partition('=')
            port = spring.free_port()
            extra = (f'--DRT-gcopt={options} profile:1',)
            argv, env, cwd, _ = load_bench.spring_server(spring, 'petclinic-rest', 'flint', port, database, workload,
                                                         manifest.get('environment', {}), True, extra, binary)
            log = out / f'pauses-{name}.strace'
            server_log = out / f'pauses-{name}-server.log'
            traced = ['strace', '-f', '--seccomp-bpf', '-e', 'trace=tgkill', '-ttt', '-o', str(log)] + argv
            with server_log.open('wb') as stream:
                process = subprocess.Popen(traced, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                           start_new_session=True)
                try:
                    url = f"http://127.0.0.1:{port}{spec['path']}"
                    deadline = time.monotonic() + 60
                    while True:
                        try:
                            load_bench.spring_verifier(url, spec['expected'])
                            break
                        except Exception:
                            if process.poll() is not None or time.monotonic() > deadline:
                                raise SystemExit(f'{name}: the server did not start; see {server_log}')
                            time.sleep(.1)
                    load = ['taskset', '--cpu-list', ','.join(map(str, workload['load_cpus'])), str(oha), '--no-tui',
                            '--output-format', 'json', '--http-version', '1.1', '-c', str(workload['connections']),
                            '--worker-threads', str(len(workload['load_cpus'])), '-q', str(a.rate),
                            '--latency-correction']
                    subprocess.run(load + ['-z', f'{a.warmup}s', url], capture_output=True, check=True)
                    began = time.time()
                    done = subprocess.run(load + ['-z', f'{a.seconds}s', url], capture_output=True, check=True)
                    ended = time.time()
                    summary = json.loads(done.stdout)
                    requests = sum(summary['statusCodeDistribution'].values())
                finally:
                    # SIGTERM through strace to the server (strace forwards it); the exit profile follows.
                    for child in subprocess.run(['pgrep', '-P', str(process.pid)], capture_output=True,
                                                text=True).stdout.split():
                        subprocess.run(['kill', '-TERM', child])
                    try:
                        process.wait(20)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
            episodes, suspend = pauses(log)
            measured = [e for e in episodes if began <= e[0] <= ended]
            ms = [e[1] * 1000 for e in measured]
            result['arms'][name] = {
                'gcopt': options, 'requests': requests, 'suspend_signal': suspend,
                'collections': len(measured), 'collections_per_1000_requests': len(measured) * 1000 / requests,
                'pause_ms': {'p50': percentile(ms, .5), 'p90': percentile(ms, .9), 'p99': percentile(ms, .99),
                             'max': max(ms) if ms else None, 'mean': statistics.mean(ms) if ms else None,
                             'total': sum(ms)},
                'threads_suspended_median': statistics.median([e[2] for e in measured]) if measured else None,
                'latency_ms': {k: summary['latencyPercentiles'][k] * 1000 for k in ('p50', 'p99', 'p99.9')}}
            log.unlink()  # large; the episodes are summarized above
            print(json.dumps({name: result['arms'][name]['pause_ms'] | {
                'collections_per_1000': round(result['arms'][name]['collections_per_1000_requests'], 2)}}), flush=True)
    a.output.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
