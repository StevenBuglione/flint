#!/usr/bin/env python3
"""Produce actual build/size evidence; absent implementations or probes fail closed.

Measurements run sequentially on the dedicated Linux x86-64 performance runner, or on the macOS arm64
runner (ADR-025), where LDC's ldmd2 fills the dev profile's DMD role until DMD arm64 lands (ADR-024).
Cold means source/build-cache cold with prebuilt toolchain runtimes and native C
libraries already prepared. It does not mean dropping the OS page cache.

--apps-only measures ADR-025's compile-speed gate on any tier-1 host, Windows
included: the development builds of bench-cli and bench-rest and the Go
references, cold and incremental, with the same method and statistics.
"""
from __future__ import annotations
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

import module_budgets
import profiles

ROOT = Path(__file__).resolve().parents[1]
# How template instances are counted: version 2 traces the package's own `-lib` compile as well as `-c` compiles
# (ADR-019: "own library and probe"). Counts of different versions are not comparable; gates.py refuses to.
TEMPLATE_COUNT_METHOD = 'own-library-and-probe/2'
NATIVE_BLOCK = re.compile(r'\n// BEGIN FLINT NATIVE\n.*?// END FLINT NATIVE\n', re.S)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run_checked(command, cwd, env=None):
    result = subprocess.run([str(x) for x in command], cwd=cwd, env=env,
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('command failed: ' + json.dumps([str(x) for x in command]) + '\n' + result.stdout + result.stderr)
    return result


PAGE_BYTES = os.sysconf('SC_PAGE_SIZE') if hasattr(os, 'sysconf') else None


def process_tree_rss(root, floor):
    """Resident bytes of `root` and its live descendants, as psutil's memory_info().rss reports them.

    Linux allocates PIDs in increasing order until they wrap, so a measured build's descendants have PIDs
    at or above `floor`, the build's own PID; only those `/proc/<pid>/stat` files are read. Scanning every
    process on the host each millisecond (psutil's children(recursive=True)) took enough CPU from the
    measured build to lengthen it: 9 ms of a 94 ms parallel DMD build and 5 ms of a 110 ms Go build. Pass
    `floor=0` after a PID wrap to scan everything.
    """
    parent = {}
    resident = {}
    for name in os.listdir('/proc'):
        if not name.isdigit() or int(name) < floor:
            continue
        try:
            with open('/proc/' + name + '/stat', 'rb') as stream:
                stat = stream.read()
        except OSError:
            continue
        # Fields after the parenthesised command: state, ppid, ..., rss (field 24) at index 21.
        fields = stat[stat.rindex(b')') + 2:].split()
        pid = int(name)
        parent[pid] = int(fields[1])
        resident[pid] = int(fields[21]) * PAGE_BYTES
    total = 0
    for pid, rss in resident.items():
        ancestor = pid
        while ancestor in parent and ancestor != root:
            ancestor = parent[ancestor]
        if ancestor == root:
            total += rss
    return total


if sys.platform == 'darwin':
    import ctypes

    _LIBPROC = ctypes.CDLL('/usr/lib/libproc.dylib')
    _PROC_PIDTASKINFO = 4

    class _TaskInfo(ctypes.Structure):
        # struct proc_taskinfo (<sys/proc_info.h>): virtual and resident sizes, then 80 more bytes.
        _fields_ = [('virtual_size', ctypes.c_uint64), ('resident_size', ctypes.c_uint64),
                    ('rest', ctypes.c_uint8 * 80)]

    def process_tree_rss(root, floor):
        """Resident bytes of `root` and its live descendants, from libproc's task info, which is the value
        psutil reports as memory_info().rss on macOS. Only the tree is walked; `floor` is unused."""
        total = 0
        pending = [root]
        children = (ctypes.c_int * 1024)()
        info = _TaskInfo()
        while pending:
            pid = pending.pop()
            if _LIBPROC.proc_pidinfo(pid, _PROC_PIDTASKINFO, ctypes.c_uint64(0), ctypes.byref(info),
                                     ctypes.sizeof(info)) == ctypes.sizeof(info):
                total += info.resident_size
            count = _LIBPROC.proc_listchildpids(pid, children, ctypes.sizeof(children))
            pending.extend(children[i] for i in range(max(0, min(count, len(children)))) if children[i] > 0)
        return total


class WindowsJob:
    """A job object holding a build's process tree on Windows, for its kernel-tracked peak memory.

    Windows has no /proc. The job records the peak committed memory of every process in it, so nothing is
    sampled while the build runs. Processes that break away from the job, such as the DMD compile server's
    warm workers, are not counted, just as the Linux sampler does not count the forked server's workers."""
    EXTENDED_LIMIT_INFORMATION = 9

    def __init__(self):
        import ctypes
        from ctypes import wintypes
        self.ctypes = ctypes
        self.kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
        self.kernel32.CreateJobObjectW.restype = wintypes.HANDLE
        self.kernel32.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
        self.kernel32.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
        self.kernel32.QueryInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p,
                                                            wintypes.DWORD, ctypes.c_void_p]
        self.kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
        self.handle = self.kernel32.CreateJobObjectW(None, None)
        if not self.handle:
            raise RuntimeError('CreateJobObjectW failed: ' + str(ctypes.get_last_error()))

    def assign(self, process):
        if not self.kernel32.AssignProcessToJobObject(self.handle, int(process._handle)):
            raise RuntimeError('AssignProcessToJobObject failed: ' + str(self.ctypes.get_last_error()))

    def peak_bytes(self):
        ctypes = self.ctypes
        # JOBOBJECT_EXTENDED_LIMIT_INFORMATION: the basic limits (64 bytes on x64), I/O counters (48 bytes),
        # then ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed and PeakJobMemoryUsed.
        buffer = (ctypes.c_uint64 * 18)()
        if not self.kernel32.QueryInformationJobObject(self.handle, self.EXTENDED_LIMIT_INFORMATION, buffer,
                                                       ctypes.sizeof(buffer), None):
            raise RuntimeError('QueryInformationJobObject failed: ' + str(ctypes.get_last_error()))
        return int(buffer[17])

    def close(self):
        self.kernel32.CloseHandle(self.handle)


def timed_windows_process(command, cwd, env, log_path):
    """Windows counterpart of timed_process: wall time and the job's peak committed memory."""
    job = WindowsJob()
    try:
        start = time.perf_counter_ns()
        with open(log_path, 'wb') as log:
            process = subprocess.Popen([str(x) for x in command], cwd=cwd, env=env,
                                       stdout=log, stderr=subprocess.STDOUT)
            # DUB starts its first child only after loading the project, well after this assignment.
            job.assign(process)
            exit_code = process.wait()
        elapsed = (time.perf_counter_ns() - start) / 1e9
        peak = job.peak_bytes()
    finally:
        job.close()
    if exit_code:
        raise RuntimeError('build failed: ' + str(command) + '\n' + Path(log_path).read_text(errors='replace')[-20000:])
    if peak <= 0:
        raise RuntimeError('no peak memory reported; measurement is incomplete')
    return {'seconds': elapsed, 'peak_rss_bytes': peak,
            'command': [str(x) for x in command], 'exit_code': exit_code,
            'log_sha256': digest(log_path),
            'memory_method': 'peak committed memory of the build\'s job object, tracked by the kernel'}


