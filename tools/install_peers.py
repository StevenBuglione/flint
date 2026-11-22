#!/usr/bin/env python3
"""Install the pinned binaries that workspace fixture peers need (policy/test-peers.toml, ADR-018).

  go        Go from policy/toolchains.json, into the toolchain directory (tools/install_toolchains.py).
  postgres  A PostgreSQL server built from the source pinned for libpq in policy/native-lock.json,
            into .flint/peers/postgresql-<version>/ with a receipt.

Peers without a pinned release (Valkey, MinIO) are refused rather than taken from the system.
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
    cli.add_argument('--peer', action='append', required=True, choices=['go', 'postgres', 'valkey', 'minio'])
    cli.add_argument('--destination', type=Path, default=ROOT / '.tools', help='toolchain directory for go')
    cli.add_argument('--jobs', type=int, default=min(os.cpu_count() or 2, 16))
    args = cli.parse_args()
    receipts = []
    for peer in args.peer:
        if peer in ('valkey', 'minio'):
            raise SystemExit(peer + ' has no pinned release in policy/; pin one before installing it')
        if peer == 'go':
            subprocess.run([sys.executable, str(ROOT / 'tools/install_toolchains.py'), '--compiler', 'go',
                            '--destination', str(args.destination)], check=True)
            receipts.append({'peer': 'go', 'bin': str(args.destination / 'go' / 'bin' / 'go')})
        else:
            receipts.append(install_postgres(args.jobs))
    print(json.dumps(receipts))


if __name__ == '__main__':
    main()
