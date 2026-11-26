#!/usr/bin/env python3
"""Execute auditable checks and assemble actual all-six-gate evidence.

Receipts are integrity records, not cryptographic attestations. CI must protect the
runner, workflows and baseline write permissions from an unreviewed pull request.
"""
from __future__ import annotations
import argparse
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = {'linux-x86_64-glibc', 'linux-aarch64-glibc', 'linux-x86_64-musl',
             'linux-aarch64-musl', 'macos-arm64', 'windows-x86_64', 'wasm32'}
QUALITY = {'quality', 'safety', 'dag', 'betterc', 'sanitizers'}
MICROS = {'arena', 'serde', 'validate', 'router', 'reactor_echo'}


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def canonical_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def git_commit():
    result = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, capture_output=True, text=True)
    require(result.returncode == 0, 'evidence requires a committed Git checkout')
    value = result.stdout.strip()
    require(re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', value), 'invalid commit identity')
    return value


def read(path):
    require(Path(path).is_file(), 'missing evidence: ' + str(path))
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate JSON key: ' + str(key))
            result[key] = value
        return result
    def nonfinite(value):
        raise ValueError('nonfinite JSON number: ' + value)
    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=pairs, parse_constant=nonfinite)


def write(path, value):
    path = Path(path).resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def verified_receipt(receipt, directory, commit=None):
    require(receipt.get('schema') == 1, 'unsupported command receipt schema')
    require(type(receipt.get('exit_code')) is int and receipt['exit_code'] == 0, 'command did not pass')
    require(isinstance(receipt.get('command'), list) and receipt['command'] and
            all(isinstance(x, str) and x for x in receipt['command']), 'invalid command receipt')
    if commit is not None:
        require(receipt.get('commit') == commit, 'receipt belongs to another source commit')
    expected = receipt.get('sha256', '')
    require(re.fullmatch(r'[0-9a-f]{64}', expected), 'invalid receipt hash')
    artifact = (Path(directory) / receipt['artifact']).resolve()
    require(artifact.is_file(), 'receipt artifact missing: ' + str(artifact))
    require(digest(artifact) == expected, 'receipt artifact digest mismatch: ' + str(artifact))
    return artifact


def record(args, capture_json=False):
    command = args.command
    if command and command[0] == '--':
        command = command[1:]
    require(command, 'a real command is required after --')
    commit = git_commit()
    args.output = args.output.resolve()
    if capture_json:
        artifact = args.output.with_suffix('.stdout.json')
    else:
        artifact = args.artifact.resolve()
    artifact.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic_ns()
    completed = subprocess.run(command, cwd=ROOT, capture_output=True)
    elapsed = (time.monotonic_ns() - start) / 1e9
    artifact.write_bytes(completed.stdout if capture_json else completed.stdout + b'\n--- stderr ---\n' + completed.stderr)
    stderr = args.output.with_suffix('.stderr.log')
    stderr.parent.mkdir(parents=True, exist_ok=True)
    stderr.write_bytes(completed.stderr)
    receipt = {'schema': 1, 'name': args.kind if capture_json else args.name,
               'commit': commit, 'command': command, 'exit_code': completed.returncode,
               'seconds': elapsed, 'artifact': os.path.relpath(artifact, args.output.parent),
               'sha256': digest(artifact), 'stderr_artifact': os.path.relpath(stderr, args.output.parent),
               'stderr_sha256': digest(stderr)}
    if not capture_json and args.platform:
        receipt['platform'] = args.platform
    if capture_json:
        payload = None
        if completed.returncode == 0:
            payload = read(artifact)
        write(args.output, {'schema': 1, 'mode': 'production', 'kind': args.kind,
                            'payload': payload, 'receipt': receipt})
    else:
        write(args.output, receipt)
    if completed.stdout:
        sys.stdout.buffer.write(completed.stdout)
    if completed.stderr:
        sys.stderr.buffer.write(completed.stderr)
    return completed.returncode


def sample_series(values, count, label):
    require(isinstance(values, list) and len(values) == count, label + ': wrong sample count')
    require(all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and v > 0 for v in values),
            label + ': measurements must be finite positive numbers')


