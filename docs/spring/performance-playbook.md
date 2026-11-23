# Performance playbook for porting Java libraries to Flint

This is the master record of what makes ported Spring, Spring Boot and other Java code fast, small and quick to build in Flint, and of what made it slow. Every rule comes from a measured finding. Read it before porting a module, and check a finished port against the checklist at the end.

**Keeping it current.** Any commit that improves or regresses build time, binary size or runtime adds or updates an entry here in the same commit. An entry carries:
- the rule;
- the evidence: numbers, commit and how they were measured;
- what enforces it: the gate, test or budget, or "not enforced yet".

A rule that turns out wrong is corrected, not deleted, with the evidence that changed it. Certified numbers come only from proof-harness's measurement queue (`docs/spring/phase1/coordination.md`, "Measurement"); local numbers are labelled as such.

**Why this exists.** Flint's own engines are faster than Go: `bench-rest` serves 1.68× Go's throughput in about 12 MB. A faithful port of Java's design was not: the first certified gs-rest-service run had throughput at 0.75 of Go and p99 at 2.45×. Java code is written for a JIT with escape analysis and a generational collector. It allocates freely, uses reflection-shaped generics and dispatches virtually everywhere, and in D each of those habits has a price. Phase 1 found the prices one by one; this file keeps them, so later ports pay none of them.

## 1. Runtime: CPU, latency and memory

The largest costs are per-request allocation and the collector pauses it causes. On gs-rest-service at 31 allocations per request, druntime ran about 90 stop-the-world collections a second: 7–11% of wall time paused, the GC 39% of user CPU, and those pauses drove p99 (`docs/spring/phase1/gc.md`).

