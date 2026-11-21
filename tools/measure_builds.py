#!/usr/bin/env python3
"""Produce actual build/size evidence; absent implementations or probes fail closed.

Measurements run sequentially on the dedicated Linux x86-64 performance runner.
Cold means source/build-cache cold with prebuilt toolchain runtimes and native C
libraries already prepared. It does not mean dropping the OS page cache.
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
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
NATIVE_BLOCK = re.compile(r'\n// BEGIN FLINT NATIVE\n.*?// END FLINT NATIVE\n', re.S)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run_checked(command, cwd, env=None):
    result = subprocess.run([str(x) for x in command], cwd=cwd, env=env,
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('command failed: ' + json.dumps([str(x) for x in command]) + '\n' + result.stdout + result.stderr)
    return result


def timed_process(command, cwd, env, log_path):
    try:
        import psutil
    except ImportError as exc:
        raise RuntimeError('psutil required; install tools/requirements.txt') from exc
    peak = 0
    start = time.perf_counter_ns()
    with open(log_path, 'wb') as log:
        process = subprocess.Popen([str(x) for x in command], cwd=cwd, env=env,
                                   stdout=log, stderr=subprocess.STDOUT)
        monitored = psutil.Process(process.pid)
        while process.poll() is None:
            total = 0
            try:
                processes = [monitored] + monitored.children(recursive=True)
            except psutil.NoSuchProcess:
                processes = []
            for child in processes:
                try:
                    total += child.memory_info().rss
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass
            peak = max(peak, total)
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


def copy_workspace(destination):
    def ignore(directory, names):
        excluded = {'.git', '.dub', '.dub-home', '.ci-dub-home', '.tools', '.native',
                    '.native-sanitized', '__pycache__'}
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
    linker = ['-linker=' + lld] if lld else []
    return {
        'dmd': ['-preview=dip1000', '-debug', '-g', '-boundscheck=on'],
        'O3': ['-preview=dip1000', '-release', '-boundscheck=safeonly', '-O3', '--flto=thin', '-link-defaultlib-shared=false'] + linker,
        'Oz': ['-preview=dip1000', '-release', '-boundscheck=safeonly', '-Oz', '--flto=thin', '-link-defaultlib-shared=false'] + linker}


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
if '-c' not in expanded or any('dub_platform_probe_' in value for value in expanded):
    os.execv(compiler, [compiler] + args)
identity = uuid.uuid4().hex
trace = traces / (identity + '.trace.json')
command = [compiler] + args + ['-vtemplates', '-ftime-trace', '-ftime-trace-file=' + str(trace)]
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
(traces / (identity + '.invocation.json')).write_text(json.dumps({'command': command, 'expanded_arguments': expanded, 'response_files': response_files, 'exit_code': result.returncode, 'trace': trace.name, 'stdout': stdout.name, 'stderr': stderr.name}) + '\\n')
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
    receipt_path = root / '.native/install/linux-x86_64-glibc/flint-native-install.json'
    if receipt_path.is_file():
        import native_build
        args = argparse.Namespace(work_dir=root / '.native', target='linux-x86_64-glibc',
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
        if relative == 'packages/rpc/dub.sdl':
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
    with log.open('a', encoding='utf-8') as output:
        output.write('\n' + json.dumps({'strip_command': [str(x) for x in strip_command],
                                       'audit_command': [str(x) for x in audit_command]}) + '\n' + audit.stdout + audit.stderr)
    return {'binary_bytes': target.stat().st_size, 'sha256': digest(target),
            'dynamic_system_dependencies': needed, 'log_sha256': digest(log)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=ROOT / 'policy/build-benchmarks.json')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--dmd', default='dmd')
    parser.add_argument('--ldc', default='ldc2')
    parser.add_argument('--dub', default='dub')
    parser.add_argument('--go', default='go')
    parser.add_argument('--strip', default='strip')
    parser.add_argument('--readelf', default='readelf')
    parser.add_argument('--lld', default=None, help='Optional external LLD22; default uses system cc/ld with bundled LLVMgold plugin')
    args = parser.parse_args(argv)
    if sys.platform != 'linux' or os.uname().machine != 'x86_64':
        raise RuntimeError('measurement policy is Linux x86-64; cross-platform correctness uses its separate matrix')
    manifest = json.loads(args.manifest.read_text())
    packages = json.loads((ROOT / 'policy/packages.json').read_text())['packages']
    if manifest['schema'] != 1 or set(manifest['packages']) != set(packages):
        raise RuntimeError('build manifest must specify all 37 packages')
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
    for name in ['dmd', 'ldc', 'dub', 'go', 'strip', 'readelf'] + (['lld'] if args.lld else []):
        found = shutil.which(getattr(args, name))
        if not found:
            raise RuntimeError('required executable missing: ' + getattr(args, name))
        setattr(args, name, str(Path(found).resolve()))
        command = [getattr(args, name), 'version' if name == 'go' else '--version']
        version = run_checked(command, ROOT).stdout
        tools[name] = {'sha256': digest(getattr(args, name)), 'version': version.strip()}
    if args.lld and not re.search(r'LLD\s+22\.', tools['lld']['version']):
        raise RuntimeError('LDC1.43 LLVM22 ThinLTO requires external LLD22 for these native profiles')
    for name in ['cc', 'ld']:
        executable=shutil.which(name)
        if not executable:raise RuntimeError('native compiler driver/linker missing: '+name)
        tools[name]={'sha256':digest(executable),'version':run_checked([executable,'--version'],ROOT).stdout.strip()}
    for name,path in [('ldc_config',Path(args.ldc).parent.parent/'etc/ldc2.conf'),
                      ('llvmgold_plugin',Path(args.ldc).parent.parent/'lib/LLVMgold-ldc.so')]:
        if path.is_file():tools[name]={'sha256':digest(path)}
    tools['measurement_protocol'] = {'version': 1, 'sha256': digest(__file__),
                                     'statistics_sha256': digest(ROOT / 'tools/perf_stats.py')}
    commit, native_inputs = source_identity(ROOT)
    args.output = args.output.resolve()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    logs = args.output.parent / 'build-logs'
    logs.mkdir(exist_ok=True)
    result = {'schema': 1, 'mode': 'production', 'commit': commit,
              'producer': 'tools/measure_builds.py', 'command': [sys.executable] + sys.argv,
              'exit_code': 0, 'toolchains': tools, 'manifest_sha256': digest(args.manifest),
              'native_inputs': native_inputs,
              'packages': {}, 'apps': {}, 'go': {'apps': {}}, 'trials': [], 'size_trials': []}
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
    def measured_native(name, fixture):
        row = {}; peaks = []
        for label, compiler, profile in [('dmd', args.dmd, 'dmd'), ('ldc', args.ldc, 'O3')]:
            cold = []; incremental = []
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
        # Template statistics and time traces use a separate build; instrumentation
        # overhead is not included in developer-loop timing samples.
        with tempfile.TemporaryDirectory(prefix='flint-templates-') as temporary:
            workspace = Path(temporary) / 'workspace'; copy_workspace(workspace)
            traces = logs / (name + '-instrumentation')
            wrapper = instrumented_compiler(Path(temporary), args.dmd, traces)
            cmd, cwd, env = dub_command(workspace, fixture['fixture'], str(wrapper), 'dmd')
            driver_log = logs / (name + '-instrumentation-driver.log')
            observation = timed_process(cmd, cwd, env, driver_log)
            # DUB may suppress successful compiler stdout if it did not itself
            # add -vtemplates. Preserve/reparse the actual compiler streams.
            log = logs / (name + '-templates.log')
            streams = sorted(traces.glob('*.stdout.txt')) + sorted(traces.glob('*.stderr.txt'))
            log.write_text(''.join(path.read_text(errors='replace') for path in streams))
            row['template_instances'] = template_instances(log.read_text(errors='replace'))
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
    published = ROOT / 'build'; published.mkdir(exist_ok=True)
    for name, fixture in manifest['packages'].items():
        print('Measuring package', name, flush=True)
        row = measured_native(name, fixture)
        row['size_basis'] = fixture['size_basis']
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
                    sizes[profile][variant] = measured_size['binary_bytes']
                    sizes[profile][variant + '_sha256'] = measured_size['sha256']
                    result['size_trials'].append(dict(measured_size, fixture=name, profile=profile,
                                                       variant=variant, log=str(logfile.relative_to(args.output.parent))))
            difference = sizes[profile]['fixture'] - sizes[profile]['baseline']
            sizes[profile]['signed_delta_bytes'] = difference
            differences.append(difference)
        row['incremental_linked_bytes'] = max(0, *differences)
        row['size_detail'] = sizes
        result['packages'][name] = row
    for name in ['bench-cli', 'bench-rest']:
        fixture = manifest['apps'][name]
        print('Measuring app', name, flush=True)
        row = measured_native(name, fixture)
        row.pop('compiler_peak_rss_bytes'); row.pop('template_instances'); row.pop('template_receipt')
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
        result['apps'][name] = row
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
    # Go's stdlib cache is primed once to match D's precompiled runtime. Each app
    # trial gets a fresh clone of that cache; the app itself has no cached objects.
    go_env = base_env.copy()
    go_env.update({'GOTOOLCHAIN': 'local', 'GOPROXY': 'off', 'GOSUMDB': 'off', 'GOWORK': 'off', 'CGO_ENABLED': '0'})
    with tempfile.TemporaryDirectory(prefix='flint-go-') as temporary:
        temporary = Path(temporary); prime = temporary / 'prime'; prime.mkdir()
        go_env['GOCACHE'] = str(prime)
        run_checked([args.go, 'build', '-buildvcs=false', 'std'], ROOT, go_env)
        for name, source in go_sources.items():
            samples = []; last_binary = None
            for iteration in range(9):
                work = temporary / (name + '-' + str(iteration))
                shutil.copytree(source, work, ignore=shutil.ignore_patterns('.git', 'build'))
                cache = temporary / (name + '-cache-' + str(iteration))
                shutil.copytree(prime, cache, copy_function=os.link)
                env = go_env.copy(); env['GOCACHE'] = str(cache)
                target = work / 'reference'
                command = [args.go, 'build', '-buildvcs=false', '-trimpath', '-ldflags=-s -w', '-o', target, '.']
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
