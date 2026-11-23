#!/usr/bin/env python3
"""The measurement queue for venus: pending performance runs, run only in a quiet window.

    measure_queue.py list
    measure_queue.py quiet [--json]                is venus quiet enough to measure right now?
    measure_queue.py show <id>
    measure_queue.py prepare <id>...               build what an entry measures (allowed any time; nothing is timed)
    measure_queue.py run <id>... [--force-busy]    prepare, check the window, measure, write the receipt
    measure_queue.py next                          run every pending entry in order while the window stays quiet

Each entry is one file, benchmarks/spring/queue/<id>.json, so sessions can add entries without touching each other's.
An entry names what to build (`builds`: an app at a commit) and how to measure it (`measure.kind`):

- `startup`: wall time from exec to the first correct response, the builds interleaved (A, B, B, A, ...);
- `rest-pair`: tools/load_bench.py's schema-1 REST workload with a base build in one slot and a candidate in the
  other, interleaved by load_bench, then the regression ratios of policy/budgets.json;
- `command`: any measuring command (measure_builds, load_bench's Spring workload, the GC matrix).

The quiet window (benchmarks/spring/README.md, "The measurement queue"):
- the 1-minute load average is below 1.5;
- no compiler or build-system process (dmd, ldc2, ldmd2, cargo, cmake, and the heavier helpers they start) uses
  CPU outside this run, in any worktree (idle DMD compile-server workers do not count);
- every port is outside 8080-8099, which other sessions' services and the default manifests use, and is free;
- servers and load generators are pinned to the CPU sets of their manifests, as the evidence rules require.
The window is checked before every measuring step and again after it, and both snapshots, with the load averages and
the processes found, go into the receipt. A step that ends in a busy window is recorded as such and not reported
as evidence. `--force-busy` measures anyway and marks the receipt `busy`, for harness checks only.

While a measurement runs, .flint/measure/MEASURING holds its entry id, start time and pid; other sessions hold
their compiles while it exists (docs/spring/phase1/coordination.md, "Measurement").

Builds happen in detached worktrees under .flint/measure/worktrees/<commit> with their own native prefix; the
shared .native is never written. Raw outputs and every attempt go to .flint/measure/results/<id>/ (attempts.jsonl); the entry file changes only
when a run counts as evidence, which receives its receipt and status done.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import socket
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QUEUE = ROOT / 'benchmarks' / 'spring' / 'queue'
WORK = ROOT / '.flint' / 'measure'
LOCK = WORK / 'MEASURING'
BUSY_COMMANDS = {'dmd', 'ldc2', 'ldmd2', 'cargo', 'cmake', 'rustc', 'cc1', 'cc1plus', 'native-image', 'ninja',
                 'dub', 'mvn', 'gradle'}
LOAD_LIMIT = 1.5
RESERVED_PORTS = range(8080, 8100)
ACTIVE_TICKS = 2  # CPU ticks (1/100 s) in the sampling second that make a build process active
SERVER_CPUS = [2, 3]
LOAD_CPUS = [4, 5, 6, 7]


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def now():
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())


# ---------------------------------------------------------------------------------------------------------------
# The quiet window


def parents():
    table = {}
    for name in os.listdir('/proc'):
        if name.isdigit():
            try:
                stat = Path(f'/proc/{name}/stat').read_text()
            except OSError:
                continue
            table[int(name)] = int(stat[stat.rindex(')') + 2:].split()[1])
    return table


def own_tree():
    """This process, its ancestors and its descendants: the run's own builds are not other sessions' load."""
    table = parents()

    def chain(pid):
        seen = []
        while pid > 1 and pid not in seen:
            seen.append(pid)
            pid = table.get(pid, 0)
        return seen
    me = os.getpid()
    mine = set(chain(me))
    mine.update(pid for pid in table if me in chain(pid))
    return mine


def cpu_ticks(pid):
    stat = Path(f'/proc/{pid}/stat').read_text()
    fields = stat[stat.rindex(')') + 2:].split()
    return int(fields[11]) + int(fields[12])


OWN_DIRECTORIES = []  # set by run(): the run's checkouts and results; a process working there belongs to the run


def build_processes():
    """Compiler and build-system processes on the host outside this run's own tree, with where they run. A process
    whose working directory is inside the run's own checkouts belongs to the run even when it is not a descendant:
    the DMD compile server detaches from the build that starts it."""
    mine = own_tree()
    own = [str(Path(d).resolve()) + os.sep for d in OWN_DIRECTORIES]
    found = []
    for name in os.listdir('/proc'):
        if not name.isdigit() or int(name) in mine:
            continue
        try:
            command = Path(f'/proc/{name}/comm').read_text().strip()
            if command not in BUSY_COMMANDS:
                continue
            cwd = os.readlink(f'/proc/{name}/cwd')
            if any((cwd.removesuffix(' (deleted)') + os.sep).startswith(prefix) for prefix in own):
                continue
            found.append({'pid': int(name), 'command': command, 'cwd': cwd, 'ticks': cpu_ticks(name)})
        except OSError:
            continue
    return found


def busy_processes(interval=1.0):
    """The build processes that use CPU during `interval` seconds. The DMD compile servers keep pre-forked workers
    asleep between builds, often thousands of them on a shared host; those are idle, not load."""
    first = build_processes()
    time.sleep(interval)
    busy = []
    for row in first:
        try:
            used = cpu_ticks(row['pid']) - row['ticks']
        except OSError:
            continue
        if used >= ACTIVE_TICKS:
            busy.append({'pid': row['pid'], 'command': row['command'], 'cwd': row['cwd'], 'cpu_ticks': used})
    busy_processes.idle = len(first) - len(busy)
    return busy


class WindowSampler:
    """Snapshots of the window every 10 s while a measurement runs, so contention in the middle is seen too."""

    def __init__(self):
        import threading
        self.samples, self.stop = [], threading.Event()
        self.thread = threading.Thread(target=self.loop, daemon=True)

    def loop(self):
        while not self.stop.wait(10):
            snapshot = quiet_snapshot(own_load_ok=True)
            self.samples.append({'time': snapshot['time'], 'load_average': snapshot['load_average'],
                                 'busy_processes': snapshot['busy_processes']})

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.stop.set()
        self.thread.join()

    def foreign_activity(self):
        return [sample for sample in self.samples if sample['busy_processes']]


def quiet_snapshot(own_load_ok=False):
    """`own_load_ok`: during a measurement the load average includes the measurement itself, so only foreign
    build processes count."""
    load = os.getloadavg()
    processes = busy_processes()
    problems = []
    if load[0] >= LOAD_LIMIT and not own_load_ok:
        problems.append(f'1-minute load average {load[0]:.2f} is not below {LOAD_LIMIT}')
    if processes:
        where = sorted({row['cwd'] for row in processes})
        problems.append(f"{len(processes)} build process(es) using CPU: "
                        + ', '.join(sorted({row['command'] for row in processes})) + ' in ' + '; '.join(where[:6]))
    return {'time': now(), 'load_average': list(load), 'busy_processes': processes,
            'idle_build_processes': getattr(busy_processes, 'idle', None), 'quiet': not problems, 'problems': problems}


def port_free(port):
    with socket.socket() as probe:
        # SO_REUSEADDR, as servers bind: a socket left in TIME_WAIT by the previous run is not a listener.
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            probe.bind(('127.0.0.1', port))
        except OSError:
            return False
    return True


def check_ports(ports):
    problems = [f'port {port} is in the reserved range 8080-8099' for port in ports if port in RESERVED_PORTS]
    problems += [f'port {port} is in use' for port in ports if port not in RESERVED_PORTS and not port_free(port)]
    return problems


# ---------------------------------------------------------------------------------------------------------------
# Entries


def entry_path(name):
    return QUEUE / f'{name}.json'


def load_entry(name):
    path = entry_path(name)
    if not path.is_file():
        raise SystemExit(f'no queue entry {name} ({path.relative_to(ROOT)})')
    return json.loads(path.read_text())


def save_entry(entry):
    entry_path(entry['id']).write_text(json.dumps(entry, indent=2, ensure_ascii=False) + '\n')


def log_attempt(entry, row):
    """Every attempt, refused or measured, in .flint/measure/results/<id>/attempts.jsonl."""
    directory = WORK / 'results' / entry['id']
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / 'attempts.jsonl').open('a') as stream:
        stream.write(json.dumps(row) + '\n')


def entries():
    return sorted((json.loads(path.read_text()) for path in QUEUE.glob('*.json')), key=lambda e: (e['created'], e['id']))


# ---------------------------------------------------------------------------------------------------------------
# Builds at a commit


def worktree(commit):
    full = subprocess.run(['git', 'rev-parse', commit + '^{commit}'], cwd=ROOT, capture_output=True, text=True,
                          check=True).stdout.strip()
    directory = WORK / 'worktrees' / full[:12]
    if not (directory / '.git').exists():
        directory.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['git', 'worktree', 'add', '--detach', '-q', str(directory), full], cwd=ROOT, check=True)
    return directory, full


def checkout_roots():
    roots = [ROOT]
    common = subprocess.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], cwd=ROOT,
                            capture_output=True, text=True).stdout.strip()
    if common and Path(common).name == '.git':
        roots.append(Path(common).parent)
    return roots


def shared_tools():
    """The toolchain directory that holds the pinned DMD: this checkout's, or the main checkout's."""
    for root in checkout_roots():
        if (root / '.tools' / 'dmd2' / 'linux' / 'bin64' / 'dmd').is_file():
            return root / '.tools'
    raise SystemExit('no checkout holds the pinned toolchain (tools/install_toolchains.py --compiler dmd)')


def private_tools(tools, linker):
    """A toolchain directory for one checkout: every entry of the shared one linked, except DMD, which is copied and
    configured to link with `linker` (ADR-021: dev builds link with mold). The shared toolchain other sessions use is
    never changed."""
    shared = shared_tools()
    tools.mkdir()
    for entry in shared.iterdir():
        if entry.name == 'dmd2':
            shutil.copytree(entry, tools / 'dmd2', symlinks=True)
        elif entry.name == 'flint-toolchain.json':
            shutil.copy2(entry, tools / entry.name)
        else:
            (tools / entry.name).symlink_to(entry)
    sys.path.insert(0, str(ROOT / 'tools'))
    import install_toolchains
    if linker == 'mold' and hasattr(install_toolchains, 'install_mold'):
        # The pinned mold (policy/toolchains.json, checksum-verified), installed into this private directory.
        linker = str(install_toolchains.install_mold(tools))
    install_toolchains.configure_dmd_linker(tools / 'dmd2' / 'linux' / 'bin64',
                                            install_toolchains.identify_elf_linker(linker))


def toolchain_environment():
    """The pinned toolchain on PATH: the forked DMD, LDC and the tools bin directory of the main checkout (this
    checkout first, for worktrees that carry their own .tools)."""
    roots = [ROOT]
    common = subprocess.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], cwd=ROOT,
                            capture_output=True, text=True).stdout.strip()
    if common and Path(common).name == '.git':
        roots.append(Path(common).parent)
    paths = []
    for root in roots:
        tools = root / '.tools'
        paths += [str(p) for p in sorted(tools.glob('oha-*')) if p.is_dir()]
        paths += [str(p) for p in (tools / 'bin', tools / 'dmd2' / 'linux' / 'bin64', tools / 'ldc2-1.43.0-linux-x86_64' / 'bin',
                                   tools / 'go' / 'bin') if p.is_dir()]
    return dict(os.environ, PATH=os.pathsep.join(paths + [os.environ.get('PATH', '')]))


def openssl_disabled(directory):
    """The features OpenSSL's Configure disabled, from the `%disabled` hash of its configdata.pm: the record of every
    `no-<feature>` switch. configuration.h is not enough, because some switches (no-legacy) emit no macro."""
    import re
    path = directory / '.native' / 'build' / 'linux-x86_64-glibc' / 'openssl' / 'configdata.pm'
    if not path.is_file():
        raise SystemExit(f'{path} is missing after the native build')
    text = path.read_text(errors='replace')
    start = text.index('our %disabled = (')
    block = text[start:text.index('\n);', start)]
    return set(re.findall(r'^\s*"([^"]+)"\s*=>', block, re.M))


def check_native(spec, directory, full):
    """`expect_openssl_disabled` maps an OpenSSL feature to whether this side's native build must have it disabled
    (ADR-031: the TLS-only build passes no-legacy, no-des, ...). A side that links the other side's libcrypto would
    time the same library twice, so a mismatch fails the build."""
    expected = spec.get('expect_openssl_disabled')
    if not expected:
        return
    disabled = openssl_disabled(directory)
    for feature, want in expected.items():
        if (feature in disabled) != want:
            raise SystemExit(f"{full[:12]}: OpenSSL feature '{feature}' is {'disabled' if feature in disabled else 'enabled'}, "
                             f"expected {'disabled' if want else 'enabled'} (configdata.pm %disabled)")


def build_bench_rest(spec, logs):
    """bench-rest as the size and REST measurements build it: LDC O3 + ThinLTO, stripped (measure_builds
    --app-sizes), in a detached worktree at the commit with that worktree's own native prefix."""
    directory, full = worktree(spec['commit'])
    method = spec.get('method', 'app-sizes')
    output = WORK / 'bin' / f"bench-rest-{full[:12]}-{method}"
    if output.is_file():
        check_native(spec, directory, full)
        return {'commit': full, 'method': method, 'binary': str(output), 'sha256': sha256(output),
                'bytes': output.stat().st_size, 'reused': True}
    steps = [[sys.executable, 'tools/native_build.py', '--profile', 'ci', '--target', 'linux-x86_64-glibc',
              '--phase', 'build', '--emit-dub']]
    if method == 'app-sizes':
        steps.append([sys.executable, 'tools/measure_builds.py', '--app-sizes', '--app', 'bench-rest', '--output',
                      str(WORK / 'results' / f'sizes-{full[:12]}.json')])
        built = directory / 'build' / 'bench-rest'
    elif method == 'dub-release':
        # benchmarks/bench-rest/README.md's own build, available at every commit (--app-sizes came with 188c632).
        steps.append(['dub', 'build', '--root=benchmarks/bench-rest', '--compiler=ldc2', '--build=release'])
        built = None
    else:
        raise SystemExit(f'unknown bench-rest build method {method}')
    (WORK / 'results').mkdir(parents=True, exist_ok=True)
    for index, command in enumerate(steps):
        log = logs / f"build-{full[:12]}-{index}.log"
        with log.open('wb') as stream:
            completed = subprocess.run(command, cwd=directory, env=toolchain_environment(), stdout=stream,
                                       stderr=subprocess.STDOUT)
        if completed.returncode:
            raise SystemExit(f'building bench-rest at {full[:12]} failed; see {log}')
        if index == 0:
            check_native(spec, directory, full)
    if built is None:
        candidates = [directory / 'benchmarks' / 'bench-rest' / 'build' / 'bench-rest', directory / 'build' / 'bench-rest']
        built = next((path for path in candidates if path.is_file()), None)
        if built is None:
            raise SystemExit(f'the bench-rest build at {full[:12]} produced no executable')
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(built, output)
    receipt = {'commit': full, 'method': method, 'binary': str(output), 'sha256': sha256(output),
               'bytes': output.stat().st_size, 'reused': False}
    if spec.get('expect_openssl_disabled'):
        receipt['openssl_disabled_checked'] = spec['expect_openssl_disabled']
    sizes_file = WORK / 'results' / f'sizes-{full[:12]}.json'
    if method == 'app-sizes' and sizes_file.is_file():
        app = json.loads(sizes_file.read_text())['apps']['bench-rest']
        receipt['sizes'] = {profile: app[profile]['binary_bytes'] for profile in ('O3', 'Oz')}
        expected = spec.get('expect_bytes')
        if expected and expected != receipt['sizes']:
            receipt['size_note'] = f"sizes {receipt['sizes']} differ from the requester's {expected} (main may have moved)"
    return receipt


