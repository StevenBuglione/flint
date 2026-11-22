# Implementation review of Milestones 1–5

All 37 packages were reviewed for correctness, specification conformance, safety-policy compliance and hot-path performance before any further milestone work. Every fix below started with a behavioural or compiler-negative test that failed on the previous code. Public import paths, UDAs, documented APIs, diagnostics, help output and completion scripts are unchanged, so applications keep the same annotation-driven programming model.

Each change was verified on DMD and LDC with the package's own suite, the structural gate and `tools/quality.py`. Suites that depend on external peers were also run against them: the HTTPS JWKS fixture (security), Valkey 9.1.2 (cache), PostgreSQL 18.6 (sql, data, migrate), the Go provider and protocol peers (http, mail), the AI loopback peer, the terminal PTY suite, template compile-negative cases, and the native and wasm32 BetterC fixtures.

## Results after the review

Measured on the merged code with the Flint toolchain fork on the same local x86-64 workstation (not the designated runner). Ratios are Flint/Go medians with the repository's 99% bootstrap interval; lower is better except capacity.

| Metric | Flint | Go 1.27.4 | Flint / Go (99% interval) |
| --- | ---: | ---: | --- |
| CLI cold build | 95.3 ms | 110.0 ms | 0.867 (0.829–0.897) |
| CLI build after edit | 71.7 ms | 108.4 ms | 0.662 (0.633–0.681) |
| REST cold build | 122.7 ms | 193.8 ms | 0.633 (0.576–0.650) |
| REST build after edit | 98.5 ms | 193.1 ms | 0.510 (0.485–0.528) |
| REST capacity | 184,428 req/s | 69,099 req/s | 2.669 (2.479–2.793) |
| p50 at 20,000 req/s | 0.151 ms | 0.269 ms | 0.559 (0.545–0.585) |
| p99 at 20,000 req/s | 0.643 ms | 4.981 ms | 0.129 (0.102–0.209) |
| p99.9 at 20,000 req/s | 5.04 ms | 18.34 ms | 0.275 (0.180–0.560) |
| Peak RSS | 13.13 MB | 14.39 MB | 0.913 (0.881–0.952) |
| CPU per request | 11.58 µs | 18.68 µs | 0.620 (0.602–0.639) |
| Stripped CLI (Oz) | 1,225,904 B | 2,732,192 B | 0.449 |
| Stripped REST (Oz) | 6,474,608 B | 6,598,816 B | 0.981 |

The runtime rows are the full production protocol of `tools/load_bench.py` (nine alternating pairs, 10 s warmup, 60 s fixed-rate and 60 s capacity phases, server CPUs 2–3, load CPUs 4–7). The build rows are nine paired trials of `tools/compare_go_builds.py`; the compile server held only druntime and Phobos, as ADR-016 proposes. Before the review the same protocol measured 176,797 req/s, 0.777 ms p99, 12.56 MB and 12.8 µs per request. The REST binary-size margin is under 1% and needs watching.

One review change moved field coercion for 13 common types into config; it sped up edits but made config the critical path of parallel cold builds (CLI cold 140 ms, 1.29× Go). It was narrowed back to per-application instantiation, keeping the other template reductions.

The full matrix on the merged code passed: every package's suite on DMD and LDC, the fixture-backed suites listed above, PostgreSQL-backed sql/data/migrate, the golden CLI, the golden REST verifier and a PTY run of the golden TUI on both compilers.

## Fixed defects

| Package | Defect | Effect before the fix |
| --- | --- | --- |
| reactor | 32-bit operation-slot generation retired busy slots permanently | After ~a month at 400k ops/s per worker every read/write failed with resourceExhausted |
| reactor | EMFILE/ENFILE during accept was fatal | Descriptor exhaustion stopped the whole server |
| reactor | Owner loop ignored suspended-fiber deadlines | Waits under 5 ms and callback-posted tasks slept the full 5 ms |
| reactor | Accepted sockets kept Nagle enabled | HTTP/2, gRPC and WebSocket replies stalled ~40 ms |
| os | Child exit noticed only on a 5 ms poll | Every child run paid up to 5 ms extra |
| serde | JSON duplicate-key check rescanned earlier members | 1 MiB object took 4.2 s (reachable via MCP, JWT, JWKS) |
| serde | TOML sibling lookup compared keys scalar by scalar | Crafted 1 MiB file took up to 7.9 s |
| config | Text overrides used a different float rounding | `--set`/env values differed from the same value in a file |
| log | Redirected stdout reopened as a second handle | Log records overwrote application output in files |
| term | SIGTERM/SIGHUP left the terminal raw | `kill` left the alternate screen and raw mode active |
| web | Request-side half-close cancelled the connection | Multi-write responses were truncated |
| web | `Expect: 100-continue` ignored | Waiting clients stalled for their timeout |
| web | 204/304 carried `Content-Length: 0` | RFC 9110 violation |
| web | Upgrade offer on an ordinary route returned 400 | `curl --http2` against an HTTP/1 route failed |
| web | Streaming waits polled every 1 ms | 4 MiB stream delivered 3.2 MB in 5 s; echo round trip 5 ms |
| http | Client waits polled every 1 ms on fibers | ~5.1 ms per loopback exchange |
| security | JWKS keys refreshed only after expiry | All tokens denied for up to 10–30 s every TTL |
| rpc | Malformed `grpc-message` discarded a valid status | Server status reported as unavailable |
| sql | Off-reactor waiters polled every 2 ms | Pools with more threads than connections collapsed (730 ops/s) |
| sql (native) | COMMIT answered with ROLLBACK reported as success | Writes silently lost after a failed statement |
| cache | `put` did not invalidate an in-flight load | A slow loader replaced newer data for the full TTL |
| mq | JetStream handler could not publish on its client | consume-then-produce returned conflict |
| mq | JetStream commands split into small writes; native socket kept Nagle | ~40 ms per request |
| template | Resource ending in `<` treated as plain text | Contextual-escaping bypass through includes |
| template | Field paths not restricted to `model` or loop bindings | Renderer internals reachable; raw D errors |
| mcp | Per-request cancellation could interrupt a started stdio reply | Half a JSON-RPC line corrupted later framing |
| mail | CR/LF/tab escaped as 6-byte sequences in provider JSON | Valid bodies under the MIME limit rejected |
| tui | Resize burst returning to the displayed size skipped repaint | Screen left with reflowed contents |