def timed_process(command, cwd, env, log_path):
    if sys.platform == 'win32':
        return timed_windows_process(command, cwd, env, log_path)
    peak = 0
    start = time.perf_counter_ns()
    with open(log_path, 'wb') as log:
        process = subprocess.Popen([str(x) for x in command], cwd=cwd, env=env,
                                   stdout=log, stderr=subprocess.STDOUT)
        floor = process.pid
        while process.poll() is None:
            # A PID wrap during the build hands out numbers below the root's; scan every process from then on.
            if floor and sys.platform == 'linux':
                try:
                    with open('/proc/sys/kernel/ns_last_pid') as stream:
                        if int(stream.read()) < floor:
                            floor = 0
                except OSError:
                    floor = 0
            peak = max(peak, process_tree_rss(process.pid, floor))
            time.sleep(.001)
        exit_code = process.wait()
    elapsed = (time.perf_counter_ns() - start) / 1e9
    if exit_code:
        raise RuntimeError('build failed: ' + str(command) + '\n' + Path(log_path).read_text(errors='replace')[-20000:])
    if peak <= 0:
        raise RuntimeError('no RSS sample obtained; measurement is incomplete')
    return {'seconds': elapsed, 'peak_rss_bytes': peak,
            'command': [str(x) for x in command], 'exit_code': exit_code,
            'log_sha256': digest(log_path),
            'memory_method': 'sum of process-tree RSS sampled every 1 ms; sampling can miss shorter peaks'}


def template_instances(text):
    counts = [int(n) for n in re.findall(r'vtemplate:\s+(\d+)\s+\(\d+\s+distinct\)\s+instantiation\(s\)', text)]
    return sum(counts)


def package_template_instances(records, name, directory=None):
    """Instantiations in the compiler invocations that compile this package's own modules or probe.

    Dependency libraries are compiled in separate invocations and counted under their own packages;
    counting them here again would charge every dependent for the same druntime instantiations (ADR-019).
    `records` are the instrumented wrapper's invocation receipts; their streams sit beside them.
    """
    marker = os.sep + os.path.normpath(directory or ('packages/' + name)) + os.sep
    total = 0
    for record in sorted(records):
        invocation = json.loads(record.read_text())
        sources = [os.path.normpath(os.path.join(invocation['cwd'], value))
                   for value in invocation['expanded_arguments'] if value.endswith('.d')]
        if any(marker in source for source in sources):
            total += template_instances(''.join((record.parent / invocation[stream]).read_text(errors='replace')
                                                for stream in ('stdout', 'stderr')))
    return total


def copy_workspace(destination):
    def ignore(directory, names):
        # .flint holds flint's local state (fixture peers, Conan cache, build outputs), never a build input.
        excluded = {'.git', '.dub', '.dub-home', '.ci-dub-home', '.tools', '.native',
                    '.native-sanitized', '.flint', '__pycache__'}
        if Path(directory).resolve() == ROOT:
            excluded |= {'artifacts', 'build'}
        return [name for name in names if name in excluded]
    shutil.copytree(ROOT, destination, ignore=ignore)


def edit_source_path(root, relative):
    path = root / relative
    alternate = path.parent / path.stem / 'package.d' if path.name != 'package.d' else path.parent.with_suffix('.d')
    if not path.is_file() and alternate.is_file():
        path = alternate
    if not path.is_file():
        raise RuntimeError('incremental edit source missing: ' + str(path))
    return path


def source_edit(root, relative, iteration):
    path = edit_source_path(root, relative)
    with path.open('a', encoding='utf-8') as output:
        output.write('\nprivate enum uint __flint_measure_edit_' + str(iteration) + ' = ' + str(iteration) + ';\n')
    return str(path.relative_to(root))


def native_profiles(lld=None):
    # Flags come from the canonical profiles shared with flint and tools/ci.py (ADR-018).
    linker = ['-linker=' + lld] if lld else []
    policy = profiles.load()
    return {
        'dmd': list(policy['dev']['dflags']) + profiles.link_dflags('dev'),
        'O3': list(policy['release']['dflags']) + profiles.link_dflags('release') + linker,
        'Oz': list(policy['size']['dflags']) + profiles.link_dflags('size') + linker}


def dub_invocation(dub, workspace, relative, compiler, flags, base_env):
    env = base_env.copy()
    env['DUB_HOME'] = str(workspace / '.dub-home')
    env['DFLAGS'] = shlex.join(flags)
    # DUB 1.43 retains debug build-type flags despite DFLAGS. Plain plus explicit
    # flags was verified from actual compiler argv. --cache=local does NOT isolate
    # DUB's build cache; DUB_HOME does, and remains the same for the edited rebuild.
    return [dub, 'build', '--compiler=' + str(compiler), '--build=plain', '--skip-registry=all'], workspace / relative, env


def instrumented_compiler(directory, compiler, traces):
    """One real DMD trace per compilation, avoiding shared trace-file overwrite."""
    wrapper = directory / 'instrumented-dmd'
    if traces.exists():
        shutil.rmtree(traces)
    traces.mkdir(parents=True)
    script = '''#!/usr/bin/env python3
import json, os, pathlib, shlex, subprocess, sys, uuid
compiler = COMPILER
traces = pathlib.Path(TRACES)
args = sys.argv[1:]
responses = []
def expand(values, depth=0):
    if depth > 8:
        raise SystemExit('compiler response nesting exceeded')
    result = []
    for value in values:
        if value.startswith('@') and pathlib.Path(value[1:]).is_file():
            path = pathlib.Path(value[1:])
            text = path.read_text(encoding='utf-8-sig')
            responses.append((str(path), text))
            result.extend(expand(shlex.split(text), depth + 1))
        else:
            result.append(value)
    return result
expanded = expand(args)
# DUB compiles a library target in one `-lib` invocation (compile and archive, no `-c`); ADR-019 counts the
# package's own library as well as its probe, so both kinds are traced.
if not ('-c' in expanded or '-lib' in expanded) or any('dub_platform_probe_' in value for value in expanded):
    os.execv(compiler, [compiler] + args)
identity = uuid.uuid4().hex
trace = traces / (identity + '.trace.json')
command = [compiler] + args + ['-vtemplates=list-instances', '-ftime-trace', '-ftime-trace-file=' + str(trace)]
response_files = []
for index, (original, text) in enumerate(responses):
    retained = traces / (identity + '-' + str(index) + '.response.txt')
    retained.write_text(text)
    response_files.append({'original': original, 'retained': retained.name})
result = subprocess.run(command, capture_output=True)
stdout = traces / (identity + '.stdout.txt')
stderr = traces / (identity + '.stderr.txt')
stdout.write_bytes(result.stdout)
stderr.write_bytes(result.stderr)
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
(traces / (identity + '.invocation.json')).write_text(json.dumps({'command': command, 'expanded_arguments': expanded, 'response_files': response_files, 'exit_code': result.returncode, 'trace': trace.name, 'stdout': stdout.name, 'stderr': stderr.name, 'cwd': os.getcwd()}) + '\\n')
raise SystemExit(result.returncode)
'''.replace('COMPILER', repr(str(compiler))).replace('TRACES', repr(str(traces)))
    wrapper.write_text(script)
    wrapper.chmod(0o755)
    return wrapper


