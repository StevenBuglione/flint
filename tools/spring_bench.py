#!/usr/bin/env python3
"""The Spring side-by-side harness (ADR-030 section 8): the Java references, the black-box suites, the Go
comparators and the GC matrix for Phase 1's two claims, that Flint behaves as Spring does and that it beats Go.

    spring_bench.py list
    spring_bench.py fetch [<app>...]                      fetch each Java reference by commit and checksum
    spring_bench.py build <app>... --impl java|go|flint   build an implementation into build/spring/
    spring_bench.py record [<app>...]                     record the golden observations from the Java reference
    spring_bench.py accept [<app>...] --impl java|go|flint [--wire exact|semantic] [--json <file>]
    spring_bench.py accept <app> --start '<command>' --url http://127.0.0.1:<port> [--wire ...]
    spring_bench.py register [<app>...]                   register the Go comparators' commits (before measuring)
    spring_bench.py check-registry                        the comparators' sources still equal their registration
    spring_bench.py gc-matrix <app> --output <file> [--smoke]

The applications, their pins and their implementations are listed in benchmarks/spring/apps.json; see
benchmarks/spring/README.md for the method. The JDK, Maven, Go and PostgreSQL are the pinned peers
(tools/install_peers.py --peer jdk --peer maven --peer go --peer postgres); nothing is taken from the system.
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib
import json
import os
import re
import shlex
import shutil
import socket
import subprocess
import sys
import tarfile
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / 'benchmarks' / 'spring'
SUITES = BENCH / 'suites'
GOLDEN = SUITES / 'golden'
REGISTRY = BENCH / 'comparators.json'
CACHE = ROOT / '.flint' / 'spring'
BUILD = ROOT / 'build' / 'spring'
IMPLEMENTATIONS = ('java', 'go', 'flint')
# Context only: reported next to the measured implementations, never compared or gated.
CONTEXT_IMPLEMENTATIONS = ('java-native',)
WIRE_DEFAULT = {'java': 'exact', 'flint': 'exact', 'go': 'semantic', 'java-native': 'exact'}

sys.path.insert(0, str(SUITES))
sys.path.insert(0, str(ROOT / 'tools'))
import springsuite  # noqa: E402
import vibe_bench  # noqa: E402  (the pinned JDK, Maven and Go, shared with the vibe benchmark)


def registry():
    return json.loads((BENCH / 'apps.json').read_text())


def app_row(name):
    apps = registry()['apps']
    if name not in apps:
        raise SystemExit(f'unknown application {name}; known: {", ".join(apps)}')
    return apps[name]


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def run(command, cwd, env=None, timeout=1800, log=None):
    result = subprocess.run([str(x) for x in command], cwd=cwd, env=env, capture_output=True, text=True,
                            timeout=timeout)
    if log is not None:
        Path(log).write_text(result.stdout + result.stderr)
    if result.returncode:
        raise SystemExit(f'command failed ({result.returncode}): {shlex.join(map(str, command))}\n'
                         f'{(result.stdout + result.stderr)[-4000:]}')
    return result


# ---------------------------------------------------------------------------------------------------------------
# The Java references, fetched by commit and checksum


def source_directory(name):
    row = app_row(name)['upstream']
    return CACHE / 'src' / f"{name}-{row['commit'][:12]}"


def fetch(name):
    """Download the pinned archive, verify it, extract it and move its parent pom to the pinned Spring Boot."""
    row = app_row(name)['upstream']
    boot = registry()['spring_boot']
    archives = CACHE / 'archives'
    archives.mkdir(parents=True, exist_ok=True)
    archive = archives / (row['sha256'] + '.tar.gz')
    if not archive.is_file() or sha256(archive) != row['sha256']:
        import urllib.request
        partial = archive.with_suffix('.partial')
        with urllib.request.urlopen(row['archive_url'], timeout=300) as response, partial.open('wb') as output:
            shutil.copyfileobj(response, output)
        partial.replace(archive)
    if sha256(archive) != row['sha256']:
        archive.unlink()
        raise SystemExit(f'{name}: the archive does not match its pinned sha256 {row["sha256"]}')
    destination = source_directory(name)
    marker = destination / '.flint-spring-source.json'
    if marker.is_file() and json.loads(marker.read_text()).get('sha256') == row['sha256']:
        return destination / row['directory']
    if destination.exists():
        shutil.rmtree(destination)
    staging = destination.with_name(destination.name + '.extract')
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    with tarfile.open(archive) as bundle:
        bundle.extractall(staging, filter='data')
    (top,) = list(staging.iterdir())
    top.rename(destination)
    staging.rmdir()
    pom = destination / row['directory'] / 'pom.xml'
    text = pom.read_text()
    parent = re.compile(r'(<artifactId>spring-boot-starter-parent</artifactId>\s*<version>)' + re.escape(row['boot_parent'])
                        + '(</version>)')
    text, count = parent.subn(r'\g<1>' + boot + r'\g<2>', text)
    if count != 1:
        raise SystemExit(f'{name}: pom.xml does not use spring-boot-starter-parent {row["boot_parent"]}')
    pom.write_text(text)
    marker.write_text(json.dumps({'sha256': row['sha256'], 'commit': row['commit'],
                                  'edit': f"spring-boot-starter-parent {row['boot_parent']} -> {boot}"}) + '\n')
    return destination / row['directory']


def build_java(name):
    directory = fetch(name)
    jdk, maven, env = vibe_bench.java_environment()
    repository = ROOT / '.flint' / 'peers' / 'm2'
    BUILD.mkdir(parents=True, exist_ok=True)
    run([maven, '--strict-checksums', '-B', '-q', '-Dmaven.repo.local=' + str(repository), '-DskipTests', 'package'],
        directory, env, log=BUILD / f'{name}-java-build.log')
    problem = vibe_bench.check_spring_boot(directory, repository)
    if problem:
        raise SystemExit(f'{name}: {problem}')
    jar = directory / app_row(name)['java']['jar']
    if not jar.is_file():
        raise SystemExit(f'{name}: Maven did not produce {jar}')
    return jar


def native_binary(name):
    row = app_row(name)
    return source_directory(name) / row['upstream']['directory'] / row['java']['native']


def build_java_native(name):
    """The Spring Boot native image (`-Pnative native:compile`), with the pinned GraalVM and Maven. Context only."""
    directory = fetch(name)
    graalvm = vibe_bench.pinned_peer('graalvm')
    _, maven, env = vibe_bench.java_environment()
    env.update({'JAVA_HOME': str(graalvm), 'GRAALVM_HOME': str(graalvm),
                'PATH': str(graalvm / 'bin') + os.pathsep + env['PATH'],
                # Leave most of the runner to other work: native-image otherwise takes every core.
                'NATIVE_IMAGE_OPTIONS': '--parallelism=8'})
    repository = ROOT / '.flint' / 'peers' / 'm2'
    BUILD.mkdir(parents=True, exist_ok=True)
    run([maven, '--strict-checksums', '-B', '-q', '-Dmaven.repo.local=' + str(repository), '-DskipTests', '-Pnative',
         'native:compile'], directory, env, timeout=3600, log=BUILD / f'{name}-java-native-build.log')
    binary = native_binary(name)
    if not binary.is_file():
        raise SystemExit(f'{name}: native-image did not produce {binary}')
    return binary


# ---------------------------------------------------------------------------------------------------------------
# The Go comparators and the Flint ports


def go_binary(name):
    return BUILD / f"{name}-go"


def build_go(name, output=None):
    row = app_row(name)['go']
    directory = ROOT / row['directory']
    if not (directory / 'go.mod').is_file():
        raise SystemExit(f'{name}: the Go comparator is missing ({directory})')
    go = vibe_bench.pinned_go()
    env = vibe_bench.go_environment()
    env['CGO_ENABLED'] = '0'
    output = Path(output or go_binary(name))
    output.parent.mkdir(parents=True, exist_ok=True)
    run([go, 'build', '-buildvcs=false', '-trimpath', '-ldflags=-s -w', '-o', output, '.'], directory, env)
    return output


def flint_binary(name):
    return BUILD / f"{name}-flint"


def flint_artifact(stdout, directory):
    """The executable `flint build --json` reports (flint.build/1 `artifact.path`), when a port's flint-spring.json
    names no `binary`, as tools/vibe_bench.py reads it."""
    document = None
    for line in reversed(stdout.splitlines()):
        if line.startswith('{'):
            try:
                document = json.loads(line)
                break
            except ValueError:
                continue
    if document is None:
        try:
            document = json.loads(stdout)
        except ValueError:
            raise SystemExit('flint build printed no flint.build/1 document; add --json to the command')
    artifact = (document.get('artifact') or {}).get('path')
    if not artifact:
        raise SystemExit('flint build reported no artifact path')
    return Path(artifact) if Path(artifact).is_absolute() else Path(directory) / artifact


def flint_port_ready(name):
    """A Flint port the harness may build: its flint-spring.json exists and is not a skeleton (benchmarks/spring/
    flint/<app>/README.md). A skeleton counts as missing, which every claim treats as a failure."""
    manifest = ROOT / app_row(name)['flint']['directory'] / 'flint-spring.json'
    return manifest.is_file() and json.loads(manifest.read_text()).get('status') != 'skeleton'


def build_flint(name):
    """The Flint port, built with the command its directory declares in flint-spring.json. The ports are written by
    the Phase 1 framework and Boot sessions; until one lands, this fails closed."""
    row = app_row(name)['flint']
    directory = ROOT / row['directory']
    manifest = directory / 'flint-spring.json'
    if not manifest.is_file():
        raise SystemExit(f'{name}: the Flint port is not there yet ({manifest} is missing). A missing port is a '
                         'failure of its claim, never a pass (AGENTS.md, "CI and evidence integrity").')
    spec = json.loads(manifest.read_text())
    if spec.get('status') == 'skeleton':
        raise SystemExit(f'{name}: the Flint port is a skeleton that does not build yet ({manifest}); a missing port '
                         'is a failure of its claim, never a pass')
    try:
        result = run(spec['build'], directory, dict(os.environ))
    except OSError as exc:
        raise SystemExit(f'{name}: the Flint build command could not run: {exc}') from exc
    produced = directory / spec['binary'] if spec.get('binary') else flint_artifact(result.stdout, directory)
    if not produced.is_file():
        raise SystemExit(f'{name}: the Flint build did not produce {produced}')
    BUILD.mkdir(parents=True, exist_ok=True)
    shutil.copy2(produced, flint_binary(name))
    return flint_binary(name)


def build(name, implementation):
    return {'java': build_java, 'go': build_go, 'flint': build_flint, 'java-native': build_java_native}[implementation](name)


# ---------------------------------------------------------------------------------------------------------------
# PostgreSQL for petclinic-rest's JDBC profile


def free_port():
    with contextlib.closing(socket.socket()) as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def postgres_bin():
    """The PostgreSQL server tools install_peers.py built from the source pinned for libpq, checked against its
    receipt, so the server is the same pinned build for every implementation."""
    libraries = json.loads((ROOT / 'policy' / 'native-lock.json').read_text())['libraries']
    rows = libraries if isinstance(libraries, list) else list(libraries.values())
    version = next(row for row in rows if row.get('name') == 'libpq')['version']
    for root in vibe_bench.checkouts():
        prefix = root / '.flint' / 'peers' / f'postgresql-{version}'
        receipt = prefix / 'flint-peer.json'
        if receipt.is_file():
            binaries = json.loads(receipt.read_text())['binaries']
            if all(sha256(prefix / 'bin' / tool) == digest for tool, digest in binaries.items()):
                return prefix / 'bin'
    raise SystemExit(f'PostgreSQL {version} is missing; install it with python3 tools/install_peers.py --peer postgres')


@contextlib.contextmanager
def postgres_cluster(cpus=None):
    """A disposable cluster of the pinned PostgreSQL peer, TCP only, on a free loopback port."""
    prefix = postgres_bin()
    with tempfile.TemporaryDirectory(prefix='flint-spring-pg-') as directory:
        data, log = Path(directory) / 'data', Path(directory) / 'server.log'
        quiet = {'stdout': subprocess.DEVNULL, 'stderr': subprocess.STDOUT}
        subprocess.run([str(prefix / 'initdb'), '-D', str(data), '-U', 'petclinic', '--auth=trust', '--encoding=UTF8',
                        '--locale=C.UTF-8', '--no-sync'], check=True, **quiet)
        port = free_port()
        options = f'-c listen_addresses=127.0.0.1 -p {port} -c unix_socket_directories= -c fsync=off -c max_connections=200'
        start = [str(prefix / 'pg_ctl'), '-D', str(data), '-l', str(log), '-o', options, '-w', '-t', '60', 'start']
        if cpus:
            start = ['taskset', '--cpu-list', ','.join(map(str, cpus))] + start
        subprocess.run(start, check=True, **quiet)
        counter = [0]

        def database():
            counter[0] += 1
            name = f'petclinic{counter[0]}'
            subprocess.run([str(prefix / 'createdb'), '-h', '127.0.0.1', '-p', str(port), '-U', 'petclinic', name],
                           check=True, **quiet)
            return {'POSTGRES_URL': f'jdbc:postgresql://127.0.0.1:{port}/{name}', 'POSTGRES_USER': 'petclinic',
                    'POSTGRES_PASS': 'petclinic'}
        try:
            yield database
        finally:
            subprocess.run([str(prefix / 'pg_ctl'), '-D', str(data), '-m', 'fast', '-w', 'stop'], check=False, **quiet)


# ---------------------------------------------------------------------------------------------------------------
# Starting an implementation


def pinned_environment():
    """The environment every implementation runs in: the same time zone and locale, so `Content-Language`, dates
    and messages cannot differ by machine."""
    env = {key: value for key, value in os.environ.items() if not key.startswith(('LC_', 'SPRING_', 'FLINT_', 'JAVA_'))}
    env.update({'TZ': 'UTC', 'LANG': 'en_US.UTF-8', 'LC_ALL': 'en_US.UTF-8'})
    return env


def launch(name, implementation, port, database=None, extra_args=(), binary=None):
    """(argv, environment, cwd) for one implementation of one application, built beforehand."""
    row = app_row(name)
    env = pinned_environment()
    env['SERVER_PORT'] = str(port)
    if row.get('database') == 'postgres':
        if database is None:
            raise SystemExit(f'{name} needs a PostgreSQL database')
        env.update(database())
    if row.get('profiles'):
        env['SPRING_PROFILES_ACTIVE'] = row['profiles']
        env['FLINT_PROFILES_ACTIVE'] = row['profiles']
    if implementation == 'java':
        jdk, _, java_env = vibe_bench.java_environment()
        env.update({'JAVA_HOME': java_env['JAVA_HOME'], 'PATH': java_env['PATH']})
        jar = source_directory(name) / row['upstream']['directory'] / row['java']['jar']
        if not jar.is_file():
            raise SystemExit(f'{name}: build the Java reference first (spring_bench.py build {name} --impl java)')
        return [str(jdk / 'bin' / 'java'), '-jar', str(jar), *extra_args], env, jar.parent.parent
    if implementation == 'java-native':
        binary = binary or native_binary(name)
    binary = Path(binary) if binary else (go_binary(name) if implementation == 'go' else flint_binary(name))
    if not binary.is_file():
        raise SystemExit(f'{name}: build the {implementation} implementation first '
                         f'(spring_bench.py build {name} --impl {implementation})')
    # A Flint port runs from its own directory, as Boot runs from the project root: application.properties,
    # schema.sql and data.sql are found relative to it.
    cwd = ROOT / row['flint']['directory'] if implementation == 'flint' else ROOT
    return [str(binary), *extra_args], env, cwd


def load_suite(name):
    return importlib.import_module(app_row(name)['suite'])


@contextlib.contextmanager
def maybe_postgres(name):
    if app_row(name).get('database') == 'postgres':
        with postgres_cluster() as database:
            yield database
    else:
        yield None


def observe(name, implementation=None, start=None, url=None, logs=None, mask=True, extra_args=(), binary=None,
            start_cwd=None):
    """Run the suite once and return (observations, seconds)."""
    row = app_row(name)
    module = load_suite(name)
    logs = Path(logs or BUILD / 'logs')
    logs.mkdir(parents=True, exist_ok=True)
    log_path = logs / f"{name}-{implementation or 'custom'}.log"
    with maybe_postgres(name) as database:
        if start:
            command = shlex.split(start)
            env = pinned_environment()
            cwd = Path(start_cwd) if start_cwd else ROOT
            if database is not None:
                env.update(database())
            port = int(url.rsplit(':', 1)[1].split('/')[0]) if url else free_port()
            env.setdefault('SERVER_PORT', str(port))
        else:
            port = free_port()
            command, env, cwd = launch(name, implementation, port, database, extra_args, binary)
        if row['kind'] == 'command':
            observed, seconds = springsuite.run_command(module.SUITE, command, env, cwd, log_path)
            return observed, seconds
        origin = url.rstrip('/') if url else f'http://127.0.0.1:{port}'
        results, seconds = springsuite.run_http(module.CASES, origin, command, env, cwd, log_path, mask=mask)
        return [{'name': case.name, 'request': {'method': case.method, 'path': case.path},
                 'response': response} for case, response in results], seconds


def golden_path(name):
    return GOLDEN / f'{name}.json'


def record(name):
    """Record the golden file from the Java reference, twice: the two runs must agree, so every value that differs
    between runs is named by the suite rather than left to chance."""
    build_java(name)
    first, _ = observe(name, 'java')
    second, _ = observe(name, 'java')
    if first != second:
        differences = [f"{left['name']}: {left['response']} != {right['response']}"
                       for left, right in zip(first, second) if left != right] if isinstance(first, list) else [
            f'{first} != {second}']
        raise SystemExit(f'{name}: two runs of the Java reference differ; name the volatile values in the suite:\n'
                         + '\n'.join(differences[:10]))
    row = app_row(name)
    golden = {'schema': 'flint.spring-golden/1', 'app': name, 'kind': row['kind'],
              'reference': {'repo': row['upstream']['repo'], 'commit': row['upstream']['commit'],
                            'spring_boot': registry()['spring_boot'],
                            'jdk': json.loads((ROOT / 'policy' / 'peer-lock.json').read_text())['peers']['jdk']['version'],
                            'profiles': row.get('profiles')},
              'observations': first}
    GOLDEN.mkdir(parents=True, exist_ok=True)
    golden_path(name).write_text(json.dumps(golden, indent=1, ensure_ascii=False) + '\n')
    count = len(first) if isinstance(first, list) else len(first['events'])
    print(f'{name}: recorded {count} observations from the Java reference into {golden_path(name).relative_to(ROOT)}')


def accept(name, implementation, wire, start=None, url=None, extra_args=(), binary=None, start_cwd=None):
    golden = json.loads(golden_path(name).read_text())
    observed, seconds = observe(name, implementation, start, url, mask=False, extra_args=extra_args, binary=binary,
                                start_cwd=start_cwd)
    if golden['kind'] == 'command':
        problems = springsuite.compare_command(golden['observations'], observed)
        cases = [{'name': 'run to completion', 'problems': problems}]
    else:
        expected = golden['observations']
        if [row['name'] for row in expected] != [row['name'] for row in observed]:
            raise SystemExit(f'{name}: the golden file does not match the suite\'s cases; record it again')
        cases = [{'name': want['name'], 'problems': springsuite.compare(want['response'], got['response'], wire)}
                 for want, got in zip(expected, observed)]
    passed = sum(not case['problems'] for case in cases)
    return {'schema': 'flint.spring-acceptance/1', 'app': name, 'implementation': implementation or 'custom',
            'start': start, 'extra_args': list(extra_args), 'binary': str(binary) if binary else None, 'wire': wire, 'golden_sha256': sha256(golden_path(name)), 'cases': cases,
            'passed': passed, 'total': len(cases), 'success': passed == len(cases), 'seconds': seconds}


# ---------------------------------------------------------------------------------------------------------------
# Comparator registration: each Go comparator is registered with its commit before any Flint measurement


def comparator_files(name):
    directory = ROOT / app_row(name)['go']['directory']
    return sorted(path for path in directory.rglob('*') if path.is_file())


def comparator_digest(name):
    digest = hashlib.sha256()
    for path in comparator_files(name):
        digest.update(str(path.relative_to(ROOT)).encode() + b'\0' + path.read_bytes() + b'\0')
    return digest.hexdigest()


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()


CENSUS = ROOT / 'benchmarks' / 'spring' / 'census'


def census_problems(name, digest):
    """ADR-032 section 4: a database app's comparator needs a census of its current source with no per-request
    divergence from the reference (spring_sql_census.py --record)."""
    if app_row(name).get('database') != 'postgres':
        return []
    path = CENSUS / f'{name}.json'
    if not path.is_file():
        return [f'{name}: no SQL census of the comparator (spring_sql_census.py --app {name} --record)']
    census = json.loads(path.read_text())
    problems = []
    if census.get('comparator_sha256') != digest:
        problems.append(f'{name}: the SQL census is of another comparator source; take it again')
    if census.get('divergences', {}).get('go') != 0:
        problems.append(f"{name}: the comparator's SQL differs from the reference's in "
                        f"{census.get('divergences', {}).get('go')} case(s) (ADR-032)")
    return problems


def register(names):
    """Record each comparator's last commit and source digest. The sources must be committed and clean, so the
    registered commit holds exactly the code that will be measured."""
    rows = json.loads(REGISTRY.read_text()) if REGISTRY.is_file() else {
        'schema': 'flint.spring-comparators/1',
        'description': 'Go comparators registered before any Flint measurement (ADR-030 section 8). '
                       'measure_builds.py --spring and load_bench.py refuse a comparator whose source differs from '
                       'its registered digest. Changing a comparator after Flint measurements exist needs its own '
                       'reviewed ADR and remeasurement of both sides (AGENTS.md).',
        'comparators': {}}
    go_version = json.loads((ROOT / 'policy' / 'toolchains.json').read_text())['versions']['go']
    for name in names:
        directory = app_row(name)['go']['directory']
        if git('status', '--porcelain', '--', directory):
            raise SystemExit(f'{name}: commit the comparator first; {directory} has uncommitted changes')
        commit = git('log', '-1', '--format=%H', '--', directory)
        if not commit:
            raise SystemExit(f'{name}: the comparator has never been committed')
        problems = census_problems(name, comparator_digest(name))
        if problems:
            raise SystemExit('; '.join(problems))
        previous = rows['comparators'].get(name)
        if previous and previous['sha256'] != comparator_digest(name) and previous.get('measured'):
            raise SystemExit(f'{name}: the registered comparator has been measured; changing it needs an ADR')
        rows['comparators'][name] = {'directory': directory, 'commit': commit, 'sha256': comparator_digest(name),
                                     'go': go_version, 'wire': 'semantic',
                                     'registered': time.strftime('%Y-%m-%d', time.gmtime()), 'measured': False}
        if (CENSUS / f'{name}.json').is_file() and app_row(name).get('database') == 'postgres':
            rows['comparators'][name]['census_sha256'] = sha256(CENSUS / f'{name}.json')
        print(f'{name}: registered {commit[:12]} ({rows["comparators"][name]["sha256"][:12]})')
    REGISTRY.write_text(json.dumps(rows, indent=2) + '\n')


def check_registry(names=None):
    """Problems with the registration of each comparator: missing, or its source changed since."""
    rows = json.loads(REGISTRY.read_text())['comparators'] if REGISTRY.is_file() else {}
    problems = []
    for name in names or [n for n, row in registry()['apps'].items() if 'go' in row]:
        row = rows.get(name)
        if row is None:
            problems.append(f'{name}: the Go comparator is not registered (spring_bench.py register {name})')
        elif row['sha256'] != comparator_digest(name):
            problems.append(f'{name}: the Go comparator differs from its registration at {row["commit"][:12]}')
        elif census_problems(name, row['sha256']):
            problems += census_problems(name, row['sha256'])
        elif app_row(name).get('database') == 'postgres' and row.get('census_sha256') != sha256(CENSUS / f'{name}.json'):
            problems.append(f'{name}: the SQL census changed since registration; register again')
        else:
            try:
                git('merge-base', '--is-ancestor', row['commit'], 'HEAD')
            except subprocess.CalledProcessError:
                problems.append(f'{name}: the registered commit {row["commit"][:12]} is not in this history')
    return problems


# ---------------------------------------------------------------------------------------------------------------
# Assembling the Phase 1 evidence from the queue's certified runs

PHASE1_FILES = {
    'error-404-p99': ['http-error-404.json'],
    'error-validation-p99': ['http-error-validation.json'],
}
# Entries split per application, one claimed window each (coordination.md "Measurement"): every entry whose id has
# the prefix is one part, and each file is merged across the parts.
PHASE1_SPLIT = {
    'phase1-builds-': ['acceptance-java.json', 'acceptance-go.json', 'acceptance-flint.json', 'builds.json'],
    'phase1-http-': ['http.json'],
}
PHASE1_GC_PREFIX = 'phase1-gc-matrix-'  # parts of the GC matrix per application, each run on natural quiet


def certified_results(entry_id):
    """The newest results directory of a queue entry whose receipt counts as evidence, or None."""
    base = ROOT / '.flint' / 'measure' / 'results' / entry_id
    for directory in sorted(base.glob('2*/'), reverse=True) if base.is_dir() else []:
        receipt = directory / 'receipt.json'
        if receipt.is_file() and json.loads(receipt.read_text()).get('evidence'):
            return directory
    return None


def merge_http(records):
    """One schema-2 load_bench record from several, one workload each (the error-path entries)."""
    merged = {'schema': 2, 'mode': 'production', 'apps': {}, 'acceptance': [], 'comparators': {}, 'parts': []}
    for path, record in records:
        merged['apps'].update(record['apps'])
        merged['acceptance'] += record.get('acceptance', [])
        merged['comparators'].update(record.get('comparators', {}))
        merged['parts'].append({'source': str(path), 'sha256': sha256(path), 'status': record['status'],
                                'mode': record['mode']})
        if record['mode'] != 'production':
            merged['mode'] = record['mode']
    merged['status'] = 'passed' if all(p['status'] == 'passed' for p in merged['parts']) else 'failed'
    return merged


def merge_acceptance(records):
    """One acceptance list from the parts' records (`accept --json` writes one record, or a list of several)."""
    merged = []
    for _, record in records:
        merged += record if isinstance(record, list) else [record]
    return merged


