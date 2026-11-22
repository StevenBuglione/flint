# flint:arena — implementation specification

Status: normative design for agents; contract declarations have been syntax checked. Runtime behavior below is an acceptance requirement, not a claim that a framework implementation already exists. The compiler receipt is [core-contracts.json](../../verification/core-contracts.json).

## 1. Purpose and reference parity

Provide bounded, resettable request storage and reusable byte-buffer ownership without D GC allocation. This is the foundation for web requests, serializers and browser command buffers.

- [ ] Netty allocator parity: preallocated backing storage, alignment, usage counters, generation-safe leases, and explicit exhaustion.
- [ ] Go sync.Pool parity: reuse a fixed per-core slab pool; no promise that independently owned objects can migrate across cores.
- [ ] BetterC parity: the exact same allocation/handle code compiles natively and for wasm32; host page acquisition remains an adapter.

## 2. Package boundary and exact DUB recipe

Catalog tier: **0**. Direct allowed Flint dependencies: **none**. No transitive import is an excuse to add a direct import without updating the dependency policy. Production code may not depend on flint:test. Recipe path: `packages/arena/dub.sdl`, invoked from the monorepo root.

```sdl
name "arena"
description "Flint arena subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"

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

These are concrete signatures in the contract fixture, not executable implementations. Internal representation may change while preserving signatures and semantics. Source: `contracts/source/flint/arena.d`.

```d
/// Public API contract; declarations are not runtime implementations.
module flint.arena;

@safe:
enum Status : int
{
    ok,
    invalidArgument,
    outOfMemory,
    cancelled,
    timedOut,
    notFound,
    conflict,
    ioError,
    unavailable,
    unsupported,
    permissionDenied,
    resourceExhausted
}

struct Error
{
    Status code;
    string message;
    size_t offset = size_t.max;
}

struct Result(T)
{
    T value;
    Error error;
    bool ok() const pure nothrow @nogc
    {
        return error.code == Status.ok;
    }
}
/// Opaque identity: caller may copy handles but cannot fabricate a valid one.
struct Buffer
{
    private ulong owner;
    private ulong epoch;
    private size_t start;
    private size_t count;
    private this(ulong owner, ulong epoch, size_t start, size_t count) nothrow @nogc;
    size_t length() const pure nothrow @nogc;
}

struct Text
{
    Buffer bytes;
}

struct ArenaStats
{
    size_t capacity;
    size_t used;
    size_t peak;
    ulong resets;
}
/// Non-copyable, thread-confined, borrows backing storage.
struct RequestArena
{
    private ubyte[] storage;
    private size_t cursor;
    private uint activeBorrows;
    private ulong owner;
    private ulong epoch;
    @disable this(this);
    this(return scope ubyte[] backing) nothrow @nogc;
    Result!Buffer allocate(size_t bytes, size_t alignment = 8) scope nothrow @nogc;
    Result!Buffer copyIn(scope const(ubyte)[] source) scope nothrow @nogc;
    Status read(Buffer handle, scope void delegate(scope const(ubyte)[]) @safe nothrow @nogc visitor) scope nothrow @nogc;
    Status write(Buffer handle, scope void delegate(scope ubyte[]) @safe nothrow @nogc visitor) scope nothrow @nogc;
    Status reset() scope nothrow @nogc;
    ArenaStats stats() const scope nothrow @nogc;
}

