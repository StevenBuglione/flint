# Per-request instructions and allocations: `tools/spring_instr.py`

The development loop for request-path work (decisions.md, 715a7c62): judge a change by deterministic per-request
counts, not timed load. Certified numbers come only from the named baselines.

```
python3 tools/spring_instr.py --list
python3 tools/spring_instr.py gs-rest-service greeting
python3 tools/spring_instr.py petclinic-rest owner --json owner.json
python3 tools/spring_instr.py petclinic-rest validation-error --binary build/spring/petclinic-rest-flint
```

**Requests.** The four benchmarked requests come from `policy/spring-http-benchmark.json` and
`policy/spring-error-paths-benchmark.json`: `greeting` and `not-found` (alias `nope`) on gs-rest-service, `owner`
(owner 1) and `validation-error` (alias `invalid-post`) on petclinic-rest. Each uses its manifest's method, path,
headers and body, and the first response must have the expected status.

**Binary.** It is built as the HTTP benchmark builds it (`spring_bench.py` `build_flint`, the release profile, copied
to `build/spring/<app>-flint`), unless `--binary` names one. Build the base commit and the candidate, then compare
the two reports.

**Instructions.** The server runs under callgrind with one reactor (`SERVER_FLINT_THREADS=1`). After `--warmup`
requests (default 1,000) over one keep-alive connection the counters are zeroed, `--requests` more (default 2,000)
are measured, and the counters are dumped. Each function's own instructions go to a layer by its module:
engine-reactor, engine-web, engine-servlet, llhttp (with engine-web's C relay), webmvc (`flint.web`, `flint.http`),
jackson, jdbc (`flint.jdbc`, `flint.engine.jdbc`), engine-sql, libpq, aot, boot, security, tx, validation, java,
spring-core, conc, arena, druntime-gc, druntime, phobos, libc, app and other. The layers add up to the total. The
report also lists the 25 functions with the most own instructions.

**Allocations.** `flint.arena`'s counting proxy, through Flint Boot's `FLINT_ALLOCATION_REPORT=<file>`: Boot installs
the counter before any thread starts and writes `<allocations> <bytes>` when `main` returns. The bytes are the
collector's block sizes. Two runs without callgrind, of `--warmup` requests and of `--warmup` plus `--requests`
requests, each ended by SIGTERM; their difference over `--requests` is the per-request figure. The callgrind dump's
count of GC allocation calls (druntime's `ConservativeGC` malloc, qalloc and calloc) is reported beside it as a
cross-check. A binary built before `FLINT_ALLOCATION_REPORT` reports allocations as unavailable.

**Isolation.** The tool reruns itself under `measure_queue.py hold`, using the queue's lock (found among this
repository's worktrees when `FLINT_MEASURE_LOCK` is unset). It pins the server, client and PostgreSQL to the three
highest CPUs, above the benchmark's 2-9. PostgreSQL runs directly from the pinned peer, not through `pg_ctl`, so it
stays in the step's process group. Every process it starts is stopped before it exits, on every path.

**Not timing.** Instruction counts leave out cache misses, syscalls, kernel time and waits. A change that moves work
into the kernel or onto another thread can look cheaper than it is. Callgrind charges each GC collection to whichever
allocation triggers it, so inclusive figures for allocating sites include a share of collection cost.
