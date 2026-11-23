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
WIRE_DEFAULT = {'java': 'exact', 'flint': 'exact', 'go': 'semantic'}

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
    run(spec['build'], directory, dict(os.environ))
    produced = directory / spec['binary']
    if not produced.is_file():
        raise SystemExit(f'{name}: the Flint build did not produce {produced}')
    BUILD.mkdir(parents=True, exist_ok=True)
    shutil.copy2(produced, flint_binary(name))
    return flint_binary(name)


def build(name, implementation):
    return {'java': build_java, 'go': build_go, 'flint': build_flint}[implementation](name)


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


def launch(name, implementation, port, database=None, extra_args=()):
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
    binary = go_binary(name) if implementation == 'go' else flint_binary(name)
    if not binary.is_file():
        raise SystemExit(f'{name}: build the {implementation} implementation first '
                         f'(spring_bench.py build {name} --impl {implementation})')
    return [str(binary), *extra_args], env, ROOT


def load_suite(name):
    return importlib.import_module(app_row(name)['suite'])


@contextlib.contextmanager
def maybe_postgres(name):
    if app_row(name).get('database') == 'postgres':
        with postgres_cluster() as database:
            yield database
    else:
        yield None


def observe(name, implementation=None, start=None, url=None, logs=None, mask=True):
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
            if database is not None:
                env.update(database())
            cwd = ROOT
            port = int(url.rsplit(':', 1)[1].split('/')[0]) if url else free_port()
            env.setdefault('SERVER_PORT', str(port))
        else:
            port = free_port()
            command, env, cwd = launch(name, implementation, port, database)
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


def accept(name, implementation, wire, start=None, url=None):
    golden = json.loads(golden_path(name).read_text())
    observed, seconds = observe(name, implementation, start, url, mask=False)
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
            'start': start, 'wire': wire, 'golden_sha256': sha256(golden_path(name)), 'cases': cases,
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
        previous = rows['comparators'].get(name)
        if previous and previous['sha256'] != comparator_digest(name) and previous.get('measured'):
            raise SystemExit(f'{name}: the registered comparator has been measured; changing it needs an ADR')
        rows['comparators'][name] = {'directory': directory, 'commit': commit, 'sha256': comparator_digest(name),
                                     'go': go_version, 'wire': 'semantic',
                                     'registered': time.strftime('%Y-%m-%d', time.gmtime()), 'measured': False}
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
        else:
            try:
                git('merge-base', '--is-ancestor', row['commit'], 'HEAD')
            except subprocess.CalledProcessError:
                problems.append(f'{name}: the registered commit {row["commit"][:12]} is not in this history')
    return problems


# ---------------------------------------------------------------------------------------------------------------


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('list')
    p = sub.add_parser('fetch'); p.add_argument('apps', nargs='*')
    p = sub.add_parser('build'); p.add_argument('apps', nargs='+'); p.add_argument('--impl', choices=IMPLEMENTATIONS, required=True)
    p = sub.add_parser('record'); p.add_argument('apps', nargs='*')
    p = sub.add_parser('accept'); p.add_argument('apps', nargs='*')
    p.add_argument('--impl', choices=IMPLEMENTATIONS)
    p.add_argument('--wire', choices=['exact', 'semantic'])
    p.add_argument('--start', help='start command of an implementation built elsewhere')
    p.add_argument('--url', help='the origin it listens on, http://127.0.0.1:<port>')
    p.add_argument('--no-build', action='store_true', help='use what build/spring already holds')
    p.add_argument('--json', type=Path)
    p = sub.add_parser('register'); p.add_argument('apps', nargs='*')
    sub.add_parser('check-registry')
    p = sub.add_parser('gc-matrix'); p.add_argument('app'); p.add_argument('--output', type=Path, required=True)
    p.add_argument('--smoke', action='store_true'); p.add_argument('--setting', action='append')
    args = parser.parse_args(argv)
    names = getattr(args, 'apps', None) or list(registry()['apps'])

    if args.command == 'list':
        for name, row in registry()['apps'].items():
            golden = 'recorded' if golden_path(name).is_file() else 'not recorded'
            flint = 'present' if (ROOT / row['flint']['directory'] / 'flint-spring.json').is_file() else 'not yet'
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
            result = accept(name, args.impl, wire, args.start, args.url)
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
    if args.command == 'check-registry':
        problems = check_registry()
        for problem in problems:
            print(problem)
        print('registry consistent' if not problems else f'{len(problems)} problem(s)')
        return 1 if problems else 0
    if args.command == 'gc-matrix':
        import spring_gc_matrix
        return spring_gc_matrix.main(args)
    return 2


if __name__ == '__main__':
    sys.exit(main())
