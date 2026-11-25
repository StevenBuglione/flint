# petclinic GC pool sizes on posidon at B4 (diagnostic, never evidence)

Requested by the coordinator at 07:58Z on 2026-11-25. web-http's preliminary trace found that owner requests at or above p99 overlap a collection 91% of the time, against 2.5% overall. The question for the owner: does a larger fixed pool help?

- **Run:** posidon at B4 `fb4c73d1`, after web-http's clean rerun. Each step ran in its own `measure_queue.py timed` window on posidon's host-wide lock, with the freeze-strays sweep. 14 and 3 processes were frozen, all continued; none is left stopped.
- **Arms:** `--DRT-gcopt=minPoolSize:N incPoolSize:0 profile:1` with N = 1, 2 and 4 MiB, and the default mark threads.
- **Step 1:** `spring_bench.py gc-matrix petclinic-rest --runs 2 --no-go --smaps`, 07:56–08:09Z. Two trials per arm, each with the manifest's 60 s at the fixed 5,000/s and 60 s at capacity. Collections, pauses, mark and sweep come from druntime's exit profile.
- **Step 2:** `gc_pauses.py`, 08:10–08:11Z. 20 s at 5,000/s per arm, with the server under `strace -f --seccomp-bpf -e trace=tgkill`. Each collection's stop-the-world pause runs from its first suspend `tgkill` to its last resume `tgkill`; the sweep after the resume is not included. strace's latency is reported for context only.

| | 1 MiB (owner's default) | 2 MiB | 4 MiB |
|---|---|---|---|
| p50 / p99 / p99.9 at 5,000/s (ms) | 0.410 / 0.858 / 1.19 | 0.413 / 0.880 / 1.26 | 0.412 / 0.885 / 1.24 |
| p99 at capacity (ms) | 4.58 | 4.61 | 4.59 |
| App CPU at 5,000/s (µs/req) | 113.5 | 114.0 | 114.4 |
| Capacity (req/s) | 17,425 | 17,557 | 17,446 |
| Peak RSS (MB) | 19.5 | 21.1 | 19.7 |
| Median RSS at 5,000/s (MB, smaps every 15 s) | 18.5 | 19.0 | 18.7 |
| Collections per 1,000 requests (druntime, whole trial) | 2.40 | 1.86 | 1.68 |
| Mean pause (druntime: total ÷ collections) | 0.56 ms | 0.60 ms | 0.58 ms |
| Mark share of pause time | 93% | 92% | 91% |
| **Stop-the-world pause p50 / p90 / p99 / max (ms, census)** | 0.455 / 0.497 / 0.573 / 0.77 | 0.468 / 0.533 / 0.625 / 8.64 | 0.499 / 0.557 / 9.10 / 9.16 |
| Census collections per 1,000 requests | 2.47 | 3.27 | 1.44 |

druntime's `max_pause_ms` has 1 ms resolution, so it shows 0–3. The census gives the distribution.

## Reading

- **A larger pool cuts collections by up to about 30% (2.40 to 1.68 per 1,000 requests), but not the pause.** Each stop-the-world pause stays about 0.45–0.50 ms, almost all of it marking. p99 does not move (0.858, 0.880 and 0.885 ms), nor do CPU, capacity or RSS.
- **Consistent with web-http's finding.** At 5,000/s a collection comes about every 80–120 ms, and a request that overlaps a ~0.46 ms pause gains up to that much. That is about 1% of requests, which is the p99 tail. Fewer collections only thin that tail slightly.
- **Outliers.** 2 and 4 MiB each showed rare 8–9 ms pauses in the census (pools4's p99 is 9.1 ms from a handful of its 144 collections); 1 MiB showed none. These are single 20 s runs under strace, so they are a lead only.
- **The levers for petclinic's p99 are the pause length and the allocation rate, not the pool size:**
  - mark work: roots, and the heap scanned on each collection;
  - fewer allocations per request: about 107 at B4;
  - a forked or concurrent mark (the GC matrix's `*-fork` settings), which takes marking out of the stop-the-world window.

Any change to the 1 MiB default is the owner's decision (decisions.md). These numbers do not support a larger pool.

posidon's absolute values differ from venus's. Compare the arms with each other.
