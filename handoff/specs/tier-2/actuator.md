# flint:actuator — Health, bounded metrics and OTLP observability

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] Liveness/readiness endpoints, Prometheus text scrape and OTLP/HTTP trace/metric export.
- [ ] Counter/histogram registration at startup; request paths update preallocated series.
- [ ] W3C-compatible trace IDs carried explicitly across fibers and worker completion records.
- [ ] Bounded queues, drop counters, redactable health details and graceful exporter shutdown.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/actuator/dub.sdl inside the Flint root that declares all subpackages. Module: flint.actuator. Direct allowed dependencies: flint:arena, flint:reactor, flint:web, flint:http, flint:log, flint:serde, flint:conc.

```sdl
name "actuator"
description "Flint actuator subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:reactor" version="*"
dependency "flint:web" version="*"
dependency "flint:http" version="*"
dependency "flint:log" version="*"
dependency "flint:serde" version="*"
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

The source library has no executable main. Native build/link selection follows the central C-FFI matrix. Public imports are explicit; transitive dependency reachability does not authorize undeclared direct imports. No package in this specification may import a higher catalog tier or introduce a cycle.

## 3. Concrete public D contract

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/actuator.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.actuator;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;
import flint.web : Server;

@safe:
enum HealthStatus : ubyte
{
    up,
    down,
    unknown
}

struct Health
{
    HealthStatus status;
    string component;
}

alias HealthProbe = Health delegate() @safe nothrow @nogc;
struct Counter
{
    private uint id;
}

struct Histogram
{
    private uint id;
}

struct TraceContext
{
    ubyte[16] traceId;
    ubyte[8] spanId;
    ubyte flags;
}

struct Span
{
    private ulong slot;
    private ulong generation;
    Error finish(long monotonicNanos, bool failed) nothrow @nogc;
}

struct ActuatorOptions
{
    string pathPrefix = "/actuator";
    uint maxMetricSeries = 4096;
    uint maxSpansQueued = 8192;
    uint maxBatchSpans = 256;
    string otlpEndpoint;
    long exportIntervalNanos = 5_000_000_000L;
}

struct Registry
{
    private ulong slot;
    private ulong generation;
    Error open(ActuatorOptions options);
    Result!Counter counter(string name, string help);
    Result!Histogram histogram(string name, scope const(double)[] bounds);
    void add(Counter counter, ulong delta = 1) nothrow @nogc;
    void record(Histogram histogram, double value) nothrow @nogc;
    Error health(string name, HealthProbe probe);
    Result!Buffer scrape(ref scope RequestArena arena) nothrow @nogc;
    Result!Span beginSpan(string name, TraceContext parent, long monotonicNanos) nothrow @nogc;
    Error exportBatch(ref Context context) nothrow @nogc;
    Error attach(ref Server server);
    Error close(ref Context context) nothrow @nogc;
}
```

## 4. Internal architecture and observable semantics

Registry.open allocates metric series, label dictionaries and span slots at startup. Registration returns compact handles; recording never inserts a new label value. Cardinality is capped at 4,096 series and rejected registration fails startup. Labels such as raw path, user ID, query string and request ID are prohibited by the default schema. Histograms have at most 32 strictly increasing finite bounds; NaN and infinities go to a dedicated invalid-input counter rather than corrupting bucket sums.

Counters and histogram observations update per-core cache-aligned cells. Scrapes merge a consistent snapshot without holding a global lock across socket writes. Prometheus output escapes help/labels, emits monotonic cumulative buckets and includes a +Inf bucket. Internal deadlines, queue lengths and allocation counters use fixed label sets. /actuator/health/live checks the process/event-loop heartbeat only; it does not fail because a database is down. /actuator/health/ready includes configured dependencies and reports 503 while draining. Details default hidden; management endpoints bind separately or use application-supplied auth.

TraceContext is a value carried in RequestContext extensions or a task envelope. Thread-local MDC is only a cache of the current fiber's context; save/restore it on every fiber switch. Span creation acquires a slot from an 8,192-element ring. Overflow drops the span, increments a counter and leaves the request successful. Export batches at 256 spans or five seconds. An exporter has its own deadline and queue; telemetry failure never recursively creates an unbounded telemetry loop.

