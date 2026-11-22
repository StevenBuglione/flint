# Milestone 06: Freeze, empirical gates and release readiness

## Shared dispatch contract

Read `AGENTS.md`, `docs/AGENT_D_DIALECT.md`, `docs/ARCHITECTURE_DAG.md`, and the package specs for all 37 packages. In a bootstrapped implementation repository prefix these paths with `handoff/`. Input contracts are in `handoff/contracts/source/`; do not link them as production code.

Assign exclusive package ownership. After an accepted API change, regenerate dependent compile fixtures and rerun both compilers. Every task retains raw command output under `artifacts/tasks/<task-id>/`; failures are actionable output, not a reason to disable a gate.

## M6.1: arena

Inputs: `handoff/specs/tier-0/arena.md`, `policy/packages.json`, `policy/budgets.json`, `packages/arena/dub.sdl` and its direct dependencies (none).

Work: Complete and run all per-package probe apps, absolute-size profiles and negative safety corpora under both compilers.

Definition of done: All37 public contracts implemented and linked; no signature-only or always-success implementation; every specified edge case has observable behavior. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :arena --compiler=dmd
dub test :arena --compiler=ldc2
python3 tools/gates.py --package arena --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M6.2: web

Inputs: `handoff/specs/tier-2/web.md`, `policy/packages.json`, `policy/budgets.json`, `packages/web/dub.sdl` and its direct dependencies (arena, reactor, conc, di, serde, validate, log).

Work: Run same-host base/candidate/Go benchmarks on the fingerprinted ephemeral runner with equivalent profiles.

Definition of done: All raw samples and histograms retained; zero errors; p99.9 sample size; all worker GC deltas; cold and edited builds; O3/Oz size closure. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :web --compiler=dmd
dub test :web --compiler=ldc2
python3 tools/gates.py --package web --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M6.3: wasi

Inputs: `handoff/specs/tier-5/wasi.md`, `policy/packages.json`, `policy/budgets.json`, `packages/wasi/dub.sdl` and its direct dependencies (arena, conc).

Work: Complete cross-platform execution, ABI layout/callback tests, static ELF inspection and browser/WASI conformance.

Definition of done: Allseven platform receipts present; musl binaries execute without host libs; no unsupported sanitizers marked passed; exact lock+notices included. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :wasi --compiler=dmd
dub test :wasi --compiler=ldc2
python3 tools/gates.py --package wasi --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M6.4: mcp

Inputs: `handoff/specs/tier-7/mcp.md`, `policy/packages.json`, `policy/budgets.json`, `packages/mcp/dub.sdl` and its direct dependencies (arena, http, web, serde, validate, conc).

Work: Run aggregate gates, verify compatibility documentation and record the first observed baseline or compare to the protected base baseline.

Definition of done: All six gates pass without cap changes; failed goals reported explicitly; changelog, source hashes and signed provenance agree with binaries. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :mcp --compiler=dmd
dub test :mcp --compiler=ldc2
python3 tools/gates.py --package mcp --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## Milestone exit

Run affected-package tests through `python3 tools/flint.py test --compiler dmd` and `--compiler ldc2` for all implemented targets. Run quality and the relevant target/sanitizer jobs. Update the milestone checklist with exact source commit, commands and evidence hashes. Do not claim full certification from the structural command.

Final command:

```sh
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The initial empirical baseline procedure is in `handoff/docs/CI_PERFORMANCE_BUDGETS.md`. It is a separate absolute-cap review; never manufacture a prior commit or duplicate current samples and label them historical.
