# Milestone 03: HTTP and persistence vertical slices

## Shared dispatch contract

Read `AGENTS.md`, `docs/AGENT_D_DIALECT.md`, `docs/ARCHITECTURE_DAG.md`, and the package specs for http, web, security, sql, data, migrate, cache, schedule, actuator, rpc. In a bootstrapped implementation repository prefix these paths with `handoff/`. Input contracts are in `handoff/contracts/source/`; do not link them as production code.

Assign exclusive package ownership. After an accepted API change, regenerate dependent compile fixtures and rerun both compilers. Every task retains raw command output under `artifacts/tasks/<task-id>/`; failures are actionable output, not a reason to disable a gate.

## M3.1: http

Inputs: `handoff/specs/tier-2/http.md`, `policy/packages.json`, `policy/budgets.json`, `packages/http/dub.sdl` and its direct dependencies (arena, reactor, conc, serde).

Work: Wrap libcurl multi with bounded response sinks, explicit request lifetime, timeouts and verified TLS defaults.

Definition of done: Redirect credentials stripped across origins; cancellation complete-before-free; slow body backpressure; content limits; certificate/hostname errors; retry only replayable requests. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :http --compiler=dmd
dub test :http --compiler=ldc2
python3 tools/gates.py --package http --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M3.2: web

Inputs: `handoff/specs/tier-2/web.md`, `policy/packages.json`, `policy/budgets.json`, `packages/web/dub.sdl` and its direct dependencies (arena, reactor, conc, di, serde, validate, log).

Work: Build H1 llhttp parser, static router and arena response ownership. Complete bench-rest correctness before adding H2 nghttp2 flow control.

Definition of done: Smuggling CL/TE cases; headers/body limits; duplicate routes fail compile; keepalive; partial sends; cancellation; H2 stream/window exhaustion; golden JSON byte identity. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :web --compiler=dmd
dub test :web --compiler=ldc2
python3 tools/gates.py --package web --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M3.3: sql

Inputs: `handoff/specs/tier-3/sql.md`, `policy/packages.json`, `policy/budgets.json`, `packages/sql/dub.sdl` and its direct dependencies (arena, reactor, conc, log).

Work: Implement SQLite offload first and PostgreSQL nonblocking connection states next; pool leases are exclusive and cancellation drains before reuse.

Definition of done: Statement binding; transaction rollback on every exit; timeout; server disconnect; exhausted pool; cancelled query drained; connection never shared by two requests. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :sql --compiler=dmd
dub test :sql --compiler=ldc2
python3 tools/gates.py --package sql --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M3.4: data

Inputs: `handoff/specs/tier-3/data.md`, `policy/packages.json`, `policy/budgets.json`, `packages/data/dub.sdl` and its direct dependencies (arena, sql, serde, validate, di, conc).

Work: Generate row codecs and repository methods, then wire the golden REST application through DI and migration startup.

Definition of done: Null/type mismatches; notFound mapping; parameterized queries; duplicate key status; repeated SQL migration checksum mismatch; concurrent migration lock. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :data --compiler=dmd
dub test :data --compiler=ldc2
python3 tools/gates.py --package data --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M3.5: security

Inputs: `handoff/specs/tier-2/security.md`, `policy/packages.json`, `policy/budgets.json`, `packages/security/dub.sdl` and its direct dependencies (arena, http, serde, conc).

Work: Implement auth decision model and crypto shims; add JWT/JWKS and issuer/audience/algorithm policies, then app middleware adaptation.

Definition of done: Reject none and algorithm confusion; wrong issuer/audience; unknown key; expired/not-yet-valid; bounded JWKS refresh; CORS origin allowlist; password-hash resource limits. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :security --compiler=dmd
dub test :security --compiler=ldc2
python3 tools/gates.py --package security --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M3.6: cache

Inputs: `handoff/specs/tier-3/cache.md`, `policy/packages.json`, `policy/budgets.json`, `packages/cache/dub.sdl` and its direct dependencies (arena, reactor, conc, serde).

Work: Implement bounded memory TTL/LRU, hiredis integration and generated cache call boundaries; concurrently add schedule/actuator after their direct dependencies pass.

Definition of done: Monotonic TTL; key collision policy; stampede handling; cron DST overlap/gap; health does not recurse; cardinality limits; exporter backpressure. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :cache --compiler=dmd
dub test :cache --compiler=ldc2
python3 tools/gates.py --package cache --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M3.7: rpc

Inputs: `handoff/specs/tier-2/rpc.md`, `policy/packages.json`, `policy/budgets.json`, `packages/rpc/dub.sdl` and its direct dependencies (arena, reactor, conc, web, http, serde).

Work: Implement WebSocket/SSE lifecycle, protobuf-c generated messages and gRPC framing/status/trailers on H2.

Definition of done: Fragmented frames; UTF-8; ping/close timeout; SSE cancellation; gRPC compressed flags/limits; deadline trailers; interop with pinned external client. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :rpc --compiler=dmd
dub test :rpc --compiler=ldc2
python3 tools/gates.py --package rpc --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## Milestone exit

Run affected-package tests through `python3 tools/flint.py test --compiler dmd` and `--compiler ldc2` for all implemented targets. Run quality and the relevant target/sanitizer jobs. Update the milestone checklist with exact source commit, commands and evidence hashes. Do not claim full certification from the structural command.