def validate_capture(capture, directory, commit, kind):
    require(capture.get('schema') == 1 and capture.get('mode') == 'production' and capture.get('kind') == kind,
            kind + ' must come from capture-json')
    artifact = verified_receipt(capture['receipt'], directory, commit)
    payload = read(artifact)
    require(capture.get('payload') == payload, kind + ' payload differs from the captured command stdout')
    return payload


def artifact_file(directory, relative, expected):
    path = (Path(directory) / relative).resolve()
    require(re.fullmatch(r'[0-9a-f]{64}', expected or ''), 'malformed artifact hash')
    require(path.is_file() and digest(path) == expected, 'missing or altered measured artifact: ' + str(path))
    return path


def validate_http(http, builds):
    """Recompute aggregates from actual retained oha outputs and process samples."""
    from load_bench import parse_oha, OHA_SHA256, OHA_VERSION
    require(http.get('schema') == 1 and http.get('mode') == 'production', 'HTTP smoke data is not release evidence')
    require(http.get('status') == 'passed', 'HTTP workload did not complete successfully')
    manifest_path = ROOT / http['manifest']
    manifest = read(manifest_path)
    require(digest(manifest_path) == http['workload_sha256'], 'HTTP workload manifest changed')
    workload = http['effective_workload']
    require(workload == manifest['workload'], 'effective HTTP workload differs from pinned manifest')
    require(workload['runs'] == 9 and workload['duration_seconds'] >= 60 and
            workload['capacity_seconds'] >= 60 and workload['warmup_seconds'] >= 10,
            'production HTTP evidence requires nine full-duration trials')
    require(http['tool'] == {'version': OHA_VERSION, 'sha256': OHA_SHA256}, 'load tool differs from verified pin')
    require(set(http['servers']) == {'flint', 'go'}, 'missing or unexpected HTTP server')
    for label, binary in [('flint', 'bench-rest'), ('go', 'reference-go-rest')]:
        server = http['servers'][label]
        require(server['sha256'] == builds['build_artifacts'][binary]['sha256'],
                'load test used a different ' + label + ' binary')
        artifact_file(ROOT, server['executable'], server['sha256'])
    trials = http['trials']
    require(len(trials) == 18, 'HTTP evidence needs 18 paired-target trials')
    expected_order = [(label, trial) for trial in range(9)
                      for label in (['flint', 'go'] if trial % 2 == 0 else ['go', 'flint'])]
    require([(row['target'], row['trial']) for row in trials] == expected_order,
            'HTTP trial identities/order are duplicated, missing, or not AB/BA')
    metrics = ['p50_ms', 'p99_ms', 'p999_ms', 'peak_rss_bytes', 'cpu_ns_per_request', 'requests_per_second']
    artifacts = []
    observed = {name: {metric: [] for metric in metrics} for name in ['flint', 'go']}
    for row in trials:
        label, trial = row['target'], row['trial']
        identity = http['servers'][label]
        require(row['server_binary_sha256'] == identity['sha256'] and row['server_command'] == identity['argv'],
                'a trial used a different server command or executable')
        for phase, duration_key in [('warmup', 'warmup_seconds'), ('latency', 'duration_seconds'), ('capacity', 'capacity_seconds')]:
            data = row[phase]; receipt = data['receipt']; duration = workload[duration_key]
            require(type(receipt['exit_code']) is int and receipt['exit_code'] == 0, 'oha phase failed')
            raw = artifact_file(ROOT, receipt['raw_file'], receipt['sha256'])
            artifacts.append((raw, f'http-{trial:02d}-{label}-{phase}'))
            parsed = parse_oha(read(raw), manifest['expected']['status'], len(manifest['expected']['body'].encode()))
            require(all(data[key] == value for key, value in parsed.items()), 'phase summary differs from raw oha output')
            require(parsed['duration_seconds'] >= duration * .995 and receipt['wall_seconds'] >= duration,
                    'HTTP phase was shorter than the declared workload')
            command = receipt['command']
            require(isinstance(command, list) and '-z' in command and command[command.index('-z') + 1] == str(duration) + 's',
                    'HTTP duration command differs from manifest')
            if phase == 'capacity':
                require('-q' not in command, 'capacity was accidentally fixed-rate limited')
            else:
                require('-q' in command and command[command.index('-q') + 1] == str(workload['fixed_rate_qps'])
                        and '--latency-correction' in command, 'fixed-rate phase lacks the offered load/correction')
                require(parsed['count'] >= math.floor(workload['fixed_rate_qps'] * duration * .995),
                        'offered load was not achieved')
            process = data['process']
            require(type(process['rss_samples']) is int and process['rss_samples'] > 0 and
                    type(process['correctness_probes']) is int and process['correctness_probes'] > 0,
                    'HTTP phase has no independent process/correctness samples')
            require(data['peak_rss_bytes'] == process['peak_rss_bytes'] and data['peak_rss_bytes'] > 0,
                    'HTTP RSS metric differs from observed process')
            require(data['cpu_ns_per_request'] == process['cpu_nanoseconds'] /
                    (parsed['count'] + process['correctness_probes']) and data['cpu_ns_per_request'] > 0,
                    'HTTP CPU/request metric differs from observed process')
            if phase != 'warmup':
                require(0 <= data['load_cpu_fraction'] < .85, 'load generator was CPU saturated')
            if phase == 'latency':
                require(parsed['count'] >= 100000, 'p99.9 requires at least 100000 completed requests per latency run')
        for metric in metrics:
            observed[label][metric].append(row['capacity' if metric == 'requests_per_second' else 'latency'][metric])
    for label, target in [('flint', http['rest']), ('go', http['go']['rest'])]:
        require(target == observed[label], 'HTTP aggregate differs from individual trials')
        for metric in metrics:
            sample_series(target[metric], 9, label + '.' + metric)
    return artifacts


