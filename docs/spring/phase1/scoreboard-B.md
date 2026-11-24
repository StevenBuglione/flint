# Phase 1 scoreboard at B (`ca5fbd4a46ed`)

The resume plan's same-commit baseline (section 2), assembled by `spring_bench.py assemble` and scored by `gates.py --gate spring` on 2026-11-24. **The gate fails, as it must:** the PetClinic HTTP part and every GC-matrix part are missing, and the PetClinic parts were measured against the Go comparator from before ADR-032 (re-registered at `f0087ee3`), which the gate now flags. Ratios are Flint / Go, median with the bootstrap 99% interval. A gated ratio passes when its upper bound is at most 0.99 (throughput: its lower bound at least 1.01).

All three applications pass their suites exactly for Java, Go and Flint (18/18, 1/1, 109/109).

## Builds (9 trials per series)

| | gs-rest-service | gs-relational-data-access | petclinic-rest |
|---|---|---|---|
| Primary: cold, platform cache | **1.063** (0.962–1.103) fail | 0.042 pass | 0.261 pass |
| Context: against a deps-primed GOCACHE | – | 1.46 | 1.72 |
| Secondary: scratch (B's older mode) | **0.985** (0.973–1.039) fail | 0.369 pass | **1.417** fail |
| Edit, dev profile | 0.387 pass | 0.765 pass | 0.645 pass |
| Edit, fully static | **1.093** fail | **1.387** fail | **2.53** fail |
| Oz size | 0.625 pass | 0.662 pass | 0.948 pass |

## Runtime (9 interleaved trials)

| | gs-rest-service | petclinic-rest |
|---|---|---|
| Throughput | **1.280** (1.272–1.293) pass the floor, miss the plan's 1.30 | not measured: Flint holds about 1,600 req/s, below the 5,000 req/s warm-up |
| p50 | **1.140** fail | – |
| p99 | 0.826 pass | – |
| Peak RSS | **1.418** fail | – |
| CPU per request | **0.951** (upper 1.029) fail | – |
| 404 path p99 | **5.74** fail (684 against 119 µs) | – |
| Validation-error path p99 | – | **6.07** fail (753 against 124 µs) |

## Non-gating

- release-static-ab: static musl against dynamic glibc, throughput 0.924 and p50 1.109 worse, RSS 0.918 better; the release profile stays dynamic (rule 6ecd8933).

## Bottleneck candidates the baseline shows

- **Build:** the fully static edit build fails on all three apps, link the largest part (m7's per-module archive layout, `c17ea1ba`, measured 0.82x locally for petclinic, waits on `.tools-v4`); gs-rest's primary regressed with the AOT step at 100 of 163 ms (flint-aot); petclinic's scratch build is 4.95 s of platform compile.
- **Runtime:** petclinic's lease convoy (data-access's change 4, then the 5,000 req/s warm-up); the error paths at 32.6 µs (404) and 106 µs (validation) of CPU per request on the servlet path (web-http, boot, third-party-apis); gs-rest RSS (fast-path-pools-ab with the smaps census next) and p50.

Evidence: `benchmarks/spring/evidence/<entry>/<stamp>/`; every certification is in decisions.md.