def merge_builds(records):
    """One measure_builds --spring record from parts that each measured some applications."""
    merged = {'schema': 'flint.spring-builds/1', 'apps': {}, 'comparators': {}, 'missing_flint': [], 'trials': [],
              'parts': []}
    for path, record in records:
        for key in ('commit', 'host', 'trials_per_series'):
            merged.setdefault(key, record.get(key))
        merged['apps'].update(record['apps'])
        merged['comparators'].update(record.get('comparators', {}))
        merged['missing_flint'] += record.get('missing_flint', [])
        merged['trials'] += record.get('trials', [])
        merged['parts'].append({'source': str(path), 'sha256': sha256(path), 'status': record['status'],
                                'mode': record['mode'], 'commit': record.get('commit'),
                                'trials_per_series': record.get('trials_per_series'), 'apps': sorted(record['apps'])})
    parts = merged['parts']
    merged['mode'] = 'production' if all(p['mode'] == 'production' for p in parts) else 'mixed'
    if len({p['trials_per_series'] for p in parts}) > 1:
        merged['mode'] = 'mixed'
    merged['status'] = 'passed' if all(p['status'] == 'passed' for p in parts) else 'failed'
    return merged


PHASE1_MERGE = {'builds.json': merge_builds, 'http.json': merge_http}


