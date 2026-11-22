# flint:term acceptance traceability

Source: `handoff/specs/tier-4/term.md` section 6. Unit tests run with `dub test :term` on DMD and LDC.
PTY rows run `fixtures/pty/test_pty.py fixtures/pty/build/test-term-pty` against the real Linux session
(build with `dub build --root=packages/term/fixtures/pty --compiler=ldc2`, or DMD).

| ID | Required item | Covering test(s) | Status |
| --- | --- | --- | --- |
| TERM-01 | Normal child exit restores canonical/echo flags and alternate screen | `fixtures/pty/test_pty.py:run_suite` mode `normal` (exact termios and screen-mode snapshot `fixtures/pty/screen.hex`) | covered |
| TERM-01 | Exit by a thrown D exception restores the same state | `fixtures/pty/test_pty.py:run_suite` mode `exception` | covered |
| TERM-01 | (related) SIGTERM/SIGHUP still terminate by the signal after restoration | `fixtures/pty/test_pty.py:run_suite` mode `terminate` | covered |
| TERM-02 | Split UTF-8 scalar at each byte boundary gives one correct event | `tests/contract_tests.d:TERM-02 split UTF-8 scalar and CSI at every byte`; PTY mode `events` (`UNICODE`, one byte per write) | covered |
| TERM-02 | Split CSI escape at each byte boundary gives one correct event | `tests/contract_tests.d:TERM-02 split UTF-8 scalar and CSI at every byte`; PTY mode `events` (`CSI`) | covered |
| TERM-02 | Malformed input yields replacement events with an error counter | `tests/contract_tests.d:TERM-02 malformed UTF-8 emits replacement and preserves the next byte` | covered |
| TERM-02 | No busy loop | `feed` helper in `tests/contract_tests.d` asserts each step consumes or emits; `tests/fuzz/corpus.d` bounds steps to 2x input; PTY `--idle` probe (0.04% of one core over 10 s) | covered |
| TERM-02 | 64-byte escape-sequence bound (section 4) | `tests/contract_tests.d:TERM-02 escape sequences up to the 64-byte bound decode and longer ones are discarded` | added |
| TERM-03 | Single ESC then 25 ms silence gives one Escape key on the monotonic clock | `tests/contract_tests.d:TERM-03 a standalone Escape expires once at 25 ms`; PTY mode `escape` (measured with `MonoTime`, >= 25 ms) | covered |
| TERM-04 | Paste over 1 MiB is bounded | `tests/contract_tests.d:TERM-04 paste capacity is inclusive and oversized tails stay data`; `tests/fuzz/corpus.d` 1 KiB/1 MiB boundary seeds | covered |
| TERM-04 | Escape sequences inside a paste stay data | `tests/contract_tests.d:TERM-04 paste is owned, preserves control bytes, and recognizes only its exact marker`; PTY mode `events` (`PASTE` with `ESC[2J`, NUL, 0xFF) | covered |
| TERM-05 | Windows surrogate pair normalized like POSIX | none | blocked (no Windows console backend exists; ADR-017 keeps Windows x86-64 out of Milestone 6 scope and `Session.open` returns `unsupported` off Linux. Closest local evidence: POSIX decoder tests for 4-byte scalars in TERM-02) |
| TERM-05 | Windows mouse record normalized like POSIX | none | blocked (same reason; closest evidence `tests/contract_tests.d:SGR mouse, control keys and unknown or overlong sequences`) |
| TERM-05 | Windows resize record normalized like POSIX | none | blocked (same reason; closest evidence PTY mode `resize`) |
| TERM-06 | stdout pipe: raw setup returns unsupported, ordinary output works | PTY `streams` (stdin and stdout piped) and `piped-output` (terminal stdin, piped stdout: unsupported raw open, plain write, no mode bytes on the terminal, termios unchanged) | added (`piped-output`) |
| TERM-06 | stdin EOF is deterministic | PTY `streams` (two consecutive `eof` events); `tests/contract_tests.d:TERM-02 malformed UTF-8 ...` (repeated `endOfInput`) | covered |
| TERM-06 | Broken output pipe does not crash | PTY `broken` (`ioError`, no SIGPIPE death) | covered |
| TERM-07 | Repeated close: no double close | `tests/contract_tests.d:move-only sessions reject use of an uninitialized handle`; PTY `normal` (close twice) and `piped-output` (close twice, write after close is `cancelled`) | covered |
| TERM-07 | Cancellation while blocked: no deadlock | PTY `cancel` (blocked `next(-1)` on another thread returns `cancelled` after `close`) | covered |
| TERM-07 | SIGWINCH storm: at most one pending resize | PTY `resize` (512 signals, one resize event, then `timedOut`) | covered |
| Fuzz | Every length 0..256, 1 KiB/1 MiB seeds, no overflow | `tests/fuzz/corpus.d:the deterministic terminal decoder seed corpus is bounded and makes progress`; `fixtures/fuzz` timed run | covered |
| Budget | Idle `next` below 1% of one core over 10 s | `fixtures/pty/test_pty.py --idle` | covered |

Stub review: no always-success paths on Linux. Off Linux every operation returns `unsupported`, which is the
documented platform scope (TERM-05 above).
