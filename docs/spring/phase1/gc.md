# GC and RSS: the ADR-030 fallback

Owner: data-access. The coordinator assigned this on 2026-11-23 (decisions.md, "ADR-030 section 4's agreed GC fallback is triggered"). The certified gs-rest-multicore run (15:59Z, gs-rest-service at `c473ea7b`, 2 server CPUs, 64 connections, 9 trials) lost every runtime metric to Go:

| metric | Flint | Go | ratio |
|---|---|---|---|
| peak RSS | 25.1 MB | 13.8 MB | 1.82 |
| p99 at 20k req/s | 0.632 ms | 0.258 ms | 2.45 |
| p50 at 20k req/s | 0.111 ms | 0.060 ms | 1.84 |
| capacity | 187k req/s | 251k req/s | 0.75 |
| CPU per request | 11.4 µs | 8.3 µs | 1.38 |

This note covers RSS and the collector. web-http owns request-path CPU, and third-party-apis owns JSON cost.

## 1. Where the time and memory go

These are local diagnosis numbers, not evidence. They come from gs-rest-service built with `flint build --profile release` at `972d8d32`. The server was pinned to CPUs 20–21, and oha 1.16.0 ran on CPUs 22–25 with 64 connections against `/greeting?name=Flint` for 10–15 s. The probes were `rss_probe.py`, which reads `/proc/<pid>/smaps`, and `gc_probe.sh`, which runs the server under gdb and reads `gc_profileStats`. Every run went through `measure_queue.py hold`. Only proof-harness's queue produces evidence (section 4).

### 1.1 The collector stops both reactors about 90 times a second

| druntime setting (`--DRT-gcopt`) | peak RSS | collections in ~11 s | total pause | max pause |
|---|---|---|---|---|
| default (conservative, parallel marking) | 24.5 MB | 942 | 0.84 s | 6.8 ms |
| `parallel:0` | 23.5 MB | 872 | 1.23 s | 14.6 ms |
| `parallel:1` | 24.2 MB | 890 | 0.91 s | 6.3 ms |
| `gc:precise parallel:1` | 24.2 MB | 775 | 0.95 s | 16.5 ms |
| `parallel:1 heapSizeFactor:4` | 23.7 MB | 870 | 0.86 s | 5.3 ms |
| `parallel:1 minPoolSize:16 incPoolSize:4` | 24.2 MB | 852 | 0.76 s | 5.1 ms |

The `fork:1` run was lost to a probe collision. It is still to be measured.

- **Pauses.** Every collection is stop-the-world and stops both reactors. The process is paused 7–11% of the time, about 0.9 ms per collection, which matches the p99 gap. No setting in the table moves the collection count by more than 20%. The count follows bytes allocated per request divided by the GC's free headroom.
- **Mark threads.** With parallel marking, druntime starts `threadsPerCPU - 1` mark threads at the first collection: 31 on venus. `core.cpuid` counts the machine's logical CPUs and ignores the affinity mask, so a server pinned to 2 CPUs runs 35 threads. They cost about 1 MB of RSS. Turning parallel marking off is still slower, because roots and heap are then marked on one thread.

### 1.2 The roots every collection scans

A conservative collection reads every registered range word by word, whether or not its pages hold live data.

| root range | size at 2 workers | owner |
|---|---|---|
| engine-web HTTP/1 connection slots (`reserveConnectionSlots`, `GC.addRange` over `cores × maxConnectionsPerCore × 600 B`) | 4.8 MB | web-http |
| program `.data` and `.bss` | 1.3 MB | everyone (static data) |
| reactor `FiberLocal` cells (`cores × fiberPoolSize × fiberLocalWords × 8 B` = 2 × 1,088 × 32 × 8) | 0.56 MB | data-access |
| reactor connection, operation and fiber tables | under 0.5 MB | data-access |
| 2 × 1,088 fiber contexts (only the used part of each stack) | small | data-access |

The connection slots dominate. The benchmark holds 64 connections, but the GC reads all 8,192 slots, about 600,000 words, on every collection. Limiting the table to 128 slots per core measured that cost (same build, with the io_uring fix, 10 s each):

| connection slots per core | peak RSS | collections | total pause | per collection | max pause |
|---|---|---|---|---|---|
| 4,096 (the default) | 22.1 MB | 907 | 0.87 s | 0.96 ms | 5.1 ms |
| 128 | 19.0 MB | 1,126 | 0.44 s | 0.39 ms | 3.6 ms |

The slot range is about 60% of every pause and about 3 MB of peak RSS. There are more collections with 128 slots only because the server serves more requests in the same 10 s. The fix keeps the 4,096-connection capacity: register only the chunks of slots a worker has used, in doubling chunks, each with its own base address (section 3, item 2).

