# Milestone 04: Terminal interaction and browser/edge WASM

## Shared dispatch contract

Read `AGENTS.md`, `docs/AGENT_D_DIALECT.md`, `docs/ARCHITECTURE_DAG.md`, and the package specs for tui, widgets, prompt, wasm-bridge, ui-signals, wasi. In a bootstrapped implementation repository prefix these paths with `handoff/`. Input contracts are in `handoff/contracts/source/`; do not link them as production code.

Assign exclusive package ownership. After an accepted API change, regenerate dependent compile fixtures and rerun both compilers. Every task retains raw command output under `artifacts/tasks/<task-id>/`; failures are actionable output, not a reason to disable a gate.

## M4.1: tui

Inputs: `handoff/specs/tier-4/tui.md`, `policy/packages.json`, `policy/budgets.json`, `packages/tui/dub.sdl` and its direct dependencies (arena, conc, term, style).

Work: Implement model-update-view scheduling, diff rendering and cancellable effects; then widgets and prompts on this runtime.

Definition of done: Resize while rendering; grapheme width; wide/combining cells; paste; focus; async completion after screen teardown; password never logged; golden TUI exit restores terminal. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :tui --compiler=dmd
dub test :tui --compiler=ldc2
python3 tools/gates.py --package tui --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M4.2: wasm-bridge

Inputs: `handoff/specs/tier-5/wasm-bridge.md`, `policy/packages.json`, `policy/budgets.json`, `packages/wasm-bridge/dub.sdl` and its direct dependencies (arena).

Work: Implement fixed FLNT ABI encoder and browser decoder conformance fixtures; use one flush per animation frame.

Definition of done: Pointer+length overflow; malformed/truncated records; stale generation; unknown op; memory growth; forbidden attributes; canvas/GPU subcommand limits. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :wasm-bridge --compiler=dmd
dub test :wasm-bridge --compiler=ldc2
python3 tools/gates.py --package wasm-bridge --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M4.3: ui-signals

Inputs: `handoff/specs/tier-5/ui-signals.md`, `policy/packages.json`, `policy/budgets.json`, `packages/ui-signals/dub.sdl` and its direct dependencies (arena, wasm-bridge).

Work: Implement bounded signal/observer graph, computed dependencies, deduplicated queue and deterministic flush into bridge.

Definition of done: Repeated set; diamond graph; cycles rejected; capacity saturation; disposed source; stale handles; callback reentrancy; native/WASM same patch order. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :ui-signals --compiler=dmd
dub test :ui-signals --compiler=ldc2
python3 tools/gates.py --package ui-signals --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M4.4: wasi

Inputs: `handoff/specs/tier-5/wasi.md`, `policy/packages.json`, `policy/budgets.json`, `packages/wasi/dub.sdl` and its direct dependencies (arena, conc).

Work: Implement native Wasmtime embedding with fuel/memory/capability limits and separate WIT component adapters; keep WAMR capability profile explicit.

Definition of done: Guest trap; fuel/deadline interruption; denied filesystem/network host calls; multiple tenants; WASI0.2 and0.3 conformance; unsupported adapter fails clearly. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :wasi --compiler=dmd
dub test :wasi --compiler=ldc2
python3 tools/gates.py --package wasi --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## Milestone exit

Run affected-package tests through `python3 tools/flint.py test --compiler dmd` and `--compiler ldc2` for all implemented targets. Run quality and the relevant target/sanitizer jobs. Update the milestone checklist with exact source commit, commands and evidence hashes. Do not claim full certification from the structural command.