def prepare_checkout(spec, logs):
    """A detached worktree at the commit with its own native prefix, for `command` steps that run measure_builds
    there (`in`). The native build runs once; later runs reuse the prefix."""
    directory, full = worktree(spec['commit'])
    # Written only after the native build succeeds: the install directory and its receipt exist half-way through.
    marker = directory / '.native' / 'flint-measure-prepared'
    if not marker.is_file():
        log = logs / f'native-{full[:12]}.log'
        with log.open('wb') as stream:
            completed = subprocess.run([sys.executable, 'tools/native_build.py', '--profile', 'ci', '--target',
                                        'linux-x86_64-glibc', '--phase', 'build', '--emit-dub'], cwd=directory,
                                       env=toolchain_environment(), stdout=stream, stderr=subprocess.STDOUT)
        if completed.returncode:
            raise SystemExit(f'the native build at {full[:12]} failed; see {log}')
        marker.write_text(now() + '\n')
    if spec.get('flint'):
        # The flint CLI at this commit, for steps that build Flint ports; the pinned compilers come from the main
        # checkout's toolchain directory, linked read-only.
        tools = directory / '.tools'
        if not tools.exists() and spec.get('linker'):
            private_tools(tools, spec['linker'])
        elif not tools.exists():
            tools.symlink_to(shared_tools())
        # The pinned peers (JDK, Maven, PostgreSQL) installed in this checkout, for spring_bench and load_bench there.
        peers = directory / '.flint' / 'peers'
        if not peers.exists() and (ROOT / '.flint' / 'peers').is_dir():
            peers.parent.mkdir(parents=True, exist_ok=True)
            peers.symlink_to(ROOT / '.flint' / 'peers')
        if not (directory / '.flint' / 'bin' / 'flint').is_file():
            log = logs / f'flint-{full[:12]}.log'
            with log.open('wb') as stream:
                completed = subprocess.run([sys.executable, 'tools/install_toolchains.py', '--compiler', 'flint'],
                                           cwd=directory, env=toolchain_environment(), stdout=stream,
                                           stderr=subprocess.STDOUT)
            if completed.returncode:
                raise SystemExit(f'bootstrapping flint at {full[:12]} failed; see {log}')
    return {'commit': full, 'worktree': str(directory)}


