# Flint terminal sessions

Linux sessions own a snapshot of the terminal settings, duplicated stream
descriptors, and a cancellation pipe. Raw mode requires terminal input
and output. A non-raw session can write ordinary redirected output and
receive EOF from an input stream.

`Session` is move-only. Close wakes a blocked read or write, waits for the
I/O gates, and restores the prior termios settings and owned screen modes.
Scope exit also closes the owner, including when a D exception unwinds the
scope. Keep the owner alive until concurrent callers have finished.

An active terminal session converts SIGWINCH and SIGINT into resize and
interrupt events. Ctrl-C in raw input also produces an interrupt event.
When SIGTERM or SIGHUP still has its default action, the session observes
it too: the handler only records the signal, a process-lifetime native
thread restores the terminal under the session lock, and the signal is
then delivered again with its default action, so the process still
terminates by that signal. An application handler or an ignored
termination signal is left untouched.
Linux uses nonblocking signal pipes and a monotonic poll deadline. The
process retains one bounded pair of pipes for each watched signal so an
already-running handler can finish without writing to a reused descriptor.
Terminal signal registration is process-wide. Register signal handlers
serially during startup. An existing custom SIGINT owner causes
`Session.open` to return a conflict.

The decoder holds at most 64 bytes for an escape sequence and waits 25 ms
for a standalone Escape. The input slab is 32 KiB. It preserves split
UTF-8 and replaces malformed key-stream bytes. Bracketed paste returns an
owned string with the original bytes, including embedded control bytes.
Paste over 1 MiB reports a resource error and discards the remainder
through the closing marker. Sanitize pasted text before writing it as
terminal formatting.

## Recovery after forced termination

Another fatal signal, such as SIGKILL, can terminate the process before
any cleanup runs. To
restore the terminal from the shell, use:

```sh
stty sane
printf '\033[?2004l\033[?1006l\033[?1000l\033[?1049l'
```

## Linux verification

```sh
dub test :term --compiler=dmd
dub test :term --compiler=ldc2
python3 tools/gates.py --package term --gate structural
dub build --root=packages/term/fixtures/pty --compiler=ldc2
python3 packages/term/fixtures/pty/test_pty.py packages/term/fixtures/pty/build/test-term-pty
python3 packages/term/fixtures/pty/test_pty.py packages/term/fixtures/pty/build/test-term-pty --idle
```

The PTY fixture checks the original termios settings and the exact ANSI
mode snapshot after normal exit, exception unwinding, resize storms,
SIGINT, termination by SIGTERM and SIGHUP, input decoding and
blocked-reader cancellation. It also checks
redirected streams and a broken output pipe.

`fixtures/fuzz` runs the deterministic short-length and paste-boundary
corpus, then samples additional inputs for the requested number of
seconds. Its duration defaults to 60 seconds and supports 1800 seconds
for the nightly corpus. Use the ASan build flags for the fuzz job and
the PTY fixture.

The feature probe in `bench/` replays a 10 MiB trace in 1-, 4-, and
4096-byte chunks. Its control verifies the same trace against the
expected event sequence. Pass `--measure` to record decoder throughput
and the calling thread's GC allocation count. The separate PTY idle
probe measures CPU while `next` waits for ten seconds.