def validate_published_binaries(builds):
    artifacts = []
    for name, row in builds['go']['apps'].items():
        binary_name = 'reference-go-rest' if name == 'bench-rest' else 'reference-go-cli'
        binary = artifact_file(ROOT / 'build', binary_name, row['sha256'])
        require(binary.stat().st_size == row['binary_bytes'] == builds['build_artifacts'][binary_name]['bytes'] and
                row['sha256'] == builds['build_artifacts'][binary_name]['sha256'], 'Go size differs from the actual executable')
        artifacts.append((binary, binary_name))
    for profile, binary_name in [('O3', 'bench.wasm'), ('Oz', 'bench-wasm-Oz.wasm')]:
        row = builds['apps']['bench-wasm'][profile]
        binary = artifact_file(ROOT / 'build', binary_name, row['sha256'])
        data = binary.read_bytes()
        require(data[:4] == b'\0asm' and len(data) == row['raw_bytes'] and
                len(gzip.compress(data, compresslevel=9, mtime=0)) == row['gzip_bytes'],
                'WASM size differs from the actual module bytes')
        require(row['sha256'] == builds['build_artifacts'][binary_name]['sha256'] and
                len(data) == builds['build_artifacts'][binary_name]['bytes'], 'WASM published artifact differs')
        artifacts.append((binary, 'wasm-' + profile))
    for name in ['bench-cli', 'bench-rest']:
        for profile, binary_name in [('O3', name), ('Oz', name + '-Oz')]:
            row = builds['apps'][name][profile]
            binary = artifact_file(ROOT / 'build', binary_name, row['sha256'])
            require(binary.stat().st_size == row['binary_bytes'] == builds['build_artifacts'][binary_name]['bytes'] and
                    row['sha256'] == builds['build_artifacts'][binary_name]['sha256'], 'native app size differs from the actual executable')
            artifacts.append((binary, name + '-' + profile))
    return artifacts


