# flint:ui-signals — implementation specification

Catalogue tier 5. Research cut: 2026-11-21. This file specifies implementation work; declarations in contracts are type-checking interfaces, not runtime implementations.

## 1. Purpose and reference parity

Implement a bounded fine-grained reactive graph without D GC, translating changed values into minimal bridge commands.

- [ ] Typed scalar signals, equality suppression, deterministic observer ordering and explicit disposal.
- [ ] One source can update several DOM text bindings; repeated writes coalesce per frame.
- [ ] Fixed caller-provided storage and no global dependency tracker or allocator.
- [ ] A stable typed handle catches disposal/reuse errors.

## 2. Exact package recipe and dependency boundary

Write this recipe to `packages/ui-signals/dub.sdl` in the implementation repository:

```sdl
name "ui-signals"
description "Flint ui-signals subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:wasm-bridge" version="*"

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

Allowed direct Flint dependencies: `flint:arena`, `flint:wasm-bridge`. The canonical allowlist is [packages.json](../../scaffold/policy/packages.json). Importing a higher catalogue tier or an unlisted same-tier package fails Gate 2.

## 3. Public D contract

Canonical declaration module: [flint.ui_signals](../../contracts/source/flint/ui_signals.d). These exact signatures are compiled with DIP1000. Implement the declarations with the semantics below; do not put unresolved declaration stubs into production artifacts.

```d
module flint.ui_signals;
import flint.arena : Error, Result;
import flint.wasm_bridge : CommandBuffer, NodeHandle;

@safe:
@nogc:
nothrow:
struct SignalId
{
    uint index;
    uint generation;
}

struct SignalSlot
{
    int value;
    uint generation;
    uint firstObserver;
    bool live;
}

alias Compute = int function(scope const(int)[]) @safe nothrow @nogc;
struct ComputedSlot
{
    SignalId output;
    uint firstInput;
    uint inputCount;
    Compute compute;
    bool live;
}

struct ObserverSlot
{
    SignalId source;
    NodeHandle destination;
    uint next;
    bool live;
}

