# flint:wasi — implementation specification

Catalogue tier 5. Research cut: 2026-11-21. This file specifies implementation work; declarations in contracts are type-checking interfaces, not runtime implementations.

## 1. Purpose and reference parity

Separate guest compilation from host embedding: build portable BetterC core modules and host sandboxed plugins through a pinned runtime; add versioned WASI component adapters as explicit artifacts.

- [ ] Host core modules and Preview1 WASI modules with Wasmtime; optional WAMR core/Preview1 backend.
- [ ] Resource limits, explicit preopens, disabled ambient environment/network and interruptible execution.
- [ ] WASI 0.2 and 0.3 component targets through WIT/Canonical ABI tooling, never by renaming a compiler triple.
- [ ] A typed scalar plugin call is the baseline; component exports use generated binding-specific adapters.

## 2. Exact package recipe and dependency boundary

Write this recipe to `packages/wasi/dub.sdl` in the implementation repository:

```sdl
name "wasi"
description "Flint wasi subpackage"
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

Allowed direct Flint dependencies: `flint:arena`, `flint:conc`. The canonical allowlist is [packages.json](../../scaffold/policy/packages.json). Importing a higher catalogue tier or an unlisted same-tier package fails Gate 2.

## 3. Public D contract

Canonical declaration module: [flint.wasi](../../contracts/source/flint/wasi.d). These exact signatures are compiled with DIP1000. Implement the declarations with the semantics below; do not put unresolved declaration stubs into production artifacts.

```d
module flint.wasi;
import flint.arena : Error, Result;

@safe:
enum Engine : ubyte
{
    wasmtime,
    wamr
}

enum GuestAbi : ubyte
{
    core,
    wasiPreview1,
    wasi02Component,
    wasi03Component
}

struct Preopen
{
    string hostPath;
    string guestPath;
    bool writable;
}

struct Limits
{
    ulong fuel = 10000000;
    ulong maxMemoryBytes = 16777216;
    uint maxTableElements = 1024;
    uint maxInstances = 1;
    uint maxOutputBytes = 1048576;
    long wallTimeNanos = 1000000000;
}

struct PluginOptions
{
    Engine engine = Engine.wasmtime;
    GuestAbi abi = GuestAbi.core;
    Limits limits;
    Preopen[] preopens;
    bool inheritEnvironment = false;
    bool allowNetwork = false;
}

struct Plugin
{
    @disable this(this);
    static Result!Plugin load(scope const(ubyte)[] wasm, PluginOptions options = PluginOptions.init);
    Result!int callI32(scope const(char)[] exportName, scope const int[] args);
    Error interrupt();
    Error close();
}
```

## 4. Internal architecture, ownership and safety

1. Guest core modules use -betterC -mtriple=wasm32-unknown-unknown-wasm and a C ABI export set. This says nothing about Preview1 or Component Model compatibility. WASI Preview1 needs wasi-libc/imports/sysroot or explicitly declared imports; WASI 0.2/0.3 need WIT metadata and Canonical ABI lowering/lifting.
2. Current official WASI 0.3 is stable, with final support in Wasmtime 46+. Flint D component bindings are a separate integration deliverable. Choose one pinned WIT version per generated binding; never mix 0.3 RC interfaces with stable 0.3 names.
3. The host default is Wasmtime 51.0.0, enabled by the verified `FlintNativeWasmtime` provider selection. Every native CI lane that tests all 37 packages prepares this provider and must execute real successful core/Preview1 calls; a missing engine, unsupported result or skipped test cannot satisfy default WASI acceptance. WAMR 2.4.6 is an explicit alternative for core/Preview1 only; requesting wasi02Component or wasi03Component with WAMR returns unsupported. Advertised WAMR core/Preview1 support requires a separately selected WAMR conformance run. Default GuestAbi.core rejects unexpected imports.
4. Limits default to 16MiB linear memory, 1024 table elements, one instance, 10M fuel units, 1s wall time and 1MiB captured output. Fuel bounds guest instructions; epoch interruption/watchdog bounds running time, including cancellation. Host callbacks also enforce deadlines because guest fuel cannot stop blocking host code.
5. Each Plugin is move-only and owns engine/store/module/instance lifetimes. A store is used by only one worker at a time. C callbacks catch D exceptions before returning status to the runtime. No arena borrow or GC object pointer is retained by a guest.
6. Preopens are explicit paths with writable=false by default. Canonicalize and open by directory handle; resolve guest paths relative to that handle without following escaping symlinks. inheritEnvironment and allowNetwork are false by default. A plugin does not inherit server credentials.
7. callI32 validates the export signature and argument count before invoking. Native Rust/C engine storage is accounted separately from D GC and is not included in the tiny CLI/REST feature profiles; deployment closure includes its shared library or static archive bytes.

### Concrete implementation files

- `packages/wasi/source/flint/wasi/package.d`: public declarations, UDA definitions and entry points.
- `packages/wasi/source/flint/wasi/internal.d`: shared non-template state machines and checked arithmetic.
- `packages/wasi/tests/contract_tests.d`: behavioral tests identified in section 6.
- `packages/wasi/tests/fuzz/`: deterministic seed corpus and bounded fuzz entry points; no fuzz data downloaded at test time.
- `packages/wasi/source/flint/wasi/ffi/` and `sys/`: allowlisted native boundaries; every trusted function has an adjacent `// SAFETY:` proof and a matching ASan test.

