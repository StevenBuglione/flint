"""Acceptance test for the terminal dashboard (TASK.md), driven through a pseudo-terminal."""
import fcntl
import json
import os
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time
from pathlib import Path

from vibelib import Recorder, visible_text


class Terminal:
    """The program on a pseudo-terminal of a given size; collects everything it writes."""

    def __init__(self, program, arguments, rows=24, columns=80):
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', rows, columns, 0, 0))
        self.slave = slave
        env = program.environment(TERM='xterm-256color', LANG='C.UTF-8', LC_ALL='C.UTF-8')
        self.process = subprocess.Popen(program.command(*arguments), stdin=slave, stdout=slave, stderr=slave,
                                        env=env, start_new_session=True)
        self.output = b''

    def pump(self, seconds):
        deadline = time.monotonic() + seconds
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return
            ready, _, _ = select.select([self.master], [], [], min(remaining, 0.05))
            if ready:
                try:
                    chunk = os.read(self.master, 65536)
                except OSError:
                    return
                if not chunk:
                    return
                self.output += chunk

    def wait_for(self, predicate, seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            self.pump(0.1)
            if predicate(self.text()):
                return True
        return predicate(self.text())

    def text(self, since=0):
        return visible_text(self.output[since:].decode('utf-8', 'replace'))

    def send(self, data):
        os.write(self.master, data)

    def resize(self, rows, columns):
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack('HHHH', rows, columns, 0, 0))
        self.process.send_signal(signal.SIGWINCH)

    def finish(self, seconds=5):
        deadline = time.monotonic() + seconds
        while self.process.poll() is None and time.monotonic() < deadline:
            self.pump(0.05)
        self.pump(0.2)
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()
        return self.process.returncode

    def raw_mode_left(self):
        """Whether the terminal was left without canonical input or echo."""
        attributes = termios.tcgetattr(self.slave)
        return not (attributes[3] & termios.ICANON and attributes[3] & termios.ECHO)

    def close(self):
        for descriptor in (self.master, self.slave):
            try:
                os.close(descriptor)
            except OSError:
                pass


def checks(program):
    r = Recorder()
    with tempfile.TemporaryDirectory(prefix='vibe-tui-') as directory:
        try:
            run_checks(r, program, Path(directory))
        except Exception as error:  # noqa: BLE001 - a crash fails the remaining checks, not the harness
            r.crashed('run', error)
    return r.results


def run_checks(r, program, root):
    missing = subprocess.run(program.command('--source', root / 'absent.jsonl'), capture_output=True, timeout=10,
                             env=program.environment(TERM='xterm-256color'))
    r.check('missing source: exit 2 with a message, screen untouched', missing.returncode == 2 and missing.stderr
            and b'\x1b[?1049h' not in missing.stdout, (missing.returncode, missing.stderr[:200]))

    source = root / 'metrics.jsonl'
    source.write_text('\n'.join(json.dumps(x) for x in [{'name': 'cpu', 'value': 3}, {'name': 'memory', 'value': 2.5},
                                                         {'name': 'disk', 'value': 0.333}]) + '\nnot json\n')
    terminal = Terminal(program, ['--source', source])
    try:
        shown = terminal.wait_for(lambda t: 'cpu' in t and 'memory' in t and 'disk' in t, 10)
        r.check('shows the metrics', shown, terminal.text()[-800:])
        text = terminal.text()
        r.check('title names the file', 'Dashboard' in text and 'metrics.jsonl' in text, text[-800:])
        r.check('values print with up to two decimals', '2.5' in text and '0.33' in text and '0.333' not in text,
                text[-800:])
        r.check('footer counts metrics and skipped lines', '3 metrics, 1 skipped' in text, text[-800:])
        raw = terminal.output
        r.check('uses the alternate screen and hides the cursor', b'\x1b[?1049h' in raw and b'\x1b[?25l' in raw)

        mark = len(terminal.output)
        with source.open('a') as stream:
            stream.write(json.dumps({'name': 'network', 'value': 42}) + '\n')
            stream.write(json.dumps({'name': 'cpu', 'value': 7.25}) + '\n')
        followed = terminal.wait_for(lambda _: 'network' in terminal.text(mark) and '7.25' in terminal.text(mark), 5)
        r.check('follows the file and replaces values', followed, terminal.text(mark)[-800:])
        r.check('footer updates', terminal.wait_for(lambda _: '4 metrics, 1 skipped' in terminal.text(mark), 3),
                terminal.text(mark)[-400:])

        mark = len(terminal.output)
        terminal.send(b's')
        terminal.pump(1.0)
        after = terminal.text(mark)
        order = [after.rfind(name) for name in ('network', 'cpu', 'memory', 'disk')]
        r.check('s sorts by value, largest first', all(i >= 0 for i in order) and order == sorted(order), after[-800:])

        terminal.send(b'j')
        terminal.send(b'\x1b[B')
        terminal.pump(0.5)
        r.check('j and arrow keys keep it running', terminal.process.poll() is None)

        terminal.resize(12, 50)
        terminal.pump(1.0)
        r.check('survives a resize to 50x12', terminal.process.poll() is None)

        terminal.send(b'q')
        code = terminal.finish()
        raw = terminal.output
        r.equal('q quits with exit 0', code, 0)
        r.check('restores the main screen and the cursor', raw.rfind(b'\x1b[?1049l') > raw.rfind(b'\x1b[?1049h')
                and raw.rfind(b'\x1b[?25h') > raw.rfind(b'\x1b[?25l'))
        r.check('leaves the terminal out of raw mode', not terminal.raw_mode_left())
    finally:
        if terminal.process.poll() is None:
            terminal.process.kill()
        terminal.close()

    terminal = Terminal(program, ['--source', source])
    try:
        terminal.wait_for(lambda t: 'cpu' in t, 10)
        terminal.process.send_signal(signal.SIGTERM)
        code = terminal.finish()
        raw = terminal.output
        r.check('SIGTERM: exit 0 with the terminal restored', code == 0 and raw.rfind(b'\x1b[?1049l')
                > raw.rfind(b'\x1b[?1049h') and not terminal.raw_mode_left(), code)
    finally:
        if terminal.process.poll() is None:
            terminal.process.kill()
        terminal.close()