def merge_gc(records):
    """One GC-matrix record from parts that each measured some settings with Go interleaved; every setting keeps
    the ratios against its own part's Go."""
    merged = {'schema': 'flint.spring-gc-matrix-result/1', 'settings': {}, 'parts': []}
    for path, record in records:
        merged.setdefault('app', record['app'])
        merged['settings'].update(record['settings'])
        merged['parts'].append({'source': str(path), 'sha256': sha256(path), 'status': record['status'],
                                'mode': record['mode'], 'settings': sorted(record['settings'])})
    merged['mode'] = 'production' if all(p['mode'] == 'production' for p in merged['parts']) else 'mixed'
    merged['status'] = 'passed' if all(p['status'] == 'passed' for p in merged['parts']) else 'failed'
    return merged


def receipt_commits(directory):
    """The source commits a certified run built and ran at: its builds' commits and its steps' harness revision."""
    receipt = json.loads((directory / 'receipt.json').read_text())
    commits = {row.get('commit') for row in receipt.get('builds', {}).values() if row.get('commit')}
    commits |= {step.get('harness_commit') for step in receipt.get('summary', {}).get('steps', []) if step.get('harness_commit')}
    return commits


def consistency_problems(parts, runs_by_family):
    """Resume plan rule 4 (owner decision, b349fb0a): the assembled evidence fails closed. Every part (builds, HTTP,
    error and GC) must be measured at one source commit, in production mode, with the gate's trial counts, and the
    parts together must cover every application, workload and setting the gate scores."""
    problems = []
    commits = {}
    baselines, checked = {}, set()
    for part in parts:
        commits.setdefault(tuple(sorted(part['commits'])), []).append(part['entry'])
    if len(commits) != 1 or any(len(key) != 1 for key in commits):
        problems.append('the parts were not all measured at one source commit: '
                        + '; '.join(f"{', '.join(key) or 'no commit'}: {', '.join(sorted(ids))}" for key, ids in commits.items()))
    for part in parts:
        record, family = part['record'], part['family']
        if family == 'acceptance':
            continue  # scored case by case by the gate; an acceptance record has no mode
        # Verdicts (a builds record's status fails with a losing budget) are the gate's to score; this is provenance.
        if record.get('mode') != 'production':
            problems.append(f"{part['entry']} {part['file']}: mode {record.get('mode')}; production required")
        if family == 'builds':
            # Served compiles (coordinator, B2): the builds step's receipt must show compile-server requests compiled
            # and none refused.
            served = [(step.get('dmd_server') or {}).get('scored') for step in part.get('steps', [])
                      if 'measure_builds.py' in ' '.join(step.get('command', []))]
            if part.get('steps') is not None and (not served or not served[0] or not served[0].get('compiled') or
                                                   (served[0].get('refused') and served[0].get('policy') != 'report')):
                problems.append(f"{part['entry']} builds.json: compile server {served[0] if served else 'not traced'}; "
                                'served compiles with none refused required')
            if record.get('trials_per_series') != 9:
                problems.append(f"{part['entry']} builds.json: {record.get('trials_per_series')} trials per series; 9 required")
            claimed = record.get('commit')
            if not claimed:
                problems.append(f"{part['entry']} builds.json names no commit")
            elif not any(c.startswith(claimed) or claimed.startswith(c) for c in part['commits']):
                problems.append(f"{part['entry']} builds.json names commit {claimed}, its receipt {sorted(part['commits'])}")
        elif family in ('http', 'error', 'gc'):
            # Owner decision c015f307: per application, every runtime part is measured against the same captured Go
            # baseline (or every one interleaves Go); a record must still be current.
            apps_of = ([record.get('app')] if family == 'gc'
                       else sorted({row.get('app', key) for key, row in record.get('apps', {}).items()}))
            for app_name in apps_of:
                baselines.setdefault(app_name, set()).add((record.get('baseline') or {}).get('sha256'))
            if record.get('baseline') and record['baseline']['record'] not in checked:
                checked.add(record['baseline']['record'])
                import spring_baseline
                try:
                    differing = spring_baseline.stale(spring_baseline.load(record['baseline']['record']))
                except (OSError, ValueError, KeyError) as exc:
                    differing = [f'unreadable: {exc}']
                if differing:
                    problems.append(f"{part['entry']}: its baseline record is stale: {', '.join(differing)}")
            # The GC matrix takes the HTTP manifest's workload; the error paths have their own manifest.
            want = runs_by_family[family]
            runs = record.get('effective_workload', {}).get('runs')
            if runs != want:
                problems.append(f"{part['entry']} {part['file']}: {runs} runs; the manifest's {want} required")
    for app_name, records in sorted(baselines.items()):
        if len(records) > 1:
            problems.append(f'{app_name}: its runtime parts use different comparator sides '
                            f"({', '.join(sorted(r[:12] if r else 'interleaved Go' for r in records))})")
    return problems


