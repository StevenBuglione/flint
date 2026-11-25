#!/usr/bin/env python3
"""posidon freeze-strays for one timed diagnostic (coordinator 2026-11-25 ~07:10Z).

    freeze_strays.py sweep --root <pid> --record <file> --stop <file>   # until <stop> exists, every 2 s
    freeze_strays.py thaw --record <file>

Freezes (SIGSTOP) every process of this user that is a compiler, test, server or tool run, outside the timed run:
- excluded: the run's own tree (descendants of --root), and the run's own scratch PostgreSQL (a postmaster or backend
  started after the sweep began, with its data directory under /tmp/flint-spring-pg-*);
- excluded always: remote-session servers (~/.claude/, editor servers), ssh/sshd/sftp-server, tailscale*, systemd, (sd-pam), dbus-daemon, shells, and any process with a
  controlling terminal (a person's interactive program);
- candidates: an executable under the user's home or /tmp (worktree tools, built servers and tests, .tools
  compilers), or a known build, test or server command.
Each frozen process is recorded with its start time; `thaw` continues only the same processes (pid and start time).
"""
import argparse
import json
import os
import signal
import sys
import time
from pathlib import Path

NEVER = {'sshd', 'ssh', 'sftp-server', 'tailscaled', 'tailscale', 'systemd', '(sd-pam)', 'dbus-daemon', 'bash', 'sh',
         'dash', 'zsh', 'sudo', 'login', 'tmux: server', 'screen', 'agetty', 'cron'}
COMMANDS = {'dmd', 'ldc2', 'ldmd2', 'ld', 'ld.gold', 'ld.bfd', 'ld.lld', 'mold', 'gcc', 'cc', 'cc1', 'cc1plus', 'c++',
            'g++', 'clang', 'as', 'collect2', 'dub', 'flint', 'go', 'compile', 'link', 'vet', 'make', 'ninja', 'cmake',
            'python3', 'python', 'java', 'oha', 'postgres', 'perf', 'strace', 'gdb', 'node'}
HOME = str(Path.home())
REMOTE_SERVERS = ('/.claude/', '/.vscode-server/', '/.cursor-server/', '/.windsurf-server/')


def stat(pid):
    text = Path(f'/proc/{pid}/stat').read_text()
    fields = text.rsplit(')', 1)[1].split()
    return {'ppid': int(fields[1]), 'tty': int(fields[4]), 'start': int(fields[19]), 'state': fields[0]}


def comm(pid):
    return Path(f'/proc/{pid}/comm').read_text().strip()


def ancestors_include(pid, root, table):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid == root:
            return True
        seen.add(pid)
        pid = table.get(pid, 0)
    return False


def candidates(root, since):
    me = os.getuid()
    rows, table = [], {}
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            if os.stat(f'/proc/{pid}').st_uid != me:
                continue
            st = stat(pid)
            table[pid] = st['ppid']
            rows.append((pid, st))
        except OSError:
            continue
    found = []
    for pid, st in rows:
        try:
            command = comm(pid)
            if pid == os.getpid() or command in NEVER or command.startswith('tailscale') or st['tty'] != 0:
                continue
            if st['state'] in ('T', 't'):
                continue  # already stopped (a `hold` pausing its build): leave it to hold, never continue it
            if ancestors_include(pid, root, table):
                continue
            exe = os.readlink(f'/proc/{pid}/exe')
            cwd = os.readlink(f'/proc/{pid}/cwd')
            if any(part in exe for part in REMOTE_SERVERS):
                continue  # remote-session servers (Claude Code, editors): freezing one hangs a session's link
            if command == 'postgres' and '/flint-spring-pg-' in cwd and st['start'] >= since:
                continue  # the run's own disposable cluster (pg_ctl daemonizes it out of the run's tree)
            if not (exe.startswith(HOME + '/') or exe.startswith('/tmp/') or command in COMMANDS):
                continue
            found.append({'pid': pid, 'start': st['start'], 'comm': command, 'exe': exe, 'cwd': cwd})
        except OSError:
            continue
    return found


def boot_ticks_now():
    uptime = float(Path('/proc/uptime').read_text().split()[0])
    return int(uptime * os.sysconf('SC_CLK_TCK'))


def sweep(root, record, stop):
    since = boot_ticks_now()
    frozen = {}
    while not stop.exists():
        for row in candidates(root, since):
            key = (row['pid'], row['start'])
            if key in frozen:
                continue
            try:
                os.kill(row['pid'], signal.SIGSTOP)
            except OSError:
                continue
            row['frozen_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
            frozen[key] = row
            print(f"froze {row['pid']} {row['comm']} ({row['cwd']})", flush=True)
            record.write_text(json.dumps(list(frozen.values()), indent=1) + '\n')
        time.sleep(2)


def thaw(record):
    if not record.exists():
        return
    for row in json.loads(record.read_text()):
        try:
            if stat(row['pid'])['start'] == row['start']:
                os.kill(row['pid'], signal.SIGCONT)
                print(f"continued {row['pid']} {row['comm']}", flush=True)
        except OSError:
            pass


def main():
    p = argparse.ArgumentParser()
    p.add_argument('action', choices=['sweep', 'thaw', 'list'])
    p.add_argument('--root', type=int)
    p.add_argument('--record', type=Path, required=True)
    p.add_argument('--stop', type=Path)
    a = p.parse_args()
    if a.action == 'list':
        for row in candidates(a.root or os.getpid(), boot_ticks_now()):
            print(row['pid'], row['comm'], row['exe'], row['cwd'])
        return
    if a.action == 'sweep':
        sweep(a.root, a.record, a.stop)
    else:
        thaw(a.record)


if __name__ == '__main__':
    sys.exit(main())
