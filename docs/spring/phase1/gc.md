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

### 1.2b Per-site targets (the allocation gate, work-queue item 28)

The target for every request is the same: only what user code can see is allocated on the GC heap. For gs-rest-service's `GET /greeting` that is the greeting's content string (the `Greeting` itself is a struct returned by value), so 1–2 allocations. Everything else moves to the request arena or to reused per-fiber or per-connection storage: the servlet adapter, dispatch, content negotiation, path matching and Jackson.

The numbers come from `policy/request-allocations.json`'s test on druntime's collector, at `f11b7e01`. Per-site counts are from the gate's call-site recording over 30 identical requests: the first frame outside druntime and the counter.

| `GET /greeting` site | per request | owner | target |
|---|---|---|---|
| `ServletEngine.serve` (filter chain, response) | 2 | web-http | 0 |
| `ServletEngine.capture` (request head, request object) | 2 | web-http | 0 |
| `ServletEngineResponse.getOutputStream`, `ServletEngineRequest.getHeaders` | 2 | web-http | 0 |
| `RequestMappingHandlerAdapter.handle` (`ServletWebRequest`, `ModelAndViewContainer`, invocable method) | 3 | framework-core | 0 |
| `MediaType.parseMediaTypes`, `determineCompatibleMediaTypes`, `createOutputMessage`, `HttpHeaders.create` | 4 | framework-core | 0 |
| `parsedLookupPath`, `getHandlerExecutionChain` | 2 | framework-core | 0 |
| `InvocableHandlerMethod.getMethodArgumentValues`, `doInvoke`, `RequestParamMethodArgumentResolver.resolveName` | 3 | flint-aot | 0 |
| `Any.of!Greeting` (boxing the return value) | 1 | flint-aot | 0 |
| Jackson (`createBufferedGenerator`, `writeStartObject`) | 0 (was 4) | third-party-apis | 0 |
| `String.format` (the content string) | 1 | the application | 1 |
| **total** | **20** (5,040 bytes) | | **1–2** |

The error paths cost the most and are the furthest from their targets. A JSON 404 costs 77 allocations:
- 14 `HashMap` and 3 `LinkedHashMap` allocations building Boot's error attributes;
- a `ContentNegotiationManager` constructed 4 times per request;
- `RequestMappingInfo.matchProduces` and `getAcceptedMediaTypes`, 4 each;
- `lookupHandlerMethod`, 3.

The 406, 405 and Whitelabel paths (90–119) look similar. Their target is the error body the client sees, the `ProblemDetail` or error map with its strings, at about 5–10 allocations. framework-core owns the negotiation and mapping sites, and boot the error attributes.

petclinic-rest's targets follow once its gate measures it. By the same rule, `GET /owners/1` should allocate only the entities and DTOs it returns, which are user-visible: the owner, pets, types and visits, their lists, and their strings from the database rows.

