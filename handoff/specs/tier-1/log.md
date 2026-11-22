# flint:log — implementation specification

Status: normative design for agents; contract declarations have been syntax checked. Runtime behavior below is an acceptance requirement, not a claim that a framework implementation already exists. The compiler receipt is [core-contracts.json](../../verification/core-contracts.json).

## 1. Purpose and reference parity

Provide structured JSON/console logging with bounded producer work and explicit request context propagation across fibers and workers.

- [ ] SLF4J/slog-style levels, fields and context; JSON production output and human-readable console output.
- [ ] Bounded asynchronous sinks, controlled flush/close, drop accounting and explicit secret redaction policy.
- [ ] A logger never imports web/config or auto-discovers the current service.

## 2. Package boundary and exact DUB recipe

Catalog tier: **1**. Direct allowed Flint dependencies: **flint:arena, flint:conc**. No transitive import is an excuse to add a direct import without updating the dependency policy. Production code may not depend on flint:test. Recipe path: `packages/log/dub.sdl`, invoked from the monorepo root.

```sdl
name "log"
description "Flint log subpackage"
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

These are concrete signatures in the contract fixture, not executable implementations. Internal representation may change while preserving signatures and semantics. Source: `contracts/source/flint/log.d`.

```d
/// Public API contract; declarations are not runtime implementations.
module flint.log;
import flint.arena : Status, Error, Result;

@safe:
enum Level : ubyte
{
    trace,
    debug_,
    info,
    warn,
    error,
    off
}

enum Format : ubyte
{
    json,
    console
}

struct Field
{
    string key;
    string value;
}

struct LogContext
{
    ulong requestId;
    ulong traceIdHigh;
    ulong traceIdLow;
    ulong spanId;
}

struct LogOptions
{
    Level level = Level.info;
    Format format = Format.json;
    uint ringBytes = 1048576;
    uint maxRecordBytes = 4096;
}