def validate_builds(builds, directory, commit):
    from measure_builds import package_template_instances, template_instances
    require(builds.get('schema') == 1 and builds.get('mode') == 'production', 'build measurements must be production evidence')
    require(builds.get('commit') == commit and type(builds.get('exit_code')) is int and builds['exit_code'] == 0,
            'build measurements have wrong commit or failed')
    packages = read(ROOT / 'policy/packages.json')['packages']
    require(set(builds['packages']) == set(packages), 'all37 package builds required')
    require(set(builds['apps']) == {'bench-cli', 'bench-rest', 'bench-wasm'} and
            set(builds['go']['apps']) == {'bench-cli', 'bench-rest'}, 'canonical app builds required')
    artifacts = []
    trial_map = {}
    for index, row in enumerate(builds['trials']):
        require(type(row['exit_code']) is int and row['exit_code'] == 0 and row['seconds'] > 0,
                'failed or invalid compiler trial')
        require(type(row['peak_rss_bytes']) is int and row['peak_rss_bytes'] > 0, 'missing process-tree RSS')
        require(isinstance(row['command'], list) and row['command'], 'missing actual build argv')
        identity = (row['fixture'], row['profile'], row['state'], row['trial'])
        require(identity not in trial_map, 'duplicate build trial identity')
        trial_map[identity] = row
        path = artifact_file(directory, row['log'], row['log_sha256'])
        artifacts.append((path, 'build-trial-' + str(index)))
    for name, row in {**builds['packages'], **{k: v for k, v in builds['apps'].items() if k != 'bench-wasm'}}.items():
        peaks = []
        for compiler in ['dmd', 'ldc']:
            for state in ['cold', 'incremental']:
                key = compiler + '_' + state + '_seconds'
                sample_series(row[key], 9, name + '.' + key)
                observations = [trial_map[(name, compiler, state, i)] for i in range(9)]
                require(row[key] == [v['seconds'] for v in observations], 'build aggregate differs from actual trials')
                if state == 'incremental':
                    require(all(v.get('edited_source') for v in observations), 'incremental build did not change a source')
                peaks += [v['peak_rss_bytes'] for v in observations]
        if name in packages:
            require(row.get('size_basis') == 'framework_over_provider_equivalent_baseline',
                    'package size basis must use a provider-equivalent baseline')
            require(row['compiler_peak_rss_bytes'] == max(peaks), 'compiler RSS differs from process samples')
            receipt = row['template_receipt']
            log = artifact_file(directory, receipt['log'], receipt['log_sha256'])
            require(type(row.get('template_instances_closure')) is int and
                    row['template_instances_closure'] == template_instances(log.read_text(errors='replace')),
                    'closure template count differs from actual compiler statistics')
            artifacts.append((log, name + '-templates'))
            require(receipt['artifacts'], 'template measurement lacks compiler trace/invocation receipts')
            records = []
            for i, item in enumerate(receipt['artifacts']):
                path = artifact_file(directory, item['artifact'], item['sha256'])
                artifacts.append((path, name + '-instrumentation-' + str(i)))
                if path.name.endswith('.invocation.json'):
                    records.append(path)
            require(type(row['template_instances']) is int and row['template_instances'] >= 0 and
                    row['template_instances'] == package_template_instances(records, name),
                    'package template count differs from its own compiler invocations')
            deltas = [row['size_detail'][profile]['fixture'] - row['size_detail'][profile]['baseline'] for profile in ['O3', 'Oz']]
            require(row['incremental_linked_bytes'] == max(0, *deltas), 'marginal size differs from observed binaries')
    wasm = builds['apps']['bench-wasm']
    for state in ['cold', 'incremental']:
        key = 'ldc_' + state + '_seconds'
        sample_series(wasm[key], 9, 'bench-wasm.' + key)
        observations = [trial_map[('bench-wasm', 'O3', state, i)] for i in range(9)]
        require(wasm[key] == [v['seconds'] for v in observations], 'WASM build aggregate differs')
    for name, row in builds['go']['apps'].items():
        sample_series(row['cold_seconds'], 9, name + '.go')
        require(row['cold_seconds'] == [trial_map[(name, 'go', 'cold', i)]['seconds'] for i in range(9)],
                'Go aggregate differs from actual builds')
    artifacts += validate_published_binaries(builds)
    sizes = {}
    for index, row in enumerate(builds['size_trials']):
        identity = (row['fixture'], row['profile'], row['variant'])
        require(identity not in sizes, 'duplicate native size observation')
        require(type(row['binary_bytes']) is int and row['binary_bytes'] > 0 and
                re.fullmatch(r'[0-9a-f]{64}', row['sha256']), 'invalid linked binary observation')
        sizes[identity] = row
        artifacts.append((artifact_file(directory, row['log'], row['log_sha256']), 'size-trial-' + str(index)))
    from module_budgets import load as module_budgets
    modules = module_budgets(read(ROOT / 'policy/budgets.json'), packages, ROOT)
    require(set(builds.get('modules', {})) == set(modules), 'module size measurements differ from the module budgets')
    for name, row in builds['modules'].items():
        deltas = [row['size_detail'][profile]['fixture'] - row['size_detail'][profile]['baseline'] for profile in ['O3', 'Oz']]
        require(row['incremental_linked_bytes'] == max(0, *deltas), 'module marginal size differs from observed binaries')
    measured = {**packages, **modules}
    expected_sizes = {(name, profile, variant) for name in measured for profile in ['O3', 'Oz'] for variant in ['fixture', 'baseline']}
    expected_sizes |= {(name, profile, 'app') for name in ['bench-cli', 'bench-rest'] for profile in ['O3', 'Oz']}
    require(set(sizes) == expected_sizes, 'all native feature/baseline and app size observations required')
    for name, profile, variant in expected_sizes:
        group = 'packages' if name in packages else 'modules' if name in modules else None
        expected = (builds[group][name]['size_detail'][profile][variant] if group
                    else builds['apps'][name][profile]['binary_bytes'])
        observed = sizes[(name, profile, variant)].get('loadable_bytes' if group else 'binary_bytes')
        require(expected == observed, 'size aggregate differs from stripped binary observation')
        if group:
            require(builds[group][name]['size_detail'][profile][variant + '_sha256'] == sizes[(name, profile, variant)]['sha256'],
                    'package or module binary identity differs from stripped observation')
    native = builds.get('native_inputs')
    if native is not None:
        artifacts.append((artifact_file(ROOT, native['receipt'], native['sha256']), 'native-install'))
    return artifacts


