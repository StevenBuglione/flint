# flint:conc acceptance traceability

Source: Section 6 of the [concurrency specification](../../handoff/specs/tier-0/conc.md).
Tests run with `dub test :conc` on DMD and LDC. Test schedules come from OS thread
interleaving and fixed key sequences; no test draws random input, so none needs a seed.

| # | Section 6 item | Covering test(s) | Status |
| --- | --- | --- | --- |
| 1a | Linearizability history with 1/2/8 producers and consumers | `tests/linearizability.d:replay concurrent histories against a bounded sequential FIFO` (MPSC 1/2/8 producers with one consumer, MPMC 1/2/8 producers and consumers, replayed against a sequential bounded FIFO); `tests/concurrency.d:bounded FIFO and concurrent close histories` (exactly-once and per-producer FIFO at 1/2/8) | covered |
| 1b | Wraparound under a reduced test counter | `source/flint/conc/sys/ring.d:sequence cells recycle across reduced counter wrap` (single-threaded, 8-bit counter); `tests/linearizability.d:replay concurrent histories against a bounded sequential FIFO` (8-bit counter histories that wrap on the first concurrent send); `tests/linearizability.d:concurrent traffic keeps every accepted item exactly once across repeated reduced-counter wrap` | covered + added |
| 1c | Close/send/receive races | `tests/linearizability.d:replay concurrent histories against a bounded sequential FIFO` (close races sends and receives in every history); `tests/concurrency.d:bounded FIFO and concurrent close histories` (`raceClose` runs check accepted == received) | covered |
| 1d | Full/empty transitions | `tests/concurrency.d:bounded FIFO and concurrent close histories` (empty `unavailable`, full `resourceExhausted`, drain after close, then `cancelled`); `tests/concurrency.d:channel capacity outside 2 through 1,048,576 or not a power of two is rejected, not rounded` (capacity bounds, full at exactly 1,048,576, permanent `cancelled` after drain) | covered + added |
| 2a | Cancellation before submission | `tests/concurrency.d:copy arena input and consume completion once` (cancelled context is rejected by `submit`); `tests/concurrency.d:bound worker resources and validate ticket and output boundaries` (expired deadline → `timedOut`) | covered |
| 2b | Cancellation during queueing | `tests/concurrency.d:copy arena input and consume completion once` (queued job cancelled → `cancelled`, never runs); `tests/concurrency.d:a queued job whose deadline elapses before a worker starts reports timedOut and never runs` | covered + added |
| 2c | Cancellation after completion | `tests/concurrency.d:copy arena input and consume completion once` (cancel after the job finished still joins `ok` with the output); `tests/concurrency.d:retain cancelled running jobs until completion` (cancel while running) | covered |
| 2d | Parent cancelled twice | `tests/concurrency.d:earlier deadlines and cancellation precedence` | covered |
| 2e | Child deadline earlier/later | `tests/concurrency.d:earlier deadlines and cancellation precedence`; `tests/concurrency.d:deadline views retain the original cancellation and only narrow inherited time` | covered |
| 2f | Monotonic overflow | `tests/concurrency.d:earlier deadlines and cancellation precedence` (`afterMillis(ulong.max)` saturates to `long.max - 1`); `tests/concurrency.d:a shared clock sample reports the same status check would at that instant` (sample at `long.max - 1`) | covered |
| 3a | Worker at capacity rejects without blocking the reactor | `tests/concurrency.d:retain cancelled running jobs until completion` and `tests/concurrency.d:copy arena input and consume completion once` (`submit` returns `resourceExhausted` while the only worker is blocked; the rejected job is never run inline, `workerCopies` stays 1) | covered |
| 3b | Copied input correct after the originating arena resets | `tests/concurrency.d:copy arena input and consume completion once` (submit inside `RequestArena.read`, reset and overwrite the arena, output equals the original bytes) | covered |
| 4a | Compile-fail channel of string | `tests/concurrency.d:compile-fail channels of string, pointer, class, delegate, destructor struct and arena Buffer`; module-level `static assert(!Accepts!string)` | covered + added |
| 4b | Compile-fail channel of pointer | same test; `static assert(!Accepts!(void*))` | covered + added |
| 4c | Compile-fail channel of class | same test; `static assert(!Accepts!Reference)` | covered + added |
| 4d | Compile-fail channel of delegate | same test; `static assert(!Accepts!(void delegate()))` | covered + added |
| 4e | Compile-fail channel of destructor-bearing struct | same test; `static assert(!Accepts!WithDestructor)` | covered + added |
| 4f | Compile-fail channel of RequestArena Buffer | `tests/concurrency.d:compile-fail channels of string, pointer, class, delegate, destructor struct and arena Buffer` (`Buffer`, `const Buffer`, MPMC `Buffer`, `Buffer[1]`; asserts `Buffer` has no indirections, so only the explicit policy rejects it). Previously only a struct containing a `Buffer` was checked | added |
| 5a | All worker stacks registered with druntime | `tests/concurrency.d:copy arena input and consume completion once` (`copyWork` asserts `Thread.getThis() !is null` on the worker); workers are `core.thread.Thread` objects started by `flint.conc.sys.workers` | covered |
| 5b | Shutdown leaves zero live tickets | `tests/concurrency.d:join concurrent shutdown callers before reclaiming jobs` (running and queued tickets retire to `cancelled`; queued job never runs; `shutdown` asserts every slot returned); `tests/concurrency.d:copy arena input and consume completion once` (repeat `shutdown`, `join` after shutdown → `cancelled`) | covered |
| 5c | No reference to a freed slab after shutdown | `tests/concurrency.d:join concurrent shutdown callers before reclaiming jobs` (two concurrent shutdown callers both return only after the running job finishes; later `submit`/`join` return `cancelled` without touching slot storage); `tests/concurrency.d:concurrent context copies, child sources, cancellation and close return every slab node` (cancellation slab returns every node) | covered |

## Stub and always-success review

No stubs or always-success paths were found. `fillSecureRandom` returns `unsupported`
outside Linux rather than success. `WorkerPool` still idles with 50 µs sleeps; this is the open
performance finding recorded in the Milestone 1–5 review, not missing behaviour.