## Performance changes

Measured before and after on the same machine; details are in the commit messages.

- conc: lock-free context copy, check and release (4 threads 839 → 113 ns per iteration).
- reactor: one clock sample per tick and a dense suspended-fiber list (1,000 parked fibers: 36.0 → 2.8 µs per loop hop).
- serde: JSON round trips 36–89% faster with byte-identical output (16 KiB plain 519 → 58 µs).
- config and cli: application template cost reduced (bench-cli `app.d` ~99 → ~77 ms checked DMD compile; `load!Settings` semantic analysis 7.1 → 1.3 ms).
- log: futex-parked consumer and arithmetic UTC timestamps (release probe 3.9k → ~270k lines/s).
- web: per-connection cancellation source (lock acquisitions per keep-alive request 41 → 22; capacity +2.6–4.7%).
- sql: futex-woken lease handoff (2 threads / 1 connection SQLite 730 → 71k ops/s).
- cache: lock-free local put/evict while no load runs (8 threads 334k → 1.93M ops per trial).
- ai: SSE parsing 2.9× faster; template: escaping 3× faster; mcp: single-pass envelope handling.
- tui and widgets: ASCII fast paths (1k-row table 40.8 → 15.5 µs per frame).

## Environment findings

- `desktop` fails `tests/sdl_runtime.d(19)` on this NixOS/Hyprland workstation although a Wayland display is present: the pinned static SDL3 has only x11/offscreen/dummy drivers (the spec disables Wayland), it `dlopen`s `libX11.so.6`, which NixOS does not place on a default search path, and the current Xwayland for `:0` listens on `/tmp/.X11-unix/X0_` while a stale Xwayland holds the standard abstract socket. With `SDL_VIDEO_DRIVER=offscreen` both desktop modules pass on DMD and LDC. A separate redesign of the desktop package on a native Wayland path is in progress.
- The earlier `rpc` link failure came from a test-copy helper that dropped the nested `FLINT RPC TEST NATIVE` recipe block; with both blocks `rpc` passes.

## Open findings

| Severity | Area | Finding |
| --- | --- | --- |
| Medium | reactor | No primitive to wake a suspended fiber on I/O completion; web and http re-check for 200 µs, then poll every 1 ms |
| Medium | reactor | io_uring delivers a cancelled read that completed with data as `cancelled` with an empty slice; needs a `Completion` semantics decision |
| Medium | reactor | `post()`/`close()` from another thread wait for the next backend wake (no eventfd/msg-ring wakeup) |
| Medium | native/ffi | io_uring submit and wait are two syscalls; CQEs are reaped one per call |
| Medium | native/ffi | SQLite worker handoff is ~40× slower than direct SQLite |
| Medium | mq | JetStream has no reconnect after a request error or timeout |
| Medium | web (TLS) | A TLS `close_notify` half-close still drops the response |
| Medium | config | Two `@ConfigurationProperties` types cannot share one file while unknown keys are rejected |
| Medium | serde | `decodeTomlInto` keeps a 43 KB document on the stack (fibers can be 16 KiB) |
| Medium | conc | WorkerPool idles with 50 µs sleeps |
| Low | log | Per-thread ring share is 8 records by default |
| Low | di | `@PreDestroy` runs for a bean whose `@PostConstruct` failed; an existing test asserts this against the specification |
| Low | web | No `Date` header; wrong method returns 404 rather than 405 |
| Low | serde | Float output is exact decimal rather than shortest round-trip |
| Low | actuator | OTLP export sends 32 series per interval |
| Low | others | See the commit messages of this review for the remaining low-severity items |

h2spec v2.6.0 still reports 138/146; the 8 remaining cases are decided by nghttp2 and the native shim.