RECIPES = {'bench-rest': build_bench_rest, 'checkout': prepare_checkout}


def prepare(entry, logs):
    built = {}
    for slot, spec in entry.get('builds', {}).items():
        print(f"{entry['id']}: building {spec['app']} at {spec['commit']} ({slot})", flush=True)
        built[slot] = RECIPES[spec['app']](spec, logs)
        if spec.get('expect_sha256_prefix') and not built[slot]['sha256'].startswith(spec['expect_sha256_prefix']):
            built[slot]['note'] = (f"sha256 {built[slot]['sha256'][:10]} differs from the requester's "
                                   f"{spec['expect_sha256_prefix']} (expected when the base differs)")
    return built


# ---------------------------------------------------------------------------------------------------------------
# Measurements


def first_response(binary, args, port, path, expected, env, cpus):
    """Milliseconds from exec to the first response with the expected status and body."""
    request = f'GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n'.encode()
    started = time.perf_counter_ns()
    process = subprocess.Popen(['taskset', '--cpu-list', ','.join(map(str, cpus)), binary,
                                *[a.replace('{port}', str(port)) for a in args]],
                               env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        while True:
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=2) as connection:
                    connection.sendall(request)
                    data = b''
                    while chunk := connection.recv(65536):
                        data += chunk
                elapsed = (time.perf_counter_ns() - started) / 1e6
                head, _, body = data.partition(b'\r\n\r\n')
                if not head.startswith(b'HTTP/1.1 200') or body != expected.encode():
                    raise SystemExit(f'{binary}: unexpected response {data[:200]!r}')
                return elapsed
            except (ConnectionRefusedError, ConnectionResetError):
                if process.poll() is not None:
                    raise SystemExit(f'{binary} exited with {process.returncode} before responding')
                if time.perf_counter_ns() - started > 30e9:
                    raise SystemExit(f'{binary} did not respond within 30 s')
                time.sleep(.0002)
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * fraction))]


