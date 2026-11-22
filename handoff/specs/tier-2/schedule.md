# flint:schedule — Scheduled jobs and explicit resilience wrappers

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] @Scheduled fixed rate/fixed delay/cron registration.
- [ ] @Retryable metadata compiled into registered invokers; circuit breaker, token bucket and timeout primitives.
- [ ] Context cancellation, deterministic test clocks and nonoverlap by default.
- [ ] No hidden background scheduler or AOP on ordinary method calls.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/schedule/dub.sdl inside the Flint root that declares all subpackages. Module: flint.schedule. Direct allowed dependencies: flint:arena, flint:reactor, flint:conc, flint:log.

```sdl
name "schedule"
description "Flint schedule subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:reactor" version="*"
dependency "flint:conc" version="*"
dependency "flint:log" version="*"

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

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/schedule.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.schedule;
import flint.arena : Error, Result;
import flint.conc : Context;

@safe:
struct Scheduled
{
    string cron;
    long fixedRateNanos;
    long fixedDelayNanos;
    bool concurrent = false;
}

struct Retryable
{
    uint maxAttempts = 3;
    long initialDelayNanos = 100_000_000L;
    long maxDelayNanos = 2_000_000_000L;
}

struct RetryPolicy
{
    uint maxAttempts = 3;
    long initialDelayNanos = 100_000_000L;
    long maxDelayNanos = 2_000_000_000L;
    bool idempotent = false;
}

enum CircuitState : ubyte
{
    closed,
    open,
    halfOpen
}

struct CircuitBreaker
{
    private ulong slot;
    private ulong generation;
    Error open(uint window = 100, uint failurePercent = 50, long openNanos = 30_000_000_000L);
    Result!bool permit(long nowNanos) nothrow @nogc;
    void record(bool success, long nowNanos) nothrow @nogc;
    CircuitState state() const nothrow @nogc;
}

struct RateLimiter
{
    private ulong slot;
    private ulong generation;
    Error open(uint burst, uint tokensPerSecond);
    Result!bool acquire(uint tokens, long nowNanos) nothrow @nogc;
}

alias ScheduledTask = Error delegate(ref Context context) @safe nothrow @nogc;
struct Scheduler
{
    private ulong slot;
    private ulong generation;
    Error open(uint capacity = 1024);
    Result!ulong add(string name, Scheduled schedule, ScheduledTask task);
    Error cancel(ulong taskId) nothrow @nogc;
    Error poll(long utcSeconds, long monotonicNanos) nothrow @nogc;
    Error close(ref Context context) nothrow @nogc;
}

Error withRetry(ref Context context, RetryPolicy policy, scope ScheduledTask operation) nothrow @nogc;
Error registerScheduled(T)(ref Scheduler scheduler, ref T component);
```

## 4. Internal architecture and observable semantics

Scheduler.open preallocates 1,024 jobs and a min-heap of next deadlines. Fixed-rate scheduling uses a monotonic clock anchored to the original schedule; fixed-delay scheduling computes the next time after completion. Only one of cron, fixedRateNanos or fixedDelayNanos may be nonzero/nonempty. Invalid combinations are compile errors for UDAs and invalidArgument for runtime registration. Cron is exactly six fields (second minute hour day-of-month month day-of-week) in UTC. Support *, comma lists, numeric ranges and /steps; disallow named months, L/W/# and seconds 60. Day-of-month/day-of-week uses OR when both are restricted; document this in generated help.

Jobs never overlap unless concurrent=true. A missed fixed-rate tick is coalesced into one execution; after a long pause, do not enqueue a burst of catch-up jobs. Cron selects the next matching UTC instant strictly after now. Clock regressions do not repeat completed schedule IDs. Each job owns a child Context and an explicit cancellation token; cancel is idempotent and removes pending work, while close waits for admitted jobs until its deadline.

withRetry requires policy.idempotent=true for automatic retries. The allowed retry categories are unavailable, timedOut before a confirmed side effect, and an explicit caller retry predicate provided by the registered adapter; validation/auth/conflict errors are never retried by default. Backoff doubles from 100 ms to 2 seconds, applies full jitter from a scheduler-owned seeded random source and is clipped to the remaining Context deadline. maxAttempts includes the first attempt. No retry occurs after output has been streamed or a transaction commit is known to have succeeded.

CircuitBreaker uses a rolling window of 100 completed calls; after at least 20 samples, ≥50% failures opens it for 30 seconds. Half-open permits one probe at a time; success resets the window, failure reopens it. Rejections return unavailable immediately. RateLimiter uses integer nanosecond arithmetic and a token bucket; capacity and replenishment are checked against overflow. Neither resilience wrapper allocates on admitted operations. Ordinary direct calls to an annotated method remain ordinary calls; only registered/generated invokers install the wrapper.

### Required implementation layout

- source/flint/schedule.d: public UDAs, scheduler and policy contracts.
- source/flint/schedule/cron.d: bounded parser and UTC next-occurrence calculator.
- source/flint/schedule/resilience.d: retry/circuit/token-bucket algorithms.
- tests/clock: deterministic synthetic time and jitter fixtures.

## 5. Native boundary, ownership and safety

No additional C library. Timers use flint:reactor and task ownership uses flint:conc. UTC calendar conversion is a bounded D implementation over integer days; it does not consult mutable process timezone state. Platform monotonic clock calls remain in the reactor sys boundary.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

No additional native dependency; consume only the lower-tier packages listed above.

### Native preparation before DUB

On the Linux glibc release runner, the exact preparation command is:

```bash
python3 tools/native_build.py --library liburing --target linux-x86_64-glibc --phase build --emit-dub
```

Use --phase plan to inspect resolved commands without claiming a build. The build installs pinned archives and a verified libflint_ffi.a from implemented native shims, then writes a delimited platform-specific lflags block into affected DUB recipes. Installation receipts are cumulative. Cross-target commands replace the target with the exact central matrix target and use its SDK/toolchain. C shim source must exist at the implementation milestone; missing shims must fail the build rather than produce a fake library.

The liburing selection is Linux-only; kqueue/IOCP need only their platform SDK imports and no liburing artifact.

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
| schedule_conflicts | Two schedule modes on one method fail compile; zero mode and zero/negative periods fail registration. |
| cron_vectors | Leap day, month rollover, Sunday numbering 0/7, comma/range/step forms and DOM/DOW OR cases have exact expected UTC instants. |
| clock_jump | Jump wall time ±24 h and pause monotonic delivery for 60 s; no busy loop, duplicated completed job or catch-up flood. |
| nonoverlap | A job taking three periods executes at most once concurrently; concurrent mode respects explicit worker capacity. |
| retry_budget | A fake 350-ms deadline permits only attempts fitting its budget and never sleeps past cancellation. |
| circuit_states | Use deterministic 20-sample failure window; prove closed→open→single half-open probe→closed/open transitions. |
| rate_limits | Refill fractional intervals without losing long-term rate; huge nanosecond gaps saturate capacity without overflow. |
| scheduler_bench | Schedule/cancel 100k jobs through repeated slots; bounded memory, zero D allocations in poll, heap depth ≤ceil(log2(capacity)). |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :schedule --compiler=dmd
dub test :schedule --compiler=ldc2
python3 tools/gates.py --package schedule --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [D UDA semantics](https://dlang.org/spec/attribute.html) — UDAs are compile-time metadata and do not automatically intercept a function call.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
