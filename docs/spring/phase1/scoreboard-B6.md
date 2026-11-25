# Phase 1 scoreboard at B6 (`be86e77f7651`)

B6 is the sixth same-commit baseline: fp main when scoreboard-B5 landed (15:20Z on 2026-11-25). It is the first tree with heapSizeFactor:3, the error-path client-limit rule (owner ae7858f8), S5 live, and the byte and flattening cuts. It was assembled by `spring_bench.py assemble` and scored by `gates.py --gate spring` with main's tools. Every gated part ran interleaved with Go. Go is the ADR-033 comparator with Tomcat's keep-alive limit (`8d29301a`).

**Every gated part measured at B6 passes. The gate fails closed only on what was not measured here:**
- **The 404 is deferred to B7** by owner schedule change (20:15Z). B6's first 404 run is void: an unheld `gates.py` structural audit overlapped Flint trial 3's gated phase. Its re-run was abandoned before claim and superseded by B7. Assembly therefore resolves the 404 to B4's run, a different commit.
- **The GC-matrix parts** move to B7.

The window checks were tightened at B6 after two misses; every gated part below ran under the tightened checks:
- **Sampler:** sees short-lived build processes and project tools.
- **Freezer:** stops compilers and busy project tools outside `hold`, with a live parent-chain walk, own-session protection and a 250 ms second sighting.
- **Voided runs** are marked with `VOID.json`.

Ratios are Flint / Go, median with the bootstrap 99% interval, over 9 trials. A gated ratio passes when its upper bound is at most 0.99, or for throughput when its lower bound is at least 1.01. All three applications pass their suites for Java and Flint (`exact`) and Go (`parity`): 18/18, 1/1, 109/109.

## Builds (all 15 gated metrics pass)

| | gs-rest-service | gs-relational-data-access | petclinic-rest |
|---|---|---|---|
| Primary: cold, platform cache | 0.499 pass | 0.019 pass | 0.193 pass |
| Context: against a deps-primed GOCACHE | – | 0.632 | 1.19 |
| Secondary: strict scratch | 0.278 pass | 0.116 pass | 0.475 pass |
| Edit, dev profile | 0.337 pass | 0.519 pass | 0.540 pass |
| Edit, fully static | 0.591 pass | 0.749 pass | 0.700 pass |
| Oz size | 0.549 pass | 0.626 pass | 0.889 pass |

## Runtime (9 interleaved trials)

| | gs-rest-service | petclinic-rest | At B5 (gs-rest / petclinic) |
|---|---|---|---|
| Throughput | **1.846** pass | **1.649** pass | 1.861 / 1.613 |
| p50 | **0.683** pass | **0.823** pass | 0.679 / 0.830 |
| p99 | **0.384** pass | **0.828** pass | 0.397 / 0.899 |
| Peak RSS | **0.758** pass | **0.740** pass | 0.673 / 0.700 |
| CPU per request | **0.568** pass | **0.809** pass | 0.564 / 0.824 |
| p99.9 (reported) | 0.77 | 0.99 | |
| Validation-error path p99 | – | **0.896** (0.862–0.932) **pass** | deferred at B5; 1.81 at B4 |
| 404 path p99 | deferred to B7 (B4: 1.80) | – | |

The validation path's capacity phase was client-limited on Flint's side in all 9 trials. It is recorded as context (ae7858f8); Flint's capacity ratio of 1.488 is a lower bound.

heapSizeFactor:3 shows as expected: petclinic p99 improves from 0.899 to 0.828, and RSS rises from 0.67–0.70 to 0.74–0.76, still well under 1.

**What remains for Phase 1's gate:** the 404 p99, measured first at B7 with flint-aot's template 404, and the GC matrix at B7.

Evidence: `benchmarks/spring/evidence/<entry>/<stamp>/`; every certification is in decisions.md.