def validate_gc(gc):
    workers = gc['worker_count']
    require(type(workers) is int and workers > 0, 'missing GC worker count')
    require(type(gc.get('before_barrier_workers')) is int and type(gc.get('after_barrier_workers')) is int and
            gc['before_barrier_workers'] == workers and gc['after_barrier_workers'] == workers,
            'GC samples must bracket the same complete worker set')
    require(len(gc.get('worker_ids', [])) == workers and len(set(gc['worker_ids'])) == workers and
            all(type(value) is int and value >= 0 for value in gc['worker_ids']), 'GC worker identities missing/duplicated')
    require(gc.get('phase') == 'steady_state' and type(gc.get('requests_completed')) is int and gc['requests_completed'] >= 100000,
            'GC evidence must cover at least 100000 real requests after warmup')
    require(len(gc['allocated_bytes_per_worker']) == workers, 'missing per-worker allocation delta')
    require(all(type(v) is int and v >= 0 for v in gc['allocated_bytes_per_worker']), 'invalid allocation delta')
    require(type(gc['collection_delta']) is int and gc['collection_delta'] >= 0, 'invalid collection delta')
    before, after = gc['allocated_before_per_worker'], gc['allocated_after_per_worker']
    require(len(before) == workers and len(after) == workers and
            all(type(value) is int and value >= 0 for value in before + after), 'raw GC allocation counters missing')
    require([end - start for start, end in zip(before, after)] == gc['allocated_bytes_per_worker'],
            'GC allocation deltas differ from raw monotonic counters')
    require(type(gc['collections_before']) is int and type(gc['collections_after']) is int and
            0 <= gc['collections_before'] <= gc['collections_after'] and
            gc['collections_after'] - gc['collections_before'] == gc['collection_delta'],
            'GC collection delta differs from raw process counters')
    return gc


def hardware():
    info = {'system': platform.system(), 'machine': platform.machine(), 'release': platform.release(),
            'libc': platform.libc_ver(), 'node': platform.node()}
    if hasattr(os, 'sched_getaffinity'):
        info['affinity'] = sorted(os.sched_getaffinity(0))
    cpu = Path('/proc/cpuinfo')
    if cpu.is_file():
        rows = [line.strip() for line in cpu.read_text().splitlines()
                if line.startswith(('model name', 'vendor_id', 'cpu family', 'model\t', 'stepping', 'microcode'))]
        info['cpu_identity'] = sorted(set(rows))
    governors = {}
    for path in sorted(Path('/sys/devices/system/cpu').glob('cpu[0-9]*/cpufreq/scaling_governor')):
        governors[path.parent.parent.name] = path.read_text().strip()
    info['governors'] = governors
    return info