def measure_startup(entry, built, outdir, smoke):
    spec = entry['measure']
    runs = 5 if smoke else spec['runs']
    ports = spec['ports']
    env = dict(os.environ, **spec.get('environment', {}))
    slots = list(built)
    samples = {slot: [] for slot in slots}
    for trial in range(runs):
        order = slots if trial % 2 == 0 else list(reversed(slots))
        for slot in order:
            port = ports[trial % len(ports)]
            samples[slot].append(first_response(built[slot]['binary'], spec['args'], port, spec['path'],
                                                spec['expected_body'], env, spec.get('cpus', SERVER_CPUS)))
    (outdir / 'startup-samples.json').write_text(json.dumps(samples) + '\n')
    summary = {slot: {'median_ms': statistics.median(v), 'p10_ms': percentile(v, .1), 'p90_ms': percentile(v, .9),
                      'runs': len(v), 'commit': built[slot]['commit'], 'sha256': built[slot]['sha256']}
               for slot, v in samples.items()}
    if len(slots) == 2 and runs >= 9:
        from perf_stats import median_ratio_interval
        median, lower, upper = median_ratio_interval(samples[slots[1]], samples[slots[0]])
        summary['ratio'] = {'of': f'{slots[1]}/{slots[0]}', 'median': median, 'lower_99': lower, 'upper_99': upper}
    return summary


