# flint:sql — Async-friendly PostgreSQL/SQLite connections and transaction scopes

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] JDBC/database-sql-style pool, prepared parameters and typed values.
- [ ] PostgreSQL nonblocking libpq on owning reactor; SQLite calls on bounded worker threads.
- [ ] Context deadlines, bounded acquisition queues, explicit leases and transaction rollback.
- [ ] @Transactional is metadata for registered invokers; withTransaction is the direct explicit API.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/sql/dub.sdl inside the Flint root that declares all subpackages. Module: flint.sql. Direct allowed dependencies: flint:arena, flint:reactor, flint:conc, flint:log.

```sdl
name "sql"
description "Flint sql subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:reactor" version="*"
dependency "flint:conc" version="*"
dependency "flint:log" version="*"

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

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/sql.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.sql;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
enum Driver : ubyte
{
    postgres,
    sqlite
}

enum Isolation : ubyte
{
    readCommitted,
    repeatableRead,
    serializable
}

enum ValueKind : ubyte
{
    null_,
    boolean,
    int64,
    float64,
    text,
    bytes
}

struct SqlValue
{
    ValueKind kind;
    long integer;
    double floating;
    Buffer bytes;
}

struct Transactional
{
    Isolation isolation = Isolation.readCommitted;
}

struct PoolOptions
{
    Driver driver = Driver.postgres;
    string connectionString;
    uint maxConnections = 16;
    uint maxWaiters = 256;
    long acquireTimeoutNanos = 5_000_000_000L;
    uint maxPreparedPerConnection = 128;
}

struct Row
{
    private ulong slot;
    private ulong generation;
    Result!SqlValue value(uint column, ref scope RequestArena arena) const nothrow @nogc;
    uint columns() const nothrow @nogc;
}

alias RowConsumer = Error delegate(ref Row row) @safe nothrow @nogc;
struct Connection
{
    private ulong slot;
    private ulong generation;
    Result!ulong execute(scope const(char)[] sql, scope const(SqlValue)[] params,
            ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error query(scope const(char)[] sql, scope const(SqlValue)[] params, ref scope RequestArena arena,
            ref Context context, scope RowConsumer consume) nothrow @nogc;
}

struct Pool
{
    private ulong slot;
    private ulong generation;
    Error open(PoolOptions options);
    Result!Connection acquire(ref Context context) nothrow @nogc;
    Error release(ref Connection connection) nothrow @nogc;
    Error close(ref Context context) nothrow @nogc;
}

alias TransactionBody = Error delegate(ref Connection connection) @safe nothrow @nogc;
Error withTransaction(ref Pool pool, Isolation isolation, ref Context context, scope TransactionBody body) nothrow @nogc;
```

## 4. Internal architecture and observable semantics

Pool.open validates its backend and creates at most 16 connections. Each native connection has one owner and at most one active nonpipelined command; callers acquire a generation-checked lease. The wait queue is FIFO, capped at 256 and bounded by min(Context.deadline, 5 seconds). release resets statement/transaction state before returning a lease. A broken or still-busy connection is retired and replaced asynchronously. A copied handle cannot release or use a lease twice because generation changes on release.

PostgreSQL connects with PQconnectStart/PQconnectPoll, enters nonblocking mode, sends typed parameters through PQsendQueryParams or cached prepared statements and drains output with PQflush. Read readiness calls PQconsumeInput, then retrieves results until PQgetResult returns null. No PQexec call runs on a reactor. Cancellation requests use the pinned libpq nonblocking cancel API where available; otherwise the cancel request is offloaded. Cancellation success is not evidence that all results have been consumed. Drain to protocol idle, inspect transaction status and issue rollback before pooling; if a deadline prevents cleanup, destroy the connection.

SQLite owns one connection per worker. It does not run on reactor cores even when a page is expected to be cached. Enable foreign_keys=ON. WAL is an explicit local-file option and is forbidden for unsupported network filesystems. The default durability is synchronous=FULL; applications may select NORMAL only with an explicit durability decision. Use sqlite3_prepare_v3, sqlite3_bind_* and sqlite3_step; finalize statements on eviction. sqlite3_interrupt cooperates with cancellation. Cap the busy wait by the caller deadline.

SqlValue uses an explicit kind tag; null is distinct from empty text, empty blob, false and zero. Text/blob parameters are Buffer handles resolved against the supplied arena. Bind lengths separately, preserve embedded NUL and never interpolate values into SQL strings. Row values are valid only inside the row-consumer call; copying a cell copies its bytes into the caller's arena. Big integers, unsigned IDs outside signed 64-bit DB range, unsupported OIDs and invalid UTF-8 produce explicit errors.