| ID | Rule | Evidence | Enforced by |
|---|---|---|---|
| R-1 | **Engine and framework memory never reaches the GC heap per request.** Only objects user code sees are GC memory: DTOs, entities, strings it receives. Everything else lives in the request arena, on the stack, or in reused buffers (ADR-030 §4). The target for `/greeting` is the user's `Greeting` and its string, nothing else. | /greeting 50 → 16 GC allocations per request across the commits below, with worker instructions 71.1k → 65.5k (web-http, callgrind, LDC). | Allocation budget gate, work-queue item 28 (`policy/request-allocations.json`), in progress |
| R-2 | **Parse once and cache what Java parses on every call:** media types (Spring's `MimeTypeUtils` LRU cache), Accept headers, lookup paths, content types. Never build a `ContentNegotiationManager` or a media-type list per request. | `6ae93070` (Accept in one allocation), `6a48c768` (lookup path in one object; a match without variables allocates nothing), `71216ac7` (content type kept). Content negotiation was 21% of user CPU and 10 GC points before. | Allocation gate |
| R-3 | **Store small collections inline.** Request attributes, parameters, headers and response headers keep their first N entries inside the owning object. `Any` stores small structs (up to 32 bytes) inline instead of boxing. | `27e8d10b`: 8 inline attribute slots, 4 parameter slots, 4 header entries plus 4 single values. `Any` inline: framework-core, in progress. | Allocation gate |
| R-4 | **Create per-handler objects once at startup and share them, but only if they are immutable after warm-up.** Spring creates some per request, such as `ServletInvocableHandlerMethod`. A shared object is never written during a request; a concurrent multi-thread test proves it. | `73d9ecbf` (−1 allocation). | Its concurrency test |
| R-5 | **Pass handler arguments in scoped stack storage.** Use DIP1000 `scope` slices, not `Any[]` arrays or wrapper objects. Fall back to the heap past a fixed count (8). | flint-aot's `d617083c` (`invokeArguments`) plus `73d9ecbf` (−2). | A compile-fail test that stores the slice |
| R-6 | **Recycle engine-internal objects, never user-visible ones.** JSON generators, parsers and buffers come from a bounded compare-and-swap pool and forget their sink and context on release. Never recycle an object user code can still hold: in D, a reference held across threads can tear a slice, which a Java reference cannot. A released instance fails loudly on use. | `852b8a8e`: Jackson per write 576 B in 4 allocations → 0. `c812b1b7`: reads down to the user's objects, e.g. OwnerFieldsDto 1,152 → 176 B. | `write_allocations_test` and the use-after-release test |
| R-7 | **No locks or monitors on hot lookups.** Configuration and pattern caches are read without a monitor; publish them immutably. | `cab192b6`: `MapperConfig.bean()` took a monitor that every reactor thread contended on. Hibernate's `PatternCache` likewise. | Not enforced yet |
| R-8 | **Never copy a payload twice.** Stream serialisation straight into the response; don't build a string and then convert it to bytes. | `b7c8891d` (`writeValueAsBytes`), then streaming through recycled generators in `27e8d10b`. | Allocation gate |
| R-9 | **Keep GC roots small and grow them lazily.** Register large engine tables as roots in chunks as they are first used, not all at startup. Size preallocated pools by the configured connection limit. | `8815f2d2`: 8,192 connection slots (4.8 MB) became doubling chunks; the pause per collection fell from 0.96 to 0.64–0.79 ms locally. `9aa14e28`: io_uring rings capped, peak RSS 24.5 → 21.5 MB. Certified RSS 1.82 → 1.61 of Go (`b231d2c2`). | gc.md measurements |
| R-10 | **Wake waiting fibers on completion; never poll.** | `e5839c8`: delayed-peer CPU fell 15× and 12×, and the median reply fell from 1,016 µs to 12 µs. | `98c4558d` counts fiber resumptions |
| R-11 | **Control-flow exceptions don't capture backtraces.** Engines return `Result`; generated dispatch converts to an exception only at the user boundary. 404 and validation paths have their own p99 runs. | ADR-030 §3. | The error-path p99 entries |
| R-12 | **Measure system calls before optimising them.** io_uring steps 1–3 (single enter, cooperative and deferred task running) left enters per request unchanged, and the certified runs showed no throughput gain from them. The allocation cuts moved the numbers. | `b231d2c2`, `345d0290`. | — |
| R-13 | **Don't change Spring's public extension-point signatures to save an allocation.** For example, `scope` parameters on `HandlerMethodArgumentResolver` would break every implementer. Avoid building the object instead: lazy materialisation on a per-endpoint fast path. | web-http, `73d9ecbf` notes. The fast-path spike is in progress. | Rulebook review |
| R-14 | **Don't link a second subsystem by default.** A prototype or alternative engine is opt-in through a version or profile flag until it wins a measurement. | `a84a8c14`: the Flint collector cost about 91 KB at Oz in every program that used `flint:arena`. | Size ratios |

## 2. Binary size

| ID | Rule | Evidence | Enforced by |
|---|---|---|---|
| S-1 | **Pay for what you use, through reachability.** D keeps every virtual method of a linked class alive through its vtable. Code that only some apps need, such as date parsing or `@JsonFormat` patterns, must not be reachable from an always-linked virtual or class. Put it behind a module that registration links: Jackson's `Module` API, an AOT-generated customizer, or a templated façade. Mark API methods `final` where upstream allows, so they leave the vtable. | Jackson Date went from +16% (+80 KB) to +2.6% on the jackson-databind probe (`5e48603a`, `bc95dae5`, `20493652`); every app paid about 70 KB before and 9–17 KB after. Diagnosis: `--print-gc-sections` and linker maps. | Per-package linked-bytes ratio (1.05) and ceilings |
| S-2 | **No `std.process`, `std.file` or `std.path` in framework packages.** Go through the host facade. | `ab46223d`: `java` linked 624,744 → 162,024 B. | Size ratios; not import-banned yet |
| S-3 | **Toolchain levers stay on:** RELR packed relocations, `--gc-sections`, `-fno-moduleinfo-localclasses` (ADR-030 §4), and TLS-only OpenSSL (ADR-031). | Oz 0.594–0.617 of Go, passing. | Oz against Go in gs-builds |
| S-4 | **Compare stripped binaries only,** against Go's `-s -w`. | An unstripped comparison read 1.78× where the truth was 1.24×. | proof-harness |

## 3. Build time

| ID | Rule | Evidence | Enforced by |
|---|---|---|---|
| B-1 | **Erased engine, thin typed façade** (ADR-030 §2). Generic public APIs are one-line templates over a non-template engine driven by descriptors. A template instantiated by user code is compiled in the user's build, every build. | `std.format.format!(char,string)` was 26 ms of a 57 ms served compile; `String.format` now runs over one non-template `Formatter` (`ea038af1`). | Template budgets: corrected count ×1.25, then only down (`e765293f`, `e849cb88`) |
| B-2 | **Avoid heavyweight Phobos templates** in anything a user build compiles: `std.format`, `std.datetime`, `std.path.buildPath`, `std.conv.to` chains, ranges and algorithms. Prefer small hand-written helpers, with a test against the Phobos result. | `001075b0`: `buildPath` took flint:config's compile from 56 to 110 ms on non-Linux hosts. `9db7fcd5`: context off `std.datetime`. | Template budgets |
| B-3 | **Generated code instantiates nothing per type that it can look up.** Reuse the module's own descriptors, use literal canonical names, and skip annotation types the shared cache already describes. | `3a5bfc94` (no `descriptorOf!(T)`), `d29a3926` (erased containers), `e755d28a`, `1b3b2c63` (raw checked cache entries, models parsed once), `c26facb0`. | Generated-module compile times in gs-builds phases |
| B-4 | **Cache by content and by the exact files a tool reads, never by directory mtimes.** Build tools write outputs into package directories. | 78 ms of every cached cold build was a stale platform description, because DUB drops libraries into package roots (m7, fix in progress). | The fix's tests |
| B-5 | **Keep DUB and hashing off the hot paths.** Dev builds compile and link directly, replaying DUB's recorded commands, with staleness tests. Dev receipts hash outputs lazily. The platform description and digests live in `FLINT_CACHE`. | `bf7b7b97`, `dc711c95`, `2d8a16dc`, `804c2b6c`, `87c13a93`. Cached cold 3.07 → 1.255 of Go; shared edit 0.398. | gs-builds phase budgets |
| B-6 | **Dev builds link shared; static links use 8 threads.** | Owner decision on dev shared linking. `df11097e`: static link 174 → 136 ms; `943466fa` makes 8 the default. | gs-builds |
| B-7 | **A served compile produces exactly what an in-process compile produces,** or fails loudly. | Missing instances fail as FLINT-E0701 (prelude, `42ebbef9`). `027721b6`: a failed served link used to exit 0. | Parity tests in the fork |

## 4. Measuring honestly

| ID | Rule | Evidence |
|---|---|---|
| M-1 | **Give Flint exactly the state Go gets.** Every cold trial starts from a fresh, platform-only cache, with no project-keyed reuse; the harness fails a trial that reuses project state. | `bf57dc9f`. The 2.52 primary at `2018e5e5` had reused the app's AOT output and was optimistic. |
| M-2 | **Match the comparator's flags:** `--no-debug`, against Go's `-s -w`. Publish the other variant as non-gating context. | Owner decision `4b27d207`. |
| M-3 | **Trace before fixing, and mirror the harness exactly when reproducing.** Priming order and the cache's history change results. | The 377 ms cold `flint` phase was a `.so` relink; the 78 ms was a stale record that only appeared after priming several configurations. |
| M-4 | **Measure in claimed windows with everything else paused,** pin base and candidate to the same conditions, and label combined changes honestly. | `docs/spring/phase1/coordination.md`, "Measurement". |

## 5. Correctness traps found while optimising

Speed work introduced these, or exposed them. Check every optimisation against them.

- **Shared or recycled objects across reactor threads.** Immutability, or a loud failure on misuse, plus a concurrent test (R-4, R-6).
- **Thread-local storage in shared libraries.** The AArch64 backend used local-exec TLS under `-fPIC`, so a library's variables silently aliased the executable's. Initial-exec through the GOT is used now, with tests that cover `dlopen`.
- **Signal dispositions inherited by worker processes.** An ignored `SIGCHLD` turned linker failures into success (`027721b6`).
- **Caches and replays that go stale silently.** Test that adding a file, removing one, changing a string import, or restoring an mtime invalidates them (`87c13a93`, `c4a5a8b2`).
- **Pay-for-use registration gaps.** Every typed path that can need the optional code must link it. The remaining gap is a recorded deviation with a loud message (D-JACKSON-10).

## 6. Checklist for porting a module

Before a ported module lands:

1. **Allocations.** Count GC allocations per call on its hot paths with the counting method in gc.md. Only user-visible objects may remain (R-1 to R-8). Add or lower its entry in `policy/request-allocations.json` once the gate exists.
2. **Hot-path engine code** is `nothrow @nogc`, returns `Result`, and uses the arena or reused buffers.
3. **No per-call parsing** of anything that could be parsed once and cached (R-2); no monitors on lookups (R-7).
4. **Templates.** Generic public APIs are thin façades over erased engines (B-1). No heavyweight Phobos templates (B-2). The module stays within its template budget.
5. **Size.** Linked bytes stay within the module's ratio and ceiling. Optional functionality is unreachable unless used (S-1). No `std.process`, `std.file` or `std.path` (S-2).
6. **Exceptions** used for control flow skip backtraces (R-11).
7. **Shared state.** Anything created once and shared is immutable after warm-up, or protected, and has a concurrent test (R-4).
8. **Generated code.** Anything the module asks Flint AOT to generate instantiates nothing per type it can look up (B-3).
9. **Records.** New findings are added to this file in the same commit.

## Open items

| Item | Owner | State |
|---|---|---|
| Allocation budget gate (item 28) | data-access | In progress |
| `Any` inline small structs; java.time slice parsing | framework-core, third-party-apis | In progress |
| Per-endpoint AOT fast path with lazy Spring objects | fast-path spike | Spike |
| Concurrent marking collector (gc.md option D3) | data-access | Prototype |
| Package-root watch fix (B-4) | m7-flint-cli | Approved |
| Compile-server hand-off (~15 ms per served compile) | dmd-arm64 | Queued |
| Import bans for S-2 and B-2 in the structural gate | — | Not started |
