# Milestone 02: Typed foundations and a complete console slice

## Shared dispatch contract

Read `AGENTS.md`, `docs/AGENT_D_DIALECT.md`, `docs/ARCHITECTURE_DAG.md`, and the package specs for test, serde, validate, config, log, di, style, term, os, cli. In a bootstrapped implementation repository prefix these paths with `handoff/`. Input contracts are in `handoff/contracts/source/`; do not link them as production code.

Assign exclusive package ownership. After an accepted API change, regenerate dependent compile fixtures and rerun both compilers. Every task retains raw command output under `artifacts/tasks/<task-id>/`; failures are actionable output, not a reason to disable a gate.

## M2.1: test

Inputs: `handoff/specs/tier-1/test.md`, `policy/packages.json`, `policy/budgets.json`, `packages/test/dub.sdl` and its direct dependencies (none).

Work: Wire named unittest enumeration, fluent equality assertions and compile-time interface mocks; keep runner code out of production builds.

Definition of done: Failing assertion yields nonzero exit; uncaught error distinguished; deterministic naming/filter; generated overloads and const/nogc interface methods compile. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :test --compiler=dmd
dub test :test --compiler=ldc2
python3 tools/gates.py --package test --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M2.2: serde

Inputs: `handoff/specs/tier-1/serde.md`, `policy/packages.json`, `policy/budgets.json`, `packages/serde/dub.sdl` and its direct dependencies (arena).

Work: Implement bounded JSON reader/writer with field metadata, checked numeric parsing, duplicate-key policy and arena Text. Then native owned adapter, TOML and optional native YAML.

Definition of done: UTF-8/surrogates; number overflow; NaN/infinity rejection; depth64 limit; embedded NUL; unknown keys; stale handles; corpus fuzz; native/BetterC/WASM identical golden JSON. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :serde --compiler=dmd
dub test :serde --compiler=ldc2
python3 tools/gates.py --package serde --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M2.3: validate

Inputs: `handoff/specs/tier-1/validate.md`, `policy/packages.json`, `policy/budgets.json`, `packages/validate/dub.sdl` and its direct dependencies (arena).

Work: Implement constraints and a bounded non-backtracking pattern engine; emit field-path diagnostics without GC.

Definition of done: Unicode blank strings; numeric bounds; malformed email; regex rejection; multiple failures; Text ownership; native and WASM parity. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :validate --compiler=dmd
dub test :validate --compiler=ldc2
python3 tools/gates.py --package validate --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M2.4: config

Inputs: `handoff/specs/tier-1/config.md`, `policy/packages.json`, `policy/budgets.json`, `packages/config/dub.sdl` and its direct dependencies (arena, serde, validate).

Work: Implement explicit precedence and profiles with typed required fields and secret-redacted diagnostics.

Definition of done: Defaults→base→profile→dotenv→process environment→CLI order; missing/unknown keys; duplicate keys; invalid values; no secret value in any error. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :config --compiler=dmd
dub test :config --compiler=ldc2
python3 tools/gates.py --package config --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M2.5: log

Inputs: `handoff/specs/tier-1/log.md`, `policy/packages.json`, `policy/budgets.json`, `packages/log/dub.sdl` and its direct dependencies (arena, conc).

Work: Implement bounded structured log ring, task context propagation and drain policy, then console formatting.

Definition of done: Full ring; maximum record size; escaping; concurrent fibers with different request IDs; shutdown drain deadline; zero hot-path GC allocations. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :log --compiler=dmd
dub test :log --compiler=ldc2
python3 tools/gates.py --package log --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M2.6: di

Inputs: `handoff/specs/tier-1/di.md`, `policy/packages.json`, `policy/budgets.json`, `packages/di/dub.sdl` and its direct dependencies (arena).

Work: Generate explicit dependency graph with constructor injection, configured instances and deterministic lifecycle order.

Definition of done: Missing/ambiguous bindings and cycles fail compilation; startup failure unwinds constructed services; external resources remain externally owned. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :di --compiler=dmd
dub test :di --compiler=ldc2
python3 tools/gates.py --package di --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M2.7: term

Inputs: `handoff/specs/tier-4/term.md`, `policy/packages.json`, `policy/budgets.json`, `packages/term/dub.sdl` and its direct dependencies (arena).

Work: Implement raw-mode guard and event decoder; add style layout, OS subprocess lifecycle, then CLI schema/parser as independent leaf tasks.

Definition of done: Terminal restore after panic/exception/signal path; split escape sequences; Ctrl-C; subprocess pipe backpressure; cancellation; flag aliases/--/negative numbers; golden CLI help. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :term --compiler=dmd
dub test :term --compiler=ldc2
python3 tools/gates.py --package term --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## Milestone exit

Run affected-package tests through `python3 tools/flint.py test --compiler dmd` and `--compiler ldc2` for all implemented targets. Run quality and the relevant target/sanitizer jobs. Update the milestone checklist with exact source commit, commands and evidence hashes. Do not claim full certification from the structural command.
