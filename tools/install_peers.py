#!/usr/bin/env python3
"""Install the pinned binaries that workspace fixture peers need (policy/test-peers.toml, ADR-018).

  go        Go from policy/toolchains.json, into the toolchain directory (tools/install_toolchains.py).
  postgres  A PostgreSQL server built from the source pinned for libpq in policy/native-lock.json.
  valkey, nats, minio, kafka, jre, jdk, maven
            The pins in policy/peer-lock.json: Valkey built with make, nats-server and MinIO built from
            their tagged sources with the pinned Go, and the Kafka, Temurin JRE and JDK, and Maven release
            archives. The JDK and Maven build the vibe benchmark's Spring Boot references.

Every archive is verified against its pinned digest before use. Each peer lands in
.flint/peers/<name>-<version>/ with a flint-peer.json receipt; nothing is taken from the system.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PEERS = ROOT / '.flint' / 'peers'


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def locked(name):
    libraries = json.loads((ROOT / 'policy/native-lock.json').read_text())['libraries']
    rows = libraries if isinstance(libraries, list) else list(libraries.values())
    return next(row for row in rows if row.get('name') == name)


def archive(row):
    """The pinned archive, from the native build's cache or downloaded, verified against the lock."""
    cached = ROOT / '.native' / 'cache' / (row['archive_sha256'] + '.tar.gz')
    if not cached.is_file():
        PEERS.mkdir(parents=True, exist_ok=True)
        cached = PEERS / (row['archive_sha256'] + '.tar.gz')
        if not cached.is_file() or sha256(cached) != row['archive_sha256']:
            with urllib.request.urlopen(row['archive_url'], timeout=120) as response, cached.open('wb') as output:
                shutil.copyfileobj(response, output)
    if sha256(cached) != row['archive_sha256']:
        raise SystemExit('checksum mismatch for ' + row['archive_url'])
    return cached


PEER_LOCK = ROOT / 'policy' / 'peer-lock.json'


def fetch(url, digest, suffix):
    """Download `url` into .flint/peers/archives, verified against its pinned SHA-256."""
    archives = PEERS / 'archives'
    archives.mkdir(parents=True, exist_ok=True)
    target = archives / (digest + suffix)
    if not target.is_file() or sha256(target) != digest:
        partial = target.with_suffix('.partial')
        with urllib.request.urlopen(url, timeout=300) as response, partial.open('wb') as output:
            shutil.copyfileobj(response, output)
        partial.replace(target)
    if sha256(target) != digest:
        raise SystemExit('checksum mismatch for ' + url)
    return target


def extract(archive, destination):
    """Extract an archive's single top-level directory as `destination`."""
    if destination.exists():
        shutil.rmtree(destination)
    staging = destination.with_name(destination.name + '.extract')
    if staging.exists():
        shutil.rmtree(staging)
    with tarfile.open(archive) as bundle:
        bundle.extractall(staging, filter='data')
    (top,) = list(staging.iterdir())
    top.rename(destination)
    staging.rmdir()
    return destination


def go_environment(toolchain):
    go = toolchain / 'go' / 'bin' / 'go'
    if not go.is_file():
        raise SystemExit('the pinned Go is missing; install it first with --peer go')
    env = dict(os.environ, CGO_ENABLED='0', GOTOOLCHAIN='local', GOFLAGS='-mod=readonly',
               GOMODCACHE=str(PEERS / 'gomod'), GOCACHE=str(PEERS / 'gocache'), GOPATH=str(PEERS / 'gopath'))
    env.pop('GONOSUMDB', None)
    env.pop('GONOSUMCHECK', None)
    env.pop('GOSUMDB', None)
    return go, env


