# Phase 1 scoreboard at B3 (`d6d15b0073dd`)

B3 is the coordinator's third same-commit baseline (named 19:04Z on 2026-11-24, decisions.md). It was assembled by `spring_bench.py assemble` and scored by `gates.py --gate spring` on 2026-11-25 with **B3's own tools**, from a worktree at `d6d15b0073dd`. Main's tools now require the Go comparators' `parity` wire mode (ADR-033), and B3's Go acceptance ran in `semantic` mode.

Every part is at the one commit, with no foreign activity in any window and strict served compiles (0 refused). **The gate fails, as it must:**
- the GC-matrix parts are missing; they run on natural quiet;
- seven runtime metrics fail.

Ratios are Flint / Go, median with the bootstrap 99% interval, over 9 trials. A gated ratio passes when its upper bound is at most 0.99, or for throughput when its lower bound is at least 1.01.

All three applications pass their suites exactly for Java, Go and Flint (18/18, 1/1, 109/109).

**B3 is the last baseline against the pre-ADR-033 Go comparators.** The owner extended HTTP parity to every gated path (118b4482, 081851b0). The comparators now match the golden's reason phrase, framing and connection lifetime, and were re-registered at `075b4715`. Every runtime part is remeasured against them at B4. The error paths are the most affected: at B3, Go kept every connection where Flint, like Tomcat, closes after the validation 400.

## Builds (all 15 gated metrics pass)

| | gs-rest-service | gs-relational-data-access | petclinic-rest |
|---|---|---|---|
| Primary: cold, platform cache | 0.554 pass | 0.020 pass | 0.207 pass |
| Context: against a deps-primed GOCACHE | – | 0.688 | 1.27 |
| Secondary: strict scratch | 0.280 pass | 0.121 pass | 0.473 pass |
| Edit, dev profile | 0.355 pass | 0.541 pass | 0.584 pass |
| Edit, fully static | 0.596 pass | 0.803 pass | 0.774 pass |
| Oz size | 0.618 pass | 0.662 pass | 0.925 pass |

At B the primary, secondary and fully static edit metrics failed (1.063, 0.985, 1.093 for gs-rest; 2.53 static edit for petclinic).

## Runtime (9 interleaved trials)

| | gs-rest-service | petclinic-rest | At B2 (gs-rest / petclinic) |
|---|---|---|---|
| Throughput | **1.488** (1.475–1.507) pass | **1.132** (1.090–1.143) pass | 1.323 / 0.933 |
| p50 | **1.319** fail (79 against 60 µs) | **1.478** fail (351 against 238 µs) | 1.297 / 2.008 |
| p99 | 0.842 pass | **1.445** fail (839 against 581 µs) | 0.851 / 1.858 |
| Peak RSS | 0.772 pass | 0.793 pass | 0.944 / 0.818 |
| CPU per request | **1.006** (upper 1.087) fail | **1.331** fail (84.2 against 63.2 µs) | 1.053 / 1.578 |
| p99.9 (reported) | 1.13 | 1.96 | |
| 404 path p99 | **2.98** fail (340 against 114 µs) | – | 6.04 |
| Validation-error path p99 | – | **3.23** fail (383 against 119 µs) | 3.995 |

Petclinic's throughput passes for the first time. Go's throughput side is unchanged by ADR-033 on gs-rest's `/greeting`, which already matched. On petclinic's owner GET it gains chunked framing.

## What B3 shows

- **Builds are done:** every gated build metric of the three applications passes. The fully static edit link, the largest B gap, passes everywhere.
- **Runtime remains:**
  - p50 and CPU per request on both applications;
  - petclinic's p99;
  - the error paths' p99. Their remaining tail has no single demonstrated cause; see `error-paths-astra.md` and web-mvc's `coordination/error-404-tail.md`.

  The validation path's capacity ratio (0.227) includes Flint's reconnect after every 400, which the old comparator never paid. B4's parity comparator pays it too, and `transport-pricing` measures the price.

Evidence: `benchmarks/spring/evidence/<entry>/<stamp>/`; every certification is in decisions.md.