withTransaction acquires exactly one connection, begins the chosen isolation, invokes the callback and commits only when it returns ok. On error/cancel/exception from an opted-in full-D adapter, rollback is attempted; failed rollback retires the connection. Nested withTransaction calls are rejected unless a separate savepoint API is used. Committing and then losing the connection yields an ambiguous-outcome error; the framework never retries the transaction automatically. @Transactional works only through generated registered calls, not arbitrary direct calls or self-invocation.

### Required implementation layout

- source/flint/sql.d: pool, lease, value, row and transaction APIs.
- source/flint/sql/pool.d: bounded waiters and lease generations.
- source/flint/sql/postgres.d and sqlite.d: backend state machines.
- source/flint/sql/ffi/shim.d and c/sql.c: libpq/sqlite opaque handles.

## 5. Native boundary, ownership and safety

Use pinned libpq and SQLite from the central matrix; wrap opaque PGconn/PGresult/sqlite3/sqlite3_stmt pointers in C. contracts/c/sql.h fixes startup/cancel ownership calls. SQLite statements and PGresult buffers are released on every success/error path before lease reuse. C callbacks carry scalar lease IDs; no GC class reference is stored in native memory. Prepared statement cache has 128 entries/connection keyed by SQL+parameter type list. DUB never links the PostgreSQL server or a C++ database client. Startup verifies sqlite3_threadsafe() and expected libpq/SQLite version ranges against the pinned build.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

| Lock ID | Version | License selection | Link profile |
| --- | --- | --- | --- |
| libpq | 18.7 | PostgreSQL | static-runtime-library |
| openssl | 3.5.9 | Apache-2.0 | static-runtime-library |
| sqlite | 3.54.1 | blessing | static-runtime-library |

Immutable commit/source IDs, artifact digests, notices and target recipes are authoritative in scaffold/policy/native-lock.json and docs/C_FFI_PINNING_MATRIX.md. A source digest check is not evidence that every target binary was built or audited.

### Flint C shim ABI

This stable Flint-facing header is compiled by the target C compiler against the selected upstream headers. Its opaque pointers are internal; the public D API exposes only checked handles.

```c
/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_SQL_ABI_H
#define FLINT_SQL_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_pg_connection flint_pg_connection;
typedef struct flint_sqlite_connection flint_sqlite_connection;
flint_pg_connection *flint_pg_connect_start(const char *connection_string);
int flint_pg_connect_poll(flint_pg_connection *connection, intptr_t *socket);
int flint_pg_send(flint_pg_connection *connection, const char *query,
                  size_t parameter_count, const char *const *values,
                  const int *lengths, const int *formats);
int flint_pg_consume(flint_pg_connection *connection);
int flint_pg_cancel_start(flint_pg_connection *connection);
int flint_pg_cancel_poll(flint_pg_connection *connection);
void flint_pg_close(flint_pg_connection *connection);
flint_sqlite_connection *flint_sqlite_open(const char *path, int flags);
void flint_sqlite_interrupt(flint_sqlite_connection *connection);
int flint_sqlite_close(flint_sqlite_connection *connection);
#ifdef __cplusplus
}
#endif
#endif
```

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
| bind_injection | Quote/comment/semicolon/embedded-NUL payloads remain data; queries never change structure. |
| value_nulls | NULL/empty text/empty blob/zero/false round-trip distinctly on both drivers. |
| pool_saturation | 16 active leases plus 256 waiters stays bounded; waiter 257 fails promptly and cancelled waiters leave the queue. |
| pg_cancel_drain | Cancel pg_sleep, then immediately reuse pool; no old result leaks into a new query and no aborted transaction remains. |
| sqlite_busy | Hold a write lock from another connection; cancellation/timeout returns without blocking a reactor heartbeat. |
| transaction_atomic | Two-step mutation with callback failure rolls back both steps; commit ambiguity is surfaced and never silently retried. |
| prepared_eviction | 129 distinct prepared statements evict one safely; execution after schema invalidation replans or reports a typed error. |
| row_lifetime | Save a Row handle past callback and query completion; generation checks reject it before reading C memory. |
| sql_bench | Run prepared SELECT and INSERT/transaction fixtures on loopback PostgreSQL and local SQLite; record queue wait/driver time separately. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :sql --compiler=dmd
dub test :sql --compiler=ldc2
python3 tools/gates.py --package sql --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [libpq asynchronous processing](https://www.postgresql.org/docs/current/libpq-async.html) — Nonblocking output and complete result draining are separate requirements.
- [SQLite WAL](https://www.sqlite.org/wal.html) — WAL concurrency and checkpoint/durability tradeoffs require explicit operational choices.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