### 1.2a What one request allocates

A `GET /greeting?name=Flint` at `08b19d2f` allocates **4,816 GC bytes in 40 allocations**. This is local diagnosis, not evidence: gs-rest-service release, one reactor thread, keep-alive, measured after 2,000 warm-up requests.

- The bytes come from druntime's per-thread counter (`bytesAllocated`), read on every thread before and after 5,000 requests, with the server running under gdb.
- The calls come from callgrind over the same 5,000 requests: every call into an allocation entry point (`gc_malloc`, `_d_allocclass`, `_d_newarray*`, `_d_arrayappend*`, `_d_arraysetlength*`), by caller.
- At the certified 187k requests per second that is about 900 MB/s of garbage. That allocation rate drives the ~90 collections per second.

| owner | call site | allocations per request |
|---|---|---|
| engine-servlet (web-http) | `capture` (request copy: 3 arrays, 1 object) | 4 |
| | `serve` | 2 |
| | `ServletEngineResponse.getOutputStream`, `write` | 2 |
| | request `fields`, `getParameterValues` | 2 |
| | `Attribute[]` and `Parameter[]` growth (`_d_arraysetlengthT`) | 2 |
| webmvc and web | `DispatcherServlet.handle` | 3 |
| | `getHandlerExecutionChain` and `HandlerExecutionChain(Object, HandlerInterceptor[])` | 2 |
| | `HandlerMethod(HandlerMethod)` (invocable copy) | 1 |
| | mapping: `getMatchingCondition`, `PathContainer.of`, `parsePath`, `PathMatchInfo` | 4 |
| | content negotiation: `resolveMediaTypes`, `determineCompatibleMediaTypes`, `new MediaType`, `setContentType` | 4 |
| | `getMethodArgumentValues`, `doInvoke`, `handleReturnValue` | 3 |
| | `HttpHeaders.put`, `HttpHeaders` entry `dup` | 2 |
| | `create()` | 1 |
| Jackson (third-party-apis) | `createBufferedGenerator` (2 objects, 1 array), `writeStartObject` | 4 |
| application and its AOT handler | `String.format` (`formatJava`: 3 string appends) | 3 |
| | `new Greeting` | 1 |
| **total** | | **40** |

Each change records its allocations and bytes per request here, with the same two probes.

| change | `gc_malloc` per request | instructions per request | reported by |
|---|---|---|---|
| `a5b05c89` (with `8815f2d2`) | 37.0 | 86.1k | web-http |
| `bc808cca`: servlet response body, fields and request head buffered in engine storage; webmvc resolver composite and `getMatchingCondition` copy removed | 31.0 | 83.7k | web-http |

web-http counts only `gc_malloc` calls (callgrind, LDC release build, one reactor). The 40 above also counts array appends, which do not always allocate. The remaining 31 calls by owner:
- Jackson: 4.
- `RequestMappingHandlerAdapter.handle`: 3, which Spring also allocates.
- The servlet engine: 5.
- Spring-side headers, response and handler chain: 5.
- Per-request argument arrays: 2.
- A boxed `PathContainer`: 1.
- Path parsing and content negotiation: 3.
- The generated glue and the app's `Greeting`: 2.

web-http's next candidates are a shared read-only `*/*` list, an unboxed `PathContainer` attribute, and `HttpHeaders`' first-entry allocation.

### 1.3 Peak RSS, by mapping

Peak RSS before and after the io_uring fix (section 3, item 1):

| region | before | after |
|---|---|---|
| GC pools (anonymous: one 7 MB pool fully resident, plus about 3.3 MB of smaller ones) | ~10.6 MB | ~10.6 MB |
| binary `.text` (file-backed, touched pages) | 3.1 MB | 3.1 MB |
| io_uring rings, 2 workers | 3.0 MB | 0.55 MB |
| libc, libm, ld.so, libgcc | 2.5 MB | 2.5 MB |
| binary data, relro and bss | 1.0–1.2 MB | 1.0 MB |
| fiber stack pages (2,208 small mappings) | 1.3 MB | 1.3 MB |
| glibc thread arenas | 1.2 MB | 1.2 MB |
| **total peak** | **24.5 MB** | **21.5 MB** |

Idle after startup, the server holds 14.2 MB, or 11.7 MB after the fix. The roughly 10 MB that load adds is almost all GC heap. The heap grows to absorb allocation between collections, and with a conservative, non-moving collector it does not shrink.

## 2. Options

### A. Settings baked in through `rt_options` (cheap, partial)