def collect(args):
    commit = git_commit()
    builds, http = read(args.builds), read(args.http)
    build_artifacts = validate_builds(builds, args.builds.parent, commit)
    http_artifacts = validate_http(http, builds)
    micro_capture, gc_capture = read(args.micro), read(args.gc)
    for label, capture, path in [('micro', micro_capture, args.micro), ('gc', gc_capture, args.gc)]:
        validate_capture(capture, path.parent, commit, label)
    micro = micro_capture['payload']['micro']
    require(set(micro) == MICROS, 'five concrete microbenchmark series required')
    for name, samples in micro.items():
        sample_series(samples, 21, name)
    require(micro_capture['payload'].get('unit') == 'nanoseconds_per_operation', 'microbenchmark unit must be explicit')
    gc = validate_gc(gc_capture['payload']['gc'])
    original_receipts = {}
    for path in sorted(args.receipts_dir.glob('*.json')):
        receipt = read(path)
        require(receipt['name'] not in original_receipts, 'duplicate quality receipt')
        verified_receipt(receipt, path.parent, commit)
        original_receipts[receipt['name']] = (receipt, path)
    require(set(original_receipts) == QUALITY, 'quality/safety/dag/betterc/sanitizers receipts all required')
    platforms = {}
    platform_records = []
    for path in sorted(args.platform_receipts_dir.rglob('*.json')):
        receipt = read(path)
        if 'platform' not in receipt:
            continue
        name = receipt['platform']
        require(name in PLATFORMS and name not in platforms, 'unknown/duplicate platform receipt')
        verified_receipt(receipt, path.parent, commit)
        platforms[name] = True
        platform_records.append((receipt, path))
    # ADR-017 decision 2: a platform without a validation receipt is recorded as failing, so Gate 6
    # reports it explicitly instead of evidence collection stopping.
    require(platforms, 'at least one platform validation receipt required')
    for name in sorted(PLATFORMS - set(platforms)):
        platforms[name] = False
    args.output = args.output.resolve()
    bundle = args.output.parent / (args.output.stem + '-artifacts')
    bundle.mkdir(parents=True, exist_ok=True)
    def retain(path, label):
        destination = bundle / (label + Path(path).suffix)
        shutil.copy2(path, destination)
        return {'artifact': os.path.relpath(destination, args.output.parent), 'sha256': digest(destination)}
    def receipt_for(name, source, command):
        data = retain(source, name)
        data.update({'schema': 1, 'name': name, 'command': command, 'exit_code': 0, 'commit': commit})
        return data
    receipts = {}
    for name, (receipt, path) in original_receipts.items():
        artifact = verified_receipt(receipt, path.parent, commit)
        receipts[name] = receipt_for(name, artifact, receipt['command'])
    receipts['compile'] = receipt_for('compile', args.builds, builds['command'])
    receipts['compile']['artifacts'] = [retain(path, label) for path, label in build_artifacts]
    receipts['size'] = receipt_for('size', args.builds, builds['command'])
    receipts['hot_gc'] = receipt_for('hot_gc', verified_receipt(gc_capture['receipt'], args.gc.parent, commit), gc_capture['receipt']['command'])
    gc_stderr = gc_capture['receipt']
    receipts['hot_gc']['artifacts'] = [retain(artifact_file(args.gc.parent, gc_stderr['stderr_artifact'], gc_stderr['stderr_sha256']), 'gc-stderr')]
    runtime_bundle = bundle / 'runtime-inputs.json'
    runtime_artifacts = [retain(args.http, 'http-load'), retain(args.micro, 'micro-capture'),
                         retain(verified_receipt(micro_capture['receipt'], args.micro.parent, commit), 'micro-output')]
    runtime_artifacts += [retain(path, label) for path, label in http_artifacts]
    write(runtime_bundle, {'http': http, 'micro': micro, 'artifacts': runtime_artifacts})
    receipts['runtime'] = {'schema': 1, 'name': 'runtime', 'command': [sys.executable] + sys.argv,
                           'exit_code': 0, 'commit': commit,
                           'artifact': os.path.relpath(runtime_bundle, args.output.parent),
                           'sha256': digest(runtime_bundle), 'artifacts': runtime_artifacts}
    platform_artifacts = []
    for receipt, path in platform_records:
        artifact = verified_receipt(receipt, path.parent, commit)
        platform_artifacts.append(retain(artifact, 'platform-' + receipt['platform']))
    platform_bundle = bundle / 'platform-summary.json'
    write(platform_bundle, {'platforms': platforms, 'artifacts': platform_artifacts})
    receipts['cross_platform'] = {'schema': 1, 'name': 'cross_platform', 'command': [sys.executable] + sys.argv,
        'exit_code': 0, 'commit': commit, 'artifact': os.path.relpath(platform_bundle, args.output.parent),
        'sha256': digest(platform_bundle), 'artifacts': platform_artifacts}
    hardware_info = hardware()
    require(args.dependency_lock.is_file(), 'exact native dependency lock required')
    toolchain = {'build': builds['toolchains'], 'profiles': builds['profiles'], 'load_tool': {k:http['tool'][k] for k in ['version','sha256']}}
    environment = {'runner_label': args.runner_label, 'runner_ephemeral': args.runner_ephemeral == '1',
                   'runner_fingerprint': canonical_hash(hardware_info),
                   'toolchain_fingerprint': canonical_hash(toolchain),
                   'dependency_lock_sha256': digest(args.dependency_lock),
                   'workload_sha256': canonical_hash({'http': http['workload_sha256'], 'build_manifest': builds['manifest_sha256'], 'build_workloads': builds['workload_sha256'],
                       'native_features': (builds.get('native_inputs') or {}).get('features', []),
                       'native_profile': (builds.get('native_inputs') or {}).get('profile_sha256')})}
    output = {'schema': 1, 'mode': 'production', 'commit': commit, 'environment': environment,
              'packages': builds['packages'], 'modules': builds['modules'], 'framework': builds.get('framework', {}), 'template_count_method': builds.get('template_count_method'), 'apps': builds['apps'], 'rest': http['rest'],
              'go': {'apps': builds['go']['apps'], 'rest': http['go']['rest']},
              'micro': micro, 'gc': gc, 'platforms': platforms, 'receipts': receipts,
              'provenance': {'hardware': hardware_info, 'toolchain': toolchain,
                             'producer': [sys.executable] + sys.argv,
                             'limitations': 'receipt hashes verify retained artifacts; trust also requires protected CI workflows, runners and baseline permissions'}}
    write(args.output, output)
    print('Collected actual evidence for', commit, 'at', args.output)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='action', required=True)
    command = commands.add_parser('record')
    command.add_argument('--name', required=True)
    command.add_argument('--platform', choices=sorted(PLATFORMS))
    command.add_argument('--output', type=Path, required=True)
    command.add_argument('--artifact', type=Path, required=True)
    command.add_argument('command', nargs=argparse.REMAINDER)
    command = commands.add_parser('capture-json')
    command.add_argument('--kind', choices=['micro', 'gc'], required=True)
    command.add_argument('--output', type=Path, required=True)
    command.add_argument('command', nargs=argparse.REMAINDER)
    command = commands.add_parser('collect')
    for name in ['builds', 'http', 'micro', 'gc', 'receipts-dir', 'platform-receipts-dir', 'dependency-lock', 'output']:
        command.add_argument('--' + name, type=Path, required=True)
    command.add_argument('--runner-label', default='flint-perf-x86_64-v1')
    command.add_argument('--runner-ephemeral', choices=('0', '1'), default='1',
                         help='1 when the runner is a single-job ephemeral image, 0 otherwise')
    args = parser.parse_args(argv)
    if args.action == 'record':
        return record(args)
    if args.action == 'capture-json':
        return record(args, True)
    return collect(args)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, OSError, RuntimeError) as error:
        print('EVIDENCE COLLECTION BLOCKED:', error, file=sys.stderr)
        raise SystemExit(1)