struct BufferPoolOptions
{
    size_t blockBytes = 65536;
    size_t blockCount = 256;
}
```

## 4. Internal architecture, ownership and safety

The allocator stores a caller-provided byte slice, a bump cursor, a unique 64-bit owner ID, an epoch and an active-borrow counter. Allocation uses checked arithmetic: reject zero/non-power-of-two alignment, reject alignments above 4096, compute padding without overflow, and check `bytes <= capacity - alignedCursor`. A zero-byte allocation succeeds with length zero and consumes no payload; it still has a valid owner/epoch. New allocations never move backing storage. Initial contents are zeroed for every allocation before exposing a handle; this prevents reuse of prior request bytes through uninitialized reads. This zeroing is O(bytes); the reset operation alone is O(1).

`Buffer` is a scalar opaque handle. Add an explicit private constructor to suppress D's otherwise usable aggregate construction; default `.init` is always invalid. Every access validates owner, epoch, `start <= cursor` and `count <= cursor-start`. The constructor obtains a process-unique monotonic owner ID through `flint.arena.sys`: native builds use a zero-initialized `shared ulong` with `core.atomic.atomicLoad` and `cas` in a saturating compare/exchange loop. Relaxed ordering is sufficient for ID uniqueness; it is not a publication fence for arena storage. The native import is version-gated out of the single-threaded WASM profile, which uses a plain global saturating counter and rejects shared-memory/threaded module builds. Once `ulong.max` has been issued, every later owner-ID request returns zero; an arena initialized with zero permanently fails allocation with `resourceExhausted`. Never use wrapping fetch-add, which would eventually reuse IDs. No custom C object, TLS or module constructor is required. If an epoch increment would wrap, invalidate that arena and return `resourceExhausted` without cycling the epoch. [Actual DMD/LDC native BetterC atomic link/run probe](../../verification/native-betterc-atomics.json). Handles never remain valid across reset, arena destruction, or reuse of the same backing address.

The safe API never returns a raw slice. `read`/`write` call a `scope` callback and borrow the arena for that callback. Increment the active-borrow count before entering user code, decrement it with `scope(exit)`, and make `reset` return `conflict` while the count is nonzero. `@nogc nothrow` callback types prevent exception unwinding or an allocating closure on this path. DIP1000 checks callback escape and the arena's borrowed backing lifetime; runtime owner/epoch checks handle reset/reuse. This combination is required: `@safe` alone does not make manual resettable lifetimes safe.

The hot arena stores no GC pointers or D object references. Store scalar DTOs, `Text`/`Buffer` handles, copied UTF-8 and serialized bytes. A `Text` names UTF-8 bytes in this arena; validity is checked at decode time. To transfer data to a worker or long-lived object, copy into the destination's owned pool. There is no `GC.addRange` call in this package. Buffer-pool construction and page release belong to the native `sys` adapter and are excluded from the BetterC core.

**Safety boundary:** Only native counter/page adapters under `flint.arena.sys` may be `@trusted`/`@system`. Core arithmetic, bounds checks, handle validation and callbacks are `@safe nothrow @nogc`. Native page acquisition may allocate outside D GC; it runs before requests.

## 5. Compile-time, size and runtime budgets

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

These are release gates on the designated reference runner, not observed performance results. Measure the package's fixed feature fixture, with dependencies frozen; cold/incremental definitions and statistical regression rules come from [CI budgets](../../docs/CI_PERFORMANCE_BUDGETS.md).

| Metric | Hard ceiling |
| --- | ---: |
| DMD cold build | 0.35 s |
| DMD incremental build | 0.35 s |
| LDC cold build | 2.10 s |
| LDC incremental build | 1.05 s |
| Marginal stripped linked bytes | 262,144 bytes |
| Compiler peak RSS | 536,870,912 bytes |
| Template instantiations | 2,000 |

The >10% compile/template/RSS regression rule and >5% binary growth rule also apply; passing a hard ceiling does not permit silent drift. Marginal size follows the provider-equivalent definition above; full native-provider and dependency footprints remain in the recorded complete binaries. Package deltas are not summed to estimate an application. Native shared-library bytes and static-dependency bytes must both be reported. BetterC core: **required; native and wasm32 profiles**.

**Benchmark fixture:** Measure 64-byte and 4096-byte allocations separately (including mandatory zeroing), a 1000-allocation/reset cycle, and checked-handle read overhead. Report ns/op and bytes zeroed/op; never benchmark only cursor arithmetic and call it end-to-end allocation.

## 6. Required acceptance tests and edge cases

1. Allocate alignments 1, 2, 8, 16, 4096; reject 0, 3 and 8192 without changing cursor.
2. Allocate capacity, capacity+1, size_t.max and overflowing padding; `outOfMemory` never corrupts state.
3. Stale owner, stale epoch, `.init`, reset during read, reentrant write, empty slice, double reset and epoch exhaustion.
4. Poison/reset/reuse backing: no previous request content becomes visible; handles for arena A fail against B.
5. Compile-fail: returning an arena backed by a local array; assigning a callback slice to a global; calling a non-@nogc function inside the callback.

Every listed case becomes a named unittest or a compiler-negative fixture, with a deterministic seed for generated schedules/inputs. FFI/kernel lifetime tests run under the platform sanitizer jobs. Add regression fixtures for every corrected failure before closing the slice.

## 7. Agent implementation order and definition of done

1. Add the package modules and public declarations, compile the positive contract usage and the negative misuse fixtures, then implement the smallest deterministic behavior covered by the first acceptance group.
2. Complete ownership/error paths before adding throughput optimization; include bounded-resource exhaustion tests.
3. Add the fixed benchmark fixture, record raw samples and candidate baseline receipts, and complete all acceptance groups before activating this package for integration.

Run from `scaffold/` after implementing this package:

```bash
python3 tools/flint.py test --package arena --compiler dmd
python3 tools/gates.py --package arena --gate structural
```

The direct test equivalent is `dub test :arena --compiler=dmd`. Repeat with `--compiler ldc2` through the orchestrator. A declaration-only contract pass is never a substitute for `dub test` on a runtime implementation. Full Gates 1–6 run for the integrated milestone once its canonical apps and runner baselines exist; absence of a required measurement blocks release rather than fabricating a zero measurement.

## Evidence and rationale

The D capability behind this design is documented at [https://dlang.org/spec/function.html#return-scope-parameters](https://dlang.org/spec/function.html#return-scope-parameters) (accessed 2026-11-21). Normative limits, failure codes and ownership policies above are Flint design decisions. See [core research evidence](../../research/core-sources.md) for precise capability claims and verification boundaries.
