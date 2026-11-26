# Integration across the five machines

The owner asked on 2026-11-26 for an integration system that uses every machine, so changes land faster without weaker verification. This page is the design. proof-harness owns the merge train and implements it. The coordinator assigns the machines.

## The machines

| Machine | Address | Hardware | Role |
|---|---|---|---|
| venus | 10.10.10.8 | 32 cores, 122 GB, AMD graphics | **Development.** All 15 Sol lanes and the Claude roles build and test here. Each lane runs its module's definition of done here. Git pushes to GitHub happen only from here. |
| posidon | 10.10.10.12 | i7-11700K (16 threads), 31 GB, RTX 3080, about 17 GB free | **Verifier A,** and the only `flint budget` runner, because the budgets were seeded on it and instruction counts depend on the CPU. |
| owner's desktop | sbuglione@10.10.10.122 | NixOS with nix-ld, 24 threads, 125 GB, RTX 3070, gigabit link, 58 GB free after the owner cleared its uv and Go caches | **Verifier B.** Being provisioned in `~/flint-verifier/` (2026-11-26). |
| neptune | steven@10.10.10.116 | NixOS laptop, 16 threads, 15 GB (mostly used by a VM), RTX 3050 Ti, link about 0.2 MB/s | **Not used.** The link is too slow to copy the toolchain (about 10 GB). It is reconsidered if it moves to wired Ethernet. |
| pluto | 10.10.10.13 | Mac mini, 8 cores, 16 GB, 19 GB free after the owner-authorised cache cleanup | **macOS lane,** plus the Linux arm64 VM (lima). It can take post-merge macOS compile checks. |

## What a verifier checks

A verifier runs the apps-closure checks that today need the `apps-landing` slot:
- gs-rest-service, gs-relational-data-access and petclinic-rest;
- DMD and LDC;
- the allocation gates with and without the forced static trim;
- `spring_bench accept` in exact mode against the golden responses;
- the structural and quality gates on the combined tree.

Allocation counts and responses are deterministic across x86-64 Linux machines with the pinned toolchain, so any verifier's result is valid. `flint budget` (instruction counts) runs only on posidon.

Each verifier has the same pinned toolchain (`.tools`, v4.2 fork), natives, PostgreSQL 18.7 peer and Go. These are copied from venus with rsync and checked against the toolchain receipts' hashes. A verifier whose receipt hashes differ refuses to run.

## Speculative parallel trains

The current train verifies one batch of up to four lanes at a time on posidon. With several verifiers, the train pipelines speculatively, as Zuul and Bors do:

1. The **queue** is the existing FIFO (`agentctl queue apps-landing`). Lanes submit a ready branch that already passes their own module's definition of done.
2. The **scheduler** runs on venus as one continuous process, not inside a lane's turn. It cuts the queue into batches B1, B2, B3 of up to four submissions each. It builds candidate trees:
   - C1 = main + B1;
   - C2 = C1 + B2;
   - C3 = C2 + B3.

   Each candidate goes to a free verifier at the same time.
3. **Landing order is strict.** C1 lands as soon as it's green. C2 lands only after C1 has landed and C2 is green, so it was verified on exactly what main became, and so on.
4. **On a red result:**
   - the failing batch is bisected by submission on any free verifier;
   - the green prefix lands;
   - the culprit returns to the head of the queue with its log;
   - every candidate built on top of the red one is rebuilt and re-verified, which is the price of speculation.
5. **`flint budget`** runs on posidon for each candidate that will land. Candidates verified elsewhere are budget-checked on posidon in parallel.
6. **Outside changes to main** (a lane landing outside the closure under the cheap-rebase rule) don't invalidate candidates unless they touch the apps' closure. A closure-touching push outside the train is refused by the train's own check: the scheduler re-verifies anything stacked on it.

**Throughput:** with three verifiers and batches of four, up to 12 submissions can be in verification at once. Each lands about one verification time after the one before it, instead of one serial verification per batch.

## Cleanup and safety

- Each verifier works in a dedicated worktree, using a private `FLINT_CACHE` and private `.dub` cache under the verifier's own directory. All of these are deleted after each run, because posidon is short of disk.
- Verifiers never push. Only the venus scheduler pushes, after checking the `-> main` line.
- Verifiers never run timed benchmarks. Certification stays on venus overnight or on request.
- On owner machines (the desktop, 10.10.10.116), the verifier touches only its own directory (`~/flint-verifier/`). It installs nothing system-wide, and stops every server and database it starts.

## Order of work

1. **Now:** posidon only, with the train as landed (d8a1cc4c, 929bfded, 1297d635).
2. **proof-harness:** move the train into a continuous scheduler process on venus, and add speculative stacking with N verifiers (N = 1 works today).
3. **When the owner authorizes venus's key on 10.10.10.122:** provision Verifier B (rsync the toolchain, natives and peers; check the receipts) and add it to the scheduler.
4. **When 10.10.10.116 is reachable:** the same for Verifier C.
