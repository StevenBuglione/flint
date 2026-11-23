# flint:os acceptance traceability

Source: Section 6 of the [os specification](../../handoff/specs/tier-4/os.md).
Tests run with `dub test :os` on DMD and LDC (Linux x86-64). Generated glob patterns use the fixed
LCG seed 8573; every other case uses fixed inputs, so no other seed is needed.

| # | Section 6 item | Covering test(s) | Status |
| --- | --- | --- | --- |
| OS-01a | Child emits 10 MiB to stdout and stderr concurrently: no deadlock | `tests/process.d:the two output pipes drain independently under concurrent writes` (10,485,760 bytes on each pipe, both counts exact) | covered |
| OS-01b | Both streams reach sinks in per-stream order | `tests/process.d:concurrent stdout and stderr each reach their sink in emission order` (two concurrent `seq 1 100000` writers, about 589 KB each, so both pipes fill; each sink's bytes match the sequence exactly) | added |
| OS-02 | Arguments with spaces, quotes, semicolons and `$()` reach the child exactly, with no shell expansion | `tests/process.d:argv, scoped environment and child working directory reach the executable directly`; `tests/process.d:invalid native argument strings are rejected before launch` (NUL in argv and workingDirectory, `=` in an EnvVar name, empty argv) | covered |
| OS-03a | Deadline cancels a child that creates a grandchild: the owned tree terminates and the waitable child is reaped | `tests/process.d:a deadline escalates past an ignored SIGTERM, kills the grandchild and reaps the direct child` (`timedOut && signalled`, SIGKILL after the grace period, direct child gives `ECHILD`, grandchild dead or a zombie of its new parent) | added |
| OS-03b | The same tree under explicit cancellation; deadline and cancel stay distinct outcomes | `tests/process.d:cancellation kills the entire owned group and reaps the waitable child`; `tests/process.d:deadline and explicit cancellation preserve distinct outcomes` | covered |
| OS-04 | Absent executable is `notFound`; child exit 127 is an `ExitStatus` | `tests/process.d:missing executable and the child's exit 127 are distinct`; `tests/process.d:the child resolves its own PATH and does not inherit unrelated descriptors` (PATH search miss is `notFound`) | covered |
| OS-05a | Symlink loop: bounded, no infinite walk | `tests/glob.d:recursive glob confines symlinks, cuts cycles and sorts root-relative paths` (followed ancestor link `a/up -> ..` is cut by device/inode); `tests/glob.d:a deep tree fails at the depth bound and self-referential links are skipped when followed` (self link and two-link cycle give `ELOOP` and are skipped, `loop/**/*` is empty) | covered + added |
| OS-05b | Deep tree: bounded failure without recursion overflow | `tests/glob.d:recursive glob confines symlinks, cuts cycles and sorts root-relative paths` (`maxDepth = 2`); `tests/glob.d:a deep tree fails at the depth bound and self-referential links are skipped when followed` (a file 64 components deep matches; an 80-level tree returns `resourceExhausted` with links followed or not; `maxDepth = 65` is rejected) | covered + added |
| OS-05c | Excessive matches: bounded failure | `tests/glob.d:recursive glob confines symlinks, cuts cycles and sorts root-relative paths` (`maxResults = 2`); `tests/glob.d:a deep tree fails at the depth bound and self-referential links are skipped when followed` (`maxResults = 100001` rejected) | covered + added |
| OS-05d | No traversal outside the root | `tests/glob.d:recursive glob confines symlinks, cuts cycles and sorts root-relative paths` (`escape -> ../outside` not followed, `../` and absolute patterns rejected) | covered |
| OS-06a | Sink throws: child cancelled and reaped, failure propagates once | `tests/process.d:a throwing sink propagates the same exception once after reaping` | covered |
| OS-06b | Sink closes early | `tests/process.d:cancellation kills the entire owned group and reaps the waitable child` (the sink ends consumption by cancelling its Context after the first line; the group is killed and reaped, and `cancelled` is returned once). `OutputSink` is a delegate with no close operation, so cancelling the Context or throwing are the only ways a sink can stop early | covered |
| OS-06c | Sink blocks | `tests/process.d:a stalled sink does not keep the child alive` (child retired while the callback is still blocked, `timedOut` returned once) | covered |
| F-1 | Fuzz every length 0–256, then 1 KiB/1 MiB seeds; reject overflow before allocation | `tests/glob.d:bounded glob syntax survives deterministic length and character-class cases` (seed 8573, lengths 0–256, 1 KiB accepted, 1 MiB rejected as `invalidArgument` before traversal). The process API has no parser; its argv and environment limits are checked in `internal.d:prepare` before launch | covered |
| F-2 | 60-second ASan smoke and 30-minute nightly corpus job | — | blocked (CI-level sanitizer and corpus jobs, not unittests; not run in this pass. Closest local evidence: the deterministic fuzz cases above on DMD and LDC) |
| P-1 | Platform-specific runtime test on each platform that owns a native boundary (Windows `CreateProcessW` and Job Object; macOS) | Linux boundary: every test above | blocked (needs Windows and macOS runners; ADR-017 keeps those platforms out of Milestone 6 scope) |

The suite also covers behaviour from Sections 3 and 4 that Section 6 does not list: capture-limit
overflow (`tests/process.d:capture overflow terminates the command without growing the retained output`),
prompt reaping (`tests/process.d:a quickly exiting child is reaped as soon as its pipes close rather than on the next supervisor poll`),
and SIGINT and SIGTERM subscriptions with graceful and forced shutdown contexts (`tests/interrupts.d`, ADR-028 section 10).
