#!/usr/bin/env python3
"""Drive Flint's actual Linux terminal session using a PTY and standard streams."""

import argparse
from contextlib import contextmanager
import errno
import fcntl
import json
import os
from pathlib import Path
import resource
import select
import signal
import struct
import subprocess
import termios
import time


SNAPSHOT = bytes.fromhex(
    " ".join(line for line in Path(__file__).with_name("screen.hex").read_text().splitlines()
             if line and not line.startswith("#"))
)


def size(slave, columns, rows):
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))


def stderr_line(process, expected, timeout=3):
    """Read one unbuffered record with a deadline even if the child hangs."""
    line = bytearray()
    deadline = time.monotonic() + timeout
    fd = process.stderr.fileno()
    while True:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([fd], [], [], remaining)[0], (expected, bytes(line))
        byte = os.read(fd, 1)
        assert byte, (expected, bytes(line), process.poll())
        if byte == b"\n":
            break
        line += byte
    record = line.decode("ascii")
    assert record.startswith(expected), (expected, record)
    return record


def read_snapshot(master):
    output = bytearray()
    while select.select([master], [], [], 0)[0]:
        try:
            part = os.read(master, 4096)
        except OSError as error:
            if error.errno == errno.EIO:
                break
            raise
        if not part:
            break
        output += part
    return bytes(output)


@contextmanager
def terminal_child(program, mode, status=0):
    master, slave = os.openpty()
    try:
        size(slave, 80, 24)
        initial = termios.tcgetattr(slave)
        env = dict(os.environ, TERM="xterm-256color", COLORTERM="truecolor")
        env.pop("NO_COLOR", None)
        with subprocess.Popen(
            [program, mode], stdin=slave, stdout=slave, stderr=subprocess.PIPE, env=env, bufsize=0
        ) as process:
            try:
                yield process, master, slave
                assert process.wait(timeout=5) == status, process.stderr.read().decode(errors="replace")
                assert termios.tcgetattr(slave) == initial, mode
                expected = b"" if mode == "conflict" else SNAPSHOT
                output = read_snapshot(master)
                assert output == expected, (mode, output.hex(), expected.hex())
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
    finally:
        os.close(master)
        os.close(slave)


def await_raw(process, slave):
    stderr_line(process, "READY")
    local_flags = termios.tcgetattr(slave)[3]
    assert not local_flags & (termios.ICANON | termios.ECHO | termios.ISIG), local_flags


def split_input(master, payload):
    for byte in payload:
        os.write(master, bytes([byte]))
        time.sleep(0.001)


def run_suite(program):
    for mode in ("normal", "exception"):
        with terminal_child(program, mode) as (process, master, slave):
            await_raw(process, slave)
            os.write(master, b"x")
            if mode == "exception":
                stderr_line(process, "CAUGHT")
        print(f"TERM-01 {mode}: exact termios and screen restoration")

    with terminal_child(program, "events") as (process, master, slave):
        await_raw(process, slave)
        split_input(master, "🦊".encode())
        stderr_line(process, "UNICODE")
        split_input(master, b"\x1b[1;6A")
        stderr_line(process, "CSI")
        split_input(master, b"\x1b[200~abc\x1b[2J\x00\xff\x1b[201~")
        stderr_line(process, "PASTE")
        os.write(master, b"\x03")
        stderr_line(process, "CTRL_C")
    print("TERM-02/04: split UTF-8, split CSI, paste bytes and raw Ctrl-C")

    with terminal_child(program, "escape") as (process, master, slave):
        await_raw(process, slave)
        os.write(master, b"\x1b")
        print("TERM-03", stderr_line(process, "ESCAPE"))

    with terminal_child(program, "resize") as (process, _, slave):
        await_raw(process, slave)
        size(slave, 113, 47)
        for _ in range(512):
            os.kill(process.pid, signal.SIGWINCH)
        stderr_line(process, "RESIZED_ONCE")
    with terminal_child(program, "signal") as (process, _, slave):
        await_raw(process, slave)
        os.kill(process.pid, signal.SIGINT)
        stderr_line(process, "SIGNAL_INTERRUPT")
    for number in (signal.SIGTERM, signal.SIGHUP):
        # Default termination signals still terminate the process, after the session restores its terminal.
        with terminal_child(program, "terminate", -number) as (process, _, slave):
            await_raw(process, slave)
            os.kill(process.pid, number)
    with terminal_child(program, "cancel") as (process, _, _):
        stderr_line(process, "CANCELLED")
    with terminal_child(program, "conflict") as (process, _, _):
        stderr_line(process, "CONFLICT")
    print("TERM-07: resize coalescing, signal delivery, termination restoration, blocked close and signal ownership conflict")

    streams = subprocess.run([program, "streams"], input=b"", capture_output=True, timeout=3, check=True)
    assert streams.stdout == b"ordinary output\n", streams.stdout
    read_fd, write_fd = os.pipe()
    os.close(read_fd)
    try:
        subprocess.run([program, "broken"], input=b"", stdout=write_fd, stderr=subprocess.PIPE,
                       timeout=3, check=True)
    finally:
        os.close(write_fd)
    master, slave = os.openpty()
    try:
        size(slave, 80, 24)
        initial = termios.tcgetattr(slave)
        piped = subprocess.run([program, "piped-output"], stdin=slave, capture_output=True, timeout=3, check=True)
        assert piped.stdout == b"ordinary output\n", piped.stdout
        assert termios.tcgetattr(slave) == initial
        assert read_snapshot(master) == b"", "redirected output must not send terminal modes"
    finally:
        os.close(master)
        os.close(slave)
    print("TERM-06: redirected stdout, terminal stdin with piped stdout, repeated EOF and broken-pipe error")


def measure_idle(program):
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    with terminal_child(program, "idle") as (process, _, slave):
        await_raw(process, slave)
        start = time.monotonic()
        stderr_line(process, "IDLE_TIMEOUT", timeout=12)
        elapsed = time.monotonic() - start
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    consumed = (after.ru_utime - before.ru_utime) + (after.ru_stime - before.ru_stime)
    ratio = consumed / elapsed
    assert elapsed >= 9.8 and ratio < 0.01, (elapsed, consumed, ratio)
    print(json.dumps({"idle_wall_seconds": elapsed, "child_cpu_seconds": consumed, "one_core_fraction": ratio}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--idle", action="store_true", help="run the 10-second idle CPU measurement")
    args = parser.parse_args()
    program = str(args.executable.resolve(strict=True))
    if args.idle:
        measure_idle(program)
    else:
        run_suite(program)


if __name__ == "__main__":
    main()