Choose OTLP/HTTP JSON for the first production profile. Its payload must follow OTLP's Protobuf JSON mapping, not an arbitrary JSON schema: IDs use the protocol's encoding, integer timestamps are decimal strings and fields have the required casing. Send to /v1/traces and /v1/metrics with application/json, parse partial-success responses and count rejected items. Retries honor server retry instructions for retryable errors, use bounded exponential backoff and stop at 60 seconds total or shutdown deadline. A response-body parse failure is not success. Later binary Protobuf support is a separate configuration with fixture parity, not a silent transport swap.

Span names are copied into a fixed 128-byte slot at beginSpan; reject longer names at registration or truncate with an explicit counter under a chosen policy. Never retain an arbitrary D string pointer in an unmanaged exporter ring. Startup-registered metric names remain rooted for the Registry lifetime.

### Required implementation layout

- source/flint/actuator.d: typed metric/span handles and attachment API.
- source/flint/actuator/registry.d: preallocated per-core cells.
- source/flint/actuator/prometheus.d: bounded text exposition.
- source/flint/actuator/otlp.d: exact OTLP JSON encoder/export state machine.

## 5. Native boundary, ownership and safety

No direct C library is added. HTTP/TLS reuse flint:http; server endpoints reuse flint:web. Metric atomics and per-core aggregation use flint:reactor/conc. Do not pull a C++ OpenTelemetry SDK into the base runtime. Trace ID randomness comes from the existing OS secure-random boundary, not an ad hoc PRNG; sampling decisions may use a documented noncryptographic hash of an already random trace ID.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

No additional native dependency; consume only the lower-tier packages listed above.

### Native preparation before DUB

On the Linux glibc release runner, the exact preparation command is:

```bash
python3 tools/native_build.py --profile rest --target linux-x86_64-glibc --phase build --emit-dub
```

Use --phase plan to inspect resolved commands without claiming a build. The build installs pinned archives and a verified libflint_ffi.a from implemented native shims, then writes a delimited platform-specific lflags block into affected DUB recipes. Installation receipts are cumulative. Cross-target commands replace the target with the exact central matrix target and use its SDK/toolchain. C shim source must exist at the implementation milestone; missing shims must fail the build rather than produce a fake library.

## 6. Numeric compile and size budgets

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

| Measurement | Hard ceiling |
| --- | --- |
| Cold DMD fixture build | 1.80 s |
| Incremental DMD leaf edit | 0.60 s |
| Cold LDC fixture build | 10.80 s |
| Incremental LDC leaf edit | 5.40 s |
| Incremental linked code/data contribution | 1048576 bytes |
| Compiler peak RSS | 536870912 bytes |
| Template instances per canonical fixture | 2000 |

These are engineering ceilings from scaffold/policy/packages.json, measured with the fixed runner/toolchain/workload policy. They are not measured achievements of these declarations. Also fail >10% compile-time/compiler-RSS/template growth or >5% binary growth against the approved baseline. The whole selected application includes native libraries in its cap; a smaller wrapper-only delta cannot excuse a larger deployment artifact. A changed profile is a different benchmark identity and cannot be compared as if equivalent.

## 7. Required unit, protocol, fuzz and benchmark acceptance

| Test identity | Passing condition |
| --- | --- |
| metric_cardinality | Registration 4097 fails with resourceExhausted; requests cannot grow labels at runtime. |
| histogram_buckets | Boundary values map correctly, cumulative buckets are monotonic, +Inf equals count and sum excludes invalid samples. |
| health_semantics | Database outage flips readiness to 503 while liveness remains 200; draining flips readiness before listener shutdown. |
| trace_fibers | Interleave 100 fibers on one core; every log/span has the correct request trace, including worker round trips. |
| otlp_json | Compare serialized trace/metric bodies with checked fixtures and an official collector; test partial-success counters. |
| export_overload | Hold exporter offline for ten minutes; queue stays ≤8192 spans, request latency stays bounded, drops are counted. |
| scrape_race | Continuously record during scrapes; no invalid text, deadlock or negative bucket count. |
| observe_bench | Measure counter and histogram operations for 1/8/32 cores; no D allocation and no global hot lock. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :actuator --compiler=dmd
dub test :actuator --compiler=ldc2
python3 tools/gates.py --package actuator --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [OTLP specification](https://opentelemetry.io/docs/specs/otlp/) — OTLP/HTTP supports Protobuf JSON and defines signal endpoints/partial success.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