def wasm_command(compiler, workspace, fixture, packages, profile, target):
    imports = ['-I' + str(workspace / 'packages' / p / 'source')
               for p, meta in packages.items() if meta['better_c']]
    source_dir = workspace / fixture['fixture'] / 'source'
    sources = sorted(source_dir.rglob('*.d'))
    return [compiler, '-betterC', '-preview=dip1000', '-mtriple=wasm32-unknown-unknown-wasm',
            '-mattr=+bulk-memory', '-' + profile, '-release', '-boundscheck=safeonly',
            '-checkaction=halt', '-link-internally', '-i=flint', '-L--no-entry',
            '-L--export-memory', '-of=' + str(target), '-I' + str(source_dir)] + [
                '-L--export=' + symbol for symbol in fixture['exports']] + imports + [str(p) for p in sources]


def native_profile_hash(blocks, prefix):
    normalized = {name: block.replace(str(prefix), '<native-install>') for name, block in blocks.items()}
    return hashlib.sha256(json.dumps(normalized, sort_keys=True).encode()).hexdigest()


def host_native_target():
    """The native install target of this host, as tools/native_build.py names it."""
    if sys.platform == 'win32':
        return 'windows-x86_64'
    if sys.platform == 'darwin':
        return 'macos-arm64'
    return 'linux-aarch64-glibc' if os.uname().machine in ('aarch64', 'arm64') else 'linux-x86_64-glibc'


def source_identity(root):
    """Reject uncommitted code; allow only exactly verified generated native flags."""
    commit = run_checked(['git', 'rev-parse', 'HEAD'], root).stdout.strip()
    run_checked(['git', 'diff', '--cached', '--quiet'], root)
    untracked = run_checked(['git', 'ls-files', '--others', '--exclude-standard', '-z'], root).stdout
    if untracked:
        raise RuntimeError('untracked inputs would invalidate commit identity: ' + untracked.replace('\0', ', '))
    changed = run_checked(['git', 'diff', '--name-only', '--relative', 'HEAD', '--'], root).stdout.splitlines()
    prefix = run_checked(['git', 'rev-parse', '--show-prefix'], root).stdout.strip()
    native = None
    expected = {}
    target = host_native_target()
    receipt_path = root / '.native/install' / target / 'flint-native-install.json'
    if receipt_path.is_file():
        import native_build
        args = argparse.Namespace(work_dir=root / '.native', target=target,
                                  prefix=None, cc=None, cxx=None, sanitize=None, phase='build')
        builder = native_build.Builder(args, json.loads((root / 'policy/native-lock.json').read_text()))
        expected = builder.dub_recipe_blocks()  # Rehashes every referenced installed archive.
        if builder.receipt.get('sanitizers'):
            raise RuntimeError('performance cannot reuse a sanitizer-instrumented native install')
        native = {'receipt': str(receipt_path), 'sha256': digest(receipt_path),
                  'features': sorted(builder.receipt['libraries']),
                  'generated_blocks': {name: hashlib.sha256(block.encode()).hexdigest()
                                       for name, block in expected.items()},
                  'profile_sha256': native_profile_hash(expected, builder.prefix),
                  'prepared_dependency_policy': 'verified immutable installed C archives shared across source-cache-cold trials'}
    for relative in changed:
        if relative not in expected:
            raise RuntimeError('uncommitted source modification: ' + relative)
        text = (root / relative).read_text()
        if NATIVE_BLOCK.findall(text) != [expected[relative]]:
            raise RuntimeError('native recipe block differs from verified installed dependency receipt: ' + relative)
        original = run_checked(['git', 'show', 'HEAD:' + prefix + relative], root).stdout
        if relative == 'packages/engine-rpc/dub.sdl':
            # The unittest-only generated codec is a separate receipt-bound
            # section and does not appear in the production linker block.
            original = builder.emit_rpc_test_archive(original)
        if text != original.rstrip() + '\n' + expected[relative]:
            raise RuntimeError('non-generated recipe modification: ' + relative)
    # Every provider expected by the native preparation must be enabled exactly.
    for relative, block in expected.items():
        path = root / relative
        if NATIVE_BLOCK.findall(path.read_text()) != [block]:
            raise RuntimeError('run native_build.py --emit-dub before measuring: ' + str(path))
    return commit, native


def workload_digest(root, path, native_inputs):
    relative = str(path.relative_to(root))
    expected = native_inputs['generated_blocks'].get(relative) if native_inputs else None
    if expected is None:
        return digest(path)
    text = path.read_text()
    blocks = NATIVE_BLOCK.findall(text)
    if len(blocks) != 1 or not text.endswith(blocks[0]) or hashlib.sha256(blocks[0].encode()).hexdigest() != expected:
        raise RuntimeError('native benchmark flags changed during measurement: ' + relative)
    # Only the already-verified generated flags are path-dependent.
    return hashlib.sha256((NATIVE_BLOCK.sub('\n', text).rstrip() + '\n').encode()).hexdigest()


def stripped_size(target, strip, readelf, workspace, log):
    if sys.platform == 'darwin':
        return stripped_size_macho(target, strip, readelf, workspace, log)
    strip_command = [strip, '--strip-all', target]
    run_checked(strip_command, workspace)
    audit_command = [readelf, '--wide', '--dynamic', target]
    audit = run_checked(audit_command, workspace)
    needed = sorted(set(re.findall(r'\(NEEDED\).*?\[([^]]+)\]', audit.stdout)))
    # The designated Linux profile ships static D/C dependencies. Only the
    # installed system runtime may remain dynamic; a new desktop/system backend
    # must explicitly extend this reviewed policy or provide a closure measure.
    system = {'libc.so.6', 'libm.so.6', 'libdl.so.2', 'libpthread.so.0', 'librt.so.1', 'libutil.so.1',
              'libgcc_s.so.1', 'libstdc++.so.6', 'libatomic.so.1', 'ld-linux-x86-64.so.2'}
    if set(needed) - system:
        raise RuntimeError('uncounted shared dependency; static profile or full closure measurement required: ' + str(needed))
    sections_command = [readelf, '--wide', '--sections', target]
    sections = run_checked(sections_command, workspace)
    with log.open('a', encoding='utf-8') as output:
        output.write('\n' + json.dumps({'strip_command': [str(x) for x in strip_command],
                                       'audit_command': [str(x) for x in audit_command],
                                       'sections_command': [str(x) for x in sections_command]}) + '\n' + audit.stdout
                     + audit.stderr + sections.stdout + sections.stderr)
    return {'binary_bytes': target.stat().st_size, 'loadable_bytes': elf_loadable_bytes(sections.stdout),
            'sha256': digest(target), 'dynamic_system_dependencies': needed, 'log_sha256': digest(log)}


def elf_loadable_bytes(listing):
    """The bytes a program occupies once loaded: the sum of its allocated (SHF_ALLOC, flag A) sections from
    `readelf --wide --sections`, .bss included and the thread-local template .tbss left out (it is per thread).
    Unlike the file size it is not rounded to pages, so a module's marginal cost reads as what it adds (decisions.md
    2026-11-26 01:20Z: incremental_linked_bytes measures loadable section bytes)."""
    total = 0
    for line in listing.splitlines():
        match = re.match(r'\s*\[\s*\d+\]\s+(.*)$', line)
        if not match:
            continue
        fields = match.group(1).split()
        # name type address offset size entsize [flags] link info align
        if len(fields) != 10 or fields[0] == '.tbss':
            continue
        if 'A' in fields[6]:
            total += int(fields[4], 16)
    return total


