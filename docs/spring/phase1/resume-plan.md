# Phase 1 resume plan (measure first, then fix one build and one runtime bottleneck at a time)

The coordinator synthesised this from two independent reviews: Gemini 4 Neon High's full assessment ([assessment-2026-11-23-neon.md](assessment-2026-11-23-neon.md)) and GPT-6.2-Astra High's verification and correction of it ([assessment-2026-11-23-astra.md](assessment-2026-11-23-astra.md)). Where they disagree, Astra's corrections stand, because they were checked against the repository. Waiting for owner approval.

## Principle
We were changing code in many places before knowing which metrics actually lose. From now on:
1. Integrate the little that's ready.
2. Take **one same-commit certified baseline** across every gating part.
3. Pick **one build bottleneck and one runtime bottleneck** from it.
4. Fix, recertify, repeat.

No other streams run.

## 1. Integrate (owner's resume + about 8 h)

| # | What | Owner | Verification |
|---|---|---|---|
| 1 | `spring/dmd-arm64-wip` (a79a0826): native AOT extraction in the DMD fork | dmd-arm64 | Install in a private toolchain; 28 toolchain tests, structural, quality; build on macOS and Windows (not just overlay application); keep the parity fixtures |
| 2 | Finish the native wiring already on main (e76e7362): prelude into the AOT step in builder.d | flint-aot (m7 approved builder.d) | Prelude only for active-platform, server-enabled, non-test dev builds; served by trace; raw **and generated** output identical on 3 apps plus fixtures; genuine errors never fall back silently; incremental equivalence; stock-compiler fallback kept |
| 3 | The certified GC winner: one parallel mark thread per spare CPU, affinity-aware and overridable | boot + data-access | Reaches druntime before main on supported targets; respects --DRT-gcopt and a single-core process. **Only this setting**: startup collection, pools and musl stay separate experiments |
| 4 | `spring/framework-core-wip` (c2fb645e): Any accessor trim | framework-core | Merge if ready by freeze; doesn't hold anything |
| 5 | Queue and gate fixes | proof-harness (gate code with m7) | fork:true and the same private build tree on the HTTP, error and GC entries; error-validation gets real builds, `in` and `smoke_args`; assembly fails closed on any SHA, trial-count or coverage mismatch across build, HTTP, error and GC parts; p50 scored at 0.99 and p99.9 reported (a strengthening) |

**Not merged now:**
- `spring/web-http-wip` (accept-count): its own slice later. It conflicts with the fast path and doesn't affect the baseline.
- `spring/fast-path-proto` and `spring/fast-path-spike-wip`: already landed. Keep the refs, since deleting another role's history is owner-only.
- The seven `windows-wip`, `m8` refs: hold for their owners.

**Freeze B** = the verified integration commit, with its full SHA recorded. If the macOS and Windows checks of the fork lag, run the baseline at 55c17ef5 as an explicitly pre-native diagnostic, and pin native later.

## 2. One trustworthy baseline on B (about 4 h 40 min including gaps)

| Order | Entry | Answers |
|---|---|---|
| 1 | phase1-builds-petclinic (17 min) | Real cold and edit times after per-module compile, memo and native extraction; first valid scratch and static edit; Oz |
| 2 | phase1-http-gs-rest (41 min, named exception) | Does the shipping default fast path clear all five metrics? |
| 3 | phase1-http-petclinic (41 min, named exception) | First real PetClinic runtime numbers (owner 1, PostgreSQL) |
| 4 | error-404-p99 (45 min) | Is the 404 p99 losing? |
| 5 | error-validation-p99 (41 min) | Is the invalid-POST p99 losing? |
| 6 | phase1-builds-gs-relational (17 min) | Does the L1 size win certify; which build gaps remain? |
| 7 | phase1-builds-gs-rest (17 min) | Same, plus scratch and static edit |
| 8 | release-static-ab (30 min, non-gating) | glibc against musl, under rule 6ecd8933 |
| 9 | fast-path-pools-ab (≤30 min, only if RSS still decides) | parallel:1 against parallel:1 minPoolSize:4 incPoolSize:0, on the default fast path |
| natural quiet | 6 GC-matrix parts (326 min), framework-timings (80), java-context (165) | Exit-ledger items; overnight |

Rules M-1..M-4 throughout: fresh output directory, exact source SHA checked per part, raw samples kept.

## 3. Fix, driven by the baseline (one build and one runtime bottleneck at a time)
Candidates, picked only where the baseline shows a loss:
- **Build: PetClinic cold and edit.** Targets at the old Go denominators: about 304 ms cold (deps primed), 306 ms edit. Owners: flint-aot, m7, then framework-core with size-levers. Take phase medians and the slowest module on the installed release CLI, then the single biggest of: generated registration, erased List!T internals (framework/java util package.d and stream.d), in-process AOT. Static and scratch are profiled separately.
- **Runtime: gs-rest RSS, p50 and CPU.** Owners: boot and data-access. Isolate pools, musl and any pre-accept collection on the shipping default, and repeat on PetClinic. Take a fresh mapping census before touching engine-web or the collector.
- **Runtime: the PetClinic request path.** Owners: fast-path-spike coordinating, flint-aot, web-http, framework-core, data-access.
  - Profile owner 1 (the benchmark request; the allocation suite's row is owner 6).
  - Fast-path shapes in the approved order: S1 path variables, S2 ResponseEntity, S3 CORS Vary, S4 security-chain proof.
  - One measured 2B data-path site if the database dominates.
- **Error paths, only if they miss.** Owners: third-party-apis (validation), boot (error attributes), framework-core or web-http (negotiation). Fresh call-site profile first; the old counts are leads only.

## 4. Stop or defer
- **Parked:**
  - Phase 2;
  - broad API classification sweeps;
  - size items L2–L4;
  - the resident daemon and musl option B;
  - S5 request bodies;
  - new collector designs (D1 and D3 stay opt-in);
  - re-analysing the multicore-4/-5 blip;
  - Boot and Security feature backlogs that no Phase 1 suite needs.
- **No numeric claims** for ld -r, 512 KB pools, sealStartup, slabs, the JSON scanner, or validator and DTO writers until a current profile shows their cost.
- **Platform lanes:** macOS and Windows compiler checks now; final lane receipts at the claimed commit; secure native aarch64-musl capacity early; linux-arm64-vm re-records with mold only on the owner's yes.

## 5. Owner decisions
1. Approve this plan and its small staffing: dmd-arm64, flint-aot, boot, data-access, proof-harness, with framework-core optional. Everyone else stays parked until named.
2. Small pools (-22% RSS, -2.1% throughput, measured before the fast path): defer until the repeat on the fast path (entry 9).
3. Static edit builds stay gating (Neon proposed demoting; Astra showed that would weaken a gate).
4. Strengthen the gate: p50 and receipt provenance fail closed.
5. Runtime metrics apply to the two HTTP apps; gs-relational is a command app with no HTTP workload. Confirm, or approve a command workload.
6. third-party-apis' next item: decided by the baseline (validation if the invalid POST loses).

## 6. Timeline
- **Day 1:** a trustworthy scoreboard plus two evidence-backed work items.
- **Then:** at least one implementation and recertification cycle per remaining gap.
- **Phase 1 exit** in about 3–4 days is plausible only if the first fixes clear their intervals, remote hosts are available, and the rehearsals pass. It isn't guaranteed.
