# Phase 1 evaluation, 23 November 2026, 7:30 PM EST

Every role was parked at the owner's request. All verified work is on `main` at or after `4956976e`; three pieces sit on branches (listed below). The measurement queue is stopped with its entries pending. Each role's resume point is in `python3 tools/agentctl.py state <role>`, and `agentctl board` shows them all.

## Scoreboard (certified, Flint ÷ Go; below 1 is better except throughput)

### Correctness
All three apps pass byte-identically against Java Spring Boot 4.2.0, with the fast path on by default: gs-rest-service 18/18, gs-relational-data-access 1/1, petclinic-rest 109/109.

### Build (phase1-builds at `6ab588f8`, before today's per-module compile, describer memo and native extraction)

| App | Cold build, platform cache | Cold build, Go's deps primed (context) | Edit build | Static edit build | From scratch | Oz size |
|---|---|---|---|---|---|---|
| gs-rest-service | **0.933 ✅** | n/a | **0.427 ✅** | 1.115 | 1.009 | **0.619 ✅** |
| gs-relational-data-access | 0.037 ✅ | **1.295** | **0.788 ✅** | 1.41 | 0.361 (no fair counterpart) | 1.249, now 0.660 locally (L1) |
| petclinic-rest | 0.620 ✅ | **4.18** | **2.08** | not measured | invalid run | 1.070, now 0.949 locally (L1) |

### Runtime (gs-rest-service only; the other two apps are not yet measured)

| Metric | Fast path on (6b7125e2) | Before today (first certified run) |
|---|---|---|
| Throughput | **1.293 ✅** | 0.746 |
| p99 | **0.729 ✅** | 2.45 |
| CPU per request | 0.84 (interval reaches 1.06) | 1.38 |
| p50 | 1.02 (level) | 1.84 |
| Peak RSS | **1.45 ❌** | 1.82 |

gc-pools-ab (certified) adds:
- parallel:1 cuts the worst pause from 13.5 to 4 ms and improves p99 further, at no cost. It is not yet baked into Boot.
- Small pools on top cut RSS by 22% but lose 2.1% throughput. That is an owner decision.

## Landed today, not yet certified
- **petclinic allocations per request:** GET /owners/1 1,655 -> 360; list owners 4,401 -> 1,544; update owner 2,973 -> 648; add pet 3,351 -> 928.
- **Per-module incremental compile (e77bc654):** petclinic edit 710–830 -> 339–379 ms locally; cold compile 530–715 -> 240–262 ms.
- **Describer memo and edit-extraction fix:** petclinic cold AOT -41..48%; edit AOT 210 -> 10 ms.
- **Drivers by composition (L1):** both database apps now beat Go on size locally.
- **The fast path is the default (8beab30b),** with an opt-out for diagnosis.
- **Harness-neutral coordination (agentctl)** and the performance playbook (R-1..R-25, B-, S-, M- rules).

## On branches (pushed, not merged)
- **`spring/dmd-arm64-wip` (a79a0826): native AOT extraction in the DMD fork.**
  - 33 ms served for petclinic, against 379 ms for the describer.
  - Byte-identical on 392 platform modules, the 3 apps and tests/aot.
  - Needs: fork install, toolchain tests, gates, macOS and Windows builds, then flint-aot's B-7 parity wiring.
- **`spring/framework-core-wip` (c2fb645e):** Any accessor trim, 201 -> 149 instructions.
- **`spring/web-http-wip` (c29c337c):** accept-count 100 and stop-accepting at max connections; unverified.

## Open questions and risks
1. **Memory (1.45×)** is the one gs-rest runtime metric still losing. The levers left:
   - bake parallel:1 into Boot;
   - post-startup GC.minimize;
   - small pools (owner trade-off);
   - static musl (release-static-ab is ready to run).
2. **petclinic's cold build (4.18× deps-primed)** is the biggest build gap. The expected path: native extraction plus per-module compile plus the template diet. About 1.3–1.6× from the first two alone; around 1× needs the diet as well.
3. **Runtime of petclinic and gs-relational** has never been measured (phase1-http parts pending).
4. **The multicore-5 CPU anomaly** (1.17 -> 1.33 at a fixed rate) has no code culprit. The likely cause is noise or 31 GC mark threads waking under a 2-CPU taskset, which parallel:1 removes. To settle it, re-run both commits in one window.
5. **Static edit builds (1.1–1.4×) and from-scratch builds (≈1.0)** still miss.
6. **Platform lanes** (macOS, Windows, Linux arm64) were not re-run against today's changes. The Linux arm64 lane receipt predates mold.

## Decisions for the owner
1. Small GC pools: −22% RSS for −2.1% throughput. Take it, or wait for musl and GC.minimize first.
2. third-party-apis' next item: AOT per-type JSON writers (~9% of /greeting) or the validator's per-request allocations (20% of create-owner).
3. The resume order (recommended below).

## Recommended resume order
1. Land the three branches once verified, with native extraction first.
2. Certify in one batch:
   - phase1-builds for all three apps, at a commit with per-module compile, memo and native extraction;
   - gs-rest-multicore with the fast path by default and parallel:1 baked in;
   - the phase1-http parts for petclinic and gs-relational;
   - release-static-ab.
3. Then the remaining gaps:
   - petclinic's fast-path shapes S1–S4;
   - RSS (GC.minimize, pools, musl);
   - petclinic's remaining data-path and compile template diet;
   - static and scratch builds.