def measure_rest_pair(entry, built, outdir, smoke):
    """The schema-1 workload with the candidate in load_bench's `flint` slot and the base in its `go` slot, so
    load_bench interleaves them trial by trial with identical accounting. The receipt names the slots."""
    spec = entry['measure']
    manifest = json.loads((ROOT / spec['manifest']).read_text())
    base, candidate = spec['base'], spec['candidate']
    ports = spec['ports']
    for slot, name, port in (('flint', candidate, ports[0]), ('go', base, ports[1])):
        target = manifest['targets'][slot]
        target['command'] = [built[name]['binary'], '--listen', f'127.0.0.1:{port}']
        target['url'] = f'http://127.0.0.1:{port}/json'
        target['environment'] = dict(spec.get('environment', {}))
    copy = outdir / 'manifest.json'
    copy.write_text(json.dumps(manifest, indent=2) + '\n')
    command = [sys.executable, str(ROOT / 'tools' / 'load_bench.py'), '--manifest', str(copy), '--output',
               str(outdir / 'http.json')] + (['--smoke'] if smoke else [])
    oha = ROOT / '.tools' / 'oha-1.16.0' / 'oha'
    if oha.is_file():
        command += ['--oha', str(oha)]
    log = outdir / 'load_bench.log'
    with log.open('wb') as stream:
        completed = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
    result = json.loads((outdir / 'http.json').read_text())
    if completed.returncode or result.get('status') != 'passed':
        raise SystemExit(f"load_bench failed: {result.get('error')}; see {log}")
    budgets = json.loads((ROOT / 'policy' / 'budgets.json').read_text())['regression']
    from perf_stats import median_ratio_interval
    new, old = result['rest'], result['go']['rest']
    summary = {'slots': {'flint': candidate, 'go': base}, 'manifest_sha256': sha256(copy), 'ratios': {}}
    for metric, ceiling in (('p99_ms', budgets['latency_ratio_max']), ('p50_ms', budgets['latency_ratio_max']),
                            ('peak_rss_bytes', budgets['rss_ratio_max']),
                            ('cpu_ns_per_request', budgets['latency_ratio_max'])):
        if len(new[metric]) >= 9 and len(old[metric]) >= 9:
            median, lower, upper = median_ratio_interval(new[metric], old[metric])
            summary['ratios'][metric] = {'median': median, 'lower_99': lower, 'upper_99': upper, 'ceiling': ceiling,
                                         'pass': median <= ceiling and upper <= ceiling}
        else:
            summary['ratios'][metric] = {'median': statistics.median(new[metric]) / statistics.median(old[metric]),
                                         'note': 'fewer than 9 trials: no interval, no verdict'}
    rps_new, rps_old = new['requests_per_second'], old['requests_per_second']
    summary['ratios']['requests_per_second'] = {'median': statistics.median(rps_new) / statistics.median(rps_old),
                                                'floor': budgets['throughput_ratio_min']}
    if len(rps_new) >= 9:
        median, lower, upper = median_ratio_interval([1 / x for x in rps_new], [1 / x for x in rps_old])
        summary['ratios']['requests_per_second'].update(
            {'pass': median <= 1 / budgets['throughput_ratio_min'] and upper <= 1 / budgets['throughput_ratio_min']})
    return summary


