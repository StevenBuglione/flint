"""Oracle for tui-dashboard: a minimal Python solution that proves the acceptance test is sound. Not a benchmark
entry."""
import argparse
import json
import os
import select
import shutil
import signal
import sys
import termios
import tty
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True)
source = Path(parser.parse_args().source)
if not source.is_file():
    print(f'dash: {source}: no such file', file=sys.stderr)
    sys.exit(2)

metrics, skipped, offset = {}, 0, 0
selected, sorting, quit_requested = 0, False, False


def read_new():
    global skipped, offset
    with source.open('rb') as stream:
        stream.seek(offset)
        data = stream.read()
    complete = data[:data.rfind(b'\n') + 1]
    offset += len(complete)
    for line in complete.decode('utf-8', 'replace').splitlines():
        try:
            item = json.loads(line)
            if not (isinstance(item, dict) and isinstance(item.get('name'), str)
                    and isinstance(item.get('value'), (int, float)) and not isinstance(item.get('value'), bool)):
                raise ValueError
            metrics[item['name']] = item['value']
        except ValueError:
            skipped += 1
    return bool(complete)


def number(value):
    text = f'{value:.2f}'.rstrip('0').rstrip('.')
    return text or '0'


def draw():
    columns, rows = shutil.get_terminal_size()
    names = sorted(metrics, key=lambda n: -metrics[n]) if sorting else list(metrics)
    out = ['\x1b[H\x1b[2J', f'\x1b[1mDashboard — {source.name}\x1b[0m'[:columns + 8]]
    for index, name in enumerate(names[:max(rows - 3, 0)]):
        line = f'{name:<{max(columns - 14, 1)}}{number(metrics[name]):>12}'[:columns]
        out.append('\r\n' + ('\x1b[7m' + line + '\x1b[0m' if index == selected else line))
    out.append(f'\x1b[{rows};1H{len(metrics)} metrics, {skipped} skipped — q quits, s sorts'[:columns + 10])
    sys.stdout.write(''.join(out))
    sys.stdout.flush()


def stop(*_):
    global quit_requested
    quit_requested = True


saved = termios.tcgetattr(0)
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGWINCH, lambda *_: draw())
tty.setraw(0)
sys.stdout.write('\x1b[?1049h\x1b[?25l')
try:
    read_new()
    draw()
    while not quit_requested:
        ready, _, _ = select.select([0], [], [], 0.25)
        changed = read_new()
        if ready:
            key = os.read(0, 16)
            if key in (b'q', b'\x1b', b'\x03'):
                break
            if key == b's':
                sorting = not sorting
            elif key in (b'j', b'\x1b[B'):
                selected = min(selected + 1, max(len(metrics) - 1, 0))
            elif key in (b'k', b'\x1b[A'):
                selected = max(selected - 1, 0)
            changed = True
        if changed:
            draw()
finally:
    termios.tcsetattr(0, termios.TCSADRAIN, saved)
    sys.stdout.write('\x1b[?25h\x1b[?1049l')
    sys.stdout.flush()
sys.exit(0)