def coverage_problems(parts):
    problems = []
    apps = set(registry()['apps'])
    measured = {family: set() for family in ('builds', 'http', 'error', 'gc', 'acceptance')}
    for part in parts:
        record = part['record']
        if part['family'] == 'gc':
            measured['gc'] |= {(record.get('app'), setting) for setting in record.get('settings', {})}
        elif part['family'] == 'acceptance':
            for row in record if isinstance(record, list) else [record]:
                measured['acceptance'].add((row.get('app'), row.get('implementation')))
        else:
            measured[part['family']] |= set(record.get('apps', {}))
    wanted = {
        'builds': apps,
        'http': set(json.loads((ROOT / 'policy' / 'spring-http-benchmark.json').read_text())['apps']) & apps,
        'error': set(json.loads((ROOT / 'policy' / 'spring-error-paths-benchmark.json').read_text())['apps']),
        'acceptance': {(app, impl) for app in apps for impl in IMPLEMENTATIONS}}
    matrix = json.loads((ROOT / 'benchmarks' / 'spring' / 'gc-matrix.json').read_text())
    wanted['gc'] = {(app, setting) for app in matrix['apps'] for setting in matrix['settings']}
    for family, want in wanted.items():
        missing = want - measured[family]
        if missing:
            problems.append(f'{family}: not covered by any certified part: '
                            + ', '.join(sorted(' '.join(item) if isinstance(item, tuple) else item for item in missing)))
    return problems