def measure_command(entry, built, outdir, smoke):
    """Each step runs in this checkout, or in a build's worktree when it names one (`in`). `{out}` is the results
    directory. A failing step stops the entry, except a `may_fail` step: measure_builds, load_bench, the GC matrix
    and the gates exit 1 when a verdict fails, which is a result, not a crash. Its exit code goes into the receipt
    and its verdicts are in its own output."""
    receipts = []
    for index, step in enumerate(entry['measure']['steps']):
        cwd, env = ROOT, toolchain_environment()
        if step.get('in'):
            cwd = worktree(built[step['in']]['commit'])[0]
            private = [cwd / '.flint' / 'bin', cwd / '.tools' / 'dmd2' / 'linux' / 'bin64']
            env['PATH'] = os.pathsep.join(str(p) for p in private if p.is_dir()) + os.pathsep + env['PATH']
        command = [part.replace('{out}', str(outdir)).replace('{python}', sys.executable) for part in step['argv']]
        if smoke and step.get('smoke_args'):
            command += step['smoke_args']
        log = outdir / f'step-{index}.log'
        with log.open('wb') as stream:
            completed = subprocess.run(command, cwd=cwd, env=env, stdout=stream,
                                       stderr=subprocess.STDOUT)
        receipts.append({'command': command, 'cwd': str(cwd), 'exit_code': completed.returncode, 'log': str(log)})
        if completed.returncode and not step.get('may_fail'):
            raise SystemExit(f'step {index} exited with {completed.returncode}; see {log}')
    return {'steps': receipts,
            'outputs': {p.name: sha256(p) for p in sorted(outdir.iterdir()) if p.is_file() and p.suffix == '.json'}}


