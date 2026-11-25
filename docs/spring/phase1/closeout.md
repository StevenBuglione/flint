# Phase 1 close-out (2026-11-25)

The owner closed Phase 1 at 23:50Z on 2026-11-25 (decisions.md, the entry after 087f28a3). This page says what Phase 1 proved, on what evidence, and what it left open.

## The claim

**Flint's port of three Spring applications passed every gated build and runtime metric against Go at a certified same-commit baseline,** with responses byte-identical to Java Spring Boot v4.2.0. The applications are gs-rest-service, gs-relational-data-access and spring-petclinic-rest.
- **Runtime parts** are certified at B7 (`43db0cae`), except gs-rest's runtime, which is certified at B6 (`be86e77f`).
- **All 15 build metrics** are certified at B6.

The original exit rule asked for every part at one commit. The owner waived it when B7's last four parts were still queued (gs-rest HTTP, builds ×3): each had passed by wide margins at B5 and B6, and certifying them again would have cost another 1.5 hours of venus. So the claim is per part, at the baseline named, not at a single commit.

All three applications pass their side-by-side suites for Java and Flint (`exact`) and Go (`parity`): 18/18, 1/1 and 109/109.

## Final certified numbers

Flint / Go, median of 9 interleaved trials. A part passes when its 99% bootstrap interval is entirely past 0.99, or past 1.01 for throughput.

### Runtime

| | gs-rest-service (B6) | petclinic-rest (B7) | 404 path (B7) | Validation 400 path (B7) |
|---|---|---|---|---|
| Throughput | 1.846 | 1.662 | context: 2.046 | context: 1.612, a lower bound |
| p50 | 0.683 | 0.820 | context: 0.679 | context: 0.703 |
| p99 | 0.384 | 0.812 | **0.558** (77 against 139 µs) | **0.810** (173 against 213 µs) |
| Peak RSS | 0.758 | 0.758 | 0.64 | 0.75 |
| CPU per request | 0.568 | 0.810 | 0.527 | 0.728 |
| p99.9 (reported) | 0.77 | 1.115 | 2.01 | 1.045 |

Bold marks the gated metric on the error paths, where the other rows are context.

### Builds (B6, all pass)

| | gs-rest-service | gs-relational-data-access | petclinic-rest |
|---|---|---|---|
| Cold, platform cache (primary) | 0.499 | 0.019 | 0.193 |
| Strict scratch (secondary) | 0.278 | 0.116 | 0.475 |
| Edit, dev profile | 0.337 | 0.519 | 0.540 |
| Edit, fully static | 0.591 | 0.749 | 0.700 |
| Oz size | 0.549 | 0.626 | 0.889 |
| Context: against a deps-primed GOCACHE | – | 0.632 | 1.19 |

Evidence lives under `benchmarks/spring/evidence/<entry>/<stamp>/`, and every certification has an entry in decisions.md. The full scoreboards are [scoreboard-B6.md](scoreboard-B6.md) and the B7 entries in decisions.md.

## How we got there

These are the levers that moved the numbers. Each has a rule in `docs/spring/performance-playbook.md`.

- **Fewer bytes per request.** The 404 went from 5,216 B and 27 allocations to 0 (template 404, S6). The validation 400 went from about 10 KB to 3,696 B (S7, R-99..R-105). The error-path p99 went from 1.8–3.0× to 0.56× and 0.81×.
- **Flint AOT fast paths S1–S7.** Proved at startup, guarded per request, with a generic fallback.
- **GC configuration:**
  - heapSizeFactor:3 (owner dc0ca836);
  - the exchange-storage pool (8cb4beb8);
  - idle threads removed from collection signalling (T1–T3: −12.5% pause);
  - the static-data map (ClassInfo-monitor rule e170ffd0: −9.5% pause). This landed after B7; its effect counts from B8.
- **Measurement discipline:**
  - interleaved trials, client-limit rules and drift guards;
  - a sampler and freezer, and `hold` on every venus command;
  - VOID marking for disturbed runs.

The generational collector, a sticky-mark design, was designed, reviewed and taken to slice 1. Slice 0 measured it as a no-go for these workloads, so it is shelved on branch `gengc-astra` ([gengc-final-plan.md](gengc-final-plan.md), [gengc-slice0-notes.md](gengc-slice0-notes.md)).

## Left open (not blocking Phase 2)

- **Exit-ledger items, deferred by 087f28a3:**
  - the GC-matrix parts;
  - framework timings;
  - the Java Spring Boot context runs;
  - platform-lane receipts (macOS, Windows, Linux arm64);
  - `docs/milestones/13.md`.
- **Non-gated tails:**
  - the 404's p99.9 is 2.01× Go (web-http is diagnosing, on posidon);
  - petclinic's p99.9 is 1.115×.
- **The validation path's capacity phase** is client-limited on Flint's side, so its 1.61× throughput is a lower bound (ae7858f8).
- **gs-relational-data-access** is a command application, so it has build metrics only.
- **Petclinic's cold build against a deps-primed GOCACHE** is 1.19×. This is context, not gated (the primary is the platform cache).
- **The owner's certification-mode question** was never formally answered. Interleaved mode was used throughout.

## What Phase 2 inherits

- [`docs/spring/phase2/porting-guide.md`](../phase2/porting-guide.md): the porting rules for autonomous agents.
- [`docs/spring/definition-of-done.md`](../definition-of-done.md): one command per module.
- The allocation gates, which run with and without the forced static trim (`AGENTS.md` step 4).
- The structural gate, including FLINT-E0536.
- `flint budget`, when m7 lands it.