struct Logger
{
    private ulong id;
    static Result!Logger create(LogOptions options);
    Status write(Level level, scope const(char)[] message, scope const(Field)[] fields,
            LogContext context = LogContext.init) nothrow @nogc;
    Status info(scope const(char)[] message, scope const(Field)[] fields = null) nothrow @nogc;
    Status warn(scope const(char)[] message, scope const(Field)[] fields = null) nothrow @nogc;
    Status error(scope const(char)[] message, scope const(Field)[] fields = null) nothrow @nogc;
    Error flush(ulong timeoutMillis = 1000) nothrow @nogc;
    void close() nothrow;
}
```

## 4. Internal architecture, ownership and safety

Create each logger and its bounded per-producer ring before request traffic. Producers copy the complete record, message and field bytes into the ring while the call is active; they retain no string/slice after return. A dedicated consumer serializes/writes complete records to stdout/stderr or a configured file. The default maximum record is 4096 bytes, default ring 1 MiB, and keys are UTF-8 strings with a maximum length of 128 bytes. Reject oversized records with `resourceExhausted` and increment a counter; do not truncate structured JSON into invalid output. JSON escaping is a small local byte writer, not an upward import of a server. Time stamps are RFC3339 UTC with millisecond precision and monotonic sequence IDs to order same-time records.

Backpressure is explicit: on a full ring, request producers drop the new record, return `resourceExhausted` and increment per-level dropped counters. They never block a reactor core. Error records use a separately reserved 64 KiB ring; exhaustion is still reported and never converted into a synchronous secret-bearing stderr dump. Startup/shutdown code may call flush with a deadline and react to its Error. Fatal process diagnostics are a separate crash handler policy, not an allocation in Logger.error.

MDC is task-local. The reactor installs/restores the current LogContext on every fiber resume/yield; storing a single thread-local request ID without restoration is incorrect when fibers interleave. The explicit `write(...,context)` path remains available and is required for worker tasks. Copy LogContext in worker input/completion metadata. Do not infer trace IDs from private request pointers. A plain standalone CLI uses zero context. Context storage may be TLS as an implementation cache only while one known task is executing; the task record is the source of truth.

The facade accepts already formatted messages and typed field strings. Generic formatting with concatenation, std.format or exception formatting on the caller's hot path is rejected by @nogc. Redact known keys (authorization, cookie, password, secret, token, api_key) before copy; provide application opt-in allowlists for sensitive structured payloads. This is an explicit logging policy, not a guarantee that arbitrary message text contains no secrets. Configuration fields marked Secret are never passed unredacted to logs.

**Safety boundary:** Only OS sink and atomic ring implementation modules under `flint.log.sys` may be trusted. Startup may allocate. Every producer method is `@safe nothrow @nogc`; flush is bounded and excluded from request handlers.

## 5. Compile-time, size and runtime budgets

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

These are release gates on the designated reference runner, not observed performance results. Measure the package's fixed feature fixture, with dependencies frozen; cold/incremental definitions and statistical regression rules come from [CI budgets](../../docs/CI_PERFORMANCE_BUDGETS.md).

| Metric | Hard ceiling |
| --- | ---: |
| DMD cold build | 0.80 s |
| DMD incremental build | 0.60 s |
| LDC cold build | 4.80 s |
| LDC incremental build | 2.40 s |
| Marginal stripped linked bytes | 262,144 bytes |
| Compiler peak RSS | 536,870,912 bytes |
| Template instantiations | 2,000 |

The >10% compile/template/RSS regression rule and >5% binary growth rule also apply; passing a hard ceiling does not permit silent drift. Marginal size follows the provider-equivalent definition above; full native-provider and dependency footprints remain in the recorded complete binaries. Package deltas are not summed to estimate an application. Native shared-library bytes and static-dependency bytes must both be reported. BetterC core: **not claimed**.

**Benchmark fixture:** Measure disabled-level calls, accepted 128-byte and 4 KiB records, saturated drop behavior and consumer throughput. Report producer p99 latency and drop counts together; dropping everything is not a performance win.

## 6. Required acceptance tests and edge cases

1. JSON escaping for control bytes/quotes/Unicode, empty messages and fields, 4095/4096/4097-byte records.
2. Full ring, reserved error ring full, consumer failure, timeout flush, close with pending records and double close.
3. Two interleaved fibers and an offloaded worker retain distinct request/trace IDs.
4. No borrowed input survives return: mutate backing after write and verify emitted record is the original copy.
5. Hot producer per-thread GC allocation delta zero; logs remain valid JSON under 32 concurrent producers.

Every listed case becomes a named unittest or a compiler-negative fixture, with a deterministic seed for generated schedules/inputs. FFI/kernel lifetime tests run under the platform sanitizer jobs. Add regression fixtures for every corrected failure before closing the slice.

## 7. Agent implementation order and definition of done

1. Add the package modules and public declarations, compile the positive contract usage and the negative misuse fixtures, then implement the smallest deterministic behavior covered by the first acceptance group.
2. Complete ownership/error paths before adding throughput optimization; include bounded-resource exhaustion tests.
3. Add the fixed benchmark fixture, record raw samples and candidate baseline receipts, and complete all acceptance groups before activating this package for integration.

Run from `scaffold/` after implementing this package:

```bash
python3 tools/flint.py test --package log --compiler dmd
python3 tools/gates.py --package log --gate structural
```

The direct test equivalent is `dub test :log --compiler=dmd`. Repeat with `--compiler ldc2` through the orchestrator. A declaration-only contract pass is never a substitute for `dub test` on a runtime implementation. Full Gates 1–6 run for the integrated milestone once its canonical apps and runner baselines exist; absence of a required measurement blocks release rather than fabricating a zero measurement.

## Evidence and rationale

The D capability behind this design is documented at [https://dlang.org/library/core/thread/fiber/fiber.html](https://dlang.org/library/core/thread/fiber/fiber.html) (accessed 2026-11-21). Normative limits, failure codes and ownership policies above are Flint design decisions. See [core research evidence](../../research/core-sources.md) for precise capability claims and verification boundaries.