KINDS = {'startup': measure_startup, 'rest-pair': measure_rest_pair, 'command': measure_command}


def run(entry, force_busy=False, smoke=False):
    outdir = WORK / 'results' / entry['id'] / time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())
    outdir.mkdir(parents=True, exist_ok=True)
    built = prepare(entry, outdir)
    ports = entry['measure'].get('ports', [])
    port_problems = check_ports(ports)
    if port_problems:
        raise SystemExit(f"{entry['id']}: " + '; '.join(port_problems))
    OWN_DIRECTORIES[:] = [outdir] + [row['worktree'] for row in built.values() if row.get('worktree')]
    before = quiet_snapshot()
    if not before['quiet'] and not force_busy:
        log_attempt(entry, {'time': before['time'], 'outcome': 'not run: busy', 'problems': before['problems']})
        raise SystemExit(f"{entry['id']}: venus is busy: " + '; '.join(before['problems']))
    print(f"{entry['id']}: measuring ({entry['measure']['kind']})", flush=True)
    # The signal other sessions watch: while MEASURING exists, a timed run is in progress and compiles would void it.
    # Smoke and forced runs are never evidence, so they do not ask anyone to hold builds.
    locking = not (smoke or force_busy)
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    if locking:
        LOCK.write_text(json.dumps({'id': entry['id'], 'started': now(), 'pid': os.getpid(),
                                'results': str(outdir)}) + '\n')
    pin = entry['measure']['kind'] == 'startup'  # load_bench and measure_builds pin their own processes
    if pin:
        os.sched_setaffinity(0, set(LOAD_CPUS))
    try:
        with WindowSampler() as sampler:
            summary = KINDS[entry['measure']['kind']](entry, built, outdir, smoke)
    finally:
        if locking:
            LOCK.unlink(missing_ok=True)
        if pin:
            os.sched_setaffinity(0, set(range(os.cpu_count())))
    # The load average at the end includes the measurement itself (a start-up run launches hundreds of processes),
    # so the after-check, like the samples during the run, judges foreign build processes only.
    after = quiet_snapshot(own_load_ok=True)
    foreign = sampler.foreign_activity()
    evidence = before['quiet'] and after['quiet'] and not foreign and not smoke
    receipt = {'time': now(), 'outcome': 'measured' if evidence else ('smoke' if smoke else 'busy'),
               'evidence': evidence, 'host': os.uname().nodename, 'builds': built, 'window_before': before,
               'window_during': sampler.samples, 'foreign_activity_during': len(foreign), 'window_after': after, 'results_directory': str(outdir.relative_to(ROOT)), 'summary': summary}
    (outdir / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    log_attempt(entry, {'time': receipt['time'], 'outcome': receipt['outcome'], 'evidence': evidence,
                        'receipt': str((outdir / 'receipt.json').relative_to(ROOT))})
    if evidence:
        # Only evidence changes the entry file, so the queue's files change when there is something to commit.
        entry.setdefault('attempts', []).append(receipt)
        entry['status'] = 'done'
        save_entry(entry)
    return receipt


# ---------------------------------------------------------------------------------------------------------------


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('list')
    p = sub.add_parser('quiet'); p.add_argument('--json', action='store_true')
    p = sub.add_parser('show'); p.add_argument('id')
    p = sub.add_parser('prepare'); p.add_argument('ids', nargs='+')
    p = sub.add_parser('run'); p.add_argument('ids', nargs='+')
    p.add_argument('--force-busy', action='store_true', help='measure in a busy window; the receipt is never evidence')
    p.add_argument('--smoke', action='store_true', help='a short harness check; never evidence')
    sub.add_parser('next')
    p = sub.add_parser('watch', help='wait for quiet, run the pending entries, repeat until none is pending')
    p.add_argument('--quiet-minutes', type=int, default=5)
    p.add_argument('--hours', type=float, default=12, help='give up after this long')
    args = parser.parse_args(argv)
    if args.command == 'list':
        for entry in entries():
            log = WORK / 'results' / entry['id'] / 'attempts.jsonl'
            lines = log.read_text().splitlines() if log.is_file() else []
            last = json.loads(lines[-1])['outcome'] if lines else '-'
            print(f"{entry['id']:34} {entry['status']:8} {entry['measure']['kind']:10} last: {last:16} {entry['summary'][:70]}")
        return 0
    if args.command == 'quiet':
        snapshot = quiet_snapshot()
        if args.json:
            print(json.dumps(snapshot, indent=2))
        else:
            print('quiet' if snapshot['quiet'] else 'busy: ' + '; '.join(snapshot['problems']))
        return 0 if snapshot['quiet'] else 1
    if args.command == 'show':
        print(json.dumps(load_entry(args.id), indent=2, ensure_ascii=False))
        return 0
    if args.command == 'prepare':
        for name in args.ids:
            entry = load_entry(name)
            logs = WORK / 'results' / name / 'prepare'
            logs.mkdir(parents=True, exist_ok=True)
            print(json.dumps(prepare(entry, logs), indent=2))
        return 0
    if args.command == 'run':
        for name in args.ids:
            receipt = run(load_entry(name), args.force_busy, args.smoke)
            print(json.dumps({'id': name, 'outcome': receipt['outcome'], 'summary': receipt['summary']}, indent=2))
        return 0
    if args.command == 'watch':
        # Natural quiet (the fiber-wake session's procedure): run when venus has been quiet for --quiet-minutes in a
        # row; a run interrupted by other sessions is recorded as not evidence and stays pending for the next window.
        deadline = time.monotonic() + args.hours * 3600
        streak = 0
        while time.monotonic() < deadline:
            # Shortest first: venus's quiet gaps are short, and a long run that loses its window should not keep
            # the one-minute timings from ever running.
            pending = sorted((e for e in entries() if e['status'] == 'pending'),
                             key=lambda e: (e.get('estimate_minutes', 60), e['created'], e['id']))
            if not pending:
                print(now(), 'no pending entries; done', flush=True)
                return 0
            snapshot = quiet_snapshot()
            streak = streak + 1 if snapshot['quiet'] else 0
            if streak < args.quiet_minutes:
                time.sleep(59)
                continue
            for entry in pending:
                if not quiet_snapshot()['quiet']:
                    print(now(), 'window closed before', entry['id'], flush=True)
                    break
                print(now(), 'running', entry['id'], flush=True)
                try:
                    receipt = run(entry)
                    print(now(), entry['id'], receipt['outcome'], 'evidence' if receipt['evidence'] else 'not evidence',
                          flush=True)
                except SystemExit as exc:
                    print(now(), entry['id'], 'stopped:', exc, flush=True)
            streak = 0
        print(now(), 'gave up after', args.hours, 'hours', flush=True)
        return 1
    if args.command == 'next':
        for entry in [e for e in entries() if e['status'] == 'pending']:
            snapshot = quiet_snapshot()
            if not snapshot['quiet']:
                print('stopping: venus is busy: ' + '; '.join(snapshot['problems']))
                return 1
            receipt = run(entry)
            print(entry['id'], receipt['outcome'])
        return 0
    return 2


if __name__ == '__main__':
    sys.path.insert(0, str(ROOT / 'tools'))
    sys.exit(main())
