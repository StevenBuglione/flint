# flint:reactor — implementation specification

Status: normative design for agents; contract declarations have been syntax checked. Runtime behavior below is an acceptance requirement, not a claim that a framework implementation already exists. The compiler receipt is [core-contracts.json](../../verification/core-contracts.json).

## 1. Purpose and reference parity

Own sockets, timers and request execution on stable per-core event loops, with an explicit owner for every connection and completion.

- [ ] Netty parity: per-loop connection ownership, bounded admission/backpressure, timers, shutdown and completion dispatch.
- [ ] Go netpoll parity: readiness/completion-driven nonblocking I/O; no goroutine migration emulation.
- [ ] Linux io_uring, macOS kqueue and Windows IOCP use a common operation state machine without pretending their cancellation semantics are identical.

## 2. Package boundary and exact DUB recipe

Catalog tier: **0**. Direct allowed Flint dependencies: **flint:arena, flint:conc**. No transitive import is an excuse to add a direct import without updating the dependency policy. Production code may not depend on flint:test. Recipe path: `packages/reactor/dub.sdl`, invoked from the monorepo root.

```sdl
name "reactor"
description "Flint reactor subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:conc" version="*"

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

These are concrete signatures in the contract fixture, not executable implementations. Internal representation may change while preserving signatures and semantics. Source: `contracts/source/flint/reactor.d`.

```d
/// Public API contract; declarations are not runtime implementations.
module flint.reactor;
import flint.arena : Status, Error, Result;
import flint.conc : Context, Deadline;

@safe:
enum Backend
{
    automatic,
    ioUring,
    kqueue,
    iocp
}

struct ReactorOptions
{
    Backend backend = Backend.automatic;
    uint cores = 0;
    uint completionsPerTick = 256;
    uint maxConnectionsPerCore = 8192;
    uint fiberPoolSize = 1024;
    size_t fiberStackBytes = 65536;
}

struct ConnectionId
{
    uint ownerCore;
    uint slot;
    ulong generation;
}

struct TimerId
{
    uint ownerCore;
    uint slot;
    ulong generation;
}

struct ListenOptions
{
    string host = "127.0.0.1";
    ushort port = 8080;
    uint backlog = 1024;
}

struct Completion
{
    ConnectionId connection;
    Status status;
    size_t bytes;
}