def install_locked(name, toolchain, jobs):
    row = json.loads(PEER_LOCK.read_text())['peers'][name]
    prefix = PEERS / (name + '-' + row['version'])
    receipt_path = prefix / 'flint-peer.json'
    if receipt_path.is_file() and json.loads(receipt_path.read_text()).get('archive_sha256') == row['sha256']:
        return json.loads(receipt_path.read_text())
    archive = fetch(row['url'], row['sha256'], '.tar.gz')
    if 'sha512' in row:
        digest = hashlib.sha512(archive.read_bytes()).hexdigest()
        if digest != row['sha512']:
            raise SystemExit('SHA-512 mismatch for ' + row['url'])
    extra = {}
    if row['kind'] == 'archive':
        extract(archive, prefix)
    else:
        source = extract(archive, PEERS / 'src' / (name + '-' + row['version']))
        if prefix.exists():
            shutil.rmtree(prefix)
        (prefix / 'bin').mkdir(parents=True)
        if row['kind'] == 'make':
            # The source tree sits inside the Flint checkout; keep git from reporting Flint's commit as Valkey's.
            env = dict(os.environ, GIT_CEILING_DIRECTORIES=str(source.parent), GIT_DIR=str(source / '.no-git'))
            subprocess.run([part if part != '-j' else '-j' + str(jobs) for part in row['build']], cwd=source, env=env,
                           check=True)
        else:
            go, env = go_environment(toolchain)
            (binary,) = row['binaries']
            subprocess.run([str(go), 'build', '-trimpath', '-o', str(source / binary), '.'], cwd=source, env=env,
                           check=True)
            extra['go'] = subprocess.check_output([str(go), 'version'], text=True).strip()
        for binary, relative in row['binaries'].items():
            shutil.copy2(source / relative, prefix / 'bin' / binary)
    binaries = {}
    for binary, relative in row['binaries'].items():
        path = prefix / relative if row['kind'] == 'archive' else prefix / 'bin' / binary
        binaries[binary] = {'path': str(path.relative_to(ROOT)), 'sha256': sha256(path)}
    receipt = {'schema': 'flint.peer/1', 'peer': name, 'version': row['version'], 'archive_sha256': row['sha256'],
               'commit': row.get('commit'), 'binaries': binaries, **extra}
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


def install_postgres(jobs):
    row = locked('libpq')
    prefix = PEERS / ('postgresql-' + row['version'])
    receipt_path = prefix / 'flint-peer.json'
    if receipt_path.is_file() and json.loads(receipt_path.read_text()).get('archive_sha256') == row['archive_sha256']:
        return json.loads(receipt_path.read_text())
    source_root = PEERS / 'src'
    source = source_root / ('postgresql-' + row['version'])
    if source.exists():
        shutil.rmtree(source)
    source.mkdir(parents=True)
    with tarfile.open(archive(row)) as bundle:
        top = bundle.getmembers()[0].name.split('/')[0]
        bundle.extractall(source_root / 'extract', filter='data')
    shutil.rmtree(source)
    (source_root / 'extract' / top).rename(source)
    shutil.rmtree(source_root / 'extract')
    build = PEERS / 'build' / ('postgresql-' + row['version'])
    if build.exists():
        shutil.rmtree(build)
    disabled = ['docs', 'gssapi', 'icu', 'ldap', 'libcurl', 'libnuma', 'liburing', 'libxml', 'libxslt', 'llvm', 'lz4',
                'nls', 'pam', 'plperl', 'plpython', 'pltcl', 'readline', 'selinux', 'systemd', 'tap_tests', 'zstd', 'zlib']
    subprocess.run(['meson', 'setup', str(build), str(source), '--prefix=' + str(prefix), '--buildtype=release',
                    '-Dssl=none', *['-D' + option + '=disabled' for option in disabled]], check=True)
    subprocess.run(['meson', 'compile', '-C', str(build), '-j', str(jobs)], check=True)
    if prefix.exists():
        shutil.rmtree(prefix)
    subprocess.run(['meson', 'install', '-C', str(build), '--quiet'], check=True)
    binaries = {name: sha256(prefix / 'bin' / name) for name in ('postgres', 'initdb', 'pg_ctl')}
    receipt = {'schema': 'flint.peer/1', 'peer': 'postgres', 'version': row['version'], 'commit': row['commit'],
               'archive_sha256': row['archive_sha256'], 'binaries': binaries}
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


def main():
    cli = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    cli.add_argument('--peer', action='append', required=True,
                     choices=['go', 'postgres', 'valkey', 'nats', 'minio', 'kafka', 'jre', 'jdk', 'maven', 'all'])
    cli.add_argument('--destination', type=Path, default=ROOT / '.tools', help='toolchain directory for go')
    cli.add_argument('--jobs', type=int, default=min(os.cpu_count() or 2, 16))
    args = cli.parse_args()
    receipts = []
    order = ['go', 'postgres', 'valkey', 'nats', 'minio', 'kafka', 'jre', 'jdk', 'maven']
    selected = order if 'all' in args.peer else [peer for peer in order if peer in args.peer]
    for peer in selected:
        if peer in ('valkey', 'nats', 'minio', 'kafka', 'jre', 'jdk', 'maven'):
            receipts.append(install_locked(peer, args.destination.resolve(), args.jobs))
        elif peer == 'go':
            subprocess.run([sys.executable, str(ROOT / 'tools/install_toolchains.py'), '--compiler', 'go',
                            '--destination', str(args.destination)], check=True)
            receipts.append({'peer': 'go', 'bin': str(args.destination / 'go' / 'bin' / 'go')})
        else:
            receipts.append(install_postgres(args.jobs))
    print(json.dumps(receipts))


if __name__ == '__main__':
    main()
