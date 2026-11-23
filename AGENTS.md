# Flint autonomous-agent operating rules

## Objective and authority

Implement the specifications in small, independently testable slices. Preserve the user's 37-package product surface and the numeric release goals. This handoff supplies the proposed API contract; it does not authorize changing external repositories, publishing services, sending messages or making purchases. Ordinary local implementation, tests, benchmarks and reversible fixes are expected.

## Read order and ownership

Read this file, the assigned milestone prompt, `docs/AGENT_D_DIALECT.md`, `docs/ARCHITECTURE_DAG.md`, the assigned package spec and all cited ADRs before editing. In a bootstrapped repo these documents live under `handoff/`. Assign one agent per package directory; assign one integration owner for policy, root manifests, generated artifacts and API changes. Agents may work on separate packages concurrently after prerequisite contracts are accepted. Never change another agent's files without coordination.

## Source layout

Each implementation lives under `packages/<dub-name>/source/flint/`. A module with children uses `flint/name/package.d`, never both `flint/name.d` and a child module hierarchy. D module names use underscores for hyphenated DUB names. `flint:engine-template` uses `flint.engine.templates`, because `template` is a keyword. Public import paths and UDAs must remain stable. `ffi/` and `sys/` are private low-level subdirectories; applications must not import them.

## Mandatory language rules

- Enable `-preview=dip1000`. Every normal source module declares `@safe:`. Every hot-path function declares `nothrow @nogc` explicitly; startup adapters may allocate and throw only when the package spec permits it.
- Use structs for data. Use classes/interfaces only for intentional runtime contracts and DI, and for the Spring-shaped API layer (see "Spring port" below). Bind constructors explicitly; never scan loaded modules or construct a service from its string name.
- Keep reflection, `__traits`, template mixins and code generation inside the approved internals of di, serde, web, data, cli, validate, test, template, desktop (command tables, ADR-020), AI/MCP schema generators, Flint AOT, and the API-layer internals listed in `docs/spring/api-mapping.md`. Application code may apply UDAs and invoke a documented template API; it may not invent a framework.
- Use explicit selective imports. No umbrella `import std;`, `std.algorithm`, `std.range` in core modules, no `std.regex` in core or BetterC paths, no recursive type discovery across an entire package.
- Every `@trusted` function is confined to an allowlisted low-level directory, has an immediately adjacent `// SAFETY:` ownership/bounds/lifetime justification, is at most 60 source lines, and has positive, negative and sanitizer/fuzz coverage. Trusting an entire scope is prohibited. The comment does not prove safety.
- No request storage escapes into a cache, queue, detached task, singleton, retained C callback or future. Copy into a specifically owned buffer before transfer. Cancellation does not release storage until the kernel/C library reports final completion.
- No new cryptographic algorithm, HTTP/2 parser, database engine, PostgreSQL wire protocol or Kafka protocol implementation. Use the pinned wrappers.

## Spring port (ADR-030)

Flint is a port of the Spring ecosystem. Read `docs/adr/ADR-030-flint-is-a-spring-port.md` and `docs/spring/api-mapping.md` before touching any public API.

- **Names.** Public names are Spring's, with only the word "Spring" replaced by "Flint". `org.springframework.X` becomes the D module `flint.X`. Configuration keys are Spring's, with `spring.` becoming `flint.`. Do not invent a name where Spring has one.
- **The API layer:** the Spring-shaped public types of the framework, Boot and portfolio libraries.
  - It follows the rulebook: classes, interfaces, exceptions, the GC, getters and setters, and overloads, mapped by rule ID.
  - It stays `@safe`.
  - It never hands arena memory to user code.
  - Every adapted element cites a rule.
  - Every deviation is listed in the rulebook with its reason.
- **Engines** (parsing, routing, I/O, pools, codecs, protocol wrappers):
  - keep every rule in "Mandatory language rules";
  - keep `nothrow @nogc` hot paths;
  - return `Result`, and convert to an exception only at the user boundary.
- **Per-fiber state** uses `FiberLocal!T`. Framework packages keep no mutable module-level thread-local state.
- **Ported code.**
  - Before porting, check the upstream project in `policy/upstream-licences.json`.
  - Keep the upstream header and add "Modified by the Flint authors".
  - Port from source only where the matrix allows it. Implement clean-room code from specification and documentation only.
  - Put EPL-2.0 files only in modules marked EPL-2.0.
- **Proof obligations.** Every ported module:
  - updates `api/mapping.json`;
  - ports its upstream tests;
  - stays within its compile-time, size and template budgets.

  A budget miss is a blocker, not a rationale.

## Dependency rules

`policy/packages.json` is the exact allowlist, not a suggested graph. A direct import requires a direct DUB dependency even when another dependency already exposes it. Lower tiers cannot import higher tiers. CLI/TUI code cannot import web/data packages. Optional codecs, desktop backends and templates attach through application composition. Circular imports are rejected, including generated code. Generated source must be materialized and checked before compilation; mixins may not generate import declarations.

## Daily task loop

1. Create or choose the isolated task branch. Record the contract version and upstream lock checksum in the task note.
2. Add the smallest failing behavioral or compiler-negative test that exercises the task's actual risk. Avoid tests that simply restate a trivial implementation.
3. Implement the slice. Use explicit error/status mapping and cleanup on every early return.
4. Run `dub test :<package> --compiler=dmd` and `dub test :<package> --compiler=ldc2`, then `python3 tools/gates.py --package <package> --gate structural`.
5. Run the relevant sanitizer, fuzz, ABI, cancellation and cross-target fixtures from the package specification. Record exact commands and exit codes.
6. Write a short handoff note: changed behavior, verified evidence, remaining implementation work and affected dependents. Integrate only when both the package owner and integration owner agree on any API change.

`<package>` denotes the task's explicit package name, not a literal shell argument; each milestone lists concrete commands for its starting slice. Do not stop because a later unimplemented package cannot yet pass its runtime suite. Do not report the complete release gate as green until the full evidence is present.

## CI and evidence integrity

Source-free packages, missing benchmark outputs, empty test reports, unsupported sanitizer flags and unknown platform results are failures for their claimed capability. A contract-only typecheck is never a runtime test. The initial baseline is an observed result on the designated runner, not a file of invented numbers. After baseline establishment, compare the base commit and candidate under the same toolchain, workload and dependency closure; do not let the candidate replace its own baseline. Runner metadata and raw samples are retained.

Agents may optimize code to meet a budget. They may not raise caps, remove cases, turn off bounds checking, reduce the response body, weaken SQL work, use a different TLS profile, alter load duration or replace the Go comparator to manufacture a win. A justified change to workload or budget requires its own reviewed ADR and remeasurement of both sides. No `continue-on-error` on required quality or performance jobs.

## Definitions of done

A package is implemented when its complete specified public contract has linked behavioral tests, its acceptance matrix passes, C ownership is exercised with the real pinned dependency, and its supported targets build/run. A milestone is complete when every slice in its checklist passes and its golden application works. A release is complete only when all 37 packages and Gates 1–6 meet the full evidence contract. Failing performance goals remain visible blockers; an architectural rationale is not a measurement.