**petclinic-rest by area** (the gate's call-site counter, each request recorded alone after a warm-up on fresh data, one 404 fence subtracted; local, LDC). `GET /owners/6` cost 1,520 allocations:

| area | allocations | owner |
|---|---|---|
| transaction manager looked up by type on every `@Transactional` call (`getBeanOfType`, through `canonicalTypeName` per bean) | 983 (65%) | data-access (cache), framework-core (by-type lookups) |
| `BeanPropertyRowMapper` built per query; column names lower-cased per row | 143 | data-access |
| engine-jdbc: text copied twice per cell, a cell array per row, metadata per call | 138 | data-access |
| engine-aot descriptors per request (`beanName`, `digits`, `descriptorOf`) | 90 | framework-core |
| media-type matching, `HashMap`, NamedParameter SQL parse, `java.time` text, validation paths, tx synchronizations, Jackson | about 150 | web-http, framework-core, data-access, third-party-apis |
| the entities and DTOs it returns | 16 | the application |

Writes do the transaction-manager lookup twice. Validation compiles and matches its regex with fresh objects (200–373 per write; third-party-apis).

After `7ca27b3b` (Spring's `transactionManagerCache`), `78445f8a` (row mapping without names or maps) and `7404e44b` (engine-jdbc cells), `policy/request-allocations.json` was re-measured at `2637c108`:

| request | before | after |
|---|---|---|
| owner with pets and visits | 1,655 | 446 |
| unknown pet | 1,152 | 163 |
| list owners | 4,401 | 2,920 |
| update owner | 2,973 | 794 |
| add pet to owner | 3,351 | 1,087 |

Next come the plan of attack's 2B data-path items: the parsed-SQL cache, `MapSqlParameterSource` copies, rows in the pooled arena, and `SimpleJdbcInsert` compiled once.

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

### 1.4 Peak RSS at current main, and the levers (local diagnosis, not evidence)

The certified gs-rest-multicore-4 run (`27e8d10b`) put Flint at 22 MB against Go's 13.8, ×1.62, flat while allocation cuts moved CPU and p99. This breakdown is gs-rest-service release at `438bebf6`, on 2 pinned CPUs with 64 connections and 15 s of load: peak 21.7 MB, idle 11.75 MB.

| region | resident at peak | note |
|---|---|---|
| GC pools | ~11.6 MB | druntime reports 12 MB of pools (1 + 4 + 7 MB; the 7 MB pool is fully resident). Live data is small; the heap grows to absorb about 100 collections' worth of allocation per second (1,002 collections in 10 s, 0.54 s of total pause, 3 ms max). |
| binary text and data | 4.3 MB | file-backed: 3.26 MB of `.text` touched, 1 MB of data and relocations |
| libc, libm, ld.so, libgcc | 2.4 MB | file-backed; libc alone is 1.75 MB |
| fiber stacks and guards | ~1.6 MB | 2 × 1,088 preallocated fibers, 2,208 small mappings |
| glibc thread arenas | ~1.2 MB | the touched part of the per-connection request arenas (header, body capacity and write queue, malloc'd) |
| io_uring rings | 0.55 MB | after `9aa14e28` |
| TLS, thread stacks (36 threads, 31 of them GC mark threads) and the rest | ~0.3 MB | |

Levers, each with a local before and after:

| lever | peak RSS | cost | proposal |
|---|---|---|---|
| `rt_options` `incPoolSize:1` (default 3 MB) | 21.6–22.4 → 18.3–19.0 MB (−3 MB) | ~65% more collections (1,615–1,663 against 928–1,002) and ~50% more pause (0.9 s against 0.6 s) | Not yet: it trades p99 for RSS. Collections scale with allocations per request, so retry it when `/greeting` reaches the next trigger (~14). |
| `heapSizeFactor:1.5`; `heapSizeLimit:8M`, `6M` or `4M` | no change | none | No. druntime treats `heapSizeLimit` as best effort, and pools still reach 10–12 MB. |
| `parallel:1` (one mark thread rather than 31) | ~−0.3 MB | pause per collection within noise | Bake it in with any `rt_options` change: a 2-CPU server needs no 31 mark threads. |
| fiber pool sized by `server.flint.max-handlers` (default unchanged) | −1.7 MB at 128 per worker (measured in §3, item 2) | more 503s under bursts at a low setting, so it's opt-in | Proposed to web-http and boot: a setting, today's default. |
| releasing freed pages after a sweep (D1b) | none at steady load: every page is reused within a collection cycle | | Only in gc:flint; not a peak-RSS lever while the heap is fully cycled. |
| fully static link (the musl target, `flint package --target linux-x86_64-musl`; `flint build --static` links the platform archives statically but keeps glibc's libc, libm and libpthread shared, ADR-023) | libc's 1.75 MB of shared text becomes only the functions linked | musl's mallocng replaces glibc malloc for the native libraries and druntime's own pools | **Known part of the gap, pending measurement** (coordinator, 2026-11-23): about 1.75 MB of Flint's peak RSS is shared-library text that Go's fully static binary does not map. Queue entry `release-static-ab` measures it once m7-flint-cli's musl pieces land (musl natives for the rest profile, a packaging test of gs-rest-service and a static Oz option). |

**Is the heap size the allocation rate or druntime's policy?** It's the policy, scaled by the live set. A synthetic program with a fixed live set (local, LDC) ends at the same heap whatever its garbage rate:

| live set | heap | collections at 1.2 / 4.8 KB garbage per request |
|---|---|---|
| 200 KB | 5 MB | 346 / 1,390 |
| 1 MB | 12 MB | 40 / 151 |
| 3 MB | 22 MB | 21 / 74 |

Quadrupling the garbage changed only the collection count. gs-rest-service's live set after a collection is 1.87 MB in a 12 MB heap (measured in-process). Fixed small pools on the real server under load:
- `minPoolSize:1 incPoolSize:0`: heap 6 MB, peak RSS 16.8–17.0 MB;
- `minPoolSize:2 incPoolSize:0` or `minPoolSize:4 incPoolSize:0`: heap 8 MB, peak RSS 17.8–18.1 MB.

Against 21.6–22.0 MB by default, that saves 4–5 MB, more than any single allocation cut. It costs 2–4× the total pause today, because the collection count follows the allocation rate. To stay under Go's 13.8 MB with about 10 MB of non-GC memory, the heap must stay under about 4 MB. That takes small fixed pools plus a live set nearer 1 MB (the floor is about twice the live set) plus allocation cuts deep enough to make the extra collections cheap. Each `rt_options` step goes to proof-harness with its own before and after.

**The live set, by site** (flint.arena's `liveAllocationSites` census, ccea7b1f). Of gs-rest-service's live set, 97% was engine-reactor preallocation: its connection, operation and I/O work tables, FiberLocal cells, and one fiber per connection slot. Other owners' items were about 0.1 MB together; flint-aot's `canonicalTypeName` was the largest, at 70 KB in flight. web-http's handler limit (200, playbook R-19) removed most fibers. `2b2c76bf` then allocates the tables a chunk at a time on first use, off the GC heap (R-20). The live set went from 2,320 to 440 KB, and an idle full collection from 149–158 to 104–108 µs. At 64 connections, peak RSS went from 21.0–21.5 to 19.1–19.6 MB (local, not evidence). The heap under load is still 12 MB: druntime's 1 + 4 + 7 MB pools fill with in-flight garbage before a collection. The small-pool settings above now cost less, because each extra collection marks a fifth of what it used to.

So most of the gap is the GC heap: about 12 MB of pools against Go's whole 13.8 MB process. Smaller pools cost pauses at today's allocation rate. Fewer allocations per request reduce both together, so item 28's cuts lead. `incPoolSize:1` and `parallel:1` follow once `/greeting` is near 14.

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

## 3a. D3: mostly-concurrent marking (design for the prototype)

D3 is the collector step aimed at p99. Today every collection stops both reactors for its whole mark, about 0.5 ms on average and 3–5 ms at most. D3 moves the heap traversal off the pause and keeps only a short stop at the end. This is Boehm's mostly-parallel collection (bdwgc's `SOFT_VDB`). D emits no write barriers, so the kernel tracks the writes instead. On venus, writing `4` to `/proc/self/clear_refs` clears every page's soft-dirty bit, and bit 55 of `/proc/self/pagemap` shows which pages were written since (checked on venus, kernel 7.0).

A collection under `gc:flint` with concurrent marking:
1. **Start (under the GC lock).** Prepare the mark bits as now, clear the soft-dirty bits, and release the lock.
2. **Concurrent mark.** Mutators keep running and allocating. The marker traces from the static data and the registered roots and ranges, over the heap as it finds it. Conservative marking only reads words, so a racing write can at worst leave an object unmarked, which step 3 repairs. While marking, an allocation that would collect or add a pool waits for the marker instead.
3. **Final pause.** Stop the world, as now. Then:
   - scan thread stacks, registers and TLS (the thread caches included);
   - rescan every marked object on a page whose soft-dirty bit is set;
   - mark to closure, and resume.

   A pointer stored during step 2 lies either in a root, which is rescanned, or on a written page, which is also rescanned. So nothing live stays unmarked. An object allocated during step 2 is live only if a root or a written page points to it.
4. **Sweep**, as now.

The final pause costs the roots plus the dirty pages, not the whole heap. At gs-rest-service's ~12 MB heap, a few hundred dirty pages are expected, against ~3,000 in total. The risks are a missed write path (only kernel-recorded writes count, so memory written through `vmsplice`, io_uring buffers or another process is excluded) and pagemap read cost. The evidence is the same as for D1: the stress fuzzer with its shadow check (with collections forced mid-mark), druntime's GC tests, ASan, and a measured pause distribution. It is Linux-only; other targets keep the stop-the-world mark. The switch back is `gc:conservative`, or `gc:flint` without the concurrent option.

**Prototype, 259a864d: built, tested, and slower on gs-rest-service.** `gc:flint-concurrent` (or `flint.arena.gc.setConcurrentMarking`) implements steps 1–4. The concurrent part runs on the collecting thread under the GC lock it already holds: other threads keep running and allocating from their D1 caches, and anything that touches the pools waits. The stress test passes under it, and so does a mover thread that shuttles objects between heap arrays during marking; that test fails 3 of 3 runs with the dirty-page rescan disabled. ASan passes. Local diagnosis, gs-rest-service release, 64 connections, 3 interleaved runs per arm, on a loaded box:

| collector | rps | p99 | pause per collection | max pause |
|---|---|---|---|---|
| `gc:conservative` (druntime) | 179k | 0.91–1.06 ms | 361–380 µs | 1–3 ms |
| `gc:flint` (D1) | 173–189k | 1.09–1.25 ms | 583–643 µs | 1–2 ms |
| `gc:flint-concurrent` (D3) | 137–143k | 2.65–2.75 ms | 1,190–1,300 µs | 4–7 ms |

Why it loses here:
- The live set is now 440 KB (R-20). So the concurrent part saves little: about 0.7 ms of 1.7 ms of marking per collection.
- The stopped part still rescans every range whole. That covers the binary's data and the reactor's chunks.
- At 180k requests/s, most heap pages are written during the concurrent part, so they are rescanned too.
- `clear_refs` write-protects every page each collection. The first write to each page then faults, which costs throughput.
- The concurrent part marks on one thread, where druntime's stopped mark is parallel.

D3 pays off for a large live set with little mutation, which is not gs-rest-service after R-20. It stays opt-in and unmeasured by proof-harness. Before any further D3 work:
- track ranges by soft-dirty too;
- mark the concurrent part in parallel;
- measure petclinic-rest, whose live set is larger.

The lead lever for RSS and pauses is the pool A/B, gc-pools-ab. Separately, `gc:flint`'s stopped mark is about 1.7× druntime's. That is a D1 regression to find before the collector is measured again.

## 3b. Pause levers measured and set aside (m7, 2026-11-25)

These are posidon diagnostics, never evidence. Full notes are in `coordination/notes/m7-gc-mark-census-fork.md`.

**Where a petclinic pause goes.** druntime's stopped mark is about 0.52 ms per collection at O0 and 0.42-0.43 ms at O3. Callgrind of the mark, with per-instruction and cache-simulated dumps, shows:
- Each collection scans about 222K words. Words that are not heap pointers cost about 0.04 ns per byte.
- 96% of the mark's L1 misses are first touches of newly marked objects, about 5.9K per collection at about 50 ns each.
- The live heap is about 7.8K objects. All of it is permanent start-up data; the allocations of 3,000 requests leave 12 KB live.
- So the pause scales with the number of permanent pointer-bearing objects, not with bytes or with requests in flight.

**Set aside, with the numbers:**
- **Trimming class metadata out of the static roots.** One scan of the 529 KB data range costs 21 us, 4.1% of the mark. ClassInfo, `__init` and ModuleInfo together are worth at most 2.2%. ClassInfo's monitor word must stay scanned: `Mutex(Object)` can make it the only reference to a GC Mutex.
- **Prefetch on mark-stack push.** Worth about 4% in `gc:flint` (1.07 to 1.025 ms), because the depth-first mark leaves little lead time. Not worth a druntime rebuild.
- **`gc:flint` against druntime.** On petclinic `gc:flint`'s stopped mark is 2.05x druntime's (1.07 against 0.52 ms per collection), which widens D1's 1.7x regression.
- **`fork:1`.** The heap grows while the child marks: median RSS at the fixed rate rose from 19.4 to 93 MB and kept climbing. The parent's stop p99 went from 0.77 to 10.0 ms, and p99.9 rose 2.7-4.5x.
- **A permanent start-up region**, branch `m7/startup-region-prototype` (f6890435, kept as a record). The main thread's scannable start-up allocations are bump-allocated from root-ranged chunks until `run` returns.
  - It holds 2.66 MB in 14,906 blocks, which is 2.4x the live start-up set. It keeps start-up garbage, scans all of it every collection, and that garbage keeps heap objects alive.
  - Every allocation also passes through the proxy.
  - Petclinic owner 1 at 5,000/s, O3: p99 0.652/0.672 against 0.852 ms, p99.9 0.875/0.859 against 1.053 ms, CPU 81.8 against 84.2 us/req, capacity 24,264 against 22,970/s, peak RSS 18.6 against 19.1 MB. Start-up is 0.027 s either way.
  - A version that keeps only long-lived objects would need either an allocation-site allowlist or copying the survivors out after start-up, and a conservative collector cannot move objects safely.

**What is left:** fewer permanent pointer-bearing objects, family by family (`coordination/notes/permanent-objects.md`), and fewer allocations per request. At O3 the default petclinic's p99 on posidon was 0.652/0.672 ms against Go's 0.687 ms in the same session.

## 3c. Generational GC, slice 0 go/no-go (m7, 2026-11-25)

Slice 0 (6bdd5365) of `gengc-final-plan.md` instruments the collector without changing it. These measurements ran on posidon under `timed`, using the commands in `gengc-slice0-notes.md`. They are diagnostics, never evidence. Each run used one O3 binary per application, built with `-O3`, `-plugin-opt=O3` and `FlintCollector`, and interleaved its arms. Raw logs are in posidon `~/m7-scratch/s0/`.

**Verdict: no-go for slices 1 and 2.** Slice 1 (sticky marking, `gc:flint-sticky-all`) was reviewed in `coordination/notes/gengc-slice1-review-m7.md` and is not landed.

1. **Parity: passes without thread caches.** Each ratio is per collection, against `gc:conservative`, for 3 rounds per application.

   | Arm | petclinic mark | petclinic pause | gs-rest mark | gs-rest pause |
   | --- | --- | --- | --- | --- |
   | `gc:flint-no-cache` | 0.995–1.003 | 0.995–1.003 | 0.972–1.002 | 0.989–1.017 |
   | `gc:flint` (caches on) | 1.074–1.077 | 1.072–1.074 | 1.088–1.116 | 1.085–1.108 |

   Flint's marker matches druntime's at O3. The earlier "2.05x" and "1.7x" figures (section 3b, the D3 notes) came from the O0 link that `elf_lflags` fixed. Each collection marks about 0.42 ms on petclinic and 0.139 ms on gs-rest.

2. **Prediction: fails.** Each estimate is a fraction of the stock stop-the-world pause on the error-path workloads. Slice 2 is shown before enumeration and before the soft-dirty clear.

   | Path | Stock pause | Slice 1 (target ≤ 0.8) | Slice 2 (target ≤ 0.6) | Floor: suspend + resume + roots |
   | --- | --- | --- | --- | --- |
   | `/nope` | 121–123 µs | 1.30–1.35 | 1.05–1.09 | 102 µs (17 + 22 + 63) |
   | petclinic 400 | 277–278 µs | 1.23 | 0.79 | 144 µs (19 + 26 + 99) |

   About 94% of the live heap is permanent. A minor collection therefore saves little tracing and still pays for the roots and for re-scanning old objects. Between collections, 50% (`/nope`) and 38% (petclinic) of scannable old bytes sit on soft-dirty pages. `clear_refs` alone costs about 180 µs per collection in the server process.

3. **Ceiling: passes.** With `gc:flint heapSizeFactor:1000000` there were zero collections in the fixed phase, and Go ran in the same session. Flint's p99 over Go's was 0.897 and 0.877 on `/nope`, and 0.860 and 0.741 on petclinic 400. On both paths the remaining gap to Go is the collector's pause.

4. **Kernel probe: passes on `PAGEMAP_SCAN`.** This is kernel 6.8, at 1,500 pages, median of 9 trials. The ioctl takes 6.7 µs at both 37 and 2,237 VMAs. pread plus enumeration takes 18.5 µs at 37 VMAs (over the 15 µs limit) and 12.7 µs at 2,237. `clear_refs` takes 23 µs at 37 VMAs and 190 µs at 2,237.

**The floor, by part.** Two rounds were run on each error path. The suspend and resume figures come from an `LD_PRELOAD` shim that timestamps druntime's `pthread_kill`, `sem_wait`, `sem_post` and `sigsuspend` on real `gc:conservative` collections. The root figures come from timed re-scans in the predictor (slice 0 build plus a local patch). The scripts are in posidon `~/m7-scratch` (`stw_probe.c`, `stw-analyze.py`, `anatomy-patch.py`).

- **Threads.** The server has 5 threads on 2 CPUs: main (in `nanosleep`), one thread blocked in `poll`, one in a futex wait, and 2 reactors in `io_uring` wait. A collection runs on a reactor and signals the other 4. Three of those 4 are idle threads, not reactors.
- **Suspend** takes 16 µs at p50 on `/nope` and 18 µs on petclinic.
  - The loop that sends the 4 signals takes 11.8 and 15.6 µs: each `tgkill` costs 3–4 µs in the sender, because the kernel wakes the target inside the call.
  - Delivery, from kill to the handler's acknowledgement, takes 4–7 µs at p50.
- **Resume.**
  - The send loop takes 12–17 µs, again 4 `tgkill`s.
  - Reactors are running again 4–10 µs after their signal at p50.
  - Idle threads wake 1–3.5 ms late at p99, because 5 threads share 2 CPUs.
- **Roots** take 59 µs on `/nope` and 94 µs on petclinic.

  | Source | `/nope` | petclinic |
  | --- | --- | --- |
  | Static data (`.data`+`.bss`, one range) | 24.6 µs, 273 KiB | 47.7 µs, 506 KiB |
  | Thread stacks (5 live extents) | 12.8 µs, 98 KiB | 18.2 µs, 140 KiB |
  | Other registered ranges | 10.0 µs, 95 KiB | 12.9 µs, 127 KiB |
  | TLS (5 threads) | 7.7 µs, 79 KiB | 12.5 µs, 129 KiB |
  | Fiber stacks | 7.4 µs | 9.8 µs |
  | `roots[]` | 0 | 0 |

  There are 200 parked fiber contexts of about 170 bytes each. Only about 2 change between collections.

The cheapest lever is to stop signalling the 3 idle threads. They could park in a known blocking state with their registers saved, or detach if they hold no GC pointers. That saves about 20 of the 39 µs spent on suspend and resume. Next in size are the static-data range and the thread stacks plus TLS.

**D1 open issue: thread-cache retention.** With caches on, `gc:flint` spends 7–11% more mark time per collection than the same binary without them. The suspected cause is not yet confirmed: slots parked in a thread's cache look allocated, so the mark scans their stale words and keeps whatever those words reach. Testing it means counting the bytes scanned through cached slots, and clearing or `NO_SCAN`-marking slots when they enter a cache. This is not on the critical path, because the generational baseline runs without caches.

## 4. How p99 and RSS are measured

- **Evidence.** Only proof-harness's queue (`tools/measure_queue.py`) produces evidence. It uses `policy/spring-http-benchmark.json`: 2 server CPUs, 4 load CPUs, 64 connections, a 10 s warm-up, 60 s capacity and fixed-rate phases, 9 trials interleaved with the Go comparator, and a quiet-window check.
  - p99 comes from oha's fixed-rate run (20k req/s for gs-rest-service, 5k for petclinic-rest).
  - Peak RSS is the largest of VmHWM and sampled VmRSS over the whole run, from `/proc/<pid>/status` (`tools/load_bench.py`).
  - A candidate is compared with its base commit under the same toolchain and workload (AGENTS.md). The candidate never replaces its own baseline.
- **GC data per run.** `spring_gc_matrix.py` adds `profile:1` to each setting and reads collections, total pause, max pause, mark and sweep time from the server log. This needs item 3 above.
- **Local diagnosis.** The local probes (the smaps breakdown, and gdb's `gc_profileStats` on a gdb-launched server, since `ptrace_scope=1` forbids attaching) find causes. They are never cited as evidence. They run through `measure_queue.py hold`, on CPUs outside the measurement sets.

### Slice 0 diagnostics

Build the release app under the runner’s measurement lock with
`python3 "$FLINT_HOME/tools/measure_queue.py" hold -- flint build --profile release -- -d-version=FlintCollector`
from the app directory, with `FLINT_HOME` set to the checkout root.
Run that binary with `"--DRT-gcopt=gc:flint-predict profile:1"` to print cumulative
phase times, the second root scan, the address-ordered live-object scan and the
soft-dirty census. `flint.arena.gc.pauseProfile()` returns the same totals in-process.
Use successive snapshots to isolate a phase. The first collection establishes the
process-wide soft-dirty baseline. The exit report counts only complete census intervals.
Use `gc:flint`, `gc:flint-no-cache` and `gc:conservative` for latency comparisons.
The predictor performs additional work while the mutators are stopped.

On Linux, with the runner's measurement lock and pinned toolchain exported, run:

```sh
python3 tools/measure_queue.py hold -- ldc2 -O3 -preview=dip1000 -d-version=FlintSoftDirtyProbe \
  packages/arena/tests/softdirty_probe.d -of=/tmp/flint-softdirty-probe
python3 tools/measure_queue.py hold -- /tmp/flint-softdirty-probe --self-test
```

For posidon measurements use the [slice 0 runbook](gengc-slice0-notes.md).
