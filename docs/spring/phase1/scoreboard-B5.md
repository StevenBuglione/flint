# Phase 1 scoreboard at B5 (`8ed3de37dc57`)

B5 is the fifth same-commit baseline (named 11:45Z on 2026-11-25 as fp main when scoreboard-B4 landed; coordinator 11:55Z). It was assembled by `spring_bench.py assemble` and scored by `gates.py --gate spring` with main's tools. Every gated part ran interleaved with Go from the start, while the owner decides on Flint-only (`benchmarks/spring/baselines/README.md`). Every part has no foreign activity and strict served compiles (0 refused).

**Both error paths are deferred to B6. The gate fails closed** on them (their newest certified runs are B4's, a different commit) and on the GC-matrix parts, which move to B6.

- **validation p99, deferred to B6:** the harness rule ae7858f8 lands after B5's tree.
  - B5's run was refused because its capacity phase saturated oha's 4 CPUs (a connection per request at 55.8k req/s).
  - The owner chose to record capacity on the error paths as context. A harness exception was declined, so the one-commit rule stays.
- **404 p99, deferred to B6:** B5's run (`20261125T143428Z`) is **void**.
  - An unheld `dub build :tx` (data-access, CPUs 0–3, about 14:59:30–15:00:50Z) overlapped Flint trial 5's fixed-rate and capacity phases (coordinator 15:12Z).
  - Neither freeze-strays, which never freezes compilers, nor the 10 s busy sampler (0 foreign samples) caught it. The run is marked `VOID.json`, which assembly skips.

Ratios are Flint / Go, median with the bootstrap 99% interval, over 9 trials. A gated ratio passes when its upper bound is at most 0.99, or for throughput when its lower bound is at least 1.01. All three applications pass their suites for Java and Flint (`exact`) and Go (`parity`): 18/18, 1/1, 109/109. Go is the ADR-033 comparator with Tomcat's keep-alive limit (`8d29301a`).

## Builds (all 15 gated metrics pass)

| | gs-rest-service | gs-relational-data-access | petclinic-rest |
|---|---|---|---|
| Primary: cold, platform cache | 0.522 pass | 0.019 pass | 0.198 pass |
| Context: against a deps-primed GOCACHE | – | 0.653 | 1.21 |
| Secondary: strict scratch | 0.277 pass | 0.114 pass | 0.493 pass |
| Edit, dev profile | 0.326 pass | 0.549 pass | 0.543 pass |
| Edit, fully static | 0.588 pass | 0.782 pass | 0.709 pass |
| Oz size | **0.549** pass (0.624 at B4) | **0.627** pass (0.668) | **0.889** pass (0.935) |

The sizes are the ThinLTO O3 fix (dd774a24): B4's trees were codegenned at O0.

## Runtime (9 interleaved trials)

| | gs-rest-service | petclinic-rest | At B4 (gs-rest / petclinic) |
|---|---|---|---|
| Throughput | **1.861** (1.851–1.875) pass | **1.613** (1.608–1.621) pass | 1.451 / 1.416 |
| p50 | **0.679** pass (43 against 63 µs) | **0.830** pass (198 against 238 µs) | 0.809 / 1.048 |
| p99 | **0.397** pass (114 against 288 µs) | **0.899** pass (525 against 584 µs) | 0.481 / 1.133 |
| Peak RSS | **0.673** pass | **0.700** pass | 0.736 / 0.754 |
| CPU per request | **0.564** pass (4.90 against 8.69 µs) | **0.824** pass (53.6 against 65.1 µs) | 0.718 / 1.044 |
| p99.9 (reported) | 0.81 | 1.04 | |
| 404 path p99 | deferred to B6 (B4: 1.80) | – | |
| Validation-error path p99 | – | deferred to B6 (B4: 1.81) | |

**Every gated build and HTTP runtime metric of both applications passes at B5.** What remains for Phase 1:
- the two error-path p99 targets, at B6;
- the GC matrix, at B6, the first tree with heapSizeFactor:3.

## The miss the checks did not see

The 404's contamination came from a compile on the benchmark's own server CPUs (2–3, inside taskset 0–3) that the window's checks treated as non-foreign. The likely path is a served DMD compile whose compile-server process runs from the measured tree. proof-harness will tighten the sampler; until then, every session's builds on venus must run under `hold`.

Evidence: `benchmarks/spring/evidence/<entry>/<stamp>/`; every certification is in decisions.md.