`benchmarks/spring/gc-matrix.json` and `tools/spring_gc_matrix.py` already define the matrix. The local sweep above says the settings trade a little RSS against pause and never close either gap. The matrix still has to run on the certified runner, on both gs-rest-service and petclinic-rest, to pick the shipped setting.

The harness cannot read druntime's `profile:1` report today. The Boot server has no signal handler and dies from SIGTERM's default action, so the report is never printed and every run would show no GC data. That is fixed first (section 3, item 3).

### B. Allocate less per request (the largest lever, shared)

At a fixed heap size, collections per second are bytes per second divided by headroom. Halving bytes per request halves both the pause share and the heap growth. Allocation counts per request are tracked with framework-core and web-http (their inboxes, 2026-11-23), and each change records its collections per second here.

### C. Scan less per collection (engine side, ours and web-http's)

- Register only the connection slots in use: a per-worker high-water prefix that grows by doubling. Or keep GC references out of `Connection`, so the range needs no registration at all.
- Size the fiber-local cells by the locals actually declared, instead of 32 words per fiber.
- Keep large static tables out of `.data` and `.bss`, or make them `immutable` where they hold no GC references.

These cut pause per collection without changing the collector.

### D. The agreed fallback: a Flint collector registered through `core.gc.registry`

druntime selects a collector by name: `registerGCFactory("flint", ...)` from a `pragma(crt_constructor)`, and `rt_options = ["gcopt=gc:flint"]`. The collector implements `core.gc.gcinterface.GC`, with `initThread`/`cleanupThread` per thread. Design points:

1. **Per-thread allocation caches.** Each thread keeps a free list per size class and refills it from the shared heap a page at a time. The fast path takes no lock. Today's `gcLock` is a global spinlock on every allocation, so this goes straight at CPU per request.
2. **Pause time needs more than caches.** D emits no write barriers, and changing the compiler is out of bounds ("never change the D language"). A collector that marks while the mutators run therefore needs the OS to track writes:
   - **D2: fork snapshot.** druntime's `fork:1` marks in a forked child. Measure it first. Risks: fork with 35 threads, RSS during copy-on-write, and the child's RSS counting toward the measured process tree.
   - **D3: mostly-concurrent marking with soft-dirty tracking.** Write `4` to `/proc/self/clear_refs`, mark concurrently, stop the world briefly, re-scan the pages whose soft-dirty bit (pagemap bit 55) is set, then sweep. This is Boehm's proven approach (bdwgc's `SOFT_VDB`). The pause becomes the re-scan of the dirty pages, not the whole heap. It is Linux-only; other targets keep stop-the-world.
   - Per-reactor heaps collected independently are ruled out. D lets references cross threads freely (`shared`, `immutable`, caches), so independence cannot be proved without language changes.
3. **Precision.** Use `TypeInfo` pointer bitmaps, as `gc:precise` does, so large pointer-free blocks are never scanned.
4. **Returning memory.** Release free pages with `madvise(MADV_DONTNEED)` after a sweep, so peak RSS follows live data and not the high-water mark.

**Risks and decisions the owner needs to make:**

- **Unsafe code.** A collector is thousands of lines of `@system` code. AGENTS.md confines `@trusted` to allowlisted `sys/` and `ffi/` directories, at most 60 lines per function, with sanitizer and fuzz coverage. The collector needs a home under those rules, likely `flint.arena.sys.gc` or a new package. A new package would change the 37-package surface. The owner and the integration owner decide.
- **Licensing.** Porting druntime's collector (Boost-1.0) or bdwgc's dirty-page tracking (MIT-style) needs an entry in `policy/upstream-licences.json` first. A clean-room collector from the published algorithms needs none.
- **Correctness.** A collector bug is a memory-safety bug in every Flint binary. It needs druntime's GC test suite, a stress fuzzer (random allocation, pinning and threads with a shadow reachability check), ASan and TSan builds, and a conservative-scan fallback switch.
- **Size and budget.** Every app links the collector. Its code and its templates count against the size budgets.

## 3. Plan

