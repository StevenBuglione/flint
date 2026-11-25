# Final plan: low-pause collector for Flint (Fable review, 2026-11-25)

Supersedes the slice plans in `gengc-design.md` (Astra) and `gengc-review-neon.md` (Gemini 4 Neon) where they differ. Read-only review by Claude Fable 5.2; nothing was built or measured. Section 9 still describes slice 0/1 work as in flight, but that run was stopped before it changed any file.

**Verdict.** Build a **stopped, non-moving, two-generation collector inside the existing `collector.d` port, with one sticky mark bit, and with minors that do not promote**. "Old" is whatever the last full collection marked. A minor traces only objects allocated since then, starting from the roots plus the old objects. First build it with *every* old scannable object rescanned in address order (no kernel dependency; removes the ~50 ns first-touch per object that dominates today's mark). Then add cumulative soft-dirty filtering (cleared only at full collections, before the stop) so only written old pages are rescanned. I expect ordinary minors of **60–90 µs on `/nope` and 60–130 µs on the petclinic 400**, against 130–150 and about 300 µs today. That is not "tens of µs" at the pessimistic end, because suspension and root scanning form a 30–60 µs floor no generational design removes. **Confidence that this alone beats Go's error-path p99: about 55% for the 404 and 55–60% for the 400**; about 70–75% for both when combined with the already-approved exchange pooling and an idle-time collection trigger (slice 6). All of this is reasoning from the notes and the code, not measurement. **Top three changes from Neon's plan:** (1) non-promoting minors on *cumulative* soft-dirty replace Boehm-style promote-everything plus per-minor `PAGEMAP_SCAN`/`UFFD_WP_ASYNC` re-arming, which removes premature tenuring of in-flight request objects and the userfaultfd permission dependency; (2) a kernel-free "scan all old, sequentially" minor lands first and stays as the portable fallback and the verifier's reference; (3) slice 0 becomes a go/no-go measurement: the D1 2× regression is very probably the ThinLTO-O0 link bug, and a diagnostic pass predicts the minor pause and the GC-free p99 ceiling before any collector work. Two hazards neither document names are also closed: soft-dirty poisoning by VMA merges, and an external `clear_refs`.

Citations: Flint paths are relative to the repo at `fp/main` a028a3ef (`collector.d` is unchanged since 259a864d, so line numbers also match the `agy-plan` checkout). `gc.d`, `osthread.d`, `threadbase.d` are the pinned druntime under `/home/olfa/flint-work/vibe/flint/.tools/dmd2/src/druntime/src/`. bdwgc is `/home/olfa/flint-work/reference/bdwgc` at ef728c0.

---

## 1. Corrections to the design and to the review

**C1. The D1 "1.7–2.05× slower mark" is most likely a build artifact, not a collector defect.** Not yet re-measured; the evidence is the timeline.
- Until a8dc0aea (2026-11-25 10:40Z) every release link passed `-plugin-opt=O0`, so all Flint bitcode was code-generated unoptimised (`policy/profiles.toml:23-30`, `:75-78`).
- `gc:flint` is Flint bitcode. `gc:conservative` lives in the prebuilt, optimised `libdruntime-ldc.a`: the release profile passes no `-defaultlib=…-lto` (`policy/profiles.toml:75`).
- The 1.7× was measured on 2026-11-23 (`docs/spring/phase1/gc.md:296-316`). The 2.05× compares 1.07 ms against druntime's **0.52 ms, which gc.md itself labels the O0 number** (`gc.md:322`, `:331`).
- The arithmetic fits: 222K scanned words at O0 instead of O3 add roughly 0.3–0.5 ms; the 5.9K first-touch misses do not change.
- If a gap survives at O3, check in this order:
  1. the thread caches: about 14 KB of extra TLS per thread is scanned, and every cached scannable object is marked (`collector.d:196-227`, `:693-719`);
  2. the port is druntime 2.114.0 (`collector.d:2`) while the LDC benchmark binary's stock collector is LDC 1.43's druntime 2.113 (`.tools/ldc2-1.43.0-linux-x86_64/lib/libdruntime-ldc-shared.so.113`): diff against LDC's own `gc.d`, not dmd2's;
  3. `GCBits.set/test` are non-template functions of `core.internal.gc.bits`, so check by disassembly that they inline into `mark`.
- Also note: a release app does not contain the collector unless the profile adds `-version=FlintCollector` (`collector.d:26-29`, `packages/arena/dub.sdl:18`). Every measurement build must add it, and its size counts against the Oz gates.

**C2. Neon §1.1 overstates the free-slot issue.** Stock already treats free slots as marked: `prepare()` copies `freebits` into `mark` (`gc.d:2828-2836`; port `collector.d:3105-3117`), and `mark()` relies on it (`gc.d:2644`). `isMarked` needs no change. The real requirement is to maintain "free ⇒ mark" when `prepare()` is skipped, at five sites (slice 1).

**C3. Promote-every-survivor (Astra §B.2, Neon §1.9) is the wrong policy for these heaps.**
- Collections are allocation-triggered, so each lands mid-burst: 6.4 requests overlap each `/nope` collection (4.3% of requests at 67 collections/s, `coordination/notes/web-http-tail-join.md:117`).
- Every in-flight object would be tenured at every minor and become garbage only a full collection frees.
- With Neon's nursery-only pages, each survivor also retires its 4 KiB page until the next full. That forces frequent fulls, and every full is a full-length pause.
- Boehm accepts this with a full every 19 partials (`alloc.c:141-149`, `:569-583`). With a tiny young live set, not promoting is strictly better: survivors are simply re-traced by the next minor.

**C4. `PAGEMAP_SCAN` + `UFFD_FEATURE_WP_ASYNC` should not be the primary backend.**
- bdwgc has no such code to adapt: its `UFFDWP_VDB` is the synchronous mode with a monitor thread (`os_dep.c:4640-4760`).
- This host has `vm.unprivileged_userfaultfd = 0` (read from `/proc/sys`), so userfaultfd needs `UFFD_USER_MODE_ONLY`. Whether async write-protect then tracks kernel-mode writes is unverified.
- Non-promoting minors need no per-minor reset at all, so the reason for uffd disappears.
- `PAGEMAP_SCAN` stays, but only as a read-only, faster enumerator of `PAGE_IS_SOFT_DIRTY` (`/usr/include/linux/fs.h:305-315`, kernel 6.7+, present on 6.8 and 7.0). Soft-dirty needs no privilege: `/proc/self/pagemap` and `clear_refs` are owner-accessible and `CONFIG_MEM_SOFT_DIRTY=y` here.

**C5. Missed by both: soft-dirty is per-VMA as well as per-PTE.** The kernel marks every new *or expanded* VMA soft-dirty, and pagemap then reports every page of it dirty until the next `clear_refs` (kernel `Documentation/admin-guide/mm/soft-dirty.rst`, last section). Pools are plain adjacent 1 MiB `os_mem_map` mappings (`collector.d:4358`, `fixed_pools.d:20`), which merge. The first pool added after a clear would make every old page read dirty. This costs speed, never safety. Fix: isolate each pool mapping with `PROT_NONE` guard pages, and detect the degraded state (slice 2).

**C6. Missed by both: soft-dirty state is process-wide and anyone can clear it.** A profiler, CRIU, or another library writing to `clear_refs` between collections would erase the remembered set and free live objects. Fix: a canary page (slice 2).

**C7. D3's stopped part is not a guide to dirty-scan cost.** It reads pagemap for *every* pool page and tests three bitmaps per slot inside the pause (`collector.d:3222-3233`, `:3246-3252`). The plan enumerates only spans holding old scannable objects and walks bitmap words (adapt `GC_push_marked1`, bdwgc `mark.c:2007`).

**C8. Pause accounting.**
- druntime's pause runs from before `thread_suspendAll` to after `thread_resumeAll` (`gc.d:3419-3432`; port `collector.d:3704`, `:3824-3837`).
- Suspension signals every attached thread, then waits on a semaphore once per thread (`osthread.d:1470-1506`). Resume only signals (`threadbase.d:1096-1101`).
- Sweep runs after resume but under `gcLock`, so the other reactor blocks at its next allocation. The effective pause on allocating paths therefore includes sweep, and neither document prices it. Slice 0 measures it.

**C9. Kernel writers: Astra's and Neon's concern is valid in general but not live in this engine.**
- The reactor's receives use ordinary user buffers with a 64-bit token (`packages/engine-reactor/native/ffi/flint_reactor_uring.c:153-165`). I found no registered or fixed buffers.
- Rings are `SINGLE_ISSUER | DEFER_TASKRUN` (`flint_reactor_uring.c:55-61`), so completions are copied in the issuer's own context through the page tables. That sets soft-dirty, and cannot happen while the issuer is suspended.
- Connection chunks are `malloc` + `GC.addRange` (`packages/engine-reactor/source/flint/engine/reactor/sys/chunks.d:69-76`): roots, always scanned.
- Rule to record in the playbook: kernel-written memory is `NO_SCAN` or off-heap; never register scannable GC memory as a fixed buffer.

**C10. Agreed with Neon, kept:**
- no second 6,000-line copy;
- a single mark bit;
- single-threaded minors;
- hooks for attribute changes and large-block growth;
- thread caches off in generational mode;
- B before BDWGC;
- the init-time kernel probe;
- the checksum verifier;
- dirty filtering of static roots as a later slice.

---

## 2. The design

### 2.1 State and invariants

Epoch **E** is the moment `clear_refs` is written for the latest full collection.

- **M1 (free implies marked).** For every small slot, `freebits ⇒ mark`. Between collections, *old* = allocated ∧ marked and *young* = allocated ∧ ¬marked. Large blocks: young ⇔ `pagetable[pn] == B_PAGE` ∧ ¬`mark[pn]`.
- **M2 (old set is frozen between fulls).** A minor never sets a mark bit that survives it, and never frees a marked object. Only a full collection or an explicit `GC.free` changes the old set.
- **M3 (remembered set).** A word of an old scannable object, or of a filtered static range, that refers to a young object lies on a page written since E, or on a force-dirty page.
  - Proof sketch: at E the full mark scanned that word and marked its target. A target slot that was *free* at E can only be reached by a false or dangling pointer, which the program may not dereference, so not retaining the later occupant is legal.
- **M4.** Stacks, registers, TLS, fiber contexts, `addRoot` values and non-ELF `addRange` memory are scanned whole in every minor.
- **M5 (tracker health).** The canary page written right after each clear reads dirty. If it does not, the minor is converted to a full collection inside the same stop.

Soundness of a minor: by M3 and M4 the start set reaches every live young object. By M1 a zero mark bit means "young, not yet visited". Everything unmarked on a young page is dead.

### 2.2 Routes by which an old object can come to refer to a young one

| Route | Handling |
|---|---|
| Mutator store, including into TLS-cached or interior words | Write fault sets soft-dirty (M3). Slice 1 needs nothing: all old is scanned. |
| Synchronous kernel write (`read`, `recv`, pipe hand-off of a pointer) | `copy_to_user` faults through the PTE, so it is tracked. Slice 2 tests it. |
| io_uring completion | Tracked (C9). Fixed buffers, O_DIRECT or DMA into scannable memory are prohibited. |
| `clrAttr`/`setAttr`/in-place `realloc` changing `NO_SCAN` on an old block | Hook sets `oldScan` and `forceDirty` for its pages. |
| `extend` or in-place large `realloc` | Old large blocks are enumerated from their *current* `bPageOffsets` extent at minor time, so new tail pages are covered. |
| Array append | Small: a new block (young). Large: `extend`, above. |
| `GC.free` of an old object, then reuse | The slot keeps mark = 1 while free (M1); allocation clears it. A dangling old word is not a reference. |
| Finalizers (run after resume, under the lock) | Stores are ordinary tracked writes. Resurrection is already undefined in D. |
| Thread caches (D1) | Off in generational mode. Re-enabling needs Boehm's free-list unmarking (`alloc.c:1184`, `:1254`). |
| Roots, ranges, fibers, TLS | M4. Only ELF data segments are ever dirty-filtered (slice 3). |
| External `clear_refs`, fork, missing `/proc` | M5 canary; the existing atfork reopen (`collector.d:3943-3975`) plus a poison flag; fall back to slice 1's scan-all-old. |
| Precise mode, `fork:1` | Generational mode refuses them, as the thread caches already do (`collector.d:364-366`). |

### 2.3 Why this beats the alternatives for these heaps

- **Boehm-style promote-all with per-minor reset** (Neon; also "BDWGC with `GC_TIME_UNLIMITED`"): premature tenuring (C3), a per-minor reset cost, uffd permissions or a process-wide `clear_refs` per minor. D3 showed what per-collection `clear_refs` costs (`gc.md:304-309`).
- **Permanent space after start-up, write-protected:** the non-moving form of this *is* the plan, with old = marked at E and sealed pages. `mprotect` + SIGSEGV tracking is rejected: kernel writes into a protected page fail with `EFAULT` instead of faulting. Copying into a region is impossible conservatively, and the bump-region prototype kept 2.4× garbage (`gc.md:333-337`).
- **Concurrent or incremental marking:** needs a reset per cycle, and the mark it would move off the pause is the part minors skip anyway. D3 lost for the same structural reasons.
- **Concurrent or lazy sweeping:** useful only if slice 0 shows the post-resume lock hold is material. Then adapt Boehm's on-demand reclaim. Not on the critical path.
- **Card-marking only pointer-bearing old pages:** included as the per-page `oldScan` bitmap.
- **Idle-time triggering:** not a collector design, but probably the cheapest tail lever. It reduces how many requests a pause hits rather than its length (slice 6).

---

## 3. Pause budget (estimates, to be replaced by slice 0's numbers)

| Component | `/nope` | petclinic 400 | Basis |
|---|---:|---:|---|
| Suspend + resume, ~5 threads on 2 CPUs | 15–35 µs | 15–35 µs | estimate from `osthread.d:1470-1506`; unmeasured |
| Stacks, 205 contexts, TLS | 8–20 | 12–25 | 75–172 KB at 0.04 ns/B plus ~200 scattered touches (`web-http-tail-join.md:59-62`) |
| `addRange` chunks | 4 | 6 | 107–140 KB |
| Static data, whole (filtered in slice 3) | 11 (≈4) | 21 (≈6) | 279–526 KB; 21 µs measured for 529 KB (`m7-gc-mark-census-fork.md:9`) |
| Slice 1: all old scannable, in address order | 25–40 | 95–125 | 1.13 MB streams in ~45 µs (`m7-gc-mark-census-fork.md:32`) plus ~10.6K heap-pointer rejections at 5–8 ns |
| Slice 2 instead: enumerate + rescan written old pages | 5–15 | 15–45 | ~650 old pages on petclinic; per-page cost is the probe's job |
| Young trace (cache-warm) | 3–10 | 5–15 | in-flight objects only |
| **Slice 1 total** | **65–120** | **155–225** | stock: 130–150 / ~300 |
| **Slice 2 total (slice 3 filter)** | **45–95 (40–85)** | **75–145 (60–130)** | |

- **The D1 regression** is a blocker only if it survives at O3. Slice 0 settles that first.
- **Biggest remaining risk to pause length:** the floor (suspend, resume, 205 fiber contexts), which is already half of a `/nope` minor. Mitigations, in order:
  1. measure it (slice 0);
  2. static-root filtering (slice 3);
  3. the reactor owner creates pool fibers lazily, so fewer contexts are registered (`createFiber`, `packages/engine-reactor/source/flint/engine/reactor/sys/fibers.d:86-95`);
  4. the idle trigger (slice 6);
  5. parking threads in GC-safe regions needs druntime changes: owner decision, out of scope.
- **Second risk:** the written-old set is larger than expected, for example Spring caches or AAs mutated per request on dense start-up pages. Slice 0's census measures it. The mitigation is page sealing, and the fallback is slice 1's cost.
- **Static roots:** filter them, but last. It saves ~7–15 µs and is sound by M3 for ELF data only.
- **Nursery-only pages:** not as a blanket rule. Seal pages holding old *scannable* objects. Pages whose old objects are all `NO_SCAN` stay allocatable, because dirtying them costs nothing.
- **Triggers:** minors fire at today's allocation-pressure sites. Fulls follow section 4, slice 3.

---

## 4. Slice plan

All code is in `packages/arena/source/flint/arena/sys/gc/` (`@system`, allowlisted). New names register beside `flint` (`collector.d:258-264`). `gc:conservative` and `gc:flint` must behave exactly as before in every slice. Tests switch modes at run time through a new `flint.arena.gc.setGenerational(mode)`, modelled on `setConcurrentMarking` (`collector.d:288-306`).

### Slice 0: measure before building (go/no-go)

**Code**
- `collector.d`: phase timers around suspend, mark, resume, sweep, and total lock hold, in `fullcollect` (`:3769-3866`). Expose them through a `flint.arena.gc.pauseProfile()` struct and the exit report.
- A diagnostic factory, **`gc:flint-predict`**. After each normal full mark, still stopped, it times:
  - (a) a second `markAll` pass, where everything is already marked, so it costs exactly a minor's root scan;
  - (b) one address-ordered pass over every marked scannable object: slice 1's old scan;
  - (c) a soft-dirty census: clear at each collection, then at the next collection count the pages that hold marked scannable objects and are dirty, and the objects and bytes on them.

  Diagnostics lengthen the pause; never use this name for latency numbers.
- `packages/arena/tests/softdirty_probe.d`, a standalone program. For 2–20 MiB of mappings, with and without 2,200 extra small VMAs, it times:
  - `pread` of pagemap;
  - `PAGEMAP_SCAN` with `category_mask = return_mask = PAGE_IS_SOFT_DIRTY`;
  - one `clear_refs` write.

  It also demonstrates C5 (map, clear, map an adjacent region, read: the first region reads dirty) and checks that a `read()` from a pipe into a clean page sets its bit.

**Measurements (m7 runs them on posidon; Astra only builds and self-tests)**
1. Parity at O3: `gc:flint`, with thread caches on and off, against `gc:conservative`, same binary, both apps. Pass: mark time and pause within ±5%.
2. Prediction: suspend + (a) + resume, plus (b), plus the census, per workload. Pass: predicted slice 1 minor ≤ 0.8× stock pause and predicted slice 2 minor ≤ 0.6× stock, on both error paths.
3. Ceiling: each error path with collections suppressed during the fixed phase (a large `heapSizeFactor`; diagnostic only, RSS ignored), Go in the same session. Pass: Flint p99 ≤ 0.9× Go's. If this fails, no collector can pass the gate alone; report to the owner and prioritise request-path CPU.
4. Probe: enumeration ≤ 15 µs for 1,500 pages, `clear_refs` ≤ 500 µs with the server's VMA count.

If item 2 or 3 fails, stop and escalate; do not build slices 1–3.

### Slice 1: `gc:flint-sticky-all` and `gc:flint-sticky-all-verify`

Non-promoting minors that rescan all old scannable objects. No kernel dependency.

**Data**
- Per pool: a `youngPage` bitmap (1 bit per page; 32 B per 1 MiB pool) and an `oldScan` bitmap (32 B).
- Per collector: `youngLog`, an `os_mem_map`-backed growable array of (pool, bit index) pairs. Start at 64 KiB and grow by doubling, exactly like `ToScanStack` (`collector.d:2731-2810`). Never `malloc` inside the stop: a suspended thread may hold the allocator lock.
- Counters: minors since full, young bytes retained, old scannable bytes.

**M1 maintenance (the five sites)**
1. `smallAlloc` at `L_hasBin` (`:2487-2498`) and `takeSmall` (`:2692-2698`): `pool.mark.clear(biti)`.
2. `SmallObjectPool.allocPage` (`:5232-5261`): set the page's mark words to all ones, and set `youngPage`.
3. `freeNoSync` (`:1247-1254`): `pool.mark.set(biti)`.
4. `sweep` (`:3358-3472`): `markdata[w] |= toFree[w]` wherever `freePageBits` runs.
5. `bigAlloc` (`:2578-2581`): `pool.mark.clear(pn)`.

Also set `youngPage` in `recoverPage` (`:3492`), and in `freeNoSync` when it pushes a slot to a bucket.

**Full collection**
1. Stock `prepare`, mark (parallel as today), sweep.
2. Inside sweep, rebuild `oldScan` per page from `mark & ~freebits & ~noscan`, clear `youngPage`, and record old scannable bytes.

**Minor collection** (new `minorcollect`, sharing the locks, suspend, resume and timers of `fullcollect`)
1. Suspend. Skip `prepare`.
2. Old scan: for each small pool and each `oldScan` page, walk `mark & ~freebits & ~noscan` by words, coalesce adjacent objects into one range, and call the minor mark function. For large pools, scan each `B_PAGE` block with mark set and noscan clear, over its current extent. Adapt `GC_push_marked1` (`mark.c:2007`) and `GC_push_marked` (`mark.c:2167`).
3. Roots: `markAll` (`:3120-3147`) with the minor mark function.
4. The minor mark function is `mark` (`:2839`) instantiated with a new `minor` template parameter. The only difference: when `testAndSet` newly sets a bit, append to `youngLog` (before the `noscan` test, so pointer-free survivors are logged too). The full-collection instantiation is byte-identical to today.
5. `thread_processTLSGCData(&clearBlkCacheData)` (`:3824`), then resume.
6. Sweep only `youngPage` pages of small pools, and all blocks of large pools, with the stock per-page code. Fully dead pages become `B_FREE` and lose `youngPage`. Others go on the recover chain. Do not reinitialise `recoverPageFirst` for pages not swept (`:3346`).
7. Clear the mark bit of every `youngLog` entry and empty the log. This is the non-promotion step, behind a `promote` knob (default never) so promote-all can be A/B-measured.
8. `bucket[] = null` and reset the recover pools, as stock (`:3859-3861`).

**Trigger.** Wherever `fullcollect(false, false)` is called for allocation pressure (`:2475-2477` and the `bigAlloc` equivalent): run a minor unless 32 minors have passed since the last full, or young bytes retained after the last minor exceed max(256 KiB, old scannable bytes ÷ 4). `GC.collect`, low memory, the out-of-memory path (`:2466-2471`) and termination stay full.

**Verifier (`-verify` names; details in section 5).** Full-mark oracle before sweep, plus post-sweep invariants.

**Tests** (extend `packages/arena/tests/gc_stress.d`; LDC and DMD):
- seeded graph fuzzing with stamped identities, under forced minors;
- old-to-young stores across pages;
- interior and one-past-the-end slices;
- `GC.free` + reuse + array-capacity cache;
- parked fibers and fiber-only roots;
- register-only and TLS-only roots;
- finalizers on young and old objects, including cycles;
- thread exit;
- large young objects and large old arrays receiving young pointers;
- `extend` of an old large array, then a store into the new tail.

**Fault injection (each must make the verifier fail):**
- skip one `oldScan` page in step 2;
- skip one fiber context in step 3;
- in step 2, use each old large block's extent as recorded at E instead of its current one.

A mutated run that passes is a test failure.

**Gate.** Zero verifier discrepancies; minor pause p50 on posidon within 15% of slice 0's prediction; `/greeting` throughput, CPU per request and peak RSS within 2% of `gc:flint`; application test suites pass under the `-verify` name.

### Slice 2: `gc:flint-sticky` and `gc:flint-sticky-verify`

The cumulative soft-dirty remembered set.

**Kernel layer** (`softdirty.d`, extended)
- Init probe: the write/clear/write check the unittest already performs (`softdirty.d:94-118`), run at collector start. Adapt `detect_soft_dirty_supported` (`os_dep.c:4335-4367`). On failure the collector runs as slice 1.
- Enumeration: `PAGEMAP_SCAN` with the soft-dirty category when the ioctl exists, looping until `walk_end` reaches the end. Otherwise buffered `pread` with a 16 KiB buffer mapped at init. Adapt `pagemap_buffered_read` (`os_dep.c:4416-4475`) and `soft_set_grungy_pages` (`os_dep.c:4478`). One call per pool, over the span from its first to its last `oldScan` page, ANDed with `oldScan` in user space.
- Pool mapping: in generational mode replace `os_mem_map(poolsize)` (`collector.d:4358`) with a mapping of `poolsize + 2 pages` at `PROT_NONE`, the inner part made read-write, and `MADV_NOHUGEPAGE`. Unmap the whole range in the pool destructor. This prevents the merges of C5.
- Canary: one private page, written immediately after every `clear_refs`.

**Epoch**
1. At a full collection, write `clear_refs` *before* `thread_suspendAll`, under the GC lock. This is safe: later writes are recorded, and the mark that follows sees the final state.
2. Write the canary.
3. Suspend and mark as usual.

**Minor**, replacing slice 1's step 2:
1. Enumerate dirty bits for `oldScan` spans and old large blocks' current extents.
2. Read the canary last. If it is clean, or any read was short or refused, run `prepare` and a full mark in this same stop, and set the tracker to poisoned until the next successful clear.
3. If more than half of the `oldScan` pages read dirty (C5's signature), schedule a full collection next and count the event.
4. Rescan the old objects on pages that are dirty or `forceDirty`.

**Sealing**
- In the full sweep, a small page with at least one old scannable object gets `sealed` (a third 32 B bitmap) and is *not* put on the recover chain (`:3470-3472`). The threshold is a constant, to be tuned.
- `freeNoSync` does not push slots of sealed pages to buckets (`:1247-1252`).
- Sealed holes are recovered only by a later full collection that finds the page without old scannable objects.

**Hooks**
- `Pool.clrBits` and `setBits` (`:4513`, `:4536`), and the in-place `realloc` attribute change (`:1036-1039`): when the block is old and `NO_SCAN` changes, set `oldScan` and a per-pool `forceDirty` bit for its pages.

**Verifier additions:** the differential check and page checksums (section 5).

**Tests, added to slice 1's:**
- a pointer to a young object written into an old object by `read()` from a pipe, with every other reference dropped;
- `clrAttr(NO_SCAN)` on an old block after storing a young pointer;
- a pool added between collections (minors must stay minors, with no spike in dirty pages);
- a fork without exec.

**Fault injection (verifier must fail, or the collector must escalate as stated):**
- drop the one dirty page holding the only old-to-young edge: fail;
- skip the attribute hook: fail;
- write `4` to `clear_refs` from the test between two minors: the canary must convert the next minor to a full, with no discrepancy;
- skip the canary check under that same injection: fail.

**Gate.** Zero discrepancies across the stress suite (at least 200 seeds per compiler), both applications' test suites and a 30-minute posidon soak, all under `-verify`. Then, without verify: minor pause p50 ≤ 90 µs on `/nope` and ≤ 130 µs on the invalid POST, and at least 25% below slice 1 on petclinic; dirty old pages per minor stable across the full interval; peak RSS within +1.0 MB of stock.

### Slice 3: triggers, static-root filter, telemetry

- **Static roots.** Tag ranges that lie inside a writable ELF `PT_LOAD` segment (`data_roots.d:79-118` already walks the headers). Enumerate their dirty bits with the pools and scan only written pages. Adapt `GC_push_conditional_static` (`mark.c:1711-1736`). Other `addRange` memory stays unconditional. The checksum verifier covers these pages too. Gate: at least 5 µs off the petclinic minor, zero discrepancies.
- **Full-collection triggers,** replacing slice 1's fixed count:
  - 64 minors since the last full;
  - retained young bytes above the slice 1 bound;
  - minor work (rescanned + young traced bytes) above half of the last full's scanned bytes, twice running;
  - tracker poisoned;
  - old growth, as in `GC_finish_collection` (`alloc.c:1386-1392`).

  Compare with MMTk's `requires_full_heap_collection` (`src/plan/generational/global.rs:158`) and `should_next_gc_be_full_heap` (`:263`).
- **Telemetry in the exit report:** minor and full counts, pause percentiles for each, dirty and old pages, young survivors, canary conversions, lock hold after resume.
- **Gate.** Interleaved posidon diagnostics against stock and Go on `/nope`, the invalid POST, owner and `/greeting`: fulls ≤ 5% of collections at steady state; p99 and p99.9 no worse than stock on any workload; the tail join shows the share of ≥p99 requests overlapping a collection falling.

### Slice 4 (only if slice 0 or 3 shows the need)

- Lazy sweep of young pages on allocation, if post-resume lock hold exceeds 20 µs.
- Thread caches compatible with minors: caches moved out of TLS into collector-owned blocks, cached slots protected during the minor and unmarked afterwards. Adapt `GC_mark_thread_local_fls_for` (`thread_local_alloc.c:342`) and `GC_clear_fl_marks` (`alloc.c:1184`).

### Slice 5: certification

The quiet interleaved venus run on each error path, then every B6-gated runtime and build metric with the collector linked.

### Slice 6 (parallel, optional, other owners): idle-time trigger

- `flint.arena.gc.collectIfDue(fraction)` runs a minor when allocation since the last collection exceeds `fraction` of the trigger.
- The reactor calls it when its loop is about to block with no handler in flight on any worker (the wait at `flint_reactor_uring.c:229-246`).
- Collections then fall in the gaps between bursts instead of inside them. Today each one hits about 6 requests.
- It is honest only if disclosed: the benefit depends on arrival gaps. It needs the engine-reactor owner and an owner decision, and its own A/B run.

---

## 5. Verifier

All verifier memory is `os_mem_map`'d and is not a root.

1. **Full-mark oracle (slices 1–3).**
   - After the minor mark, still stopped, copy every pool's mark bitmap aside (8 KiB per 1 MiB small pool).
   - Run stock `prepare` + `markAll`.
   - Any allocated slot marked by the full pass but not by the minor is a live object the minor would free. Record the pool, slot, and the first referring word found by a reverse scan, then abort.
   - Slots the minor marked and the full pass did not are counted (floating old garbage, conservative nepotism).
   - Restore the minor's bitmaps.
   - Fault injection applies only to the minor's walk, so a root omitted by injection is caught. A bug in druntime's own root enumeration is shared with stock and is out of scope.
2. **Differential (slice 2 on).** Run the old scan twice into separate bitmaps, once filtered and once over all old pages. The newly marked sets must be identical. A difference names the page whose dirty bit was missed.
3. **Checksums (slice 2 on).** At E, store a 64-bit checksum of every `oldScan` page and every filtered static page. At each minor, every page the kernel reports clean must still match. A mismatch is a write the kernel did not report, whether or not it stored a young pointer. Adapt `GC_update_check_page` and `GC_check_dirty` (`checksums.c:104-182`).
4. **Post-sweep invariants:**
   - M1 on every small page;
   - `youngLog` empty and no logged slot still marked;
   - every bucket entry is a free slot on an unsealed page;
   - no array-capacity cache entry refers to a freed block;
   - `oldScan` covers every old scannable object;
   - large-pool marks only at `B_PAGE` starts.

---

## 6. Build and test procedure on this machine

From the dedicated worktree (`/home/olfa/flint-work/worktrees/gengc`, branch `gengc-astra`), never committing:

```
export FLINT_MEASURE_LOCK=/home/olfa/flint-work/flint/.claude/worktrees/jolly-mendeleev-ea37ba/.flint/measure/MEASURING
export PATH=$PWD/.tools/ldc2-1.43.0-linux-x86_64/bin:$PWD/.tools/dmd2/linux/bin64:$PATH
python3 tools/measure_queue.py hold -- dub test :arena --compiler=ldc2
python3 tools/measure_queue.py hold -- dub test :arena --compiler=dmd
python3 tools/measure_queue.py hold -- python3 tools/gates.py --package arena --gate structural
```

- Every compile, test and probe run goes through `hold`. Never wrap `hold` in `timeout`. Gate commits on the test's own exit status, not on a pipe.
- No servers, benchmarks or network from the implementing agent. m7 runs posidon diagnostics through `measure_queue.py timed`.
- The stress tests run once per mode in the one test binary through `setGenerational`; the verify modes are the default in tests.
- The sanitize profile (ASan + UBSan) must pass with the new stack-scanning instantiation carrying the same `@scansStacks` exemption as `mark` (`collector.d:2838`).

---

## 7. Risks

1. **The floor makes minors too long for the 404** (section 3). Slice 0 prices it; slice 6 and lazy fiber creation address it.
2. **The non-GC tail already exceeds Go's p99.** Slice 0 item 3 detects it before any collector work.
3. **An unreported write.** Covered by the init probe, the canary, the checksum verifier in CI and soak, and the scan-all-old fallback. The residual risk is a kernel regression on a deployment kernel that the soak never ran on.
4. **Soft-dirty is process-wide.** `clear_refs` at each full collection write-protects every page of the process, costing one minor fault per page written afterwards. Expect about 1,000 faults per full interval; the probe measures the write itself. Other soft-dirty users in the same process are disturbed; document it.
5. **Sealing costs RSS.** Holes in start-up pages become unusable: up to ~1.5 MB on petclinic, where start-up allocates 2.4× its live set (`gc.md:334`). The slice 2 gate bounds it; the sealing threshold tunes it.
6. **Long-lived young growth** (a warming cache) is re-traced by every minor until a full promotes it. The retained-bytes trigger bounds this; the worst case degrades to stock behaviour.
7. **Finalization delay.** Objects that survived a full are finalized only by a later full.
8. **Shared collector file.** Every edit to hot paths (`smallAlloc`, `mark`) must leave `gc:flint` unchanged. Slice 0's parity run is repeated after slices 1 and 2.

---

## 8. Success criteria for proposing the default, and rollback

Propose `gc:flint-sticky` as Boot's default only when all hold:

1. Zero verifier discrepancies in the stress suite on LDC and DMD, both applications' full test suites, the sanitizer lane, and a 30-minute soak per error path, all under `gc:flint-sticky-verify`.
2. On venus, quiet and interleaved: the paired upper 99% bound of Flint ÷ Go is below 0.99 for `error-404-p99` and `error-validation-p99`.
3. Every other B6-gated metric still passes with the collector linked: throughput, p50, p99, peak RSS and CPU per request on both applications, and all build and size metrics.
4. p99.9 and maximum pause are no worse than stock on any gated workload. Full collections are at most 5% of collections at steady state.
5. The allocation gates pass on LDC and DMD for both applications.
6. Fallbacks are demonstrated: without `/proc` the collector runs as slice 1; an injected `clear_refs` converts to a full collection.

**Rollback.** The default is one `rt_options` entry prepended at start-up, like `fixed_pools.d:42-50`. `--DRT-gcopt=gc:conservative`, or an application's own `rt_options`, overrides it at process start with no rebuild. Reverting the default is a one-line commit. Until criterion 2 passes, nothing changes for any shipped binary: the collector stays behind `-version=FlintCollector` and its opt-in names.

---

## 9. Delta for the Slice 0/1 work already in flight

Astra's current brief (`coordination/astra-gengc-impl-brief.md`) follows Neon's section 5.

**Keep:** phase timers, the kernel probe, M1, single-threaded minors, the hooks, buffered pagemap reading, the full-mark oracle, checksums, the stress-test list.

**Change:**
- Do not promote at minors. Add the `youngLog` and the unmark step.
- Do not clear soft-dirty per minor and do not build the uffd backend. Clear once per full collection, before the stop.
- Land scan-all-old first, under its own registry names.
- Seal by old-scannable content rather than making all old pages non-allocatable.
- Add the pool guard pages, the canary, and `gc:flint-predict`.
- Treat the O3 parity re-measurement as the first act of slice 0, before any search for a code-level cause.
