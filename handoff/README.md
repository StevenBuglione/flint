# Flint: agent implementation handoff

**Research cut: 21 November 2026.** This archive defines a 37-subpackage D framework and supplies the build policies, contracts, examples, engineering specifications and task sequence for implementing it. It is an implementation handoff, not a claim that the framework already exists or has beaten Go.

## Start here

1. Read `AGENTS.md`, then `docs/RESEARCH_REPORT.md` and `docs/AGENT_D_DIALECT.md`.
2. Read `verification/VERIFICATION_REPORT.md` for exactly what was executed during preparation. Public `.d` contract modules are declaration-only; their successful compilation establishes syntax/type compatibility, not runtime functionality.
3. In a Python 3.12+ environment, install `tools/requirements.txt` and `scaffold/tools/requirements.txt`, then run `python3 tools/verify_handoff.py`. Supply `--dmd`, `--ldc`, `--dub`, `--go`, `--node`, `--dfmt` and `--dscanner` with the installed paths to reproduce the full preparation check; the verification report gives the complete command.
4. Run `python3 tools/bootstrap.py --destination ../flint` to create the implementation checkout. The destination must not already exist. This copies scaffolding, examples and a versioned handoff reference directory; it does not publish a repository.
5. Follow `MILESTONES_EXECUTION_PLAN.md` and dispatch tasks from `task-prompts/`. From the generated repository root, use `python3 tools/flint.py list`, `python3 tools/flint.py test --package arena --compiler dmd`, and `python3 tools/gates.py --package arena --gate structural`.

Initialize Git in the new implementation directory and commit actual implementation/benchmark changes before collecting release evidence. Bootstrap creates files; it does not invent repository history or a performance baseline.

The archive includes all 37 exact `dub.sdl` recipes. Empty production source directories are deliberate: no fake HTTP server, allocator or security implementation is presented as complete. The orchestrator rejects source-free build/test targets. Implement each package against its specification and checked contract; do not copy declaration-only contracts into production and call that an implementation.

`MANIFEST.sha256` records every delivered file except the manifest itself. From the extracted archive root, run `sha256sum -c MANIFEST.sha256` before rerunning verification tools, which refresh their result files.

## Fixed engineering decisions

- DMD **2.114.0**, LDC **1.43.0**, DUB **1.43.0**, dfmt **0.15.2**, D-Scanner **0.15.2**, Go **1.27.4**. LDC's frontend is D **2.113.0**: shared code uses the common supported subset, including `-preview=dip1000`.
- An explicit DUB dependency allowlist replaces accidental transitive imports. Catalog tiers remain as requested. Compression and templating are injected into web applications from the composition root so lower tiers do not import Tier 8.
- Application code defaults to `@safe`. Request arenas expose checked handles and scoped callbacks. GC-owned objects never become hidden arena roots. Event loops own their fibers and context state; a fiber never migrates between workers in Flint.
- Compile-time DI/routes/validation discover only explicit registered types. Runtime initialization, I/O, serialization and allocations still have real costs; no runtime reflection does not mean zero work.
- The five dual-target core packages use caller-owned storage and status returns. Browser core WASM, WASI components and native embedded WASM engines are separate build profiles.
- C ABI dependencies are pinned in `research/c-libraries.json` and `docs/C_FFI_PINNING_MATRIX.md`. ImportC is optional behind normalized C shims; it is not a promise that arbitrary vendor headers work unchanged.

## Performance release contract

The requested caps remain release goals: CLI cold DMD build below **1.5 seconds**, REST below **3 seconds**, stripped CLI below **3,000,000 bytes**, REST below **8,000,000 bytes**, and browser WASM below **100,000 gzip bytes**. They are not measured Flint results. All counters, percentiles, dependency closure sizes and reference-Go comparisons must come from equivalent workloads on the pinned runner. `docs/CI_PERFORMANCE_BUDGETS.md` specifies the measurement and initial-baseline procedure. Missing evidence blocks the full release gate.

## Contents

| Path | Purpose |
|---|---|
| `docs/` | Research, dialect, complete DAG, C pins, budgets and numbered ADRs |
| `specs/tier-0` through `specs/tier-8` | One detailed engineering specification for each library |
| `contracts/source/` | Checked public D API declarations, separate from runtime implementation |
| `scaffold/` | 37 recipes, Python orchestration, policy files, quality/performance tooling and GitHub workflows |
| `templates/` | CLI, TUI, REST, browser WASM and runnable Go CLI/HTTP references |
| `task-prompts/` | Six milestone dispatch documents with atomic slices and exit commands |
| `verification/` | Compiler evidence, positive/negative probes and preparation results |
| `research/` | Source ledger, release evidence and immutable dependency identities |

## Decisions requiring deliberate ownership

The strict latency profile must prevent GC activity across the participating process, including worker threads. `@nogc` on a request function alone cannot establish that. Static musl requires matching target runtime libraries and C dependencies; changing the linker to `zig cc` is insufficient. WebKitGTK does not satisfy the permissive-only default. WASI 0.3 is published, while Flint's D component adapter still requires implementation and conformance tests. Required GitHub checks and an ephemeral performance runner must be provisioned in the destination repository; a YAML file alone cannot configure branch protection.