def macho_loadable_bytes(listing):
    """The Mach-O counterpart of elf_loadable_bytes: the sizes of every section `otool -l` lists (zero-fill included,
    thread-local zero-fill left out)."""
    total, name = 0, None
    for line in listing.splitlines():
        words = line.split()
        if len(words) == 2 and words[0] == 'sectname':
            name = words[1]
        elif len(words) == 2 and words[0] == 'size' and name is not None:
            if name != '__thread_bss':
                total += int(words[1], 16)
            name = None
    return total


def stripped_size_macho(target, strip, otool, workspace, log):
    """Mach-O: Apple strip removes every symbol of an executable, and otool -L lists its dylibs."""
    strip_command = [strip, target]
    run_checked(strip_command, workspace)
    audit_command = [otool, '-L', target]
    audit = run_checked(audit_command, workspace)
    needed = sorted(line.strip().split(' (')[0] for line in audit.stdout.splitlines()[1:] if line.strip())
    # Only the operating system's own libraries and frameworks may remain dynamic (ADR-021 section 4).
    unexpected = [name for name in needed if not name.startswith(('/usr/lib/', '/System/Library/Frameworks/'))]
    if unexpected:
        raise RuntimeError('uncounted shared dependency; static profile or full closure measurement required: '
                           + str(unexpected))
    sections_command = [otool, '-l', target]
    sections = run_checked(sections_command, workspace)
    with log.open('a', encoding='utf-8') as output:
        output.write('\n' + json.dumps({'strip_command': [str(x) for x in strip_command],
                                       'audit_command': [str(x) for x in audit_command],
                                       'sections_command': [str(x) for x in sections_command]}) + '\n' + audit.stdout
                     + audit.stderr + sections.stdout + sections.stderr)
    return {'binary_bytes': target.stat().st_size, 'loadable_bytes': macho_loadable_bytes(sections.stdout),
            'sha256': digest(target), 'dynamic_system_dependencies': needed, 'log_sha256': digest(log)}


def go_compile_gate_trials(go, name, source, go_env, temporary, logs, result):
    """Go's cold and incremental builds for the compile-speed gate: a fresh copy of the reference app and a fresh
    clone of the standard-library-primed cache per trial, then the same app rebuilt after appending a declaration
    to main.go, as the D app's edit source is edited."""
    cold, incremental = [], []
    go_build = [go, 'build', '-buildvcs=false', '-trimpath']
    for iteration in range(9):
        work = temporary / (name + '-' + str(iteration))
        shutil.copytree(source, work, ignore=shutil.ignore_patterns('.git', 'build'))
        cache = temporary / (name + '-cache-' + str(iteration))
        shutil.copytree(temporary / 'prime', cache, copy_function=os.link)
        env = go_env.copy(); env['GOCACHE'] = str(cache)
        command = go_build + ['-ldflags=-s -w', '-o', work / 'reference', '.']
        for state in ['cold', 'incremental']:
            if state == 'incremental':
                with (work / 'main.go').open('a', encoding='utf-8') as output:
                    output.write('\nconst flintMeasureEdit' + str(iteration) + ' = ' + str(iteration) + '\n')
            logfile = logs / f'{name}-go-{state}-{iteration}.log'
            measured = timed_process(command, work, env, logfile)
            (cold if state == 'cold' else incremental).append(measured['seconds'])
            result['trials'].append(dict(measured, fixture=name, profile='go', state=state, trial=iteration,
                                         log=str(logfile.relative_to(logs.parent))))
    return cold, incremental


def measure_compile_gate(args, manifest, result, measured_native, go_sources, base_env, logs):
    """ADR-025 section 1: the development builds of the apps against Go on the same machine, cold and
    incremental, each ratio's median and bootstrap 99% upper bound at most 0.99."""
    from perf_stats import median_ratio_interval
    result['mode'] = 'compile-gate'
    result['host'] = {'platform': sys.platform, 'machine': __import__('platform').machine(), 'cpus': os.cpu_count()}
    apps = args.app or ['bench-cli', 'bench-rest']
    for name in apps:
        print('Measuring app', name, flush=True)
        row = measured_native(name, manifest['apps'][name], apps_only=True)
        row.pop('compiler_peak_rss_bytes')
        result['apps'][name] = row
    go_env = base_env.copy()
    go_env.update({'GOTOOLCHAIN': 'local', 'GOPROXY': 'off', 'GOSUMDB': 'off', 'GOWORK': 'off', 'CGO_ENABLED': '0'})
    with tempfile.TemporaryDirectory(prefix='flint-go-') as temporary:
        temporary = Path(temporary); (temporary / 'prime').mkdir()
        run_checked([args.go, 'build', '-buildvcs=false', '-trimpath', 'std'], ROOT,
                    dict(go_env, GOCACHE=str(temporary / 'prime')))
        for name in apps:
            cold, incremental = go_compile_gate_trials(args.go, name, go_sources[name], go_env, temporary, logs, result)
            result['go']['apps'][name] = {'cold_seconds': cold, 'incremental_seconds': incremental}
    verdicts = {}
    for name in apps:
        for state in ['cold', 'incremental']:
            median, lower, upper = median_ratio_interval(result['apps'][name]['dmd_' + state + '_seconds'],
                                                         result['go']['apps'][name][state + '_seconds'])
            verdicts[name + ' ' + state] = {'median_ratio': median, 'lower_99': lower, 'upper_99': upper,
                                            'pass': median <= .99 and upper <= .99}
    result['compile_gate'] = {'ceiling': .99, 'ratios': verdicts,
                              'pass': set(apps) == {'bench-cli', 'bench-rest'} and all(v['pass'] for v in verdicts.values())}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    for label, verdict in verdicts.items():
        print(f"{label}: median ratio {verdict['median_ratio']:.3f}, 99% upper {verdict['upper_99']:.3f}",
              'pass' if verdict['pass'] else 'FAIL')
    print('Wrote compile-gate evidence', args.output, '(gate', 'passes)' if result['compile_gate']['pass'] else 'fails)')
    return 0


