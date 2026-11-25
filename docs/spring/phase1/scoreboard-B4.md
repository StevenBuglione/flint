# Phase 1 scoreboard at B4 (`fb4c73d1adc7`)

B4 is the coordinator's fourth same-commit baseline (named 05:45Z on 2026-11-25, decisions.md f345940e). It was assembled by `spring_bench.py assemble` and scored by `gates.py --gate spring` on 2026-11-25 with main's tools. B4's Go acceptance rows are in the `parity` wire mode that main's gate requires.

Every part is at the one commit, with no foreign activity in any window and strict served compiles (0 refused). **The gate fails, as it must:**
- the GC-matrix parts are missing (natural quiet; `phase1-gc-matrix-3` began at 11:48Z);
- five runtime metrics fail.

Ratios are Flint / Go, median with the bootstrap 99% interval, over 9 trials. A gated ratio passes when its upper bound is at most 0.99, or for throughput when its lower bound is at least 1.01.

All three applications pass their suites for Java and Flint (`exact`) and for Go (`parity`): 18/18, 1/1, 109/109.

**The comparator changed at B4.** B4 is the first baseline against the Go comparators of ADR-033, registered at `8d29301a`:
- HTTP parity on every gated path: the golden's reason phrase, framing and connection lifetime;
- Tomcat's 100-request keep-alive limit, on both sides.

The error paths are the most affected: Go now closes after the validation 400, as Java and Flint do. B3's numbers were measured against the earlier comparator, so the B3 column is context, not a like-for-like change.

The runtime parts were planned Flint-only against the `-3` Go records. Both HTTP parts failed a drift guard, by 0.6% (petclinic) and 0.5–1.5% (gs-rest), and were measured again interleaved. The two error paths ran interleaved from the start (coordinator). See `benchmarks/spring/baselines/README.md` for the guard and the fallback rate.

## Builds (all 15 gated metrics pass)

| | gs-rest-service | gs-relational-data-access | petclinic-rest |
|---|---|---|---|
| Primary: cold, platform cache | 0.530 pass | 0.020 pass | 0.214 pass |
| Context: against a deps-primed GOCACHE | – | 0.682 | 1.27 |
| Secondary: strict scratch | 0.277 pass | 0.120 pass | 0.490 pass |
| Edit, dev profile | 0.368 pass | 0.526 pass | 0.578 pass |
| Edit, fully static | 0.600 pass | 0.773 pass | 0.770 pass |
| Oz size | 0.624 pass | 0.668 pass | 0.935 pass |

## Runtime (9 interleaved trials)

| | gs-rest-service | petclinic-rest | At B3 (gs-rest / petclinic) |
|---|---|---|---|
| Throughput | **1.451** (1.437–1.469) pass | **1.416** (1.407–1.423) pass | 1.488 / 1.132 |
| p50 | **0.809** pass (51 against 63 µs) | **1.048** fail (250 against 238 µs) | 1.319 / 1.478 |
| p99 | **0.481** pass (136 against 283 µs) | **1.133** fail (668 against 590 µs) | 0.842 / 1.445 |
| Peak RSS | **0.736** pass | **0.754** pass | 0.772 / 0.793 |
| CPU per request | **0.718** pass (6.20 against 8.63 µs) | **1.044** fail (68.2 against 65.3 µs) | 1.006 / 1.331 |
| p99.9 (reported) | 0.69 | 1.42 | |
| 404 path p99 | **1.80** fail (236 against 131 µs) | – | 2.98 |
| Validation-error path p99 | – | **1.81** fail (389 against 215 µs) | 3.23 |

**gs-rest passes every gated runtime metric for the first time.**

## What B4 shows

- **gs-rest is done on runtime.** It passes throughput, p50, p99, RSS and CPU.
- **petclinic is close.** p50 is 5% from Go and CPU 4%; p99 is 13%. posidon's diagnostics locate the work:
  - **CPU:** the Spring layers between the mapped floor and ordinary Flint cost about 41 µs, while Flint's transport and libpq floor are below Go's (`evidence/floor-reference/posidon-20261125T070834Z`).
  - **p99:** collections. Pool size does not move it (`evidence/gc-pools-petclinic/posidon-20261125T075609Z`). heapSizeFactor 3 gives −7% p99 at 0.88× Go RSS, and factor 8 breaks the RSS gate (`evidence/gc-heap-size-factor/posidon-20261125T082533Z`). Both choices are the owner's.
- **The error paths remain about 1.8×.**
  - About half of the old validation gap was transport, now equal on both sides. What remains is Flint's: CPU 1.41× on the validation path and 1.55× on the 404.
  - The 404 shortcut (engine and Boot halves) is not yet active at B4.

Evidence: `benchmarks/spring/evidence/<entry>/<stamp>/`; every certification is in decisions.md.
