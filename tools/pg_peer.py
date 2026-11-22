#!/usr/bin/env python3
"""Run a command against a disposable PostgreSQL cluster (the sql, data and migrate fixture peer).

The cluster is created in a temporary directory, listens on a free loopback port, and is stopped
and deleted afterwards. Every --variable receives the libpq connection string.
"""
import argparse
import contextlib
import os
import socket
import subprocess
import sys
import tempfile
from pathlib import Path


def free_port():
    with contextlib.closing(socket.socket()) as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--bin', type=Path, required=True, help='PostgreSQL bin directory (initdb, pg_ctl)')
    cli.add_argument('--variable', action='append', required=True, help='environment variable for the DSN')
    cli.add_argument('command', nargs=argparse.REMAINDER)
    args = cli.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        cli.error('a test command is required')
    initdb, pg_ctl = args.bin / 'initdb', args.bin / 'pg_ctl'
    for tool in (initdb, pg_ctl):
        if not tool.is_file():
            raise SystemExit('PostgreSQL tool missing: ' + str(tool))
    with tempfile.TemporaryDirectory(prefix='flint-pg-') as directory:
        data, log = Path(directory) / 'data', Path(directory) / 'server.log'
        quiet = {'stdout': subprocess.DEVNULL, 'stderr': subprocess.STDOUT}
        subprocess.run([str(initdb), '-D', str(data), '-U', 'flint', '--auth=trust', '--encoding=UTF8',
                        '--locale=C.UTF-8', '--no-sync'], check=True, **quiet)
        port = free_port()
        options = f"-c listen_addresses=127.0.0.1 -p {port} -k {directory} -c fsync=off"
        subprocess.run([str(pg_ctl), '-D', str(data), '-l', str(log), '-o', options, '-w', '-t', '60', 'start'],
                       check=True, **quiet)
        try:
            dsn = f'host=127.0.0.1 port={port} user=flint dbname=postgres'
            env = dict(os.environ, **{name: dsn for name in args.variable})
            result = subprocess.run(command, env=env, check=False, timeout=900)
        finally:
            subprocess.run([str(pg_ctl), '-D', str(data), '-m', 'fast', '-w', 'stop'], check=False, **quiet)
        if result.returncode:
            print(log.read_text()[-4000:], file=sys.stderr)
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