def pinned_workspace(path):
    """Each repo's commit in the measured workspace (plan section 7). A workspace whose checkouts are not all this
    checkout cannot be measured yet: the probes' recipes reach their packages through this checkout's root
    dub.sdl until the split rewrites them."""
    sys.path.insert(0, str(ROOT / 'tools'))
    from workspace import Workspace, repo_policy
    workspace = Workspace(path)
    problems = workspace.verify()
    if problems:
        raise RuntimeError('workspace: ' + '; '.join(problems))
    if workspace.file and {checkout for checkout, _ in workspace.checkouts.values()} != {ROOT}:
        raise RuntimeError('measure_builds measures one checkout until the split rewrites the probes\' recipes '
                           '(plan section 7, step 5); every checkout of this workspace must be ' + str(ROOT))
    head = run_checked(['git', 'rev-parse', 'HEAD'], ROOT).stdout.strip()
    return {repo: head for repo in sorted(repo_policy(ROOT)['repos'])}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=ROOT / 'policy/build-benchmarks.json')
    parser.add_argument('--output', type=Path, required=True)
    darwin = sys.platform == 'darwin'
    parser.add_argument('--dmd', default='ldmd2' if darwin else 'dmd',
                        help='the dev-profile compiler: the forked DMD, or ldmd2 on macOS (ADR-024)')
    parser.add_argument('--ldc', default='ldc2')
    parser.add_argument('--dub', default='dub')
    parser.add_argument('--go', default='go')
    parser.add_argument('--strip', default='strip')
    parser.add_argument('--readelf', default='otool' if darwin else 'readelf',
                        help='the dynamic-dependency audit tool: readelf, or otool on macOS')
    parser.add_argument('--lld', default=None, help='Optional external LLD22; default uses system cc/ld with bundled LLVMgold plugin')
    parser.add_argument('--apps-only', action='store_true',
                        help='ADR-025 compile-speed gate on any tier-1 host: dev builds of the apps and Go, cold and incremental')
    parser.add_argument('--app-sizes', action='store_true',
                        help='only the stripped O3 and Oz sizes of bench-cli and bench-rest')
    parser.add_argument('--framework-sizes', action='store_true',
                        help='only the linked bytes and template instances of the policy/framework.json modules')
    parser.add_argument('--framework-builds', action='store_true',
                        help='only the policy/framework.json modules, measured in full as packages are: nine cold and '
                             'edited DMD and LDC builds, compiler peak RSS, template instances and linked bytes')
    parser.add_argument('--framework', action='append',
                        help='with --framework-sizes or --framework-builds, measure only this module')
    parser.add_argument('--package-templates', action='store_true',
                        help='only the template instances (own library plus probe) of the policy/packages.json '
                             'packages, the input of their template budgets')
    parser.add_argument('--package', action='append', help='with --package-templates, measure only this package')
    parser.add_argument('--app', action='append', choices=['bench-cli', 'bench-rest'],
                        help='with --apps-only or --app-sizes, measure only this app (the gate needs both)')
    parser.add_argument('--spring', action='store_true',
                        help='the Spring side-by-side apps (benchmarks/spring, ADR-030 section 8): the Flint ports '
                             'against the registered Go comparators, both headlines, Java as context; see tools/spring_builds.py')
    parser.add_argument('--spring-app', action='append', help='with --spring, measure only this application')
    parser.add_argument('--trials', type=int, default=9, help='with --spring: trials per series (9 for evidence)')
    parser.add_argument('--smoke', action='store_true', help='with --spring: a short harness check, never evidence')
    parser.add_argument('--allow-missing-flint', action='store_true',
                        help='with --spring: record the Go and Java sides when a Flint port is missing (incomplete)')
    parser.add_argument('--no-context', action='store_true', help='with --spring: skip the Java context builds')
    parser.add_argument('--native-context', action='store_true',
                        help='with --spring: also build each Java reference as a GraalVM native image once (context)')
    parser.add_argument('--workspace', type=Path,
                        help='flint.workspace/1 file pinning each repo\'s checkout (plan section 7); default: this '
                             'monorepo. Its commits are recorded in the evidence.')
    args = parser.parse_args(argv)
    if args.spring:
        import spring_builds
        return spring_builds.measure(args, timed_process)
    workspace_commits = pinned_workspace(args.workspace)
    if args.app and not (args.apps_only or args.app_sizes):
        raise RuntimeError('--app applies only to --apps-only and --app-sizes')
    if sum((args.apps_only, args.app_sizes, args.framework_sizes, args.framework_builds, args.package_templates)) > 1:
        raise RuntimeError('--apps-only, --app-sizes, --framework-sizes, --framework-builds and --package-templates '
                           'are separate measurements')
    if args.framework and not (args.framework_sizes or args.framework_builds):
        raise RuntimeError('--framework applies only to --framework-sizes and --framework-builds')
    if args.package and not args.package_templates:
        raise RuntimeError('--package applies only to --package-templates')
    host = (sys.platform, os.uname().machine if hasattr(os, 'uname') else '')
    if not args.apps_only and host not in (('linux', 'x86_64'), ('darwin', 'arm64')):
        raise RuntimeError('measurement runners are Linux x86-64 and macOS arm64 (ADR-025); '
                           'cross-platform correctness uses its separate matrix')
    manifest = json.loads(args.manifest.read_text())
    packages = json.loads((ROOT / 'policy/packages.json').read_text())['packages']
    # --app-sizes builds only the apps, so it does not need every package's probes.
    if manifest['schema'] != 1 or (set(manifest['packages']) != set(packages) and not (args.app_sizes or args.framework_sizes or args.framework_builds)):
        raise RuntimeError('build manifest must specify every package of policy/packages.json')
    if manifest['samples'] != 9:
        raise RuntimeError('production build evidence requires exactly 9 samples')
    missing = []
    for name, fixture in manifest['packages'].items():
        if fixture.get('size_basis') != 'framework_over_provider_equivalent_baseline':
            raise RuntimeError('explicit provider-equivalent size basis required: ' + name)
        if not list((ROOT / 'packages' / name / 'source').rglob('*.d')):
            missing.append('runtime implementation ' + name)
        for key in ['fixture', 'baseline']:
            directory = ROOT / fixture[key]
            if not (directory / 'dub.sdl').is_file() or not (directory / 'source/app.d').is_file():
                missing.append(key + ' probe ' + str(directory.relative_to(ROOT)))
        try:
            edit_source_path(ROOT, fixture['edit_source'])
        except RuntimeError:
            missing.append('edit source ' + fixture['edit_source'])
    # ADR-030 section 5: the Spring-layer modules of policy/framework.json, each with its own budget and probe.
    import framework_budgets
    try:
        framework_fixtures = ({} if args.apps_only or args.app_sizes or args.package_templates else
                              framework_budgets.load(ROOT, require_budget=not args.framework_sizes))
        if (args.framework_sizes or args.framework_builds) and args.framework:
            unknown = sorted(set(args.framework) - set(framework_fixtures))
            if unknown:
                raise RuntimeError('--framework names modules without a probe: ' + ', '.join(unknown))
            framework_fixtures = {k: v for k, v in framework_fixtures.items() if k in args.framework}
    except ValueError as exc:
        missing.append(str(exc)); framework_fixtures = {}
    for name, fixture in framework_fixtures.items():
        if not list((ROOT / fixture['directory'] / 'source').rglob('*.d')):
            missing.append('runtime implementation ' + fixture['directory'])
        for key in ['fixture', 'baseline']:
            directory = ROOT / fixture[key]
            if not (directory / 'dub.sdl').is_file() or not (directory / 'source/app.d').is_file():
                missing.append(key + ' probe ' + str(directory.relative_to(ROOT)))
        try:
            edit_source_path(ROOT, fixture['edit_source'])
        except RuntimeError:
            missing.append('edit source ' + fixture['edit_source'])
    for name, fixture in manifest['apps'].items():
        if not (ROOT / fixture['source']).is_file():
            missing.append('app source ' + fixture['source'])
    go_sources = {}
    for name, fixture in manifest['go_apps'].items():
        source = (ROOT / fixture['directory']).resolve()
        if not (source / 'go.mod').is_file() or not list(source.glob('*.go')):
            missing.append('Go reference ' + str(source))
        go_sources[name] = source
    if missing:
        raise RuntimeError('Build measurement requires implemented benchmark fixtures:\n' + '\n'.join(missing))
    tools = {}
    required = ['dmd', 'dub', 'go'] if args.apps_only else ['dmd', 'ldc', 'dub', 'go', 'strip', 'readelf']
    if args.app_sizes or args.framework_sizes or args.package_templates:
        # The size-only modes build no Go reference.
        required.remove('go')
    for name in required + (['lld'] if args.lld else []):
        found = shutil.which(getattr(args, name))
        if not found:
            raise RuntimeError('required executable missing: ' + getattr(args, name))
        setattr(args, name, str(Path(found).resolve()))
        if darwin and name == 'strip':
            # Apple's strip has no version option; it ships with the cctools otool reports.
            command = [shutil.which('otool') or 'otool', '--version']
        else:
            command = [getattr(args, name), 'version' if name == 'go' else '--version']
        version = run_checked(command, ROOT).stdout
        tools[name] = {'sha256': digest(getattr(args, name)), 'version': version.strip()}
    if args.lld and not re.search(r'LLD\s+22\.', tools['lld']['version']):
        raise RuntimeError('LDC1.43 LLVM22 ThinLTO requires external LLD22 for these native profiles')
    for name in [] if args.apps_only else ['cc', 'ld']:
        executable=shutil.which(name)
        if not executable:raise RuntimeError('native compiler driver/linker missing: '+name)
        probe=run_checked([executable,'-v' if darwin and name=='ld' else '--version'],ROOT)
        tools[name]={'sha256':digest(executable),'version':(probe.stdout or probe.stderr).strip()}
    for name,path in [('ldc_config',Path(args.ldc).parent.parent/'etc/ldc2.conf'),
                      ('llvmgold_plugin',Path(args.ldc).parent.parent/'lib/LLVMgold-ldc.so')]:
        if path.is_file():tools[name]={'sha256':digest(path)}
    tools['measurement_protocol'] = {'version': 1, 'sha256': digest(__file__),
                                     'statistics_sha256': digest(ROOT / 'tools/perf_stats.py'),
                                     'profiles_sha256': digest(profiles.POLICY)}
    commit, native_inputs = source_identity(ROOT)
    args.output = args.output.resolve()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    logs = args.output.parent / 'build-logs'
    logs.mkdir(exist_ok=True)
    result = {'schema': 1, 'mode': 'production', 'commit': commit, 'template_count_method': TEMPLATE_COUNT_METHOD,
              'producer': 'tools/measure_builds.py', 'command': [sys.executable] + sys.argv,
              'exit_code': 0, 'toolchains': tools, 'manifest_sha256': digest(args.manifest),
              'native_inputs': native_inputs, 'workspace': workspace_commits,
              'packages': {}, 'modules': {}, 'framework': {}, 'apps': {}, 'go': {'apps': {}}, 'trials': [], 'size_trials': []}
    base_env = os.environ.copy()
    base_env.pop('DFLAGS', None)
    # A fully qualified LDC linker path is accepted by -linker; no shell is involved.
    native = native_profiles(args.lld)
    workload_files={}
    for name,fixture in manifest['packages'].items():
        for variant in ['fixture','baseline']:
            for path in sorted((ROOT/fixture[variant]).rglob('*')):
                if path.is_file() and (path.suffix in ('.d', '.c', '.h') or path.name=='dub.sdl') and '.dub' not in path.parts:
                    workload_files[str(path.relative_to(ROOT))]=workload_digest(ROOT, path, native_inputs)
    for fixture in framework_fixtures.values():
        for variant in ['fixture', 'baseline']:
            for path in sorted((ROOT / fixture[variant]).rglob('*')):
                if path.is_file() and (path.suffix in ('.d', '.c', '.h') or path.name == 'dub.sdl') and '.dub' not in path.parts:
                    workload_files[str(path.relative_to(ROOT))] = workload_digest(ROOT, path, native_inputs)
    for entry in module_budgets.load(json.loads((ROOT / 'policy/budgets.json').read_text()), packages, ROOT).values():
        for variant in ['fixture', 'baseline']:
            for path in sorted((ROOT / entry[variant]).rglob('*')):
                if path.is_file() and (path.suffix in ('.d', '.c', '.h') or path.name == 'dub.sdl') and '.dub' not in path.parts:
                    workload_files[str(path.relative_to(ROOT))] = workload_digest(ROOT, path, native_inputs)
    for name,fixture in manifest['apps'].items():
        for path in sorted((ROOT/fixture['fixture']).rglob('*')):
            if path.is_file() and (path.suffix=='.d' or path.name=='dub.sdl') and '.dub' not in path.parts:
                workload_files[str(path.relative_to(ROOT))]=digest(path)
    for name in ['micro', 'hot-gc']:
        for path in sorted((ROOT / 'benchmarks' / name).rglob('*')):
            if path.is_file() and (path.suffix in ['.d', '.json'] or path.name == 'dub.sdl') and '.dub' not in path.parts:
                workload_files[str(path.relative_to(ROOT))] = digest(path)
    for name,directory in go_sources.items():
        for path in sorted(directory.glob('*')):
            if path.is_file() and (path.suffix=='.go' or path.name in ['go.mod','go.sum']):
                workload_files['go/'+name+'/'+path.name]=digest(path)
    result['workload_sha256']=hashlib.sha256(json.dumps(workload_files,sort_keys=True).encode()).hexdigest()
    result['workload_files']=workload_files
    result['profiles'] = native
    def dub_command(workspace, relative, compiler, profile, extras=()):
        return dub_invocation(args.dub, workspace, relative, compiler,
                              native[profile] + list(extras), base_env)
    def binary(workspace, relative, compiler):
        env = base_env.copy(); env['DUB_HOME'] = str(workspace / '.dub-home')
        data = run_checked([args.dub, 'describe', '--compiler=' + compiler, '--skip-registry=all'], workspace / relative, env)
        description = json.loads(data.stdout)
        meta = next(p for p in description['packages'] if p['name'] == description['rootPackage'])
        path = (Path(meta['path']) / meta['targetPath'] / meta['targetFileName']).resolve()
        if not path.is_relative_to(workspace.resolve()) or not path.is_file():
            raise RuntimeError('DUB target missing or outside isolated workspace: ' + str(path))
        return path
    def measured_native(name, fixture, apps_only=False):
        row = {}; peaks = []
        compilers = [('dmd', args.dmd, 'dmd')] + ([] if apps_only else [('ldc', args.ldc, 'O3')])
        for label, compiler, profile in compilers:
            cold = []; incremental = []
            if label == 'dmd':
                # ADR-016: cold trials start with the toolchain compile server running for the measured flags,
                # as Go's start from a primed standard library, and the report states the first build without a
                # server. The server key includes each fixture's -version flags, so every fixture needs its own.
                # Record that first build with the server disabled, then let two unscored builds start the server
                # and pre-fork its workers before trial 0, so no trial overlaps server start-up.
                for attempt, server in enumerate(['0', '1', '1']):
                    with tempfile.TemporaryDirectory(prefix='flint-build-') as temporary:
                        workspace = Path(temporary) / 'workspace'; copy_workspace(workspace)
                        cmd, cwd, env = dub_command(workspace, fixture['fixture'], compiler, profile)
                        env['FLINT_DMD_SERVER'] = server
                        state = 'first' if attempt == 0 else 'prime'
                        logfile = logs / f'{name}-{label}-{state}-{attempt}.log'
                        observation = timed_process(cmd, cwd, env, logfile)
                        if attempt == 0:
                            row['dmd_first_build_seconds'] = observation['seconds']
                        observation.update({'fixture': name, 'profile': label, 'state': state, 'edited_source': None,
                                            'trial': attempt, 'log': str(logfile.relative_to(args.output.parent))})
                        result['trials'].append(observation)
            for iteration in range(9):
                with tempfile.TemporaryDirectory(prefix='flint-build-') as temporary:
                    workspace = Path(temporary) / 'workspace'; copy_workspace(workspace)
                    cmd, cwd, env = dub_command(workspace, fixture['fixture'], compiler, profile)
                    for state in ['cold', 'incremental']:
                        edited = None
                        if state == 'incremental':
                            edited = source_edit(workspace, fixture['edit_source'], iteration)
                        logfile = logs / f'{name}-{label}-{state}-{iteration}.log'
                        observation = timed_process(cmd, cwd, env, logfile)
                        (cold if state == 'cold' else incremental).append(observation['seconds'])
                        peaks.append(observation['peak_rss_bytes'])
                        observation.update({'fixture': name, 'profile': label, 'state': state,
                                            'edited_source': edited,
                                            'trial': iteration, 'log': str(logfile.relative_to(args.output.parent))})
                        result['trials'].append(observation)
            row[label + '_cold_seconds'] = cold
            row[label + '_incremental_seconds'] = incremental
        row['compiler_peak_rss_bytes'] = max(peaks)
        if apps_only:
            return row
        return templates(name, fixture, row)
    def templates(name, fixture, row):
        # Template statistics and time traces use a separate build; instrumentation
        # overhead is not included in developer-loop timing samples.
        with tempfile.TemporaryDirectory(prefix='flint-templates-') as temporary:
            workspace = Path(temporary) / 'workspace'; copy_workspace(workspace)
            traces = logs / (name + '-instrumentation')
            wrapper = instrumented_compiler(Path(temporary), args.dmd, traces)
            cmd, cwd, env = dub_command(workspace, fixture['fixture'], str(wrapper), 'dmd')
            # Count templates with one compiler invocation per target, as upstream DUB builds. The
            # Flint DUB pipeline splits targets into chunks sized by the host's hardware threads, and
            # every chunk re-instantiates the shared druntime templates, so a chunked count would
            # depend on the machine rather than on the code (ADR-017).
            env['FLINT_DUB_PIPELINE'] = '0'
            driver_log = logs / (name + '-instrumentation-driver.log')
            observation = timed_process(cmd, cwd, env, driver_log)
            # DUB may suppress successful compiler stdout if it did not itself
            # add -vtemplates. Preserve/reparse the actual compiler streams.
            log = logs / (name + '-templates.log')
            streams = sorted(traces.glob('*.stdout.txt')) + sorted(traces.glob('*.stderr.txt'))
            log.write_text(''.join(path.read_text(errors='replace') for path in streams))
            # ADR-019: the budget counts the package's own library and probe compiles; the whole build
            # closure, dependencies included, stays recorded for visibility.
            row['template_instances'] = package_template_instances(traces.glob('*.invocation.json'), name,
                                                                   fixture.get('directory'))
            row['template_instances_closure'] = template_instances(log.read_text(errors='replace'))
            row['template_receipt'] = {'command': observation['command'], 'log_sha256': digest(log),
                                       'log': str(log.relative_to(args.output.parent)),
                                       'zero_means': 'no vtemplate lines from an actual successful instrumented compiler invocation'}
            trace_files = list(traces.glob('*.trace.json'))
            invocations = list(traces.glob('*.invocation.json'))
            if not trace_files or len(invocations) != len(trace_files):
                raise RuntimeError('DMD did not emit one requested trace per compiler invocation: ' + str(traces))
            row['template_receipt']['artifacts'] = [
                {'artifact': str(path.relative_to(args.output.parent)), 'sha256': digest(path)}
                for path in sorted(trace_files + invocations + streams + list(traces.glob('*.response.txt')) + [driver_log])]
        return row
    if args.apps_only:
        return measure_compile_gate(args, manifest, result, measured_native, go_sources, base_env, logs)
    published = ROOT / 'build'; published.mkdir(exist_ok=True)
    def app_sizes(name, fixture, row):
        for profile in ['O3', 'Oz']:
            with tempfile.TemporaryDirectory(prefix='flint-app-size-') as temporary:
                workspace = Path(temporary) / 'workspace'; copy_workspace(workspace)
                cmd, cwd, env = dub_command(workspace, fixture['fixture'], args.ldc, profile)
                build = run_checked(cmd, cwd, env)
                logfile = logs / f'size-{name}-{profile}.log'
                logfile.write_text(json.dumps({'command': cmd, 'dflags': env['DFLAGS']}) + '\n' + build.stdout + build.stderr)
                target = binary(workspace, fixture['fixture'], args.ldc)
                measured_size = stripped_size(target, args.strip, args.readelf, workspace, logfile)
                row[profile] = {k: measured_size[k] for k in ['binary_bytes', 'sha256', 'dynamic_system_dependencies']}
                result['size_trials'].append(dict(measured_size, fixture=name, profile=profile,
                                                   variant='app', log=str(logfile.relative_to(args.output.parent))))
                shutil.copy2(target, published / (name if profile == 'O3' else name + '-Oz'))
        return row
    if args.app_sizes:
        # The release (O3) and size (Oz) profile sizes of the apps alone, for linker and toolchain levers.
        result['mode'] = 'app-sizes'
        for name in args.app or ['bench-cli', 'bench-rest']:
            print('Measuring app size', name, flush=True)
            result['apps'][name] = app_sizes(name, manifest['apps'][name], {})
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        for name, row in result['apps'].items():
            print(name, 'O3', row['O3']['binary_bytes'], 'Oz', row['Oz']['binary_bytes'])
        return 0
    def size_delta(name, fixture):
        """The larger O3/Oz difference in loadable bytes of a fixture over its baseline, and the sizes (each variant's
        loadable bytes, plus its stripped file size as `<variant>_file_bytes`)."""
        differences = []; sizes = {}
        for profile in ['O3', 'Oz']:
            sizes[profile] = {}
            for variant in ['fixture', 'baseline']:
                with tempfile.TemporaryDirectory(prefix='flint-size-') as temporary:
                    workspace = Path(temporary) / 'workspace'; copy_workspace(workspace)
                    cmd, cwd, env = dub_command(workspace, fixture[variant], args.ldc, profile)
                    build = run_checked(cmd, cwd, env)
                    logfile = logs / f'size-{name}-{profile}-{variant}.log'
                    logfile.write_text(json.dumps({'command': cmd, 'dflags': env['DFLAGS']}) + '\n' + build.stdout + build.stderr)
                    target = binary(workspace, fixture[variant], args.ldc)
                    measured_size = stripped_size(target, args.strip, args.readelf, workspace, logfile)
                    sizes[profile][variant] = measured_size['loadable_bytes']
                    sizes[profile][variant + '_file_bytes'] = measured_size['binary_bytes']
                    sizes[profile][variant + '_sha256'] = measured_size['sha256']
                    result['size_trials'].append(dict(measured_size, fixture=name, profile=profile,
                                                       variant=variant, log=str(logfile.relative_to(args.output.parent))))
            difference = sizes[profile]['fixture'] - sizes[profile]['baseline']
            sizes[profile]['signed_delta_bytes'] = difference
            differences.append(difference)
        return max(0, *differences), sizes
    if args.framework_builds:
        # The timed budget inputs of each framework module as well: what replaces the provisional compile-time and
        # compiler-RSS placeholders of policy/framework.json (framework_budgets.py apply).
        result['mode'] = 'framework-builds'
        for name, fixture in framework_fixtures.items():
            print('Measuring framework module', name, flush=True)
            row = measured_native(name, fixture)
            row['size_basis'] = fixture['size_basis']
            row['incremental_linked_bytes'], row['size_detail'] = size_delta(name, fixture)
            result['framework'][name] = row
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        for name, row in result['framework'].items():
            print(name, 'dmd cold', round(statistics.median(row['dmd_cold_seconds']), 3), 'ldc cold',
                  round(statistics.median(row['ldc_cold_seconds']), 3), 'rss', row['compiler_peak_rss_bytes'],
                  'templates', row['template_instances'], 'linked', row['incremental_linked_bytes'])
        return 0
    if args.framework_sizes:
        # The deterministic budget inputs of each framework module: linked bytes and template instances.
        result['mode'] = 'framework-sizes'
        result['framework_unprobed'] = sorted(set(framework_budgets.modules(ROOT)) - set(framework_fixtures))
        if result['framework_unprobed'] and not args.framework:
            print('No probe yet, not measured:', ', '.join(result['framework_unprobed']), flush=True)
        for name, fixture in framework_fixtures.items():
            print('Measuring framework module size and templates', name, flush=True)
            row = {'size_basis': fixture['size_basis']}
            row['incremental_linked_bytes'], row['size_detail'] = size_delta(name, fixture)
            result['framework'][name] = templates(name, fixture, row)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        for name, row in result['framework'].items():
            print(name, 'linked', row['incremental_linked_bytes'], 'templates', row['template_instances'])
        return 0
    if args.package_templates:
        # The template budget input of each package alone (owner decision 3 resets the budgets from it).
        result['mode'] = 'package-templates'
        unknown = sorted(set(args.package or ()) - set(manifest['packages']))
        if unknown:
            raise SystemExit('not a measured package: ' + ', '.join(unknown))
        for name in args.package or list(manifest['packages']):
            print('Measuring package templates', name, flush=True)
            result['packages'][name] = templates(name, manifest['packages'][name], {})
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        for name, row in result['packages'].items():
            print(name, 'templates', row['template_instances'])
        return 0
    for name, fixture in manifest['packages'].items():
        print('Measuring package', name, flush=True)
        row = measured_native(name, fixture)
        row['size_basis'] = fixture['size_basis']
        row['incremental_linked_bytes'], row['size_detail'] = size_delta(name, fixture)
        result['packages'][name] = row
    result['framework'] = {}
    for name, fixture in framework_fixtures.items():
        print('Measuring framework module', name, flush=True)
        row = measured_native(name, fixture)
        row['size_basis'] = fixture['size_basis']
        row['incremental_linked_bytes'], row['size_detail'] = size_delta(name, fixture)
        result['framework'][name] = row
    # Per-module linked-bytes budgets (policy/budgets.json module_linked_bytes), measured as packages are.
    for module, entry in module_budgets.load(json.loads((ROOT / 'policy/budgets.json').read_text()),
                                             packages, ROOT).items():
        print('Measuring module', module, flush=True)
        incremental, sizes = size_delta(module, entry)
        result['modules'][module] = {'incremental_linked_bytes': incremental, 'size_detail': sizes}
    for name in ['bench-cli', 'bench-rest']:
        print('Measuring app', name, flush=True)
        row = measured_native(name, manifest['apps'][name])
        row.pop('compiler_peak_rss_bytes'); row.pop('template_instances'); row.pop('template_receipt')
        result['apps'][name] = app_sizes(name, manifest['apps'][name], row)
    wasm = manifest['apps']['bench-wasm']
    wasm_row = {'ldc_cold_seconds': [], 'ldc_incremental_seconds': []}
    for profile in ['O3', 'Oz']:
        for iteration in range(9 if profile == 'O3' else 1):
            with tempfile.TemporaryDirectory(prefix='flint-wasm-') as temporary:
                workspace = Path(temporary) / 'workspace'; copy_workspace(workspace)
                target = workspace / 'bench.wasm'
                command = wasm_command(args.ldc, workspace, wasm, packages, profile, target)
                for state in (['cold', 'incremental'] if profile == 'O3' else ['cold']):
                    edited = None
                    if state == 'incremental':
                        edited = source_edit(workspace, wasm['edit_source'], iteration)
                    logfile = logs / f'wasm-{profile}-{state}-{iteration}.log'
                    observation = timed_process(command, workspace, base_env, logfile)
                    if profile == 'O3':
                        wasm_row['ldc_' + state + '_seconds'].append(observation['seconds'])
                    result['trials'].append(dict(observation, fixture='bench-wasm', profile=profile,
                                                state=state, trial=iteration, edited_source=edited,
                                                log=str(logfile.relative_to(args.output.parent))))
                    if state == 'cold' and iteration == 0:
                        data = target.read_bytes()
                        if data[:4] != b'\0asm':
                            raise RuntimeError('WASM compiler output has wrong magic')
                        wasm_row[profile] = {'raw_bytes': len(data), 'gzip_bytes': len(gzip.compress(data, compresslevel=9, mtime=0)), 'sha256': digest(target)}
                        shutil.copy2(target, published / ('bench.wasm' if profile == 'O3' else 'bench-wasm-Oz.wasm'))
    result['apps']['bench-wasm'] = wasm_row
    # Prime the Go stdlib with the same compile flags as the app. Each app trial
    # gets a fresh clone of that cache and compiles its own objects.
    go_env = base_env.copy()
    go_env.update({'GOTOOLCHAIN': 'local', 'GOPROXY': 'off', 'GOSUMDB': 'off', 'GOWORK': 'off', 'CGO_ENABLED': '0'})
    with tempfile.TemporaryDirectory(prefix='flint-go-') as temporary:
        temporary = Path(temporary); prime = temporary / 'prime'; prime.mkdir()
        go_env['GOCACHE'] = str(prime)
        go_build = [args.go, 'build', '-buildvcs=false', '-trimpath']
        run_checked(go_build + ['std'], ROOT, go_env)
        for name, source in go_sources.items():
            samples = []; last_binary = None
            for iteration in range(9):
                work = temporary / (name + '-' + str(iteration))
                shutil.copytree(source, work, ignore=shutil.ignore_patterns('.git', 'build'))
                cache = temporary / (name + '-cache-' + str(iteration))
                shutil.copytree(prime, cache, copy_function=os.link)
                env = go_env.copy(); env['GOCACHE'] = str(cache)
                target = work / 'reference'
                command = go_build + ['-ldflags=-s -w', '-o', target, '.']
                logfile = logs / f'{name}-go-{iteration}.log'
                measured = timed_process(command, work, env, logfile)
                samples.append(measured['seconds']); last_binary = target
                result['trials'].append(dict(measured, fixture=name, profile='go', state='cold', trial=iteration,
                                             log=str(logfile.relative_to(args.output.parent))))
            result['go']['apps'][name] = {'cold_seconds': samples, 'binary_bytes': last_binary.stat().st_size, 'sha256': digest(last_binary)}
            shutil.copy2(last_binary, published / ('reference-go-rest' if name == 'bench-rest' else 'reference-go-cli'))
    result['build_artifacts'] = {p.name: {'sha256': digest(p), 'bytes': p.stat().st_size} for p in published.iterdir() if p.is_file()}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print('Wrote measured evidence', args.output)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, OSError, RuntimeError) as error:
        print('BUILD MEASUREMENT BLOCKED:', error, file=sys.stderr)
        raise SystemExit(1)