The public surface defaults to `@safe`. Pointer arithmetic and native handle conversions are confined to those reviewed boundaries. This full-D package may allocate where documented. Do not add `@nogc` to an API unless every implementation path and callback has that contract.

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

Required benchmark: Benchmark module compile, cached instantiation and a 100K-call scalar export separately. Record engine version, guest ABI, fuel setting, native engine RSS and full deployment size. Compare WAMR interpreter and Wasmtime JIT only with the same guest and safety limits.

## 6. Acceptance, edge cases and required tests

| Test ID | Stimulus | Required result |
| --- | --- | --- |
| WASI-01 | Malformed module, unexpected import and missing export | Deterministic invalidArgument/notFound; no host crash or leaked store. |
| WASI-02 | Infinite guest loop and memory.grow beyond cap | Fuel/deadline interruption and memory limit enforced within 100ms scheduler tolerance. |
| WASI-03 | Attempt access outside a preopen through .. and symlink | Denied; no host filesystem disclosure. |
| WASI-04 | Read environment and network with defaults | No ambient env/network available. |
| WASI-05 | Core, Preview1, WASI0.2 and WASI0.3 fixture modules | Version-specific accepted/rejected matrix; no claim based only on successful core compilation. |
| WASI-06 | WAMR selected for component module | unsupported before execution. |
| WASI-07 | Host callback blocks past deadline or throws | Bounded worker policy cancels/fails the callback; no exception crosses C. |
| WASI-08 | Default Wasmtime loads a valid core module exporting answer() -> i32 | Load succeeds and the call returns 42; absent provider/unsupported/skip is a failure. Repeat the default engine conformance suite in every native target lane. |

The following is a real D test/usage fixture to place in the package tests. Runtime assertions become passing only after the specified implementation exists:

```d
import flint.wasi : Plugin, PluginOptions, Engine, GuestAbi;
import flint.arena : Status;
unittest {
    immutable ubyte[] invalid = [1, 2, 3, 4];
    auto loaded = Plugin.load(invalid);
    assert(loaded.error.code == Status.invalidArgument);
    immutable ubyte[] scalar = [
        0, 97, 115, 109, 1, 0, 0, 0,
        1, 5, 1, 96, 0, 1, 127,
        3, 2, 1, 0,
        7, 10, 1, 6, 97, 110, 115, 119, 101, 114, 0, 0,
        10, 6, 1, 4, 0, 65, 42, 11
    ];
    auto valid = Plugin.load(scalar);
    assert(valid.ok(), "Default Wasmtime provider is required");
    scope (exit) valid.value.close();
    auto answer = valid.value.callI32("answer", null);
    assert(answer.ok() && answer.value == 42);
}
```

For parser/codec boundaries fuzz every length from 0 through 256, then 1KiB/1MiB boundary seeds; reject overflows before allocation. Run a 60-second ASan smoke on every PR and a 30-minute corpus job nightly. A platform-specific test is required on the platform that owns the native boundary; a Linux compile-only job does not count as a Windows runtime pass.

From the implementation repository root, prepare the default engine before package tests:

```sh
rustup toolchain install 1.97.0 --profile minimal --target x86_64-unknown-linux-gnu
RUSTUP_TOOLCHAIN=1.97.0 python3 tools/native_build.py --profile wasm-host --target linux-x86_64-glibc --phase build --emit-dub
dub test :wasi --compiler=dmd
dub test :wasi --compiler=ldc2
python3 tools/gates.py --package wasi --gate structural
```

All-package CI uses `--profile ci --library wasmtime`: the ci profile itself is the C-provider closure, while the added engine is mandatory for wasi tests. The sanitizer lane first builds Wasmtime without Rust instrumentation into the final sanitized installation prefix using a separate engine build directory, then instruments the C dependencies and Flint C shims, emits the cumulative provider configuration, and runs the same package tests with D ASan. This covers the D/C boundary and actual engine behavior; it does not claim Rust-internal sanitizer coverage. See [the native preparation matrix](../../docs/C_FFI_PINNING_MATRIX.md) for exact commands and prerequisite versions. Required component-adapter conformance is an additional acceptance gate; a required positive WASI0.3 fixture cannot pass by returning unsupported.

Do not mark this package complete until behavioral fixtures, compile-fail safety fixtures, the package budget fixture and all applicable native/WASM jobs pass. A declaration-only typecheck is API verification, not a package acceptance result.

## 7. Primary sources

- https://wasi.dev/releases
- https://wasi.dev/releases/wasi-p3
- https://docs.wasmtime.dev/c-api/
- https://docs.wasmtime.dev/security.html
- https://github.com/wasm-micro-runtime/wasm-micro-runtime