alias AcceptFn = void function(ConnectionId) @safe nothrow @nogc;
alias CompletionFn = void function(Completion) @safe nothrow @nogc;
struct Reactor
{
    private ulong id;
    @disable this(this);
    static Result!Reactor create(ReactorOptions options);
    Error listen(ListenOptions options, AcceptFn accept);
    Error run();
    void stop() nothrow @nogc;
    Error post(uint ownerCore, void function() @safe nothrow @nogc task) nothrow @nogc;
    Error close(ConnectionId connection) nothrow @nogc;
    uint currentCore() const nothrow @nogc;
}
```

## 4. Internal architecture, ownership and safety

Startup creates one loop for each selected logical CPU (zero means available CPUs after process affinity filtering). Connection tables, request arenas, completion slots, timer storage, fiber objects and fiber stacks are preallocated before listening. Each connection ID includes owner core, slot and generation. Reject operations on the wrong owner or return them through a bounded mailbox; do not share sockets between request executors. A non-owner may request close only by mailbox. The event loop services at most `completionsPerTick` I/O completions before running ready timers and queued tasks, preventing I/O starvation of cancellation.

Linux uses pinned liburing through a small C shim, baseline Linux 6.1 with feature probing at startup. Single-shot accept/read/write is the initial contract. Multishot accept/receive and fixed buffers become separately benchmarked optimizations after identical cancellation/lifetime tests pass. If required io_uring operations are denied or unavailable, startup returns `unsupported` with the failed capability; do not silently change to blocking sockets. macOS uses EVFILT_READ/WRITE and carefully rearms filters after would-block; EOF is distinct from ordinary readiness. Windows retains each OVERLAPPED and its buffer until the completion is observed, including CancelIoEx races. Close enters DRAINING and the slot is reusable only after every outstanding completion has retired. A timer expiry never frees in-flight kernel memory.

Fibers never migrate in Flint. The official D Fiber API permits transferring a suspended fiber, so this restriction is an intentional ownership/TLS policy. Allocate fibers at startup and pin them to their first core. One fiber serves one logical request at a time, with complete request context reset on recycle. Fiber-local logging/request state is stored in a task record, not in an unqualified TLS MDC. On every resume, install that task's context and restore the previous context on yield. A non-yielding CPU-heavy handler still monopolizes a core; limit inline work and offload bounded CPU/blocking work through `flint:conc`.

A druntime fiber scheduler call is a private boundary whose actual pinned compiler signature must be audited; do not cast an arbitrary allocating callback to `@nogc`. The externally registered request handler and all handler-reachable serialization/routing methods must compile as `@safe nothrow @nogc`. Startup and scheduler instrumentation are measured separately. GC-managed application roots remain registered on druntime threads. Zero per-thread GC allocations in a handler does not eliminate collections started elsewhere; the production policy and tests must measure process collection counts too.

Shutdown is ordered: stop listening, reject new work, signal contexts, drain completions until deadline, abort remaining sockets, observe final kernel completions, join loops, then release slabs. `run` returns an Error on fatal backend failure and never restarts a failed loop silently.

**Safety boundary:** Only `flint.reactor.sys` and `flint.reactor.ffi` access OS handles, raw pointers or fiber-switch machinery. Each callback validates connection generation before touching state. These modules require ASan-backed native tests and platform-specific completion tests.

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

**Benchmark fixture:** Run a fixed-size TCP echo fixture with 1/64/1024 persistent clients, 64/4096-byte payloads, saturated admission and cancellation storms. Record throughput, p50/p99/p99.9, per-core CPU, context switches and outstanding buffers after shutdown.

## 6. Required acceptance tests and edge cases

1. Connection slot reuse with stale completion; cancelled read completing successfully; close while write pending; timeout and completion in the same poll batch.
2. Admission overflow, mailbox saturation, hot connection fairness, timer fairness, read/write partial progress, EOF and half-close.
3. TLS/task context alternation between two fibers on one core; fail if a request observes another request ID.
4. Linux capability denied; kqueue EOF+data; Windows CancelIoEx ERROR_NOT_FOUND and completion-after-cancel.
5. ASan tests retain all kernel buffers to final completion; functional echo on every native matrix platform.

Every listed case becomes a named unittest or a compiler-negative fixture, with a deterministic seed for generated schedules/inputs. FFI/kernel lifetime tests run under the platform sanitizer jobs. Add regression fixtures for every corrected failure before closing the slice.

## 7. Agent implementation order and definition of done

1. Add the package modules and public declarations, compile the positive contract usage and the negative misuse fixtures, then implement the smallest deterministic behavior covered by the first acceptance group.
2. Complete ownership/error paths before adding throughput optimization; include bounded-resource exhaustion tests.
3. Add the fixed benchmark fixture, record raw samples and candidate baseline receipts, and complete all acceptance groups before activating this package for integration.

Run from `scaffold/` after implementing this package:

```bash
python3 tools/flint.py test --package reactor --compiler dmd
python3 tools/gates.py --package reactor --gate structural
```

The direct test equivalent is `dub test :reactor --compiler=dmd`. Repeat with `--compiler ldc2` through the orchestrator. A declaration-only contract pass is never a substitute for `dub test` on a runtime implementation. Full Gates 1–6 run for the integrated milestone once its canonical apps and runner baselines exist; absence of a required measurement blocks release rather than fabricating a zero measurement.

## Evidence and rationale

The D capability behind this design is documented at [https://dlang.org/library/core/thread/fiber/fiber.html](https://dlang.org/library/core/thread/fiber/fiber.html) (accessed 2026-11-21). Normative limits, failure codes and ownership policies above are Flint design decisions. See [core research evidence](../../research/core-sources.md) for precise capability claims and verification boundaries.