def assemble(output):
    """Copy the newest certified outputs of the Phase 1 entries into `output`, as gates.py --gate spring reads it.
    It fails closed: a missing part, parts at different commits, a wrong trial count or a gap in coverage is a
    problem in assembled.json, which the gate refuses."""
    output = Path(output)
    # A stale or hand-placed file beside a clean assembly would be scored with it: assemble only into an empty
    # directory, and record the digest of every file written, which the gate checks.
    if output.exists() and any(output.iterdir()):
        raise SystemExit(f'{output} is not empty; assemble into a new directory')
    output.mkdir(parents=True, exist_ok=True)
    manifest = {'schema': 'flint.spring-evidence/2', 'assembled': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                'sources': {}, 'missing': [], 'commits': {}}
    queue = ROOT / 'benchmarks' / 'spring' / 'queue'
    parts = []

    def certified(entry_id):
        directory = certified_results(entry_id)
        if directory is None:
            manifest['missing'].append(entry_id)
            return None
        manifest['sources'][entry_id] = {'directory': str(directory.relative_to(ROOT)),
                                         'receipt_sha256': sha256(directory / 'receipt.json')}
        manifest['commits'][entry_id] = sorted(receipt_commits(directory))
        return directory

    def add(entry_id, directory, name, family):
        path = directory / name
        if not path.is_file():
            manifest['missing'].append(f'{entry_id}/{name}')
            return
        receipt = json.loads((directory / 'receipt.json').read_text())
        parts.append({'entry': entry_id, 'file': name, 'path': path, 'family': family,
                      'record': json.loads(path.read_text()), 'commits': receipt_commits(directory),
                      'steps': receipt.get('summary', {}).get('steps', [])})

    for entry_id, files in PHASE1_FILES.items():
        directory = certified(entry_id)
        for name in files if directory else []:
            add(entry_id, directory, name, 'error')
    families = {'builds.json': 'builds', 'http.json': 'http'}
    for prefix, files in PHASE1_SPLIT.items():
        for entry in sorted(queue.glob(prefix + '*.json')):
            directory = certified(entry.stem)
            for name in files if directory else []:
                add(entry.stem, directory, name, families.get(name, 'acceptance'))
    for entry in sorted(queue.glob(PHASE1_GC_PREFIX + '*.json')):
        directory = certified(entry.stem)
        if directory is None:
            continue
        found = sorted(directory.glob('gc-matrix-*.json'))
        if not found:
            manifest['missing'].append(f'{entry.stem}/gc-matrix-*.json')
        for path in found:
            add(entry.stem, directory, path.name, 'gc')

    errors = [(p['path'], p['record']) for p in parts if p['family'] == 'error']
    if errors:
        (output / 'http-error-paths.json').write_text(json.dumps(merge_http(errors), indent=2) + '\n')
    for name in PHASE1_SPLIT['phase1-builds-'] + PHASE1_SPLIT['phase1-http-']:
        records = [(p['path'], p['record']) for p in parts if p['file'] == name]
        if records:
            merged = PHASE1_MERGE.get(name, merge_acceptance)(records)
            (output / name).write_text(json.dumps(merged, indent=2) + '\n')
    for app in sorted({p['record']['app'] for p in parts if p['family'] == 'gc'}):
        merged = merge_gc([(p['path'], p['record']) for p in parts if p['family'] == 'gc' and p['record']['app'] == app])
        (output / f'gc-matrix-{app}.json').write_text(json.dumps(merged, indent=2) + '\n')

    http_runs = json.loads((ROOT / 'policy' / 'spring-http-benchmark.json').read_text())['workload']['runs']
    error_runs = json.loads((ROOT / 'policy' / 'spring-error-paths-benchmark.json').read_text())['workload']['runs']
    problems = [f'missing certified part: {item}' for item in manifest['missing']]
    problems += (consistency_problems(parts, {'http': http_runs, 'gc': http_runs, 'error': error_runs})
                 + coverage_problems(parts))
    manifest['files'] = {path.name: sha256(path) for path in sorted(output.iterdir()) if path.is_file()}
    commits = {c for p in parts for c in p['commits']}
    manifest['commit'] = next(iter(commits)) if len(commits) == 1 else None
    manifest['problems'] = problems
    manifest['status'] = 'failed' if problems else 'passed'
    (output / 'assembled.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('list')
    p = sub.add_parser('fetch'); p.add_argument('apps', nargs='*')
    p = sub.add_parser('build'); p.add_argument('apps', nargs='+'); p.add_argument('--impl', choices=IMPLEMENTATIONS + CONTEXT_IMPLEMENTATIONS, required=True)
    p = sub.add_parser('record'); p.add_argument('apps', nargs='*')
    p = sub.add_parser('accept'); p.add_argument('apps', nargs='*')
    p.add_argument('--impl', choices=IMPLEMENTATIONS + CONTEXT_IMPLEMENTATIONS)
    p.add_argument('--wire', choices=['exact', 'semantic'])
    p.add_argument('--start', help='start command of an implementation built elsewhere')
    p.add_argument('--url', help='the origin it listens on, http://127.0.0.1:<port>')
    p.add_argument('--cwd', help='with --start: the working directory (a Flint port runs from its own directory)')
    p.add_argument('--no-build', action='store_true', help='use what build/spring already holds')
    p.add_argument('--json', type=Path)
    p = sub.add_parser('register'); p.add_argument('apps', nargs='*')
    sub.add_parser('check-registry')
    p = sub.add_parser('assemble', help="gather the Phase 1 entries' newest certified outputs for gates.py --gate spring")
    p.add_argument('output', type=Path)
    p = sub.add_parser('profile', help='a reproducible local load recipe for profiling (never evidence)')
    p.add_argument('workload'); p.add_argument('--manifest', default='policy/spring-http-benchmark.json')
    p.add_argument('--impl', action='append', choices=['flint', 'go'])
    p.add_argument('--flint-binary'); p.add_argument('--go-binary')
    p.add_argument('--runs', type=int, default=3); p.add_argument('--seconds', type=int, default=15)
    p.add_argument('--warmup', type=int, default=5); p.add_argument('--rate', type=int)
    p.add_argument('--server-cpus'); p.add_argument('--load-cpus'); p.add_argument('--database-cpus')
    p.add_argument('--oha'); p.add_argument('--output')
    p = sub.add_parser('gc-matrix'); p.add_argument('app'); p.add_argument('--output', type=Path, required=True)
    p.add_argument('--smoke', action='store_true'); p.add_argument('--setting', action='append')
    p.add_argument('--gcopt', action='append', help='an arm outside the matrix, <name>=<options>; makes an ab record')
    p.add_argument('--runs', type=int, help="override the manifest's trials; makes an ab record")
    p.add_argument('--no-go', action='store_true', help='leave out the Go comparator; makes an ab record')
    p.add_argument('--binary', help='a stand-in executable for harness checks; never evidence')
    p.add_argument('--smaps', action='store_true', help='a smaps census per phase and every 15 s of the fixed-rate phase')
    p.add_argument('--baseline', type=Path, help='Flint only, against a captured Go baseline record (spring_baseline.py)')
    args = parser.parse_args(argv)
    names = getattr(args, 'apps', None) or list(registry()['apps'])

    if args.command == 'list':
        for name, row in registry()['apps'].items():
            golden = 'recorded' if golden_path(name).is_file() else 'not recorded'
            manifest = ROOT / row['flint']['directory'] / 'flint-spring.json'
            flint = 'ready' if flint_port_ready(name) else ('skeleton' if manifest.is_file() else 'not yet')
            print(f"{name:28} {row['kind']:8} upstream {row['upstream']['commit'][:12]}  golden {golden:13} flint {flint}")
        return 0
    if args.command == 'fetch':
        for name in names:
            print(name, fetch(name))
        return 0
    if args.command == 'build':
        for name in names:
            print(name, build(name, args.impl))
        return 0
    if args.command == 'record':
        for name in names:
            record(name)
        return 0
    if args.command == 'accept':
        if args.start and (len(names) != 1 or args.impl):
            raise SystemExit('--start runs one application and replaces --impl')
        if not args.start and not args.impl:
            raise SystemExit('give --impl or --start')
        records, failed = [], False
        for name in names:
            if args.impl and not args.no_build:
                build(name, args.impl)
            wire = args.wire or WIRE_DEFAULT.get(args.impl, 'exact')
            result = accept(name, args.impl, wire, args.start, args.url, start_cwd=args.cwd)
            records.append(result)
            failed |= not result['success']
            print(f"{name} [{result['implementation']}, wire {wire}]: {result['passed']}/{result['total']} cases pass")
            for case in result['cases']:
                for problem in case['problems']:
                    print(f"  FAIL {case['name']}: {problem}")
        if args.json:
            args.json.parent.mkdir(parents=True, exist_ok=True)
            args.json.write_text(json.dumps(records if len(records) > 1 else records[0], indent=2) + '\n')
        return 1 if failed else 0
    if args.command == 'register':
        register(names)
        return 0
    if args.command == 'assemble':
        manifest = assemble(args.output)
        print(json.dumps(manifest, indent=2))
        return 1 if manifest['problems'] else 0
    if args.command == 'check-registry':
        problems = check_registry()
        for problem in problems:
            print(problem)
        print('registry consistent' if not problems else f'{len(problems)} problem(s)')
        return 1 if problems else 0
    if args.command == 'profile':
        import spring_profile
        return spring_profile.main(args)
    if args.command == 'gc-matrix':
        import spring_gc_matrix
        return spring_gc_matrix.main(args)
    return 2


if __name__ == '__main__':
    sys.exit(main())
