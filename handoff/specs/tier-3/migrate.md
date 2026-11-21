# flint:migrate — Versioned embedded SQL migrations with transactional history

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] Flyway-style versioned SQL, embedded source bytes and SHA-256 history validation.
- [ ] Ordered startup migration, cross-process database lock and fail-fast checksum drift.
- [ ] PostgreSQL and SQLite transaction policy with a deliberate nontransactional migration escape hatch.
- [ ] No automatic destructive down migration or silent history repair.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/migrate/dub.sdl inside the Flint root that declares all subpackages. Module: flint.migrate. Direct allowed dependencies: flint:arena, flint:sql, flint:log, flint:conc.

```sdl
name "migrate"
description "Flint migrate subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:sql" version="*"
dependency "flint:log" version="*"
dependency "flint:conc" version="*"

configuration "library" {
    targetType "library"
}
configuration "unittest" {
    targetType "library"
    sourcePaths "source" "tests"
    importPaths "source" "tests"
    excludedSourceFiles "tests/betterc.d"
}
```

The source library has no executable main. Native build/link selection follows the central C-FFI matrix. Public imports are explicit; transitive dependency reachability does not authorize undeclared direct imports. No package in this specification may import a higher catalog tier or introduce a cycle.

## 3. Concrete public D contract

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/migrate.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.migrate;
import flint.arena : Error, Result;
import flint.conc : Context;
import flint.sql : Pool;

@safe:
struct Migration
{
    ulong versionNumber;
    string description;
    string sql;
    ubyte[32] sha256;
    bool transactional = true;
}

struct MigrationOptions
{
    string historyTable = "flint_schema_history";
    long lockTimeoutNanos = 30_000_000_000L;
    bool validateOnly = false;
}

struct MigrationReport
{
    uint discovered;
    uint applied;
    ulong currentVersion;
}

Migration embeddedMigration(string fileName, ulong versionNumber, string description, bool transactional = true)();
Result!MigrationReport migrate(ref Pool pool, scope const(Migration)[] migrations,
        MigrationOptions options, ref Context context);