struct SignalGraph
{
@safe:
nothrow:
@nogc:
    private SignalSlot[] signals_;
    private ObserverSlot[] observers_;
    private uint[] dirtyQueue_;
    private ComputedSlot[] computed_;
    private SignalId[] edges_;
    private int[64] scratch_;
    private uint dirtyCount_;
    private uint edgeCount_;
    private bool flushing_;
    @disable this(this);
    static Result!SignalGraph fromStorage(return scope SignalSlot[] signals, return scope ObserverSlot[] observers,
            return scope uint[] dirtyQueue, return scope ComputedSlot[] computedStorage = null,
            return scope SignalId[] edgeStorage = null);
    Result!SignalId create(int initial) scope;
    Result!SignalId computed(scope const SignalId[] inputs, Compute compute) scope;
    Result!int read(SignalId id) scope const;
    Error set(SignalId id, int value) scope;
    Error bindText(SignalId id, NodeHandle node) scope;
    Error dispose(SignalId id) scope;
    Error flush(ref scope CommandBuffer output) scope;
}
```

## 4. Internal architecture, ownership and safety

1. ABI v1 stores signed 32-bit scalar signals, computed scalar nodes and text observers. Generic application structs can map richer state into several scalar signals. Compute function pointers take a scope slice of input values; a fixed scratch buffer limits each computation to 64 dependencies.
2. SignalGraph borrows caller-owned slabs: SignalSlot[], ObserverSlot[], uint[] dirtyQueue and optional ComputedSlot[]/SignalId[] for computed nodes. No references escape read/set; IDs are scalar index/generation values. Initialized storage must contain zeroed slots, and invalid or unequal capacity combinations return invalidArgument.
3. create takes a free slot and assigns a nonzero generation; dispose unlinks all observers, clears queue membership and increments generation. Generation overflow retires the slot. Access through any stale ID returns notFound.
4. set compares the old value and enqueues at most once. DirtyQueue overflow returns resourceExhausted without changing the signal, preserving retry semantics. A flush reserves the whole command batch before any emission; if output capacity is insufficient it emits nothing and preserves the dirty set.
5. Observers are traversed in registration order. Decimal formatting is allocation-free and handles int.min without signed overflow. Multiple bindings to the same node are rejected conflict, preventing last-writer ambiguity.
6. No observer callback can call set during flush in v1. computed copies input IDs into optional edgeStorage and stores a noncapturing @safe nothrow @nogc function pointer in computedStorage. Missing computed storage returns resourceExhausted. Inputs must already exist; creating a new output only from earlier nodes enforces a DAG. set on a computed output is invalidArgument. Flush propagates dirty values in creation/topological order, computes each node once, suppresses equal outputs and then emits text patches. Disposing an input with live computed dependants returns conflict. No recursive evaluation or unbounded cascades.

### Concrete implementation files

- `packages/ui-signals/source/flint/ui_signals/package.d`: public declarations, UDA definitions and entry points.
- `packages/ui-signals/source/flint/ui_signals/internal.d`: shared non-template state machines and checked arithmetic.
- `packages/ui-signals/tests/contract_tests.d`: behavioral tests identified in section 6.
- `packages/ui-signals/tests/fuzz/`: deterministic seed corpus and bounded fuzz entry points; no fuzz data downloaded at test time.

The public surface defaults to `@safe`. Pointer arithmetic and native handle conversions are confined to those reviewed boundaries. Every implementation path in this contract is also `nothrow @nogc`; no D runtime/GC, class, dynamic array append, associative array, exception, TypeInfo, or Phobos runtime dependency is permitted.

## 5. Measured budget contract

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

These are engineering ceilings, not measured performance claims. Use the fixed runner and sampling procedure in [CI performance budgets](../../docs/CI_PERFORMANCE_BUDGETS.md). Per-package timing excludes rebuilding dependencies; whole-application gates include the selected closure.

| Measurement | Ceiling |
| --- | --- |
| DMD cold / incremental package build | 0.80s / 0.60s |
| LDC cold / incremental package build | 4.80s / 2.40s |
| Incremental stripped linked bytes | 49152 bytes |
| Compiler peak RSS | 536870912 bytes |
| Template instantiations in the package fixture | 2000 |

Compile regression >10% or binary growth >5% fails independently of these hard ceilings. Native dependencies and final shared-library closure are reported separately and counted in the application deployment metric; they are never hidden by quoting only D wrapper size.

Required benchmark: Run 100K sets over 1, 1000 and 10000 signals with 10% dirty per frame. Record ns/set, ns/observer and emitted patches. Equal-value updates must allocate zero bytes and emit zero commands.

## 6. Acceptance, edge cases and required tests

| Test ID | Stimulus | Required result |
| --- | --- | --- |
| SIGNAL-01 | Set same value 1000 times | No dirty queue entry and no emitted patch after initial flush. |
| SIGNAL-02 | Set same signal three times before flush | One text update containing final value. |
| SIGNAL-03 | Dispose then reuse slot and read old handle | Old handle returns notFound; new handle has different generation. |
| SIGNAL-04 | Dirty queue full or output buffer short | No partial state mutation or partial batch; retry after capacity recovery works. |
| SIGNAL-05 | int.min, int.max, negative and zero values | Correct decimal text, no overflow or GC allocation. |
| SIGNAL-06 | Two signals bind the same node | Second binding returns conflict. |
| SIGNAL-07 | Native and WASM runs over identical operation trace | Identical result/error codes and bridge bytes. |

The following is a real D test/usage fixture to place in the package tests. Runtime assertions become passing only after the specified implementation exists:

```d
import flint.ui_signals : SignalGraph, SignalSlot, ObserverSlot;
import flint.arena : Status;
unittest {
    SignalSlot[8] signals;
    ObserverSlot[8] observers;
    uint[8] queue;
    auto graph = SignalGraph.fromStorage(signals[], observers[], queue[]);
    assert(graph.ok());
    auto id = graph.value.create(7);
    assert(id.ok());
    assert(graph.value.set(id.value, 8).code == Status.ok);
    assert(graph.value.read(id.value).value == 8);
}
```

For parser/codec boundaries fuzz every length from 0 through 256, then 1KiB/1MiB boundary seeds; reject overflows before allocation. Run a 60-second ASan smoke on every PR and a 30-minute corpus job nightly. A platform-specific test is required on the platform that owns the native boundary; a Linux compile-only job does not count as a Windows runtime pass.

From the implementation repository root:

```sh
dub test :ui-signals --compiler=dmd
dub test :ui-signals --compiler=ldc2
python3 tools/gates.py --package ui-signals --gate structural
```

Do not mark this package complete until behavioral fixtures, compile-fail safety fixtures, the package budget fixture and all applicable native/WASM jobs pass. A declaration-only typecheck is API verification, not a package acceptance result.

## 7. Primary sources

- https://dlang.org/spec/betterc.html
- https://docs.solidjs.com/concepts/signals
