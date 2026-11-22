# flint:conc — implementation specification

Status: normative design for agents; contract declarations have been syntax checked. Runtime behavior below is an acceptance requirement, not a claim that a framework implementation already exists. The compiler receipt is [core-contracts.json](../../verification/core-contracts.json).

## 1. Purpose and reference parity

Provide deadline propagation, cancellation, bounded channels and blocking-work offload without importing a server, a logger or a higher-tier package.

- [ ] Go context parity: explicit cancellation/deadline value, parent propagation, idempotent cancellation, first completion wins.
- [ ] Go channel/errgroup parity: bounded send/receive, defined close/drain behavior, cooperative task joining; no implicit unbounded queues.
- [ ] Java structured task parity: a group cannot report successful closure while owned tasks remain live; blocking calls run on bounded workers.

## 2. Package boundary and exact DUB recipe

Catalog tier: **0**. Direct allowed Flint dependencies: **flint:arena**. No transitive import is an excuse to add a direct import without updating the dependency policy. Production code may not depend on flint:test. Recipe path: `packages/conc/dub.sdl`, invoked from the monorepo root.

```sdl
name "conc"
description "Flint conc subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"

configuration "library" {
    targetType "library"
}
configuration "unittest" {
    targetType "library"
    sourcePaths "source" "tests"
    importPaths "source" "tests"
    excludedSourceFiles "tests/betterc.d"
}
```

The root manifest registers the subpackage path. Fully qualified flint:<name> sibling dependencies resolve in the parent package; do not turn these dependencies into independently fetched registry packages. The recipe and [packages policy](../../scaffold/policy/packages.json) are authoritative.

## 3. Public D API and UDA definitions

These are concrete signatures in the contract fixture, not executable implementations. Internal representation may change while preserving signatures and semantics. Source: `contracts/source/flint/conc.d`.

```d
/// Public API contract; declarations are not runtime implementations.
module flint.conc;
import flint.arena : Status, Error, Result;

@safe:
struct Deadline
{
    long monotonicNanoseconds;
    static Deadline afterMillis(ulong duration) nothrow @nogc;
    static Deadline none() pure nothrow @nogc;
}

struct Context
{
    private ulong id;
    private Deadline deadlineValue;
    bool cancelled() const nothrow @nogc;
    Deadline deadline() const nothrow @nogc;
    Error check() const nothrow @nogc;
}

struct CancelSource
{
    private ulong id;
    @disable this(this);
    static Result!CancelSource create(Context parent, Deadline deadline) nothrow @nogc;
    Context context() const nothrow @nogc;
    void cancel() nothrow @nogc;
    void close() nothrow @nogc;
}

enum QueueKind
{
    mpsc,
    mpmc
}

struct Channel(T, QueueKind kind = QueueKind.mpsc)
{
    private ulong id;
    @disable this(this);
    static Result!Channel create(size_t capacity) nothrow @nogc;
    Status trySend(T value) nothrow @nogc;
    Result!T tryReceive() nothrow @nogc;
    void close() nothrow @nogc;
}

struct WorkerOptions
{
    uint threads = 4;
    uint queueCapacity = 256;
}

struct WorkTicket
{
    ulong id;
}

alias WorkFn = Error function(scope const(ubyte)[] input, scope ubyte[] output, out size_t written) @safe nothrow @nogc;
struct WorkerPool
{
    private ulong id;
    @disable this(this);
    static Result!WorkerPool create(WorkerOptions options);
    Result!WorkTicket submit(Context context, scope const(ubyte)[] ownedCopy, WorkFn job) nothrow @nogc;
    Error join(WorkTicket ticket, scope ubyte[] output, out size_t written) nothrow @nogc;
    void shutdown() nothrow;
}
```

## 4. Internal architecture, ownership and safety

`Context` is an opaque generation-validated reference to cancellation state. Native state is allocated from a preallocated slab; copies retain a lifetime reference until request/task completion. It uses absolute monotonic nanoseconds; wall-clock changes never alter existing deadlines. A child chooses the earlier of its explicit deadline and its parent's. `Context.init` means uncancelled/no deadline. `check` distinguishes `cancelled` from `timedOut`; an observed cancellation wins according to a single atomic state transition. `CancelSource.close` releases its ownership only after dependent task/context references are retired.

Channels use a power-of-two ring of sequence-numbered cells, 64-byte-separated producer and consumer counters, acquire/release ordering, and explicit ownership transfer. MPSC has one consumer; MPMC permits multiple consumers. The implementation must provide a linearization argument for publish, consume and close, including sequence wrap. Reject capacity outside 2..1,048,576 or non-power-of-two input rather than silently rounding. `trySend` returns `resourceExhausted` when full and `cancelled` after close. `tryReceive` returns `unavailable` for an empty open channel; after close it drains published items then returns `cancelled` permanently. A close/send race has one linearization winner and never loses an item reported as accepted.

