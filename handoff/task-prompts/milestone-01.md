# Milestone 01: Memory, cancellation and platform operations

## Shared dispatch contract

Read `AGENTS.md`, `docs/AGENT_D_DIALECT.md`, `docs/ARCHITECTURE_DAG.md`, and the package specs for arena, conc, reactor. In a bootstrapped implementation repository prefix these paths with `handoff/`. Input contracts are in `handoff/contracts/source/`; do not link them as production code.

Assign exclusive package ownership. After an accepted API change, regenerate dependent compile fixtures and rerun both compilers. Every task retains raw command output under `artifacts/tasks/<task-id>/`; failures are actionable output, not a reason to disable a gate.

## M1.1: arena

Inputs: `handoff/specs/tier-0/arena.md`, `policy/packages.json`, `policy/budgets.json`, `packages/arena/dub.sdl` and its direct dependencies (none).

Work: Implement checked buffer identities, alignment, overflow-safe allocation, scoped read/write callbacks and reset with outstanding-borrow rejection.

Definition of done: Zero capacity; overflow; double reset; foreign/stale handle; stack/callback escape fails compilation; randomized reuse under ASan. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :arena --compiler=dmd
dub test :arena --compiler=ldc2
python3 tools/gates.py --package arena --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M1.2: conc

Inputs: `handoff/specs/tier-0/conc.md`, `policy/packages.json`, `policy/budgets.json`, `packages/conc/dub.sdl` and its direct dependencies (arena).

Work: Implement cancellation tree, monotonic deadlines and bounded single-consumer queue first; then separate MPMC sequence-slot queue and bounded offload pool.

Definition of done: Cancel-before-start; cancel/complete race; nested deadline; capacity saturation; wraparound; shutdown while producers wait; exact-once completion. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :conc --compiler=dmd
dub test :conc --compiler=ldc2
python3 tools/gates.py --package conc --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M1.3: reactor

Inputs: `handoff/specs/tier-0/reactor.md`, `policy/packages.json`, `policy/budgets.json`, `packages/reactor/dub.sdl` and its direct dependencies (arena, conc).

Work: Implement operation table and epoll fallback, then io_uring feature selection, then kqueue and IOCP behind the same completion contract.

Definition of done: Partial read/write; EOF; cancellation before/during/after submit; handle reuse; no free before final completion; blocked io_uring falls back; per-worker GC counters. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :reactor --compiler=dmd
dub test :reactor --compiler=ldc2
python3 tools/gates.py --package reactor --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## Milestone exit

Run affected-package tests through `python3 tools/flint.py test --compiler dmd` and `--compiler ldc2` for all implemented targets. Run quality and the relevant target/sanitizer jobs. Update the milestone checklist with exact source commit, commands and evidence hashes. Do not claim full certification from the structural command.