Error validateHistory(ref Pool pool, scope const(Migration)[] migrations, ref Context context);
```

## 4. Internal architecture and observable semantics

The bundled tools/migration_manifest.py computes SHA-256 over exact source bytes using Python hashlib, emits a D Migration table and per-file .sha256 sidecars, and verifies drift with --check. embeddedMigration!(fileName,version,description) reads the SQL and its generated sidecar through D string imports; CTFE parses the 64 hexadecimal digest digits but does not implement SHA-256 or call a C library. The application supplies an explicit immutable array; there is no filesystem scan at runtime. Filenames follow V000001__description.sql with six-or-more decimal digits, unique positive version numbers and UTF-8 content. Reject duplicate/descending versions and empty descriptions before connecting. Encoding/line-ending changes alter the checksum; do not normalize them.

The history table has version BIGINT primary key, description TEXT, sha256 CHAR(64), installed_at UTC timestamp, execution_ms BIGINT and success BOOLEAN. PostgreSQL additionally stores the effective schema and driver identity in the first row's metadata table; SQLite stores them in an adjacent settings table. The migration lock is PostgreSQL pg_advisory_lock on a fixed application-defined 64-bit key, acquired with deadline polling, or a SQLite BEGIN IMMEDIATE transaction. Do not use a process-local mutex as the cross-process guarantee.

Under the lock, read all applied versions, compare stored digests and reject missing or modified historical migrations. Apply pending migrations in ascending order. Transactional migration SQL and its successful history insert commit together. If execution fails, rollback; the process reports the failing version and sanitized SQL error, never begins serving traffic and never advances history. validateOnly performs all ordering/checksum checks without SQL execution.

Some PostgreSQL operations, such as concurrent index creation, cannot run in a transaction. Such a migration must explicitly set transactional=false; a durable started marker is written before executing it and success is recorded only afterward. Any started-but-unsuccessful marker blocks future startup with a concrete manual recovery instruction and the exact version. The system never guesses whether the partial operation succeeded. SQLite nontransactional migration mode is rejected in the initial implementation.

Embed scripts as whole SQL programs. PostgreSQL execution may use an allowed blocking driver operation on a worker during startup because migration is not a request hot path. SQLite uses sqlite3_exec/prepared stepping on its worker. Do not split statements on semicolons: functions, strings and comments can contain semicolons. Resource loading uses an allowlisted -J migration directory; an arbitrary application path cannot be read by a template.

### Required implementation layout

- source/flint/migrate.d: Migration types and embedding entry point.
- source/flint/migrate/history.d: backend history schema, validation and lock ownership.
- source/flint/migrate/runner.d: transactional/nontransactional state machine.
- tests/migrations: exact fixtures for drift, failed and concurrent startup.

## 5. Native boundary, ownership and safety

No new native runtime. Driver operations use flint:sql. Hashing is performed by the bundled offline Python generator, with --check required before D compilation. The canonical command is python3 tools/migration_manifest.py --input resources/migrations --output generated/app_migrations.d --module app.migrations; add --check in CI. Each source sidecar is named V000001__description.sql.sha256 and contains exactly the lowercase digest, two spaces, basename and newline. A sidecar is not a substitute for recomputation: CI rejects any stale generated D, JSON or hash sidecar. No pure-D cryptographic implementation is introduced and CTFE never attempts an impossible foreign call. Migration startup is full D and may allocate; it is excluded from hot-request allocation claims.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

No additional native dependency; consume only the lower-tier packages listed above.

### Native preparation before DUB

On the Linux glibc release runner, the exact preparation command is:

```bash
python3 tools/native_build.py --profile sql --target linux-x86_64-glibc --phase build --emit-dub
```

Use --phase plan to inspect resolved commands without claiming a build. The build installs pinned archives and a verified libflint_ffi.a from implemented native shims, then writes a delimited platform-specific lflags block into affected DUB recipes. Installation receipts are cumulative. Cross-target commands replace the target with the exact central matrix target and use its SDK/toolchain. C shim source must exist at the implementation milestone; missing shims must fail the build rather than produce a fake library.

## 6. Numeric compile and size budgets

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

| Measurement | Hard ceiling |
| --- | --- |
| Cold DMD fixture build | 1.40 s |
| Incremental DMD leaf edit | 0.60 s |
| Cold LDC fixture build | 8.40 s |
| Incremental LDC leaf edit | 4.20 s |
| Incremental linked code/data contribution | 786432 bytes |
| Compiler peak RSS | 536870912 bytes |
| Template instances per canonical fixture | 2000 |

These are engineering ceilings from scaffold/policy/packages.json, measured with the fixed runner/toolchain/workload policy. They are not measured achievements of these declarations. Also fail >10% compile-time/compiler-RSS/template growth or >5% binary growth against the approved baseline. The whole selected application includes native libraries in its cap; a smaller wrapper-only delta cannot excuse a larger deployment artifact. A changed profile is a different benchmark identity and cannot be compared as if equivalent.

## 7. Required unit, protocol, fuzz and benchmark acceptance

| Test identity | Passing condition |
| --- | --- |
| embedded_bytes | Compile the same script twice; embedded bytes/hash are identical. One CRLF/LF change produces checksum drift. |
| order_validation | Duplicate, zero and out-of-order versions fail before opening the database. |
| history_drift | Modify/remove an applied migration; startup fails and does not execute any new script. |
| transaction_rollback | A migration inserts data then fails; data and success history are absent after rollback. |
| concurrent_start | Start two processes against one database; each migration applies once and the second sees completed history. |
| lock_timeout | Hold the migration lock; deadline expires with no partial work and no leaked connection. |
| sql_program | Dollar-quoted PostgreSQL functions, semicolons inside strings/comments and SQLite triggers execute intact. |
| nontransactional_recovery | Crash after started marker; next startup blocks with version/hash and never silently retries or marks success. |
| migration_bench | Load/validate history of 1000 embedded migrations; bound startup query count and compiler template counts. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :migrate --compiler=dmd
dub test :migrate --compiler=ldc2
python3 tools/gates.py --package migrate --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [D string imports](https://dlang.org/spec/expression.html#import_expressions) — String imports are compile-time file contents constrained by the compiler import path.
- [PostgreSQL explicit locking](https://www.postgresql.org/docs/current/explicit-locking.html) — Database-scoped advisory locks coordinate independent migration processes.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