1. **Done locally, measured.** The reactor's io_uring submission queue is capped at 256 entries and the completion queue sized separately (`IORING_SETUP_CQSIZE`). That takes 1.27 MB per worker, 2.5 MB at 2 workers (24.5 → 21.5 MB peak locally), with no change to in-flight limits. The C wrapper test covers more operations than the submission queue holds, and the rings' resident size.
2. **Root ranges (C).** Done in `8815f2d2`, agreed with web-http: the HTTP/1 connection slots become GC roots in chunks of 64, 128, 256 … per worker as the reactor first uses them. The reactor hands out the lowest free slot, so a server at 64 connections registers one chunk. Locally the pause per collection fell from 0.96 to 0.64–0.79 ms, with peak RSS unchanged.
   - The rest of the 128-connection gain comes from preallocation sized by the connection limit. The fiber pool is 1,088 fibers per worker: fiber objects, stacks, task and fiber-local arrays. Capping it at 128 per worker saved 1.7 MB of RSS and about 0.1 ms per collection. A fixed cap changes overload behaviour, though: more requests get 503 instead of waiting, as they would in Tomcat's backlog. web-http would accept a `server.flint.max-handlers` setting that keeps today's default, or real backpressure.
   - The reactor's `IoWork` table (120 B × 4,160 per worker) is also scanned on every collection.
3. **GC profile in the harness.** Done: boot's `a5b05c89` adds graceful SIGTERM/SIGINT, so Boot apps exit 0 and print druntime's `profile:1` report. proof-harness released the matrix (`7d18cc86`): `phase1-gc-matrix-1/2/3` for petclinic-rest and `phase1-gc-matrix-gs-rest-1/2/3` for gs-rest-service, at `08b19d2f`, on natural quiet.
4. **Allocation table (B).** Started in section 1.2a: 4,816 bytes and 40 allocations per `/greeting` request at `08b19d2f`. web-http is cutting the servlet adapter, third-party-apis the Jackson copy, and framework-core the MIME-type parsing.
5. **The Flint collector (D).** Approved by the owner (`b515505b`): it lives in `flint.arena.sys.gc` and ports druntime (BSL-1.0) and bdwgc's soft-dirty tracking (Boehm-GC). Both upstreams are in `policy/upstream-licences.json` and NOTICE (`0ae1fabf`).
   - **Step 0, `9bfdd441`.** druntime v2.114.0's conservative collector, ported unchanged and registered as `flint`. `flint.arena.gc` links it, and boot's `c88cf777` links it into every Boot app. `--DRT-gcopt=gc:flint` or `rt_options` selects it; druntime's collector stays the default. arena's test program runs on it, including druntime's own collector unittests.
   - **Step D1a, `c341740f`: per-thread allocation caches.**
     - Small allocations with no attributes, `NO_SCAN`, `APPENDABLE` or both come from a thread-local cache, refilled under the lock with up to 2 KiB of objects of one bin and class at a time.
     - Cached objects are already allocated, and the TLS slots reference them. Every collection scans TLS, so nothing is flushed, a thread stopped mid-pop is safe, and an exiting thread's cache becomes garbage.
     - The fast path writes no shared state.
     - Finalized, aligned and `NO_INTERIOR` objects, the precise collector and `fork:1` keep the locked path.
     - Evidence of correctness:
       - `tests/gc_stress.d`: four threads and 576,000 stamped allocations under repeated collections. A shadow ring and chains of nodes reachable only through it are re-verified every round, and address uniqueness is checked across threads. An injected double-allocation bug crashes it.
       - The `ci.py` sanitize profile: ASan, UBSan and LSan.
       - A ThreadSanitizer lane does not exist yet.
   - **Next, D1b: page release.** Return free pages with `madvise(MADV_DONTNEED)` after a sweep, with hysteresis so that pages reused at once are not released.
   - **Gating.** gc:flint and gc:conservative run on the same binary through proof-harness's queue. D3 (mostly-concurrent marking with soft-dirty tracking) follows only if the pause still loses.

## 4. How p99 and RSS are measured

- **Evidence.** Only proof-harness's queue (`tools/measure_queue.py`) produces evidence. It uses `policy/spring-http-benchmark.json`: 2 server CPUs, 4 load CPUs, 64 connections, a 10 s warm-up, 60 s capacity and fixed-rate phases, 9 trials interleaved with the Go comparator, and a quiet-window check.
  - p99 comes from oha's fixed-rate run (20k req/s for gs-rest-service, 5k for petclinic-rest).
  - Peak RSS is the largest of VmHWM and sampled VmRSS over the whole run, from `/proc/<pid>/status` (`tools/load_bench.py`).
  - A candidate is compared with its base commit under the same toolchain and workload (AGENTS.md). The candidate never replaces its own baseline.
- **GC data per run.** `spring_gc_matrix.py` adds `profile:1` to each setting and reads collections, total pause, max pause, mark and sweep time from the server log. This needs item 3 above.
- **Local diagnosis.** The local probes (the smaps breakdown, and gdb's `gc_profileStats` on a gdb-launched server, since `ptrace_scope=1` forbids attaching) find causes. They are never cited as evidence. They run through `measure_queue.py hold`, on CPUs outside the measurement sets.