`Channel!T` accepts only recursively validated transfer values: integers, floating values, enums, fixed arrays of them, and structs whose fields satisfy the same rule. Reject pointers, slices, associative arrays, delegates, classes, interfaces, unions, and structs with destructors/postblits. Larger data travels as IDs into an explicitly retained owned-buffer pool. A `Buffer` from a request arena is not a cross-thread ownership token and must not be sent merely because its representation is scalar; the channel policy additionally rejects that type. This avoids making D's `shared` qualifier an ownership escape hatch.

Worker submission copies input into the pool's bounded owned storage before it returns. Completion owns its copied output until `join` consumes it. For a request arena's data, perform the copy synchronously inside its `read` callback. No worker retains the caller's slice, stack frame, delegate context, or reactor TLS. Queue saturation returns `resourceExhausted`; it never executes the job inline on a reactor core. Cancellation is cooperative: a C function already running may finish later, and its result is discarded safely if the owner has cancelled. `shutdown` stops admissions, cancels queued work, joins workers and returns only when no job can touch pool memory. A noncooperative C call requires application shutdown timeout/process policy; there is no unsafe thread kill.

**Safety boundary:** `core.atomic` intrinsics and OS threading access are confined to `flint.conc.sys`; D public functions are `@safe`. Channels and cancellation checks are `@nogc`; initial worker/thread/slab creation is startup-only and may allocate. No inline `@trusted` atomic casts in generic application code.

## 5. Compile-time, size and runtime budgets

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

These are release gates on the designated reference runner, not observed performance results. Measure the package's fixed feature fixture, with dependencies frozen; cold/incremental definitions and statistical regression rules come from [CI budgets](../../docs/CI_PERFORMANCE_BUDGETS.md).

| Metric | Hard ceiling |
| --- | ---: |
| DMD cold build | 0.90 s |
| DMD incremental build | 0.60 s |
| LDC cold build | 5.40 s |
| LDC incremental build | 2.70 s |
| Marginal stripped linked bytes | 262,144 bytes |
| Compiler peak RSS | 536,870,912 bytes |
| Template instantiations | 2,000 |

The >10% compile/template/RSS regression rule and >5% binary growth rule also apply; passing a hard ceiling does not permit silent drift. Marginal size follows the provider-equivalent definition above; full native-provider and dependency footprints remain in the recorded complete binaries. Package deltas are not summed to estimate an application. Native shared-library bytes and static-dependency bytes must both be reported. BetterC core: **not claimed**.

**Benchmark fixture:** Measure MPSC and MPMC at 1/2/8/32 producers, empty polling, full rejection, cancellation checks and 4 KiB offload round trips. Report successful ops/sec and p99 enqueue wait separately from rejected operations.

## 6. Required acceptance tests and edge cases

1. Linearizability history with 1/2/8 producers and consumers, wraparound under a reduced test counter, close/send/receive races and full/empty transitions.
2. Cancellation before submission, during queueing and after completion; parent cancelled twice; child deadline earlier/later; monotonic overflow.
3. Worker at capacity must reject without blocking the reactor; copied input must remain correct after the originating arena resets.
4. Compile-fail channels of string, pointer, class, delegate, destructor-bearing struct and RequestArena Buffer.
5. All worker stacks registered with druntime; shutdown leaves zero live tickets and no reference to a freed slab.

Every listed case becomes a named unittest or a compiler-negative fixture, with a deterministic seed for generated schedules/inputs. FFI/kernel lifetime tests run under the platform sanitizer jobs. Add regression fixtures for every corrected failure before closing the slice.

## 7. Agent implementation order and definition of done

1. Add the package modules and public declarations, compile the positive contract usage and the negative misuse fixtures, then implement the smallest deterministic behavior covered by the first acceptance group.
2. Complete ownership/error paths before adding throughput optimization; include bounded-resource exhaustion tests.
3. Add the fixed benchmark fixture, record raw samples and candidate baseline receipts, and complete all acceptance groups before activating this package for integration.

Run from `scaffold/` after implementing this package:

```bash
python3 tools/flint.py test --package conc --compiler dmd
python3 tools/gates.py --package conc --gate structural
```

The direct test equivalent is `dub test :conc --compiler=dmd`. Repeat with `--compiler ldc2` through the orchestrator. A declaration-only contract pass is never a substitute for `dub test` on a runtime implementation. Full Gates 1–6 run for the integrated milestone once its canonical apps and runner baselines exist; absence of a required measurement blocks release rather than fabricating a zero measurement.

## Evidence and rationale

The D capability behind this design is documented at [https://dlang.org/spec/type.html#shared](https://dlang.org/spec/type.html#shared) (accessed 2026-11-21). Normative limits, failure codes and ownership policies above are Flint design decisions. See [core research evidence](../../research/core-sources.md) for precise capability claims and verification boundaries.
